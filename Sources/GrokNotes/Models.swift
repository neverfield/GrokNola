import Foundation

enum AudioSource: String, Codable {
    case mic
    case system
}

enum Attribution: String, Codable {
    case me
    case activeSpeaker
    case onScreen
    case inferred
    case manual
    case unknown

    var label: String {
        switch self {
        case .me: return "you"
        case .activeSpeaker: return "active speaker"
        case .onScreen: return "seen on screen"
        case .inferred: return "inferred by Grok"
        case .manual: return "set by you"
        case .unknown: return "unidentified"
        }
    }
}

enum AttributionMode: String, Codable {
    case detecting
    case named
    case meThem
    case micOnly

    var label: String {
        switch self {
        case .detecting: return "Identifying speakers"
        case .named: return "Named speakers"
        case .meThem: return "Me / Them"
        case .micOnly: return "Microphone only"
        }
    }
}

struct Utterance: Codable, Identifiable, Hashable {
    var id = UUID()
    var source: AudioSource
    var speakerKey: String
    /// Seconds since the meeting started.
    var start: Double
    var end: Double
    var text: String
}

struct SpeakerInfo: Codable, Hashable {
    var name: String?
    var attribution: Attribution
    var confidence: Double?
    var evidence: String?
    // Added after the first release: keep these Optional so older meeting.json files still decode.
    /// True while a name found during recording is still a guess. Nil reads as confirmed.
    var provisional: Bool?
    /// Meeting time when the name was first found during recording. Nil for names found after the meeting.
    var identifiedLiveAt: Double?

    var isProvisional: Bool { provisional ?? false }
}

struct ChatMessage: Codable, Identifiable, Hashable {
    var id = UUID()
    var role: String
    var content: String
}

struct Meeting: Codable, Identifiable {
    var id = UUID()
    var title: String
    var autoTitle: Bool
    var startedAt: Date
    var endedAt: Date?
    var appName: String?
    var attendees: [String] = []
    var userNotes: String = ""
    var enhancedNotes: String?
    var utterances: [Utterance] = []
    var speakers: [String: SpeakerInfo] = [:]
    var mode: AttributionMode = .detecting
    var chat: [ChatMessage] = []
    // Added after the first release: keep these Optional so older meeting.json files still decode.
    var topics: [String]?
    /// Themed sections of the conversation, in order. When set, `topics` comes from their titles.
    var chapters: [Chapter]?
    var tags: [String]?
    var pinned: Bool?
    /// The chosen summary template. Nil uses the default from Settings.
    var templateID: String?
    /// The template the current enhanced notes were written with.
    var notesTemplateID: String?
    /// Meeting time of the first sample in each kept recording, keyed by `AudioSource` raw value. Nil reads as 0.
    var audioOffsets: [String: Double]?
    /// Invitee emails from the calendar event, excluding you.
    var attendeeEmails: [String]?
    /// The enhanced notes exactly as Grok last wrote them.
    var generatedNotes: String?
    /// When the user last changed the enhanced notes after Grok wrote them. Cleared when Grok writes notes.
    var notesEditedAt: Date?
    /// Live speaker keys merged into another key while recording, so later segments of that voice join the target.
    var speakerAliases: [String: String]?
    /// When speakers were last merged or lines moved after Grok wrote the notes. Cleared when Grok writes notes.
    var speakersEditedAt: Date?
}

struct TalkStat: Hashable {
    var key: String
    var name: String
    var seconds: Double
    /// Fraction of all talk time, 0 to 1.
    var share: Double
    var words: Int
}

extension Meeting {
    static let meKey = "me"

    var tagList: [String] { tags ?? [] }
    var isPinned: Bool { pinned ?? false }

    /// The user changed the enhanced notes since Grok wrote them, so a regenerate would lose work.
    /// Notes edited back to exactly what Grok wrote do not count.
    var hasEditedNotes: Bool {
        guard notesEditedAt != nil, let enhancedNotes, !enhancedNotes.isEmpty else { return false }
        return generatedNotes.map { $0 != enhancedNotes } ?? true
    }

    /// Records a user change to the enhanced notes.
    mutating func markNotesEdited(at date: Date = Date()) {
        notesEditedAt = date
    }

    /// Records notes Grok just wrote.
    mutating func setGeneratedNotes(_ markdown: String?) {
        enhancedNotes = markdown
        generatedNotes = markdown
        notesEditedAt = nil
        speakersEditedAt = nil
    }

    /// Appends the edited enhanced notes to the rough notes, so the next regenerate keeps their changes.
    mutating func saveEditedNotesToUserNotes(at date: Date = Date()) {
        guard let enhancedNotes, !enhancedNotes.isEmpty else { return }
        let block = "\(Meeting.previousEditsHeading) (\(date.formatted(date: .abbreviated, time: .shortened)))\n\n\(enhancedNotes.trimmingCharacters(in: .whitespacesAndNewlines))"
        let notes = userNotes.trimmingCharacters(in: .newlines)
        userNotes = notes.isEmpty ? block + "\n" : notes + "\n\n" + block + "\n"
    }

