import Foundation
import UserNotifications

/// Notification identifiers and one-off alerts, shared by the app and the widget extension.
enum Notify {
    static let doseCategory = "DOSE"
    static let checkInCategory = "CHECKIN"
    static let refillCategory = "REFILL"
    static let logAction = "LOG_DOSE"
    static let dosePrefix = "dose."
    static let nudgePrefix = "nudge."
    static let checkInPrefix = "checkin."

    static func dayKey(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd"
        return f.string(from: date)
    }

    static func doseId(jar: String, slot: String, day: Date) -> String { "\(dosePrefix)\(jar).\(slot).\(dayKey(day))" }
    static func nudgeId(jar: String, slot: String, day: Date) -> String { "\(nudgePrefix)\(jar).\(slot).\(dayKey(day))" }

    /// Drops today's reminder and nudge for a dose once it's logged, pending or already delivered.
    static func clear(jar: String, slot: String, day: Date) {
        let ids = [doseId(jar: jar, slot: slot, day: day), nudgeId(jar: jar, slot: slot, day: day)]
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    /// Shows an alert right away (or after `delay` seconds).
    static func post(id: String = UUID().uuidString, title: String, body: String, category: String? = nil,
                     userInfo: [String: String] = [:], delay: TimeInterval = 1) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let category { content.categoryIdentifier = category }
        content.userInfo = userInfo
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, delay), repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    static func lowSupply(_ jar: Jar) {
        let left = Format.pills(jar.pillsLeft, jar.form).ifEmptyText("No \(jar.form.plural)")
        let days = jar.daysLeft.map { $0 == 1 ? "about 1 day" : "about \($0) days" } ?? "not much"
        post(id: "refill.\(jar.id)", title: "Refill \(jar.name) soon",
             body: "\(left) left, \(days) of doses.", category: refillCategory, userInfo: ["jarId": jar.id])
    }

    static func scheduleCheckIn(for entry: DoseEntry, after minutes: Int) {
        post(id: "\(checkInPrefix)\(entry.id)", title: "How are you feeling?",
             body: "Check in on your \(entry.jarName) dose from \(Format.time12(entry.takenAt)).",
             category: checkInCategory, userInfo: ["entryId": entry.id, "jarId": entry.jarId],
             delay: TimeInterval(max(1, minutes) * 60))
    }

    static func cancelCheckIn(entryId: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["\(checkInPrefix)\(entryId)"])
    }
}

extension String {
    func ifEmptyText(_ fallback: String) -> String { isEmpty ? fallback : self }
}
