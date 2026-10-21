import AppIntents
import Foundation

/// A jar as Shortcuts sees it, so an NFC automation can say "Open Jar: Adderall IR".
struct JarEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Jar"
    static var defaultQuery = JarQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct JarQuery: EntityQuery {
    func entities(for identifiers: [JarEntity.ID]) async throws -> [JarEntity] {
        StoreIO.load().jars.filter { identifiers.contains($0.id) }.map { JarEntity(id: $0.id, name: $0.name) }
    }

    func suggestedEntities() async throws -> [JarEntity] {
        StoreIO.load().jars.map { JarEntity(id: $0.id, name: $0.name) }
    }
}

struct OpenJarIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Jar"
    static var description = IntentDescription("Opens a jar's dose card in Med Jars.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Jar")
    var jar: JarEntity

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        Router.shared.open(jarId: jar.id)
        return .result()
    }
}

/// For NFC automations: opens the jar with the log sheet up, so the amount can be checked before logging.
struct OpenLogSheetIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Dose and Choose Amount"
    static var description = IntentDescription("Opens the jar with the log sheet ready, set to your usual amount, so you can change it before logging.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Jar")
    var jar: JarEntity

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        let store = AppStore.shared
        store.reload()
        Router.shared.open(jarId: jar.id)
        if let j = store.jar(jar.id) {
            let suggested = store.suggestion(for: j)?.slot
            Router.shared.logRequest = LogTarget(jarId: j.id, slotId: suggested?.id ?? j.asNeededSlot?.id ?? "", slot: suggested)
        }
        return .result()
    }
}

struct LogNextDoseIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Next Dose"
    static var description = IntentDescription("Logs the jar's next scheduled dose right now, without opening the app.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Jar")
    var jar: JarEntity

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = AppStore.shared
        store.reload()
        guard let j = store.jar(jar.id) else {
            return .result(dialog: "That jar isn't in Med Jars anymore.")
        }
        guard j.isActive() else {
            return .result(dialog: IntentDialog(stringLiteral: "\(j.name) is \(j.paused ? "paused" : "on a break"), so nothing was logged."))
        }
        if j.asNeeded, let slot = j.asNeededSlot {
            let warnings = store.logWarnings(jar: j, slot: slot)
            if !warnings.isEmpty {
                return .result(dialog: IntentDialog(stringLiteral: "Not logged. " + warnings.joined(separator: " ") + " Open Med Jars to log it anyway."))
            }
            guard let entry = store.log(jarId: j.id, slot: slot, amount: slot.amount, pills: slot.pills, at: Date()) else {
                return .result(dialog: "Couldn't log that dose.")
            }
            // Runs without opening the app, which can stop as soon as this returns: save now.
            store.flush()
            return .result(dialog: IntentDialog(stringLiteral: "Logged \(entry.amount.isEmpty ? j.name : "\(entry.amount) of \(j.name)") at \(Format.time12(entry.takenAt))."))
        }
        // Only a dose that's due now or was missed in the last 3 hours. Never an early one.
        guard let slot = DoseLogic.dueSlot(for: j, entries: store.entries, planned: store.planned) else {
            if let next = DoseLogic.nextDose(jars: [j], entries: store.entries, planned: store.planned) {
                let when = DoseLogic.sameDoseDay(next.time, Date()) ? "at" : "\(next.time.formatted(.dateTime.weekday(.wide))) at"
                return .result(dialog: IntentDialog(stringLiteral: "Nothing is due right now. Your next \(j.name) dose is \(when) \(Format.time12(next.time))."))
            }
            return .result(dialog: IntentDialog(stringLiteral: "Every \(j.name) dose is already logged today."))
        }
        let interactionWarnings = store.logWarnings(jar: j, slot: slot).filter { $0.contains("Interaction") }
        if interactionWarnings.contains(where: { $0.hasPrefix("Major") }) {
            return .result(dialog: IntentDialog(stringLiteral: "Not logged. " + interactionWarnings.joined(separator: " ") + " Open Med Jars to log it anyway."))
        }
        guard let entry = store.log(jarId: j.id, slot: slot, amount: slot.amount, pills: slot.pills, at: Date()) else {
            return .result(dialog: "Couldn't log that dose.")
        }
        store.flush()
        let what = entry.amount.isEmpty ? j.name : "\(entry.amount) of \(j.name)"
        var reply = "Logged \(what) at \(Format.time12(entry.takenAt))."
        if !interactionWarnings.isEmpty { reply += " Heads up: " + interactionWarnings.joined(separator: " ") }
        return .result(dialog: IntentDialog(stringLiteral: reply))
    }
}

