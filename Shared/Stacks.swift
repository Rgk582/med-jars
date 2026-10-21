import Foundation

/// A stretch of dose days a stack was turned off. `until` is the day it came back on (not counted), nil while still off.
struct OffSpan: Codable, Hashable {
    var from: Date
    var until: Date?
}

/// Whether a stack sets a substance's schedule while it runs, or only lists it (the substance keeps its own schedule).
enum MemberMode: String, Codable, CaseIterable, Identifiable {
    case controls, own
    var id: String { rawValue }
    var name: String {
        switch self {
        case .controls: return "Stack Controls It"
        case .own: return "Keeps Its Own Schedule"
        }
    }
}

/// What a controlled substance does on days the stack doesn't give it a dose.
enum OffDayRule: String, Codable, CaseIterable, Identifiable {
    case off, normal
    var id: String { rawValue }
    var name: String {
        switch self {
        case .off: return "Off"
        case .normal: return "Normal Schedule"
        }
    }
}

/// One substance in a stack with its stack schedule.
struct StackMember: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var jarId: String
    var mode: MemberMode = .controls
    var offDays: OffDayRule = .off
    var rule: ScheduleRule = ScheduleRule()
    /// Timed after another member: that member's id and the gap. The time follows when that one is actually logged.
    var gapAfter: String? = nil
    var gapMinutes: Int = 30

    init(jarId: String) { self.jarId = jarId }

    enum CodingKeys: String, CodingKey { case id, jarId, mode, offDays, rule, gapAfter, gapMinutes }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
        jarId = try c.decode(String.self, forKey: .jarId)
        mode = (try? c.decodeIfPresent(MemberMode.self, forKey: .mode)) ?? .controls
        offDays = (try? c.decodeIfPresent(OffDayRule.self, forKey: .offDays)) ?? .off
        rule = (try? c.decodeIfPresent(ScheduleRule.self, forKey: .rule)) ?? ScheduleRule()
        gapAfter = try? c.decodeIfPresent(String.self, forKey: .gapAfter)
        gapMinutes = (try? c.decodeIfPresent(Int.self, forKey: .gapMinutes)) ?? 30
    }
}

/// Substances that work together toward a goal, with their own schedule that can run for set dates,
/// continuously, or in on/off cycles. While it runs, it replaces the schedule of the substances it controls.
struct Stack: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String = ""
    var goal: String = ""
    var notes: String = ""
    var color: LidColor = .indigo
    var members: [StackMember] = []
    /// First dose day. Nil until it's first turned on.
    var start: Date? = nil
    /// Last dose day. Nil runs until turned off.
    var end: Date? = nil
    /// Repeating cycle: weeks on, then weeks off (0 means no cycle).
    var cycleOnWeeks: Int = 0
    var cycleOffWeeks: Int = 0
    /// Times it was turned off. Turning back on picks up where it left off.
    var offSpans: [OffSpan] = []
    /// For each cycle after a break (by number): true restarts rotations at week 1, false keeps counting.
    var restartAfterBreak: [String: Bool] = [:]
    /// Optional NFC tags that open the stack ready to log.
    var tagIds: [String] = []
    var order: Int = 0
    /// When it was last turned on, so the newest wins a tie.
    var turnedOnAt: Date? = nil

    init() {}

    enum CodingKeys: String, CodingKey {
        case id, name, goal, notes, color, members, start, end, cycleOnWeeks, cycleOffWeeks, offSpans, restartAfterBreak, tagIds, order, turnedOnAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        goal = (try? c.decodeIfPresent(String.self, forKey: .goal)) ?? ""
        notes = (try? c.decodeIfPresent(String.self, forKey: .notes)) ?? ""
        color = (try? c.decodeIfPresent(LidColor.self, forKey: .color)) ?? .indigo
        members = ((try? c.decodeIfPresent([Lossy<StackMember>].self, forKey: .members)) ?? []).compactMap(\.value)
        start = try? c.decodeIfPresent(Date.self, forKey: .start)
        end = try? c.decodeIfPresent(Date.self, forKey: .end)
        cycleOnWeeks = max(0, (try? c.decodeIfPresent(Int.self, forKey: .cycleOnWeeks)) ?? 0)
        cycleOffWeeks = max(0, (try? c.decodeIfPresent(Int.self, forKey: .cycleOffWeeks)) ?? 0)
        offSpans = (try? c.decodeIfPresent([OffSpan].self, forKey: .offSpans)) ?? []
        restartAfterBreak = (try? c.decodeIfPresent([String: Bool].self, forKey: .restartAfterBreak)) ?? [:]
        tagIds = (try? c.decodeIfPresent([String].self, forKey: .tagIds)) ?? []
        order = (try? c.decodeIfPresent(Int.self, forKey: .order)) ?? 0
        turnedOnAt = try? c.decodeIfPresent(Date.self, forKey: .turnedOnAt)
    }

    /// Turned on (running, scheduled to start, or between cycles), as opposed to turned off.
    var isOn: Bool {
        guard start != nil else { return false }
        return offSpans.last.map { $0.until != nil } ?? true
    }

    var hasCycle: Bool { cycleOnWeeks > 0 && cycleOffWeeks > 0 }

    var displayName: String { name.isEmpty ? "Untitled Stack" : name }
}

