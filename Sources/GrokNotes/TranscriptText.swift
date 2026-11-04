import Foundation

/// A run of consecutive utterances by one speaker, as the Transcript tab shows it.
struct TranscriptBlock: Identifiable {
    let id: UUID
    let speakerKey: String
    let start: Double
    var end: Double
    var lines: [(id: UUID, text: String)]
}

/// Transcript blocks, their chapters, and the plain text the copy buttons put on the pasteboard.
enum TranscriptText {
    /// What to copy.
    enum Scope: Equatable {
        /// Every block, with the meeting title and date first.
        case all
        /// The blocks of the chapter at this index, under its heading.
        case chapter(Int)
        /// One block.
        case block(UUID)
        /// A block and the rest of its chapter.
        case toChapterEnd(UUID)
    }

    static func blocks(from utterances: [Utterance]) -> [TranscriptBlock] {
        var blocks: [TranscriptBlock] = []
        for u in utterances {
            if var last = blocks.last, last.speakerKey == u.speakerKey {
                last.lines.append((id: u.id, text: u.text))
                last.end = max(last.end, u.end)
                blocks[blocks.count - 1] = last
            } else {
                blocks.append(TranscriptBlock(id: u.id, speakerKey: u.speakerKey, start: u.start, end: u.end, lines: [(u.id, u.text)]))
            }
        }
        return blocks
    }

    /// The chapter a block belongs to, by its start. Chapter starts are whole seconds copied from `[mm:ss]` stamps,
    /// so a block up to one second before a chapter start belongs to that chapter.
    static func chapterIndex(ofBlockAt start: Double, in chapters: [Chapter]) -> Int? {
        Chapters.index(at: start + 1, in: chapters)
    }

    /// `## Pricing (04:12–10:30)`
    static func heading(_ chapter: Chapter) -> String {
        "## \(chapter.title) (\(Meeting.timestamp(chapter.start))–\(Meeting.timestamp(chapter.end)))"
    }

    /// `[04:12] Dana: text`, the block's lines joined with spaces.
    static func line(_ block: TranscriptBlock, in meeting: Meeting, myName: String) -> String {
        let text = block.lines.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: " ")
        return "[\(Meeting.timestamp(block.start))] \(meeting.displayName(for: block.speakerKey, myName: myName)): \(text)"
    }

    /// Plain text for `scope`. Pass no chapters to leave headings out, for example while recording.
    static func text(_ meeting: Meeting, myName: String, chapters: [Chapter], scope: Scope) -> String {
        let blocks = blocks(from: meeting.utterances)
        let assigned = blocks.map { chapterIndex(ofBlockAt: $0.start, in: chapters) }
        let selected: [Int]
        var headings = false
        switch scope {
        case .all:
            selected = Array(blocks.indices)
            headings = true
        case .chapter(let c):
            selected = blocks.indices.filter { assigned[$0] == c }
            headings = true
        case .block(let id):
            selected = blocks.firstIndex { $0.id == id }.map { [$0] } ?? []
        case .toChapterEnd(let id):
            guard let i = blocks.firstIndex(where: { $0.id == id }) else { return "" }
            selected = Array(blocks.indices[i...].prefix { assigned[$0] == assigned[i] })
        }

        var out: [String] = []
        if scope == .all {
            out.append("\(meeting.title) · \(meeting.startedAt.formatted(date: .long, time: .shortened))")
        }
        if case .chapter(let c) = scope, selected.isEmpty, chapters.indices.contains(c) {
            out.append(heading(chapters[c]))
        }
        var current: Int?
        for i in selected {
            if headings, let c = assigned[i], c != current {
                if !out.isEmpty { out.append("") }
                out.append(heading(chapters[c]))
                current = c
            } else if scope == .all, out.count == 1 {
                out.append("")
            }
            out.append(line(blocks[i], in: meeting, myName: myName))
        }
        return out.joined(separator: "\n")
    }
}
