import SwiftUI

enum TagColor: String, Codable, CaseIterable {
    case gray, red, orange, yellow, green, teal, blue, indigo, purple, pink

    var color: Color {
        switch self {
        case .gray: return .gray
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .teal: return .teal
        case .blue: return .blue
        case .indigo: return .indigo
        case .purple: return .purple
        case .pink: return .pink
        }
    }

    /// A stable color for tags the user has not colored.
    static func automatic(for name: String) -> TagColor {
        let palette: [TagColor] = [.blue, .orange, .purple, .teal, .pink, .green, .indigo, .red, .yellow]
        let hash = name.lowercased().utf8.reduce(5381) { ($0 &* 33) &+ Int($1) }
        return palette[abs(hash) % palette.count]
    }
}

/// One entry in the tag catalog. User tags are created in Settings or the inspector.
/// Dynamic tags were proposed by Grok and stay dynamic until the user keeps them.
struct TagDefinition: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    /// Guides Grok on when the tag applies.
    var detail: String?
    var color: TagColor?
    var dynamic: Bool?

    var isDynamic: Bool { dynamic ?? false }
    var displayColor: Color { (color ?? TagColor.automatic(for: name)).color }
}

struct TagBackfillProgress {
    var done: Int
    var total: Int
}

/// The global tag catalog at ~/Library/Application Support/GrokNotes/tags.json.
/// Renames and deletes that touch meetings go through `AppState` so meetings stay in sync.
@MainActor
final class TagCatalog: ObservableObject {
    @Published private(set) var tags: [TagDefinition] = []
    /// Meetings Grok is tagging right now.
    @Published var tagging: Set<UUID> = []
    @Published var backfill: TagBackfillProgress?
    var backfillCancelled = false
    private let url: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GrokNotes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("tags.json")
        if let data = try? Data(contentsOf: url) {
            tags = (try? JSONDecoder().decode([TagDefinition].self, from: data)) ?? []
        }
    }

    var userTags: [TagDefinition] { tags.filter { !$0.isDynamic } }
    var dynamicTags: [TagDefinition] { tags.filter(\.isDynamic) }

    func definition(named name: String) -> TagDefinition? {
        tags.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    func color(for name: String) -> Color {
        definition(named: name)?.displayColor ?? TagColor.automatic(for: name).color
    }

    /// The catalog spelling of `name`, or the cleaned-up name when it is new.
    func canonical(_ name: String) -> String {
        let clean = Self.clean(name)
        return definition(named: clean)?.name ?? clean
    }

    /// Adds a tag when it is missing. A user add of an existing dynamic tag keeps it.
    @discardableResult
    func register(_ name: String, dynamic: Bool, detail: String? = nil, color: TagColor? = nil) -> String {
        let clean = Self.clean(name)
        guard !clean.isEmpty else { return clean }
        if let index = tags.firstIndex(where: { $0.name.caseInsensitiveCompare(clean) == .orderedSame }) {
            if !dynamic, tags[index].isDynamic { tags[index].dynamic = nil }
            if let detail, !detail.isEmpty { tags[index].detail = detail }
            if let color { tags[index].color = color }
            save()
            return tags[index].name
        }
        tags.append(TagDefinition(name: clean, detail: detail?.isEmpty == true ? nil : detail, color: color, dynamic: dynamic ? true : nil))
        save()
        return clean
    }

    func keep(_ id: UUID) {
        edit(id) { $0.dynamic = nil }
    }

    func setDetail(_ id: UUID, _ detail: String) {
        let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        edit(id) { $0.detail = trimmed.isEmpty ? nil : trimmed }
    }

    func setColor(_ id: UUID, _ color: TagColor?) {
        edit(id) { $0.color = color }
    }

    /// Catalog half of a rename. Merges into an existing tag of the new name.
    func rename(_ id: UUID, to newName: String) {
        let clean = Self.clean(newName)
        guard !clean.isEmpty, let index = tags.firstIndex(where: { $0.id == id }) else { return }
        if let other = tags.firstIndex(where: { $0.id != id && $0.name.caseInsensitiveCompare(clean) == .orderedSame }) {
            if !tags[index].isDynamic { tags[other].dynamic = nil }
            if tags[other].detail == nil { tags[other].detail = tags[index].detail }
            tags.remove(at: index)
        } else {
            tags[index].name = clean
        }
        save()
    }

    func remove(_ id: UUID) {
        tags.removeAll { $0.id == id }
        save()
    }

    /// Registers tags found on meetings but missing from the catalog, and drops unused dynamic tags.
    func reconcile(with meetings: [Meeting]) {
        let used = Set(meetings.flatMap(\.tagList).map { $0.lowercased() })
        let before = tags
        tags.removeAll { $0.isDynamic && !used.contains($0.name.lowercased()) }
        for name in uniqueNames(meetings.flatMap(\.tagList)) where definition(named: name) == nil {
            tags.append(TagDefinition(name: name, dynamic: true))
        }
        if tags != before { save() }
    }

    private func edit(_ id: UUID, _ body: (inout TagDefinition) -> Void) {
        guard let index = tags.firstIndex(where: { $0.id == id }) else { return }
        body(&tags[index])
        save()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(tags).write(to: url, options: .atomic)
    }

    nonisolated static func clean(_ name: String) -> String {
        let words = name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return String(words.trimmingCharacters(in: CharacterSet(charactersIn: "#,").union(.whitespaces)).prefix(40))
    }
}

