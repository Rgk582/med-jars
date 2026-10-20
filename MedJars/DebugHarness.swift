#if DEBUG
import Foundation
import UIKit

/// Test-only helpers for the full simulator test run. Never part of a release build.
/// - `-seedFullTest`: replaces the saved data with the seed file before anything loads.
/// - Writes perf.log (main-thread hangs, persist timing, memory, schedule work per second) and stdout.log
///   (SwiftUI `_printChanges` output) to PERF_DIR, or Documents when that isn't reachable.
enum DebugHarness {
    nonisolated(unsafe) static var bodyCount = 0
    nonisolated(unsafe) static var bodies: [String: Int] = [:]
    private nonisolated(unsafe) static var started = false
    private nonisolated(unsafe) static var logURL: URL?
    private static let lock = NSLock()
    private static let t0 = Date()

    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("-perfHarness") }

    /// Counts a view body evaluation. Use as `let _ = DebugHarness.body("Name")`.
    @discardableResult
    static func body(_ name: String) -> Int {
        guard logURL != nil else { return 0 }
        lock.lock()
        bodyCount += 1
        bodies[name, default: 0] += 1
        lock.unlock()
        return 0
    }

    /// Called first thing in AppStore.init.
    static func prepare() {
        guard !started else { return }
        started = true
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-perfHarness") || args.contains("-seedFullTest") else { return }
        let dir = outputDir()
        logURL = dir.appendingPathComponent("perf.log")
        if args.contains("-captureStdout") {
            let out = dir.appendingPathComponent("stdout.log").path
            _ = freopen(out, "a+", stdout)
            setvbuf(stdout, nil, _IOLBF, 0)
        }
        log("LAUNCH args=\(args.dropFirst().joined(separator: " "))")
        if args.contains("-seedFullTest") { seed() }
        if args.contains("-perfHarness") { startWatchdog() }
        if let i = args.firstIndex(of: "-autopilot"), i + 1 < args.count {
            let name = args[i + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                Task { @MainActor in await Autopilot.run(name) }
            }
        }
    }

    private static func outputDir() -> URL {
        let fm = FileManager.default
        if let p = ProcessInfo.processInfo.environment["PERF_DIR"], !p.isEmpty {
            let url = URL(fileURLWithPath: p)
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
            let probe = url.appendingPathComponent(".probe")
            if (try? Data("ok".utf8).write(to: probe)) != nil {
                try? fm.removeItem(at: probe)
                return url
            }
        }
        return fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static func log(_ line: String) {
        guard let logURL else { return }
        let t = String(format: "%.3f", Date().timeIntervalSince(t0))
        let text = "\(Date().timeIntervalSince1970) +\(t) \(line)\n"
        lock.lock(); defer { lock.unlock() }
        if let h = try? FileHandle(forWritingTo: logURL) {
            h.seekToEndOfFile()
            h.write(Data(text.utf8))
            try? h.close()
        } else {
            try? Data(text.utf8).write(to: logURL)
        }
    }

    /// Times a block and logs it when it takes 4 ms or more.
    @discardableResult
    static func measure<T>(_ name: String, _ body: () throws -> T) rethrows -> T {
        guard logURL != nil else { return try body() }
        let s = CFAbsoluteTimeGetCurrent()
        let r = try body()
        let ms = (CFAbsoluteTimeGetCurrent() - s) * 1000
        if ms >= 4 { log(String(format: "TIME %@ %.1fms", name, ms)) }
        return r
    }

    // MARK: Seed

    private static func seed() {
        let env = ProcessInfo.processInfo.environment
        var candidates: [URL] = []
        if let p = env["SEED_PATH"], !p.isEmpty { candidates.append(URL(fileURLWithPath: p)) }
        candidates.append(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("seed.json"))
        for url in candidates {
            guard let data = try? Data(contentsOf: url) else { continue }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .secondsSince1970
            do {
                let file = try decoder.decode(StoreFile.self, from: data)
                try StoreIO.save(file)
                log("SEED OK from \(url.path): \(file.jars.count) jars, \(file.entries.count) entries, \(file.stacks.count) stacks")
                return
            } catch {
                log("SEED ERROR \(url.path): \(error)")
            }
        }
        log("SEED ERROR no seed file found")
    }

    // MARK: Watchdog

    private static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
    }

    private static func startWatchdog() {
        let thread = Thread {
            var lastStats = Date()
            var lastRows = 0
            var lastBodies = 0
            while true {
                let sem = DispatchSemaphore(value: 0)
                let sent = CFAbsoluteTimeGetCurrent()
                DispatchQueue.main.async { sem.signal() }
                if sem.wait(timeout: .now() + 0.25) == .timedOut {
                    sem.wait()
                    let ms = (CFAbsoluteTimeGetCurrent() - sent) * 1000
                    log(String(format: "HANG %.0fms", ms))
                }
                if Date().timeIntervalSince(lastStats) >= 5 {
                    lock.lock()
                    let top = bodies.sorted { $0.value > $1.value }.prefix(8).map { "\($0.key)=\($0.value)" }.joined(separator: ",")
                    bodies = [:]
                    let b = bodyCount
                    lock.unlock()
                    let rows = DebugCounters.rows
                    log(String(format: "STATS mem=%.1fMB rows/5s=%d bodies/5s=%d top=%@", footprintMB(), rows - lastRows, b - lastBodies, top))
                    lastRows = rows; lastBodies = b
                    lastStats = Date()
                }
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
        thread.name = "perf-watchdog"
        thread.qualityOfService = .userInteractive
        thread.start()
    }
}

// MARK: - Autopilot (in-app scenarios with no test tool attached)

/// Measures frame pacing with a display link: frames, hitches (a frame 1.5x late or worse), hitch time and the worst frame.
@MainActor
final class FrameMonitor: NSObject {
    static let shared = FrameMonitor()
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private var frames = 0, hitches = 0
    private var worst: Double = 0, hitchTime: Double = 0, total: Double = 0
    var onFrame: ((CFTimeInterval) -> Void)?

    func start() {
        frames = 0; hitches = 0; worst = 0; hitchTime = 0; total = 0; last = 0
        let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
        l.add(to: .main, forMode: .common)
        link = l
    }

    @objc private func tick(_ l: CADisplayLink) {
        let now = l.timestamp
        if last > 0 {
            let dt = now - last
            let expected = l.duration > 0 ? l.duration : 1.0 / 60
            frames += 1
            total += dt
            if dt > expected * 1.5 { hitches += 1; hitchTime += dt - expected }
            worst = max(worst, dt)
        }
        last = now
        onFrame?(now)
    }

    func stop() -> String {
        link?.invalidate(); link = nil; onFrame = nil
        return String(format: "frames=%d hitches=%d hitchRatio=%.1fms/s worst=%.0fms", frames, hitches,
                      total > 0 ? hitchTime * 1000 / total : 0, worst * 1000)
    }
}

@MainActor
enum Autopilot {
    static var store: AppStore { AppStore.shared }
    static var router: Router { Router.shared }

    static func pause(_ s: Double) async { try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000)) }

    static func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first { $0.isKeyWindow }
    }

    /// The biggest scrollable view on screen.
    static func visibleScrollView() -> UIScrollView? {
        guard let window = keyWindow() else { return nil }
        var best: UIScrollView?
        var bestArea: CGFloat = 0
        func walk(_ v: UIView) {
            if v.isHidden || v.alpha < 0.01 { return }
            if let s = v as? UIScrollView, s.contentSize.height > s.bounds.height + 40 {
                let f = s.convert(s.bounds, to: window).intersection(window.bounds)
                let area = f.isNull ? 0 : f.width * f.height
                if area > bestArea { best = s; bestArea = area }
            }
            for sub in v.subviews { walk(sub) }
        }
        walk(window)
        return best
    }

    static func go(_ screen: String) async {
        router.homePath = []; router.path = []; router.schedulePath = []; router.stacksPath = []
        switch screen {
        case "home": router.tab = .home
        case "schedule": router.tab = .schedule
        case "cabinet": router.tab = .cabinet
        case "stacks": router.tab = .stacks
        case "history": router.tab = .cabinet; await pause(0.5); router.path = [.history]
        case "page": router.tab = .cabinet; await pause(0.5); router.path = [.jar("adderall")]
        case "settings": router.tab = .home; await pause(0.5); router.homePath = [.settings]
        default: router.tab = .home
        }
        await pause(2)
    }

    /// Scrolls the screen top to bottom and back once a second, every frame, like a fast finger.
    static func scroll(seconds: Double, period: Double = 1.0) async {
        guard let s = visibleScrollView() else { DebugHarness.log("AUTOPILOT no scroll view"); await pause(seconds); return }
        DebugHarness.log(String(format: "AUTOPILOT scrolling %@ content=%.0f", String(describing: type(of: s)), s.contentSize.height))
        let top = -s.adjustedContentInset.top
        let bottom = max(top, s.contentSize.height - s.bounds.height + s.adjustedContentInset.bottom)
        var t0: CFTimeInterval = 0
        FrameMonitor.shared.onFrame = { [weak s] now in
            guard let s else { return }
            if t0 == 0 { t0 = now }
            let phase = (now - t0) / period
            let y = top + (1 - cos(2 * .pi * phase)) / 2 * (bottom - top)
            s.setContentOffset(CGPoint(x: s.contentOffset.x, y: y), animated: false)
        }
        await pause(seconds)
        FrameMonitor.shared.onFrame = nil
        s.setContentOffset(CGPoint(x: 0, y: top), animated: false)
    }

    static func presentCheck(_ label: String) async {
        DebugHarness.log("AUTOPILOT present-check \(label) begin")
        router.logRequest = LogTarget(jarId: "fish-oil")
        await pause(2)
        DebugHarness.log("AUTOPILOT present-check \(label) logRequest=\(router.logRequest == nil ? "nil" : "set")")
        router.logRequest = nil
        await pause(1.5)
    }

    static func logUndo(_ n: Int, gap: Double) async {
        for _ in 0..<n {
            if let e = store.log(jarId: "fish-oil", slot: nil, amount: "", pills: 1, at: Date()) {
                await pause(gap)
                store.undoLog(e.id)
            }
            await pause(gap)
        }
    }

    static func run(_ name: String) async {
        DebugHarness.log("AUTOPILOT BEGIN \(name)")
        let parts = name.split(separator: ":").map(String.init)
        let kind = parts[0]
        let target = parts.count > 1 ? parts[1] : "home"
        if kind != "idle" { await go(target) }
        FrameMonitor.shared.start()
        let start = CFAbsoluteTimeGetCurrent()
        switch kind {
        case "scroll":
            await scroll(seconds: 12)
        case "tabs":
            let tabs: [AppTab] = [.home, .cabinet, .schedule, .stacks]
            for i in 0..<48 { router.tab = tabs[i % 4]; await pause(0.25) }
        case "logundo":
            await logUndo(15, gap: 0.35)
        case "reload":
            for _ in 0..<15 {
                store.reload()
                Reminders.reschedule(jars: store.jars, entries: store.entries, planned: store.planned, enabled: true, grouped: true)
                LiveDoses.sync(jars: store.jars, entries: store.entries, discreet: store.settings.discreet)
                await pause(0.4)
            }
        case "sheets":
            for _ in 0..<12 {
                router.logRequest = LogTarget(jarId: "fish-oil")
                await pause(0.6)
                router.logRequest = nil
                await pause(0.6)
            }
        case "chaos":
            let scrollTask = Task { @MainActor in await scroll(seconds: 20, period: 0.8) }
            let tabs: [AppTab] = [.home, .schedule, .cabinet, .home]
            for i in 0..<20 {
                if let e = store.log(jarId: "fish-oil", slot: nil, amount: "", pills: 1, at: Date()) {
                    await pause(0.25)
                    store.undoLog(e.id)
                }
                if i % 3 == 0 { router.tab = tabs[(i / 3) % 4] }
                if i % 4 == 1 { router.logRequest = LogTarget(jarId: "vitamin-d3") }
                if i % 4 == 2 { router.logRequest = nil }
                await pause(0.75)
            }
            await scrollTask.value
            router.logRequest = nil
        case "idle":
            await pause(15)
        default:
            await pause(5)
        }
        let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
        let stats = FrameMonitor.shared.stop()
        DebugHarness.log(String(format: "AUTOPILOT RESULT %@ %@ elapsed=%.0fms", name, stats, ms))
        await pause(1)
        await presentCheck(name)
        DebugHarness.log("AUTOPILOT END \(name)")
    }
}
#endif
