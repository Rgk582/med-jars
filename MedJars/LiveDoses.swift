import ActivityKit
import Foundation

/// Keeps one Live Activity showing every dose whose effect timeline is still running.
@MainActor
enum LiveDoses {
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

    static func sync(jars: [Jar], entries: [DoseEntry]) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let doses = activeDoses(jars: jars, entries: entries)
        let current = Activity<DoseActivityAttributes>.activities
        let state = DoseActivityAttributes.ContentState(doses: doses)
        let stale = doses.map(\.end).max()
        Task {
            if doses.isEmpty {
                for activity in current { await activity.end(nil, dismissalPolicy: .immediate) }
                return
            }
            if let activity = current.first {
                await activity.update(ActivityContent(state: state, staleDate: stale))
                for extra in current.dropFirst() { await extra.end(nil, dismissalPolicy: .immediate) }
            } else {
                _ = try? Activity.request(attributes: DoseActivityAttributes(),
                                          content: ActivityContent(state: state, staleDate: stale),
                                          pushType: nil)
            }
        }
    }
}
