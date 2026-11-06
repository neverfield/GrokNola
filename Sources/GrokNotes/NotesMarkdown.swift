import Foundation

/// The block structure of notes Markdown, one line at a time. The reader renders from it,
/// the editor dims its markers, and checkbox clicks rewrite a line with it.
enum NotesMarkdown {
    enum Kind: Equatable {
        case heading(Int)
        case checkbox(done: Bool)
        case bullet
        /// The list marker as written, such as "1." or "2)".
        case numbered(String)
        case rule
        case fence
        case table
        case blank
        case paragraph
    }

    struct Line: Equatable {
        var kind: Kind
        /// List nesting from leading spaces, two per level.
        var indent: Int
        /// `>` quote depth.
        var quote: Int
        /// The line after its quote, indent, and block markers.
        var text: String
        /// UTF-16 length of everything before `text`.
        var markerLength: Int
    }

    static func lines(_ markdown: String) -> [String] {
        markdown.components(separatedBy: "\n")
    }

    static func parse(_ raw: String) -> Line {
        var rest = Substring(raw)
        var quote = 0
        while true {
            let trimmed = rest.drop { $0 == " " }
            guard trimmed.first == ">" else { break }
            quote += 1
            rest = trimmed.dropFirst()
            if rest.first == " " { rest = rest.dropFirst() }
        }
        let leading = rest.prefix { $0 == " " || $0 == "\t" }
        let indent = leading.reduce(0) { $0 + ($1 == "\t" ? 2 : 1) } / 2
        let body = rest.dropFirst(leading.count)

        func line(_ kind: Kind, text: Substring) -> Line {
            Line(kind: kind, indent: indent, quote: quote, text: String(text), markerLength: raw.utf16.count - text.utf16.count)
        }

        if body.allSatisfy(\.isWhitespace) { return line(.blank, text: body) }
        if body.hasPrefix("```") { return line(.fence, text: body) }
        if body.hasPrefix("|") { return line(.table, text: body) }

        let hashes = body.prefix { $0 == "#" }.count
        if (1...6).contains(hashes), body.dropFirst(hashes).first == " " {
            return line(.heading(hashes), text: body.dropFirst(hashes + 1))
        }

        let compact = body.filter { !$0.isWhitespace }
        if compact.count >= 3, let first = compact.first, "-*_".contains(first), compact.allSatisfy({ $0 == first }) {
            return line(.rule, text: body.dropFirst(body.count))
        }

        if let marker = body.first, "-*+".contains(marker), body.dropFirst().first == " " {
            let after = body.dropFirst(2)
            let box = after.prefix(3).lowercased()
            if box == "[ ]" || box == "[x]", after.count == 3 || after.dropFirst(3).first == " " {
                return line(.checkbox(done: box == "[x]"), text: after.dropFirst(3).drop { $0 == " " })
            }
            return line(.bullet, text: after)
        }

        let digits = body.prefix { $0.isASCII && $0.isNumber }
        if (1...3).contains(digits.count) {
            let after = body.dropFirst(digits.count)
            if let close = after.first, close == "." || close == ")", after.dropFirst().first == " " {
                return line(.numbered(String(digits) + String(close)), text: after.dropFirst(2))
            }
        }
        return line(.paragraph, text: body)
    }

    /// Flips the checkbox on one line. Nil when that line is not a checkbox.
    static func togglingCheckbox(atLine index: Int, in markdown: String) -> String? {
        var all = lines(markdown)
        guard all.indices.contains(index), case .checkbox(let done) = parse(all[index]).kind,
              let box = all[index].range(of: done ? "[x]" : "[ ]", options: .caseInsensitive) else { return nil }
        all[index].replaceSubrange(box, with: done ? "[ ]" : "[x]")
        return all.joined(separator: "\n")
    }
}
