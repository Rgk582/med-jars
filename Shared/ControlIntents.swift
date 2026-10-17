import AppIntents
import WidgetKit
import Foundation

/// Logging from outside the app (widget button, Control Center). Needs the App Group to reach the app's data.
enum ExtensionLog {
    static let noAccessMessage = "Your certificate doesn't let widgets and Control Center reach Med Jars' data. Use the Open and Log control instead."

    @discardableResult
    static func log(jarId: String, slotId: String?, at now: Date = Date()) -> DoseEntry? {
        var file = StoreIO.load()
        guard let jar = file.jars.first(where: { $0.id == jarId }), jar.isActive(on: now) else { return nil }
        let slot = slotId.flatMap { file.slot(jarId: jarId, slotId: $0) } ?? jar.asNeededSlot
        if let slot, slot.isPlanned, file.entries.contains(where: { $0.slotId == slot.id }) { return nil }
        if let slot, slot.minutes != nil, !slot.isPlanned,
           file.entries.contains(where: { $0.jarId == jar.id && $0.slotId == slot.id && DoseLogic.sameDoseDay($0.takenAt, now) }) {
            return nil
        }
        let entry = file.makeEntry(jar: jar, slot: slot, amount: jar.strengthText(for: slot), pills: slot?.pills, at: now)
        let low = file.applyLog(entry)
        guard (try? StoreIO.save(file)) != nil else { return nil }
        Notify.afterLog(entry, jar: jar, lowSupply: low)
        Notify.post(id: "logged.\(entry.id)", title: "Logged \(jar.name)",
                    body: "\(jar.amountText(for: slot).ifEmptyText("Dose")) at \(Format.time12(now)).")
        WidgetCenter.shared.reloadAllTimelines()
        ControlCenter.shared.reloadAllControls()
        return entry
    }
}

/// Control Center: logs the dose that's due now without opening the app.
struct LogDueDoseIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Due Dose"
    static var description = IntentDescription("Logs whichever scheduled dose is due right now.")
    static var isDiscoverable: Bool = false
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        guard StoreIO.isShared else {
            Notify.post(title: "Couldn't log from Control Center", body: ExtensionLog.noAccessMessage)
            return .result()
        }
        let file = StoreIO.load()
        guard let due = file.dueDose() else {
            let next = DoseLogic.nextDose(jars: file.jars, entries: file.entries, planned: file.planned)
            Notify.post(title: "Nothing due right now",
                        body: next.map { "Next up: \($0.jar.name) at \(Format.time12($0.time))." } ?? "No more doses scheduled.")
            return .result()
        }
        ExtensionLog.log(jarId: due.0.id, slotId: due.1.id)
        return .result()
    }
}

/// Widget button: logs one specific dose.
struct LogSlotIntent: AppIntent {
    static var title: LocalizedStringResource = "Log This Dose"
    static var isDiscoverable: Bool = false
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Jar") var jarId: String
    @Parameter(title: "Dose") var slotId: String

    init() {}
    init(jarId: String, slotId: String) {
        self.jarId = jarId
        self.slotId = slotId
    }

    func perform() async throws -> some IntentResult {
        guard StoreIO.isShared else {
            Notify.post(title: "Couldn't log from the widget", body: ExtensionLog.noAccessMessage)
            return .result()
        }
        ExtensionLog.log(jarId: jarId, slotId: slotId.isEmpty ? nil : slotId)
        return .result()
    }
}

/// Control Center: opens Med Jars to the dose that's due, ready to confirm the amount. Works with any certificate.
struct OpenAndLogIntent: AppIntent {
    static var title: LocalizedStringResource = "Open and Log Dose"
    static var description = IntentDescription("Opens Med Jars to the dose that's due now so you can confirm how much and log it.")
    static var isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "medjars://log-next")!))
    }
}

/// The text under the Control Center button: what's due next.
struct NextDoseControlValue: ControlValueProvider {
    var previewValue: String { "Next Dose" }

    func currentValue() async throws -> String {
        guard StoreIO.isShared else { return "Log Dose" }
        let file = StoreIO.load()
        if let due = file.dueDose() { return "\(due.0.name) now" }
        guard let next = DoseLogic.nextDose(jars: file.jars, entries: file.entries, planned: file.planned) else { return "Log Dose" }
        return "\(next.jar.name), \(Format.time12(next.time))"
    }
}
