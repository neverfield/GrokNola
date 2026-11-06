import AVFoundation
import Combine
import Foundation

/// Plays one meeting's kept recordings, with the microphone and system audio mixed in sync on a meeting-time clock.
/// Playback runs to the end of the recording, except a clip, which stops by itself at the end of its stretch.
/// The microphone is often recorded much quieter than system audio, so each track's speech level is measured
/// and, with "Balance voices" on, both are brought to the same level.
@MainActor
final class ClipPlayer: ObservableObject {
    struct NowPlaying: Equatable {
        var meetingID: UUID
        /// The time that was asked for. Asking for the same time again pauses the clip.
        var anchor: Double
        /// Meeting seconds.
        var start: Double
        var end: Double
        var speakerKey: String?
    }

    static let leadIn = 1.5
    static let minLength = 8.0
    static let maxLength = 30.0
    static let rates: [Float] = [1, 1.25, 1.5, 2]
    private static let minDuration = 0.5

    /// The clip in progress. Nil during continuous playback.
    @Published private(set) var nowPlaying: NowPlaying?
    @Published private(set) var loadedID: UUID?
    /// Meeting time where the last recording ends.
    @Published private(set) var duration: Double = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var rate: Float = 1
    @Published private(set) var balanceVoices = Prefs.balanceVoices
    /// dB added to the microphone track, on top of balancing.
    @Published private(set) var myVoiceGain = Prefs.myVoiceGain
    /// dB added to the system audio track, on top of balancing.
    @Published private(set) var othersGain = Prefs.othersGain
    @Published private(set) var myVoiceMuted = Prefs.myVoiceMuted
    @Published private(set) var othersMuted = Prefs.othersMuted
    /// The meeting and playback time, ten times a second while playing and after every seek.
    /// Not `@Published`, so only views that subscribe redraw.
    let ticks = PassthroughSubject<(meetingID: UUID, seconds: Double), Never>()

    private let root: URL
    /// Renders with no output device, pulled by the caller through `mix.engine`. For checks that must stay silent.
    private let offline: Bool
    private(set) var mix: MeetingMix?
    private var sources: [AudioSource] = []
    /// Where playback started, or the paused position.
    private var anchorTime: Double = 0
    private var clipEnd: Double?
    private var finishedAt: Date?
    private var timer: Timer?
    private var configObserver: NSObjectProtocol?
    private var audioCache: [UUID: Bool] = [:]
    /// Measured speech levels in dBFS per meeting and track. Nil for a track with too little speech to tell.
    private var levelCache: [UUID: [String: Float?]] = [:]

    init(root: URL, offline: Bool = false) {
        self.root = root
        self.offline = offline
    }

    /// The playback position in meeting seconds.
    var currentTime: Double {
        guard isPlaying, let mix else { return anchorTime }
        return min(max(anchorTime, mix.position), clipEnd ?? duration)
    }

    /// Seconds into the current clip.
    var elapsed: Double {
        guard let nowPlaying else { return 0 }
        return min(max(0, currentTime - nowPlaying.start), nowPlaying.end - nowPlaying.start)
    }

    /// Whether the meeting has a kept recording on disk. Cached; call `invalidate` when files change.
    func hasAudio(_ meetingID: UUID) -> Bool {
        if let cached = audioCache[meetingID] { return cached }
        let found = !openTracks(for: meetingID).isEmpty
        audioCache[meetingID] = found
        return found
    }

    /// Forgets cached file checks, and unloads a meeting whose recording is gone.
    func invalidate(_ meetingID: UUID? = nil) {
        if let meetingID {
            audioCache[meetingID] = nil
            levelCache[meetingID] = nil
        } else {
            audioCache.removeAll()
            levelCache.removeAll()
        }
        if let loadedID, meetingID == nil || meetingID == loadedID, !hasAudio(loadedID) { stop() }
    }

    // MARK: Whole meeting

