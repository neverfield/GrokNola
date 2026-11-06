import Foundation

/// One live connection to `wss://api.x.ai/v1/stt` for one audio source.
/// Accepts 16 kHz mono PCM16, reconnects on drops, and emits finished utterances
/// split by diarized speaker, with times in seconds since the meeting started.
final class STTStream {
    struct Config {
        var apiKey: String
        var diarize: Bool
        var language: String?
        var keyterms: [String]
    }

    struct Word {
        var text: String
        var start: Double
        var end: Double
        var speaker: Int?
    }

    struct Segment {
        var speaker: Int?
        var text: String
        var start: Double
        var end: Double
    }

    /// Text that is still being spoken. Empty when nothing is pending.
    var onLive: ((String) -> Void)?
    /// Finished segments and the connection epoch. Speaker numbers are only stable within one epoch.
    var onSegments: (([Segment], Int) -> Void)?
    /// A status message, or nil when the connection is healthy.
    var onStatus: ((String?) -> Void)?

    private static let bytesPerSecond = 16_000 * 2
    private static let chunkBytes = 3_200
    private static let maxBufferedBytes = bytesPerSecond * 60

    private let config: Config
    private let queue = DispatchQueue(label: "groknotes.stt")
    private var task: URLSessionWebSocketTask?
    private var ready = false
    private var buffer = Data()
    /// Meeting time of the first byte this connection will send.
    private var baseOffset: Double?
    private var chunkFinals: [Word] = []
    private var epoch = 0
    private var attempts = 0
    private var stopping = false
    private var doneHandler: (() -> Void)?

    init(config: Config) {
        self.config = config
    }

    func start() {
        queue.async { self.connect() }
    }

    func append(_ pcm: Data, at meetingTime: Double) {
        queue.async {
            guard !self.stopping else { return }
            if self.baseOffset == nil { self.baseOffset = meetingTime }
            self.buffer.append(pcm)
            if self.ready {
                self.flush(force: false)
            } else if self.buffer.count > Self.maxBufferedBytes {
                let drop = self.buffer.count - Self.maxBufferedBytes
                self.buffer.removeFirst(drop)
                self.baseOffset = (self.baseOffset ?? 0) + Double(drop) / Double(Self.bytesPerSecond)
            }
        }
    }

