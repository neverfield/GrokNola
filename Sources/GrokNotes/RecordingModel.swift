import Foundation

/// Input level of one capture source, written from its audio thread and read by the meter timer.
final class InputLevelMeter: @unchecked Sendable {
    /// RMS above this counts as speech. Matches the remote-speech threshold the snapshotter uses.
    static let speechRMS = 500.0
    /// RMS below this is treated as no signal at all, such as a muted or wrong input device.
    static let signalRMS = 40.0

    private let lock = NSLock()
    private var peak = 0.0
    private var lastSignal = Date()
    private var lastSpeech = Date.distantPast

    /// Called from the audio thread with each PCM16 chunk.
    func record(_ pcm: Data) {
        let rms = SpeechActivity.level(pcm)
        let now = Date()
        lock.withLock {
            peak = max(peak, rms)
            if rms >= Self.signalRMS { lastSignal = now }
            if rms >= Self.speechRMS { lastSpeech = now }
        }
    }

    /// The loudest level since the last read, from 0 to 1 on a -60...0 dBFS scale, and when the source was last heard.
    func read() -> (level: Double, lastSignal: Date, lastSpeech: Date) {
        lock.withLock {
            let rms = peak
            peak = 0
            let dB = rms > 0 ? 20 * log10(rms / 32_767) : -60
            return (min(max((dB + 60) / 60, 0), 1), lastSignal, lastSpeech)
        }
    }
}

/// State that changes every second or faster while a meeting is recorded: the clock and interim text.
/// It is separate from `AppState` so a tick redraws only the views that show these values, not the sidebar,
/// Home, or the transcript. Input levels publish ten times a second from their own object, `levels`.
@MainActor
final class RecordingModel: ObservableObject {
    @Published private(set) var elapsed: TimeInterval = 0
    @Published var liveMe = ""
    @Published private(set) var liveThem = ""
    /// The diarized speaker of the interim call-audio text, or nil until the stream labels it.
    @Published private(set) var liveThemKey: String?
    /// The name the meeting app shows as talking, when the interim text has no speaker key that matches it.
    @Published private(set) var liveThemTalker: String?
    /// The last finished utterance on each side, for the live strip when no interim text is showing.
    @Published private(set) var lastMe = ""
    @Published private(set) var lastThem = ""
    /// The speaker key of the last finished call-audio utterance, for the name beside the live line.
    @Published private(set) var lastThemKey: String?
    /// When the current recording started. Not published; it is set before `AppState.recordingID`.
    private(set) var startedAt: Date?
    let levels = InputLevels()
    let speakers = LiveSpeakerNames()

    func reset(startedAt: Date? = nil) {
        self.startedAt = startedAt
        elapsed = 0
        liveMe = ""
        liveThem = ""
        liveThemKey = nil
        liveThemTalker = nil
        lastMe = ""
        lastThem = ""
        lastThemKey = nil
        levels.reset()
        speakers.reset()
    }

    func setElapsed(_ seconds: TimeInterval) {
        if Int(seconds) != Int(elapsed) { elapsed = seconds }
    }

    func heardLive(_ text: String, key: String?, talker: String?) {
        if liveThem != text { liveThem = text }
        if liveThemKey != key { liveThemKey = key }
        if liveThemTalker != talker { liveThemTalker = talker }
    }

    func heardFinal(_ text: String, source: AudioSource, key: String? = nil) {
        if source == .mic {
            lastMe = text
        } else {
            lastThem = text
            if lastThemKey != key { lastThemKey = key }
        }
    }
}

/// Speaker names found while recording, published only when a name changes.
/// Speaker chips and the live lines observe this, so a name redraws them and nothing else.
@MainActor
final class LiveSpeakerNames: ObservableObject {
    /// Names for the meeting being recorded: names you set, then names found live, confirmed or not.
    @Published private(set) var infos: [String: SpeakerInfo] = [:]
    /// True while speakers are being identified live, so unnamed voices can show "identifying…".
    @Published private(set) var identifying = false

    func set(_ infos: [String: SpeakerInfo]) {
        if infos != self.infos { self.infos = infos }
    }

    func setIdentifying(_ on: Bool) {
        if identifying != on { identifying = on }
    }

    func reset() {
        set([:])
        setIdentifying(false)
    }
}

/// Mic and call-audio meters and health, published about ten times a second while recording.
@MainActor
final class InputLevels: ObservableObject {
    /// One capture source's meter and health.
    struct Source: Equatable {
        /// 0 to 1, quantized so small changes do not publish.
        var level = 0.0
        var active = false
        /// A reason to check this source, shown in orange beside its meter.
        var warning: String?
        /// The transcription stream's reconnect or error message.
        var streamStatus: String?
    }

    /// Silence on one side for longer than this, while the other side talks, raises a warning.
    static let silenceWarningSeconds: TimeInterval = 20

    @Published private(set) var mic = Source()
    @Published private(set) var system = Source()

    let micMeter = InputLevelMeter()
    let systemMeter = InputLevelMeter()

    func reset() {
        mic = Source()
        system = Source()
    }

    func setActive(mic: Bool, system: Bool) {
        self.mic.active = mic
        self.system.active = system
    }

    func setStreamStatus(_ status: String?, source: AudioSource) {
        if source == .mic {
            if mic.streamStatus != status { mic.streamStatus = status }
        } else if system.streamStatus != status {
            system.streamStatus = status
        }
    }

    /// Samples both meters and updates the silence warnings.
    func sample(elapsed: TimeInterval, now: Date = Date()) {
        let m = micMeter.read()
        let s = systemMeter.read()
        let micSilent = now.timeIntervalSince(m.lastSignal)
        let systemQuiet = now.timeIntervalSince(s.lastSpeech)
        let micTalking = now.timeIntervalSince(m.lastSpeech) < Self.silenceWarningSeconds
        let othersTalking = systemQuiet < Self.silenceWarningSeconds

        var nextMic = mic
        nextMic.level = mic.active ? Self.quantize(m.level) : 0
        nextMic.warning = mic.active && system.active && othersTalking && micSilent > Self.silenceWarningSeconds
            ? "No audio from your mic for \(Int(micSilent))s — check the input device in System Settings > Sound."
            : nil
        var nextSystem = system
        nextSystem.level = system.active ? Self.quantize(s.level) : 0
        nextSystem.warning = system.active && micTalking && systemQuiet > Self.silenceWarningSeconds && elapsed > Self.silenceWarningSeconds
            ? "No call audio — is the meeting app playing through this Mac?"
            : nil
        if nextMic != mic { mic = nextMic }
        if nextSystem != system { system = nextSystem }
    }

    private static func quantize(_ level: Double) -> Double {
        (level * 12).rounded() / 12
    }
}
