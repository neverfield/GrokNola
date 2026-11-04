import Foundation

struct XAIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct XAIClient {
    static let baseURL = URL(string: "https://api.x.ai/v1")!
    static let transcribeModel = "grok-voice-transcribe-2.0"
    static let keychainAccount = "xai_api_key"

    let apiKey: String
    /// What requests from this client are for, so usage is logged against the right meeting and feature.
    var usageContext: UsageContext?

    func tracking(_ kind: UsageKind, _ meeting: Meeting) -> XAIClient {
        var copy = self
        copy.usageContext = UsageContext(kind: kind, meetingID: meeting.id, meetingTitle: meeting.title)
        return copy
    }

    static func storedAPIKey() -> String? {
        if let key = Keychain.get(keychainAccount), !key.isEmpty { return key }
        if let key = ProcessInfo.processInfo.environment["XAI_API_KEY"], !key.isEmpty { return key }
        return nil
    }

    static func fromSettings() throws -> XAIClient {
        guard let key = storedAPIKey() else { throw XAIError(message: "Add your xAI API key in Settings.") }
        return XAIClient(apiKey: key)
    }

    // MARK: Chat

    struct Message: Encodable {
        let role: String
        let content: String
    }

    enum Part {
        case text(String)
        case jpeg(Data)
    }

    func chat(model: String, messages: [Message]) async throws -> String {
        try await chat(model: model, rawMessages: messages.map { ["role": $0.role, "content": $0.content] })
    }

    /// A system prompt plus one user message mixing text and images.
    func chat(model: String, system: String, parts: [Part]) async throws -> String {
        let content: [[String: Any]] = parts.map { part in
            switch part {
            case .text(let text):
                return ["type": "text", "text": text]
            case .jpeg(let data):
                return ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(data.base64EncodedString())", "detail": "high"]]
            }
        }
        return try await chat(model: model, rawMessages: [
            ["role": "system", "content": system],
            ["role": "user", "content": content],
        ])
    }

    private func chat(model: String, rawMessages: [[String: Any]]) async throws -> String {
        struct Response: Decodable {
            struct Choice: Decodable {
                struct Content: Decodable { let content: String? }
                let message: Content
            }
            struct Usage: Decodable {
                struct PromptDetails: Decodable { let cached_tokens: Int? }
                let prompt_tokens: Int?
                let completion_tokens: Int?
                let prompt_tokens_details: PromptDetails?
                let cost_in_usd_ticks: Int64?
            }
            let choices: [Choice]
            let usage: Usage?
        }
        var request = makeRequest("chat/completions", timeout: 600)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "stream": false, "messages": rawMessages])
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.check(response, data)
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        if let usage = decoded.usage {
            UsageRecorder.recordChat(
                model: model,
                inputTokens: usage.prompt_tokens,
                cachedTokens: usage.prompt_tokens_details?.cached_tokens,
                outputTokens: usage.completion_tokens,
                costTicks: usage.cost_in_usd_ticks,
                context: usageContext
            )
        }
        guard let text = decoded.choices.first?.message.content, !text.isEmpty else {
            throw XAIError(message: "Grok returned an empty reply.")
        }
        return text
    }

    func listModelCount() async throws -> Int {
        struct Response: Decodable {
            struct Model: Decodable { let id: String }
            let data: [Model]
        }
        let (data, response) = try await URLSession.shared.data(for: makeRequest("models", timeout: 30))
        try Self.check(response, data)
        return try JSONDecoder().decode(Response.self, from: data).data.count
    }

    // MARK: Batch speech-to-text

    struct STTWord: Decodable {
        let text: String
        let start: Double
        let end: Double
        let speaker: Int?
    }

    struct STTResult: Decodable {
        let text: String
        let duration: Double?
        let words: [STTWord]?
    }

    /// Streams the multipart body from disk so long recordings are not loaded into memory.
    func transcribe(fileURL: URL, diarize: Bool, language: String?, keyterms: [String]) async throws -> STTResult {
        let boundary = "groknotes-\(UUID().uuidString)"
        let bodyURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(boundary).multipart")
        FileManager.default.createFile(atPath: bodyURL.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: bodyURL) }

        let out = try FileHandle(forWritingTo: bodyURL)
        func write(_ s: String) { out.write(Data(s.utf8)) }
        func field(_ name: String, _ value: String) {
            write("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n")
        }
        field("model", Self.transcribeModel)
        if diarize { field("diarize", "true") }
        if let language, !language.isEmpty { field("language", language) }
        for term in keyterms { field("keyterm", term) }
        // The API requires `file` to be the last field.
        write("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\nContent-Type: audio/wav\r\n\r\n")
        let input = try FileHandle(forReadingFrom: fileURL)
        while let chunk = try input.read(upToCount: 1 << 20), !chunk.isEmpty { out.write(chunk) }
        try input.close()
        write("\r\n--\(boundary)--\r\n")
        try out.close()

        var request = makeRequest("stt", timeout: 1800)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.upload(for: request, fromFile: bodyURL)
        try Self.check(response, data)
        let result = try JSONDecoder().decode(STTResult.self, from: data)
        let seconds = result.duration ?? Double((try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0) / 32_000
        UsageRecorder.recordTranscription(kind: .batchTranscription, seconds: seconds, context: usageContext)
        return result
    }

    // MARK: Helpers

    private func makeRequest(_ path: String, timeout: TimeInterval) -> URLRequest {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent(path))
        request.timeoutInterval = timeout
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        return request
    }

    private static func check(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) else { return }
        var detail = String(data: data, encoding: .utf8) ?? ""
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = obj["error"] as? String { detail = error }
            if let error = obj["error"] as? [String: Any], let message = error["message"] as? String { detail = message }
        }
        throw XAIError(message: "xAI API \(http.statusCode): \(detail.prefix(300))")
    }
}
