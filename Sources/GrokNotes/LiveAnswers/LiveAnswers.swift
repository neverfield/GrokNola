import Foundation

/// One detected or typed question and its streamed answer. Lives only in memory unless pinned into the notes.
struct LiveAnswerCard: Identifiable, Equatable {
    enum Status: Equatable {
        case waiting
        case streaming
        case done
        case failed(String)
    }

    struct Source: Equatable {
        var title: String
        var date: Date
    }

    let id = UUID()
    var meetingID: UUID
    var question: String
    var asker: String
    /// Seconds since the meeting started.
    var askedAt: Double
    var typed: Bool
    var status: Status = .waiting
    var answer = ""
    /// Past meetings that were given to the model.
    var sources: [Source] = []
    /// Seconds from sending the request to the first visible token.
    var latency: Double?
    /// The block appended to the meeting's notes, so it can be removed again.
    var pinnedBlock: String?

    var isPinned: Bool { pinnedBlock != nil }
    /// Detected questions stay hidden until the reply is known not to be SKIP, so declined ones never flash.
    var isVisible: Bool { typed || !LiveAnswersPrompt.mightBeSkip(answer) || isFailed }
    var isFailed: Bool { if case .failed = status { return true } else { return false } }
    /// Past meetings the answer names, for the source line.
    var citedSources: [Source] { sources.filter { answer.localizedCaseInsensitiveContains($0.title) } }
}

/// Watches the live transcript of the recording meeting for questions and streams short answers from a fast model.
/// At most one request runs at a time. A newer question replaces the queued one and cancels an in-flight one
/// that has not produced tokens yet. Detected questions start at most once every `minInterval` seconds.
@MainActor
final class LiveAnswersEngine: ObservableObject {
    @Published private(set) var cards: [LiveAnswerCard] = []
    /// Answering for the current recording. Starts from Settings; the toolbar button toggles it.
    @Published var enabled = true
    @Published private(set) var meetingID: UUID?

    static let minInterval: TimeInterval = 8
    static let maxCards = 10
    static let interimDelay: Duration = .seconds(1)

    weak var app: AppState?
    private var apiKey: String?
    private var detector = QuestionDetector()
    private var pendingTyped: [UUID] = []
    private var pendingDetected: UUID?
    private var inFlight: (cardID: UUID, task: Task<Void, Never>, typed: Bool)?
    private var inFlightHasTokens = false
    private var lastStart: Date?
    private var startBeforeInFlight: Date?
    private var pumpTask: Task<Void, Never>?
    private var interimTasks: [AudioSource: Task<Void, Never>] = [:]

    func cards(for meetingID: UUID) -> [LiveAnswerCard] {
        cards.filter { $0.meetingID == meetingID && $0.isVisible }
    }

    // MARK: Session

    func begin(meetingID: UUID, apiKey: String) {
        cancelAll()
        cards = []
        detector.reset()
        lastStart = nil
        self.meetingID = meetingID
        self.apiKey = apiKey
        enabled = Prefs.liveAnswers
    }

    /// Stops answering and keeps only pinned cards.
    func end() {
        cancelAll()
        cards.removeAll { !$0.isPinned }
        meetingID = nil
        apiKey = nil
    }

    func setEnabled(_ on: Bool) {
        enabled = on
        if !on {
            cancelAll()
            cards.removeAll { !$0.isPinned && $0.status != .done }
        }
    }

    // MARK: Input

    /// A finished transcript segment.
    func heard(_ text: String, asker: String, at seconds: Double) {
        guard enabled, let meetingID, let question = detector.detect(text) else { return }
        enqueue(LiveAnswerCard(meetingID: meetingID, question: question, asker: asker, askedAt: seconds, typed: false))
    }

    /// Interim text. A question that stays unchanged for a second is answered before the segment is final;
    /// the final copy is then dropped as a duplicate.
    func heardInterim(_ text: String, source: AudioSource) {
        interimTasks[source]?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard enabled, meetingID != nil, trimmed.hasSuffix("?") else { return }
        interimTasks[source] = Task { [weak self] in
            try? await Task.sleep(for: Self.interimDelay)
            guard !Task.isCancelled, let self, let app = self.app else { return }
            let current = (source == .mic ? app.liveMe : app.liveThem).trimmingCharacters(in: .whitespacesAndNewlines)
            guard current == trimmed else { return }
            self.heard(trimmed, asker: source == .mic ? "You" : "Them", at: app.elapsed)
        }
    }

    /// A question typed into Ask now. Skips detection and the rate limit.
    func ask(_ question: String) {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, let meetingID else { return }
        detector.remember(q)
        enqueue(LiveAnswerCard(meetingID: meetingID, question: q, asker: "You", askedAt: app?.elapsed ?? 0, typed: true))
    }

    // MARK: Card actions

    func dismiss(_ id: UUID) {
        if inFlight?.cardID == id { cancelInFlight() }
        pendingTyped.removeAll { $0 == id }
        if pendingDetected == id { pendingDetected = nil }
        cards.removeAll { $0.id == id }
        pump()
    }

    func setPinnedBlock(_ id: UUID, _ block: String?) {
        guard let i = cards.firstIndex(where: { $0.id == id }) else { return }
        cards[i].pinnedBlock = block
    }

