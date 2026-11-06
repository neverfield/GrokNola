import Foundation

/// Token counts and billed cost from a chat completion. Streams repeat it on chunks; the last one is final.
struct ChatUsage: Equatable {
    var promptTokens: Int?
    var cachedTokens: Int?
    var completionTokens: Int?
    var costTicks: Int64?
}

enum ChatStreamEvent: Equatable {
    case delta(String)
    case usage(ChatUsage)
    case done
}

/// Parses the server-sent event lines of a streaming `chat/completions` response.
enum ChatStreamParser {
    private struct Chunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable { let content: String? }
            let delta: Delta?
        }
        struct Usage: Decodable {
            struct PromptDetails: Decodable { let cached_tokens: Int? }
            let prompt_tokens: Int?
            let completion_tokens: Int?
            let prompt_tokens_details: PromptDetails?
            let cost_in_usd_ticks: Int64?
        }
        struct Failure: Decodable { let message: String? }
        let choices: [Choice]?
        let usage: Usage?
        let error: Failure?
    }

    /// Events in one line. Blank lines, comments, and non-data fields yield nothing.
    /// Reasoning deltas are dropped; only visible content is returned.
    static func events(fromLine line: String) throws -> [ChatStreamEvent] {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("data:") else { return [] }
        let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" { return [.done] }
        guard !payload.isEmpty else { return [] }
        let chunk = try JSONDecoder().decode(Chunk.self, from: Data(payload.utf8))
        if let error = chunk.error {
            throw XAIError(message: "xAI stream error: \(error.message ?? "unknown")")
        }
        var out: [ChatStreamEvent] = []
        let text = (chunk.choices ?? []).compactMap { $0.delta?.content }.joined()
        if !text.isEmpty { out.append(.delta(text)) }
        if let u = chunk.usage {
            out.append(.usage(ChatUsage(
                promptTokens: u.prompt_tokens,
                cachedTokens: u.prompt_tokens_details?.cached_tokens,
                completionTokens: u.completion_tokens,
                costTicks: u.cost_in_usd_ticks
            )))
        }
        return out
    }
}
