import Foundation

/// Debug counters for expensive view work. Set `GROKNOTES_PERF=1` in a debug build to log every hit,
/// for example to check that a recording tick does not regroup the sidebar or rebuild Home.
enum PerfProbe {
    #if DEBUG
    private static let enabled = ProcessInfo.processInfo.environment["GROKNOTES_PERF"] == "1"
    private static let lock = NSLock()
    nonisolated(unsafe) private static var counts: [String: Int] = [:]
    #endif

    @inline(__always)
    static func hit(_ name: String) {
        #if DEBUG
        guard enabled else { return }
        let count = lock.withLock {
            counts[name, default: 0] += 1
            return counts[name] ?? 0
        }
        NSLog("GrokNotes perf: %@ #%d", name, count)
        #endif
    }
}
