import Foundation

enum SlotStatus: Equatable {
    case taken(DoseEntry)
    case skipped(DoseEntry)
    case due
    case later
    case missed
    case asNeeded

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

    /// Doses that count toward the day's progress (skipped ones don't).
    var counted: [DayItem] { items.filter { if case .skipped = $0.row.status { return false } else { return true } } }
    var taken: Int { counted.filter { $0.row.status.isTaken }.count }
    var total: Int { counted.count }
}

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

    /// When a slot happens within the dose day that starts at `dayStart`.
    static func occurrence(of slot: DoseSlot, dayStart: Date) -> Date? {
        guard let m = slot.minutes else { return nil }
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

    /// One jar's doses on any dose day. Past days show what was logged or missed, future days show the plan.
    static func rows(for jar: Jar, entries: [DoseEntry], planned: [PlannedDose], dayStart: Date, now: Date) -> [SlotRow] {
        guard jar.isActive(on: dayStart) else { return [] }
        let todays = Self.entries(for: jar.id, entries: entries, dayStart: dayStart)
        var out: [SlotRow] = []
        if jar.asNeeded {
            if let prn = jar.asNeededSlot {
                let last = todays.first { !$0.skipped && !($0.slotId ?? "").hasPrefix(PlannedDose.slotPrefix) }
                out.append(SlotRow(slot: prn, status: last.map { .taken($0) } ?? .asNeeded, distance: 100_000))
            }
        } else {
            for slot in jar.slots(onDayStarting: dayStart) {
                guard let at = occurrence(of: slot, dayStart: dayStart) else { continue }
                let hits = todays.filter { $0.slotId == slot.id }
                let result = status(at: at, hit: hits.first(where: { !$0.skipped }) ?? hits.first, now: now)
                out.append(SlotRow(slot: slot, status: result.0, distance: result.1, at: at))
            }
        }
        for p in Self.planned(for: jar.id, planned: planned, dayStart: dayStart) {
            let hits = entries.filter { $0.jarId == jar.id && $0.slotId == p.slotId }
            let result = status(at: p.at, hit: hits.first(where: { !$0.skipped }) ?? hits.first, now: now)
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
        let open = rows.filter { $0.at != nil && !$0.status.isHandled && !($0.isPlanned && $0.status == .later) }
        if let best = open.min(by: { $0.distance < $1.distance }) { return best }
        return rows.first { $0.at == nil }
    }

    /// A dose that's due now or was missed within the last 3 hours. Never a future one.
    static func dueRow(for jar: Jar, entries: [DoseEntry], planned: [PlannedDose] = [], now: Date = Date()) -> SlotRow? {
        rows(for: jar, entries: entries, planned: planned, now: now)
            .filter { row in
                switch row.status {
                case .due: return true
                case .missed: return row.distance <= 180
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
        let cal = Calendar.current
        var best: NextDose?
        let today = doseDayStart(for: now)
        for offset in 0...7 {
            guard let dayStart = cal.date(byAdding: .day, value: offset, to: today) else { continue }
            for jar in jars where jar.isActive(on: dayStart) {
                for slot in jar.slots(onDayStarting: dayStart) {
                    guard let t = occurrence(of: slot, dayStart: dayStart), t >= now.addingTimeInterval(-3600) else { continue }
                    let handled = entries.contains { $0.jarId == jar.id && $0.slotId == slot.id && sameDoseDay($0.takenAt, t) }
                    if handled { continue }
                    if best == nil || t < best!.time { best = NextDose(jar: jar, slot: slot, time: t) }
                }
            }
            if best != nil { break }
        }
        for p in planned where p.at >= now.addingTimeInterval(-3600) {
            guard let jar = jars.first(where: { $0.id == p.jarId }), jar.isActive(on: doseDayStart(for: p.at)) else { continue }
            if entries.contains(where: { $0.slotId == p.slotId }) { continue }
            if best == nil || p.at < best!.time { best = NextDose(jar: jar, slot: p.slot, time: p.at) }
        }
        return best
    }

    static func todayCounts(jars: [Jar], entries: [DoseEntry], planned: [PlannedDose] = [], now: Date = Date()) -> (taken: Int, total: Int) {
        let day = schedule(jars: jars, entries: entries, planned: planned, dayStart: doseDayStart(for: now), now: now)
        return (day.taken, day.total)
    }

    /// Everything on one dose day for the Schedule tab.
    static func schedule(jars: [Jar], entries: [DoseEntry], planned: [PlannedDose], dayStart: Date, now: Date) -> DaySchedule {
        var items: [DayItem] = []
        var asNeeded: [Jar] = []
        for jar in jars where jar.isActive(on: dayStart) {
            let jarRows = rows(for: jar, entries: entries, planned: planned, dayStart: dayStart, now: now)
            items += jarRows.filter { $0.at != nil }.map { DayItem(jar: jar, row: $0) }
            let hasTimed = jarRows.contains { $0.at != nil && !$0.isPlanned }
            if jar.kind.allowsSchedule && !hasTimed { asNeeded.append(jar) }
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
