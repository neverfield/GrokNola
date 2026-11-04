import Foundation

/// Puts names on diarized speakers. Evidence, strongest first:
/// 1. Manual names the user set (never overwritten).
/// 2. The meeting app's active-speaker indicator overlapping that speaker's speech.
/// 3. Grok vision reading the highlighted tile in meeting-window snapshots.
/// 4. Grok reading the transcript ("Thanks, Priya") against invitees and names seen in the app.
/// A speaker with no strong evidence stays "Them".
enum SpeakerResolver {
    static func applyActiveSpeakerVotes(to meeting: inout Meeting, samples: [ActiveSpeakerMonitor.Sample]) {
        let solo = samples.filter { $0.speaking.count == 1 }
        guard !solo.isEmpty else { return }

        var votes: [String: [String: Int]] = [:]
        for u in meeting.utterances where u.source == .system {
            for sample in solo where sample.time >= u.start - 0.5 && sample.time <= u.end + 1 {
                votes[u.speakerKey, default: [:]][sample.speaking[0], default: 0] += 1
            }
        }

        for (key, tally) in votes {
            if let existing = meeting.speakers[key], existing.attribution == .manual { continue }
            let total = tally.values.reduce(0, +)
            guard let (name, count) = tally.max(by: { $0.value < $1.value }),
                  count >= 3, Double(count) / Double(total) >= 0.6
            else { continue }
            meeting.speakers[key] = SpeakerInfo(
                name: name,
                attribution: .activeSpeaker,
                confidence: Double(count) / Double(total),
                evidence: "Shown as talking in \(count) of \(total) samples"
            )
        }
    }

    /// Shows Grok meeting-window snapshots taken while each unidentified voice was talking alone,
    /// and asks whose tile is highlighted. Returns every participant name visible in the snapshots.
    @discardableResult
    static func identifyFromSnapshots(
        in meeting: inout Meeting,
        frames: [WindowSnapshotter.Frame],
        myName: String,
        client: XAIClient,
        model: String
    ) async throws -> [String] {
        let unresolved = meeting.unresolvedRemoteKeys
        var picked: [(key: String, frames: [WindowSnapshotter.Frame])] = []
        for key in unresolved.prefix(8) {
            let chosen = pickFrames(for: key, in: meeting, from: frames)
            if !chosen.isEmpty { picked.append((key, chosen)) }
        }
        // Without a clean frame per speaker, still read the participant names from a few frames.
        let rosterFrames = picked.isEmpty ? evenlySpaced(frames, count: 3) : []
        guard !picked.isEmpty || !rosterFrames.isEmpty else { return [] }

        let system = """
        You read screenshots of a video-call window (Zoom, Microsoft Teams, Google Meet, Slack huddle, Webex).
        Each screenshot was taken while one remote participant was talking. That speaker has a voice label like r0.
        Apps show the current speaker with a highlighted or colored tile border, a large speaker-view tile,
        a moving audio or microphone indicator, or a "Talking:" label. Tiles show participant names.

        For each label, decide who is talking from its screenshots. Agreement across screenshots raises confidence.
        The user, \(myName.isEmpty ? "the local participant" : myName), is not any of these labels. Never give a label the user's name.
        If no speaker indicator is clear, return null for that label. Do not guess from tile position alone.
        Also list every participant name you can read anywhere in the screenshots.

        Reply with JSON only:
        {"participants":["<name>"],"mappings":[{"speaker":"<label>","name":"<name or null>","confidence":<0 to 1>,"evidence":"<what you saw>"}]}
        """
        var parts: [XAIClient.Part] = [.text("Meeting app: \(meeting.appName ?? "unknown"). Labels: \(picked.map(\.key).joined(separator: ", ")).")]
        for (key, chosen) in picked {
            for (index, frame) in chosen.enumerated() {
                guard let data = try? Data(contentsOf: frame.url) else { continue }
                parts.append(.text("Label \(key), screenshot \(index + 1) at \(Meeting.timestamp(frame.time)):"))
                parts.append(.jpeg(data))
            }
        }
        for (index, frame) in rosterFrames.enumerated() {
            guard let data = try? Data(contentsOf: frame.url) else { continue }
            parts.append(.text("Participants screenshot \(index + 1) at \(Meeting.timestamp(frame.time)) (no label; read names only):"))
            parts.append(.jpeg(data))
        }

        let reply = try await client.chat(model: model, system: system, parts: parts)
        guard let json = extractJSONObject(reply),
              let parsed = try? JSONDecoder().decode(SnapshotReply.self, from: Data(json.utf8))
        else { return [] }

        let participants = uniqueNames((parsed.participants ?? []).filter { !isLikelyUser($0, myName: myName) })
        for mapping in parsed.mappings ?? [] {
            guard unresolved.contains(mapping.speaker),
                  let name = mapping.name?.trimmingCharacters(in: .whitespaces), !name.isEmpty,
                  name.caseInsensitiveCompare(myName) != .orderedSame,
                  let confidence = mapping.confidence, confidence >= 0.7
            else { continue }
            meeting.speakers[mapping.speaker] = SpeakerInfo(
                name: name,
                attribution: .onScreen,
                confidence: confidence,
                evidence: mapping.evidence
            )
        }
        assignSoleParticipant(in: &meeting, participants: participants, evidence: "Only other participant shown in the call window")
        return participants
    }

