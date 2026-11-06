import AVFoundation
import os

/// Mixes a meeting's recordings on one meeting-time clock: a source node sums the tracks sample by sample with a gain
/// each, then time-stretch for the playback rate and a peak limiter so boosted speech cannot clip.
final class MeetingMix {
    struct Track {
        let pcm: PCMTrack
        /// Meeting seconds of the first sample.
        let offset: Double
    }

    static let format = AVAudioFormat(standardFormatWithSampleRate: PCMTrack.sampleRate, channels: 1)!

    let engine = AVAudioEngine()
    /// Meeting seconds where the last track ends.
    let duration: Double
    private let state: MixState
    private let source: AVAudioSourceNode
    private let timePitch = AVAudioUnitTimePitch()
    private let limiter = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
        componentType: kAudioUnitType_Effect,
        componentSubType: kAudioUnitSubType_PeakLimiter,
        componentManufacturer: kAudioUnitManufacturer_Apple,
        componentFlags: 0,
        componentFlagsMask: 0
    ))
    private var rate: Float = 1

    /// `offlineFrames` puts the engine in offline manual rendering, for checks that must not make a sound.
    init(tracks: [Track], offlineFrames: AVAudioFrameCount? = nil) throws {
        let state = MixState(tracks: tracks.map {
            MixState.Source(samples: $0.pcm.samples, frames: $0.pcm.frames, offset: Int(($0.offset * PCMTrack.sampleRate).rounded()))
        })
        self.state = state
        // Keeps the mapped files alive as long as the render block can read them.
        let retained = tracks.map(\.pcm)
        duration = tracks.map { $0.offset + $0.pcm.duration }.max() ?? 0
        source = AVAudioSourceNode(format: Self.format) { isSilence, _, frameCount, buffers in
            withExtendedLifetime(retained) {
                state.render(frames: Int(frameCount), into: buffers, isSilence: isSilence)
            }
            return noErr
        }
        if let offlineFrames {
            try engine.enableManualRenderingMode(.offline, format: Self.format, maximumFrameCount: offlineFrames)
        }
        engine.attach(source)
        engine.attach(timePitch)
        engine.attach(limiter)
        engine.connect(source, to: timePitch, format: Self.format)
        engine.connect(timePitch, to: limiter, format: Self.format)
        engine.connect(limiter, to: engine.mainMixerNode, format: Self.format)
        timePitch.bypass = true
        engine.prepare()
    }

    /// Meeting seconds of the audio being heard now: what has been rendered, less what is still on its way to the speakers.
    var position: Double {
        let rendered = Double(state.position) / PCMTrack.sampleRate
        return rendered - latency * Double(rate)
    }

    /// Whether rendering reached the stop point given to `play`.
    var finished: Bool { state.finished }

    /// Seconds between rendering a sample and hearing it.
    var latency: Double {
        guard !engine.isInManualRenderingMode else { return 0 }
        return engine.outputNode.presentationLatency + timePitch.auAudioUnit.latency + limiter.auAudioUnit.latency
    }

    /// Gains in dB, one per track in the order given to `init`. Minus infinity mutes a track.
    /// The render thread glides to new gains over about 50 ms, so changes during playback do not click.
    func setGains(_ dB: [Float]) {
        state.setGains(dB.map(SpeechLevel.linear))
    }

    func setRate(_ newRate: Float) {
        rate = newRate
        timePitch.rate = newRate
        timePitch.bypass = newRate == 1
    }

    /// Plays from `seconds` and goes silent at `stop`, both meeting seconds.
    func play(from seconds: Double, until stop: Double) throws {
        if engine.isRunning, !engine.isInManualRenderingMode { engine.pause() }
        state.pause()
        timePitch.reset()
        limiter.reset()
        state.play(from: Int(seconds * PCMTrack.sampleRate), until: Int(stop * PCMTrack.sampleRate))
        if !engine.isRunning { try engine.start() }
    }

    func pause() {
        state.pause()
        if engine.isRunning, !engine.isInManualRenderingMode { engine.pause() }
    }

    func stop() {
        state.pause()
        engine.stop()
    }
}

/// What the render thread shares with the player. Transport and gains sit behind a lock held for a few loads and stores;
/// the gain ramps and limiter envelope belong to the render thread alone.
private final class MixState: @unchecked Sendable {
    struct Source {
        let samples: UnsafePointer<Int16>
        let frames: Int
        /// Meeting frame of the first sample.
        let offset: Int
    }

    private struct Transport {
        var position = 0
        var stop = 0
        var playing = false
        var gains: [Float]
    }

    private static let threshold: Float = 0.89 // -1 dBFS
    private static let release: Float = exp(-1 / (0.2 * Float(PCMTrack.sampleRate)))
    private static let glide: Float = 1 - exp(-1 / (0.05 * Float(PCMTrack.sampleRate)))

    let sources: [Source]
    private let lock: OSAllocatedUnfairLock<Transport>
    private var gains: [Float]
    private var targets: [Float]
    private var envelope: Float = 0

    init(tracks: [Source]) {
        sources = tracks
        gains = Array(repeating: 1, count: tracks.count)
        targets = gains
        lock = OSAllocatedUnfairLock(initialState: Transport(gains: Array(repeating: 1, count: tracks.count)))
    }

    var position: Int { lock.withLock { $0.position } }
    var finished: Bool { lock.withLock { $0.position >= $0.stop } }

    func setGains(_ linear: [Float]) {
        lock.withLock { $0.gains = linear }
    }

    func play(from frame: Int, until stop: Int) {
        lock.withLock {
            $0.position = max(0, frame)
            $0.stop = stop
            $0.playing = true
        }
    }

    func pause() {
        lock.withLock { $0.playing = false }
    }

    func render(frames n: Int, into list: UnsafeMutablePointer<AudioBufferList>, isSilence: UnsafeMutablePointer<ObjCBool>) {
        let buffers = UnsafeMutableAudioBufferListPointer(list)
        guard let out = buffers[0].mData?.assumingMemoryBound(to: Float.self) else { return }
        let (start, count) = lock.withLock { t -> (Int, Int) in
            for i in targets.indices where i < t.gains.count { targets[i] = t.gains[i] }
            guard t.playing else { return (0, 0) }
            let count = max(0, min(n, t.stop - t.position))
            let start = t.position
            t.position += count
            return (start, count)
        }
        guard count > 0 else {
            out.update(repeating: 0, count: n)
            isSilence.pointee = true
            return
        }
        for i in 0..<n {
            var x: Float = 0
            if i < count {
                let frame = start + i
                for k in sources.indices {
                    let step = (targets[k] - gains[k]) * Self.glide
                    // Lands exactly on the target, so a muted track reaches 0 instead of decaying into denormals.
                    gains[k] = abs(step) < 1e-7 ? targets[k] : gains[k] + step
                    let j = frame - sources[k].offset
                    if j >= 0, j < sources[k].frames {
                        x += Float(sources[k].samples[j]) * (gains[k] / 32768)
                    }
                }
            }
            envelope = max(abs(x), envelope * Self.release)
            if envelope > Self.threshold { x *= Self.threshold / envelope }
            out[i] = x
        }
    }
}