    /// Flushes audio, asks the server to finish, and calls `completion` once the last transcript is in.
    func stop(completion: @escaping () -> Void) {
        queue.async {
            self.stopping = true
            self.doneHandler = completion
            guard let task = self.task, self.ready else {
                self.finish()
                return
            }
            self.flush(force: true)
            task.send(.string(#"{"type":"audio.done"}"#)) { _ in }
            self.queue.asyncAfter(deadline: .now() + 8) { self.finish() }
        }
    }

    // MARK: Connection

    private func connect() {
        var components = URLComponents(string: "wss://api.x.ai/v1/stt")!
        var items = [
            URLQueryItem(name: "model", value: XAIClient.transcribeModel),
            URLQueryItem(name: "sample_rate", value: "16000"),
            URLQueryItem(name: "encoding", value: "pcm"),
            URLQueryItem(name: "interim_results", value: "true"),
        ]
        if config.diarize { items.append(URLQueryItem(name: "diarize", value: "true")) }
        if let language = config.language, !language.isEmpty {
            items.append(URLQueryItem(name: "language", value: language))
            items.append(URLQueryItem(name: "format", value: "true"))
        }
        items += config.keyterms.map { URLQueryItem(name: "keyterm", value: $0) }
        components.queryItems = items

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        let task = URLSession.shared.webSocketTask(with: request)
        task.maximumMessageSize = 16 << 20
        self.task = task
        ready = false
        task.resume()
        receive(on: task)
    }

    private func receive(on task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self else { return }
            self.queue.async {
                guard task === self.task else { return }
                switch result {
                case .failure(let error):
                    self.disconnected(reason: error.localizedDescription)
                case .success(let message):
                    switch message {
                    case .string(let text): self.handle(text)
                    case .data(let data): self.handle(String(decoding: data, as: UTF8.self))
                    @unknown default: break
                    }
                    if task === self.task { self.receive(on: task) }
                }
            }
        }
    }

    private func disconnected(reason: String) {
        if stopping {
            finish()
            return
        }
        commit(chunkFinals)
        chunkFinals = []
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        ready = false
        buffer.removeAll()
        baseOffset = nil
        epoch += 1
        attempts += 1
        onLive?("")
        onStatus?("Transcription reconnecting: \(reason)")
        let delay = min(30, 1.5 * pow(2, Double(attempts - 1)))
        queue.asyncAfter(deadline: .now() + delay) {
            if !self.stopping && self.task == nil { self.connect() }
        }
    }

    private func finish() {
        commit(chunkFinals)
        chunkFinals = []
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        onLive?("")
        let handler = doneHandler
        doneHandler = nil
        handler?()
    }

    private func flush(force: Bool) {
        guard let task, ready else { return }
        while buffer.count >= Self.chunkBytes || (force && !buffer.isEmpty) {
            let count = min(Self.chunkBytes, buffer.count)
            let chunk = Data(buffer.prefix(count))
            buffer.removeFirst(count)
            task.send(.data(chunk)) { _ in }
        }
    }

    // MARK: Events

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = event["type"] as? String
        else { return }

        switch type {
        case "transcript.created":
            ready = true
            attempts = 0
            onStatus?(nil)
            flush(force: false)

        case "transcript.partial":
            let words = Self.words(in: event)
            let isFinal = event["is_final"] as? Bool ?? false
            let speechFinal = event["speech_final"] as? Bool ?? false
            if !isFinal {
                onLive?(Self.join(chunkFinals + words))
            } else if !speechFinal {
                chunkFinals += words
                onLive?(Self.join(chunkFinals))
            } else {
                // An utterance-final event normally restates the whole utterance.
                // If it only covers the tail, keep the chunk finals in front of it.
                var final = words
                if let first = chunkFinals.first, let head = final.first, head.start > first.start + 0.5 {
                    final = chunkFinals + final
                }
                if final.isEmpty { final = chunkFinals }
                chunkFinals = []
                commit(final)
                onLive?("")
            }

        case "transcript.done":
            if stopping { finish() }

        case "error":
            onStatus?("Transcription error: \(event["message"] as? String ?? "unknown")")

        default:
            break
        }
    }

    private func commit(_ words: [Word]) {
        let segments = Self.group(words, offset: baseOffset ?? 0)
        if !segments.isEmpty { onSegments?(segments, epoch) }
    }

    private static func words(in event: [String: Any]) -> [Word] {
        let eventStart = event["start"] as? Double ?? 0
        var words = (event["words"] as? [[String: Any]] ?? []).compactMap { w -> Word? in
            guard let text = w["text"] as? String, !text.isEmpty else { return nil }
            let start = w["start"] as? Double ?? eventStart
            return Word(text: text, start: start, end: w["end"] as? Double ?? start, speaker: w["speaker"] as? Int)
        }
        if words.isEmpty, let text = event["text"] as? String, !text.isEmpty {
            words = [Word(text: text, start: eventStart, end: eventStart + (event["duration"] as? Double ?? 0), speaker: nil)]
        }
        // Word times should be stream-relative. Shift them if they look relative to the event.
        if eventStart > 1, let first = words.first, first.start < eventStart - 0.25 {
            words = words.map { Word(text: $0.text, start: $0.start + eventStart, end: $0.end + eventStart, speaker: $0.speaker) }
        }
        return words
    }

    private static func join(_ words: [Word]) -> String {
        words.map(\.text).joined(separator: " ")
    }

    /// Groups consecutive words by speaker, and also splits on pauses longer than 1.5 s.
    static func group(_ words: [Word], offset: Double) -> [Segment] {
        var segments: [Segment] = []
        var lastEnd = -Double.infinity
        for word in words {
            if var last = segments.last, last.speaker == word.speaker, word.start - lastEnd <= 1.5 {
                last.text += " " + word.text
                last.end = word.end + offset
                segments[segments.count - 1] = last
            } else {
                segments.append(Segment(speaker: word.speaker, text: word.text, start: word.start + offset, end: word.end + offset))
            }
            lastEnd = word.end
        }
        return segments
    }
}