    /// Opens the meeting's recordings, keeping the position when it is already loaded. Returns false when there is no audio.
    @discardableResult
    func load(_ meeting: Meeting) -> Bool {
        if loadedID == meeting.id, mix != nil { return true }
        stop()
        let opened = openTracks(for: meeting.id)
        let tracks = opened.map { MeetingMix.Track(pcm: $0.pcm, offset: meeting.audioOffsets?[$0.source.rawValue] ?? 0) }
        guard !tracks.isEmpty, let mix = try? MeetingMix(tracks: tracks, offlineFrames: offline ? 4096 : nil) else {
            if opened.isEmpty { audioCache[meeting.id] = false }
            return false
        }
        mix.setRate(rate)
        self.mix = mix
        sources = opened.map(\.source)
        loadedID = meeting.id
        duration = mix.duration
        anchorTime = 0
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: mix.engine, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.restartAfterDeviceChange() }
        }
        applyGains()
        measureLevels(meeting, tracks: Array(zip(opened.map(\.source), tracks)))
        return true
    }

    /// Plays from `seconds` without stopping at a clip end.
    @discardableResult
    func play(_ meeting: Meeting, from seconds: Double) -> Bool {
        guard load(meeting) else { return false }
        endClip()
        start(at: seconds)
        return true
    }

    /// Resumes from the current position, or from the start after reaching the end.
    func play() {
        guard mix != nil else { return }
        start(at: anchorTime >= duration - 0.25 ? 0 : anchorTime)
    }

    func pause() {
        guard isPlaying else { return }
        anchorTime = currentTime
        mix?.pause()
        isPlaying = false
        stopTimer()
        endClip()
        sendTick()
    }

    func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    func seek(to seconds: Double) {
        guard mix != nil else { return }
        endClip()
        if isPlaying {
            start(at: seconds)
        } else {
            anchorTime = min(max(0, seconds), duration)
            sendTick()
        }
    }

    func skip(_ delta: Double) {
        seek(to: currentTime + delta)
    }

    func setRate(_ newRate: Float) {
        guard newRate != rate else { return }
        rate = newRate
        mix?.setRate(newRate)
    }

    func setBalanceVoices(_ on: Bool) {
        balanceVoices = on
        Prefs.balanceVoices = on
        applyGains()
    }

    func setMyVoiceGain(_ dB: Double) {
        Prefs.myVoiceGain = dB
        myVoiceGain = Prefs.myVoiceGain
        applyGains()
    }

    func setOthersGain(_ dB: Double) {
        Prefs.othersGain = dB
        othersGain = Prefs.othersGain
        applyGains()
    }

    func setMyVoiceMuted(_ on: Bool) {
        myVoiceMuted = on
        Prefs.myVoiceMuted = on
        applyGains()
    }

    func setOthersMuted(_ on: Bool) {
        othersMuted = on
        Prefs.othersMuted = on
        applyGains()
    }

    /// Whether any voice control differs from its default.
    var voicesAdjusted: Bool {
        !balanceVoices || myVoiceGain != 0 || othersGain != 0 || myVoiceMuted || othersMuted
    }

    /// Balancing on, both gains at 0 dB, nothing muted.
    func resetVoices() {
        Prefs.balanceVoices = true
        Prefs.myVoiceGain = 0
        Prefs.othersGain = 0
        Prefs.myVoiceMuted = false
        Prefs.othersMuted = false
        balanceVoices = true
        myVoiceGain = 0
        othersGain = 0
        myVoiceMuted = false
        othersMuted = false
        applyGains()
    }

    /// Stops playback and closes the recordings.
    func stop() {
        stopTimer()
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
        mix?.stop()
        mix = nil
        sources = []
        anchorTime = 0
        clipEnd = nil
        if nowPlaying != nil { nowPlaying = nil }
        if isPlaying { isPlaying = false }
        if loadedID != nil { loadedID = nil }
        if duration != 0 { duration = 0 }
    }

    // MARK: Clips

    func isPlayingClip(_ meetingID: UUID, at anchor: Double) -> Bool {
        isPlaying && nowPlaying?.meetingID == meetingID && nowPlaying?.anchor == anchor
    }

    /// Starts the clip around `seconds`, or pauses it if that clip is already playing. Returns false when there is no audio.
    @discardableResult
    func toggle(_ meeting: Meeting, at seconds: Double, until end: Double? = nil) -> Bool {
        if isPlayingClip(meeting.id, at: seconds) {
            pause()
            return true
        }
        return play(meeting, at: seconds, until: end)
    }

    /// Plays from just before `seconds` to the end of the transcript block there, 8 to 30 seconds.
    @discardableResult
    func play(_ meeting: Meeting, at seconds: Double, until explicitEnd: Double? = nil) -> Bool {
        guard load(meeting) else { return false }
        let block = Self.block(containing: seconds, in: meeting.utterances)
        let start = max(0, seconds - Self.leadIn)
        let spokenEnd = (explicitEnd ?? block?.end ?? seconds) + 0.5
        let end = min(max(spokenEnd, start + Self.minLength), start + Self.maxLength)
        clipEnd = end
        nowPlaying = NowPlaying(meetingID: meeting.id, anchor: seconds, start: start, end: end, speakerKey: block?.speakerKey)
        self.start(at: start)
        return true
    }

    // MARK: Engine

    private func start(at seconds: Double) {
        guard let mix else { return }
        let t = min(max(0, seconds), duration)
        do {
            try mix.play(from: t, until: clipEnd ?? duration)
        } catch {
            NSLog("GrokNotes: could not start playback: \(error)")
            mix.pause()
            if isPlaying { isPlaying = false }
            stopTimer()
            return
        }
        anchorTime = t
        finishedAt = nil
        if !isPlaying { isPlaying = true }
        startTimer()
        sendTick()
    }

    /// Ends playback once rendering reached the stop point and the last of it has been heard.
    private func tick() {
        guard isPlaying, let mix else { return }
        if mix.finished {
            let reached = finishedAt ?? Date()
            finishedAt = reached
            // Time-stretch holds up to 0.2 s that the reported latency can leave out.
            guard Date().timeIntervalSince(reached) >= max(mix.latency, 0.2) else { return sendTick() }
            let end = clipEnd ?? duration
            pause()
            anchorTime = end
            sendTick()
        } else {
            sendTick()
        }
    }

    /// The engine stops when the output device changes. Picks up where it was.
    private func restartAfterDeviceChange() {
        guard isPlaying else { return }
        start(at: currentTime)
    }

    private func sendTick() {
        if let loadedID { ticks.send((loadedID, currentTime)) }
    }

    private func endClip() {
        clipEnd = nil
        if nowPlaying != nil { nowPlaying = nil }
    }

    private func startTimer() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    /// A meeting's kept recordings, skipping missing, empty, and too-short files.
    private func openTracks(for meetingID: UUID) -> [(source: AudioSource, pcm: PCMTrack)] {
        let dir = root.appendingPathComponent(meetingID.uuidString, isDirectory: true)
        return [AudioSource.mic, .system].compactMap { source in
            guard let pcm = PCMTrack(url: dir.appendingPathComponent("\(source.rawValue).wav")), pcm.duration >= Self.minDuration else { return nil }
            return (source, pcm)
        }
    }

    // MARK: Levels

    private func applyGains() {
        guard let mix, let loadedID else { return }
        let levels = levelCache[loadedID] ?? [:]
        let gains = SpeechLevel.gains(
            mic: levels[AudioSource.mic.rawValue] ?? nil,
            system: levels[AudioSource.system.rawValue] ?? nil,
            balance: balanceVoices,
            myVoice: Float(myVoiceGain),
            others: Float(othersGain)
        )
        let mic = myVoiceMuted ? -Float.infinity : gains.mic
        let system = othersMuted ? -Float.infinity : gains.system
        mix.setGains(sources.map { $0 == .mic ? mic : system })
    }

    /// Measures each track's speech level off the main thread, once per meeting, then applies the gains.
    private func measureLevels(_ meeting: Meeting, tracks: [(AudioSource, MeetingMix.Track)]) {
        guard levelCache[meeting.id] == nil else { return }
        let spans: [AudioSource: [(start: Double, end: Double)]] = Dictionary(grouping: meeting.utterances, by: \.source)
            .mapValues { utterances in utterances.map { (start: $0.start, end: $0.end) } }
        let id = meeting.id
        let jobs = tracks.map { source, track in
            (source.rawValue, track.pcm, (spans[source] ?? []).map { (start: $0.start - track.offset, end: $0.end - track.offset) })
        }
        Task.detached(priority: .utility) { [weak self] in
            var levels: [String: Float?] = [:]
            for (key, pcm, fileSpans) in jobs { levels[key] = SpeechLevel.measure(pcm, spans: fileSpans) }
            guard let self else { return }
            await self.store(levels, for: id)
        }
    }

    private func store(_ levels: [String: Float?], for id: UUID) {
        levelCache[id] = levels
        if loadedID == id { applyGains() }
    }

    /// The run of consecutive utterances by one speaker around `seconds`, as the transcript shows it.
    /// Citations are whole seconds, so a block may start up to one second after the cited time.
    static func block(containing seconds: Double, in utterances: [Utterance]) -> (speakerKey: String, start: Double, end: Double)? {
        var blocks: [(speakerKey: String, start: Double, end: Double)] = []
        for u in utterances {
            if let last = blocks.last, last.speakerKey == u.speakerKey {
                blocks[blocks.count - 1].end = max(last.end, u.end)
            } else {
                blocks.append((u.speakerKey, u.start, u.end))
            }
        }
        return blocks.last { $0.start < seconds + 1 } ?? blocks.first
    }
}
