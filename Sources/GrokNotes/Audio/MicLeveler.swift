import Foundation

/// Slow automatic gain for 16 kHz mono PCM16 microphone audio. With voice processing on, speech often arrives
/// 20 dB or more below system audio, which makes the transcript and playback of "Me" quiet.
/// Gain only boosts, by up to 12 dB, rising 3 dB a second while the user talks. The target is the average of speech
/// chunks, which reads about 4 dB under the louder-half level playback measures, so it lands near -20 dBFS there.
/// It drops at once when a chunk would peak above -1 dBFS, and a soft knee above -3 dBFS catches the rest.
final class MicLeveler {
    private static let target: Float = -24
    private static let maxGain: Float = 12
    private static let risePerSecond: Float = 3
    private static let ceiling: Float = -1
    /// Seconds of speech needed before the first boost.
    private static let warmUp: Double = 1
    private static let knee: Float = 0.7

    private var gain: Float = 0
    private var speechLevel: Float?
    private var noiseFloor: Float = -60
    private var heardSpeech: Double = 0

    func process(_ data: Data) -> Data {
        let count = data.count / 2
        guard count > 0 else { return data }
        var samples = [Int16](repeating: 0, count: count)
        _ = samples.withUnsafeMutableBytes { data.copyBytes(to: $0) }

        var sum: Float = 0
        var peak: Float = 0
        for s in samples {
            let v = Float(s) / 32768
            sum += v * v
            peak = max(peak, abs(v))
        }
        let seconds = Double(count) / 16_000
        let level = Self.decibels(sqrt(sum / Float(count)))
        let peakLevel = Self.decibels(peak)

        noiseFloor = level < noiseFloor ? level : noiseFloor + Float(seconds)
        if level > -60, level > noiseFloor + 10 {
            heardSpeech += seconds
            let weight = Float(min(1, seconds / 3))
            speechLevel = speechLevel.map { $0 + (level - $0) * weight } ?? level
        }

        var desired: Float = 0
        if let speechLevel, heardSpeech >= Self.warmUp {
            desired = min(max(Self.target - speechLevel, 0), Self.maxGain)
        }
        desired = min(desired, max(0, Self.ceiling - peakLevel))
        let previous = gain
        gain = desired < gain ? desired : min(desired, gain + Self.risePerSecond * Float(seconds))
        guard previous > 0.01 || gain > 0.01 else { return data }

        let from = Self.linear(previous)
        let step = (Self.linear(gain) - from) / Float(count)
        for i in samples.indices {
            var y = Float(samples[i]) / 32768 * (from + step * Float(i))
            let a = abs(y)
            if a > Self.knee {
                y = (y < 0 ? -1 : 1) * (Self.knee + (1 - Self.knee) * tanh((a - Self.knee) / (1 - Self.knee)))
            }
            samples[i] = Int16(max(-32768, min(32767, (y * 32767).rounded())))
        }
        return samples.withUnsafeBytes { Data($0) }
    }

    private static func decibels(_ amplitude: Float) -> Float { amplitude > 0 ? 20 * log10(amplitude) : -120 }

    private static func linear(_ dB: Float) -> Float { pow(10, dB / 20) }
}
