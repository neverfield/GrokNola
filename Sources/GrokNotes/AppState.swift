import AVFoundation
import AppKit
import ApplicationServices
import SwiftUI

struct Permissions {
    var microphone = false
    var systemAudio = false
    var accessibility = false
    /// Apple Calendar access.
    var calendar = false
    /// A fresh calendar.json from the Cursor sync.
    var calendarFile = false
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
    var identifier: LiveSpeakerIdentifier?
    /// The identifier's latest names, before names you set are applied.
    var liveSpeakers: [String: SpeakerInfo] = [:]
    /// Live names you cleared, by speaker key, lowercased, so the same guess does not come back.
    var rejectedLive: [String: String] = [:]
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
    @Published var meetings: [Meeting] = [] {
        didSet { meetingsRevision &+= 1 }
    }
    /// Changes on every edit to `meetings`, so views can cache what they derive from the list.
    private(set) var meetingsRevision = 0
    @Published var selectedID: UUID? {
        didSet {
            if let playing = clips.loadedID, playing != selectedID, selectedID != nil { clips.stop() }
        }
    }
    @Published private(set) var recordingID: UUID?
    @Published private(set) var processing: Set<UUID> = []
    @Published private(set) var asking: Set<UUID> = []
    /// Meetings with a Find topics or Find chapters request in flight.
    @Published var findingTopics: Set<UUID> = []
    /// Where each meeting's after-meeting steps are. Kept after a failure so the step can be retried.
    @Published private(set) var processingStage: [UUID: ProcessingProgress] = [:]
    @Published var transcriptFocus: TranscriptFocus?
    @Published private(set) var detectedApp: MeetingDetector.App?
    /// Messages across the top of the window, oldest first.
    @Published private(set) var banners: [BannerItem] = []
    @Published private(set) var permissions = Permissions()
    /// True while the detail pane shows the chat across all notes instead of a meeting.
    @Published var showLibraryChat = false
    @Published private(set) var libraryChat: [ChatMessage] = []
    @Published private(set) var libraryAsking = false
    /// What the question in flight is answered from, for the progress line.
    @Published private(set) var libraryRoute: HelpRouter.Route = .meetings
    /// The meeting whose regenerate waits for the user to choose what happens to their edited notes.
    @Published var regenerateConfirmation: UUID?
    /// The notes each meeting had before its last regenerate this session, for Undo regenerate.
    var regenerateUndo: [UUID: RegenerateUndo] = [:]

    let store = MeetingStore()
    let usage = UsageLedger()
    let tagCatalog = TagCatalog()
    let templateCatalog = TemplateCatalog()
    let clips: ClipPlayer
    let calendars = CalendarHub()
    /// The clock, interim text and input levels while recording. Views that show them observe this, not `AppState`.
    let recording = RecordingModel()
    let notifications = AppNotifications()
    /// Deleted meetings, kept 30 days for Undo. Purges old ones when created at launch.
    let trash = MeetingTrash()
    private var session: RecordingSession?
    private var detectorTimer: Timer?
    private var saveTasks: [UUID: Task<Void, Never>] = [:]
    private var bannerTimers: [UUID: Task<Void, Never>] = [:]
    /// Consecutive detector polls that saw a meeting app, so a brief mic use does not notify.
    private var detectionStreak = 0
    /// The app a "call detected" notification was posted for, until the call ends.
    private var notifiedDetection: String?