/// Asks Grok which catalog tags fit a meeting, plus up to two new ones.
enum TagSuggester {
    static let maxNewTags = 2
    private static let notesBudget = 12_000
    private static let transcriptBudget = 8_000

    struct Suggestion {
        var existing: [String]
        var new: [String]
    }

    /// Rough input size for the cost warning before a backfill.
    static func estimatedCost(for meeting: Meeting, catalogSize: Int) -> Double {
        let notes = meeting.enhancedNotes.map { min($0.count, notesBudget) }
            ?? min(meeting.userNotes.count, notesBudget) + min(meeting.utterances.reduce(0) { $0 + $1.text.count + 12 }, transcriptBudget)
        let inputTokens = Double(notes + 1_200 + catalogSize * 80) / 4
        return (inputTokens * 2.00 + 120 * 6.00) / 1_000_000
    }

    static func suggest(
        for meeting: Meeting,
        catalog: [TagDefinition],
        allowNew: Bool,
        myName: String,
        client: XAIClient,
        model: String
    ) async throws -> Suggestion {
        let userTags = catalog.filter { !$0.isDynamic }
        let dynamicTags = catalog.filter(\.isDynamic)
        var catalogText = userTags.map { tag in
            tag.detail.map { "- \(tag.name): \($0)" } ?? "- \(tag.name)"
        }.joined(separator: "\n")
        if !dynamicTags.isEmpty {
            catalogText += (catalogText.isEmpty ? "" : "\n") + dynamicTags.map { "- \($0.name)" }.joined(separator: "\n")
        }

        let newRule = allowNew
            ? "Add at most \(maxNewTags) new tags only when no catalog tag covers an important theme. New tags are Title Case, 1 to 3 words, broad enough to reuse across meetings (a topic, project, customer, or meeting type), never a person's name or a date."
            : "Do not invent new tags. Use \"new\": []."
        let system = """
        You tag meeting notes so the user can filter their library. Prefer tags from the catalog; follow each tag's description.
        Pick only tags that clearly apply. Fewer is better: usually 1 to 3 tags in total.
        \(newRule)
        Reply with JSON only: {"tags":["<catalog tag>", ...],"new":["<new tag>", ...]}
        """

        let people = uniqueNames(meeting.speakers.values.compactMap(\.name)).joined(separator: ", ")
        var body: String
        if let notes = meeting.enhancedNotes, !notes.isEmpty {
            body = "Notes:\n\(notes.prefix(notesBudget))"
        } else {
            body = "My rough notes:\n\(meeting.userNotes.isEmpty ? "(none)" : String(meeting.userNotes.prefix(notesBudget)))"
            body += "\n\nTranscript excerpt:\n\(meeting.transcript(myName: myName).prefix(transcriptBudget))"
        }
        let user = """
        Tag catalog:
        \(catalogText.isEmpty ? "(empty)" : catalogText)

        Meeting: \(meeting.title)
        Invitees: \(meeting.attendees.isEmpty ? "unknown" : meeting.attendees.joined(separator: ", "))
        Speakers: \(people.isEmpty ? "unknown" : people)

        \(body)
        """

        let reply = try await client.chat(model: model, messages: [
            .init(role: "system", content: system),
            .init(role: "user", content: user),
        ])
        return parse(reply, catalog: catalog, allowNew: allowNew)
    }

    static func parse(_ reply: String, catalog: [TagDefinition], allowNew: Bool) -> Suggestion {
        struct Reply: Decodable {
            var tags: [String]?
            var new: [String]?
        }
        guard let json = SpeakerResolver.extractJSONObject(reply),
              let parsed = try? JSONDecoder().decode(Reply.self, from: Data(json.utf8))
        else { return Suggestion(existing: [], new: []) }

        var existing: [String] = []
        var proposed: [String] = []
        for name in (parsed.tags ?? []) + (parsed.new ?? []) {
            let clean = TagCatalog.clean(name)
            guard !clean.isEmpty else { continue }
            if let match = catalog.first(where: { $0.name.caseInsensitiveCompare(clean) == .orderedSame }) {
                existing.append(match.name)
            } else {
                proposed.append(clean)
            }
        }
        let new = allowNew
            ? Array(uniqueNames(proposed).filter { $0.split(separator: " ").count <= 3 && $0.count <= 30 }.map(titleCase).prefix(maxNewTags))
            : []
        return Suggestion(existing: uniqueNames(existing), new: new)
    }

    /// Capitalizes each word but keeps acronyms like "API" and "Q3".
    static func titleCase(_ name: String) -> String {
        name.split(separator: " ").map { word in
            word.first.map { String($0).uppercased() + word.dropFirst() } ?? ""
        }.joined(separator: " ")
    }
}
