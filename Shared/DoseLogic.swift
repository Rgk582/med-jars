import Foundation

enum SlotStatus: Equatable {
    case taken(DoseEntry)
    case skipped(DoseEntry)
    case due
    case later
    case missed
    case asNeeded
    /// A stack dose timed after another one that hasn't been logged yet.
    case waiting
    /// A recreational dose whose time passed without a log. It only reminds, so it never counts as missed.
    case reminder

    var isTaken: Bool { if case .taken = self { return true } else { return false } }
    /// Taken or deliberately skipped: nothing more to do for this dose.
    var isHandled: Bool {
        switch self {
        case .taken, .skipped: return true
        default: return false
        }
    }
}

struct SlotRow: Identifiable {
    let slot: DoseSlot
    let status: SlotStatus
    /// Minutes between the slot time and now (absolute); very large for untimed slots.
    let distance: Int
    /// When the dose happens, nil for as-needed.
    var at: Date? = nil
    var id: String { slot.id }
    var isPlanned: Bool { slot.isPlanned }
}

struct NextDose {
    let jar: Jar
    let slot: DoseSlot
    let time: Date
}

/// One dose on a day's schedule: a dose time (each part of a split dose is its own) or a planned dose.
struct DayItem: Identifiable {
    let jar: Jar
    let row: SlotRow
    var id: String { jar.id + "/" + row.slot.id }
}

/// A day's schedule: the timed and planned doses in order, and the jars that are as needed that day.
struct DaySchedule {
    let dayStart: Date
    let items: [DayItem]
    let asNeeded: [Jar]

    /// Doses that count toward the day's progress. Skipped doses, doses waiting on another one and
    /// recreational doses (reminders only) don't.
    var counted: [DayItem] {
        items.filter { item in
            if item.jar.kind.remindOnly { return false }
            switch item.row.status {
            case .skipped, .waiting, .reminder: return false
            default: return true
            }
        }
    }
    var taken: Int { counted.filter { $0.row.status.isTaken }.count }
    var total: Int { counted.count }
}

/// Where schedule math looks up logged and planned doses.
protocol DoseSource {
    /// A substance's doses logged in the dose day that starts at `dayStart`, in log order (newest first).
    func entries(jarId: String, dayStart: Date) -> [DoseEntry]
    /// Every dose of a substance logged against one dose id (a planned dose), in log order.
    func entries(jarId: String, slotId: String) -> [DoseEntry]
    /// A substance's planned doses on the dose day that starts at `dayStart`.
    func planned(jarId: String, dayStart: Date) -> [PlannedDose]
}

/// Looks things up by scanning the whole log each time. Fine for one substance.
struct ArrayDoseSource: DoseSource {
    let entries: [DoseEntry]
    let planned: [PlannedDose]

    func entries(jarId: String, dayStart: Date) -> [DoseEntry] {
        DoseLogic.entries(for: jarId, entries: entries, dayStart: dayStart)
    }

    func entries(jarId: String, slotId: String) -> [DoseEntry] {
        entries.filter { $0.jarId == jarId && $0.slotId == slotId }
    }

    func planned(jarId: String, dayStart: Date) -> [PlannedDose] {
        DoseLogic.planned(for: jarId, planned: planned, dayStart: dayStart)
    }
}

/// The log and planned doses grouped by substance once, so working out many schedules (every substance, several
/// days) doesn't scan the whole log for each one.
final class DoseIndex: DoseSource, @unchecked Sendable {
    private let byJar: [String: [DoseEntry]]
    private let plannedByJar: [String: [PlannedDose]]

    init(entries: [DoseEntry], planned: [PlannedDose]) {
        byJar = Dictionary(grouping: entries, by: \.jarId)
        plannedByJar = Dictionary(grouping: planned, by: \.jarId)
    }

    func entries(jarId: String, dayStart: Date) -> [DoseEntry] {
        guard let list = byJar[jarId] else { return [] }
        let end = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        return list.filter { $0.takenAt >= dayStart && $0.takenAt < end }
    }

    func entries(jarId: String, slotId: String) -> [DoseEntry] {
        (byJar[jarId] ?? []).filter { $0.slotId == slotId }
    }

