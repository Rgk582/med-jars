import Foundation
import Observation
import WidgetKit
import SwiftUI

@MainActor
@Observable
final class AppStore {
    static let shared = AppStore()

    private(set) var jars: [Jar] = []
    private(set) var entries: [DoseEntry] = []
    private(set) var settings: AppSettings = AppSettings()
    private(set) var caffeine: [CaffeineEntry] = []
    var isLocked: Bool = false
    var saveError: String?

    private init() {
        let file = StoreIO.load()
        jars = file.jars.sorted(by: Self.jarOrder)
        entries = file.entries.sorted { $0.takenAt > $1.takenAt }
        settings = file.settings
        caffeine = file.caffeine.sorted { $0.at > $1.at }
        isLocked = file.settings.faceIDLock
        if let copy = StoreIO.unreadableCopy {
            saveError = "Your saved data couldn't be read, so a copy was kept as \(copy.lastPathComponent). Restore from a backup in Settings."
        }
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

    var accentColor: Color { AccentChoice.color(for: settings.accent) }

    var caffeineTrackerOn: Bool { settings.caffeineTracker ?? true }
    var groupRemindersOn: Bool { settings.groupReminders ?? true }

    func setCaffeineTracker(_ on: Bool) {
        settings.caffeineTracker = on
        persist()
    }

    func setGroupReminders(_ on: Bool) {
        settings.groupReminders = on
        persist()
    }

    /// A preset id like "blue", a hex code, or nil for the default orange.
    func setAccent(_ value: String?) {
        settings.accent = value
        persist()
    }

    func jar(_ id: String) -> Jar? { jars.first { $0.id == id } }

    func lastEntry(for jarId: String) -> DoseEntry? { entries.first { $0.jarId == jarId } }

    /// The most recent dose actually taken (not skipped).
    func lastTaken(for jarId: String) -> DoseEntry? { entries.first { $0.jarId == jarId && !$0.skipped } }

    /// The newest dose of this jar whose effect is still running, if the jar has an effect timeline.
    func activeEffectDose(for jar: Jar, now: Date = Date()) -> DoseEntry? {
        guard let effect = jar.effect?.normalized, let last = lastTaken(for: jar.id) else { return nil }
        let end = last.takenAt.addingTimeInterval(Double(effect.durationMinutes) * 60)
        return now < end && now >= last.takenAt ? last : nil
    }

    func interactions(for jarId: String) -> [(Jar, InteractionLevel)] { file.interactions(for: jarId) }

    func logWarnings(jar: Jar, slot: DoseSlot?, at date: Date = Date()) -> [String] {
        file.logWarnings(jar: jar, slot: slot, at: date)
    }

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

    /// Adds a jar for each Health medication that isn't in the cabinet yet. Returns how many were added.
    func addFromHealth(_ found: [HealthImport.Found]) -> Int {
        let names = Set(jars.map { $0.name.lowercased() })
        var added = 0
        for med in found where !names.contains(med.name.lowercased()) && jar(med.id) == nil {
            var j = Jar(id: med.id, name: med.name)
            j.labelName = med.nickname ?? ""
            j.kind = .rx
            j.form = .tablet
            j.schedule = [DoseSlot(label: "Morning", time: "08:00", amount: "1 dose", pills: 1)]
            j.order = (jars.map(\.order).max() ?? 0) + 1
            jars.append(j)
            added += 1
        }
        guard added > 0 else { return 0 }
        jars.sort(by: Self.jarOrder)
        persist()
        return added
    }

    func deleteJar(_ id: String) {
        jars.removeAll { $0.id == id }
        for i in jars.indices { jars[i].interactions.removeAll { $0.jarId == id } }
        persist()
    }

    /// Sets how a jar interacts with others, on both jars so the warning shows from either side.
    func setInteractions(for jarId: String, _ levels: [String: InteractionLevel]) {
        guard let me = jars.firstIndex(where: { $0.id == jarId }) else { return }
        jars[me].interactions = levels.map { JarInteraction(jarId: $0.key, level: $0.value) }.sorted { $0.jarId < $1.jarId }
        for i in jars.indices where i != me {
            jars[i].interactions.removeAll { $0.jarId == jarId }
            if let level = levels[jars[i].id] { jars[i].interactions.append(JarInteraction(jarId: jarId, level: level)) }
        }
        persist()
    }

    func setPaused(_ jarId: String, _ paused: Bool) {
        guard let i = jars.firstIndex(where: { $0.id == jarId }) else { return }
        jars[i].paused = paused
        persist()
    }

    /// A break between two days (inclusive). Pass nil to clear it.
    func setBreak(_ jarId: String, from: Date?, until: Date?) {
        guard let i = jars.firstIndex(where: { $0.id == jarId }) else { return }
        if let from, let until {
            jars[i].breakFrom = min(from, until)
            jars[i].breakUntil = max(from, until)
        } else {
            jars[i].breakFrom = nil
            jars[i].breakUntil = nil
        }
        persist()
    }

    func isIdTaken(_ id: String) -> Bool { jars.contains { $0.id == id } }

    // MARK: NFC tags

    /// Finds the jar for a scanned tag: a paired tag ID first, then a link written on the tag
    /// (medjars://jar/<id>, or any link ending in #<id> or /<id>, like the web cabinet's).
    func jar(forTag tag: ScannedTag) -> Jar? {
        if let j = jars.first(where: { $0.tagIds.contains(tag.uid) }) { return j }
        guard let url = tag.url else { return nil }
        var candidates: [String] = []
        if url.scheme?.lowercased() == "medjars", let id = url.pathComponents.dropFirst().first { candidates.append(id) }
        if let fragment = url.fragment { candidates.append(fragment) }
        candidates.append(url.lastPathComponent)
        for c in candidates {
            let id = Format.slug(c)
            if let j = jars.first(where: { $0.id == id }) { return j }
        }
        return nil
    }

    func pair(tagUID uid: String, toJar jarId: String) {
        guard !uid.isEmpty else { return }
        for i in jars.indices { jars[i].tagIds.removeAll { $0 == uid } }
        if let i = jars.firstIndex(where: { $0.id == jarId }) { jars[i].tagIds.append(uid) }
        persist()
    }

    func unpairTags(jarId: String) {
        if let i = jars.firstIndex(where: { $0.id == jarId }) { jars[i].tagIds = [] }
        persist()
    }

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
            if var existing = jar(j.id) {
                // Update the card's content but keep tags, supply, order, settings and history links.
                existing.name = j.name
                if !j.labelName.isEmpty { existing.labelName = j.labelName }
                existing.kind = j.kind
                existing.form = j.form
                if !j.strength.isEmpty { existing.strength = j.strength }
                if !j.schedule.isEmpty { existing.schedule = j.schedule; existing.asNeeded = j.asNeeded }
                if !j.howTo.isEmpty { existing.howTo = j.howTo }
                existing.food = j.food
                if !j.avoid.isEmpty { existing.avoid = j.avoid }
                if !j.absorb.isEmpty { existing.absorb = j.absorb }
                if !j.summary.isEmpty { existing.summary = j.summary }
                if j.effect != nil { existing.effect = j.effect }
                if j.pillsLeft != nil { existing.pillsLeft = j.pillsLeft }
                upsert(existing)
                updated += 1
            } else {
                upsert(j)
                added += 1
            }
        }
        return "Imported \(added) new and updated \(updated) existing jar\(added + updated == 1 ? "" : "s")."
    }

    // MARK: Logging

    private var file: StoreFile { StoreFile(jars: jars, entries: entries, settings: settings, caffeine: caffeine) }

    private func adopt(_ f: StoreFile) {
        jars = f.jars.sorted(by: Self.jarOrder)
        entries = f.entries
        caffeine = f.caffeine.sorted { $0.at > $1.at }
    }

    /// A dose logged from outside the jar page (Control Center, a link) that the jar page should confirm.
    var recentLog: DoseEntry?

    @discardableResult
    func log(jarId: String, slot: DoseSlot?, amount: String, pills: Double?, at date: Date, note: String = "") -> DoseEntry? {
        guard let jar = self.jar(jarId) else { return nil }
        var f = file
        let entry = f.makeEntry(jar: jar, slot: slot, amount: amount, pills: pills, at: date, note: note)
        let low = f.applyLog(entry)
        adopt(f)
        persist()
        Notify.afterLog(entry, jar: jar, lowSupply: low)
        return entry
    }

    /// Records a dose as skipped, with an optional reason. Clears its reminders; doesn't touch supply.
    @discardableResult
    func skip(jarId: String, slot: DoseSlot?, reason: String, at date: Date = Date()) -> DoseEntry? {
        guard let jar = self.jar(jarId) else { return nil }
        var f = file
        let entry = f.makeEntry(jar: jar, slot: slot, amount: slot?.amount ?? "", pills: nil, at: date, note: reason, skipped: true)
        f.applyLog(entry)
        adopt(f)
        persist()
        Notify.afterLog(entry, jar: jar, lowSupply: nil)
        return entry
    }

    /// Logs a scheduled dose right now. Returns nil if a timed dose was already handled today.
    @discardableResult
    func logSlot(jarId: String, slotId: String, at date: Date = Date()) -> DoseEntry? {
        guard let jar = self.jar(jarId), let slot = jar.sortedSchedule.first(where: { $0.id == slotId }) else { return nil }
        if alreadyLogged(jarId: jarId, slotId: slotId, on: date) != nil { return nil }
        return log(jarId: jarId, slot: slot, amount: slot.amount, pills: slot.pills, at: date)
    }

    /// Logs every listed dose that isn't handled yet (the Log All button on a grouped reminder).
    func logAll(_ items: [(jarId: String, slotId: String)]) {
        for item in items { logSlot(jarId: item.jarId, slotId: item.slotId) }
    }

    /// Logs whichever scheduled dose is due now across all jars.
    @discardableResult
    func logDueDose() -> DoseEntry? {
        reload()
        guard let due = file.dueDose() else { return nil }
        let entry = log(jarId: due.0.id, slot: due.1, amount: due.1.amount, pills: due.1.pills, at: Date())
        recentLog = entry
        return entry
    }

    /// A timed dose already taken or skipped in the same dose day. As-needed doses never count as duplicates.
    func alreadyLogged(jarId: String, slotId: String?, on day: Date) -> DoseEntry? {
        guard let slotId, let jar = jar(jarId), !jar.asNeeded,
              let slot = jar.schedule.first(where: { $0.id == slotId }), slot.minutes != nil else { return nil }
        return entries.first { $0.jarId == jarId && $0.slotId == slotId && DoseLogic.sameDoseDay($0.takenAt, day) }
    }

    func deleteEntry(_ id: String) {
        var f = file
        _ = f.removeLog(id)
        adopt(f)
        Notify.cancel(entryId: id)
        persist()
    }

    func restore(_ entry: DoseEntry) {
        guard !entries.contains(where: { $0.id == entry.id }) else { return }
        var f = file
        _ = f.applyLog(entry)
        adopt(f)
        persist()
    }

    func entry(_ id: String) -> DoseEntry? { entries.first { $0.id == id } }

    // MARK: Check-ins

    func saveCheckIn(_ checkIn: CheckIn?, for entryId: String) {
        guard let i = entries.firstIndex(where: { $0.id == entryId }) else { return }
        entries[i].checkIn = checkIn
        Notify.cancelCheckIn(entryId: entryId)
        persist()
    }

    func checkIns(for jarId: String) -> [DoseEntry] {
        entries.filter { $0.jarId == jarId && $0.checkIn != nil }
    }

    // MARK: Caffeine

    func addCaffeine(mg: Double, label: String, at date: Date = Date()) {
        caffeine.insert(CaffeineEntry(mg: mg, label: label, at: date), at: 0)
        caffeine.sort { $0.at > $1.at }
        persist()
    }

    func deleteCaffeine(_ id: String) {
        caffeine.removeAll { $0.id == id }
        persist()
    }

    func caffeineInSystem(at now: Date = Date()) -> Double {
        caffeine.filter { now.timeIntervalSince($0.at) < 36 * 3600 }.reduce(0) { $0 + $1.remaining(at: now) }
    }

    func caffeineToday(at now: Date = Date()) -> Double {
        let start = DoseLogic.doseDayStart(for: now)
        return caffeine.filter { $0.at >= start && $0.at <= now }.reduce(0) { $0 + $1.mg }
    }

    // MARK: Supply

    /// Adds pills to a jar (a refill) or sets the count outright.
    func refill(jarId: String, add: Double? = nil, setTo: Double? = nil) {
        guard let i = jars.firstIndex(where: { $0.id == jarId }) else { return }
        if let setTo { jars[i].pillsLeft = max(0, setTo) }
        else if let add { jars[i].pillsLeft = max(0, (jars[i].pillsLeft ?? 0) + add) }
        if !jars[i].isLow { jars[i].lowNotified = false }
        persist()
    }

    // MARK: Backup

    var lastBackup: Date? {
        let t = UserDefaults.standard.double(forKey: "lastBackup")
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }
    private(set) var backupError: String?

    func backupData() -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var f = file
        f.settings.backupBookmark = nil
        return (try? encoder.encode(f)) ?? Data()
    }

    /// Replaces everything with a backup file's contents. Returns a message for the person.
    func restoreBackup(from data: Data) -> String {
        let decoder = JSONDecoder()
        var restored: StoreFile?
        for strategy in [JSONDecoder.DateDecodingStrategy.iso8601, .secondsSince1970] {
            decoder.dateDecodingStrategy = strategy
            if let f = try? decoder.decode(StoreFile.self, from: data) { restored = f; break }
        }
        guard var f = restored else { return "That file isn't a Med Jars backup." }
        f.settings.backupBookmark = settings.backupBookmark
        adopt(f)
        entries.sort { $0.takenAt > $1.takenAt }
        settings = f.settings
        saveError = nil
        persist()
        return "Restored \(jars.count) jar\(jars.count == 1 ? "" : "s") and \(entries.count) dose\(entries.count == 1 ? "" : "s")."
    }

    func setBackupFolder(_ url: URL?) {
        guard let url else {
            settings.backupBookmark = nil
            persist()
            return
        }
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        settings.backupBookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        persist()
    }

    var backupFolderName: String? {
        guard let data = settings.backupBookmark else { return nil }
        var stale = false
        return (try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale))?.lastPathComponent
    }

    func backupNow() {
        guard let data = settings.backupBookmark else { return }
        var stale = false
        guard let folder = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else {
            backupError = "Can't reach the backup folder. Choose it again in Settings."
            return
        }
        let ok = folder.startAccessingSecurityScopedResource()
        defer { if ok { folder.stopAccessingSecurityScopedResource() } }
        do {
            try backupData().write(to: folder.appendingPathComponent("Med Jars Backup.json"), options: .atomic)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastBackup")
            backupError = nil
        } catch {
            backupError = "Backup failed: \(error.localizedDescription)"
        }
    }

    var csv: String {
        func cell(_ s: String) -> String { s.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s }
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"
        var out = ["Date,Time,Jar,Type,Dose,Status,Amount,Pills,Note,Focus,Mood,Side effects"]
        for e in entries.reversed() {
            let c = e.checkIn
            out.append([df.string(from: e.takenAt), Format.time12(e.takenAt), e.jarName, e.kind.label, e.slotLabel,
                        e.skipped ? "Skipped" : "Taken", e.amount,
                        Format.number(e.pills), e.note, c.map { String($0.focus) } ?? "", c.map { String($0.mood) } ?? "",
                        c?.sideEffects.joined(separator: "; ") ?? ""].map(cell).joined(separator: ","))
        }
        return out.joined(separator: "\n")
    }

    // MARK: Saving

    func reload() {
        let f = StoreIO.load()
        jars = f.jars.sorted(by: Self.jarOrder)
        entries = f.entries.sorted { $0.takenAt > $1.takenAt }
        caffeine = f.caffeine.sorted { $0.at > $1.at }
    }

    private func persist() {
        do {
            try StoreIO.save(file)
            saveError = nil
        } catch {
            saveError = "Couldn't save: \(error.localizedDescription)"
        }
        WidgetCenter.shared.reloadAllTimelines()
        ControlCenter.shared.reloadAllControls()
        Reminders.reschedule(jars: jars, entries: entries, enabled: settings.reminders, grouped: groupRemindersOn)
        MedJarsShortcuts.updateAppShortcutParameters()
        LiveDoses.sync(jars: jars, entries: entries)
        backupNow()
    }
}
