import ApplicationServices
import Foundation

/// Reads the meeting app's accessibility tree once a second and records who the app
/// says is talking ("Talking: Ana", "Ana is speaking", and similar labels).
/// The samples are matched against diarized speech to put real names on remote speakers.
final class ActiveSpeakerMonitor {
    struct Sample {
        let time: Double
        let speaking: [String]
    }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestTrust() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Elements read per poll, across all windows.
    private static let maxNodesPerPoll = 6_000
    /// Windows read per poll for an app whose call window has no known title.
    static let maxUntitledWindowsPerPoll = 3
    private static let manualAccessibility = "AXManualAccessibility"
    private static let enhancedUserInterface = "AXEnhancedUserInterface"
    private static let patterns: [NSRegularExpression] = [
        #"^talking:\s*(.+)$"#,
        #"^speaking:\s*(.+)$"#,
        #"^(.+?)\s+is\s+(?:speaking|talking)\.?$"#,
        #"^(.+?),\s*(?:speaking|talking)\b.*$"#,
        #"^(.+?)\s*\((?:speaking|talking)\)$"#,
    ].map { try! NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }

    private let pid: pid_t
    private let bundleID: String
    private let isBrowser: Bool
    private let meetingStart: Date
    private let ignoredNames: Set<String>
    private let queue = DispatchQueue(label: "groknotes.ax")
    private let lock = NSLock()
    private var timer: DispatchSourceTimer?
    private var element: AXUIElement?
    /// The app's accessibility switches before `begin()` turned them on, restored by `end()`.
    private var priorSwitches: [String: Bool] = [:]
    private var recorded: [Sample] = []
    private var nameCounts: [String: Int] = [:]

    init(app: MeetingDetector.App, meetingStart: Date, ignoredNames: [String]) {
        pid = app.pid
        bundleID = app.bundleID
        isBrowser = app.isBrowser
        self.meetingStart = meetingStart
        self.ignoredNames = Set(ignoredNames.map { $0.lowercased() })
    }

    var samples: [Sample] { lock.withLock { recorded } }

    /// Samples recorded at or after `index`, and the index to pass next time.
    func samples(from index: Int) -> (samples: [Sample], next: Int) {
        lock.withLock {
            let start = min(max(index, 0), recorded.count)
            return (Array(recorded[start...]), recorded.count)
        }
    }

    /// The one person the meeting app shows as talking right now, or nil when it shows nobody, several people,
    /// or has not been read for `maxAge` seconds.
    ///
    /// **Lag and stickiness:** Polling runs once per second, so the label can trail the actual speaker by up to
    /// ~1s plus UI delay. If the app shows multiple talkers or none, this returns nil until a single name is shown
    /// again. Samples older than `maxAge` are ignored, so attribution drops to nil shortly after the UI clears.
    func currentTalker(maxAge: TimeInterval = 2.5) -> String? {
        let now = Date().timeIntervalSince(meetingStart)
        return lock.withLock {
            guard let last = recorded.last, now - last.time <= maxAge, last.speaking.count == 1 else { return nil }
            return last.speaking[0]
        }
    }

    /// Names the meeting app showed as talking, most frequent first.
    var observedNames: [String] {
        lock.withLock { nameCounts.sorted { $0.value > $1.value }.map(\.key) }
    }

    /// Starts polling. Call `end()` to stop and put the app's accessibility switches back.
    func begin() {
        guard element == nil else { return }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        element = app
        // Electron (Slack, Teams) and Chromium build their accessibility trees only when asked.
        var switches = [Self.manualAccessibility]
        if isBrowser { switches.append(Self.enhancedUserInterface) }
        for name in switches {
            priorSwitches[name] = Self.bool(app, name) ?? false
            AXUIElementSetAttributeValue(app, name as CFString, kCFBooleanTrue)
        }
        startTimer()
    }

    /// Stops polling and restores the switches `begin()` changed.
    func end() {
        stopTimer()
        guard let app = element else { return }
        element = nil
        let switches = priorSwitches
        priorSwitches = [:]
        queue.async {
            for (name, value) in switches {
                AXUIElementSetAttributeValue(app, name as CFString, value ? kCFBooleanTrue : kCFBooleanFalse)
            }
        }
    }

    /// Stops reading the app while the recording is paused.
    func pause() { stopTimer() }

    func resume() {
        guard element != nil, timer == nil else { return }
        startTimer()
    }

    private func startTimer() {
        guard let app = element else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in self?.poll(app) }
        timer.resume()
        self.timer = timer
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }

    /// Whether to read a window. Apps with a known call-window title are read only in that window; other apps
    /// have every window read, up to `maxUntitledWindowsPerPoll`.
    static func shouldScan(windowTitle: String?, bundleID: String, isBrowser: Bool) -> Bool {
        MeetingDetector.isCallWindowTitle(windowTitle ?? "", bundleID: bundleID, isBrowser: isBrowser) ?? true
    }

    private func poll(_ app: AXUIElement) {
        let time = Date().timeIntervalSince(meetingStart)
        var speaking = Set<String>()
        var budget = Self.maxNodesPerPoll
        let hasCallTitle = MeetingDetector.knowsCallWindowTitle(bundleID: bundleID, isBrowser: isBrowser)
        var windows = Self.elements(app, kAXWindowsAttribute).filter {
            Self.shouldScan(windowTitle: Self.string($0, kAXTitleAttribute), bundleID: bundleID, isBrowser: isBrowser)
        }
        if !hasCallTitle { windows = Array(windows.prefix(Self.maxUntitledWindowsPerPoll)) }
        for window in windows where budget > 0 {
            budget -= scan(window, budget: budget) { text in
                if let name = Self.speakerName(in: text), SpeakerResolver.isPlausibleName(name),
                   !ignoredNames.contains(name.lowercased()) {
                    speaking.insert(name)
                }
            }
        }
        lock.withLock {
            recorded.append(Sample(time: time, speaking: Array(speaking)))
            for name in speaking { nameCounts[name, default: 0] += 1 }
        }
    }

    /// Reads up to `budget` elements under `root`, breadth first, and returns how many it read.
    private func scan(_ root: AXUIElement, budget: Int, visit: (String) -> Void) -> Int {
        var pending = [root]
        var index = 0
        while index < pending.count, index < budget {
            let element = pending[index]
            index += 1
            for attribute in [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXHelpAttribute] {
                if let text = Self.string(element, attribute), !text.isEmpty, text.count < 200 { visit(text) }
            }
            pending += Self.elements(element, kAXChildrenAttribute)
        }
        return index
    }

    static func speakerName(in text: String) -> String? {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(s.startIndex..., in: s)
        for pattern in patterns {
            if let match = pattern.firstMatch(in: s, range: range), let r = Range(match.range(at: 1), in: s) {
                return clean(String(s[r]))
            }
        }
        return nil
    }

    private static func clean(_ raw: String) -> String? {
        var name = raw.replacingOccurrences(
            of: #"\s*\((?:host|co-host|guest|me|you|external|organi[sz]er)\)"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        name = name.trimmingCharacters(in: CharacterSet.whitespaces.union(.punctuationCharacters))
        // Several names at once ("Ana, Bo") cannot be attributed to one voice.
        guard (2...60).contains(name.count), !name.contains(","), name.rangeOfCharacter(from: .letters) != nil else { return nil }
        if ["you", "me", "someone", "no one", "nobody"].contains(name.lowercased()) { return nil }
        return name
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return (value as? NSNumber)?.boolValue
    }

    private static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }
}
