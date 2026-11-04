import AVFoundation
import AppKit
import ApplicationServices
import SwiftUI

struct Permissions {
    var microphone = false
    var systemAudio = false
    var accessibility = false
    var calendar = false
}

/// Everything that lives only while one meeting is being recorded.
private final class RecordingSession {
    let meetingID: UUID
    let start: Date
    let app: MeetingDetector.App?
    var keyterms: [String] = []
    var mic: MicCapture?
    var system: SystemAudioCapture?
    var micStream: STTStream?
    var systemStream: STTStream?
    var micWAV: WAVWriter?
    var systemWAV: WAVWriter?
    var monitor: ActiveSpeakerMonitor?
    var snapshotter: WindowSnapshotter?
    var hasSystemAudio = false
    var timer: Timer?

    init(meetingID: UUID, start: Date, app: MeetingDetector.App?) {
        self.meetingID = meetingID
        self.start = start
        self.app = app
    }
}

/// A request to show the transcript of a meeting at a time, set by clicking a citation.
struct TranscriptFocus: Equatable {
    var meetingID: UUID
    var seconds: Double
    var token = UUID()
}

enum DetailRoute: Equatable {
    case home
    case library
    case meeting(UUID)
}

@MainActor
final class AppState: ObservableObject {
    @Published var meetings: [Meeting] = []
    @Published var selectedID: UUID? {
        didSet {
            if let playing = clips.nowPlaying?.meetingID, playing != selectedID, selectedID != nil { clips.stop() }
        }
    }
    @Published private(set) var recordingID: UUID?
    @Published private(set) var processing: Set<UUID> = []
    @Published private(set) var asking: Set<UUID> = []
    @Published private(set) var findingTopics: Set<UUID> = []
    @Published var transcriptFocus: TranscriptFocus?
    @Published var liveMe = ""
    @Published var liveThem = ""
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var detectedApp: MeetingDetector.App?
    @Published var banner: String?
    @Published private(set) var streamStatus: String?
    @Published private(set) var permissions = Permissions()
    /// True while the detail pane shows the chat across all notes instead of a meeting.
    @Published var showLibraryChat = false
    @Published private(set) var libraryChat: [ChatMessage] = []
    @Published private(set) var libraryAsking = false

    let store = MeetingStore()
    let usage = UsageLedger()
    let tagCatalog = TagCatalog()
    let templateCatalog = TemplateCatalog()
    let clips: ClipPlayer
    private let calendar = CalendarService()
    private var session: RecordingSession?
    private var detectorTimer: Timer?
    private var saveTasks: [UUID: Task<Void, Never>] = [:]

