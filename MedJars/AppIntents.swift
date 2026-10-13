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
        let rows = DoseLogic.rows(for: j, entries: store.entries)
        guard let next = DoseLogic.suggestion(rows) else {
            return .result(dialog: "Every \(j.name) dose is already logged today.")
        }
        guard let entry = store.log(jarId: j.id, slot: next.slot, amount: next.slot.amount, pills: next.slot.pills, at: Date()) else {
            return .result(dialog: "Couldn't log that dose.")
        }
        let what = entry.amount.isEmpty ? j.name : "\(entry.amount) of \(j.name)"
        return .result(dialog: "Logged \(what) at \(Format.time12(entry.takenAt)).")
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
        let today = store.entries.filter { $0.jarId == j.id && cal.isDateInToday($0.takenAt) }.sorted { $0.takenAt < $1.takenAt }
        let rows = DoseLogic.rows(for: j, entries: store.entries)
        let left = rows.filter { $0.slot.minutes != nil && !$0.status.isTaken }
        var parts: [String] = []
        if today.isEmpty {
            parts.append("No, you haven't logged \(j.name) today.")
        } else if today.count == 1, let e = today.first {
            parts.append("Yes. You took \(e.amount.isEmpty ? j.name : "\(e.amount) of \(j.name)") at \(Format.time12(e.takenAt)).")
        } else {
            parts.append("Yes. You've logged \(j.name) \(today.count) times today, at " + today.map { Format.time12($0.takenAt) }.joined(separator: ", ") + ".")
        }
        if let next = left.first {
            parts.append("Your \(Format.time12(next.slot.time)) dose is still \(next.status == .missed ? "not logged" : "to come").")
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
            for row in DoseLogic.rows(for: jar, entries: store.entries) where row.slot.minutes != nil && !row.status.isTaken {
                left.append((row.slot.minutes ?? 0, "\(jar.name) at \(Format.time12(row.slot.time))"))
            }
        }
        left.sort { $0.0 < $1.0 }
        let counts = DoseLogic.todayCounts(jars: store.jars, entries: store.entries)
        if counts.total == 0 { return .result(dialog: "You don't have any scheduled doses.") }
        if left.isEmpty { return .result(dialog: "You're done. All \(counts.total) doses are logged today.") }
        let list = left.map(\.1).joined(separator: ", ")
        return .result(dialog: IntentDialog(stringLiteral: "\(left.count) left today: \(list)."))
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
    }
}
