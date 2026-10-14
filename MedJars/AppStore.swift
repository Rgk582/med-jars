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
    /// One-time planned doses, soonest first.
    private(set) var planned: [PlannedDose] = []
    /// Wake-up times seen in Apple Health, by dose day key.
    private(set) var wakeTimes: [String: Date] = [:]
    var isLocked: Bool = false
    var saveError: String?

    private init() {
        let file = StoreIO.load()
        jars = file.jars.sorted(by: Self.jarOrder)
        entries = file.entries.sorted { $0.takenAt > $1.takenAt }
        settings = file.settings
        caffeine = file.caffeine.sorted { $0.at > $1.at }
        planned = file.planned.sorted { $0.at < $1.at }
        wakeTimes = file.wakeTimes
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

    var bedtimeMinutes: Int { settings.bedtime ?? Bedtime.defaultMinutes }
    var usualWakeMinutes: Int { settings.usualWake ?? WakeTimes.defaultMinutes }

    /// Where doses taken upon waking sit in the Schedule until today's wake-up is seen.
    func setUsualWake(_ minutes: Int) {
        settings.usualWake = minutes
        WakeTimes.usualMinutes = minutes
        persist()
    }

    /// True when any active jar has a dose taken upon waking.
    var hasWakingDoses: Bool {
        jars.contains { jar in !jar.asNeeded && jar.plans.contains { $0.doses.contains { $0.uponWaking } } }
    }

    func wakeTime(on day: Date) -> Date? { wakeTimes[WakeTimes.key(day)] }

    /// A wake-up seen in Apple Health. The first one each day sends the reminder for that day's doses taken upon waking.
    func recordWake(_ woke: Date) {
        let key = WakeTimes.key(woke)
        guard wakeTimes[key] == nil else { return }
        wakeTimes[key] = woke
        let cutoff = WakeTimes.key(Date().addingTimeInterval(-21 * 86400))
        wakeTimes = wakeTimes.filter { $0.key >= cutoff }
        WakeTimes.byDay = wakeTimes
        persist()
        remindWakingDoses(woke: woke)
    }

    private func remindWakingDoses(woke: Date) {
        guard settings.reminders else { return }
        let dayStart = DoseLogic.doseDayStart(for: woke)
        var due: [(Jar, DoseSlot)] = []
        for jar in jars where jar.isActive(on: dayStart) {
            for slot in jar.slots(onDayStarting: dayStart) where slot.uponWaking {
                let done = entries.contains { $0.jarId == jar.id && $0.slotId == slot.id && DoseLogic.sameDoseDay($0.takenAt, woke) }
                if !done { due.append((jar, slot)) }
            }
        }
        guard !due.isEmpty else { return }
        if due.count == 1, let first = due.first {
            let (jar, slot) = first
            let amount = slot.amountLine(jar.form)
            Notify.post(id: Notify.doseId(jar: jar.id, slot: slot.id, day: woke), title: "Good morning. Time for \(jar.name)",
                        body: amount.isEmpty ? "Your dose to take upon waking." : "\(amount), upon waking.",
                        category: Notify.doseCategory, userInfo: ["jarId": jar.id, "slotId": slot.id], timeSensitive: true)
        } else {
            let list = due.map { pair -> String in
                let (jar, slot) = pair
                let amount = slot.amountLine(jar.form)
                return amount.isEmpty ? jar.name : "\(jar.name) \(amount)"
            }.joined(separator: ", ")
            Notify.post(id: "\(Notify.groupPrefix)waking.\(WakeTimes.key(woke))", title: "Good morning. \(due.count) doses upon waking",
                        body: list, category: Notify.groupCategory,
                        userInfo: ["items": due.map { "\($0.0.id)|\($0.1.id)" }.joined(separator: ";")], timeSensitive: true)
        }
        // Keep reminding for jars that ask to, until each dose is logged.
        for (jar, slot) in due where jar.nudge {
            for n in 1...min(Notify.maxNudges, max(1, jar.nudgeRepeats)) {
                Notify.post(id: Notify.nudgeId(jar: jar.id, slot: slot.id, day: woke, n: n), title: "Did you take \(jar.name)?",
                            body: "Your dose upon waking. Tap Log Dose if you took it.", category: Notify.doseCategory,
                            userInfo: ["jarId": jar.id, "slotId": slot.id], delay: Double(n * max(5, jar.nudgeMinutes) * 60), timeSensitive: true)
            }
        }
    }

    // MARK: Day plans

    /// Saves a change for one date, replacing any change already made for that day.
    func saveDatePlan(jarId: String, _ plan: DosePlan) {
        guard let i = jars.firstIndex(where: { $0.id == jarId }), let date = plan.date else { return }
        jars[i].plans.removeAll { $0.date.map { DoseLogic.sameDoseDay($0, date) } ?? false }
        jars[i].plans.append(plan)
        persist()
    }

    /// Goes back to the regular plan on a date.
    func removeDatePlan(jarId: String, on day: Date) {
        guard let i = jars.firstIndex(where: { $0.id == jarId }) else { return }
        jars[i].plans.removeAll { $0.date.map { DoseLogic.sameDoseDay($0, day) } ?? false }
        persist()
    }

    /// Moves every dose timed "before bed" along with it.
    func setBedtime(_ minutes: Int) {
        settings.bedtime = minutes
        Bedtime.minutes = minutes
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
            j.plans = [DosePlan(days: DoseSlot.everyDay, dailyPills: 1, splitEqual: true,
                                doses: [DoseSlot(label: "Morning", time: "08:00", amount: "", pills: 1, share: 1)])]
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
        planned.removeAll { $0.jarId == id }
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
                if !j.schedule.isEmpty || !j.plans.isEmpty {
                    existing.schedule = j.schedule
                    existing.plans = j.plans
                    existing.asNeeded = j.asNeeded
                }
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

    private var file: StoreFile {
        StoreFile(jars: jars, entries: entries, settings: settings, caffeine: caffeine, planned: planned, wakeTimes: wakeTimes)
    }

    private func adopt(_ f: StoreFile) {
        jars = f.jars.sorted(by: Self.jarOrder)
        entries = f.entries
        caffeine = f.caffeine.sorted { $0.at > $1.at }
        planned = f.planned.sorted { $0.at < $1.at }
        wakeTimes = f.wakeTimes
    }

    /// A jar's dose time or planned dose by id.
    func slot(jarId: String, slotId: String) -> DoseSlot? { file.slot(jarId: jarId, slotId: slotId) }

    // MARK: Planned doses

    func savePlanned(_ dose: PlannedDose) {
        planned.removeAll { $0.id == dose.id }
        planned.append(dose)
        planned.sort { $0.at < $1.at }
        persist()
    }

    func deletePlanned(_ id: String) {
        planned.removeAll { $0.id == id }
        persist()
    }

    func plannedDose(slotId: String) -> PlannedDose? { planned.first { $0.slotId == slotId } }

    /// Planned doses for a jar that are still ahead or from the last few hours and not logged or skipped.
    func upcomingPlanned(for jarId: String, now: Date = Date()) -> [PlannedDose] {
        planned.filter { p in
            p.jarId == jarId && p.at > now.addingTimeInterval(-3 * 3600) && !entries.contains { $0.slotId == p.slotId }
        }
    }

    /// Times a jar was taken (not skipped) in the last `days` days.
    func usageCount(jarId: String, days: Int, now: Date = Date()) -> Int {
        let since = now.addingTimeInterval(-Double(days) * 86400)
        return entries.filter { $0.jarId == jarId && !$0.skipped && $0.takenAt >= since }.count
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

    /// Logs a scheduled or planned dose right now. Returns nil if it was already handled.
    @discardableResult
    func logSlot(jarId: String, slotId: String, at date: Date = Date()) -> DoseEntry? {
        guard self.jar(jarId) != nil, let slot = self.slot(jarId: jarId, slotId: slotId) else { return nil }
        if slot.isPlanned, entries.contains(where: { $0.slotId == slotId }) { return nil }
        if alreadyLogged(jarId: jarId, slotId: slotId, on: date) != nil { return nil }
        return log(jarId: jarId, slot: slot, amount: slot.amount, pills: slot.pills, at: date)
    }

    /// Logs every listed dose that isn't handled yet (the Log All button on a grouped reminder).
    func logAll(_ items: [(jarId: String, slotId: String)]) {
        for item in items { logSlot(jarId: item.jarId, slotId: item.slotId) }
    }

    /// The scheduled dose that's due now (or missed in the last 3 hours) across all jars.
    func dueDose() -> (Jar, DoseSlot)? { file.dueDose() }

    /// Saves changes to a logged dose. Pills left in the jar follow the new pill count.
    func updateEntry(_ updated: DoseEntry) {
        var f = file
        guard let old = f.removeLog(updated.id) else { return }
        var e = updated
        e.checkIn = old.checkIn
        let low = f.applyLog(e)
        adopt(f)
        persist()
        if let low { Notify.lowSupply(low) }
    }

    /// A timed dose already taken or skipped in the same dose day. As-needed doses never count as duplicates.
    func alreadyLogged(jarId: String, slotId: String?, on day: Date) -> DoseEntry? {
        guard let slotId, let jar = jar(jarId), !jar.asNeeded,
              let slot = jar.timedSlots.first(where: { $0.id == slotId }), slot.minutes != nil else { return nil }
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
        Bedtime.minutes = f.settings.bedtime ?? Bedtime.defaultMinutes
        WakeTimes.usualMinutes = f.settings.usualWake ?? WakeTimes.defaultMinutes
        WakeTimes.byDay = f.wakeTimes
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
        planned = f.planned.sorted { $0.at < $1.at }
        wakeTimes = f.wakeTimes
        settings.bedtime = f.settings.bedtime ?? settings.bedtime
        settings.usualWake = f.settings.usualWake ?? settings.usualWake
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
        Reminders.reschedule(jars: jars, entries: entries, planned: planned, enabled: settings.reminders, grouped: groupRemindersOn)
        MedJarsShortcuts.updateAppShortcutParameters()
        LiveDoses.sync(jars: jars, entries: entries)
        backupNow()
    }
}
