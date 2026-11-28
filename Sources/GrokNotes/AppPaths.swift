import Foundation

enum AppPaths {
    /// ~/Library/Application Support/GrokNotes. Demo builds use a throwaway folder instead.
    static let support: URL = {
        #if GROKNOLA_DEMO
        return DemoMode.dataRoot
        #else
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GrokNotes", isDirectory: true)
        #endif
    }()
}
