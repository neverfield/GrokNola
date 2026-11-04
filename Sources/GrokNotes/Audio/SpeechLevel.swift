import Accelerate
import Foundation

/// How loud speech is in a recording, and the playback gains that bring the microphone and system audio to the same level.
enum SpeechLevel {
    /// Speech level both tracks are brought to, in dBFS.
    static let target: Float = -20
    static let maxBoost: Float = 18
    static let maxCut: Float = -12
    /// The louder track is turned down until the quieter one is within this many dB, when boosting alone cannot get there.
    static let allowedGap: Float = 3

    private static let window = 800 // 50 ms
    /// Windows quieter than this are pauses or noise, not speech.
    private static let gate: Float = -55
    private static let minSpeechWindows = 40 // 2 s

    /// The speech level of a track in dBFS: the power mean of the louder half of the 50 ms windows inside `spans`
    /// (file seconds where the transcript has this track speaking). Without enough transcribed speech it uses
    /// every window above a noise gate. Nil when the track holds too little speech to tell.
    static func measure(_ track: PCMTrack, spans: [(start: Double, end: Double)]) -> Float? {
        var scratch = [Float](repeating: 0, count: window)
        func power(at frame: Int) -> Float {
            var meanSquare: Float = 0
            scratch.withUnsafeMutableBufferPointer { buf in
                vDSP_vflt16(track.samples + frame, 1, buf.baseAddress!, 1, vDSP_Length(window))
                vDSP_measqv(buf.baseAddress!, 1, &meanSquare, vDSP_Length(window))
            }
            return meanSquare / (32768 * 32768)
        }
        let last = track.frames - window

        var spoken: [Float] = []
        for span in spans {
            var frame = max(0, Int(span.start * PCMTrack.sampleRate))
            let end = min(last, Int(span.end * PCMTrack.sampleRate))
            while frame <= end {
                spoken.append(power(at: frame))
                frame += window
            }
        }
        if spoken.count >= minSpeechWindows, let level = louderHalf(spoken) { return level }

        let floor = powerRatio(gate)
        var loud: [Float] = []
        var frame = 0
        while frame <= last {
            let p = power(at: frame)
            if p > floor { loud.append(p) }
            frame += window
        }
        return loud.count >= minSpeechWindows ? louderHalf(loud) : nil
    }

    /// Playback gains in dB for the microphone and system audio.
    /// With balancing on, each measured track moves toward `target` within `maxCut`...`maxBoost`.
    /// `myVoice` is added to the microphone and `others` to system audio either way.
    static func gains(mic: Float?, system: Float?, balance: Bool, myVoice: Float, others: Float = 0) -> (mic: Float, system: Float) {
        var m: Float = 0
        var s: Float = 0
        if balance {
            if let mic { m = clamp(target - mic) }
            if let system { s = clamp(target - system) }
            if let mic, let system {
                let gap = (system + s) - (mic + m)
                if gap > allowedGap { s = max(maxCut, s - (gap - allowedGap)) }
                if gap < -allowedGap { m = max(maxCut, m - (-gap - allowedGap)) }
            }
        }
        return (m + myVoice, s + others)
    }

    /// Minus infinity is silence.
    static func linear(_ dB: Float) -> Float { pow(10, dB / 20) }

    private static func clamp(_ dB: Float) -> Float { min(max(dB, maxCut), maxBoost) }

    private static func powerRatio(_ dB: Float) -> Float { pow(10, dB / 10) }

    private static func louderHalf(_ powers: [Float]) -> Float? {
        let top = powers.sorted().suffix(max(1, powers.count / 2))
        let mean = top.reduce(0, +) / Float(top.count)
        return mean > 0 ? 10 * log10(mean) : nil
    }
}
