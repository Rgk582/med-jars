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
#endif
