import Foundation

/// A contiguous stretch of a meeting about one theme. Times are meeting seconds.
struct Chapter: Codable, Hashable {
    var title: String
    var start: Double
    var end: Double

    var length: Double { max(0, end - start) }
}

/// Topic chapters: Grok splits the conversation into themed, contiguous sections that cover it in order.
enum Chapters {
    static let maxCount = 8
    /// Chapters shorter than this merge into a neighbor.
    static let minLength = 45.0

    /// A chapter start as Grok wrote it, before clamping and merging.
    struct Entry: Equatable {
        var title: String
        var start: Double
    }

    /// Where the meeting's timeline ends: its duration or the last spoken word, whichever is later.
    static func end(of meeting: Meeting) -> Double {
        max(meeting.duration, meeting.utterances.map(\.end).max() ?? 0)
    }

    /// The chapter that `seconds` falls in. Times before the first chapter fall in the first.
    static func index(at seconds: Double, in chapters: [Chapter]) -> Int? {
        guard !chapters.isEmpty else { return nil }
        return chapters.lastIndex { $0.start <= seconds } ?? 0
    }

    // MARK: Parsing

    /// Splits a trailing "Chapters:" block off Grok's notes. The block may come before or after the Topics line.
    /// Returns the reply without the block, and the entries, or nil entries when there is no block.
    static func split(from reply: String) -> (text: String, entries: [Entry]?) {
        let lines = reply.components(separatedBy: "\n")
        guard let header = lines.lastIndex(where: isHeader) else { return (reply, nil) }
        var entries: [Entry] = []
        var stop = header + 1
        while stop < lines.count {
            let line = lines[stop]
            if let entry = entry(in: line) {
                entries.append(entry)
            } else if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                break
            }
            stop += 1
        }
        // Only a Topics line or a rule may follow the block, so a "Chapters" heading inside the notes stays.
        let rest = lines[stop...].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard rest.allSatisfy({ $0 == "---" || Topics.topicsList(in: $0) != nil }) else { return (reply, nil) }