/// Where a stack stands on one dose day.
enum StackDay: Equatable {
    /// Never turned on.
    case notOn
    /// Turned on, starting later.
    case scheduled
    /// Running. `index` counts every running day so far, `cycle` is which on-cycle, `cycleDay` the day within it.
    case active(index: Int, cycle: Int, cycleDay: Int)
    /// Between cycles.
    case onBreak(cycle: Int)
    /// Turned off.
    case off
    /// Past its last day.
    case ended

    var isActive: Bool { if case .active = self { return true } else { return false } }
}

/// Something about a stack that changes on a day, for the heads-up the night before.
enum StackChange {
    case starts, lastDay, breakStarts, breakEnds(cycle: Int)
}

enum StackLogic {
    /// Every stack and substance, set whenever data loads so schedules everywhere (app, widget, reminders) agree.
    static var stacks: [Stack] {
        get { ScheduleContext.current.stacks }
        set { ScheduleContext.current.stacks = newValue }
    }
    static var jars: [Jar] {
        get { ScheduleContext.current.jars }
        set { ScheduleContext.current.jars = newValue }
    }
    /// Stops gap times from looking up other gap times forever.
    private static var resolvingGap: Bool {
        get { ScheduleContext.current.resolvingGap }
        set { ScheduleContext.current.resolvingGap = newValue }
    }

    static func dayStart(_ d: Date) -> Date { DoseLogic.doseDayStart(for: d) }

