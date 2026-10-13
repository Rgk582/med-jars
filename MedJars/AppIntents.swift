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

struct MedJarsShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OpenJarIntent(), phrases: ["Open a jar in \(.applicationName)"],
                    shortTitle: "Open Jar", systemImageName: "pills")
        AppShortcut(intent: LogNextDoseIntent(), phrases: ["Log a dose in \(.applicationName)"],
                    shortTitle: "Log Next Dose", systemImageName: "checkmark.circle")
    }
}
