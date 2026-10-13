import Foundation
import UserNotifications

/// Notification identifiers and one-off alerts, shared by the app and the widget extension.
enum Notify {
    static let doseCategory = "DOSE"
    static let groupCategory = "DOSE_GROUP"
    static let checkInCategory = "CHECKIN"
    static let refillCategory = "REFILL"
    static let infoCategory = "INFO"
    static let logAction = "LOG_DOSE"
    static let logCustomAction = "LOG_CUSTOM"
    static let skipAction = "SKIP_DOSE"
    static let logAllAction = "LOG_ALL"
    static let dosePrefix = "dose."
    static let nudgePrefix = "nudge."
    static let groupPrefix = "dosegroup."
    static let checkInPrefix = "checkin."
    static let effectPrefix = "effect."
    static let followUpPrefix = "followup."
    static let headsUpPrefix = "headsup."
    static let maxNudges = 10

    /// Key for the dose day a date falls in (4 AM to 4 AM).
    static func dayKey(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd"
        return f.string(from: DoseLogic.doseDayStart(for: date))
    }

    static func doseId(jar: String, slot: String, day: Date) -> String { "\(dosePrefix)\(jar).\(slot).\(dayKey(day))" }
    static func nudgeId(jar: String, slot: String, day: Date, n: Int) -> String { "\(nudgePrefix)\(jar).\(slot).\(dayKey(day)).\(n)" }

    /// Drops a dose's reminder and every nudge for that dose day, pending or already delivered.
    static func clear(jar: String, slot: String, day: Date) {
        var ids = [doseId(jar: jar, slot: slot, day: day)]
        ids += (1...maxNudges).map { nudgeId(jar: jar, slot: slot, day: day, n: $0) }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    /// Shows an alert after `delay` seconds.
    static func post(id: String = UUID().uuidString, title: String, body: String, category: String? = nil,
                     userInfo: [String: String] = [:], delay: TimeInterval = 1, timeSensitive: Bool = false) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let category { content.categoryIdentifier = category }
        content.userInfo = userInfo
        if timeSensitive { content.interruptionLevel = .timeSensitive }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, delay), repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    static func lowSupply(_ jar: Jar) {
        let left = Format.pills(jar.pillsLeft, jar.form).ifEmptyText("No \(jar.form.plural)")
        let days = jar.daysLeft.map { $0 == 1 ? "about 1 day" : "about \($0) days" } ?? "not much"
        post(id: "refill.\(jar.id)", title: "Refill \(jar.name) soon",
             body: "\(left) left, \(days) of doses.", category: refillCategory, userInfo: ["jarId": jar.id])
    }

    /// Everything that follows a logged dose: clear its reminders, refill warning, check-in,
    /// wearing-off alert and as-needed follow-up. Used by the app, Siri, widgets and Control Center.
    static func afterLog(_ entry: DoseEntry, jar: Jar, lowSupply low: Jar?) {
        if let slot = entry.slotId {
            clear(jar: jar.id, slot: slot, day: entry.takenAt)
            if slot.hasPrefix(PlannedDose.slotPrefix) {
                let ids = ["\(headsUpPrefix)\(slot)"]
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
                UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
            }
        }
        if entry.skipped { return }
        if let low { lowSupply(low) }
        let sinceDose = Date().timeIntervalSince(entry.takenAt)
        if jar.checkIn && sinceDose < 3 * 3600 {
            post(id: "\(checkInPrefix)\(entry.id)", title: "How are you feeling?",
                 body: "Check in on your \(entry.jarName) dose from \(Format.time12(entry.takenAt)).",
                 category: checkInCategory, userInfo: ["entryId": entry.id, "jarId": entry.jarId],
                 delay: max(1, Double(jar.checkInMinutes) * 60 - sinceDose))
        }
        if let effect = jar.effect?.normalized, effect.wearOffAlert {
            let end = Double(effect.durationMinutes) * 60 - sinceDose
            if end > 0 {
                post(id: "\(effectPrefix)\(entry.id)", title: "\(jar.name) is wearing off",
                     body: "Your \(Format.time12(entry.takenAt)) dose has reached its \(Format.duration(effect.durationMinutes)) effective duration.",
                     category: infoCategory, userInfo: ["jarId": jar.id], delay: end)
            }
        }
        if jar.asNeeded && jar.followUpMinutes > 0 {
            let at = Double(jar.followUpMinutes) * 60 - sinceDose
            if at > 0 {
                post(id: "\(followUpPrefix)\(entry.id)", title: jar.name,
                     body: "It's been \(Format.duration(jar.followUpMinutes)) since your \(Format.time12(entry.takenAt)) dose.",
                     category: infoCategory, userInfo: ["jarId": jar.id], delay: at)
            }
        }
    }

    /// Cancels the alerts tied to one logged dose (when it's deleted).
    static func cancel(entryId: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [
            "\(checkInPrefix)\(entryId)", "\(effectPrefix)\(entryId)", "\(followUpPrefix)\(entryId)"
        ])
    }

    static func cancelCheckIn(entryId: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["\(checkInPrefix)\(entryId)"])
    }
}

extension String {
    func ifEmptyText(_ fallback: String) -> String { isEmpty ? fallback : self }
}
