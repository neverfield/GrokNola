import Foundation

/// Aggregates over meetings for the Home dashboard. Reads notes, topics, tags, and utterance
/// timings only, never transcript text, so it stays cheap for hundreds of meetings.
enum Insights {
    struct Count: Identifiable, Hashable {
        var name: String
        var count: Int
        var id: String { name.lowercased() }
    }

    enum Trend {
        case new, up, down, flat
    }

    struct Trending: Identifiable, Hashable {
        var name: String
        var count: Int
        var previous: Int
        var id: String { name.lowercased() }

        var trend: Trend {
            if previous == 0 { return .new }
            if count > previous { return .up }
            if count < previous { return .down }
            return .flat
        }
    }

    /// How many meetings in `[since, until)` mention each topic. Groups case-insensitively and
    /// keeps the most common casing. Most frequent first.
    static func topicCounts(in meetings: [Meeting], since: Date, until: Date? = nil) -> [Count] {
        counts(in: meetings, since: since, until: until) { $0.topics ?? [] }
    }

    static func tagCounts(in meetings: [Meeting], since: Date, until: Date? = nil) -> [Count] {
        counts(in: meetings, since: since, until: until) { $0.tagList }
    }

    private static func counts(in meetings: [Meeting], since: Date, until: Date?, values: (Meeting) -> [String]) -> [Count] {
        var totals: [String: Int] = [:]
        var casings: [String: [String: Int]] = [:]
        // Ties between casings go to the one seen first, so pass meetings newest first.
        var firstSeen: [String: Int] = [:]
        for m in meetings where m.startedAt >= since && (until == nil || m.startedAt < until!) {
            var seen = Set<String>()
            for raw in values(m) {
                let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                let key = name.lowercased()
                guard !key.isEmpty, seen.insert(key).inserted else { continue }
                totals[key, default: 0] += 1
                casings[key, default: [:]][name, default: 0] += 1
                if firstSeen[name] == nil { firstSeen[name] = firstSeen.count }
            }
        }
        return totals.map { key, count in
            let name = casings[key]?.max {
                $0.value != $1.value ? $0.value < $1.value : (firstSeen[$0.key] ?? 0) > (firstSeen[$1.key] ?? 0)
            }?.key ?? key
            return Count(name: name, count: count)
        }
        .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Ranks the current window and compares each entry with the window before it.
    static func trending(current: [Count], previous: [Count]) -> [Trending] {
        let before = Dictionary(previous.map { ($0.id, $0.count) }, uniquingKeysWith: +)
        return current.map { Trending(name: $0.name, count: $0.count, previous: before[$0.id] ?? 0) }
    }

    // MARK: Time in meetings

    struct Glance {
        var meetings = 0
        var seconds: Double = 0
        /// The user's share of talk time, 0 to 1, or nil when no meeting has a transcript.
        var myShare: Double?
    }

    static func glance(_ meetings: [Meeting], since: Date, until: Date? = nil) -> Glance {
        var g = Glance()
        var mine: Double = 0
        var total: Double = 0
        for m in meetings where m.startedAt >= since && (until == nil || m.startedAt < until!) {
            g.meetings += 1
            g.seconds += m.duration
            for u in m.utterances {
                let s = max(0, u.end - u.start)
                total += s
                if u.speakerKey == Meeting.meKey { mine += s }
            }
        }
        g.myShare = total > 0 ? mine / total : nil
        return g
    }

    // MARK: Notes parsing

    struct ActionItem: Identifiable, Hashable {
        var meetingID: UUID
        /// Line number in the meeting's `enhancedNotes`.
        var line: Int
        /// The line exactly as it appears in the notes, used to check it before rewriting.
        var raw: String
        var owner: String?
        var task: String
        var done: Bool
        var id: String { "\(meetingID.uuidString)#\(line)" }
    }

    /// Checkbox lines anywhere in the notes. Checkboxes only appear in action items, so this
    /// still works when a template renames the "Action items" heading.
    static func actionItems(in notes: String, meetingID: UUID) -> [ActionItem] {
        notes.components(separatedBy: "\n").enumerated().compactMap { index, raw in
            guard let parsed = checkbox(raw) else { return nil }
            let (owner, task) = splitOwner(parsed.text)
            return ActionItem(meetingID: meetingID, line: index, raw: raw, owner: owner, task: task, done: parsed.done)
        }
    }

    static func checkbox(_ raw: String) -> (done: Bool, text: String)? {
        let line = raw.trimmingCharacters(in: .whitespaces)
        let lower = line.lowercased()
        for marker in ["- ", "* "] {
            if lower.hasPrefix(marker + "[ ] ") { return (false, String(line.dropFirst(6))) }
            if lower.hasPrefix(marker + "[x] ") { return (true, String(line.dropFirst(6))) }
        }
        return nil
    }

    /// Rewrites one checkbox line, or returns nil when the line no longer matches.
    static func setting(_ item: ActionItem, done: Bool, in notes: String) -> String? {
        var lines = notes.components(separatedBy: "\n")
        let index: Int
        if item.line < lines.count, lines[item.line] == item.raw {
            index = item.line
        } else if let found = lines.firstIndex(of: item.raw) {
            index = found
        } else {
            return nil
        }
        let line = lines[index]
        guard let box = line.range(of: done ? "[ ]" : "[x]", options: .caseInsensitive) else { return nil }
        lines[index] = line.replacingCharacters(in: box, with: done ? "[x]" : "[ ]")
        return lines.joined(separator: "\n")
    }

    private static func splitOwner(_ text: String) -> (String?, String) {
        guard let colon = text.firstIndex(of: ":") else { return (nil, text) }
        let owner = text[..<colon].replacingOccurrences(of: "**", with: "").trimmingCharacters(in: .whitespaces)
        let task = text[text.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        let looksLikeName = !owner.isEmpty && owner.count <= 40 && !owner.contains("[") && !owner.contains("(")
            && owner.split(separator: " ").count <= 4 && !task.isEmpty
        return looksLikeName ? (owner, task) : (nil, text)
    }

    /// Bullet lines under the first `## ` heading whose title starts with one of `titles`.
    static func section(_ notes: String, titles: [String]) -> [String] {
        var inside = false
        var out: [String] = []
        for raw in notes.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") {
                if inside { break }
                let title = line.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces).lowercased()
                inside = line.hasPrefix("## ") && titles.contains { title.hasPrefix($0) }
                continue
            }
            if inside, !line.isEmpty { out.append(line) }
        }
        return out
    }

    static func decisions(in notes: String) -> [String] {
        section(notes, titles: ["decision"]).compactMap { line in
            guard line.hasPrefix("- ") || line.hasPrefix("* ") else { return nil }
            let text = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            return text.isEmpty ? nil : text
        }
    }

    /// The "Summary" section as plain text, else the first lines of the notes.
    static func summary(of meeting: Meeting) -> String? {
        let plain: (String) -> String = { line in
            var t = line
            for prefix in ["- [ ] ", "- [x] ", "- ", "* "] where t.lowercased().hasPrefix(prefix) {
                t = String(t.dropFirst(prefix.count))
                break
            }
            t = t.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "__", with: "")
            return Citations.strip(t)
        }
        if let notes = meeting.enhancedNotes, !notes.isEmpty {
            let summary = section(notes, titles: ["summary", "overview", "tl;dr", "tldr"]).map(plain)
            if !summary.isEmpty { return summary.joined(separator: " ") }
            let lines = notes.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("#") }
                .prefix(2)
                .map(plain)
            if !lines.isEmpty { return lines.joined(separator: " ") }
        }
        let rough = meeting.userNotes.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .prefix(2)
            .map(plain)
        return rough.isEmpty ? nil : rough.joined(separator: " ")
    }

    /// Named remote speakers, else calendar invitees.
    static func participants(of meeting: Meeting, myName: String) -> [String] {
        let named = meeting.speakerKeys
            .filter { $0 != Meeting.meKey }
            .compactMap { meeting.speakers[$0]?.name }
        let names = uniqueNames(named)
        if !names.isEmpty { return names }
        return uniqueNames(meeting.attendees.filter { $0.caseInsensitiveCompare(myName) != .orderedSame })
    }
}
