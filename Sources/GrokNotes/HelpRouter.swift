import Foundation

/// Decides, without a model call, whether an Ask Grok question is about the app, the user's meetings, or both.
/// Help-only questions skip meeting selection. Anything unclear gets both.
enum HelpRouter {
    enum Route: String {
        case help
        case meetings
        case both
    }

    /// Feature names and settings that almost always mean a question about the app.
    private static let appTerms: [String] = [
        "groknola", "grok nola", "grok notes", "groknotes", "this app", "the app", "in the app", "user guide",
        "setting", "settings", "preferences", "permission", "permissions", "accessibility",
        "screen recording", "screen & system audio", "system audio", "system settings", "privacy pane",
        "api key", "xai key", "keychain", "test connection", "echo cancellation", "10875", "diarization", "diarize",
        "speaker names", "speaker name", "name speakers", "rename a speaker", "rename speaker", "who is talking",
        "active speaker", "snapshots", "snapshot", "me them", "remembered people",
        "template", "templates", "regenerate", "enhanced notes", "rough notes", "my notes tab",
        "find chapters", "chapter timeline", "call summary card", "call summary", "citation", "citations", "timestamps",
        "clip", "clips", "keep audio", "playback", "player", "playback speed", "balance voices", "my voice",
        "transcript tab", "ask grok tab", "ask across notes", "new chat", "up next", "home dashboard",
        "trending topics", "suggest tags", "auto tag", "auto tagging", "tag all untagged", "suggested by grok",
        "tag catalog", "dynamic tags", "sidebar", "menu bar", "pin a meeting", "pinned",
        "google calendar", "apple calendar", "calendar json", "calendar source", "sync my calendar",
        "cursor", "loop 30m", "mcp", "google drive", "drive for desktop", "my drive",
        "usage cost", "usage window", "usage and cost", "api spend", "api cost",
        "shortcut", "shortcuts", "keyboard", "hotkey", "command k", "cmd k",
        "data folder", "stored", "storage", "application support", "auto delete", "retention",
        "signing", "signing cert", "certificate", "rebuild", "relaunch", "build app",
        "start notes", "meeting detection", "detect meetings", "detected", "notes model", "language code",
        "grok voice transcribe", "transcribe 2 0", "grok 4 7", "troubleshoot", "troubleshooting",
    ]

    /// Words that sometimes mean the app (a feature) and sometimes meeting content.
    private static let ambiguousTerms: [String] = [
        "calendar", "tag", "tags", "chapters", "chapter", "topics", "cost", "costs", "spend", "price", "home",
        "model", "record", "recording", "transcript", "audio", "microphone", "mic", "drive", "export",
        "search", "pin", "speaker", "speakers", "notes", "zoom", "teams", "meet", "slack", "webex", "facetime",
        "names", "usage", "headphones", "quiet",
    ]

    /// Question shapes typical of how-to and troubleshooting.
    private static let howPhrases: [String] = [
        "how do i", "how can i", "how do", "how does", "how to", "how should i set", "where is", "where are my",
        "where do i", "where can i", "where's", "why can't", "why cant", "why isn't", "why is", "why does",
        "why doesn't", "why won't", "why are", "is there a way", "is it possible", "can i", "what does",
        "what happens", "help", "not working", "doesn't work", "isn't working", "stopped working", "broken",
        "error", "turn on", "turn off", "enable", "disable", "set up", "setup", "configure", "change the",
        "missing", "stuck",
    ]

    /// Phrases about what happened in meetings.
    private static let meetingPhrases: [String] = [
        "did i", "did we", "did they", "did he", "did she", "who said", "said", "say about", "says",
        "mentioned", "mention", "discussed", "discuss", "talked about", "decided", "decide", "decision",
        "decisions", "agreed", "commit", "committed", "commitments", "promised", "action items", "follow up", "followup", "draft", "summarize", "summarise", "summary of", "recap", "last call",
        "last meeting", "last three", "my last", "recent", "most recent", "my meetings", "my calls",
        "meeting with", "meetings with", "call with", "calls with", "1 1 with", "this week", "last week",
        "yesterday", "today", "this morning", "customer", "customers", "client", "clients", "open questions",
        "next steps", "blockers", "who attended", "who was", "attendees", "when did", "how many meetings",
        "objection", "objections", "pricing", "deal", "roadmap", "standup", "sync with", "feedback",
    ]

    /// - Parameters:
    ///   - previous: The user's previous question in this chat, used when this one has no signals ("And on Teams?").
    ///   - people: Lowercased name tokens from meeting invitees and speakers. A mention points at meetings.
    static func route(_ question: String, previous: String? = nil, people: Set<String> = []) -> Route {
        let text = normalize(question)
        let raw = question.lowercased()
        var help = 0
        var meetings = 0

        help += min(count(appTerms, in: text), 2) * 3
        help += min(count(ambiguousTerms, in: text), 2)
        if count(howPhrases, in: text) > 0 { help += 1 }
        if raw.contains("⌘") { help += 3 }

        meetings += min(count(meetingPhrases, in: text), 3)
        let words = Set(text.split(separator: " ").map { $0.hasSuffix("'s") ? String($0.dropLast(2)) : String($0) })
        if !words.isDisjoint(with: people) { meetings += 2 }

        if help == 0, meetings == 0 {
            guard let previous else { return .both }
            return route(previous, people: people)
        }
        if meetings == 0 { return help >= 3 ? .help : .both }
        if help == 0 || (help <= 1 && meetings >= 2) { return .meetings }
        return .both
    }

    /// Name tokens (first and last names, three letters or more) for `route(_:previous:people:)`, without the user's own.
    static func peopleTokens(_ names: [String], excluding myName: String) -> Set<String> {
        let mine = Set(normalize(myName).split(separator: " ").map(String.init))
        let common = Set(appTerms + ambiguousTerms + meetingPhrases)
        var out = Set<String>()
        for name in names {
            for token in normalize(name).split(separator: " ").map(String.init)
            where token.count >= 3 && !mine.contains(token) && !common.contains(token) {
                out.insert(token)
            }
        }
        return out
    }

    /// Lowercase, straight apostrophes, and single spaces around words, so phrases match on word boundaries.
    private static func normalize(_ s: String) -> String {
        let lowered = s.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
        let mapped = lowered.unicodeScalars.map { c -> Character in
            CharacterSet.alphanumerics.contains(c) || c == "'" ? Character(c) : " "
        }
        return " " + String(mapped).split(separator: " ").joined(separator: " ") + " "
    }

    private static func count(_ phrases: [String], in text: String) -> Int {
        phrases.reduce(0) { $0 + (text.contains(" \(normalize($1).trimmingCharacters(in: .whitespaces)) ") ? 1 : 0) }
    }
}
