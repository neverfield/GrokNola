#if GROKNOLA_DEMO
import AppKit
import Foundation

/// Screenshot builds only (`GROKNOLA_DEMO=1 ./scripts/build-app.sh`, run by `scripts/take-screenshots.sh`).
/// Made-up meetings live in a throwaway folder, the Keychain is in memory, the calendar is made up, and one scene
/// opens, so the real data, Keychain, settings, and calendar are never read or written.
enum DemoMode {
    enum Scene: String {
        case home, notes, transcript, ask
        case meetingAsk = "meeting-ask"
    }

    /// Always `$TMPDIR/groknola-demo`: `prepare` deletes and refills it, so it is never taken from the environment.
    static let dataRoot = FileManager.default.temporaryDirectory.appendingPathComponent("groknola-demo", isDirectory: true)
    static let scene = Scene(rawValue: ProcessInfo.processInfo.environment["GROKNOLA_DEMO_SCENE"] ?? "") ?? .notes
    static let dark = ProcessInfo.processInfo.environment["GROKNOLA_DEMO_APPEARANCE"] == "dark"
    static let calendar = DemoCalendar(events: DemoData.events(now: Date()))

    static var initialTab: MeetingDetailView.Tab {
        switch scene {
        case .transcript: .transcript
        case .meetingAsk: .ask
        case .home, .notes, .ask: .notes
        }
    }

    /// Replaces the demo folder and settings with the made-up library. Runs before `AppState` loads.
    static func prepare() {
        guard let bundleID = Bundle.main.bundleIdentifier, bundleID.hasSuffix(".demo") else {
            fatalError("A demo build must run with a .demo bundle ID, so it never touches the real settings.")
        }
        let fm = FileManager.default
        try? fm.removeItem(at: dataRoot)
        try? fm.createDirectory(at: dataRoot, withIntermediateDirectories: true)

        let defaults = UserDefaults.standard
        defaults.removePersistentDomain(forName: bundleID)
        defaults.set(DemoData.myName, forKey: "myName")
        defaults.set("example.com", forKey: "companyDomains")
        Keychain.set("xai-demo-not-a-real-key", for: XAIClient.keychainAccount)

        let now = Date()
        let store = MeetingStore()
        for meeting in DemoData.meetings(now: now) {
            try? store.save(meeting)
        }
        if let chat = try? JSONEncoder().encode(DemoData.libraryChat(now: now)) {
            try? chat.write(to: AppPaths.support.appendingPathComponent("library-chat.json"))
        }
        if let usage = UsageLedger.lines(DemoData.usage(now: now)) {
            try? usage.write(to: AppPaths.support.appendingPathComponent("usage.jsonl"))
        }
    }

    /// Opens the scene, sizes the window, then writes its window number for `screencapture -l`.
    @MainActor
    static func show(_ state: AppState) async {
        NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        switch scene {
        case .home: state.openHome()
        case .ask: state.openLibraryChat()
        case .notes, .meetingAsk: state.openMeeting(DemoData.heroID)
        case .transcript: state.openTranscript(DemoData.heroID, at: DemoData.transcriptFocus)
        }
        try? await Task.sleep(for: .milliseconds(500))
        let windows = NSApp.windows.filter { $0.isVisible && $0.styleMask.contains(.titled) }
        guard let window = windows.max(by: { $0.frame.width < $1.frame.width }) else { return }
        window.setContentSize(NSSize(width: 1440, height: 900))
        window.center()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        try? await Task.sleep(for: .seconds(2))
        try? "\(window.windowNumber)".write(to: dataRoot.appendingPathComponent("window-id"), atomically: true, encoding: .utf8)
    }
}

struct DemoCalendar: CalendarSource {
    let all: [CalendarEvent]

    init(events: [CalendarEvent]) {
        all = events
    }

    func events(from start: Date, to end: Date) -> [CalendarEvent] {
        all.filter { $0.end > start && $0.start < end }
    }
}

/// Holds items in memory for the life of the process, in place of the login Keychain.
enum Keychain {
    private static let lock = NSLock()
    private static var items: [String: Data] = [:]

    static func get(_ account: String) -> String? {
        lock.withLock { items[account] }.flatMap { String(data: $0, encoding: .utf8) }
    }

    static func set(_ value: String, for account: String) {
        lock.withLock { items[account] = value.isEmpty ? nil : Data(value.utf8) }
    }

    static func data(for account: String) throws -> Data? {
        lock.withLock { items[account] }
    }

    static func add(_ data: Data, for account: String) throws {
        lock.withLock {
            if items[account] == nil { items[account] = data }
        }
    }

    static func delete(_ account: String) {
        lock.withLock { items[account] = nil }
    }
}
#endif
