import Foundation

/// Meeting topics are themes (subject areas), kept consistent across meetings so they can be counted.
enum Topics {
    static let maxPerMeeting = 5
    static let vocabularySize = 40

    /// How often each topic appears across `meetings`, most used first. Topics that differ only in
    /// case, spacing, punctuation, or "&" versus "and" count as one, under their most common spelling.
    /// `since` keeps meetings that started on or after that date.
    static func topicCounts(in meetings: [Meeting], since: Date? = nil) -> [(topic: String, count: Int)] {
        var counts: [String: Int] = [:]
        var spellings: [String: [String: Int]] = [:]
        for m in meetings {
            if let since, m.startedAt < since { continue }
            var seen = Set<String>()
            for topic in m.topics ?? [] {
                let k = key(topic)
                guard !k.isEmpty, seen.insert(k).inserted else { continue }
                counts[k, default: 0] += 1
                spellings[k, default: [:]][topic, default: 0] += 1
            }
        }
        return counts.map { k, count in
            let spelling = spellings[k]?.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }?.key ?? k
            return (topic: spelling, count: count)
        }
        .sorted { $0.count != $1.count ? $0.count > $1.count : $0.topic.localizedCaseInsensitiveCompare($1.topic) == .orderedAscending }
    }

    /// The user's most used topics, offered to Grok so it reuses names instead of inventing near-duplicates.
    static func vocabulary(from meetings: [Meeting], excluding id: UUID? = nil) -> [String] {
        topicCounts(in: meetings.filter { $0.id != id }).prefix(vocabularySize).map(\.topic)
    }

    /// Cleans Grok's topics: strips list marks and punctuation, Title Cases, maps to the vocabulary
    /// spelling when one matches, drops sentences, dedupes, and keeps at most five.
    static func normalize(_ raw: [String], vocabulary: [String] = []) -> [String] {
        var known: [String: String] = [:]
        for name in vocabulary where known[key(name)] == nil { known[key(name)] = name }
        var seen = Set<String>()
        var out: [String] = []
        for item in raw {
            var t = Citations.strip(item)
                .replacingOccurrences(of: #"^\s*(?:[-*•#]+|\d{1,2}[.)])\s*"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".;,:!?\"'*_`")))
            t = t.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            let words = t.split(separator: " ").count
            guard (1...6).contains(words), t.count <= 48 else { continue }
            let k = key(t)
            guard !k.isEmpty, seen.insert(k).inserted else { continue }
            out.append(known[k] ?? titleCase(t))
            if out.count == maxPerMeeting { break }
        }
        return out
    }

    /// Title Case that keeps acronyms like "API" and "Q4" and lowercases short joining words.
    static func titleCase(_ text: String) -> String {
        let minor: Set<String> = ["a", "an", "and", "as", "at", "by", "for", "in", "of", "on", "or", "the", "to", "vs", "with"]
        return text.split(separator: " ").enumerated().map { index, word in
            let lower = word.lowercased()
            if index > 0, minor.contains(lower) { return lower }
            return word.first.map { String($0).uppercased() + word.dropFirst() } ?? ""
        }.joined(separator: " ")
    }

    /// Matching key: lowercase letters and digits only, with "&" read as "and".
    static func key(_ topic: String) -> String {
        topic.lowercased()
            .replacingOccurrences(of: "&", with: " and ")
            .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init).joined()
    }

    /// Splits a trailing "Topics: a; b; c" line off Grok's notes. Returns the notes without it and
    /// the raw topics, or nil topics when the line is missing.
    static func splitTopicsLine(from reply: String) -> (notes: String, topics: [String]?) {
        var lines = reply.components(separatedBy: "\n")
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
        guard let last = lines.last, let list = topicsList(in: last) else {
            return (reply.trimmingCharacters(in: .whitespacesAndNewlines), nil)
        }
        lines.removeLast()
        while let tail = lines.last?.trimmingCharacters(in: .whitespaces),
              tail.isEmpty || tail == "---" || tail.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "# ")) == "topics" {
            lines.removeLast()
        }
        return (lines.joined(separator: "\n"), list)
    }

    /// The items of a "Topics: a; b; c" line, tolerating Markdown emphasis around the label.
    static func topicsList(in line: String) -> [String]? {
        let pattern = #"^\s*(?:[-*#]+\s*)?[*_]*topics[*_]*\s*:\s*[*_]*(.*?)[*_]*\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 1), in: line)
        else { return nil }
        let body = String(line[range])
        let separator: Character = body.contains(";") ? ";" : ","
        let items = body.split(separator: separator).map { String($0) }
        return items.isEmpty ? nil : items
    }

    /// Prompt rules shared by the notes call and Find topics.
    static func rules(template: SummaryTemplate, vocabulary: [String]) -> String {
        var rules = """
        Topics are the 3 to 5 THEMES of the meeting: the subject areas it spent time on, most discussed first.
        - Each theme is a 2 to 4 word noun phrase in Title Case naming a subject area, like "Pricing and Packaging", "Onboarding Friction", or "Q4 Hiring Plan".
        - A theme is never a fact, a sentence, a decision, a number, a date, or only a person's name. Bad: "Budget is capped at $50k", "Ship on Friday", "Sarah". Good: "Budget Planning", "Release Timeline".
        - Prefer broad, reusable names that would fit other meetings on the same subject over one-off details.
        - No trailing punctuation.
        """
        let focus = template.topicFocus.trimmingCharacters(in: .whitespacesAndNewlines)
        if !focus.isEmpty { rules += "\n- For this kind of meeting, themes are \(focus)" }
        if !vocabulary.isEmpty {
            rules += "\n- The user's existing topics are listed below. When a theme matches one of them, even if you would word it differently, reuse that exact name. Create a new name only for a subject none of them covers."
        }
        return rules
    }

    static func vocabularyBlock(_ vocabulary: [String]) -> String {
        vocabulary.isEmpty ? "" : "\n\nExisting topics (most used first): \(vocabulary.joined(separator: "; "))"
    }
}
