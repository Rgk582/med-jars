import Foundation
import Observation
import WidgetKit

@MainActor
@Observable
final class AppStore {
    static let shared = AppStore()

    private(set) var jars: [Jar] = []
    private(set) var entries: [DoseEntry] = []
    private(set) var settings: AppSettings = AppSettings()
    var isLocked: Bool = false
    var saveError: String?

    private init() {
        let file = StoreIO.load()
        jars = file.jars.sorted(by: Self.jarOrder)
        entries = file.entries.sorted { $0.takenAt > $1.takenAt }
        settings = file.settings
        isLocked = file.settings.faceIDLock
    }

    private static func jarOrder(_ a: Jar, _ b: Jar) -> Bool {
        a.order != b.order ? a.order < b.order : a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
    }

    func setFaceIDLock(_ on: Bool) {
        settings.faceIDLock = on
        persist()
    }

    func setReminders(_ on: Bool) {
        settings.reminders = on
        persist()
    }

    func jar(_ id: String) -> Jar? { jars.first { $0.id == id } }

    func lastEntry(for jarId: String) -> DoseEntry? { entries.first { $0.jarId == jarId } }

    // MARK: Jars

    func upsert(_ jar: Jar) {
        var j = jar
        if let i = jars.firstIndex(where: { $0.id == j.id }) {
            jars[i] = j
        } else {
            j.order = (jars.map(\.order).max() ?? 0) + 1
            jars.append(j)
        }
        jars.sort(by: Self.jarOrder)
        persist()
    }

    func deleteJar(_ id: String) {
        jars.removeAll { $0.id == id }
        persist()
    }

    func isIdTaken(_ id: String) -> Bool { jars.contains { $0.id == id } }

    /// Imports jars from JSON: one jar object or an array of them (web cabinet format works).
    func importJars(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8), !trimmed.isEmpty else { return "Paste a jar first." }
        let decoder = JSONDecoder()
        var incoming: [Jar] = []
        if let many = try? decoder.decode([Jar].self, from: data) { incoming = many }
        else if let one = try? decoder.decode(Jar.self, from: data) { incoming = [one] }
        else { return "That text isn't a jar. Paste the whole block, including the braces." }
        var added = 0, updated = 0
        for j in incoming where !j.id.isEmpty {
            if isIdTaken(j.id) { updated += 1 } else { added += 1 }
            upsert(j)
        }
        return "Imported \(added) new and updated \(updated) existing jar\(added + updated == 1 ? "" : "s")."
    }

    // MARK: Logging

    @discardableResult
    func log(jarId: String, slot: DoseSlot?, amount: String, pills: Double?, at date: Date, note: String = "") -> DoseEntry? {
        guard let jar = self.jar(jarId) else { return nil }
        let entry = DoseEntry(jarId: jar.id, jarName: jar.name, kind: jar.kind, form: jar.form,
                              amount: amount, pills: pills, slotId: slot?.id,
                              slotLabel: slot?.displayLabel ?? "Extra", takenAt: date, note: note)
        entries.insert(entry, at: 0)
        entries.sort { $0.takenAt > $1.takenAt }
        persist()
        if let slot { Reminders.clearDelivered(jarId: jar.id, slotId: slot.id) }
        return entry
    }

    /// Logs a scheduled dose right now. Returns nil if it was already logged today.
    @discardableResult
    func logSlot(jarId: String, slotId: String, at date: Date = Date()) -> DoseEntry? {
        guard let jar = self.jar(jarId), let slot = jar.schedule.first(where: { $0.id == slotId }) else { return nil }
        if alreadyLogged(jarId: jarId, slotId: slotId, on: date) != nil { return nil }
        return log(jarId: jarId, slot: slot, amount: slot.amount, pills: slot.pills, at: date)
    }

    func alreadyLogged(jarId: String, slotId: String?, on day: Date) -> DoseEntry? {
        guard let slotId else { return nil }
        return entries.first { $0.jarId == jarId && $0.slotId == slotId && Calendar.current.isDate($0.takenAt, inSameDayAs: day) }
    }

    func deleteEntry(_ id: String) {
        entries.removeAll { $0.id == id }
        persist()
    }

    func restore(_ entry: DoseEntry) {
        guard !entries.contains(where: { $0.id == entry.id }) else { return }
        entries.append(entry)
        entries.sort { $0.takenAt > $1.takenAt }
        persist()
    }

    var csv: String {
        func cell(_ s: String) -> String { s.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s }
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        var out = ["Date,Time,Jar,Type,Dose,Amount,Pills,Note"]
        for e in entries.reversed() {
            out.append([df.string(from: e.takenAt), Format.time12(e.takenAt), e.jarName, e.kind.label, e.slotLabel, e.amount, Format.number(e.pills), e.note].map(cell).joined(separator: ","))
        }
        return out.joined(separator: "\n")
    }

    // MARK: Saving

    func reload() {
        let file = StoreIO.load()
        jars = file.jars.sorted(by: Self.jarOrder)
        entries = file.entries.sorted { $0.takenAt > $1.takenAt }
    }

    private func persist() {
        do {
            try StoreIO.save(StoreFile(jars: jars, entries: entries, settings: settings))
            saveError = nil
        } catch {
            saveError = "Couldn't save: \(error.localizedDescription)"
        }
        WidgetCenter.shared.reloadAllTimelines()
        Reminders.reschedule(jars: jars, entries: entries, enabled: settings.reminders)
    }
}
