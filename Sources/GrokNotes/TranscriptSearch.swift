import SwiftUI

/// Find in the Transcript tab: every occurrence of a query, in reading order.
enum TranscriptSearch {
    struct Match: Equatable {
        var blockID: UUID
        var lineID: UUID
        /// Which occurrence within the line, from 0.
        var occurrence: Int
    }

    private static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    static func ranges(of query: String, in text: String) -> [Range<String.Index>] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        var out: [Range<String.Index>] = []
        var from = text.startIndex
        while from < text.endIndex, let r = text.range(of: q, options: options, range: from..<text.endIndex) {
            out.append(r)
            from = r.upperBound
        }
        return out
    }

    static func matches(_ query: String, in blocks: [TranscriptBlock]) -> [Match] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return blocks.flatMap { block in
            block.lines.flatMap { line in
                ranges(of: query, in: line.text).indices.map { Match(blockID: block.id, lineID: line.id, occurrence: $0) }
            }
        }
    }

    /// The line with every match tinted and `current`, an occurrence index, tinted strongest.
    static func highlighted(_ text: String, query: String, current: Int?) -> AttributedString {
        var out = AttributedString(text)
        for (i, r) in ranges(of: query, in: text).enumerated() {
            guard let range = Range(r, in: out) else { continue }
            out[range].backgroundColor = i == current ? Color.yellow.opacity(0.85) : Color.yellow.opacity(0.3)
            if i == current { out[range].foregroundColor = .black }
        }
        return out
    }
}
