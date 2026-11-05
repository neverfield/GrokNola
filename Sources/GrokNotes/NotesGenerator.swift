import Foundation

enum NotesGenerator {
    private static let maxTranscriptCharacters = 300_000

    struct Notes {
        var markdown: String
        /// Normalized themes from the notes call, or nil when Grok left out the Topics line.
        var topics: [String]?
        /// Chapters from the trailing block, or nil when Grok left it out or it did not parse.
        var chapters: [Chapter]?
    }

    /// Writes the notes with `template` and, in the same request, the meeting's topics and chapters.
    static func enhancedNotes(
        for meeting: Meeting,
        template: SummaryTemplate,
        topicVocabulary: [String],
        myName: String,
        client: XAIClient,
        model: String
    ) async throws -> Notes {
        let sections = template.sections.enumerated().map { "\($0.offset + 1). ## \($0.element)" }.joined(separator: "\n")
        let instructions = template.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        let chapterSection = meeting.utterances.isEmpty ? "" : """


        Chapters:
        - After the Topics line, end with a line "Chapters:" and then one line per chapter, for example:
        Chapters:
        [00:00] Kickoff and Agenda
        [04:12] Pricing and Packaging
        \(Chapters.rules)
        """
        let system = """
        You are GrokNola, an expert meeting note-taker. Turn the transcript and the user's rough notes into clean, skimmable Markdown.

        Meeting type: \(template.name)
        \(instructions.isEmpty ? "Write balanced, skimmable notes." : instructions)

        Format:
        - First line: "# " and a short, specific title (8 words or fewer).
        - Then use exactly these "## " sections, in this order, with these headings:
        \(sections.isEmpty ? "1. ## Summary\n2. ## Key points\n3. ## Action items" : sections)
        - Leave out a section that would be empty. Do not add other "## " sections; use "### " subheadings inside a section when it helps.
        - Short "- " bullets. Write action items, next steps, and follow-ups as "- [ ] Owner: task, due date if stated".
        - The user's rough notes are the backbone. Keep every point they wrote, in their order, placed in the section where it fits, and add specifics from the transcript under each.
        - A rough-notes line starting with "📌 Q (" is a question the user pinned during the call, followed by an "A:" answer. The user highlighted it: include the question and the answer's facts in the section where they fit. Do not copy the 📌 marker.
        - A rough-notes section "\(Meeting.previousEditsHeading) (…)" holds earlier notes the user corrected by hand. Treat its names, facts, and wording as authoritative and keep its points, but write fresh notes in the format above rather than copying it, and do not output that heading.

        Topics:
        - After the notes, write exactly one plain line: "Topics: Theme One; Theme Two; Theme Three".
        \(Topics.rules(template: template, vocabulary: topicVocabulary))\(chapterSection)

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
        \(String(meeting.transcript(myName: myName).prefix(maxTranscriptCharacters)))\(Topics.vocabularyBlock(topicVocabulary))
        """
        let reply = try await client.chat(model: model, messages: [
            .init(role: "system", content: system),
            .init(role: "user", content: user),
        ])
        let block = Chapters.split(from: reply)
        let split = Topics.splitTopicsLine(from: block.text)
        let topics = split.topics.map { Topics.normalize($0, vocabulary: topicVocabulary) }
        let chapters = block.entries.flatMap { Chapters.build($0, end: Chapters.end(of: meeting), vocabulary: topicVocabulary) }
        return Notes(markdown: split.notes, topics: topics?.isEmpty == true ? nil : topics, chapters: chapters)
    }

    /// Chapters for meetings whose notes came without them. Reads the transcript, which carries the timestamps.
    static func chapters(
        for meeting: Meeting,
        template: SummaryTemplate,
        topicVocabulary: [String],
        myName: String,
        client: XAIClient,
        model: String
    ) async throws -> [Chapter]? {
        let reply = try await client.chat(model: model, messages: [
            .init(role: "system", content: """
            You split a meeting (meeting type: \(template.name)) into topic chapters.
            \(Topics.rules(template: template, vocabulary: topicVocabulary))
            \(Chapters.rules)
            Reply with the line "Chapters:" and then one line per chapter, like "[04:12] Pricing and Packaging", and nothing else.
            """),
            .init(role: "user", content: """
            Meeting: \(meeting.title)\(Topics.vocabularyBlock(topicVocabulary))

            Transcript:
            \(String(meeting.transcript(myName: myName).prefix(maxTranscriptCharacters)))
            """),
        ])
        return Chapters.build(Chapters.entries(in: reply), end: Chapters.end(of: meeting), vocabulary: topicVocabulary)
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

    /// 3 to 5 themes, for meetings whose notes came without topics. Reads the notes when there are some, otherwise the transcript.
    static func topics(
        for meeting: Meeting,
        template: SummaryTemplate,
        topicVocabulary: [String],
        myName: String,
        client: XAIClient,
        model: String
    ) async throws -> [String] {
        let source: String
        if let notes = meeting.enhancedNotes, !notes.isEmpty {
            source = "Meeting notes:\n\(notes)"
        } else {
            source = "Transcript:\n\(String(meeting.transcript(myName: myName).prefix(maxTranscriptCharacters)))"
        }
        let reply = try await client.chat(model: model, messages: [
            .init(role: "system", content: """
            You name the themes of a meeting (meeting type: \(template.name)).
            \(Topics.rules(template: template, vocabulary: topicVocabulary))
            Reply with one line and nothing else: "Topics: Theme One; Theme Two; Theme Three".
            """),
            .init(role: "user", content: "Meeting: \(meeting.title)\(Topics.vocabularyBlock(topicVocabulary))\n\n\(source)"),
        ])
        return parseTopics(reply, vocabulary: topicVocabulary)
    }

    /// Reads a "Topics:" line, or one topic per line when Grok skipped the label.
    static func parseTopics(_ reply: String, vocabulary: [String] = []) -> [String] {
        let lines = reply.split(whereSeparator: \.isNewline).map(String.init)
        let raw = lines.compactMap(Topics.topicsList(in:)).last ?? lines
        return Topics.normalize(raw, vocabulary: vocabulary)
    }

    static func title(fromNotes notes: String) -> String? {
        guard let line = notes.split(separator: "\n").first(where: { $0.hasPrefix("# ") }) else { return nil }
        let title = Citations.strip(String(line.dropFirst(2)))
        return title.isEmpty ? nil : title
    }
}
