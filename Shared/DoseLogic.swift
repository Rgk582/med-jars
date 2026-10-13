import Foundation

enum SlotStatus: Equatable {
    case taken(DoseEntry)
    case due
    case later
    case missed
    case asNeeded

    var isTaken: Bool { if case .taken = self { return true } else { return false } }
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
    /// Today's doses for one jar, with what has been logged against each.
    static func rows(for jar: Jar, entries: [DoseEntry], now: Date = Date()) -> [SlotRow] {
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute], from: now)
        let nowMin = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        let todays = entries.filter { $0.jarId == jar.id && cal.isDate($0.takenAt, inSameDayAs: now) }
        return jar.sortedSchedule.map { slot in
            let hit = todays.first { $0.slotId == slot.id }
            guard let m = slot.minutes else {
                return SlotRow(slot: slot, status: hit.map { .taken($0) } ?? .asNeeded, distance: 100_000)
            }
            let diff = m - nowMin
            let status: SlotStatus
            if let hit { status = .taken(hit) }
            else if diff > 45 { status = .later }
            else if diff >= -60 { status = .due }
            else { status = .missed }
            return SlotRow(slot: slot, status: status, distance: abs(diff))
        }
    }

    /// The dose the Log button should offer: the untaken timed dose closest to now,
    /// or the first as-needed dose for jars that have no set times.
    static func suggestion(_ rows: [SlotRow]) -> SlotRow? {
        let open = rows.filter { $0.slot.minutes != nil && !$0.status.isTaken }
        if let best = open.min(by: { $0.distance < $1.distance }) { return best }
        if !rows.contains(where: { $0.slot.minutes != nil }) { return rows.first }
        return nil
    }

    static func date(for slot: DoseSlot, on day: Date) -> Date? {
        guard let m = slot.minutes else { return nil }
        return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: day)
    }

    /// The next timed dose across every jar that hasn't been logged yet.
    /// A dose stays "next" until an hour after its time; after that it rolls forward.
    static func nextDose(jars: [Jar], entries: [DoseEntry], at now: Date = Date()) -> NextDose? {
        let cal = Calendar.current
        var best: NextDose?
        for dayOffset in 0...1 {
            guard let day = cal.date(byAdding: .day, value: dayOffset, to: now) else { continue }
            for jar in jars {
                for slot in jar.timedSlots {
                    guard let t = date(for: slot, on: day) else { continue }
                    if dayOffset == 0 {
                        if t < now.addingTimeInterval(-3600) { continue }
                        let taken = entries.contains { $0.jarId == jar.id && $0.slotId == slot.id && cal.isDate($0.takenAt, inSameDayAs: now) }
                        if taken { continue }
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
            total += rows.count
            taken += rows.filter { $0.status.isTaken }.count
        }
        return (taken, total)
    }
}
