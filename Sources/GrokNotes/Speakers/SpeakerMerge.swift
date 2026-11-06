import Foundation

extension Meeting {
    /// Gives every line of `from` to `target` and removes `from`. The target keeps its name, and takes
    /// the name of `from` only when it has none. Your own key cannot be merged away.
    mutating func mergeSpeaker(_ from: String, into target: String) {
        guard from != target, from != Meeting.meKey else { return }
        for i in utterances.indices where utterances[i].speakerKey == from {
            utterances[i].speakerKey = target
        }
        let targetNamed = !(speakers[target]?.name ?? "").isEmpty
        if target != Meeting.meKey, !targetNamed, let source = speakers[from], !(source.name ?? "").isEmpty {
            speakers[target] = source
        } else if speakers[target] == nil {
            speakers[target] = SpeakerInfo(name: nil, attribution: target == Meeting.meKey ? .me : .unknown)
        }
        speakers[from] = nil
        var aliases = speakerAliases ?? [:]
        for (key, value) in aliases where value == from { aliases[key] = target }
        aliases[from] = target
        speakerAliases = aliases
    }

    /// Gives the lines with these ids to `key`, for a block that diarization put on the wrong voice.
    mutating func reassignUtterances(ids: Set<UUID>, to key: String) {
        for i in utterances.indices where ids.contains(utterances[i].id) {
            utterances[i].speakerKey = key
        }
        if speakers[key] == nil {
            speakers[key] = SpeakerInfo(name: nil, attribution: key == Meeting.meKey ? .me : .unknown)
        }
    }

    /// The speaker key that live segments heard under `key` belong to.
    func aliasedKey(_ key: String) -> String {
        speakerAliases?[key] ?? key
    }

    /// The other speaker in this meeting already named `name`, ignoring case.
    func speaker(named name: String, except key: String) -> String? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return speakerKeys.first { other in
            other != key && (speakers[other]?.name ?? "").caseInsensitiveCompare(name) == .orderedSame
        }
    }

    /// The speaker's name, numbered with when they first talk when several speakers share it, as in "Them 2 · 03:12".
    func distinctName(for key: String, myName: String) -> String {
        let name = displayName(for: key, myName: myName)
        let same = speakerKeys.filter { displayName(for: $0, myName: myName) == name }
        guard same.count > 1, let n = same.firstIndex(of: key) else { return name }
        let first = utterances.first { $0.speakerKey == key }.map { " · \(Meeting.timestamp($0.start))" } ?? ""
        return "\(name) \(n + 1)\(first)"
    }

    /// Speakers were merged or lines moved since Grok wrote the enhanced notes.
    var speakersChangedSinceNotes: Bool {
        speakersEditedAt != nil && !(enhancedNotes ?? "").isEmpty
    }

    /// The attribution mode once speaker names changed. A meeting still being identified stays that way.
    mutating func refreshAttributionMode() {
        guard mode != .detecting else { return }
        mode = hasNamedRemoteSpeaker ? .named : (mode == .micOnly ? .micOnly : .meThem)
    }
}
