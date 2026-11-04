import AVFoundation
import Foundation

/// Plays a short stretch of a meeting's kept recordings, with the microphone and system audio mixed in sync.
@MainActor
final class ClipPlayer: ObservableObject {
    struct NowPlaying: Equatable {
        var meetingID: UUID
        /// The time that was asked for. Asking for the same time again stops the clip.
        var anchor: Double
        /// Meeting seconds.
        var start: Double
        var end: Double
        var speakerKey: String?
    }

    static let leadIn = 1.5
    static let minLength = 8.0
    static let maxLength = 30.0
    /// A WAV header plus half a second of 16 kHz PCM16. Shorter files hold no useful audio.
    private static let minFileBytes = 44 + 16_000

    @Published private(set) var nowPlaying: NowPlaying?

    private let root: URL
    private var players: [AVAudioPlayer] = []
    private var startDeviceTime: TimeInterval = 0
    private var endTask: Task<Void, Never>?
    private var audioCache: [UUID: Bool] = [:]

    init(root: URL) {
        self.root = root
    }

    /// Seconds into the current clip.
    var elapsed: Double {
        guard let nowPlaying, let clock = players.first else { return 0 }
        return min(max(0, clock.deviceCurrentTime - startDeviceTime), nowPlaying.end - nowPlaying.start)
    }

    /// Whether the meeting has a kept recording on disk. Cached; call `invalidate` when files change.
    func hasAudio(_ meetingID: UUID) -> Bool {
        if let cached = audioCache[meetingID] { return cached }
        let found = !files(for: meetingID).isEmpty
        audioCache[meetingID] = found
        return found
    }

    func invalidate(_ meetingID: UUID? = nil) {
        if let meetingID { audioCache[meetingID] = nil } else { audioCache.removeAll() }
    }

    func isPlaying(_ meetingID: UUID, at anchor: Double) -> Bool {
        nowPlaying?.meetingID == meetingID && nowPlaying?.anchor == anchor
    }

    /// Starts the clip around `seconds`, or stops it if that clip is already playing. Returns false when there is no audio.
    @discardableResult
    func toggle(_ meeting: Meeting, at seconds: Double, until end: Double? = nil) -> Bool {
        if isPlaying(meeting.id, at: seconds) {
            stop()
            return true
        }
        return play(meeting, at: seconds, until: end)
    }

    @discardableResult
    func play(_ meeting: Meeting, at seconds: Double, until explicitEnd: Double? = nil) -> Bool {
        stop()
        let block = Self.block(containing: seconds, in: meeting.utterances)
        let start = max(0, seconds - Self.leadIn)
        let spokenEnd = (explicitEnd ?? block?.end ?? seconds) + 0.5
        let end = min(max(spokenEnd, start + Self.minLength), start + Self.maxLength)

        var loaded: [(player: AVAudioPlayer, offset: Double)] = []
        for (source, url) in files(for: meeting.id) {
            guard let player = try? AVAudioPlayer(contentsOf: url) else { continue }
            let offset = meeting.audioOffsets?[source.rawValue] ?? 0
            // Skip a file that ends before the clip starts, so it does not drive the clock.
            guard start - offset < player.duration else { continue }
            player.volume = 0.9
            player.prepareToPlay()
            loaded.append((player, offset))
        }
        guard let clock = loaded.first?.player else {
            invalidate(meeting.id)
            return false
        }

        let startAt = clock.deviceCurrentTime + 0.1
        for (player, offset) in loaded {
            let fileTime = start - offset
            if fileTime >= 0 {
                player.currentTime = fileTime
                player.play(atTime: startAt)
            } else {
                player.currentTime = 0
                player.play(atTime: startAt - fileTime)
            }
        }
        players = loaded.map(\.player)
        startDeviceTime = startAt
        nowPlaying = NowPlaying(meetingID: meeting.id, anchor: seconds, start: start, end: end, speakerKey: block?.speakerKey)

        let length = end - start
        endTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(length + 0.1))
            guard !Task.isCancelled else { return }
            self?.stop()
        }
        return true
    }

    func stop() {
        endTask?.cancel()
        endTask = nil
        players.forEach { $0.stop() }
        players = []
        if nowPlaying != nil { nowPlaying = nil }
    }

    /// Kept recordings for a meeting, skipping empty files.
    private func files(for meetingID: UUID) -> [(AudioSource, URL)] {
        let dir = root.appendingPathComponent(meetingID.uuidString, isDirectory: true)
        return [AudioSource.mic, .system].compactMap { source in
            let url = dir.appendingPathComponent("\(source.rawValue).wav")
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            return size >= Self.minFileBytes ? (source, url) : nil
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
