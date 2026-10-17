import Foundation
import HealthKit
import BackgroundTasks

/// Watches Apple Health sleep data for a wake-up between 5 AM and 12 PM, then sends the reminder for doses
/// taken upon waking. iOS wakes the app when new sleep data is saved (background delivery), a background refresh
/// checks again as often as iOS allows, and opening the app always checks.
@MainActor
enum WakeDetector {
    static let taskId = "com.medjars.app.wakecheck"
    private static let health = HKHealthStore()
    private static var observing = false
    /// Whether iOS agreed to wake the app for new sleep data. Nil until it answers.
    private(set) static var instantUpdates: Bool?

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }
    private static var sleepType: HKCategoryType { HKCategoryType(.sleepAnalysis) }

    /// At launch: registers the background check (iOS needs this before launch finishes) and starts watching if needed.
    static func launch() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskId, using: nil) { task in
            Task { @MainActor in handle(task) }
        }
        refresh()
    }

    /// Starts watching when any jar has a dose taken upon waking, and checks right away.
    static func refresh() {
        guard isAvailable, AppStore.shared.hasWakingDoses else { return }
        startObserving()
        scheduleCheck()
        Task { await check() }
    }

    /// Asks to read sleep data from Apple Health.
    @discardableResult
    static func requestAccess() async -> Bool {
        await requestAccessError() == nil
    }

    /// Asks to read sleep data. Returns why it failed, or nil when iOS took the request.
    static func requestAccessError() async -> String? {
        guard isAvailable else { return "Apple Health isn't available on this device." }
        do {
            try await health.requestAuthorization(toShare: [], read: [sleepType])
            refresh()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Whether iOS will still show the Apple Health permission screen. It only shows once; after that, access
    /// is changed in the Health app.
    static func needsAsking() async -> Bool {
        guard isAvailable else { return false }
        let status = try? await health.statusForAuthorizationRequest(toShare: [], read: [sleepType])
        return status == .shouldRequest
    }

    /// The end of the most recent sleep in Apple Health from the last week, if Med Jars can see any.
    static func lastSleepEnd(days: Int = 7) async -> Date? {
        guard isAvailable else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: Date().addingTimeInterval(-Double(days) * 86400), end: Date(), options: [])
        let descriptor = HKSampleQueryDescriptor(predicates: [.categorySample(type: sleepType, predicate: predicate)],
                                                 sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)], limit: 100)
        guard let samples = try? await descriptor.result(for: health) else { return nil }
        return samples.first(where: { isAsleep($0.value) })?.endDate
    }

    private static func startObserving() {
        guard !observing else { return }
        observing = true
        let query = HKObserverQuery(sampleType: sleepType, predicate: nil) { _, completion, error in
            Task { @MainActor in
                if error == nil { await check() }
                completion()
            }
        }
        health.execute(query)
        health.enableBackgroundDelivery(for: sleepType, frequency: .immediate) { ok, _ in
            Task { @MainActor in instantUpdates = ok }
        }
    }

    /// Looks for today's wake-up: the end of the most recent asleep sample, if it falls between 5 AM and 12 PM.
    static func check(now: Date = Date()) async {
        let cal = Calendar.current
        guard let start = cal.date(bySettingHour: 5, minute: 0, second: 0, of: now),
              let end = cal.date(bySettingHour: 12, minute: 0, second: 0, of: now),
              now >= start, AppStore.shared.wakeTime(on: now) == nil else { return }
        let predicate = HKQuery.predicateForSamples(withStart: start.addingTimeInterval(-14 * 3600), end: now, options: [])
        let descriptor = HKSampleQueryDescriptor(predicates: [.categorySample(type: sleepType, predicate: predicate)],
                                                 sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)], limit: 300)
        guard let samples = try? await descriptor.result(for: health) else { return }
        guard let last = samples.first(where: { isAsleep($0.value) }),
              last.endDate >= start, last.endDate <= end, last.endDate <= now else { return }
        AppStore.shared.recordWake(last.endDate)
    }

    private static func isAsleep(_ value: Int) -> Bool {
        guard let v = HKCategoryValueSleepAnalysis(rawValue: value) else { return false }
        switch v {
        case .inBed, .awake: return false
        default: return true
        }
    }

    /// Asks iOS for the next background check: every 5 minutes between 5 AM and 12 PM until the wake-up is seen,
    /// otherwise 5 AM tomorrow. iOS decides when it actually runs.
    static func scheduleCheck(now: Date = Date()) {
        let cal = Calendar.current
        guard let start = cal.date(bySettingHour: 5, minute: 0, second: 0, of: now),
              let end = cal.date(bySettingHour: 12, minute: 0, second: 0, of: now) else { return }
        let next: Date
        if now < start {
            next = start
        } else if now < end && AppStore.shared.wakeTime(on: now) == nil {
            next = now.addingTimeInterval(5 * 60)
        } else {
            next = cal.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86400)
        }
        let request = BGAppRefreshTaskRequest(identifier: taskId)
        request.earliestBeginDate = next
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(_ task: BGTask) {
        scheduleCheck()
        let work = Task { @MainActor in
            AppStore.shared.reload()
            await check()
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { work.cancel() }
    }
}
