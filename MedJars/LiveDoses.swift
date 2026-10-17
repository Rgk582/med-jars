import ActivityKit
import BackgroundTasks
import Foundation

/// Keeps one Live Activity showing every dose whose effect timeline is still running.
/// A Live Activity can't redraw itself, so each update marks it out of date at the next change (a peak, an end,
/// or Discreet Mode's schedule switching), which makes iOS draw it again then, and asks iOS for a background
/// refresh around that time to send a fresh update.
@MainActor
enum LiveDoses {
    static let taskId = "com.medjars.app.liveupdate"
    /// The update in flight, so a Shortcut can wait for it before it finishes.
    private(set) static var lastSync: Task<Void, Never>?

    static func activeDoses(jars: [Jar], entries: [DoseEntry], now: Date = Date()) -> [ActiveDose] {
        var out: [ActiveDose] = []
        for e in entries where !e.skipped && now.timeIntervalSince(e.takenAt) < 48 * 3600 && e.takenAt <= now {
            guard let jar = jars.first(where: { $0.id == e.jarId }), !jar.paused,
                  let effect = jar.effect, effect.liveActivity else { continue }
            let dose = effect.activeDose(id: e.id, jar: jar, amount: e.amount, start: e.takenAt)
            if dose.end > now { out.append(dose) }
        }
        return Array(out.sorted { $0.start > $1.start }.prefix(4))
    }

    /// The next moment the Live Activity should look different.
    static func nextChange(doses: [ActiveDose], discreet: DiscreetSettings?, after now: Date) -> Date? {
        var dates = doses.flatMap { [$0.peak, $0.end] }.filter { $0 > now }
        if !doses.isEmpty, let d = discreet?.nextChange(after: now) { dates.append(d) }
        return dates.min()
    }

    // MARK: Dismissed doses

    /// Doses whose Live Activity is showing, so a missing activity later means it was swiped away.
    private static let shownKey = "liveActivityShownDoses"
    /// Doses swiped away from the Lock Screen, with when their effect ends. They stay off until then.
    private static let dismissedKey = "liveActivityDismissedDoses"

    private static var shown: [String] {
        get { UserDefaults.standard.stringArray(forKey: shownKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: shownKey) }
    }

    private static var dismissed: [String: Double] {
        get { (UserDefaults.standard.dictionary(forKey: dismissedKey) as? [String: Double]) ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: dismissedKey) }
    }

    @discardableResult
    static func sync(jars: [Jar], entries: [DoseEntry], discreet: DiscreetSettings?) -> Task<Void, Never>? {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return nil }
        let now = Date()
        let running = activeDoses(jars: jars, entries: entries, now: now)
        let all = Activity<DoseActivityAttributes>.activities
        let current = all.filter { $0.activityState == .active || $0.activityState == .stale }

        // Swiped away: keep those doses off the Lock Screen for the rest of their effect.
        var gone = dismissed.filter { $0.value > now.timeIntervalSince1970 }
        for a in all where a.activityState == .dismissed {
            for d in a.content.state.doses where d.end > now { gone[d.id] = d.end.timeIntervalSince1970 }
        }
        let wasShowing = shown
        if current.isEmpty && !wasShowing.isEmpty {
            for d in running where wasShowing.contains(d.id) { gone[d.id] = d.end.timeIntervalSince1970 }
        }
        dismissed = gone

        let doses = running.filter { gone[$0.id] == nil }
        let state = DoseActivityAttributes.ContentState(doses: doses, discreet: discreet, updated: now)
        let next = nextChange(doses: doses, discreet: discreet, after: now)
        let stale = next ?? doses.map(\.end).max()
        scheduleRefresh(at: next)
        let ids = doses.map(\.id)
        let task = Task { @MainActor in
            if doses.isEmpty {
                for activity in current { await activity.end(nil, dismissalPolicy: .immediate) }
                shown = []
                return
            }
            if let activity = current.first {
                await activity.update(ActivityContent(state: state, staleDate: stale))
                for extra in current.dropFirst() { await extra.end(nil, dismissalPolicy: .immediate) }
                shown = ids
            } else if (try? Activity.request(attributes: DoseActivityAttributes(),
                                             content: ActivityContent(state: state, staleDate: stale),
                                             pushType: nil)) != nil {
                shown = ids
            } else {
                shown = []
            }
        }
        lastSync = task
        return task
    }

    // MARK: Background refresh

    /// Registers the background refresh. iOS needs this before launch finishes.
    static func registerBackground() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskId, using: nil) { task in
            Task { @MainActor in handle(task) }
        }
    }

    private static func scheduleRefresh(at date: Date?) {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskId)
        guard let date else { return }
        let request = BGAppRefreshTaskRequest(identifier: taskId)
        request.earliestBeginDate = date
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(_ task: BGTask) {
        let work = Task { @MainActor in
            let store = AppStore.shared
            store.reload()
            await sync(jars: store.jars, entries: store.entries, discreet: store.settings.discreet)?.value
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { work.cancel() }
    }
}
