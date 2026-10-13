import Foundation
import UserNotifications

/// Dose reminders and missed-dose nudges. iOS keeps at most 64 pending notifications, so instead of
/// repeating alarms the app schedules the next upcoming ones (skipping doses already logged today)
/// and tops the queue up every time it opens or the log changes.
enum Reminders {
    private static let maxPending = 56

    static func registerCategories() {
        let log = UNNotificationAction(identifier: Notify.logAction, title: "Log Dose", options: [.authenticationRequired])
        let dose = UNNotificationCategory(identifier: Notify.doseCategory, actions: [log], intentIdentifiers: [], options: [])
        let checkIn = UNNotificationCategory(identifier: Notify.checkInCategory, actions: [], intentIdentifiers: [], options: [])
        let refill = UNNotificationCategory(identifier: Notify.refillCategory, actions: [], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([dose, checkIn, refill])
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

    static func reschedule(jars: [Jar], entries: [DoseEntry], enabled: Bool) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            let ours = pending.map(\.identifier).filter { $0.hasPrefix(Notify.dosePrefix) || $0.hasPrefix(Notify.nudgePrefix) }
            center.removePendingNotificationRequests(withIdentifiers: ours)

            let cal = Calendar.current
            let now = Date()
            struct Item { let id: String; let date: Date; let content: UNMutableNotificationContent }
            var items: [Item] = []
            for dayOffset in 0..<8 {
                guard let day = cal.date(byAdding: .day, value: dayOffset, to: now) else { continue }
                for jar in jars {
                    let wantsNudge = jar.nudge
                    guard enabled || wantsNudge else { continue }
                    for slot in jar.timedSlots {
                        guard let at = DoseLogic.date(for: slot, on: day) else { continue }
                        if dayOffset == 0, entries.contains(where: { $0.jarId == jar.id && $0.slotId == slot.id && cal.isDate($0.takenAt, inSameDayAs: now) }) { continue }
                        let info = ["jarId": jar.id, "slotId": slot.id]
                        let amount = slot.amountLine(jar.form)
                        if enabled && at > now {
                            let c = UNMutableNotificationContent()
                            c.title = "\(jar.name): \(slot.amount.isEmpty ? "dose due" : slot.amount)"
                            c.body = [slot.displayLabel, Format.pills(slot.pills, jar.form)].filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
                            c.sound = .default
                            c.categoryIdentifier = Notify.doseCategory
                            c.threadIdentifier = jar.id
                            c.userInfo = info
                            items.append(Item(id: Notify.doseId(jar: jar.id, slot: slot.id, day: day), date: at, content: c))
                        }
                        if wantsNudge {
                            let nudgeAt = at.addingTimeInterval(TimeInterval(max(5, jar.nudgeMinutes) * 60))
                            if nudgeAt > now {
                                let c = UNMutableNotificationContent()
                                c.title = "Did you take \(jar.name)?"
                                c.body = "\(amount.isEmpty ? "Your dose" : amount) was due at \(Format.time12(slot.time)). Tap Log Dose if you took it."
                                c.sound = .default
                                c.categoryIdentifier = Notify.doseCategory
                                c.threadIdentifier = jar.id
                                c.userInfo = info
                                items.append(Item(id: Notify.nudgeId(jar: jar.id, slot: slot.id, day: day), date: nudgeAt, content: c))
                            }
                        }
                    }
                }
            }
            items.sort { $0.date < $1.date }
            for item in items.prefix(maxPending) {
                let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: item.date)
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                center.add(UNNotificationRequest(identifier: item.id, content: item.content, trigger: trigger))
            }
        }
    }
}

