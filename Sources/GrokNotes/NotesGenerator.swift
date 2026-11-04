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
            You answer questions about one meeting using its transcript and notes. Cite timestamps like [12:04] when useful. \
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

    static func title(fromNotes notes: String) -> String? {
        guard let line = notes.split(separator: "\n").first(where: { $0.hasPrefix("# ") }) else { return nil }
        let title = line.dropFirst(2).trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? nil : title
    }
}
