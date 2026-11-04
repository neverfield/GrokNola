import Foundation

/// Answers questions across every meeting and about the app itself: picks the relevant meetings, then asks Grok
/// with their notes and transcripts and, for app questions, the user guide. Answers link back with `groknotes://meeting/<id>`.
enum LibraryAsk {
    static let linkScheme = "groknotes"
    private static let maxMeetingsInContext = 8
    private static let contextBudget = 240_000
    private static let indexLimit = 300

    static func link(for meeting: Meeting) -> String {
        "\(linkScheme)://meeting/\(meeting.id.uuidString)"
    }

    static func meetingID(from url: URL) -> UUID? {
        guard url.scheme == linkScheme, url.host == "meeting" else { return nil }
        return UUID(uuidString: url.lastPathComponent)
    }

    /// Whether a question needs the user guide, the meetings, or both. Without meetings, only the guide can help.
    static func route(for question: String, history: [ChatMessage], meetings: [Meeting], myName: String) -> HelpRouter.Route {
        guard !meetings.isEmpty else { return .help }
        let people = HelpRouter.peopleTokens(
            meetings.prefix(indexLimit).flatMap { $0.attendees + $0.speakers.values.compactMap(\.name) },
            excluding: myName
        )
        let previous = history.last { $0.role == "user" }?.content
        return HelpRouter.route(question, previous: previous, people: people)
    }

    static func answer(
        _ question: String,
        history: [ChatMessage],
        meetings: [Meeting],
        myName: String,
        route: HelpRouter.Route,
        client: XAIClient,
        model: String
    ) async throws -> String {
        var messages: [XAIClient.Message] = []
        if route != .meetings {
            messages.append(.init(role: "system", content: helpPrompt(hasMeetings: !meetings.isEmpty)))
        }
        if route != .help {
            let recentTurns = history.suffix(6).map(\.content).joined(separator: "\n")
            let selected = try await select(for: question, context: recentTurns, from: meetings, myName: myName, client: client, model: model)
            messages.append(.init(role: "system", content: """
            You answer questions across the user's meeting notes and transcripts.
            Use only the meetings provided. If they do not contain the answer, say so and suggest what to search for.
            Cite every fact with a Markdown link to its meeting, using the exact link given, for example [Pricing sync, Nov 3](\(linkScheme)://meeting/<id>).
            Add a timestamp like [12:04] when quoting the transcript. "Them" is an unidentified remote participant.
            Be concise. Use short bullets for lists.
            """ + (route == .both ? """

            The question may be about the meetings, about how Grok Notes works, or both. \
            Answer app questions from the user guide with the rules above, and meeting questions from the meetings. \
            Leave out the part that does not apply.
            """ : "")))
            messages.append(.init(role: "user", content: context(for: selected, total: meetings.count, myName: myName)))
        }
        messages += history.suffix(12).map { .init(role: $0.role, content: $0.content) }
        messages.append(.init(role: "user", content: question))
        return try await client.chat(model: model, messages: messages)
    }

    /// The guide comes first and does not change between questions, so xAI can cache it.
    private static func helpPrompt(hasMeetings: Bool) -> String {
        """
        You are the built-in help for Grok Notes, a macOS meeting notepad. Answer questions about how the app works \
        (features, settings, permissions, troubleshooting) using only the Grok Notes user guide below.
        - Give concrete numbered steps. Name the exact UI labels from the guide in bold, for example **Settings > Privacy > Keep audio recordings after notes are written**, and include the keyboard shortcut when the guide lists one.
        - If the guide does not cover something, say that the guide does not cover it and point to the closest topic it does cover. Never invent features, settings, menu items, file paths, or shortcuts.
        - These Markdown links open places in the app; add one when it saves the user a step: \(AppLink.promptList). Use no other groknotes:// links in help answers.
        - Be concise. Use short bullets for lists.\(hasMeetings ? "" : "\n- The user has not recorded any meetings yet. If they ask about meeting content, say so and explain how to start notes.")

        <user_guide>
        \(HelpGuide.text)
        </user_guide>
        """
    }

    // MARK: Selection

