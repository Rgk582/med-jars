import Foundation

/// What the schedule math reads besides a substance and its doses: every stack and substance, bedtimes,
/// wake-ups and the jar order. Set whenever data loads.
///
/// There's one shared copy, used on the main thread and anywhere nothing else is set up. Background work that
/// works out schedules (reminders) installs its own snapshot for its thread, so it never sees the main thread's
/// copy change halfway through a pass, and the main thread never sees half of a background pass.
final class ScheduleContext: @unchecked Sendable {
    var stacks: [Stack] = []
    var jars: [Jar] = []
    var bedtimeMinutes = 23 * 60
    var bedtimeByWeekday: [String: Int] = [:]
    var bedtimeByDate: [String: Int] = [:]
    var usualWakeMinutes = 7 * 60
    var wakeByDay: [String: Date] = [:]
    var pickOrder: PickOrder = .wholeFirst
    /// Stops gap times from looking up other gap times forever.
    var resolvingGap = false

    init() {}

    func copy() -> ScheduleContext {
        let c = ScheduleContext()
        c.stacks = stacks
        c.jars = jars
        c.bedtimeMinutes = bedtimeMinutes
        c.bedtimeByWeekday = bedtimeByWeekday
        c.bedtimeByDate = bedtimeByDate
        c.usualWakeMinutes = usualWakeMinutes
        c.wakeByDay = wakeByDay
        c.pickOrder = pickOrder
        return c
    }

    private static let shared = ScheduleContext()
    private static let threadKey = "com.medjars.schedulecontext"

    /// The context for the calling thread.
    static var current: ScheduleContext {
        if !Thread.isMainThread, let c = Thread.current.threadDictionary[threadKey] as? ScheduleContext { return c }
        return shared
    }

    /// Runs `work` on the calling thread with `snapshot` as its context, then puts back what was there.
    static func with<T>(_ snapshot: ScheduleContext, _ work: () -> T) -> T {
        let dict = Thread.current.threadDictionary
        let previous = dict[threadKey]
        dict[threadKey] = snapshot
        defer { dict[threadKey] = previous }
        return work()
    }
}
