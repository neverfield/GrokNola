import Foundation

/// The user guide that Ask Grok answers app questions from: `Resources/Help/GrokNotesGuide.md`,
/// copied into the app bundle by `scripts/build-app.sh`.
enum HelpGuide {
    static let fileName = "GrokNotesGuide"

    /// The bundled guide, else the source copy next to a `swift run` build, else `fallback`.
    static let text: String = url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? fallback

    static var url: URL? {
        if let bundled = Bundle.main.url(forResource: fileName, withExtension: "md", subdirectory: "Help") {
            return bundled
        }
        // `swift run` puts the binary in .build/<triple>/<config>/; the guide is under the package root.
        var dir = Bundle.main.executableURL?.resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<5 {
            guard let current = dir else { break }
            let candidate = current.appendingPathComponent("Resources/Help/\(fileName).md")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            dir = current.deletingLastPathComponent()
        }
        return nil
    }

    private static let fallback = """
    # Grok Notes (short guide)

    The full user guide is missing from this build, so only the basics are known.

    - Add your xAI API key in **Settings > Models & API** (Command-comma).
    - Grant **Microphone**, **Screen & System Audio Recording** (then relaunch), **Accessibility**, and optionally **Apple Calendar** in **Settings > Recording**.
    - Click **Start notes** (Shift-Command-R) when a call starts, type rough notes, and click **Stop**. Grok writes enhanced notes and names speakers.
    - **Ask Grok** in the sidebar (Command-K) answers across all meetings. **Home** is Shift-Command-H. **Usage & Cost** is Shift-Command-U.
    - Data lives in ~/Library/Application Support/GrokNotes/.
    """
}

/// `groknotes://` links that open places in the app, for help answers.
enum AppLink: Equatable {
    case settings
    case usage
    case home
    /// A System Settings > Privacy & Security pane, by its anchor.
    case privacy(String)

    static let privacyPanes: [String: String] = [
        "microphone": "Privacy_Microphone",
        "screen-recording": "Privacy_ScreenCapture",
        "accessibility": "Privacy_Accessibility",
        "calendars": "Privacy_Calendars",
    ]

    init?(_ url: URL) {
        guard url.scheme == LibraryAsk.linkScheme, let host = url.host else { return nil }
        switch host {
        case "settings": self = .settings
        case "usage": self = .usage
        case "home": self = .home
        case "privacy":
            guard let anchor = Self.privacyPanes[url.lastPathComponent] else { return nil }
            self = .privacy(anchor)
        default: return nil
        }
    }

    /// The link list given to the model in help answers.
    static let promptList = """
    [Open Settings](groknotes://settings), [Open Usage & Cost](groknotes://usage), [Open Home](groknotes://home), \
    and System Settings privacy panes: [Microphone](groknotes://privacy/microphone), \
    [Screen & System Audio Recording](groknotes://privacy/screen-recording), \
    [Accessibility](groknotes://privacy/accessibility), [Calendars](groknotes://privacy/calendars)
    """
}