    func card(_ id: UUID) -> LiveAnswerCard? {
        cards.first { $0.id == id }
    }

    // MARK: Scheduling

    private func enqueue(_ card: LiveAnswerCard) {
        cards.insert(card, at: 0)
        if card.typed {
            pendingTyped.append(card.id)
        } else {
            if let old = pendingDetected { cards.removeAll { $0.id == old } }
            pendingDetected = card.id
        }
        if inFlight != nil, !inFlightHasTokens, inFlight?.typed == false {
            let stale = inFlight!.cardID
            cancelInFlight()
            cards.removeAll { $0.id == stale }
            lastStart = startBeforeInFlight
        }
        trim()
        pump()
    }

    private func pump() {
        guard inFlight == nil else { return }
        pumpTask?.cancel()
        pumpTask = nil
        let next: (id: UUID, typed: Bool)
        if let typed = pendingTyped.first {
            next = (typed, true)
        } else if let detected = pendingDetected {
            next = (detected, false)
            if let lastStart {
                let wait = Self.minInterval - Date().timeIntervalSince(lastStart)
                if wait > 0 {
                    pumpTask = Task { [weak self] in
                        try? await Task.sleep(for: .seconds(wait))
                        guard !Task.isCancelled else { return }
                        self?.pumpTask = nil
                        self?.pump()
                    }
                    return
                }
            }
        } else {
            return
        }
        if next.typed { pendingTyped.removeFirst() } else { pendingDetected = nil }
        start(next.id, typed: next.typed)
    }

    private func start(_ cardID: UUID, typed: Bool) {
        guard let app, let apiKey, let card = card(cardID), let meeting = app.meeting(card.meetingID) else {
            update(cardID) { $0.status = .failed("Live answers need a recording meeting and an xAI API key.") }
            return
        }
        startBeforeInFlight = lastStart
        lastStart = Date()
        inFlightHasTokens = false
        let client = XAIClient(apiKey: apiKey).tracking(.liveAnswers, meeting)
        let others = Prefs.liveAnswersPastMeetings ? app.meetings.filter { $0.id != meeting.id && $0.endedAt != nil } : []
        let template = app.templateCatalog.template(for: meeting).name
        let myName = Prefs.myName
        let transcript = meeting.utterances.filter { $0.end >= app.elapsed - LiveAnswersPrompt.transcriptWindow }
        let model = Prefs.liveAnswersModel
        let extra = LiveAnswersPrompt.requestOptions()

        let task = Task { [weak self] in
            let sent = Date()
            let past = await Task.detached(priority: .userInitiated) {
                LiveAnswersPrompt.pastMeetings(for: card.question, current: meeting, in: others)
            }.value
            guard !Task.isCancelled else { return }
            self?.update(cardID) { $0.sources = past.map { .init(title: $0.title, date: $0.startedAt) } }
            let messages = LiveAnswersPrompt.messages(
                card: card, meeting: meeting, recent: transcript, past: past, templateName: template, myName: myName
            )
            do {
                for try await delta in client.streamChat(model: model, messages: messages, extra: extra, conversationID: "groknotes-live-\(meeting.id.uuidString)") {
                    guard let self else { return }
                    if !self.inFlightHasTokens {
                        self.inFlightHasTokens = true
                        self.update(cardID) { $0.latency = Date().timeIntervalSince(sent); $0.status = .streaming }
                    }
                    self.update(cardID) { $0.answer += delta }
                }
                guard let self else { return }
                let answer = self.card(cardID)?.answer.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !typed, LiveAnswersPrompt.isSkip(answer) || answer.isEmpty {
                    self.cards.removeAll { $0.id == cardID }
                } else {
                    self.update(cardID) {
                        $0.answer = LiveAnswersPrompt.isSkip(answer) ? "No answer needed." : answer
                        $0.status = .done
                    }
                }
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.update(cardID) { $0.status = .failed(error.localizedDescription) }
            }
            self?.finished(cardID)
        }
        inFlight = (cardID, task, typed)
    }

    private func finished(_ cardID: UUID) {
        guard inFlight?.cardID == cardID else { return }
        inFlight = nil
        pump()
    }

    private func cancelInFlight() {
        inFlight?.task.cancel()
        inFlight = nil
    }

    private func cancelAll() {
        cancelInFlight()
        pumpTask?.cancel()
        pumpTask = nil
        interimTasks.values.forEach { $0.cancel() }
        interimTasks = [:]
        pendingTyped = []
        pendingDetected = nil
    }

    private func update(_ id: UUID, _ body: (inout LiveAnswerCard) -> Void) {
        guard let i = cards.firstIndex(where: { $0.id == id }) else { return }
        body(&cards[i])
    }

    /// Keeps the newest `maxCards` unpinned cards. Pinned cards and queued or running ones stay.
    private func trim() {
        let busy = Set(pendingTyped + [pendingDetected, inFlight?.cardID].compactMap { $0 })
        var kept = 0
        cards.removeAll { card in
            if card.isPinned || busy.contains(card.id) { return false }
            kept += 1
            return kept > Self.maxCards
        }
    }
}