    static let previousEditsHeading = "## Previous edited notes"

    func hasTag(_ name: String) -> Bool {
        tagList.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
    }

    func displayName(for key: String, myName: String) -> String {
        if let name = speakers[key]?.name, !name.isEmpty { return name }
        if key == Meeting.meKey { return myName.isEmpty ? "Me" : myName }
        return "Them"
    }

    var speakerKeys: [String] {
        var seen = Set<String>()
        return utterances.map(\.speakerKey).filter { seen.insert($0).inserted }
    }

    var unresolvedRemoteKeys: [String] {
        speakerKeys.filter { $0 != Meeting.meKey && (speakers[$0]?.name ?? "").isEmpty }
    }

    var hasNamedRemoteSpeaker: Bool {
        speakerKeys.contains { $0 != Meeting.meKey && !(speakers[$0]?.name ?? "").isEmpty }
    }

    func transcript(myName: String, rawKeys: Bool = false) -> String {
        utterances.map { u in
            let who = rawKeys ? u.speakerKey : displayName(for: u.speakerKey, myName: myName)
            return "[\(Meeting.timestamp(u.start))] \(who): \(u.text)"
        }.joined(separator: "\n")
    }

    func markdown(myName: String) -> String {
        var out = "# \(title)\n\n"
        out += "_\(startedAt.formatted(date: .long, time: .shortened))"
        if let appName { out += " · \(appName)" }
        out += "_\n\n"
        if !attendees.isEmpty { out += "**Attendees:** \(attendees.joined(separator: ", "))\n\n" }
        if !tagList.isEmpty { out += "**Tags:** \(tagList.joined(separator: ", "))\n\n" }
        if !utterances.isEmpty {
            out += "## Call summary\n\n"
            out += "- Duration: \(Meeting.durationLabel(duration))\n"
            let people = talkStats(myName: myName).map { "\($0.name) (\(Meeting.durationLabel($0.seconds)), \(Int(($0.share * 100).rounded()))%)" }
            out += "- Participants: \(people.joined(separator: ", "))\n"
            if let topics, !topics.isEmpty { out += "- Topics: \(topics.joined(separator: "; "))\n" }
            out += Chapters.markdown(chapters ?? [])
            out += "\n"
        }
        if let enhancedNotes {
            out += enhancedNotes + "\n\n"
        } else if !userNotes.isEmpty {
            out += "## My notes\n\n\(userNotes)\n\n"
        }
        if !utterances.isEmpty {
            out += "## Transcript\n\n"
            out += utterances.map { u in
                "**\(displayName(for: u.speakerKey, myName: myName))** [\(Meeting.timestamp(u.start))]: \(u.text)"
            }.joined(separator: "\n\n")
            out += "\n"
        }
        return out
    }

    mutating func insert(_ utterance: Utterance) {
        let index = utterances.lastIndex(where: { $0.start <= utterance.start }).map { $0 + 1 } ?? 0
        utterances.insert(utterance, at: index)
    }

    /// Wall-clock length of the meeting, or the end of the last utterance when it has no end time.
    var duration: Double {
        if let endedAt { return max(0, endedAt.timeIntervalSince(startedAt)) }
        return utterances.map(\.end).max() ?? 0
    }

    /// Talk time per speaker, longest first.
    func talkStats(myName: String) -> [TalkStat] {
        var seconds: [String: Double] = [:]
        var words: [String: Int] = [:]
        for u in utterances {
            seconds[u.speakerKey, default: 0] += max(0, u.end - u.start)
            words[u.speakerKey, default: 0] += u.text.split(whereSeparator: \.isWhitespace).count
        }
        let total = seconds.values.reduce(0, +)
        return speakerKeys.map { key in
            let s = seconds[key] ?? 0
            return TalkStat(
                key: key,
                name: displayName(for: key, myName: myName),
                seconds: s,
                share: total > 0 ? s / total : 0,
                words: words[key] ?? 0
            )
        }
        .sorted { $0.seconds != $1.seconds ? $0.seconds > $1.seconds : $0.name < $1.name }
    }

    /// "1h 5m", "4m 12s", or "45s".
    static func durationLabel(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded()))
        if s >= 3600 { return "\(s / 3600)h \((s % 3600) / 60)m" }
        if s >= 60 { return s % 60 == 0 ? "\(s / 60)m" : "\(s / 60)m \(s % 60)s" }
        return "\(s)s"
    }

    static func timestamp(_ seconds: Double) -> String {
        let s = max(0, Int(seconds))
        if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) }
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}
