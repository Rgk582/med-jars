import Foundation
import UserNotifications

/// Dose reminders and missed-dose nudges. iOS keeps at most 64 pending notifications, so instead of
/// repeating alarms the app schedules the next upcoming ones (skipping doses already handled, paused
/// jars and breaks) and tops the queue up every time it opens or the log changes.
enum Reminders {
    /// Leaves room under iOS's limit of 64 for check-ins, wearing-off alerts and follow-ups.
    private static let pendingLimit = 60

    static func registerCategories() {
        let log = UNNotificationAction(identifier: Notify.logAction, title: "Log Dose", options: [.authenticationRequired])
        let custom = UNNotificationAction(identifier: Notify.logCustomAction, title: "Log a Different Amount", options: [.foreground])
        let skip = UNNotificationAction(identifier: Notify.skipAction, title: "Skip", options: [.authenticationRequired])
        let logAll = UNNotificationAction(identifier: Notify.logAllAction, title: "Log All", options: [.authenticationRequired])
        let changeNow = UNNotificationAction(identifier: Notify.changeToNowAction, title: "Change to Now", options: [.authenticationRequired])
        let restart = UNNotificationAction(identifier: Notify.restartAction, title: "Restart at Week 1", options: [.authenticationRequired])
        let keep = UNNotificationAction(identifier: Notify.keepCountingAction, title: "Keep Counting", options: [.authenticationRequired])
        let dose = UNNotificationCategory(identifier: Notify.doseCategory, actions: [log, custom, skip], intentIdentifiers: [], options: [])
        let group = UNNotificationCategory(identifier: Notify.groupCategory, actions: [logAll], intentIdentifiers: [], options: [])
        let checkIn = UNNotificationCategory(identifier: Notify.checkInCategory, actions: [], intentIdentifiers: [], options: [])
        let refill = UNNotificationCategory(identifier: Notify.refillCategory, actions: [], intentIdentifiers: [], options: [])
        let info = UNNotificationCategory(identifier: Notify.infoCategory, actions: [], intentIdentifiers: [], options: [])
        let late = UNNotificationCategory(identifier: Notify.loggedLateCategory, actions: [changeNow], intentIdentifiers: [], options: [])
        let resume = UNNotificationCategory(identifier: Notify.stackResumeCategory, actions: [restart, keep], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([dose, group, checkIn, refill, info, late, resume])
    }

    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let current = await center.notificationSettings()
        switch current.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .denied: return false
        default:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        }
    }

    private struct Item {
        let id: String
        let date: Date
        let content: UNMutableNotificationContent
    }

    private struct Due {
        let jar: Jar
        let slot: DoseSlot
        let at: Date
    }

    static func reschedule(jars: [Jar], entries: [DoseEntry], planned: [PlannedDose], enabled: Bool, grouped: Bool) {
        let stacks = StackLogic.stacks
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            let mine: (String) -> Bool = {
                $0.hasPrefix(Notify.dosePrefix) || $0.hasPrefix(Notify.nudgePrefix) || $0.hasPrefix(Notify.groupPrefix)
                    || $0.hasPrefix(Notify.headsUpPrefix) || $0.hasPrefix(Notify.stackPrefix)
            }
            let ours = pending.map(\.identifier).filter(mine)
            center.removePendingNotificationRequests(withIdentifiers: ours)
            let budget = max(8, pendingLimit - (pending.count - ours.count))

            let cal = Calendar.current
            let now = Date()
            let today = DoseLogic.doseDayStart(for: now)
            var onTime: [(Date, Due)] = []
            var items: [Item] = []

            for offset in 0..<8 {
                guard let dayStart = cal.date(byAdding: .day, value: offset, to: today) else { continue }
                for jar in jars where jar.isActive(on: dayStart) {
                    guard enabled || jar.nudge else { continue }
                    for row in DoseLogic.rows(for: jar, entries: entries, planned: [], dayStart: dayStart, now: now) {
                        guard let at = row.at, !row.isPlanned else { continue }
                        // Doses taken upon waking are reminded when Apple Health shows the wake-up, not at a clock time.
                        if row.slot.uponWaking { continue }
                        switch row.status {
                        case .taken, .skipped, .waiting: continue
                        default: break
                        }
                        if enabled && at > now { onTime.append((at, Due(jar: jar, slot: row.slot, at: at))) }
                        guard jar.nudge, !jar.kind.remindOnly else { continue }
                        let every = TimeInterval(max(5, jar.nudgeMinutes) * 60)
                        for n in 1...min(Notify.maxNudges, max(1, jar.nudgeRepeats)) {
                            let nudgeAt = at.addingTimeInterval(every * Double(n))
                            guard nudgeAt > now else { continue }
                            let c = UNMutableNotificationContent()
                            c.title = "Did you take \(jar.name)?"
                            let amount = jar.amountText(for: row.slot)
                            c.body = "\(amount.isEmpty ? "Your dose" : amount) was due at \(Format.time12(at)). Tap Log Dose if you took it."
                            c.sound = .default
                            c.interruptionLevel = .timeSensitive
                            c.categoryIdentifier = Notify.doseCategory
                            c.threadIdentifier = jar.id
                            c.userInfo = ["jarId": jar.id, "slotId": row.slot.id]
                            items.append(Item(id: Notify.nudgeId(jar: jar.id, slot: row.slot.id, day: at, n: n), date: nudgeAt, content: c))
                        }
                    }
                }
            }

            // Doses within 15 minutes of each other share one reminder at the earliest time.
            for (at, doses) in DoseLogic.groupTimes(onTime) {
                if grouped && doses.count > 1 {
                    let c = UNMutableNotificationContent()
                    c.title = "\(doses.count) doses due"
                    c.body = doses.map { d in
                        let amount = d.jar.amountText(for: d.slot)
                        return amount.isEmpty ? d.jar.name : "\(d.jar.name) \(amount)"
                    }.joined(separator: ", ")
                    c.sound = .default
                    c.interruptionLevel = .timeSensitive
                    c.categoryIdentifier = Notify.groupCategory
                    c.threadIdentifier = "group"
                    c.userInfo = ["items": doses.map { "\($0.jar.id)|\($0.slot.id)" }.joined(separator: ";")]
                    let f = DateFormatter(); f.dateFormat = "yyyyMMddHHmm"
                    items.append(Item(id: "\(Notify.groupPrefix)\(f.string(from: at))", date: at, content: c))
                } else {
                    for d in doses {
                        let c = UNMutableNotificationContent()
                        let strength = d.jar.strengthText(for: d.slot)
                        c.title = d.jar.kind.remindOnly ? "Reminder: \(d.jar.name)" : "\(d.jar.name): \(strength.isEmpty ? "dose due" : strength)"
                        c.body = [d.jar.labelName, d.slot.displayLabel, d.jar.usesStrength ? d.jar.partsText(d.jar.parts(for: d.slot)) : Format.pills(d.slot.pills, d.jar.form)]
                            .filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
                        c.sound = .default
                        c.interruptionLevel = .timeSensitive
                        c.categoryIdentifier = Notify.doseCategory
                        c.threadIdentifier = d.jar.id
                        c.userInfo = ["jarId": d.jar.id, "slotId": d.slot.id]
                        items.append(Item(id: Notify.doseId(jar: d.jar.id, slot: d.slot.id, day: d.at), date: d.at, content: c))
                    }
                }
            }

            // One-time planned doses: a reminder at the time and the heads-up before it.
            if enabled {
                for p in planned where p.at > now && p.at < now.addingTimeInterval(30 * 86400) {
                    guard let jar = jars.first(where: { $0.id == p.jarId }), jar.isActive(on: DoseLogic.doseDayStart(for: p.at)),
                          !entries.contains(where: { $0.slotId == p.slotId }) else { continue }
                    let slot = p.slot
                    let amount = jar.amountText(for: slot)
                    let c = UNMutableNotificationContent()
                    c.title = "\(jar.name): \(amount.isEmpty ? "planned dose" : amount)"
                    c.body = [p.note.isEmpty ? "Planned dose" : p.note, Format.time12(p.at)].joined(separator: " \u{00B7} ")
                    c.sound = .default
                    c.interruptionLevel = .timeSensitive
                    c.categoryIdentifier = Notify.doseCategory
                    c.threadIdentifier = jar.id
                    c.userInfo = ["jarId": jar.id, "slotId": slot.id]
                    items.append(Item(id: Notify.doseId(jar: jar.id, slot: slot.id, day: p.at), date: p.at, content: c))
                    if p.headsUpMinutes > 0 {
                        let at = p.at.addingTimeInterval(-Double(p.headsUpMinutes) * 60)
                        guard at > now else { continue }
                        let h = UNMutableNotificationContent()
                        h.title = "Coming up: \(jar.name)"
                        h.body = "\(p.note.isEmpty ? "Planned dose" : p.note) at \(Format.time12(p.at))\(Calendar.current.isDate(p.at, inSameDayAs: at) ? "" : " on " + p.at.formatted(.dateTime.weekday(.wide).month(.wide).day())). \(amount)"
                            .trimmingCharacters(in: .whitespaces)
                        h.sound = .default
                        h.interruptionLevel = .timeSensitive
                        h.categoryIdentifier = Notify.infoCategory
                        h.threadIdentifier = jar.id
                        h.userInfo = ["jarId": jar.id]
                        items.append(Item(id: "\(Notify.headsUpPrefix)\(slot.id)", date: at, content: h))
                    }
                }

                // Stacks: a heads-up at 8 PM the night before one starts, goes on a break or comes back, and on its last day.
                for s in stacks where s.isOn {
                    for change in StackLogic.changes(s, from: now, days: 8) {
                        let night: Date?
                        switch change.change {
                        case .lastDay: night = cal.date(bySettingHour: 20, minute: 0, second: 0, of: change.day)
                        default: night = cal.date(byAdding: .day, value: -1, to: change.day).flatMap { cal.date(bySettingHour: 20, minute: 0, second: 0, of: $0) }
                        }
                        guard let fire = night, fire > now else { continue }
                        let c = UNMutableNotificationContent()
                        let names = s.members.compactMap { m in jars.first { $0.id == m.jarId }?.name }.joined(separator: ", ")
                        var kind = "change"
                        switch change.change {
                        case .starts:
                            kind = "start"
                            c.title = "\(s.displayName) starts tomorrow"
                            c.body = names.isEmpty ? "Its schedule starts in the morning." : "Its schedule takes over for \(names) in the morning."
                            c.categoryIdentifier = Notify.infoCategory
                        case .lastDay:
                            kind = "end"
                            c.title = "Last day of \(s.displayName)"
                            c.body = "Your normal schedules start again tomorrow."
                            c.categoryIdentifier = Notify.infoCategory
                        case .breakStarts:
                            kind = "break"
                            c.title = "\(s.displayName) goes on a break tomorrow"
                            c.body = "Your normal schedules take over during the break."
                            c.categoryIdentifier = Notify.infoCategory
                        case .breakEnds(let cycle):
                            kind = "back\(cycle)"
                            c.title = "\(s.displayName) is back tomorrow"
                            c.body = "Restart its rotations at week 1, or keep counting from where they were? Hold this notification to choose."
                            c.categoryIdentifier = Notify.stackResumeCategory
                            c.userInfo = ["stackId": s.id, "cycle": String(cycle)]
                        }
                        c.sound = .default
                        c.threadIdentifier = "stack.\(s.id)"
                        if c.userInfo.isEmpty { c.userInfo = ["stackId": s.id] }
                        items.append(Item(id: "\(Notify.stackPrefix)\(s.id).\(kind).\(Notify.dayKey(change.day))", date: fire, content: c))
                    }
                }
            }

            items.sort { $0.date < $1.date }
            for item in items.prefix(budget) {
                let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: item.date)
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                center.add(UNNotificationRequest(identifier: item.id, content: item.content, trigger: trigger))
            }
        }
    }
}