    /// In a one-on-one call, the single remote voice must be the single other participant.
    static func assignSoleParticipant(in meeting: inout Meeting, participants: [String], evidence: String) {
        let remoteKeys = meeting.speakerKeys.filter { $0 != Meeting.meKey }
        guard remoteKeys.count == 1, participants.count == 1,
              let key = remoteKeys.first, meeting.unresolvedRemoteKeys == [key]
        else { return }
        meeting.speakers[key] = SpeakerInfo(name: participants[0], attribution: .onScreen, confidence: 0.9, evidence: evidence)
    }

    /// The user's own tile may show their full name, their bare first name, or "(me)".
    /// Another participant who shares the user's first name ("Andrew Parsons") is not the user.
    private static func isLikelyUser(_ name: String, myName: String) -> Bool {
        let n = name.lowercased().trimmingCharacters(in: .whitespaces)
        if n.contains("(me)") || n == "me" || n == "you" { return true }
        let mine = myName.lowercased()
        return n == mine || (!n.contains(" ") && mine.split(separator: " ").first.map(String.init) == n)
    }

    private static func evenlySpaced(_ frames: [WindowSnapshotter.Frame], count: Int) -> [WindowSnapshotter.Frame] {
        guard frames.count > count else { return frames }
        return (0..<count).map { frames[($0 * (frames.count - 1)) / max(count - 1, 1)] }
    }

    /// Up to `limit` frames taken in the middle of this speaker's longer turns while nobody else spoke,
    /// spread at least 15 seconds apart when possible.
    private static func pickFrames(for key: String, in meeting: Meeting, from frames: [WindowSnapshotter.Frame], limit: Int = 3) -> [WindowSnapshotter.Frame] {
        let turns = meeting.utterances.filter { $0.speakerKey == key && $0.end - $0.start >= 1.5 }
        var scored: [(frame: WindowSnapshotter.Frame, turnLength: Double)] = []
        for frame in frames {
            guard let turn = turns.first(where: { frame.time >= $0.start + 0.5 && frame.time <= $0.end - 0.2 }) else { continue }
            let overlapped = meeting.utterances.contains {
                $0.speakerKey != key && frame.time >= $0.start - 0.3 && frame.time <= $0.end + 0.3
            }
            if !overlapped { scored.append((frame, turn.end - turn.start)) }
        }
        scored.sort { $0.turnLength > $1.turnLength }
        var chosen: [WindowSnapshotter.Frame] = []
        for candidate in scored where chosen.count < limit {
            if chosen.allSatisfy({ abs($0.time - candidate.frame.time) >= 15 }) { chosen.append(candidate.frame) }
        }
        for candidate in scored where chosen.count < limit && !chosen.contains(where: { $0.url == candidate.frame.url }) {
            chosen.append(candidate.frame)
        }
        return chosen.sorted { $0.time < $1.time }
    }