    init() {
        clips = ClipPlayer(root: store.root)
        meetings = store.loadAll()
        deleteExpiredAudio()
        tagCatalog.reconcile(with: meetings)
        libraryChat = Self.loadLibraryChat()
        refreshPermissions()
        notifications.app = self
        notifications.configure()
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
            m.refreshAttributionMode()
        }
        if !name.isEmpty, key != Meeting.meKey { Prefs.remember([name]) }
        if let s = session, s.meetingID == meetingID {
            if name.isEmpty, let guess = s.liveSpeakers[key]?.name { s.rejectedLive[key] = guess.lowercased() }
            publishLiveSpeakers()
        }
        save(meetingID)
    }

    func delete(_ id: UUID) {
        guard id != recordingID else { return }
        if clips.loadedID == id { clips.stop() }
        meetings.removeAll { $0.id == id }
        processingStage[id] = nil
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
            showBanner("Could not save \"\(m.title)\": \(error.localizedDescription)", severity: .error)
        }
    }

    // MARK: Banners

    /// Adds a banner. The same message is not shown twice at once. Info banners close after six seconds by default.
    func showBanner(_ message: String, severity: BannerItem.Severity, action: BannerItem.Action? = nil, autoDismiss: TimeInterval? = nil) {
        guard !banners.contains(where: { $0.message == message }) else { return }
        let item = BannerItem(severity: severity, message: message, action: action, autoDismiss: autoDismiss ?? (severity == .info ? 6 : nil))
        banners.append(item)
        if banners.count > 6 { banners.removeFirst(banners.count - 6) }
        if let seconds = item.autoDismiss {
            bannerTimers[item.id] = Task { [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled else { return }
                self?.dismissBanner(item.id)
            }
        }
    }

    /// An error banner. When the failure is a missing API key it offers to open Settings.
    func reportError(_ error: Error, _ prefix: String? = nil) {
        let message = [prefix, error.localizedDescription].compactMap { $0 }.joined(separator: " ")
        if XAIClient.storedAPIKey() == nil {
            showBanner(message, severity: .error, action: Self.openSettingsAction)
        } else {
            showBanner(message, severity: .error)
        }
    }

    func dismissBanner(_ id: UUID) {
        bannerTimers.removeValue(forKey: id)?.cancel()
        banners.removeAll { $0.id == id }
    }

    func dismissAllBanners() {
        for id in banners.map(\.id) { dismissBanner(id) }
    }

    /// Older call sites set a message string. Setting shows it as an error; setting nil closes the newest banner.
    var banner: String? {
        get { banners.last?.message }
        set {
            if let newValue {
                showBanner(newValue, severity: .error)
            } else if let last = banners.last {
                dismissBanner(last.id)
            }
        }
    }

    static let openSettingsAction = BannerItem.Action(label: "Open Settings") {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    func scheduleSave(_ id: UUID) {
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
            calendar: calendars.apple.isAuthorized,
            calendarFile: calendars.hasFreshFile
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
        _ = await calendars.apple.requestAccess()
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
        noteDetection(app)
    }

    /// Posts "<App> call detected" once per call, after two polls in a row see it.
    private func noteDetection(_ app: MeetingDetector.App?) {
        guard let app else {
            detectionStreak = 0
            if notifiedDetection != nil {
                notifiedDetection = nil
                notifications.clearMeetingDetected()
            }
            return
        }
        detectionStreak += 1
        guard detectionStreak >= 2, notifiedDetection == nil else { return }
        notifiedDetection = app.name
        if Prefs.notifyOnMeetingDetected { notifications.meetingDetected(app.name) }
    }

    // MARK: Recording

    /// Starts recording. Pass an event, such as one picked on Home, to use its title and invitees.
    func startMeeting(event picked: CalendarEvent? = nil) async {
        guard session == nil else { return }
        clips.stop()
        guard let apiKey = XAIClient.storedAPIKey() else {
            showBanner("Add your xAI API key in Settings (Command-comma) first.", severity: .error, action: Self.openSettingsAction)
            return
        }
        guard await MicCapture.requestPermission() else {
            showBanner(
                "GrokNola needs microphone access. Turn it on in System Settings > Privacy & Security > Microphone.",
                severity: .error,
                action: BannerItem.Action(label: "Open Privacy Settings") { [weak self] in self?.openPrivacyPane("Privacy_Microphone") }
            )
            refreshPermissions()
            return
        }

        let now = Date()
        let app = MeetingDetector.detect(micInUse: MeetingDetector.micInUse())
        notifiedDetection = app?.name ?? notifiedDetection
        notifications.clearMeetingDetected()
        calendars.reload()
        let event = picked ?? calendars.currentEvent(at: now)
        let myName = Prefs.myName
        var meeting = Meeting(
            title: event?.title ?? "\(app?.name ?? "Meeting") · \(now.formatted(date: .abbreviated, time: .shortened))",
            autoTitle: event == nil,
            startedAt: now
        )
        meeting.appName = app?.name ?? event?.meetingAppName
        meeting.attendees = event?.attendeeNames ?? []
        if let emails = event?.attendeeEmails, !emails.isEmpty { meeting.attendeeEmails = emails }
        meetings.insert(meeting, at: 0)
        selectedID = meeting.id

        let s = RecordingSession(meetingID: meeting.id, start: now, app: app)
        s.keyterms = Array(uniqueNames(meeting.attendees + Prefs.knownPeople + [myName]).filter { $0.count <= 50 }.prefix(100))
        session = s
        recordingID = meeting.id
        recording.reset(startedAt: now)
        let dir = store.directory(for: meeting.id)
        let meetingID = meeting.id
        let micMeter = recording.levels.micMeter
        let systemMeter = recording.levels.systemMeter

        // Remote participants: system audio, diarized.
        let system = SystemAudioCapture()
        let systemStream = makeStream(apiKey: apiKey, diarize: true, keyterms: s.keyterms, meetingID: meetingID, source: .system)
        let systemWAV = try? WAVWriter(url: dir.appendingPathComponent("system.wav"))
        let remoteSpeech = SpeechActivity()
        system.onPCM = { data in
            let t = Date().timeIntervalSince(now) - Double(data.count) / 32_000
            systemStream.append(data, at: t)
            systemWAV?.write(data, at: t)
            if SpeechActivity.level(data) > InputLevelMeter.speechRMS { remoteSpeech.mark() }
            systemMeter.record(data)
        }
        system.onError = { [weak self] message in
            Task { @MainActor in self?.recording.levels.setStreamStatus(message, source: .system) }
        }
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
            showBanner(
                "System audio is off (\(error.localizedDescription)). Recording the microphone only. Allow Screen & System Audio Recording to separate remote speakers.",
                severity: .warning,
                action: BannerItem.Action(label: "Open Privacy Settings") { [weak self] in self?.openPrivacyPane("Privacy_ScreenCapture") }
            )
        }

        // The local user: microphone. Diarize it only when there is no separate system audio.
        let mic = MicCapture()
        let micStream = makeStream(apiKey: apiKey, diarize: !s.hasSystemAudio, keyterms: s.keyterms, meetingID: meetingID, source: .mic)
        let micWAV = try? WAVWriter(url: dir.appendingPathComponent("mic.wav"))
        mic.onPCM = { data in
            let t = Date().timeIntervalSince(now) - Double(data.count) / 32_000
            micStream.append(data, at: t)
            micWAV?.write(data, at: t)
            micMeter.record(data)
        }
        do {
            let wantsEchoCancellation = Prefs.echoCancellation && s.hasSystemAudio
            try mic.start(echoCancellation: wantsEchoCancellation)
            if wantsEchoCancellation && !mic.echoCancellationActive {
                showBanner(
                    "Echo cancellation is not supported by your current audio devices. Use headphones so other voices are not transcribed as you.",
                    severity: .warning
                )
            }
            s.mic = mic
            s.micStream = micStream
            s.micWAV = micWAV
            micStream.start()
        } catch {
            micWAV?.close()
            showBanner("Could not start the microphone: \(error.localizedDescription)", severity: .error)
        }
        recording.levels.setActive(mic: s.mic != nil, system: s.hasSystemAudio)

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
        if s.hasSystemAudio, Prefs.liveSpeakerID {
            let identifier = LiveSpeakerIdentifier(
                config: .init(
                    myName: myName,
                    attendees: meeting.attendees,
                    knownPeople: Prefs.knownPeople,
                    appName: meeting.appName,
                    useVision: Prefs.useSnapshots && Prefs.liveSpeakerSnapshots
                ),
                monitor: s.monitor,
                snapshotter: s.snapshotter,
                meeting: { [weak self] in self?.meeting(meetingID) }
            )
            identifier.onChange = { [weak self] infos in self?.applyLiveSpeakers(infos, meetingID: meetingID) }
            s.identifier = identifier
            recording.speakers.setIdentifying(true)
        }

        update(meetingID) { m in
            m.speakers[Meeting.meKey] = SpeakerInfo(name: nil, attribution: .me)
            m.mode = s.hasSystemAudio ? .detecting : .micOnly
        }
        save(meetingID)
        refreshPermissions()

        // Ten times a second for the level meters; the once-a-second work runs when the second changes.
        s.timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func stopMeeting() async {
        guard let s = session else { return }
        let id = s.meetingID
        s.identifier?.finish()
        session = nil
        recordingID = nil
        // Show progress right away; draining the streams can take a few seconds.
        processing.insert(id)
        var progress = ProcessingProgress()
        progress.set(.transcribing, .running)
        processingStage[id] = progress
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
        recording.reset()
        if let m = meeting(id), m.utterances.isEmpty, m.userNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            processing.remove(id)
            delete(id)
            showBanner("Nothing was recorded, so the meeting was discarded.", severity: .info)
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
        stream.onLive = { [weak self] text, speaker, epoch in
            Task { @MainActor in
                guard let self else { return }
                if source == .mic {
                    self.recording.liveMe = text
                } else {
                    self.heardLiveThem(text, speaker: speaker, epoch: epoch, meetingID: meetingID)
                }
            }
        }
        stream.onStatus = { [weak self] status in
            Task { @MainActor in self?.recording.levels.setStreamStatus(status, source: source) }
        }
        return stream
    }

    /// Interim call-audio text has no diarized speaker until its first chunk is final, so until then the line
    /// takes the name the meeting app shows as talking. Without either, it shows a plain label.
    ///
    /// **Lag:** While waiting for diarization, the displayed talker follows `ActiveSpeakerMonitor.currentTalker`,
    /// so live lines inherit that monitor’s polling delay and nil transitions when the meeting UI shows zero or
    /// several speakers. After diarization assigns a speaker, this path stops using the monitor for that chunk.
    private func heardLiveThem(_ text: String, speaker: Int?, epoch: Int, meetingID: UUID) {
        let m = meeting(meetingID)
        if let speaker {
            let key = "s\(epoch)-\(speaker)"
            recording.heardLive(text, key: m?.aliasedKey(key) ?? key, talker: nil)
            return
        }
        guard !text.isEmpty, let talker = session?.monitor?.currentTalker() else {
            recording.heardLive(text, key: nil, talker: nil)
            return
        }
        let names = recording.speakers.infos.merging(m?.speakers ?? [:]) { live, _ in live }
        let key = m?.speakerKeys.last { $0 != Meeting.meKey && names[$0]?.name?.caseInsensitiveCompare(talker) == .orderedSame }
        recording.heardLive(text, key: key, talker: key == nil ? talker : nil)
    }

    private static func drain(_ stream: STTStream?) async {
        guard let stream else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            stream.stop { continuation.resume() }
        }
    }

    private func ingest(_ segments: [STTStream.Segment], meetingID: UUID, source: AudioSource, epoch: Int, diarized: Bool) {
        var added: [Utterance] = []
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
                let utterance = Utterance(source: source, speakerKey: m.aliasedKey(key), start: segment.start, end: segment.end, text: text)
                m.insert(utterance)
                added.append(utterance)
            }
        }
        guard meetingID == recordingID else { return }
        if let last = added.last { recording.heardFinal(last.text, source: source, key: last.speakerKey) }
        if source == .system, let identifier = session?.identifier {
            for u in added { identifier.heard(u) }
        }
    }

    private func tick() {
        guard let s = session else { return }
        let elapsed = Date().timeIntervalSince(s.start)
        recording.levels.sample(elapsed: elapsed)
        let seconds = Int(elapsed)
        guard seconds != Int(recording.elapsed) else { return }
        recording.setElapsed(elapsed)
        s.identifier?.tick(at: elapsed)
        if seconds % 30 == 0 { save(s.meetingID) }
    }

    // MARK: Live speaker names

    /// Takes the live identifier's names. Confirmed names go into the meeting, so they are saved and used in
    /// the notes; guesses stay on screen only. Names you set are never replaced.
    private func applyLiveSpeakers(_ infos: [String: SpeakerInfo], meetingID: UUID) {
        guard let s = session, s.meetingID == meetingID else { return }
        s.liveSpeakers = infos
        let accepted = acceptedLiveSpeakers(s)
        if let m = meeting(meetingID) {
            let heard = Set(m.speakerKeys)
            var speakers = m.speakers
            for (key, info) in accepted where !info.isProvisional && heard.contains(key) && key != Meeting.meKey {
                if speakers[key]?.attribution != .manual { speakers[key] = info }
            }
            // A live name that fell back to a guess, or was rejected, comes off the meeting.
            for (key, info) in m.speakers where info.identifiedLiveAt != nil && info.attribution != .manual {
                if accepted[key].map({ $0.isProvisional }) ?? true { speakers[key] = SpeakerInfo(name: nil, attribution: .unknown) }
            }
            // Writing an unchanged meeting would still redraw every view that lists meetings.
            if speakers != m.speakers { update(meetingID) { $0.speakers = speakers } }
        }
        publishLiveSpeakers()
    }

    /// Folds a merged voice's live evidence into the voice it joined, while that meeting is recording.
    func liveSpeakersMerged(from: String, into target: String, in meetingID: UUID) {
        guard let s = session, s.meetingID == meetingID else { return }
        s.rejectedLive[from] = nil
        s.identifier?.merge(from, into: target)
        publishLiveSpeakers()
    }

    private func acceptedLiveSpeakers(_ s: RecordingSession) -> [String: SpeakerInfo] {
        s.liveSpeakers.filter { key, info in
            guard let rejected = s.rejectedLive[key] else { return true }
            return info.name?.lowercased() != rejected
        }
    }

    /// Publishes the names chips show while recording: names you set, then live names, then any other stored name.
    private func publishLiveSpeakers() {
        guard let s = session, let m = meeting(s.meetingID) else {
            recording.speakers.set([:])
            return
        }
        var names = acceptedLiveSpeakers(s)
        for (key, info) in m.speakers {
            if info.attribution == .manual || (names[key] == nil && !(info.name ?? "").isEmpty) { names[key] = info }
        }
        recording.speakers.set(names)
    }

    // MARK: After the meeting

    private func postProcess(_ s: RecordingSession, micDuration: Double, systemDuration: Double) async {
        let id = s.meetingID
        defer { s.snapshotter?.deleteFrames() }
        defer { processing.remove(id) }
        guard var m = meeting(id) else {
            processingStage[id] = nil
            return
        }
        let client: XAIClient
        do {
            client = try XAIClient.fromSettings()
        } catch {
            setStep(id, .transcribing, .done)
            for step in [ProcessingProgress.Step.naming, .tagging] { setStep(id, step, .skipped) }
            setStep(id, .writing, .failed(error.localizedDescription))
            finishProcessing(id)
            return
        }
        let myName = Prefs.myName
        let model = Prefs.model
        let language = Prefs.language

        // Re-diarize the full recording. Speaker numbers from one batch pass are stable for the
        // whole meeting, unlike the live stream, which restarts numbering after a reconnect.
        let fullPass: (wav: WAVWriter, source: AudioSource)?
        if s.hasSystemAudio {
            fullPass = systemDuration > 10 ? s.systemWAV.map { ($0, .system) } : nil
        } else {
            fullPass = micDuration > 10 ? s.micWAV.map { ($0, .mic) } : nil
        }
        // Names found while recording, and names you set, carry over to the re-diarized voices.
        let live = m
        if let fullPass {
            do {
                if let segments = try await batchSegments(client.tracking(.batchTranscription, m), wav: fullPass.wav, language: language, keyterms: s.keyterms) {
                    if fullPass.source == .system {
                        m.utterances.removeAll { $0.source == .system }
                        m.speakers = m.speakers.filter { !$0.key.hasPrefix("s") }
                        for seg in segments {
                            m.insert(Utterance(source: .system, speakerKey: "r\(seg.speaker ?? 0)", start: seg.start, end: seg.end, text: seg.text))
                        }
                    } else {
                        m.utterances.removeAll { $0.source == .mic }
                        m.speakers = m.speakers.filter { $0.key == Meeting.meKey || !$0.key.hasPrefix("m") }
                        for seg in segments {
                            m.insert(Utterance(source: .mic, speakerKey: "v\(seg.speaker ?? 0)", start: seg.start, end: seg.end, text: seg.text))
                        }
                    }
                    SpeakerResolver.carryNames(from: live, into: &m)
                }
                setStep(id, .transcribing, .done)
            } catch {
                setStep(id, .transcribing, .failed("Kept the live transcript. \(error.localizedDescription)"))
            }
        } else {
            setStep(id, .transcribing, .done)
        }
        if !s.hasSystemAudio { SpeakerResolver.assignDominantMicSpeakerToMe(&m) }

        setStep(id, .naming, .running)
        var namingErrors: [String] = []
        SpeakerResolver.applyActiveSpeakerVotes(to: &m, samples: s.monitor?.samples ?? [])
        var namesOnScreen: [String] = []
        if let frames = s.snapshotter?.frames, !frames.isEmpty {
            do {
                namesOnScreen = try await SpeakerResolver.identifyFromSnapshots(
                    in: &m, frames: frames, myName: myName, client: client.tracking(.vision, m), model: model
                )
            } catch {
                namingErrors.append("Could not read the meeting-window snapshots: \(error.localizedDescription)")
            }
        }
        SpeakerResolver.assignSoleParticipant(in: &m, participants: m.attendees, evidence: "Only other invitee")
        if Prefs.inferNames {
            let candidates = uniqueNames(
                m.attendees + namesOnScreen + (s.monitor?.observedNames ?? []) + (s.identifier?.guessedNames ?? []) + Prefs.knownPeople
            )
            do {
                try await SpeakerResolver.inferNames(
                    in: &m, candidates: candidates, myName: myName, client: client.tracking(.speakerNames, m), model: model
                )
            } catch {
                namingErrors.append("Could not match names to voices: \(error.localizedDescription)")
            }
        }
        for key in m.speakerKeys where m.speakers[key] == nil {
            m.speakers[key] = SpeakerInfo(name: nil, attribution: key == Meeting.meKey ? .me : .unknown)
        }
        m.mode = m.hasNamedRemoteSpeaker ? .named : (s.hasSystemAudio ? .meThem : .micOnly)
        setStep(id, .naming, namingErrors.isEmpty ? .done : .failed(namingErrors.joined(separator: " ")))

        if !m.utterances.isEmpty || !m.userNotes.isEmpty {
            setStep(id, .writing, .running)
            m.templateID = meeting(id)?.templateID ?? m.templateID
            do {
                try await writeNotes(into: &m, client: client)
                setStep(id, .writing, .done)
            } catch {
                setStep(id, .writing, .failed(error.localizedDescription))
            }
        } else {
            setStep(id, .writing, .skipped)
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
            // Names set on the live voices while this ran belong to the re-diarized voices now.
            SpeakerResolver.carryNames(from: current, into: &m, onlyManual: true, includeManualTargets: true)
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
            setStep(id, .tagging, .running)
            let tagged = await applySuggestedTags(id, client: client, reportErrors: false)
            setStep(id, .tagging, tagged ? .done : .failed(Self.tagFailure))
        } else {
            setStep(id, .tagging, .skipped)
        }
        finishProcessing(id)
    }

    /// Nil when the pass returned no words.
    private func batchSegments(_ client: XAIClient, wav: WAVWriter, language: String, keyterms: [String]) async throws -> [STTStream.Segment]? {
        let result = try await client.transcribe(fileURL: wav.url, diarize: true, language: language, keyterms: keyterms)
        let words = (result.words ?? []).map { STTStream.Word(text: $0.text, start: $0.start, end: $0.end, speaker: $0.speaker) }
        let segments = STTStream.group(words, offset: wav.startOffset ?? 0)
        return segments.isEmpty ? nil : segments
    }

    private static let tagFailure = "Grok could not suggest tags."

    private func setStep(_ id: UUID, _ step: ProcessingProgress.Step, _ status: ProcessingProgress.Status) {
        processingStage[id]?.set(step, status)
    }

    /// Marks a step running for a retry or a regenerate, starting a one-step list when no run is showing.
    private func beginStep(_ id: UUID, _ step: ProcessingProgress.Step) {
        if processingStage[id]?.entry(step) == nil { processingStage[id] = ProcessingProgress(steps: [step]) }
        setStep(id, step, .running)
    }

    /// Ends a retried step. The list goes away once every step has succeeded.
    private func endStep(_ id: UUID, _ step: ProcessingProgress.Step, _ status: ProcessingProgress.Status) {
        setStep(id, step, status)
        if processingStage[id]?.succeeded == true { processingStage[id] = nil }
    }

    /// Tells the user the run is over. The step list stays when a step failed, so it can be retried.
    private func finishProcessing(_ id: UUID) {
        guard let progress = processingStage[id], let m = meeting(id) else {
            processingStage[id] = nil
            return
        }
        let viewing = NSApp.isActive && selectedID == id
        if !viewing {
            if case .failed(let message) = progress.status(.writing) {
                notifications.processingFailed(m, message: message)
            } else {
                notifications.notesReady(m, failedSteps: progress.failures.map(\.step))
            }
        }
        if progress.hasFailure {
            if !viewing {
                showBanner(
                    "Some steps failed for \"\(m.title)\": \(progress.failures.map { $0.step.title.lowercased() }.joined(separator: ", ")).",
                    severity: .warning,
                    action: BannerItem.Action(label: "Open Meeting") { [weak self] in self?.openMeeting(id) }
                )
            }
        } else {
            processingStage[id] = nil
        }
    }

    /// Runs one failed step again. Rewriting notes the user edited asks first.
    func retry(_ step: ProcessingProgress.Step, for id: UUID, undoManager: UndoManager? = nil) async {
        switch step {
        case .writing: requestRegenerate(id, undoManager: undoManager)
        case .naming: await renameSpeakers(id)
        case .tagging: await retagMeeting(id)
        case .transcribing: break
        }
    }

    /// Hides a step list that has a failure, without retrying.
    func dismissProcessingStage(_ id: UUID) {
        guard !processing.contains(id) else { return }
        processingStage[id] = nil
    }

    /// Matches names to unnamed voices again from the invitees and known people. Manual names are kept.
    func renameSpeakers(_ id: UUID) async {
        guard var m = meeting(id), !processing.contains(id) else { return }
        let client: XAIClient
        do {
            client = try XAIClient.fromSettings()
        } catch {
            reportError(error)
            return
        }
        processing.insert(id)
        defer { processing.remove(id) }
        beginStep(id, .naming)
        SpeakerResolver.assignSoleParticipant(in: &m, participants: m.attendees, evidence: "Only other invitee")
        do {
            try await SpeakerResolver.inferNames(
                in: &m, candidates: uniqueNames(m.attendees + Prefs.knownPeople), myName: Prefs.myName,
                client: client.tracking(.speakerNames, m), model: Prefs.model
            )
        } catch {
            endStep(id, .naming, .failed("Could not match names to voices: \(error.localizedDescription)"))
            return
        }
        update(id) { current in
            for (key, info) in m.speakers where current.speakers[key]?.attribution != .manual { current.speakers[key] = info }
            if current.hasNamedRemoteSpeaker { current.mode = .named }
        }
        save(id)
        endStep(id, .naming, .done)
    }

    /// Suggests tags again after a failed tagging step.
    func retagMeeting(_ id: UUID) async {
        let client: XAIClient
        do {
            client = try XAIClient.fromSettings()
        } catch {
            reportError(error)
            return
        }
        beginStep(id, .tagging)
        let tagged = await applySuggestedTags(id, client: client, reportErrors: false)
        endStep(id, .tagging, tagged ? .done : .failed(Self.tagFailure))
    }

    // MARK: Notes and questions

    /// Writes the notes again without asking. Use `requestRegenerate` from the UI, which protects edited notes.
    /// When notes were replaced, offers Undo regenerate.
    func regenerateNotes(_ id: UUID, undoManager: UndoManager? = nil, previous: NotesVersion? = nil) async {
        guard var m = meeting(id), !processing.contains(id) else { return }
        let before = previous ?? NotesVersion(m)
        let client: XAIClient
        do {
            client = try XAIClient.fromSettings()
        } catch {
            reportError(error)
            return
        }
        processing.insert(id)
        beginStep(id, .writing)
        let gotTopics: Bool
        do {
            gotTopics = try await writeNotes(into: &m, client: client)
        } catch {
            processing.remove(id)
            endStep(id, .writing, .failed(error.localizedDescription))
            return
        }
        update(id) {
            $0.setGeneratedNotes(m.enhancedNotes)
            $0.notesTemplateID = m.notesTemplateID
            if gotTopics { $0.topics = m.topics }
            if m.chapters != nil { $0.chapters = m.chapters }
        }
        save(id)
        processing.remove(id)
        endStep(id, .writing, .done)
        offerUndoRegenerate(id, before: before, undoManager: undoManager)
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
            reportError(error, "Grok could not find the topics.")
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

    /// Plays the audio around a time, or pauses it when that clip is already playing.
    func toggleClip(_ id: UUID, at seconds: Double, until end: Double? = nil) {
        guard recordingID != id, let m = meeting(id) else { return }
        if !clips.toggle(m, at: seconds, until: end) {
            showBanner("The audio for this meeting is no longer on this Mac.", severity: .warning)
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

    /// Opens Ask Grok, where the empty state offers help questions and the composer takes app questions.
    func openHelp() {
        openLibraryChat()
    }

    func openMeeting(_ id: UUID) {
        guard meeting(id) != nil else { return }
        showLibraryChat = false
        selectedID = id
    }

    func askLibrary(_ question: String) async {
        guard !libraryAsking else { return }
        let history = libraryChat
        let myName = Prefs.myName
        let route = LibraryAsk.route(for: question, history: history, meetings: meetings, myName: myName)
        libraryChat.append(ChatMessage(role: "user", content: question))
        libraryRoute = route
        libraryAsking = true
        defer {
            libraryAsking = false
            saveLibraryChat()
        }
        do {
            let client = try XAIClient.fromSettings().tracking(route == .help ? .help : .library)
            let answer = try await LibraryAsk.answer(
                question, history: history, meetings: meetings, myName: myName, route: route, client: client, model: Prefs.model
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

    /// Copies transcript text as plain `[mm:ss] Name: text` lines. Chapter headings are left out while recording.
    func copyTranscript(_ id: UUID, _ scope: TranscriptText.Scope) {
        guard let m = meeting(id) else { return }
        let chapters = recordingID == id ? [] : m.chapters ?? []
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(TranscriptText.text(m, myName: Prefs.myName, chapters: chapters, scope: scope), forType: .string)
    }

    func revealInFinder(_ id: UUID) {
        NSWorkspace.shared.activateFileViewerSelecting([store.directory(for: id).appendingPathComponent("notes.md")])
    }
}
