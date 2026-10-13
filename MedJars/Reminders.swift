import Foundation
import UserNotifications

/// Local dose reminders. iOS keeps at most 64 pending notifications, so instead of repeating
/// alarms the app schedules the next upcoming doses (skipping ones already logged today)
/// and tops the queue up every time it opens or the log changes.
enum Reminders {
    static let category = "DOSE"
    static let logAction = "LOG_DOSE"
    static let idPrefix = "dose."
    private static let maxPending = 60

    static func registerCategories() {
        let log = UNNotificationAction(identifier: logAction, title: "Log dose", options: [.authenticationRequired])
        let cat = UNNotificationCategory(identifier: category, actions: [log], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([cat])
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
            let ours = pending.map(\.identifier).filter { $0.hasPrefix(Reminders.idPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: ours)
            guard enabled else { return }

            let cal = Calendar.current
            let now = Date()
            struct Occurrence { let jar: Jar; let slot: DoseSlot; let date: Date }
            var upcoming: [Occurrence] = []
            for dayOffset in 0..<8 {
                guard let day = cal.date(byAdding: .day, value: dayOffset, to: now) else { continue }
                for jar in jars {
                    for slot in jar.timedSlots {
                        guard let date = DoseLogic.date(for: slot, on: day), date > now else { continue }
                        if dayOffset == 0, entries.contains(where: { $0.jarId == jar.id && $0.slotId == slot.id && cal.isDate($0.takenAt, inSameDayAs: now) }) { continue }
                        upcoming.append(Occurrence(jar: jar, slot: slot, date: date))
                    }
                }
            }
            upcoming.sort { $0.date < $1.date }

            let df = DateFormatter(); df.dateFormat = "yyyyMMdd"
            for occ in upcoming.prefix(Reminders.maxPending) {
                let content = UNMutableNotificationContent()
                content.title = "\(occ.jar.name): \(occ.slot.amount.isEmpty ? "dose due" : occ.slot.amount)"
                let pills = Format.pills(occ.slot.pills, occ.jar.form)
                content.body = [occ.slot.displayLabel, pills].filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
                content.sound = .default
                content.categoryIdentifier = Reminders.category
                content.threadIdentifier = occ.jar.id
                content.userInfo = ["jarId": occ.jar.id, "slotId": occ.slot.id]
                let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: occ.date)
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                let id = "\(Reminders.idPrefix)\(occ.jar.id).\(occ.slot.id).\(df.string(from: occ.date))"
                center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
            }
        }
    }

    /// Removes any reminder for this dose still sitting in Notification Center.
    static func clearDelivered(jarId: String, slotId: String) {
        let center = UNUserNotificationCenter.current()
        let start = "\(Reminders.idPrefix)\(jarId).\(slotId)."
        center.getDeliveredNotifications { delivered in
            let ids = delivered.map(\.request.identifier).filter { $0.hasPrefix(start) }
            if !ids.isEmpty { center.removeDeliveredNotifications(withIdentifiers: ids) }
        }
    }
}
