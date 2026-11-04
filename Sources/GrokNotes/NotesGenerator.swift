import Foundation

enum NotesGenerator {
    private static let maxTranscriptCharacters = 300_000

    static func enhancedNotes(for meeting: Meeting, myName: String, client: XAIClient, model: String) async throws -> String {
        let system = """
        You are Grok Notes, an expert meeting note-taker. Turn the transcript and the user's rough notes into clean, skimmable Markdown.

        Format:
        - First line: "# " and a short, specific title (8 words or fewer).
        - "## Summary": 2 to 4 sentences.
        - The user's rough notes are the backbone. Keep every point they wrote, in their order, and add specifics from the transcript under each. Then add other important topics.
        - Use "## " topic headings with short "- " bullets.
        - "## Decisions" and "## Action items" (as "- [ ] Owner: task, due date if stated"). Leave out a section that would be empty.

        Rules:
        - Attribute statements and owners by name only when the transcript label is a real name. "Them" is an unidentified remote participant; write "the other side" or "someone" instead.
        - Use only facts from the transcript and the notes. Never invent names, numbers, or dates.
        - Cite sources: end each factual bullet and action item with the timestamps of the transcript lines it relies on, copied exactly from the line prefixes, each in its own brackets, for example "- Budget is capped at $50k [12:04] [15:30]". Use 1 to 3 timestamps per bullet. Do not cite in the title or headings. Skip the citation when a point comes only from the user's rough notes. Never invent a timestamp.
        - Output Markdown only.
        """
        let user = """
        Meeting: \(meeting.title)
        Date: \(meeting.startedAt.formatted(date: .long, time: .shortened))
        App: \(meeting.appName ?? "unknown")
        Invitees: \(meeting.attendees.isEmpty ? "unknown" : meeting.attendees.joined(separator: ", "))
        User: \(myName)

        My rough notes:
        \(meeting.userNotes.isEmpty ? "(none)" : meeting.userNotes)

        Transcript:
        \(String(meeting.transcript(myName: myName).prefix(maxTranscriptCharacters)))
        """
        return try await client.chat(model: model, messages: [
            .init(role: "system", content: system),
            .init(role: "user", content: user),
        ])
    }

    static func answer(_ question: String, about meeting: Meeting, myName: String, client: XAIClient, model: String) async throws -> String {
        var messages: [XAIClient.Message] = [
            .init(role: "system", content: """
            You answer questions about one meeting using its transcript and notes. Cite timestamps copied from transcript lines, \
            each in its own brackets like [12:04], when useful. \
            If the meeting does not contain the answer, say so. "Them" is an unidentified remote participant.
            """),
            .init(role: "user", content: """
            Meeting: \(meeting.title) (\(meeting.startedAt.formatted(date: .long, time: .shortened)))
            User: \(myName)

            Notes:
            \(meeting.enhancedNotes ?? meeting.userNotes)

            Transcript:
            \(String(meeting.transcript(myName: myName).prefix(maxTranscriptCharacters)))
            """),
        ]
        messages += meeting.chat.suffix(20).map { .init(role: $0.role, content: $0.content) }
        messages.append(.init(role: "user", content: question))
        return try await client.chat(model: model, messages: messages)
    }

    /// 3 to 6 short topic phrases. Reads the notes when there are some, otherwise the transcript.
    static func topics(for meeting: Meeting, myName: String, client: XAIClient, model: String) async throws -> [String] {
        let source: String
        if let notes = meeting.enhancedNotes, !notes.isEmpty {
            source = "Meeting notes:\n\(notes)"
        } else {
            source = "Transcript:\n\(String(meeting.transcript(myName: myName).prefix(maxTranscriptCharacters)))"
        }
        let reply = try await client.chat(model: model, messages: [
            .init(role: "system", content: """
            List the 3 to 6 main topics of this meeting, most discussed first. \
            Each topic is a short noun phrase of 2 to 5 words in sentence case. \
            Output one topic per line and nothing else: no numbering, bullets, or punctuation at the end.
            """),
            .init(role: "user", content: "Meeting: \(meeting.title)\n\n\(source)"),
        ])
        return parseTopics(reply)
    }

    static func parseTopics(_ reply: String) -> [String] {
        let lines = reply.split(whereSeparator: \.isNewline).map { line -> String in
            let t = Citations.strip(String(line))
                .replacingOccurrences(of: #"^\s*(?:[-*•#]+|\d{1,2}[.)])\s*"#, with: "", options: .regularExpression)
            return t.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ".;,\"*")))
        }
        var seen = Set<String>()
        return Array(lines.filter { !$0.isEmpty && $0.count <= 60 && seen.insert($0.lowercased()).inserted }.prefix(6))
    }

    static func title(fromNotes notes: String) -> String? {
        guard let line = notes.split(separator: "\n").first(where: { $0.hasPrefix("# ") }) else { return nil }
        let title = Citations.strip(String(line.dropFirst(2)))
        return title.isEmpty ? nil : title
    }
}
