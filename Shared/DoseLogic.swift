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
    var id: String { slot.id }
}

struct NextDose {
    let jar: Jar
    let slot: DoseSlot
    let time: Date
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
        let start = doseDayStart(for: now), end = doseDayEnd(for: now)
        return entries.filter { $0.jarId == jarId && $0.takenAt >= start && $0.takenAt < end }
    }

    /// Today's doses for one jar, with what has been logged against each. Paused jars and jars on a break have none.
    static func rows(for jar: Jar, entries: [DoseEntry], now: Date = Date()) -> [SlotRow] {
        let dayStart = doseDayStart(for: now)
        guard jar.isActive(on: dayStart) else { return [] }
        let todays = entriesToday(for: jar.id, entries: entries, now: now)
        return jar.sortedSchedule.map { slot in
            let hits = todays.filter { $0.slotId == slot.id }
            let hit = hits.first(where: { !$0.skipped }) ?? hits.first
            guard let at = occurrence(of: slot, dayStart: dayStart) else {
                let last = todays.first(where: { !$0.skipped })
                return SlotRow(slot: slot, status: last.map { .taken($0) } ?? .asNeeded, distance: 100_000)
            }
            let diff = Int((at.timeIntervalSince(now) / 60).rounded())
            let status: SlotStatus
            if let hit { status = hit.skipped ? .skipped(hit) : .taken(hit) }
            else if diff > 45 { status = .later }
            else if diff >= -60 { status = .due }
            else { status = .missed }
            return SlotRow(slot: slot, status: status, distance: abs(diff))
        }
    }

    /// The dose the Log button should offer: the unhandled timed dose closest to now,
    /// or the as-needed dose for as-needed jars.
    static func suggestion(_ rows: [SlotRow]) -> SlotRow? {
        let open = rows.filter { $0.slot.minutes != nil && !$0.status.isHandled }
        if let best = open.min(by: { $0.distance < $1.distance }) { return best }
        if !rows.contains(where: { $0.slot.minutes != nil }) { return rows.first }
        return nil
    }

    /// A dose that's due now or was missed within the last 3 hours. Never a future one.
    static func dueSlot(for jar: Jar, entries: [DoseEntry], now: Date = Date()) -> DoseSlot? {
        rows(for: jar, entries: entries, now: now)
            .filter { row in
                switch row.status {
                case .due: return true
                case .missed: return row.distance <= 180
                default: return false
                }
            }
            .min { $0.distance < $1.distance }?.slot
    }

    /// The next timed dose across every active jar that hasn't been handled yet.
    /// A dose stays "next" until an hour after its time; after that it rolls forward.
    static func nextDose(jars: [Jar], entries: [DoseEntry], at now: Date = Date()) -> NextDose? {
        let cal = Calendar.current
        var best: NextDose?
        let today = doseDayStart(for: now)
        for offset in 0...2 {
            guard let dayStart = cal.date(byAdding: .day, value: offset, to: today) else { continue }
            for jar in jars where jar.isActive(on: dayStart) {
                for slot in jar.timedSlots {
                    guard let t = occurrence(of: slot, dayStart: dayStart) else { continue }
                    if offset == 0 {
                        if t < now.addingTimeInterval(-3600) { continue }
                        let handled = entries.contains { $0.jarId == jar.id && $0.slotId == slot.id && sameDoseDay($0.takenAt, now) }
                        if handled { continue }
                    }
                    if best == nil || t < best!.time { best = NextDose(jar: jar, slot: slot, time: t) }
                }
            }
            if best != nil { return best }
        }
        return best
    }

    static func todayCounts(jars: [Jar], entries: [DoseEntry], now: Date = Date()) -> (taken: Int, total: Int) {
        var total = 0, taken = 0
        for jar in jars {
            let rows = rows(for: jar, entries: entries, now: now).filter { $0.slot.minutes != nil }
            for r in rows {
                if case .skipped = r.status { continue }
                total += 1
                if r.status.isTaken { taken += 1 }
            }
        }
        return (taken, total)
    }

    /// Moments when a status on screen changes (a dose becomes due, missed, or a new dose day starts),
    /// so lists only redraw when something actually changes.
    static func refreshDates(jars: [Jar], from now: Date = Date()) -> [Date] {
        var out: [Date] = [now]
        let cal = Calendar.current
        let today = doseDayStart(for: now)
        for offset in 0...1 {
            guard let dayStart = cal.date(byAdding: .day, value: offset, to: today) else { continue }
            out.append(dayStart)
            for jar in jars {
                for slot in jar.timedSlots {
                    guard let t = occurrence(of: slot, dayStart: dayStart) else { continue }
                    out.append(contentsOf: [t.addingTimeInterval(-45 * 60), t, t.addingTimeInterval(60 * 60 + 1)])
                }
            }
        }
        out.append(doseDayEnd(for: now))
        return Array(Set(out.filter { $0 >= now.addingTimeInterval(-1) })).sorted()
    }
}