/// Siri: "Did I take my Magnesium in Med Jars?"
struct DoseStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Did I Take It?"
    static var description = IntentDescription("Tells you whether you've logged a jar today and what's still due.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Jar")
    var jar: JarEntity

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = AppStore.shared
        store.reload()
        guard let j = store.jar(jar.id) else { return .result(dialog: "That jar isn't in Med Jars anymore.") }
        let cal = Calendar.current
        let today = DoseLogic.entriesToday(for: j.id, entries: store.entries).filter { !$0.skipped }.sorted { $0.takenAt < $1.takenAt }
        _ = cal
        let rows = DoseLogic.rows(for: j, entries: store.entries, planned: store.planned)
        let left = rows.filter { $0.slot.minutes != nil && !$0.status.isHandled }
        var parts: [String] = []
        if today.isEmpty {
            parts.append("No, you haven't logged \(j.name) today.")
        } else if today.count == 1, let e = today.first {
            parts.append("Yes. You took \(e.amount.isEmpty ? j.name : "\(e.amount) of \(j.name)") at \(Format.time12(e.takenAt)).")
        } else {
            parts.append("Yes. You've logged \(j.name) \(today.count) times today, at " + today.map { Format.time12($0.takenAt) }.joined(separator: ", ") + ".")
        }
        if let next = left.first {
            parts.append("Your \(next.slot.timeText) dose is still \(next.status == .missed ? "not logged" : "to come").")
        } else if !rows.isEmpty && !today.isEmpty {
            parts.append("That's every scheduled dose for today.")
        }
        return .result(dialog: IntentDialog(stringLiteral: parts.joined(separator: " ")))
    }
}

/// Siri: "What's left today in Med Jars?"
struct TodayDosesIntent: AppIntent {
    static var title: LocalizedStringResource = "Doses Left Today"
    static var description = IntentDescription("Lists the doses you still need to take today.")
    static var openAppWhenRun: Bool = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = AppStore.shared
        store.reload()
        var left: [(Int, String)] = []
        for jar in store.jars {
            for row in DoseLogic.rows(for: jar, entries: store.entries, planned: store.planned) where row.at != nil && !row.status.isHandled {
                left.append((DoseLogic.order(row.slot.minutes ?? 0), "\(jar.name) at \(row.slot.timeText)"))
            }
        }
        left.sort { $0.0 < $1.0 }
        let counts = DoseLogic.todayCounts(jars: store.jars, entries: store.entries, planned: store.planned)
        if counts.total == 0 { return .result(dialog: "You don't have any scheduled doses.") }
        if left.isEmpty { return .result(dialog: "You're done. All \(counts.total) doses are logged today.") }
        let list = left.map(\.1).joined(separator: ", ")
        return .result(dialog: IntentDialog(stringLiteral: "\(left.count) left today: \(list)."))
    }
}

/// For Shortcuts and automations: Discreet Mode on, off, back to its schedule, or flipped.
enum DiscreetChoice: String, AppEnum {
    case on, off, scheduled, toggle

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Discreet Mode"
    static var caseDisplayRepresentations: [DiscreetChoice: DisplayRepresentation] = [
        .on: "On",
        .off: "Off",
        .scheduled: "On a Schedule",
        .toggle: "Toggle"
    ]
}

/// Runs quietly in the background, so an automation can switch Discreet Mode without opening the app.
struct SetDiscreetModeIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Discreet Mode"
    static var description = IntentDescription("Turns Discreet Mode on or off, puts it back on its schedule, or flips it. Discreet Mode hides the name, icon and words in the Live Activity and Dynamic Island.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Discreet Mode", default: .on)
    var mode: DiscreetChoice

    static var parameterSummary: some ParameterSummary {
        Summary("Set Discreet Mode to \(\.$mode)")
    }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        let store = AppStore.shared
        store.reload()
        var d = store.discreet
        switch mode {
        case .on: d.mode = .on
        case .off: d.mode = .off
        case .scheduled: d.mode = .scheduled
        case .toggle: d.mode = d.isOn() ? .off : .on
        }
        store.setDiscreet(d)
        store.flush()
        await LiveDoses.lastSync?.value
        return .result()
    }
}

struct MedJarsShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: DoseStatusIntent(), phrases: [
            "Did I take my \(\.$jar) in \(.applicationName)",
            "Did I take \(\.$jar) in \(.applicationName)",
            "Did I take my \(\.$jar) today in \(.applicationName)",
            "Check \(\.$jar) in \(.applicationName)",
            "Did I take my meds in \(.applicationName)"
        ], shortTitle: "Did I Take It?", systemImageName: "questionmark.circle")
        AppShortcut(intent: TodayDosesIntent(), phrases: [
            "What's left today in \(.applicationName)",
            "What doses are left in \(.applicationName)",
            "What do I still need to take in \(.applicationName)"
        ], shortTitle: "Doses Left Today", systemImageName: "list.bullet.clipboard")
        AppShortcut(intent: OpenJarIntent(), phrases: ["Open a jar in \(.applicationName)"],
                    shortTitle: "Open Jar", systemImageName: "pills")
        AppShortcut(intent: LogNextDoseIntent(), phrases: ["Log a dose in \(.applicationName)"],
                    shortTitle: "Log Next Dose", systemImageName: "checkmark.circle")
        AppShortcut(intent: SetDiscreetModeIntent(), phrases: [
            "Set \(.applicationName) discreet mode to \(\.$mode)",
            "Discreet mode \(\.$mode) in \(.applicationName)"
        ], shortTitle: "Discreet Mode", systemImageName: "eye.slash")
    }
}
