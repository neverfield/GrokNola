import Foundation

enum UsageKind: String, Codable, CaseIterable {
    case liveTranscription
    case batchTranscription
    case notes
    case topics
    case speakerNames
    case vision
    case ask
    case library
    case tags
    case other

    var label: String {
        switch self {
        case .liveTranscription: return "Live transcription"
        case .batchTranscription: return "Full-recording transcription"
        case .notes: return "Notes"
        case .topics: return "Topics"
        case .speakerNames: return "Speaker names (transcript)"
        case .vision: return "Speaker names (snapshots)"
        case .ask: return "Ask Grok (one meeting)"
        case .library: return "Ask across notes"
        case .tags: return "Tags"
        case .other: return "Other"
        }
    }
}

struct UsageEntry: Codable, Identifiable {
    var id = UUID()
    var date: Date
    var meetingID: UUID?
    var meetingTitle: String?
    var kind: UsageKind
    var model: String
    var audioSeconds: Double?
    var inputTokens: Int?
    var cachedTokens: Int?
    var outputTokens: Int?
    var costUSD: Double
    /// True when xAI reported the billed cost. False for estimates from audio duration or token counts.
    var exact: Bool
}

struct UsageContext {
    var kind: UsageKind
    var meetingID: UUID?
    var meetingTitle: String?
}

/// `XAIClient` reports each request here with the context it was given, and the ledger stores it.
enum UsageRecorder {
    nonisolated(unsafe) static var sink: ((UsageEntry) -> Void)?

    /// List prices from docs.x.ai, used only when a response has no `cost_in_usd_ticks`.
    static let streamingSTTPerHour = 0.20
    static let batchSTTPerHour = 0.10
    private static let fallbackTokenPrices: [String: (input: Double, cached: Double, output: Double)] = [
        "grok-4.7": (2.00, 0.50, 6.00),
    ]

    static func recordChat(model: String, inputTokens: Int?, cachedTokens: Int?, outputTokens: Int?, costTicks: Int64?, context: UsageContext?) {
        let cost: Double
        let exact: Bool
        if let costTicks {
            cost = Double(costTicks) / 10_000_000_000
            exact = true
        } else {
            let prices = fallbackTokenPrices[model] ?? fallbackTokenPrices["grok-4.7"]!
            let cached = cachedTokens ?? 0
            let uncached = max(0, (inputTokens ?? 0) - cached)
            cost = (Double(uncached) * prices.input + Double(cached) * prices.cached + Double(outputTokens ?? 0) * prices.output) / 1_000_000
            exact = false
        }
        emit(kind: context?.kind ?? .other, model: model, audioSeconds: nil, inputTokens: inputTokens, cachedTokens: cachedTokens,
             outputTokens: outputTokens, cost: cost, exact: exact, context: context)
    }

    static func recordTranscription(kind: UsageKind, seconds: Double, context: UsageContext?) {
        guard seconds > 0 else { return }
        let perHour = kind == .liveTranscription ? streamingSTTPerHour : batchSTTPerHour
        emit(kind: kind, model: XAIClient.transcribeModel, audioSeconds: seconds, inputTokens: nil, cachedTokens: nil, outputTokens: nil,
             cost: seconds / 3600 * perHour, exact: false, context: context)
    }

    private static func emit(kind: UsageKind, model: String, audioSeconds: Double?, inputTokens: Int?, cachedTokens: Int?,
                             outputTokens: Int?, cost: Double, exact: Bool, context: UsageContext?) {
        let entry = UsageEntry(
            date: Date(),
            meetingID: context?.meetingID,
            meetingTitle: context?.meetingTitle,
            kind: kind,
            model: model,
            audioSeconds: audioSeconds,
            inputTokens: inputTokens,
            cachedTokens: cachedTokens,
            outputTokens: outputTokens,
            costUSD: cost,
            exact: exact
        )
        sink?(entry)
    }
}

/// Append-only log at ~/Library/Application Support/GrokNotes/usage.jsonl.
@MainActor
final class UsageLedger: ObservableObject {
    @Published private(set) var entries: [UsageEntry] = []
    private let url: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("GrokNotes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("usage.jsonl")
        entries = Self.load(url)
        UsageRecorder.sink = { [weak self] entry in
            Task { @MainActor in self?.append(entry) }
        }
    }

    func append(_ entry: UsageEntry) {
        entries.append(entry)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard var line = try? encoder.encode(entry) else { return }
        line.append(0x0A)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(line)
            try? handle.close()
        } else {
            try? line.write(to: url)
        }
    }

    func total(since start: Date? = nil) -> Double {
        entries.filter { start == nil || $0.date >= start! }.reduce(0) { $0 + $1.costUSD }
    }

    func total(for meetingID: UUID) -> Double {
        entries.filter { $0.meetingID == meetingID }.reduce(0) { $0 + $1.costUSD }
    }

    func byKind(since start: Date?) -> [(kind: UsageKind, cost: Double)] {
        let filtered = entries.filter { start == nil || $0.date >= start! }
        return UsageKind.allCases.compactMap { kind in
            let cost = filtered.filter { $0.kind == kind }.reduce(0) { $0 + $1.costUSD }
            return cost > 0 ? (kind, cost) : nil
        }
    }

    func byMeeting(since start: Date?) -> [(id: UUID, title: String, date: Date, cost: Double)] {
        let filtered = entries.filter { $0.meetingID != nil && (start == nil || $0.date >= start!) }
        let groups = Dictionary(grouping: filtered) { $0.meetingID! }
        return groups.map { id, items in
            (id, items.last(where: { $0.meetingTitle != nil })?.meetingTitle ?? "Meeting",
             items.map(\.date).min() ?? Date(), items.reduce(0) { $0 + $1.costUSD })
        }
        .sorted { $0.date > $1.date }
    }

    private static func load(_ url: URL) -> [UsageEntry] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return text.split(separator: "\n").compactMap { try? decoder.decode(UsageEntry.self, from: Data($0.utf8)) }
    }
}

extension Double {
    var usd: String {
        if self == 0 { return "$0.00" }
        if self < 0.01 { return String(format: "$%.4f", self) }
        return String(format: "$%.2f", self)
    }
}