    func planned(jarId: String, dayStart: Date) -> [PlannedDose] {
        guard let list = plannedByJar[jarId] else { return [] }
        let end = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        return list.filter { $0.at >= dayStart && $0.at < end }
    }
}

#if DEBUG
/// Test-only counters read by the perf harness.
enum DebugCounters {
    nonisolated(unsafe) static var rows = 0
}
#endif

enum DoseLogic {
    /// A "dose day" runs from 4 AM to 4 AM, so a 12:30 AM bedtime dose belongs to the evening before.
    static let dayStartHour = 4

    static func doseDayStart(for date: Date) -> Date {
        let cal = Calendar.current
        let today = cal.date(bySettingHour: dayStartHour, minute: 0, second: 0, of: date) ?? cal.startOfDay(for: date)
        return date >= today ? today : (cal.date(byAdding: .day, value: -1, to: today) ?? today)
    }

    static func doseDayEnd(for date: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: 1, to: doseDayStart(for: date)) ?? date
    }

    /// Sort key for a time of day inside a dose day (times before 4 AM come last).
    static func order(_ minutes: Int) -> Int {
        minutes < dayStartHour * 60 ? minutes + 24 * 60 : minutes
    }

    /// Doses within this many minutes of the first one in a group are due together.
    static let groupMinutes = 15

    /// When a slot happens within the dose day that starts at `dayStart`.
    static func occurrence(of slot: DoseSlot, dayStart: Date) -> Date? {
        if slot.uponWaking, slot.time != nil, let woke = WakeTimes.detected(onDayStarting: dayStart) { return woke }
        guard let m = slot.minutes(onDayStarting: dayStart) else { return nil }
        let cal = Calendar.current
        guard var d = cal.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: dayStart) else { return nil }
        if m < dayStartHour * 60, let next = cal.date(byAdding: .day, value: 1, to: d) { d = next }
        return d
    }

    /// Kept for callers that think in calendar days.
    static func date(for slot: DoseSlot, on day: Date) -> Date? {
        occurrence(of: slot, dayStart: doseDayStart(for: day))
    }

    static func sameDoseDay(_ a: Date, _ b: Date) -> Bool { doseDayStart(for: a) == doseDayStart(for: b) }

    static func entriesToday(for jarId: String, entries: [DoseEntry], now: Date = Date()) -> [DoseEntry] {
        Self.entries(for: jarId, entries: entries, dayStart: doseDayStart(for: now))
    }

    static func entries(for jarId: String, entries: [DoseEntry], dayStart: Date) -> [DoseEntry] {
        let end = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        return entries.filter { $0.jarId == jarId && $0.takenAt >= dayStart && $0.takenAt < end }
    }

    /// Planned doses for a jar on the dose day starting at `dayStart`.
    static func planned(for jarId: String, planned: [PlannedDose], dayStart: Date) -> [PlannedDose] {
        let end = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        return planned.filter { $0.jarId == jarId && $0.at >= dayStart && $0.at < end }
    }

    private static func status(at: Date, hit: DoseEntry?, now: Date) -> (SlotStatus, Int) {
        let diff = Int((at.timeIntervalSince(now) / 60).rounded())
        if let hit { return (hit.skipped ? .skipped(hit) : .taken(hit), abs(diff)) }
        if diff > 45 { return (.later, abs(diff)) }
        if diff >= -60 { return (.due, abs(diff)) }
        return (.missed, abs(diff))
    }

    /// Today's doses for one jar (dose times that run today plus planned doses), with what has been logged
    /// against each. Paused jars and jars on a break have none.
    static func rows(for jar: Jar, entries: [DoseEntry], planned: [PlannedDose] = [], now: Date = Date()) -> [SlotRow] {
        rows(for: jar, entries: entries, planned: planned, dayStart: doseDayStart(for: now), now: now)
    }

    /// One substance's doses on any dose day. Past days show what was logged or missed, future days show the plan.
    /// Doses logged earlier in the day under a schedule that has since changed (a stack turned on or off) count
    /// toward today's doses, so nothing gets doubled.
    static func rows(for jar: Jar, entries: [DoseEntry], planned: [PlannedDose], dayStart: Date, now: Date) -> [SlotRow] {
        rows(for: jar, source: ArrayDoseSource(entries: entries, planned: planned), dayStart: dayStart, now: now)
    }

    /// The same, reading logged and planned doses from `source`.
    static func rows(for jar: Jar, source: some DoseSource, dayStart: Date, now: Date) -> [SlotRow] {
        #if DEBUG
        DebugCounters.rows += 1
        #endif
        guard jar.isActive(on: dayStart) else { return [] }
        let todays = source.entries(jarId: jar.id, dayStart: dayStart)
        let today = doseDayStart(for: now)
        let (slots, fromStack) = jar.daySlots(onDayStarting: dayStart)
        var out: [SlotRow] = []
        if slots.isEmpty && jar.asNeeded && !fromStack {
            if let prn = jar.asNeededSlot {
                let last = todays.first { !$0.skipped && !($0.slotId ?? "").hasPrefix(PlannedDose.slotPrefix) }
                out.append(SlotRow(slot: prn, status: last.map { .taken($0) } ?? .asNeeded, distance: 100_000))
            }
        } else {
            for slot in slots {
                guard var at = occurrence(of: slot, dayStart: dayStart) else { continue }
                let hits = todays.filter { $0.slotId == slot.id }
                let hit = hits.first(where: { !$0.skipped }) ?? hits.first
                var result = status(at: at, hit: hit, now: now)
                // Upon waking: until today's wake-up shows up in Apple Health, the dose is still to come.
                if slot.uponWaking, hit == nil, WakeTimes.detected(onDayStarting: dayStart) == nil, dayStart >= today {
                    result = (.later, result.1)
                }
                // Timed after another dose: follows when that one was actually logged. If it was skipped or never
                // taken, this one is skipped too.
                if let gapSlot = slot.gapSlotId, let gapJar = slot.gapJarId {
                    let gap = Double(slot.gapMinutes ?? 0) * 60
                    let anchorHits = source.entries(jarId: gapJar, dayStart: dayStart).filter { $0.slotId == gapSlot }
                    let anchor = anchorHits.first(where: { !$0.skipped }) ?? anchorHits.first
                    if let anchor, !anchor.skipped {
                        at = anchor.takenAt.addingTimeInterval(gap)
                        result = status(at: at, hit: hit, now: now)
                    } else if hit == nil {
                        let anchorTime = at.addingTimeInterval(-gap)
                        if anchor?.skipped == true || dayStart < today || now > anchorTime.addingTimeInterval(3 * 3600) {
                            let skipped = DoseEntry(jarId: jar.id, jarName: jar.name, kind: jar.kind, form: jar.form, amount: "", pills: nil,
                                                    slotId: slot.id, slotLabel: slot.displayLabel, takenAt: at,
                                                    skipped: true, skipReason: "The dose it follows wasn't taken")
                            result = (.skipped(skipped), result.1)
                        } else {
                            result = (.waiting, result.1)
                        }
                    }
                }
                if jar.kind.remindOnly, result.0 == .missed { result = (.reminder, result.1) }
                // A substance added partway through a day has nothing to take before it was added.
                if hit == nil, let created = jar.createdAt, at < created { continue }
                out.append(SlotRow(slot: slot, status: result.0, distance: result.1, at: at))
            }
            // Doses logged under another schedule earlier today count toward the doses still open.
            let ids = Set(slots.map(\.id))
            let prnId = jar.asNeededSlot?.id ?? "prn"
            let leftover = todays
                .filter { e in
                    guard let sid = e.slotId else { return false }
                    return !ids.contains(sid) && sid != prnId && sid != "prn" && !sid.hasPrefix(PlannedDose.slotPrefix)
                }
                .sorted { $0.takenAt < $1.takenAt }
            for e in leftover {
                let ordered = out.indices.sorted { (out[$0].at ?? .distantFuture) < (out[$1].at ?? .distantFuture) }
                guard let i = ordered.first(where: { i in
                    switch out[i].status {
                    case .taken, .skipped: return false
                    default: return out[i].at != nil
                    }
                }) else { break }
                out[i] = SlotRow(slot: out[i].slot, status: e.skipped ? .skipped(e) : .taken(e), distance: out[i].distance, at: out[i].at)
            }
        }
        for p in source.planned(jarId: jar.id, dayStart: dayStart) {
            let hits = source.entries(jarId: jar.id, slotId: p.slotId)
            var result = status(at: p.at, hit: hits.first(where: { !$0.skipped }) ?? hits.first, now: now)
            if jar.kind.remindOnly, result.0 == .missed { result = (.reminder, result.1) }
            out.append(SlotRow(slot: p.slot, status: result.0, distance: result.1, at: p.at))
        }
        return out.sorted { a, b in
            switch (a.at, b.at) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            default: return false
            }
        }
    }

    /// The dose the Log button should offer: the unhandled timed or planned dose closest to now,
    /// or the as-needed dose for as-needed jars.
    static func suggestion(_ rows: [SlotRow]) -> SlotRow? {
        // Planned doses are only offered once they're due, so an unplanned extra dose isn't logged as the planned one.
        let open = rows.filter { $0.at != nil && !$0.status.isHandled && $0.status != .waiting && !($0.isPlanned && $0.status == .later) }
        // A dose due now comes first, then one missed earlier today, then the next one coming up.
        func rank(_ s: SlotStatus) -> Int {
            switch s {
            case .due: return 0
            case .missed, .reminder: return 1
            default: return 2
            }
        }
        if let best = open.min(by: { (rank($0.status), $0.distance) < (rank($1.status), $1.distance) }) { return best }
        return rows.first { $0.at == nil }
    }

    /// A dose that's due now or was missed within the last 3 hours. Never a future one.
    static func dueRow(for jar: Jar, entries: [DoseEntry], planned: [PlannedDose] = [], now: Date = Date()) -> SlotRow? {
        rows(for: jar, entries: entries, planned: planned, now: now)
            .filter { row in
                switch row.status {
                case .due: return true
                case .missed, .reminder: return row.distance <= 180
                default: return false
                }
            }
            .min { $0.distance < $1.distance }
    }

    static func dueSlot(for jar: Jar, entries: [DoseEntry], planned: [PlannedDose] = [], now: Date = Date()) -> DoseSlot? {
        dueRow(for: jar, entries: entries, planned: planned, now: now)?.slot
    }

    /// The next timed or planned dose across every active jar that hasn't been handled yet.
    /// A dose stays "next" until an hour after its time; after that it rolls forward.
    static func nextDose(jars: [Jar], entries: [DoseEntry], planned: [PlannedDose] = [], at now: Date = Date()) -> NextDose? {
        nextGroup(jars: jars, entries: entries, planned: planned, at: now).first
    }

    /// The next dose and every other dose due with it (within the group window), across all jars.
    static func nextGroup(jars: [Jar], entries: [DoseEntry], planned: [PlannedDose] = [], at now: Date = Date()) -> [NextDose] {
        let index = DoseIndex(entries: entries, planned: planned)
        return nextGroup(jars: jars, at: now) { rows(for: $0, source: index, dayStart: $1, now: now) }
    }

    /// The same, with each substance's rows for a dose day coming from `rows`.
    static func nextGroup(jars: [Jar], at now: Date, rows: (Jar, Date) -> [SlotRow]) -> [NextDose] {
        let cal = Calendar.current
        let today = doseDayStart(for: now)
        for offset in 0...7 {
            guard let dayStart = cal.date(byAdding: .day, value: offset, to: today) else { continue }
            var open: [NextDose] = []
            for jar in jars where jar.isActive(on: dayStart) {
                for row in rows(jar, dayStart) {
                    guard let at = row.at, at >= now.addingTimeInterval(-3600), !row.status.isHandled, row.status != .waiting else { continue }
                    open.append(NextDose(jar: jar, slot: row.slot, time: at))
                }
            }
            open.sort { $0.time != $1.time ? $0.time < $1.time : $0.jar.name < $1.jar.name }
            guard let first = open.first else { continue }
            let limit = first.time.addingTimeInterval(Double(groupMinutes) * 60)
            return open.filter { $0.time <= limit }
        }
        return []
    }

    /// A day's doses split into groups due together: each group starts at its earliest dose and takes every dose
    /// within the group window of it.
    static func groups(_ items: [DayItem]) -> [[DayItem]] {
        let sorted = items.filter { $0.row.at != nil }.sorted { ($0.row.at ?? .distantFuture) < ($1.row.at ?? .distantFuture) }
        var out: [[DayItem]] = []
        var current: [DayItem] = []
        var start: Date?
        for item in sorted {
            guard let at = item.row.at else { continue }
            if let s = start, at.timeIntervalSince(s) <= Double(groupMinutes) * 60 {
                current.append(item)
            } else {
                if !current.isEmpty { out.append(current) }
                current = [item]
                start = at
            }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    /// Dates grouped the same way, for reminders.
    static func groupTimes<T>(_ items: [(Date, T)]) -> [(Date, [T])] {
        let sorted = items.sorted { $0.0 < $1.0 }
        var out: [(Date, [T])] = []
        for (date, value) in sorted {
            if let last = out.last, date.timeIntervalSince(last.0) <= Double(groupMinutes) * 60 {
                out[out.count - 1].1.append(value)
            } else {
                out.append((date, [value]))
            }
        }
        return out
    }

    static func todayCounts(jars: [Jar], entries: [DoseEntry], planned: [PlannedDose] = [], now: Date = Date()) -> (taken: Int, total: Int) {
        let day = schedule(jars: jars, entries: entries, planned: planned, dayStart: doseDayStart(for: now), now: now)
        return (day.taken, day.total)
    }

    /// Everything on one dose day for the Schedule tab.
    static func schedule(jars: [Jar], entries: [DoseEntry], planned: [PlannedDose], dayStart: Date, now: Date) -> DaySchedule {
        let index = DoseIndex(entries: entries, planned: planned)
        return schedule(jars: jars, dayStart: dayStart) { rows(for: $0, source: index, dayStart: dayStart, now: now) }
    }

    /// The same, with each substance's rows coming from `rows`.
    static func schedule(jars: [Jar], dayStart: Date, rows: (Jar) -> [SlotRow]) -> DaySchedule {
        var items: [DayItem] = []
        var asNeeded: [Jar] = []
        for jar in jars where jar.isActive(on: dayStart) {
            let jarRows = rows(jar)
            items += jarRows.filter { $0.at != nil }.map { DayItem(jar: jar, row: $0) }
            let hasTimed = jarRows.contains { $0.at != nil && !$0.isPlanned }
            if !jar.kind.remindOnly && !hasTimed { asNeeded.append(jar) }
        }
        items.sort { a, b in
            let x = a.row.at ?? .distantFuture, y = b.row.at ?? .distantFuture
            return x != y ? x < y : a.jar.name < b.jar.name
        }
        return DaySchedule(dayStart: dayStart, items: items, asNeeded: asNeeded)
    }

    /// True when the dose day has any timed or planned dose (for the dots on the week strip).
    static func hasDoses(jars: [Jar], planned: [PlannedDose], dayStart: Date) -> Bool {
        for jar in jars where jar.isActive(on: dayStart) {
            if !jar.slots(onDayStarting: dayStart).isEmpty { return true }
            if !Self.planned(for: jar.id, planned: planned, dayStart: dayStart).isEmpty { return true }
        }
        return false
    }

    /// Moments when a status changes (a dose becomes due, missed, or a new dose day starts), for the widget.
    /// The list starts at the dose day's start and never contains the current second.
    static func refreshDates(jars: [Jar], planned: [PlannedDose] = [], from now: Date = Date()) -> [Date] {
        var upcoming = Set<Date>()
        let cal = Calendar.current
        let today = doseDayStart(for: now)
        for offset in 0...2 {
            guard let dayStart = cal.date(byAdding: .day, value: offset, to: today) else { continue }
            upcoming.insert(dayStart)
            guard offset < 2 else { continue }
            for jar in jars {
                for slot in jar.slots(onDayStarting: dayStart) {
                    guard let t = occurrence(of: slot, dayStart: dayStart) else { continue }
                    upcoming.formUnion([t.addingTimeInterval(-45 * 60), t, t.addingTimeInterval(60 * 60 + 1)])
                }
            }
        }
        for p in planned where p.at > now && p.at < now.addingTimeInterval(2 * 86400) {
            upcoming.formUnion([p.at.addingTimeInterval(-45 * 60), p.at, p.at.addingTimeInterval(60 * 60 + 1)])
        }
        return [today] + upcoming.filter { $0 > now }.sorted()
    }
}