    private struct SnapshotReply: Decodable {
        struct Item: Decodable {
            let speaker: String
            let name: String?
            let confidence: Double?
            let evidence: String?
        }
        let participants: [String]?
        let mappings: [Item]?
    }

    /// Microphone-only fallback: the voice that talks most into the mic is the user.
    static func assignDominantMicSpeakerToMe(_ meeting: inout Meeting) {
        var counts: [String: Int] = [:]
        for u in meeting.utterances where u.source == .mic && u.speakerKey != Meeting.meKey {
            counts[u.speakerKey, default: 0] += u.text.split(separator: " ").count
        }
        guard let top = counts.max(by: { $0.value < $1.value })?.key else { return }
        for i in meeting.utterances.indices where meeting.utterances[i].speakerKey == top {
            meeting.utterances[i].speakerKey = Meeting.meKey
        }
        meeting.speakers[top] = nil
        meeting.speakers[Meeting.meKey] = SpeakerInfo(name: nil, attribution: .me)
    }

    static func inferNames(in meeting: inout Meeting, candidates: [String], myName: String, client: XAIClient, model: String) async throws {
        let unresolved = meeting.unresolvedRemoteKeys
        guard !unresolved.isEmpty else { return }

        let identified = meeting.speakerKeys.compactMap { key -> String? in
            guard key != Meeting.meKey, let name = meeting.speakers[key]?.name else { return nil }
            return "\(key) = \(name)"
        }
        let transcript = String(meeting.transcript(myName: myName, rawKeys: true).prefix(200_000))

        let system = """
        You identify speakers in a diarized meeting transcript. Each line is "[time] label: text".
        The label `me` is the user. Other labels are remote participants found by voice.

        Assign a real name to a label only with clear evidence in the transcript:
        - the speaker introduces themselves ("This is Dana from finance"), or
        - someone addresses them by name and that label answers right after, or
        - other speakers refer to them in a way that fits only one person.
        Prefer names from the candidate list and use the full name when it is listed.
        Never give the user's own name to another label. Do not guess. When evidence is weak, return null.

        Reply with JSON only:
        {"mappings":[{"speaker":"<label>","name":"<name or null>","confidence":<0 to 1>,"evidence":"<short quote>"}]}
        """
        let user = """
        User (label `me`): \(myName.isEmpty ? "unknown" : myName)
        Candidates (calendar invitees, names shown in the meeting app, people from past meetings): \(candidates.isEmpty ? "none" : candidates.joined(separator: ", "))
        Already identified: \(identified.isEmpty ? "none" : identified.joined(separator: "; "))
        Labels to identify: \(unresolved.joined(separator: ", "))

        Transcript:
        \(transcript)
        """

        let reply = try await client.chat(model: model, messages: [
            .init(role: "system", content: system),
            .init(role: "user", content: user),
        ])
        guard let json = extractJSONObject(reply),
              let parsed = try? JSONDecoder().decode(Mappings.self, from: Data(json.utf8))
        else { return }

        for mapping in parsed.mappings {
            guard unresolved.contains(mapping.speaker),
                  let name = mapping.name?.trimmingCharacters(in: .whitespaces), !name.isEmpty,
                  name.caseInsensitiveCompare(myName) != .orderedSame
            else { continue }
            let lower = name.lowercased()
            let candidate = candidates.first { $0.lowercased() == lower || $0.lowercased().hasPrefix(lower + " ") }
            let confidence = mapping.confidence ?? 0
            // A name that is not on any list needs stronger evidence.
            guard confidence >= (candidate == nil ? 0.85 : 0.75) else { continue }
            meeting.speakers[mapping.speaker] = SpeakerInfo(
                name: candidate ?? name,
                attribution: .inferred,
                confidence: confidence,
                evidence: mapping.evidence
            )
        }
    }

    private struct Mappings: Decodable {
        struct Item: Decodable {
            let speaker: String
            let name: String?
            let confidence: Double?
            let evidence: String?
        }
        let mappings: [Item]
    }

    static func extractJSONObject(_ text: String) -> String? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else { return nil }
        return String(text[start...end])
    }
}
