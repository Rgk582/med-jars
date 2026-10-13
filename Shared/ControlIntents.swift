import AppIntents
import WidgetKit
import Foundation

/// Control Center: logs the dose that's due now without opening the app.
/// Runs in the widget extension, so it needs the App Group to reach the app's data.
struct LogDueDoseIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Due Dose"
    static var description = IntentDescription("Logs whichever scheduled dose is due right now.")
    static var isDiscoverable: Bool = false
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        guard StoreIO.isShared else {
            Notify.post(title: "Couldn't log from Control Center",
                        body: "Your certificate doesn't let Control Center reach Med Jars' data. Use the Open and Log control instead.")
            return .result()
        }
        var file = StoreIO.load()
        guard let due = file.dueDose() else {
            let next = DoseLogic.nextDose(jars: file.jars, entries: file.entries)
            Notify.post(title: "Nothing due right now",
                        body: next.map { "Next up: \($0.jar.name) at \(Format.time12($0.time))." } ?? "No more doses scheduled.")
            return .result()
        }
        let (jar, slot) = due
        let now = Date()
        let entry = file.makeEntry(jar: jar, slot: slot, amount: slot.amount, pills: slot.pills, at: now)
        let low = file.applyLog(entry)
        try StoreIO.save(file)
        Notify.clear(jar: jar.id, slot: slot.id, day: now)
        Notify.post(id: "logged.\(entry.id)", title: "Logged \(jar.name)",
                    body: "\(slot.amountLine(jar.form).ifEmptyText("Dose")) at \(Format.time12(now)).")
        if let low { Notify.lowSupply(low) }
        if jar.checkIn { Notify.scheduleCheckIn(for: entry, after: jar.checkInMinutes) }
        WidgetCenter.shared.reloadAllTimelines()
        ControlCenter.shared.reloadAllControls()
        return .result()
    }
}

/// Control Center: opens Med Jars and logs the dose that's due. Works with any certificate.
struct OpenAndLogIntent: AppIntent {
    static var title: LocalizedStringResource = "Open and Log Dose"
    static var description = IntentDescription("Opens Med Jars and logs the dose that's due now.")
    static var isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "medjars://log-next")!))
    }
}