    init() {
        clips = ClipPlayer(root: store.root)
        meetings = store.loadAll()
        deleteExpiredAudio()
        tagCatalog.reconcile(with: meetings)
        libraryChat = Self.loadLibraryChat()
        refreshPermissions()
        detectorTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.detectMeeting() }
        }
    }

    // MARK: Lookup and edits

    func meeting(_ id: UUID) -> Meeting? {
        meetings.first { $0.id == id }
    }

    func update(_ id: UUID, _ body: (inout Meeting) -> Void) {
        guard let index = meetings.firstIndex(where: { $0.id == id }) else { return }
        body(&meetings[index])
    }

    func binding<T>(_ id: UUID, _ keyPath: WritableKeyPath<Meeting, T>, default fallback: T) -> Binding<T> {
        Binding(
            get: { self.meeting(id)?[keyPath: keyPath] ?? fallback },
            set: { value in
                self.update(id) { $0[keyPath: keyPath] = value }
                self.scheduleSave(id)
            }
        )
    }

    func titleBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { self.meeting(id)?.title ?? "" },
            set: { value in
                self.update(id) {
                    $0.title = value
                    $0.autoTitle = false
                }
                self.scheduleSave(id)
            }
        )
    }

    func renameSpeaker(_ meetingID: UUID, key: String, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        update(meetingID) { m in
            if name.isEmpty {
                m.speakers[key] = SpeakerInfo(name: nil, attribution: key == Meeting.meKey ? .me : .unknown)
            } else {
                m.speakers[key] = SpeakerInfo(name: name, attribution: .manual, confidence: 1, evidence: nil)
            }
            if m.mode != .detecting { m.mode = m.hasNamedRemoteSpeaker ? .named : (m.mode == .micOnly ? .micOnly : .meThem) }
        }
        if !name.isEmpty, key != Meeting.meKey { Prefs.remember([name]) }
        save(meetingID)
    }

    func delete(_ id: UUID) {
        guard id != recordingID else { return }
        if clips.nowPlaying?.meetingID == id { clips.stop() }
        meetings.removeAll { $0.id == id }
        store.delete(id)
        clips.invalidate(id)
        if selectedID == id { selectedID = nil }
    }

    func save(_ id: UUID) {
        saveTasks[id]?.cancel()
        saveTasks[id] = nil
        guard let m = meeting(id) else { return }
        do {
            try store.save(m, myName: Prefs.myName)
        } catch {
            banner = "Could not save \"\(m.title)\": \(error.localizedDescription)"
        }
    }

    private func scheduleSave(_ id: UUID) {
        saveTasks[id]?.cancel()
        saveTasks[id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.save(id)
        }
    }

    // MARK: Permissions

    func refreshPermissions() {
        permissions = Permissions(
            microphone: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
            systemAudio: CGPreflightScreenCaptureAccess(),
            accessibility: ActiveSpeakerMonitor.isTrusted,
            calendar: calendar.isAuthorized
        )
    }

    func requestMicrophone() async {
        _ = await MicCapture.requestPermission()
        refreshPermissions()
    }

    func requestSystemAudio() {
        if !CGRequestScreenCaptureAccess() {
            openPrivacyPane("Privacy_ScreenCapture")
        }
        refreshPermissions()
    }

    func requestAccessibility() {
        ActiveSpeakerMonitor.requestTrust()
        refreshPermissions()
    }

    func requestCalendar() async {
        _ = await calendar.requestAccess()
        refreshPermissions()
    }

    func openPrivacyPane(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    private func detectMeeting() {
        guard session == nil else { return }
        let app = MeetingDetector.detect(micInUse: MeetingDetector.micInUse())
        if app != detectedApp { detectedApp = app }
    }

    // MARK: Recording

    func startMeeting() async {
        guard session == nil else { return }
        clips.stop()
        guard let apiKey = XAIClient.storedAPIKey() else {
            banner = "Add your xAI API key in Settings (Command-comma) first."
            return
        }
        guard await MicCapture.requestPermission() else {
            banner = "Grok Notes needs microphone access. Turn it on in System Settings > Privacy & Security > Microphone."
            refreshPermissions()
            return
        }

        let now = Date()
        let app = MeetingDetector.detect(micInUse: MeetingDetector.micInUse())
        let event = calendar.currentEvent()
        let myName = Prefs.myName
        var meeting = Meeting(
            title: event?.title ?? "\(app?.name ?? "Meeting") · \(now.formatted(date: .abbreviated, time: .shortened))",
            autoTitle: event == nil,
            startedAt: now
        )
        meeting.appName = app?.name
        meeting.attendees = event?.attendees ?? []
        meetings.insert(meeting, at: 0)
        selectedID = meeting.id

        let s = RecordingSession(meetingID: meeting.id, start: now, app: app)
        s.keyterms = Array(uniqueNames(meeting.attendees + Prefs.knownPeople + [myName]).filter { $0.count <= 50 }.prefix(100))
        session = s
        recordingID = meeting.id
        elapsed = 0
        liveMe = ""
        liveThem = ""
        let dir = store.directory(for: meeting.id)
        let meetingID = meeting.id

        // Remote participants: system audio, diarized.
        let system = SystemAudioCapture()
        let systemStream = makeStream(apiKey: apiKey, diarize: true, keyterms: s.keyterms, meetingID: meetingID, source: .system)
        let systemWAV = try? WAVWriter(url: dir.appendingPathComponent("system.wav"))
        let remoteSpeech = SpeechActivity()
        system.onPCM = { data in
            let t = Date().timeIntervalSince(now) - Double(data.count) / 32_000
            systemStream.append(data, at: t)
            systemWAV?.write(data, at: t)
            if SpeechActivity.level(data) > 500 { remoteSpeech.mark() }
        }
        system.onError = { [weak self] message in Task { @MainActor in self?.streamStatus = message } }
        do {
            try await system.start()
            s.system = system
            s.systemStream = systemStream
            s.systemWAV = systemWAV
            s.hasSystemAudio = true
            systemStream.start()
        } catch {
            systemWAV?.close()
            try? FileManager.default.removeItem(at: dir.appendingPathComponent("system.wav"))
            banner = "System audio is off (\(error.localizedDescription)). Recording the microphone only. Allow Screen & System Audio Recording in Settings to separate remote speakers."
        }

        // The local user: microphone. Diarize it only when there is no separate system audio.
        let mic = MicCapture()
        let micStream = makeStream(apiKey: apiKey, diarize: !s.hasSystemAudio, keyterms: s.keyterms, meetingID: meetingID, source: .mic)
        let micWAV = try? WAVWriter(url: dir.appendingPathComponent("mic.wav"))
        mic.onPCM = { data in
            let t = Date().timeIntervalSince(now) - Double(data.count) / 32_000
            micStream.append(data, at: t)
            micWAV?.write(data, at: t)
        }
        do {
            let wantsEchoCancellation = Prefs.echoCancellation && s.hasSystemAudio
            try mic.start(echoCancellation: wantsEchoCancellation)
            if wantsEchoCancellation && !mic.echoCancellationActive {
                banner = "Echo cancellation is not supported by your current audio devices. Use headphones so other voices are not transcribed as you."
            }
            s.mic = mic
            s.micStream = micStream
            s.micWAV = micWAV
            micStream.start()
        } catch {
            micWAV?.close()
            banner = "Could not start the microphone: \(error.localizedDescription)"
        }

        if let app, ActiveSpeakerMonitor.isTrusted, s.hasSystemAudio {
            let monitor = ActiveSpeakerMonitor(app: app, meetingStart: now, ignoredNames: [myName, "you"])
            monitor.begin()
            s.monitor = monitor
        }
        if s.hasSystemAudio, Prefs.useSnapshots {
            let snapshotter = WindowSnapshotter(directory: dir.appendingPathComponent("frames"), start: now, app: app, speech: remoteSpeech)
            snapshotter.begin()
            s.snapshotter = snapshotter
        }

        update(meetingID) { m in
            m.speakers[Meeting.meKey] = SpeakerInfo(name: nil, attribution: .me)
            m.mode = s.hasSystemAudio ? .detecting : .micOnly
        }
        save(meetingID)
        refreshPermissions()

        s.timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func stopMeeting() async {
        guard let s = session else { return }
        session = nil
        recordingID = nil
        s.timer?.invalidate()
        s.mic?.stop()
        await s.system?.stop()
        s.monitor?.end()
        s.snapshotter?.end()

        async let micDone: Void = Self.drain(s.micStream)
        async let systemDone: Void = Self.drain(s.systemStream)
        _ = await (micDone, systemDone)
        await Task.yield()

        let micDuration = s.micWAV?.close() ?? 0
        let systemDuration = s.systemWAV?.close() ?? 0
        UsageRecorder.recordTranscription(
            kind: .liveTranscription,
            seconds: (s.micStream == nil ? 0 : micDuration) + (s.systemStream == nil ? 0 : systemDuration),
            context: UsageContext(kind: .liveTranscription, meetingID: s.meetingID, meetingTitle: meeting(s.meetingID)?.title)
        )
        liveMe = ""
        liveThem = ""
        streamStatus = nil
        if let m = meeting(s.meetingID), m.utterances.isEmpty, m.userNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            delete(s.meetingID)
            return
        }
        update(s.meetingID) { m in
            m.endedAt = Date()
            if m.appName == nil { m.appName = s.snapshotter?.app?.name }
            var offsets: [String: Double] = [:]
            offsets[AudioSource.mic.rawValue] = s.micWAV?.startOffset
            offsets[AudioSource.system.rawValue] = s.systemWAV?.startOffset
            m.audioOffsets = offsets.isEmpty ? nil : offsets
        }
        save(s.meetingID)

        await postProcess(s, micDuration: micDuration, systemDuration: systemDuration)
    }

    private func makeStream(apiKey: String, diarize: Bool, keyterms: [String], meetingID: UUID, source: AudioSource) -> STTStream {
        let stream = STTStream(config: .init(apiKey: apiKey, diarize: diarize, language: Prefs.language, keyterms: keyterms))
        stream.onSegments = { [weak self] segments, epoch in
            Task { @MainActor in self?.ingest(segments, meetingID: meetingID, source: source, epoch: epoch, diarized: diarize) }
        }
        stream.onLive = { [weak self] text in
            Task { @MainActor in
                if source == .mic { self?.liveMe = text } else { self?.liveThem = text }
            }
        }
        stream.onStatus = { [weak self] status in Task { @MainActor in self?.streamStatus = status } }
        return stream
    }

    private static func drain(_ stream: STTStream?) async {
        guard let stream else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            stream.stop { continuation.resume() }
        }
    }

    private func ingest(_ segments: [STTStream.Segment], meetingID: UUID, source: AudioSource, epoch: Int, diarized: Bool) {
        update(meetingID) { m in
            for segment in segments {
                let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                let key: String
                switch (source, diarized) {
                case (.mic, false): key = Meeting.meKey
                case (.mic, true): key = "m\(epoch)-\(segment.speaker ?? 0)"
                case (.system, _): key = "s\(epoch)-\(segment.speaker ?? 0)"
                }
                m.insert(Utterance(source: source, speakerKey: key, start: segment.start, end: segment.end, text: text))
            }
        }
    }

    private func tick() {
        guard let s = session else { return }
        elapsed = Date().timeIntervalSince(s.start)
        let seconds = Int(elapsed)
        if seconds % 10 == 0, let monitor = s.monitor {
            update(s.meetingID) { SpeakerResolver.applyActiveSpeakerVotes(to: &$0, samples: monitor.samples) }
        }
        if seconds % 30 == 0 { save(s.meetingID) }
    }

    // MARK: After the meeting

    private func postProcess(_ s: RecordingSession, micDuration: Double, systemDuration: Double) async {
        let id = s.meetingID
        defer { s.snapshotter?.deleteFrames() }
        guard let client = try? XAIClient.fromSettings(), var m = meeting(id) else { return }
        processing.insert(id)
        defer { processing.remove(id) }
        let myName = Prefs.myName
        let model = Prefs.model
        let language = Prefs.language

        // Re-diarize the full recording. Speaker numbers from one batch pass are stable for the
        // whole meeting, unlike the live stream, which restarts numbering after a reconnect.
        if s.hasSystemAudio, systemDuration > 10, let wav = s.systemWAV {
            if let segments = await batchSegments(client.tracking(.batchTranscription, m), wav: wav, language: language, keyterms: s.keyterms) {
                m.utterances.removeAll { $0.source == .system }
                m.speakers = m.speakers.filter { !$0.key.hasPrefix("s") }
                for seg in segments {
                    m.insert(Utterance(source: .system, speakerKey: "r\(seg.speaker ?? 0)", start: seg.start, end: seg.end, text: seg.text))
                }
            }
        }
        if !s.hasSystemAudio {
            if micDuration > 10, let wav = s.micWAV,
               let segments = await batchSegments(client.tracking(.batchTranscription, m), wav: wav, language: language, keyterms: s.keyterms) {
                m.utterances.removeAll { $0.source == .mic }
                m.speakers = m.speakers.filter { $0.key == Meeting.meKey || !$0.key.hasPrefix("m") }
                for seg in segments {
                    m.insert(Utterance(source: .mic, speakerKey: "v\(seg.speaker ?? 0)", start: seg.start, end: seg.end, text: seg.text))
                }
            }
            SpeakerResolver.assignDominantMicSpeakerToMe(&m)
        }

        SpeakerResolver.applyActiveSpeakerVotes(to: &m, samples: s.monitor?.samples ?? [])
        var namesOnScreen: [String] = []
        if let frames = s.snapshotter?.frames, !frames.isEmpty {
            do {
                namesOnScreen = try await SpeakerResolver.identifyFromSnapshots(
                    in: &m, frames: frames, myName: myName, client: client.tracking(.vision, m), model: model
                )
            } catch {
                banner = "Grok could not read the meeting-window snapshots: \(error.localizedDescription)"
            }
        }
        SpeakerResolver.assignSoleParticipant(in: &m, participants: m.attendees, evidence: "Only other invitee")
        if Prefs.inferNames {
            let candidates = uniqueNames(m.attendees + namesOnScreen + (s.monitor?.observedNames ?? []) + Prefs.knownPeople)
            do {
                try await SpeakerResolver.inferNames(
                    in: &m, candidates: candidates, myName: myName, client: client.tracking(.speakerNames, m), model: model
                )
            } catch {
                banner = "Grok could not match names to voices: \(error.localizedDescription)"
            }
        }
        for key in m.speakerKeys where m.speakers[key] == nil {
            m.speakers[key] = SpeakerInfo(name: nil, attribution: key == Meeting.meKey ? .me : .unknown)
        }
        m.mode = m.hasNamedRemoteSpeaker ? .named : (s.hasSystemAudio ? .meThem : .micOnly)

        if !m.utterances.isEmpty || !m.userNotes.isEmpty {
            m.templateID = meeting(id)?.templateID ?? m.templateID
            do {
                try await writeNotes(into: &m, client: client)
            } catch {
                banner = "Grok could not write the notes: \(error.localizedDescription)"
            }
        }
        if !m.utterances.isEmpty, (m.topics ?? []).isEmpty {
            m.topics = try? await topics(for: m, client: client)
        }

        // Keep edits made while processing ran.
        if let current = meeting(id) {
            m.userNotes = current.userNotes
            m.title = current.title
            m.autoTitle = current.autoTitle
            m.tags = current.tags
            m.pinned = current.pinned
            m.templateID = current.templateID
            for (key, info) in current.speakers where info.attribution == .manual { m.speakers[key] = info }
        }
        if m.autoTitle, let notes = m.enhancedNotes, let title = NotesGenerator.title(fromNotes: notes) {
            m.title = title
        }

        if !Prefs.keepAudio {
            for wav in [s.micWAV, s.systemWAV].compactMap({ $0 }) { try? FileManager.default.removeItem(at: wav.url) }
        }
        let confirmed = m.speakers.values.filter { [.activeSpeaker, .onScreen, .manual].contains($0.attribution) }.compactMap(\.name)
        Prefs.remember(confirmed)

        update(id) { $0 = m }
        save(id)
        clips.invalidate(id)

        if Prefs.autoTag, m.enhancedNotes != nil {
            await applySuggestedTags(id, client: client)
        }
    }

    private func batchSegments(_ client: XAIClient, wav: WAVWriter, language: String, keyterms: [String]) async -> [STTStream.Segment]? {
        do {
            let result = try await client.transcribe(fileURL: wav.url, diarize: true, language: language, keyterms: keyterms)
            let words = (result.words ?? []).map { STTStream.Word(text: $0.text, start: $0.start, end: $0.end, speaker: $0.speaker) }
            let segments = STTStream.group(words, offset: wav.startOffset ?? 0)
            return segments.isEmpty ? nil : segments
        } catch {
            banner = "The full-recording pass failed, so the live transcript was kept. \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: Notes and questions

    func regenerateNotes(_ id: UUID) async {
        guard var m = meeting(id), !processing.contains(id) else { return }
        var gotTopics = false
        do {
            let client = try XAIClient.fromSettings()
            processing.insert(id)
            defer { processing.remove(id) }
            gotTopics = try await writeNotes(into: &m, client: client)
            update(id) {
                $0.enhancedNotes = m.enhancedNotes
                $0.notesTemplateID = m.notesTemplateID
                if gotTopics { $0.topics = m.topics }
            }
            save(id)
        } catch {
            banner = error.localizedDescription
            return
        }
        if !gotTopics { await findTopics(id) }
    }

    func findTopics(_ id: UUID) async {
        guard let m = meeting(id), !m.utterances.isEmpty, !findingTopics.contains(id) else { return }
        findingTopics.insert(id)
        defer { findingTopics.remove(id) }
        do {
            let client = try XAIClient.fromSettings()
            let topics = try await self.topics(for: m, client: client)
            update(id) { $0.topics = topics }
            save(id)
        } catch {
            banner = "Grok could not find the topics: \(error.localizedDescription)"
        }
    }

    func focusTranscript(_ id: UUID, at seconds: Double) {
        transcriptFocus = TranscriptFocus(meetingID: id, seconds: seconds)
    }

    // MARK: Audio clips

    /// Whether clips can play for a meeting: its audio was kept and it is not being recorded.
    func canPlayClips(_ id: UUID) -> Bool {
        recordingID != id && clips.hasAudio(id)
    }

    /// Plays the audio around a time, or stops it when that clip is already playing.
    func toggleClip(_ id: UUID, at seconds: Double, until end: Double? = nil) {
        guard recordingID != id, let m = meeting(id) else { return }
        if !clips.toggle(m, at: seconds, until: end) {
            banner = "The audio for this meeting is no longer on this Mac."
        }
    }

    /// Removes kept recordings older than the retention set in Settings.
    private func deleteExpiredAudio() {
        guard let days = Prefs.audioRetentionDays else { return }
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        for m in meetings where (m.endedAt ?? m.startedAt) < cutoff {
            let dir = store.root.appendingPathComponent(m.id.uuidString, isDirectory: true)
            for source in [AudioSource.mic, .system] {
                try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(source.rawValue).wav"))
            }
        }
        clips.invalidate()
    }

    func ask(_ id: UUID, _ question: String) async {
        guard let m = meeting(id) else { return }
        update(id) { $0.chat.append(ChatMessage(role: "user", content: question)) }
        asking.insert(id)
        defer { asking.remove(id) }
        do {
            let client = try XAIClient.fromSettings()
            let answer = try await NotesGenerator.answer(question, about: m, myName: Prefs.myName, client: client.tracking(.ask, m), model: Prefs.model)
            update(id) { $0.chat.append(ChatMessage(role: "assistant", content: answer)) }
        } catch {
            update(id) { $0.chat.append(ChatMessage(role: "assistant", content: "Error: \(error.localizedDescription)")) }
        }
        save(id)
    }

    // MARK: Navigation

    /// What the detail pane shows. Home is the default when nothing else is open.
    var route: DetailRoute {
        if showLibraryChat { return .library }
        if let selectedID, meeting(selectedID) != nil { return .meeting(selectedID) }
        return .home
    }

    func openHome() {
        showLibraryChat = false
        selectedID = nil
    }

    // MARK: Ask across notes

    func openLibraryChat() {
        clips.stop()
        showLibraryChat = true
        selectedID = nil
    }

    func openMeeting(_ id: UUID) {
        guard meeting(id) != nil else { return }
        showLibraryChat = false
        selectedID = id
    }

    func askLibrary(_ question: String) async {
        guard !libraryAsking else { return }
        let history = libraryChat
        libraryChat.append(ChatMessage(role: "user", content: question))
        libraryAsking = true
        defer {
            libraryAsking = false
            saveLibraryChat()
        }
        do {
            let client = try XAIClient.fromSettings().tracking(.library)
            let answer = try await LibraryAsk.answer(
                question, history: history, meetings: meetings, myName: Prefs.myName, client: client, model: Prefs.model
            )
            libraryChat.append(ChatMessage(role: "assistant", content: answer))
        } catch {
            libraryChat.append(ChatMessage(role: "assistant", content: "Error: \(error.localizedDescription)"))
        }
    }

    func clearLibraryChat() {
        libraryChat = []
        saveLibraryChat()
    }

    private static var libraryChatURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GrokNotes/library-chat.json")
    }

    private static func loadLibraryChat() -> [ChatMessage] {
        guard let data = try? Data(contentsOf: libraryChatURL) else { return [] }
        return (try? JSONDecoder().decode([ChatMessage].self, from: data)) ?? []
    }

    private func saveLibraryChat() {
        try? JSONEncoder().encode(libraryChat).write(to: Self.libraryChatURL, options: .atomic)
    }

    func copyMarkdown(_ id: UUID) {
        guard let m = meeting(id) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(m.markdown(myName: Prefs.myName), forType: .string)
    }

    func revealInFinder(_ id: UUID) {
        NSWorkspace.shared.activateFileViewerSelecting([store.directory(for: id).appendingPathComponent("notes.md")])
    }
}
