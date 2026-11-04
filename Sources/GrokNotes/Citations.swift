import Foundation

/// Transcript citations like `[12:04]` or `[1:02:03]` in notes and answers, linked as
/// `groknotes://transcript/<meetingID>/<seconds>`.
enum Citations {
    static let host = "transcript"

    private static let time = #"(?:\d{1,2}:)?\d{1,2}:\d{2}"#
    /// A bracketed timestamp or comma/semicolon list of them, not already the text of a Markdown link.
    private static let pattern = try! NSRegularExpression(
        pattern: #"\[(\#(time)(?:\s*[,;]\s*\#(time))*)\](?!\()"#
    )
    private static let anyCitation = try! NSRegularExpression(pattern: #"\s*\[\#(time)(?:\s*[,;]\s*\#(time))*\]"#)

    static func link(meetingID: UUID, seconds: Double) -> String {
        "\(LibraryAsk.linkScheme)://\(host)/\(meetingID.uuidString)/\(Int(seconds))"
    }

    static func target(from url: URL) -> (meetingID: UUID, seconds: Double)? {
        guard url.scheme == LibraryAsk.linkScheme, url.host == host else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 2, let id = UUID(uuidString: parts[0]), let seconds = Double(parts[1]) else { return nil }
        return (id, seconds)
    }

    /// Parses "mm:ss" or "h:mm:ss" into seconds.
    static func seconds(from timestamp: String) -> Double? {
        let parts = timestamp.split(separator: ":").map { Int($0) }
        guard (2...3).contains(parts.count), parts.allSatisfy({ $0 != nil }) else { return nil }
        let values = parts.compactMap { $0 }
        guard values.dropFirst().allSatisfy({ $0 < 60 }) else { return nil }
        return Double(values.reduce(0) { $0 * 60 + $1 })
    }

    /// Rewrites bare citations into Markdown links. Text without citations comes back unchanged.
    static func linkify(_ markdown: String, meetingID: UUID) -> String {
        let ns = markdown as NSString
        var out = markdown
        for match in pattern.matches(in: markdown, range: NSRange(location: 0, length: ns.length)).reversed() {
            let inner = ns.substring(with: match.range(at: 1))
            let links = inner.split(whereSeparator: { $0 == "," || $0 == ";" }).compactMap { raw -> String? in
                let stamp = raw.trimmingCharacters(in: .whitespaces)
                guard let seconds = seconds(from: stamp) else { return nil }
                return "[\(stamp)](\(link(meetingID: meetingID, seconds: seconds)))"
            }
            guard !links.isEmpty, let range = Range(match.range, in: out) else { continue }
            out.replaceSubrange(range, with: links.joined(separator: " "))
        }
        return out
    }

    /// Removes citations, for places like titles that should read as plain text.
    static func strip(_ text: String) -> String {
        anyCitation.stringByReplacingMatches(
            in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: ""
        ).trimmingCharacters(in: .whitespaces)
    }
}
