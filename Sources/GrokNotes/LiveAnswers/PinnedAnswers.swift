import Foundation

/// The plain-text block a pinned live answer adds to the rough notes, which are edited as plain text:
///
///     📌 Q (Alex, 12:04): What does it cost?
///     A: $40 per seat
///
/// Earlier versions wrote a Markdown quote (`> **Q (Alex, 12:04):** …` then `> …` lines). Those are
/// converted to this form when the notes are shown or a card is pinned or unpinned.
enum PinnedAnswers {
    static let marker = "📌 Q ("

    static func block(asker: String, time: String, question: String, answer: String) -> String {
        let q = question.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        return "\(marker)\(asker), \(time)): \(q)\n" + answerLines(answer)
    }

    /// The block the earlier versions wrote. Kept so old notes can be recognized.
    static func legacyBlock(asker: String, time: String, question: String, answer: String) -> String {
        var block = "> **Q (\(asker), \(time)):** \(question)\n"
        block += answer.split(separator: "\n", omittingEmptySubsequences: false).map { "> \($0)" }.joined(separator: "\n")
        return block
    }

    /// "A: text" for a one-line answer, or "A:" then one "• " line per bullet.
    private static func answerLines(_ answer: String) -> String {
        let lines = answer.split(separator: "\n").map { plain(String($0)) }.filter { !$0.isEmpty }
        guard lines.count > 1 else { return "A: " + (lines.first.map(stripBullet) ?? "") }
        return "A:\n" + lines.map { line in
            let text = stripBullet(line)
            return text == line && line.first?.isNumber == true ? line : "• " + text
        }.joined(separator: "\n")
    }

    private static func stripBullet(_ line: String) -> String {
        for prefix in ["- ", "* ", "+ ", "• "] where line.hasPrefix(prefix) {
            return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        return line
    }

    /// Drops the Markdown a short answer tends to carry: bold, italics with underscores, code, headings, and links.
    static func plain(_ line: String) -> String {
        var s = line.trimmingCharacters(in: .whitespaces)
        while s.hasPrefix("#") { s.removeFirst() }
        s = s.trimmingCharacters(in: .whitespaces)
        s = s.replacingOccurrences(of: #"\[([^\]]+)\]\((https?://[^)\s]+)\)"#, with: "$1 ($2)", options: .regularExpression)
        for token in ["**", "__", "`"] { s = s.replacingOccurrences(of: token, with: "") }
        return s
    }

    // MARK: Old Markdown blocks

    private static let legacyQuestion = try! NSRegularExpression(pattern: #"^> \*\*Q \((.+?)\):\*\* ?(.*)$"#)

    /// Rewrites every old Markdown pinned block in `notes` as plain text. Returns nil when there are none.
    static func migrateLegacy(_ notes: String) -> String? {
        guard notes.contains("> **Q (") else { return nil }
        let lines = notes.components(separatedBy: "\n")
        var out: [String] = []
        var changed = false
        var i = 0
        while i < lines.count {
            let line = lines[i]
            let ns = line as NSString
            guard let match = legacyQuestion.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else {
                out.append(line)
                i += 1
                continue
            }
            let header = ns.substring(with: match.range(at: 1))
            let question = ns.substring(with: match.range(at: 2))
            var answer: [String] = []
            i += 1
            while i < lines.count, lines[i].hasPrefix(">") {
                answer.append(String(lines[i].dropFirst(lines[i].hasPrefix("> ") ? 2 : 1)))
                i += 1
            }
            let q = question.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
            out.append(contentsOf: ("\(marker)\(header)): \(q)\n" + answerLines(answer.joined(separator: "\n"))).components(separatedBy: "\n"))
            changed = true
        }
        return changed ? out.joined(separator: "\n") : nil
    }

    /// `notes` without `block`, also when the block was converted from the old format since it was pinned.
    /// Nil when it is no longer there unchanged.
    static func removing(_ block: String, from notes: String) -> String? {
        var candidates = [block]
        if let migrated = migrateLegacy(block) { candidates.append(migrated) }
        guard let range = candidates.lazy.compactMap({ notes.range(of: $0) }).first else { return nil }
        let before = notes[..<range.lowerBound]
        let after = notes[range.upperBound...].drop { $0 == "\n" }
        let kept = before.reversed().drop { $0 == "\n" }.count
        guard kept > 0 else { return String(after) }
        guard !after.isEmpty else { return String(before.prefix(kept)) }
        return String(before) + after
    }
}