        var before = Array(lines[..<header])
        while let tail = before.last?.trimmingCharacters(in: .whitespaces), tail.isEmpty || tail == "---" {
            before.removeLast()
        }
        let text = (before + lines[stop...]).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return (text, entries.isEmpty ? nil : entries)
    }

    /// "Chapters:", "## Chapters", or "**Chapters:**".
    private static func isHeader(_ line: String) -> Bool {
        line.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "#*_: \t")) == "chapters"
    }

    /// Every chapter line in a reply, with or without a "Chapters:" header. For the Find chapters call.
    static func entries(in reply: String) -> [Entry] {
        reply.components(separatedBy: "\n").compactMap(entry(in:))
    }

    /// "[04:12] Pricing and Packaging", tolerating bullets, numbering, emphasis, and a dash after the time.
    static func entry(in line: String) -> Entry? {
        let pattern = #"^\s*(?:[-*•]\s+|\d{1,2}[.)]\s+)?[*_]*[\[(]?(\d{1,2}(?::\d{2}){1,2})[\])]?[*_]*\s*(?:[-–—:|·]\s*)?(.+?)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let timeRange = Range(match.range(at: 1), in: line),
              let titleRange = Range(match.range(at: 2), in: line),
              let start = seconds(from: String(line[timeRange]))
        else { return nil }
        let title = String(line[titleRange]).trimmingCharacters(in: CharacterSet(charactersIn: "*_ "))
        return title.isEmpty ? nil : Entry(title: title, start: start)
    }

    /// "mm:ss" or "h:mm:ss".
    static func seconds(from timestamp: String) -> Double? {
        let parts = timestamp.split(separator: ":").map { Int($0) }
        guard parts.allSatisfy({ $0 != nil }) else { return nil }
        let p = parts.compactMap { $0 }
        switch p.count {
        case 2 where p[1] < 60: return Double(p[0] * 60 + p[1])
        case 3 where p[1] < 60 && p[2] < 60: return Double(p[0] * 3600 + p[1] * 60 + p[2])
        default: return nil
        }
    }

    // MARK: Building

    /// Turns raw entries into chapters that cover 0 to `end` in order: titles normalized as topics,
    /// times clamped and sorted, duplicates dropped, neighbors on one theme joined, short chapters merged.
    static func build(_ entries: [Entry], end: Double, vocabulary: [String] = []) -> [Chapter]? {
        guard end > 0 else { return nil }
        var starts: [Entry] = []
        for e in entries.enumerated().sorted(by: { $0.element.start != $1.element.start ? $0.element.start < $1.element.start : $0.offset < $1.offset }).map(\.element) {
            guard e.start < end, let title = Topics.normalize([e.title], vocabulary: vocabulary).first else { continue }
            if starts.last?.start == e.start { continue }
            starts.append(Entry(title: title, start: max(0, e.start)))
        }
        guard !starts.isEmpty else { return nil }
        starts[0].start = 0

        var chapters = starts.enumerated().map { i, e in
            Chapter(title: e.title, start: e.start, end: i + 1 < starts.count ? starts[i + 1].start : end)
        }
        joinSameTitle(&chapters)
        while chapters.count > 1, let i = chapters.indices.min(by: { chapters[$0].length < chapters[$1].length }),
              chapters.count > maxCount || chapters[i].length < minLength {
            let j: Int
            if i == 0 { j = 1 } else if i == chapters.count - 1 { j = i - 1 } else {
                j = chapters[i - 1].length <= chapters[i + 1].length ? i - 1 : i + 1
            }
            if j < i { chapters[j].end = chapters[i].end } else { chapters[j].start = chapters[i].start }
            chapters.remove(at: i)
            joinSameTitle(&chapters)
        }
        return chapters
    }

    private static func joinSameTitle(_ chapters: inout [Chapter]) {
        var i = 1
        while i < chapters.count {
            if Topics.key(chapters[i].title) == Topics.key(chapters[i - 1].title) {
                chapters[i - 1].end = chapters[i].end
                chapters.remove(at: i)
            } else {
                i += 1
            }
        }
    }

    /// The meeting's topics: unique chapter titles, most total time first, at most five.
    static func topics(from chapters: [Chapter], vocabulary: [String] = []) -> [String] {
        var totals: [String: (title: String, seconds: Double, first: Int)] = [:]
        for (i, c) in chapters.enumerated() {
            let k = Topics.key(c.title)
            if let t = totals[k] {
                totals[k] = (t.title, t.seconds + c.length, t.first)
            } else {
                totals[k] = (c.title, c.length, i)
            }
        }
        let ordered = totals.values.sorted { $0.seconds != $1.seconds ? $0.seconds > $1.seconds : $0.first < $1.first }
        return Topics.normalize(ordered.map(\.title), vocabulary: vocabulary)
    }

    // MARK: Prompt and export

    /// Prompt rules for the chapter block, shared by the notes call and Find chapters. Follows `Topics.rules`.
    static let rules = """
    - Split the whole conversation into 3 to 8 chapters: contiguous stretches in time order that together cover it from start to end. A meeting under 5 minutes may have 1 or 2.
    - Write one line per chapter: its start time in brackets, copied exactly from the transcript line where that subject begins, then its title. The first chapter starts at the first transcript line.
    - Title each chapter as a theme, following the topic rules: a 2 to 4 word Title Case noun phrase naming a subject area. Reuse an existing topic name or one of your Topics when it fits.
    - Each chapter should last at least a minute. Join neighboring stretches on the same theme into one chapter.
    """

    /// Markdown lines for the call summary in exports.
    static func markdown(_ chapters: [Chapter]) -> String {
        guard !chapters.isEmpty else { return "" }
        return "- Chapters:\n" + chapters.map { "  - [\(Meeting.timestamp($0.start))] \($0.title) (\(Meeting.durationLabel($0.length)))\n" }.joined()
    }
}
