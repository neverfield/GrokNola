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
    var tags: [String]?
    var pinned: Bool?
}

extension Meeting {
    static let meKey = "me"

    var tagList: [String] { tags ?? [] }
    var isPinned: Bool { pinned ?? false }

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

    static func timestamp(_ seconds: Double) -> String {
        let s = max(0, Int(seconds))
        if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) }
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}
