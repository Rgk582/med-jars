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
        let dose = UNNotificationCategory(identifier: Notify.doseCategory, actions: [log, custom, skip], intentIdentifiers: [], options: [])
        let group = UNNotificationCategory(identifier: Notify.groupCategory, actions: [logAll], intentIdentifiers: [], options: [])
        let checkIn = UNNotificationCategory(identifier: Notify.checkInCategory, actions: [], intentIdentifiers: [], options: [])
        let refill = UNNotificationCategory(identifier: Notify.refillCategory, actions: [], intentIdentifiers: [], options: [])
        let info = UNNotificationCategory(identifier: Notify.infoCategory, actions: [], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([dose, group, checkIn, refill, info])
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

    static func reschedule(jars: [Jar], entries: [DoseEntry], planned: [PlannedDose], enabled: Bool, grouped: Bool) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            let mine: (String) -> Bool = {
                $0.hasPrefix(Notify.dosePrefix) || $0.hasPrefix(Notify.nudgePrefix) || $0.hasPrefix(Notify.groupPrefix) || $0.hasPrefix(Notify.headsUpPrefix)
            }
            let ours = pending.map(\.identifier).filter(mine)
            center.removePendingNotificationRequests(withIdentifiers: ours)
            let budget = max(8, pendingLimit - (pending.count - ours.count))

            let cal = Calendar.current
            let now = Date()
            let today = DoseLogic.doseDayStart(for: now)
            var onTime: [Date: [(Jar, DoseSlot)]] = [:]
            var items: [Item] = []

            for offset in 0..<8 {
                guard let dayStart = cal.date(byAdding: .day, value: offset, to: today) else { continue }
                for jar in jars where jar.isActive(on: dayStart) && !jar.asNeeded {
                    guard enabled || jar.nudge else { continue }
                    // Doses taken upon waking are reminded when Apple Health shows the wake-up, not at a clock time.
                    for slot in jar.slots(onDayStarting: dayStart) where !slot.uponWaking {
                        guard let at = DoseLogic.occurrence(of: slot, dayStart: dayStart) else { continue }
                        if offset == 0, entries.contains(where: { $0.jarId == jar.id && $0.slotId == slot.id && DoseLogic.sameDoseDay($0.takenAt, now) }) { continue }
                        if enabled && at > now { onTime[at, default: []].append((jar, slot)) }
                        guard jar.nudge else { continue }
                        let every = TimeInterval(max(5, jar.nudgeMinutes) * 60)
                        for n in 1...min(Notify.maxNudges, max(1, jar.nudgeRepeats)) {
                            let nudgeAt = at.addingTimeInterval(every * Double(n))
                            guard nudgeAt > now else { continue }
                            let c = UNMutableNotificationContent()
                            c.title = "Did you take \(jar.name)?"
                            let amount = slot.amountLine(jar.form)
                            c.body = "\(amount.isEmpty ? "Your dose" : amount) was due at \(Format.time12(at)). Tap Log Dose if you took it."
                            c.sound = .default
                            c.interruptionLevel = .timeSensitive
                            c.categoryIdentifier = Notify.doseCategory
                            c.threadIdentifier = jar.id
                            c.userInfo = ["jarId": jar.id, "slotId": slot.id]
                            items.append(Item(id: Notify.nudgeId(jar: jar.id, slot: slot.id, day: at, n: n), date: nudgeAt, content: c))
                        }
                    }
                }
            }

            for (at, doses) in onTime {
                if grouped && doses.count > 1 {
                    let c = UNMutableNotificationContent()
                    c.title = "\(doses.count) doses due"
                    c.body = doses.map { jar, slot in
                        let amount = slot.amountLine(jar.form)
                        return amount.isEmpty ? jar.name : "\(jar.name) \(amount)"
                    }.joined(separator: ", ")
                    c.sound = .default
                    c.interruptionLevel = .timeSensitive
                    c.categoryIdentifier = Notify.groupCategory
                    c.threadIdentifier = "group"
                    c.userInfo = ["items": doses.map { "\($0.0.id)|\($0.1.id)" }.joined(separator: ";")]
                    let f = DateFormatter(); f.dateFormat = "yyyyMMddHHmm"
                    items.append(Item(id: "\(Notify.groupPrefix)\(f.string(from: at))", date: at, content: c))
                } else {
                    for (jar, slot) in doses {
                        let c = UNMutableNotificationContent()
                        c.title = "\(jar.name): \(slot.amount.isEmpty ? "dose due" : slot.amount)"
                        c.body = [jar.labelName, slot.displayLabel, Format.pills(slot.pills, jar.form)].filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
                        c.sound = .default
                        c.interruptionLevel = .timeSensitive
                        c.categoryIdentifier = Notify.doseCategory
                        c.threadIdentifier = jar.id
                        c.userInfo = ["jarId": jar.id, "slotId": slot.id]
                        items.append(Item(id: Notify.doseId(jar: jar.id, slot: slot.id, day: at), date: at, content: c))
                    }
                }
            }

            // One-time planned doses: a reminder at the time and the heads-up before it.
            if enabled {
                for p in planned where p.at > now && p.at < now.addingTimeInterval(30 * 86400) {
                    guard let jar = jars.first(where: { $0.id == p.jarId }), jar.isActive(on: DoseLogic.doseDayStart(for: p.at)),
                          !entries.contains(where: { $0.slotId == p.slotId }) else { continue }
                    let slot = p.slot
                    let amount = slot.amountLine(jar.form)
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
