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
    private(set) var stacks: [Stack] = []
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
        stacks = file.stacks.sorted { $0.order < $1.order }
        isLocked = file.settings.faceIDLock
        syncContext()
        if let copy = StoreIO.unreadableCopy {
            saveError = "Your saved data couldn't be read, so a copy was kept as \(copy.lastPathComponent). Restore from a backup in Settings."
        }
    }

    private static func jarOrder(_ a: Jar, _ b: Jar) -> Bool {
        a.order != b.order ? a.order < b.order : a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
    }

    /// Hands the current stacks, jars and settings to the shared schedule logic.
    private func syncContext() {
        StackLogic.stacks = stacks
        StackLogic.jars = jars
        settings.apply()
        WakeTimes.byDay = wakeTimes
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

    /// True when any active jar or stack has a dose taken upon waking.
    var hasWakingDoses: Bool {
        jars.contains { jar in
            !jar.asNeeded && (jar.plans + (jar.rule?.allPlans ?? [])).contains { $0.doses.contains { $0.uponWaking } }
        } || stacks.contains { s in s.isOn && s.members.contains { $0.rule.allSlots.contains { $0.uponWaking } } }
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
            let amount = jar.amountText(for: slot)
            Notify.post(id: Notify.doseId(jar: jar.id, slot: slot.id, day: woke), title: "Good morning. Time for \(jar.name)",
                        body: amount.isEmpty ? "Your dose to take upon waking." : "\(amount), upon waking.",
                        category: Notify.doseCategory, userInfo: ["jarId": jar.id, "slotId": slot.id], timeSensitive: true)
        } else {
            let list = due.map { pair -> String in
                let (jar, slot) = pair
                let amount = jar.amountText(for: slot)
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

    /// Bedtime on one dose day.
    func bedtime(on day: Date) -> Int { Bedtime.minutes(onDayStarting: DoseLogic.doseDayStart(for: day)) }

    /// Changes bedtime for one dose day only. Nil goes back to the regular bedtime.
    func setBedtime(on day: Date, minutes: Int?) {
        var map = settings.bedtimeByDate ?? [:]
        let key = WakeTimes.key(day)
        map[key] = minutes
        // Old one-day changes aren't needed.
        let cutoff = WakeTimes.key(Date().addingTimeInterval(-14 * 86400))
        map = map.filter { $0.key >= cutoff }
        settings.bedtimeByDate = map.isEmpty ? nil : map
        persist()
    }

    /// A regular bedtime for one weekday (1 is Sunday). Nil uses the everyday bedtime.
    func setWeekdayBedtime(_ weekday: Int, minutes: Int?) {
        var map = settings.bedtimeByWeekday ?? [:]
        map[String(weekday)] = minutes
        settings.bedtimeByWeekday = map.isEmpty ? nil : map
        persist()
    }

    var pickOrder: PickOrder { settings.pickOrder ?? .wholeFirst }

    func setPickOrder(_ order: PickOrder) {
        settings.pickOrder = order
        persist()
    }

    // MARK: Home

    var homeCards: [HomeCard] { HomeCard.normalized(settings.home) }

    func setHomeCards(_ cards: [HomeCard]) {
        settings.home = cards
        persist()
    }

    /// A preset id like "blue", a hex code, or nil for the default orange.
    func setAccent(_ value: String?) {
        settings.accent = value
        persist()
    }

    /// Discreet Mode for the Live Activity and Dynamic Island.
    var discreet: DiscreetSettings { settings.discreet ?? DiscreetSettings() }

    func setDiscreet(_ value: DiscreetSettings) {
        settings.discreet = value
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
        if j.bottles.isEmpty { j.bottles = [Bottle(id: j.id)]; j.defaultBottleId = j.id }
        if let i = jars.firstIndex(where: { $0.id == j.id }) {
            jars[i] = j
        } else {
            j.order = (jars.map(\.order).max() ?? 0) + 1
            jars.append(j)
        }
        // A tag belongs to one jar: take this substance's tags off anything else.
        let tags = Set(j.tagIds)
        if !tags.isEmpty {
            for i in jars.indices where jars[i].id != j.id {
                for b in jars[i].bottles.indices { jars[i].bottles[b].tagIds.removeAll { tags.contains($0) } }
            }
            for i in stacks.indices { stacks[i].tagIds.removeAll { tags.contains($0) } }
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
        for i in stacks.indices { stacks[i].members.removeAll { $0.jarId == id } }
        persist()
    }

    /// Moves a substance's jars, log and planned doses into another substance (for jars set up separately before
    /// a substance could have several), then removes it.
    func merge(_ sourceId: String, into targetId: String) {
        guard sourceId != targetId, let s = jars.firstIndex(where: { $0.id == sourceId }),
              let t = jars.firstIndex(where: { $0.id == targetId }) else { return }
        let source = jars[s]
        var target = jars[t]
        for var b in source.bottles {
            if target.bottles.contains(where: { $0.id == b.id }) { b.id = UUID().uuidString }
            target.bottles.append(b)
        }
        target.syncDoseMode()
        jars[t] = target
        let name = target.name
        for i in entries.indices where entries[i].jarId == sourceId {
            entries[i].jarId = targetId
            entries[i].jarName = name
            if entries[i].parts == nil, let p = entries[i].pills, let b = source.bottles.first {
                entries[i].parts = [BottlePart(bottleId: b.id, pills: p)]
            }
        }
        for i in planned.indices where planned[i].jarId == sourceId { planned[i].jarId = targetId }
        for i in stacks.indices {
            for m in stacks[i].members.indices where stacks[i].members[m].jarId == sourceId { stacks[i].members[m].jarId = targetId }
        }
        deleteJar(sourceId)
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

    func isIdTaken(_ id: String) -> Bool { jars.contains { $0.id == id || $0.bottles.contains { $0.id == id } } }

    // MARK: NFC tags

    /// Finds the jar for a scanned tag: a paired tag ID first, then a link written on the tag
    /// (medjars://jar/<id>, or any link ending in #<id> or /<id>, like the web cabinet's).
    func jar(forTag tag: ScannedTag) -> Jar? { find(tag: tag)?.0 }

    /// The substance and the exact jar a tag belongs to.
    func find(tag: ScannedTag) -> (Jar, Bottle)? {
        for j in jars {
            if let b = j.bottles.first(where: { $0.tagIds.contains(tag.uid) }) { return (j, b) }
        }
        guard let url = tag.url else { return nil }
        var candidates: [String] = []
        if url.scheme?.lowercased() == "medjars", let id = url.pathComponents.dropFirst().first { candidates.append(id) }
        if let fragment = url.fragment { candidates.append(fragment) }
        candidates.append(url.lastPathComponent)
        for c in candidates {
            let id = Format.slug(c)
            if let j = jars.first(where: { $0.id == id }) { return (j, j.defaultBottle) }
            for j in jars { if let b = j.bottles.first(where: { $0.id == id }) { return (j, b) } }
        }
        return nil
    }

    /// The stack a tag opens.
    func stack(forTag tag: ScannedTag) -> Stack? { stacks.first { $0.tagIds.contains(tag.uid) } }

    /// Pairs a tag with one jar (the default jar when none is given), moving it off anything else.
    func pair(tagUID uid: String, toJar jarId: String, bottleId: String? = nil) {
        guard !uid.isEmpty else { return }
        for i in jars.indices { for b in jars[i].bottles.indices { jars[i].bottles[b].tagIds.removeAll { $0 == uid } } }
        for i in stacks.indices { stacks[i].tagIds.removeAll { $0 == uid } }
        if let i = jars.firstIndex(where: { $0.id == jarId }) {
            let target = bottleId ?? jars[i].defaultBottleId
            if let b = jars[i].bottles.firstIndex(where: { $0.id == target }) { jars[i].bottles[b].tagIds.append(uid) }
            else if !jars[i].bottles.isEmpty { jars[i].bottles[0].tagIds.append(uid) }
        }
        persist()
    }

    func unpairTags(jarId: String, bottleId: String? = nil) {
        if let i = jars.firstIndex(where: { $0.id == jarId }) {
            for b in jars[i].bottles.indices where bottleId == nil || jars[i].bottles[b].id == bottleId { jars[i].bottles[b].tagIds = [] }
        }
        persist()
    }

    func pair(tagUID uid: String, toStack stackId: String) {
        guard !uid.isEmpty else { return }
        for i in jars.indices { for b in jars[i].bottles.indices { jars[i].bottles[b].tagIds.removeAll { $0 == uid } } }
        for i in stacks.indices { stacks[i].tagIds.removeAll { $0 == uid } }
        if let i = stacks.firstIndex(where: { $0.id == stackId }) { stacks[i].tagIds.append(uid) }
        persist()
    }

    func unpairTags(stackId: String) {
        if let i = stacks.firstIndex(where: { $0.id == stackId }) { stacks[i].tagIds = [] }
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
                if !j.strength.isEmpty { existing.defaultBottle.setStrength(text: j.strength) }
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
        StoreFile(jars: jars, entries: entries, settings: settings, caffeine: caffeine, planned: planned, wakeTimes: wakeTimes, stacks: stacks)
    }

    private func adopt(_ f: StoreFile) {
        jars = f.jars.sorted(by: Self.jarOrder)
        entries = f.entries
        caffeine = f.caffeine.sorted { $0.at > $1.at }
        planned = f.planned.sorted { $0.at < $1.at }
        wakeTimes = f.wakeTimes
        stacks = f.stacks.sorted { $0.order < $1.order }
        syncContext()
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
    func log(jarId: String, slot: DoseSlot?, amount: String, pills: Double?, parts: [BottlePart]? = nil, at date: Date,
             note: String = "", loggedLate: Bool = false) -> DoseEntry? {
        guard let jar = self.jar(jarId) else { return nil }
        var f = file
        var entry = f.makeEntry(jar: jar, slot: slot, amount: amount, pills: pills, parts: parts, at: date, note: note)
        entry.loggedLate = loggedLate
        let low = f.applyLog(entry)
        adopt(f)
        persist()
        Notify.afterLog(entry, jar: jar, lowSupply: low)
        return entry
    }

    /// Several doses logged together (Log All). Each keeps its own amount, jars and time.
    @discardableResult
    func logGroup(_ items: [GroupLogItem]) -> [DoseEntry] {
        var f = file
        var out: [(DoseEntry, Jar, LowSupply?)] = []
        for item in items {
            guard let jar = jars.first(where: { $0.id == item.jarId }) else { continue }
            let entry = f.makeEntry(jar: jar, slot: item.slot, amount: item.amount, pills: item.pills, parts: item.parts, at: item.at, note: item.note)
            let low = f.applyLog(entry)
            out.append((entry, jar, low))
        }
        adopt(f)
        persist()
        for (entry, jar, low) in out { Notify.afterLog(entry, jar: jar, lowSupply: low) }
        return out.map { $0.0 }
    }

    /// Moves a logged dose to another time.
    func changeTime(entryId: String, to date: Date) {
        guard var e = entry(entryId) else { return }
        e.takenAt = date
        e.loggedLate = false
        updateEntry(e)
    }

    /// When a dose was meant to happen today.
    func scheduledTime(jarId: String, slotId: String, on day: Date = Date()) -> Date? {
        guard let jar = jar(jarId) else { return nil }
        if slotId.hasPrefix(PlannedDose.slotPrefix) { return planned.first { $0.slotId == slotId }?.at }
        return DoseLogic.rows(for: jar, entries: entries, planned: planned, dayStart: DoseLogic.doseDayStart(for: day), now: day)
            .first { $0.slot.id == slotId }?.at
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
    func logSlot(jarId: String, slotId: String, at date: Date = Date(), loggedLate: Bool = false) -> DoseEntry? {
        guard let jar = self.jar(jarId), let slot = self.slot(jarId: jarId, slotId: slotId) else { return nil }
        if slot.isPlanned, entries.contains(where: { $0.slotId == slotId }) { return nil }
        if alreadyLogged(jarId: jarId, slotId: slotId, on: date) != nil { return nil }
        return log(jarId: jarId, slot: slot, amount: jar.strengthText(for: slot), pills: slot.pills, at: date, loggedLate: loggedLate)
    }

    /// Log Dose on a notification. More than 2 hours after the dose time, it's logged at the dose time and a
    /// follow-up notification offers to change it to now.
    @discardableResult
    func logFromNotification(jarId: String, slotId: String) -> DoseEntry? {
        let now = Date()
        if let at = scheduledTime(jarId: jarId, slotId: slotId, on: now), now.timeIntervalSince(at) > 2 * 3600,
           let entry = logSlot(jarId: jarId, slotId: slotId, at: at, loggedLate: true) {
            Notify.loggedLate(entry, now: now)
            return entry
        }
        return logSlot(jarId: jarId, slotId: slotId, at: now)
    }

    /// Logs every listed dose that isn't handled yet (the Log All button on a grouped reminder).
    func logAll(_ items: [(jarId: String, slotId: String)]) {
        for item in items { logFromNotification(jarId: item.jarId, slotId: item.slotId) }
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
        guard let slotId, let jar = jar(jarId), let slot = jar.findSlot(slotId), slot.minutes != nil else { return nil }
        let row = DoseLogic.rows(for: jar, entries: entries, planned: planned, dayStart: DoseLogic.doseDayStart(for: day), now: Date())
            .first { $0.slot.id == slotId }
        switch row?.status {
        case .taken(let e), .skipped(let e): return e.skipReason == "The dose it follows wasn't taken" ? nil : e
        default: return nil
        }
    }

    /// The dose deleted last, for the Undo toast.
    var lastDeleted: DoseEntry?

    /// Deletes a dose and offers to undo it.
    func deleteEntry(_ id: String) {
        var f = file
        let old = f.removeLog(id)
        adopt(f)
        Notify.cancel(entryId: id)
        persist()
        lastDeleted = old
    }

    /// Takes back a dose just logged (the Undo on "Logged …"), without a second undo toast.
    func undoLog(_ id: String) {
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

    /// Adds pills to a jar (a refill) or sets the count outright. Without a jar id, the default jar.
    func refill(jarId: String, bottleId: String? = nil, add: Double? = nil, setTo: Double? = nil) {
        guard let i = jars.firstIndex(where: { $0.id == jarId }) else { return }
        let target = bottleId ?? jars[i].defaultBottleId
        guard let b = jars[i].bottles.firstIndex(where: { $0.id == target }) else { return }
        if let setTo { jars[i].bottles[b].pillsLeft = max(0, setTo) }
        else if let add { jars[i].bottles[b].pillsLeft = max(0, (jars[i].bottles[b].pillsLeft ?? 0) + add) }
        if !jars[i].isLow(jars[i].bottles[b]) { jars[i].bottles[b].lowNotified = false }
        persist()
    }

    // MARK: Stacks

    func stack(_ id: String) -> Stack? { stacks.first { $0.id == id } }

    func upsertStack(_ stack: Stack) {
        var s = stack
        if let i = stacks.firstIndex(where: { $0.id == s.id }) {
            stacks[i] = s
        } else {
            s.order = (stacks.map(\.order).max() ?? 0) + 1
            stacks.append(s)
        }
        persist()
    }

    func deleteStack(_ id: String) {
        stacks.removeAll { $0.id == id }
        for i in jars.indices where jars[i].stackOwner == id { jars[i].stackOwner = nil }
        persist()
    }

    /// Turns a stack on from a dose day. The first time sets its start. After being off, it picks up where it left
    /// off: the days it was off don't count, and its end moves back by them. `owners` picks which stack controls a
    /// substance two stacks share.
    func turnOn(stackId: String, from day: Date, owners: [String: String] = [:]) {
        guard let i = stacks.firstIndex(where: { $0.id == stackId }) else { return }
        let d = DoseLogic.doseDayStart(for: day)
        var s = stacks[i]
        if s.start == nil {
            s.start = d
            s.offSpans = []
            if let end = s.end, end < d { s.end = nil }
        } else if case .ended = StackLogic.day(s, d), let oldStart = s.start {
            // Run it again from the start, for the same length.
            if let end = s.end {
                let length = StackLogic.days(from: oldStart, to: end) - StackLogic.offDays(s, before: end)
                s.end = Calendar.current.date(byAdding: .day, value: max(0, length), to: d)
            }
            s.start = d
            s.offSpans = []
            s.restartAfterBreak = [:]
        } else if let last = s.offSpans.last, last.until == nil {
            let from = DoseLogic.doseDayStart(for: last.from)
            if d <= from {
                s.offSpans.removeLast()
            } else {
                s.offSpans[s.offSpans.count - 1].until = d
                if let end = s.end, d > from {
                    s.end = Calendar.current.date(byAdding: .day, value: StackLogic.days(from: from, to: d), to: end)
                }
            }
        }
        s.turnedOnAt = Date()
        stacks[i] = s
        for (jarId, owner) in owners {
            if let j = jars.firstIndex(where: { $0.id == jarId }) { jars[j].stackOwner = owner }
        }
        persist()
    }

    /// Turns a stack off from today. Its substances go back to their normal schedules.
    func turnOff(stackId: String) {
        guard let i = stacks.firstIndex(where: { $0.id == stackId }), stacks[i].isOn else { return }
        let today = DoseLogic.doseDayStart(for: Date())
        if let start = stacks[i].start, today < DoseLogic.doseDayStart(for: start), stacks[i].offSpans.isEmpty {
            // It hadn't started yet: back to never started.
            stacks[i].start = nil
        } else {
            stacks[i].offSpans.append(OffSpan(from: today, until: nil))
        }
        persist()
    }

    /// Restart rotations at week 1 after a break (true), or keep counting (false).
    func setRestart(stackId: String, cycle: Int, restart: Bool) {
        guard let i = stacks.firstIndex(where: { $0.id == stackId }) else { return }
        stacks[i].restartAfterBreak[String(cycle)] = restart
        persist()
    }

    /// Moves a stack's end date (extend or shorten).
    func setEnd(stackId: String, end: Date?) {
        guard let i = stacks.firstIndex(where: { $0.id == stackId }) else { return }
        stacks[i].end = end.map { DoseLogic.doseDayStart(for: $0) }
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
        syncContext()
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
        stacks = f.stacks.sorted { $0.order < $1.order }
        settings.bedtime = f.settings.bedtime ?? settings.bedtime
        settings.usualWake = f.settings.usualWake ?? settings.usualWake
        settings.bedtimeByDate = f.settings.bedtimeByDate ?? settings.bedtimeByDate
        settings.bedtimeByWeekday = f.settings.bedtimeByWeekday ?? settings.bedtimeByWeekday
        syncContext()
    }

    private func persist() {
        syncContext()
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
        LiveDoses.sync(jars: jars, entries: entries, discreet: settings.discreet)
        backupNow()
    }
}
