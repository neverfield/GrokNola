import Foundation

/// The prompt and request options for live answers. Context is capped near `contextBudget` characters for speed.
enum LiveAnswersPrompt {
    static let transcriptWindow: Double = 180
    static let contextBudget = 8_000
    static let maxOutputTokens = 200
    static let maxPastMeetings = 3
    /// Keyword score a past meeting needs, not counting recency, to be offered as context.
    static let pastMeetingMinimumScore: Double = 4

    /// Static so xAI can cache it across questions.
    static let system = """
    You are a live meeting copilot. Someone on the user's call just asked a question. Answer it so the user can glance at it while they talk.
    - Reply with 1 to 3 short Markdown bullets ("- "), 60 words at most in total. No preamble, no heading, no restating the question.
    - Be factual. When the answer depends on the past meetings or notes provided, use them and cite the meeting as (Title, Mon D).
    - If you are not confident, say so in a few words.
    - Never invent company-specific facts such as numbers, dates, names, prices, owners, or decisions that are not in the context.
    - Reply with exactly SKIP and nothing else when the question does not need an answer: rhetorical, social, purely logistical, \
    addressed to a person about their own plans or opinion, or answerable only with private information you were not given.
    """

    static func requestOptions() -> [String: Any] {
        var extra: [String: Any] = ["max_completion_tokens": maxOutputTokens]
        let effort = Prefs.liveAnswersEffort.trimmingCharacters(in: .whitespaces)
        if !effort.isEmpty { extra["reasoning_effort"] = effort }
        if Prefs.liveAnswersPriority { extra["service_tier"] = "priority" }
        return extra
    }

    static func pastMeetings(for question: String, current: Meeting, in meetings: [Meeting]) -> [Meeting] {
        guard !meetings.isEmpty else { return [] }
        let query = question + " " + current.title
        return Array(LibraryAsk.matching(meetings, query: query, minimumScore: pastMeetingMinimumScore).prefix(maxPastMeetings))
    }

    static func messages(
        card: LiveAnswerCard,
        meeting: Meeting,
        recent: [Utterance],
        past: [Meeting],
        templateName: String,
        myName: String
    ) -> [XAIClient.Message] {
        var header = "Meeting: \(meeting.title) (\(templateName)), started \(meeting.startedAt.formatted(date: .abbreviated, time: .shortened))\n"
        header += "The user is \(myName.isEmpty ? "Me" : myName).\n"
        if !meeting.attendees.isEmpty { header += "Invitees: \(meeting.attendees.prefix(15).joined(separator: ", "))\n" }

        var pastBlock = ""
        if !past.isEmpty {
            pastBlock = "\nRelevant past meetings:\n"
            for m in past {
                let snippet = LibraryAsk.snippet(m, query: card.question, limit: 500)
                pastBlock += "- \(m.title) (\(m.startedAt.formatted(.dateTime.month(.abbreviated).day()))): \(snippet)\n"
            }
        }

        let notes = meeting.userNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let notesBlock = notes.isEmpty ? "" : "\nUser's rough notes so far:\n\(String(notes.suffix(1_500)))\n"

        let who = card.asker == "You" ? "the user" : card.asker
        var ask = "\nQuestion from \(who) at [\(Meeting.timestamp(card.askedAt))]: \(card.question)"
        if card.typed { ask += "\nThe user typed this question. Always answer it; never reply SKIP." }

        let fixed = header.count + pastBlock.count + notesBlock.count + ask.count + 40
        let lines = recent.map { "[\(Meeting.timestamp($0.start))] \(meeting.displayName(for: $0.speakerKey, myName: myName)): \($0.text)" }
        let transcript = tail(lines, budget: max(1_000, contextBudget - fixed))
        let transcriptBlock = transcript.isEmpty ? "" : "\nRecent transcript (last 3 minutes):\n\(transcript)\n"

        return [
            .init(role: "system", content: system),
            .init(role: "user", content: header + transcriptBlock + notesBlock + pastBlock + ask),
        ]
    }

    static func isSkip(_ answer: String) -> Bool {
        let a = answer.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)).uppercased()
        return a == "SKIP"
    }

    /// True while a streaming reply could still turn out to be SKIP.
    static func mightBeSkip(_ partial: String) -> Bool {
        let a = partial.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return a.isEmpty || "SKIP".hasPrefix(a) || a.hasPrefix("SKIP")
    }

    /// The newest lines that fit in `budget` characters, oldest first.
    private static func tail(_ lines: [String], budget: Int) -> String {
        var out: [String] = []
        var used = 0
        for line in lines.reversed() {
            guard used + line.count + 1 <= budget else { break }
            out.append(line)
            used += line.count + 1
        }
        return out.reversed().joined(separator: "\n")
    }
}
