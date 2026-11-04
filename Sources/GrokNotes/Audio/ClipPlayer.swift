import AVFoundation
import Combine
import Foundation

/// Plays one meeting's kept recordings, with the microphone and system audio mixed in sync on a meeting-time clock.
/// Playback runs to the end of the recording, except a clip, which stops by itself at the end of its stretch.
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
    /// A WAV header plus half a second of 16 kHz PCM16. Shorter files hold no useful audio.
    private static let minFileBytes = 44 + 16_000

    /// The clip in progress. Nil during continuous playback.
    @Published private(set) var nowPlaying: NowPlaying?
    @Published private(set) var loadedID: UUID?
    /// Meeting time where the last recording ends.
    @Published private(set) var duration: Double = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var rate: Float = 1
    /// The meeting and playback time, ten times a second while playing and after every seek.
    /// Not `@Published`, so only views that subscribe redraw.
    let ticks = PassthroughSubject<(meetingID: UUID, seconds: Double), Never>()

    private let root: URL
    private var tracks: [(player: AVAudioPlayer, offset: Double)] = []
    /// Meeting time at `anchorDevice`, or the paused position.
    private var anchorTime: Double = 0
    private var anchorDevice: TimeInterval = 0
    private var clipEnd: Double?
    private var timer: Timer?
    private var audioCache: [UUID: Bool] = [:]

    init(root: URL) {
        self.root = root
    }

    /// The playback position in meeting seconds.
    var currentTime: Double {
        guard isPlaying, let clock = tracks.first?.player else { return anchorTime }
        return min(anchorTime + max(0, clock.deviceCurrentTime - anchorDevice) * Double(rate), duration)
    }

    /// Seconds into the current clip.
    var elapsed: Double {
        guard let nowPlaying else { return 0 }
        return min(max(0, currentTime - nowPlaying.start), nowPlaying.end - nowPlaying.start)
    }

    /// Whether the meeting has a kept recording on disk. Cached; call `invalidate` when files change.
    func hasAudio(_ meetingID: UUID) -> Bool {
        if let cached = audioCache[meetingID] { return cached }
        let found = !openTracks(for: meetingID, offsets: nil).isEmpty
        audioCache[meetingID] = found
        return found
    }

    /// Forgets cached file checks, and unloads a meeting whose recording is gone.
    func invalidate(_ meetingID: UUID? = nil) {
        if let meetingID { audioCache[meetingID] = nil } else { audioCache.removeAll() }
        if let loadedID, meetingID == nil || meetingID == loadedID, !hasAudio(loadedID) { stop() }
    }

    // MARK: Whole meeting

    /// Opens the meeting's recordings, keeping the position when it is already loaded. Returns false when there is no audio.
    @discardableResult
    func load(_ meeting: Meeting) -> Bool {
        if loadedID == meeting.id, !tracks.isEmpty { return true }
        stop()
        let loaded = openTracks(for: meeting.id, offsets: meeting.audioOffsets)
        loaded.forEach { $0.player.prepareToPlay() }
        guard !loaded.isEmpty else {
            audioCache[meeting.id] = false
            return false
        }
        tracks = loaded
        loadedID = meeting.id
        duration = loaded.map { $0.offset + $0.player.duration }.max() ?? meeting.duration
        anchorTime = 0
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
        guard !tracks.isEmpty else { return }
        start(at: anchorTime >= duration - 0.25 ? 0 : anchorTime)
    }

    func pause() {
        guard isPlaying else { return }
        anchorTime = currentTime
        tracks.forEach { $0.player.pause() }
        isPlaying = false
        stopTimer()
        endClip()
        sendTick()
    }

    func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    func seek(to seconds: Double) {
        guard !tracks.isEmpty else { return }
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
        let position = currentTime
        rate = newRate
        if isPlaying { start(at: position) }
    }

    /// Stops playback and closes the recordings.
    func stop() {
        stopTimer()
        tracks.forEach { $0.player.stop() }
        tracks = []
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
        guard let clock = tracks.first?.player else { return }
        let t = min(max(0, seconds), duration)
        tracks.forEach { $0.player.pause() }
        let startAt = clock.deviceCurrentTime + 0.05
        for (player, offset) in tracks {
            player.rate = rate
            let fileTime = t - offset
            // A file that ends before this point stays silent.
            guard fileTime < player.duration else { continue }
            if fileTime >= 0 {
                player.currentTime = fileTime
                player.play(atTime: startAt)
            } else {
                player.currentTime = 0
                player.play(atTime: startAt - fileTime / Double(rate))
            }
        }
        anchorTime = t
        anchorDevice = startAt
        if !isPlaying { isPlaying = true }
        startTimer()
        sendTick()
    }

    private func tick() {
        guard isPlaying else { return }
        let t = currentTime
        if let clipEnd, t >= clipEnd {
            pause()
        } else if t >= duration {
            pause()
            anchorTime = duration
        } else {
            sendTick()
        }
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

    /// Players for a meeting's kept recordings, skipping empty files and files whose header reports no length.
    private func openTracks(for meetingID: UUID, offsets: [String: Double]?) -> [(player: AVAudioPlayer, offset: Double)] {
        let dir = root.appendingPathComponent(meetingID.uuidString, isDirectory: true)
        return [AudioSource.mic, .system].compactMap { source in
            let url = dir.appendingPathComponent("\(source.rawValue).wav")
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            guard size >= Self.minFileBytes, let player = try? AVAudioPlayer(contentsOf: url), player.duration >= 0.5 else { return nil }
            player.enableRate = true
            player.volume = 0.9
            return (player, offsets?[source.rawValue] ?? 0)
        }
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