    /// Keyword and recency ranking, then Grok picks from a compact index when there are many meetings.
    private static func select(
        for question: String,
        context: String,
        from meetings: [Meeting],
        myName: String,
        client: XAIClient,
        model: String
    ) async throws -> [Meeting] {
        let ranked = rank(meetings, query: question + " " + context)
        guard meetings.count > maxMeetingsInContext else { return ranked }

        let index = meetings.sorted { $0.startedAt > $1.startedAt }.prefix(indexLimit).map(indexLine).joined(separator: "\n")
        let reply = try await client.chat(model: model, messages: [
            .init(role: "system", content: """
            Pick the meetings most likely to answer the question. Consider names, tags, topics, and dates \
            (today is \(Date().formatted(date: .complete, time: .omitted))).
            Reply with JSON only: {"ids":["<id>", ...]} with at most \(maxMeetingsInContext) ids, most relevant first.
            """),
            .init(role: "user", content: "Question: \(question)\n\nRecent conversation:\n\(context.isEmpty ? "(none)" : context)\n\nMeetings:\n\(index)"),
        ])
        let picked = parseIDs(reply).compactMap { id in meetings.first { $0.id.uuidString.lowercased().hasPrefix(id.lowercased()) } }

        var result: [Meeting] = []
        for m in picked + ranked.prefix(3) where !result.contains(where: { $0.id == m.id }) {
            result.append(m)
        }
        return Array(result.prefix(maxMeetingsInContext))
    }

    static func rank(_ meetings: [Meeting], query: String) -> [Meeting] {
        let terms = tokens(query)
        let now = Date()
        let scored = meetings.map { m -> (Meeting, Double) in
            let title = m.title.lowercased()
            let notes = (m.enhancedNotes ?? m.userNotes).lowercased()
            let people = (m.attendees + m.speakers.values.compactMap(\.name)).joined(separator: " ").lowercased()
            let transcript = m.utterances.map(\.text).joined(separator: " ").lowercased()
            let tags = m.tagList.joined(separator: " ").lowercased()
            var score = 0.0
            for term in terms {
                score += Double(count(term, in: title)) * 6
                score += Double(count(term, in: tags)) * 5
                score += Double(count(term, in: people)) * 4
                score += Double(min(count(term, in: notes), 10)) * 2
                score += Double(min(count(term, in: transcript), 20))
            }
            let ageDays = max(0, now.timeIntervalSince(m.startedAt) / 86_400)
            score += 3 / (1 + ageDays / 7)
            return (m, score)
        }
        return scored.sorted { $0.1 > $1.1 }.prefix(maxMeetingsInContext).map(\.0)
    }

    // MARK: Context

    private static func indexLine(_ m: Meeting) -> String {
        let people = uniqueNames(m.attendees + m.speakers.values.compactMap(\.name)).prefix(8).joined(separator: ", ")
        let summary = summaryLine(m)
        let tags = m.tagList.isEmpty ? "" : " | tags: \(m.tagList.joined(separator: ", "))"
        return "\(m.id.uuidString.prefix(8)) | \(m.startedAt.formatted(date: .abbreviated, time: .omitted)) | \(m.title) | \(people)\(tags) | \(summary)"
    }

    private static func summaryLine(_ m: Meeting) -> String {
        let source = m.enhancedNotes ?? m.userNotes
        let lines = source.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let body = lines.filter { !$0.hasPrefix("#") && !$0.isEmpty }.prefix(3).joined(separator: " ")
        return String(body.prefix(240))
    }

    private static func context(for meetings: [Meeting], total: Int, myName: String) -> String {
        var out = "The user (\(myName)) has \(total) meetings. These are the most relevant:\n"
        let perMeeting = contextBudget / max(meetings.count, 1)
        for m in meetings {
            var block = "\n=== \(m.title) — \(m.startedAt.formatted(date: .abbreviated, time: .shortened))"
            if let app = m.appName { block += " — \(app)" }
            block += "\nLink: \(link(for: m))\n"
            if !m.attendees.isEmpty { block += "Invitees: \(m.attendees.joined(separator: ", "))\n" }
            if !m.tagList.isEmpty { block += "Tags: \(m.tagList.joined(separator: ", "))\n" }
            block += "Notes:\n\(m.enhancedNotes ?? (m.userNotes.isEmpty ? "(none)" : m.userNotes))\n"
            block += "Transcript:\n\(m.transcript(myName: myName))\n"
            out += String(block.prefix(perMeeting))
        }
        return out
    }

    // MARK: Helpers

    private static let stopwords: Set<String> = [
        "the", "and", "for", "with", "what", "when", "where", "who", "why", "how", "did", "does", "was", "were",
        "are", "you", "about", "that", "this", "from", "have", "has", "had", "our", "their", "they", "say",
        "said", "any", "all", "can", "could", "would", "should", "meeting", "meetings", "notes", "call", "calls",
    ]

    private static func tokens(_ text: String) -> [String] {
        Array(Set(text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count >= 3 && !stopwords.contains($0) }))
    }

    private static func count(_ term: String, in text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        return text.components(separatedBy: term).count - 1
    }

    private static func parseIDs(_ reply: String) -> [String] {
        guard let json = SpeakerResolver.extractJSONObject(reply),
              let obj = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let ids = obj["ids"] as? [String]
        else { return [] }
        return ids
    }
}