    /// Calendar days from one dose day to another.
    static func days(from a: Date, to b: Date) -> Int {
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: dayStart(a)), to: cal.startOfDay(for: dayStart(b))).day ?? 0
    }

    /// Days the stack was off between its start and `day` (not counting `day`).
    static func offDays(_ s: Stack, before day: Date) -> Int {
        guard let start = s.start else { return 0 }
        var total = 0
        for span in s.offSpans {
            let from = max(dayStart(span.from), dayStart(start))
            let until = min(dayStart(span.until ?? day), dayStart(day))
            if until > from { total += days(from: from, to: until) }
        }
        return total
    }

    /// The stack's status on a dose day.
    static func day(_ s: Stack, _ date: Date) -> StackDay {
        guard let start = s.start else { return .notOn }
        let d = dayStart(date)
        let st = dayStart(start)
        for span in s.offSpans {
            let from = dayStart(span.from)
            if d >= from, span.until.map({ d < dayStart($0) }) ?? true { return .off }
        }
        if d < st { return .scheduled }
        if let end = s.end, d > dayStart(end) { return .ended }
        let running = days(from: st, to: d) - offDays(s, before: d)
        if s.hasCycle {
            let onLen = s.cycleOnWeeks * 7
            let len = onLen + s.cycleOffWeeks * 7
            let cycle = running / len
            let pos = running % len
            if pos >= onLen { return .onBreak(cycle: cycle) }
            return .active(index: cycle * onLen + pos, cycle: cycle, cycleDay: pos)
        }
        return .active(index: running, cycle: 0, cycleDay: running)
    }

    static func isRunning(_ s: Stack, on date: Date) -> Bool { day(s, date).isActive }

    /// Turned on and not past its end: running, on a break, or set to start.
    static func isLive(_ s: Stack, now: Date = Date()) -> Bool {
        guard s.isOn else { return false }
        if case .ended = day(s, now) { return false }
        return true
    }

    /// The day count a stack's rotations and every-few-days schedules use: restart at each cycle (the default),
    /// or keep counting through breaks when you chose that for the cycle.
    static func memberIndex(_ s: Stack, _ d: StackDay) -> Int? {
        guard case let .active(index, cycle, cycleDay) = d else { return nil }
        if cycle == 0 { return cycleDay }
        return (s.restartAfterBreak[String(cycle)] ?? true) ? cycleDay : index
    }

    /// The running stack (and member) that sets a substance's schedule on a day. When two do, the one picked for
    /// the substance wins, then the one turned on most recently.
    static func controller(jarId: String, owner: String?, dayStart date: Date) -> (Stack, StackMember)? {
        var found: [(Stack, StackMember)] = []
        for s in stacks where isRunning(s, on: date) {
            if let m = s.members.first(where: { $0.jarId == jarId && $0.mode == .controls }) { found.append((s, m)) }
        }
        if found.count > 1, let owner, let pick = found.first(where: { $0.0.id == owner }) { return pick }
        return found.max { ($0.0.turnedOnAt ?? .distantPast) < ($1.0.turnedOnAt ?? .distantPast) }
    }

    /// A member's doses on a day, tagged with the stack, with gap doses timed after the dose they follow.
    /// Nil when the member has no doses that day.
    static func memberSlots(_ s: Stack, _ m: StackMember, dayStart date: Date) -> [DoseSlot]? {
        let d = day(s, date)
        guard let idx = memberIndex(s, d) else { return nil }
        var doses: [DoseSlot]
        if m.mode == .own {
            guard let jar = jars.first(where: { $0.id == m.jarId }) else { return nil }
            doses = jar.slots(onDayStarting: date)
        } else {
            guard let plan = m.rule.plan(onDayStarting: date, index: idx) else { return nil }
            doses = plan.doses.filter { $0.time != nil }
            for i in doses.indices { doses[i].stackId = s.id }
        }
        if doses.isEmpty { return nil }
        if !resolvingGap, m.mode == .controls, let anchorId = m.gapAfter, anchorId != m.id,
           let anchor = s.members.first(where: { $0.id == anchorId }) {
            resolvingGap = true
            let anchorSlots = memberSlots(s, anchor, dayStart: date) ?? []
            resolvingGap = false
            for i in doses.indices where i < anchorSlots.count {
                let a = anchorSlots[i]
                doses[i].gapJarId = anchor.jarId
                doses[i].gapSlotId = a.id
                doses[i].gapMinutes = m.gapMinutes
                if let am = a.minutes(onDayStarting: date) {
                    let t = ((am + m.gapMinutes) % 1440 + 1440) % 1440
                    doses[i].time = String(format: "%02d:%02d", t / 60, t % 60)
                    doses[i].bedtimeOffset = nil
                    doses[i].uponWaking = false
                }
            }
        }
        return doses
    }

    /// A substance's doses from the stack that controls it on a day. Nil when no running stack controls it, or when
    /// the stack gives it nothing that day and it's set to run its normal schedule then.
    static func slots(for jar: Jar, dayStart date: Date) -> [DoseSlot]? {
        guard let pair = controller(jarId: jar.id, owner: jar.stackOwner, dayStart: date) else { return nil }
        let (s, m) = pair
        if let doses = memberSlots(s, m, dayStart: date), !doses.isEmpty { return doses }
        return m.offDays == .off ? [] : nil
    }

    /// A stack dose by id.
    static func slot(jarId: String, slotId: String) -> DoseSlot? {
        for s in stacks {
            for m in s.members where m.jarId == jarId {
                if var found = m.rule.allSlots.first(where: { $0.id == slotId }) {
                    found.stackId = s.id
                    return found
                }
            }
        }
        return nil
    }

    /// Stacks that also control one of this stack's substances and run (or are set to run) at the same time.
    static func conflicts(for s: Stack) -> [(jarId: String, other: Stack)] {
        var out: [(jarId: String, other: Stack)] = []
        for m in s.members where m.mode == .controls {
            for other in stacks where other.id != s.id && other.isOn {
                if other.members.contains(where: { $0.jarId == m.jarId && $0.mode == .controls }) { out.append((m.jarId, other)) }
            }
        }
        return out
    }

    /// Running day number (1 based) and the total when the stack has an end date.
    static func dayNumber(_ s: Stack, on date: Date) -> (Int, Int?)? {
        guard let start = s.start else { return nil }
        let d = day(s, date)
        guard d.isActive || { if case .onBreak = d { return true } else { return false } }() else { return nil }
        let n = days(from: start, to: date) - offDays(s, before: date) + 1
        let total = s.end.map { days(from: start, to: $0) - offDays(s, before: $0) + 1 }
        return (n, total)
    }

    /// The next dose day the stack's status changes from what it is on `date`, looking ahead up to a year.
    static func nextChange(_ s: Stack, after date: Date) -> Date? {
        let cal = Calendar.current
        let today = dayStart(date)
        let now = day(s, today)
        for offset in 1...366 {
            guard let d = cal.date(byAdding: .day, value: offset, to: today) else { continue }
            let state = day(s, d)
            switch (now, state) {
            case (.active, .active): continue
            case (.onBreak, .onBreak): continue
            default: if state != now { return d }
            }
        }
        return nil
    }

    /// Changes coming up in the next `count` days, for heads-ups the night before.
    static func changes(_ s: Stack, from date: Date, days count: Int) -> [(day: Date, change: StackChange)] {
        let cal = Calendar.current
        let today = dayStart(date)
        var out: [(day: Date, change: StackChange)] = []
        for offset in 0...count {
            guard let d = cal.date(byAdding: .day, value: offset, to: today),
                  let prev = cal.date(byAdding: .day, value: -1, to: d),
                  let next = cal.date(byAdding: .day, value: 1, to: d) else { continue }
            let was = day(s, prev), is_ = day(s, d), will = day(s, next)
            if is_.isActive && was == .scheduled { out.append((d, .starts)) }
            if is_.isActive, case .ended = will { out.append((d, .lastDay)) }
            if case .onBreak = is_, was.isActive { out.append((d, .breakStarts)) }
            if case let .active(_, cycle, cycleDay) = is_, cycleDay == 0, cycle > 0, case .onBreak = was {
                out.append((d, .breakEnds(cycle: cycle)))
            }
        }
        return out
    }

    /// "Day 12 of 56", "Starts Tue, Oct 20", "On a break until Nov 3", "Off", "Ended Oct 1".
    static func statusText(_ s: Stack, now: Date = Date()) -> String {
        let d = day(s, now)
        switch d {
        case .notOn, .off:
            return "Off"
        case .scheduled:
            return s.start.map { "Starts \($0.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))" } ?? "Scheduled"
        case .active:
            guard let dn = dayNumber(s, on: now) else { return "Running" }
            let (n, total) = dn
            return total.map { "Day \(n) of \($0)" } ?? "Day \(n)"
        case .onBreak:
            if let back = nextChange(s, after: now) {
                return "On a break until \(back.formatted(.dateTime.month(.abbreviated).day()))"
            }
            return "On a break"
        case .ended:
            return s.end.map { "Ended \($0.formatted(.dateTime.month(.abbreviated).day()))" } ?? "Ended"
        }
    }
}
