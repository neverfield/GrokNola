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

    static let playHost = "play"
    /// Marks a citation that plays audio. The variation selector keeps it from rendering as an emoji.
    static let playGlyph = "▶\u{FE0E}"

    /// "5:17" or "1:02:03": no leading zero on the first unit.
    static func label(_ seconds: Double) -> String {
        let s = max(0, Int(seconds))
        if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) }
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// What a citation reads as: "▶ 5:17" when it plays audio, "5:17" when it opens the transcript.
    /// The space does not break, so a citation never wraps across lines.
    static func displayText(_ seconds: Double, playable: Bool) -> String {
        playable ? "\(playGlyph)\u{00A0}\(label(seconds))" : label(seconds)
    }

    /// One citation's link: play when the audio is on disk, else the transcript.
    static func url(meetingID: UUID, seconds: Double, playable: Bool) -> URL? {
        URL(string: playable ? playLink(meetingID: meetingID, seconds: seconds) : link(meetingID: meetingID, seconds: seconds))
    }

    /// The transcript link for a citation link of either kind, for Option-click and the context menu.
    static func transcriptURL(for url: URL) -> URL? {
        guard let t = playTarget(from: url) ?? target(from: url) else { return nil }
        return URL(string: link(meetingID: t.meetingID, seconds: t.seconds))
    }

    /// A bracketed citation group in plain text: its range and the times it lists.
    struct Span {
        var range: Range<String.Index>
        var nsRange: NSRange
        var times: [Double]
    }

    /// Bracketed citations in `text`, skipping ones that are already the text of a Markdown link.
    static func spans(in text: String) -> [Span] {
        let ns = text as NSString
        return pattern.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            let times = ns.substring(with: match.range(at: 1))
                .split(whereSeparator: { $0 == "," || $0 == ";" })
                .compactMap { seconds(from: $0.trimmingCharacters(in: .whitespaces)) }
            guard !times.isEmpty, let range = Range(match.range, in: text) else { return nil }
            return Span(range: range, nsRange: match.range, times: times)
        }
    }

    static func link(meetingID: UUID, seconds: Double) -> String {
        "\(LibraryAsk.linkScheme)://\(host)/\(meetingID.uuidString)/\(Int(seconds))"
    }

    static func playLink(meetingID: UUID, seconds: Double) -> String {
        "\(LibraryAsk.linkScheme)://\(playHost)/\(meetingID.uuidString)/\(Int(seconds))"
    }

    static func target(from url: URL) -> (meetingID: UUID, seconds: Double)? {
        parse(url, host: host)
    }

    static func playTarget(from url: URL) -> (meetingID: UUID, seconds: Double)? {
        parse(url, host: playHost)
    }

    private static func parse(_ url: URL, host: String) -> (meetingID: UUID, seconds: Double)? {
        guard url.scheme == LibraryAsk.linkScheme, url.host == host else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 2, let id = UUID(uuidString: parts[0]), let seconds = Double(parts[1]) else { return nil }
        return (id, seconds)
    }

    static func contains(_ markdown: String) -> Bool {
        linkify(markdown, meetingID: UUID()) != markdown
    }

    /// Parses "mm:ss" or "h:mm:ss" into seconds.
    static func seconds(from timestamp: String) -> Double? {
        let parts = timestamp.split(separator: ":").map { Int($0) }
        guard (2...3).contains(parts.count), parts.allSatisfy({ $0 != nil }) else { return nil }
        let values = parts.compactMap { $0 }
        guard values.dropFirst().allSatisfy({ $0 < 60 }) else { return nil }
        return Double(values.reduce(0) { $0 * 60 + $1 })
    }

    /// The index of the span a citation at `seconds` points at: the latest one that contains it, else the nearest.
    /// Citations are whole seconds, so a span may start up to one second after the cited time.
    static func index<T>(at seconds: Double, in items: [T], start: (T) -> Double, end: (T) -> Double) -> Int? {
        var best: (index: Int, start: Double, distance: Double)?
        for (i, item) in items.enumerated() {
            let s = start(item), e = max(s, end(item))
            let distance = s >= seconds + 1 ? s - seconds : max(0, seconds - e)
            if let b = best, distance > b.distance || (distance == b.distance && s < b.start) { continue }
            best = (i, s, distance)
        }
        return best?.index
    }

    /// Rewrites bare citations into Markdown links, one per time. Each plays its clip when `playable`,
    /// else opens the transcript. Text without citations comes back unchanged.
    static func linkify(_ markdown: String, meetingID: UUID, playable: Bool = false) -> String {
        var out = markdown
        for span in spans(in: markdown).reversed() {
            let links = span.times.map { seconds in
                let target = playable ? playLink(meetingID: meetingID, seconds: seconds) : link(meetingID: meetingID, seconds: seconds)
                return "[\(displayText(seconds, playable: playable))](\(target))"
            }
            // Indices of `markdown` are not valid in the edited copy, so convert from UTF-16 offsets.
            guard let range = Range(span.nsRange, in: out) else { continue }
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
