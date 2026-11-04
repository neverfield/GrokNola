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

    private static let maxNodesPerPoll = 6_000
    private static let patterns: [NSRegularExpression] = [
        #"^talking:\s*(.+)$"#,
        #"^speaking:\s*(.+)$"#,
        #"^(.+?)\s+is\s+(?:speaking|talking)\.?$"#,
        #"^(.+?),\s*(?:speaking|talking)\b.*$"#,
        #"^(.+?)\s*\((?:speaking|talking)\)$"#,
    ].map { try! NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }

    private let pid: pid_t
    private let isBrowser: Bool
    private let meetingStart: Date
    private let ignoredNames: Set<String>
    private let queue = DispatchQueue(label: "groknotes.ax")
    private let lock = NSLock()
    private var timer: DispatchSourceTimer?
    private var recorded: [Sample] = []
    private var nameCounts: [String: Int] = [:]

    init(app: MeetingDetector.App, meetingStart: Date, ignoredNames: [String]) {
        pid = app.pid
        isBrowser = app.isBrowser
        self.meetingStart = meetingStart
        self.ignoredNames = Set(ignoredNames.map { $0.lowercased() })
    }

    var samples: [Sample] { lock.withLock { recorded } }

    /// Names the meeting app showed as talking, most frequent first.
    var observedNames: [String] {
        lock.withLock { nameCounts.sorted { $0.value > $1.value }.map(\.key) }
    }

    func begin() {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        // Electron (Slack, Teams) and Chromium build their accessibility trees only when asked.
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        if isBrowser {
            AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in self?.poll(app) }
        timer.resume()
        self.timer = timer
    }

    func end() {
        timer?.cancel()
        timer = nil
    }

    private func poll(_ app: AXUIElement) {
        let time = Date().timeIntervalSince(meetingStart)
        var speaking = Set<String>()
        for window in Self.elements(app, kAXWindowsAttribute) {
            if isBrowser, let title = Self.string(window, kAXTitleAttribute), !title.localizedCaseInsensitiveContains("meet") {
                continue
            }
            scan(window) { text in
                if let name = Self.speakerName(in: text), !ignoredNames.contains(name.lowercased()) {
                    speaking.insert(name)
                }
            }
        }
        lock.withLock {
            recorded.append(Sample(time: time, speaking: Array(speaking)))
            for name in speaking { nameCounts[name, default: 0] += 1 }
        }
    }

    private func scan(_ root: AXUIElement, visit: (String) -> Void) {
        var pending = [root]
        var index = 0
        while index < pending.count, index < Self.maxNodesPerPoll {
            let element = pending[index]
            index += 1
            for attribute in [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXHelpAttribute] {
                if let text = Self.string(element, attribute), !text.isEmpty, text.count < 200 { visit(text) }
            }
            pending += Self.elements(element, kAXChildrenAttribute)
        }
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

    private static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }
}
