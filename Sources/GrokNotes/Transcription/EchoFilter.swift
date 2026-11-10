import Foundation

/// Finds microphone lines that only repeat call audio the speakers played back into the microphone.
/// Used when echo cancellation is unavailable. System audio is the far-end signal, so a microphone line
/// whose words, in order, are mostly in call-audio lines around the same time is the call heard twice.
///
/// A line counts as echo when, of its normalized words, the share that appear in order in the call-audio
/// words within `window` seconds of it (a longest common subsequence) reaches the threshold:
/// - 6 or more words: at least 70%, so a line that adds a few of your own words to an echo is still dropped,
///   but a reply that only quotes part of what was said is kept.
/// - 3 to 5 words: at least 80%, in practice all of them or all but one.
/// - 1 or 2 words, such as "yeah" or "okay": only when one call-audio line has exactly the same words and
///   starts within `shortStartGap` seconds, so two people saying "yeah" a few seconds apart both stay.
enum EchoFilter {
    /// Seconds around a microphone line to look for the call audio it may repeat. Covers acoustic delay and
    /// the different segment boundaries of the two transcription streams.
    static let window: Double = 2
    static let longThreshold = 0.7
    static let mediumThreshold = 0.8
    static let shortStartGap: Double = 1

    /// The IDs of microphone utterances that repeat overlapping system utterances.
    static func echoIDs(in utterances: [Utterance]) -> Set<UUID> {
        let system = utterances.filter { $0.source == .system }.sorted { $0.start < $1.start }
        guard !system.isEmpty else { return [] }
        return Set(utterances.filter { $0.source == .mic && isEcho($0, system: system) }.map(\.id))
    }

    /// True when `mic` repeats the call audio in `system` around the same time.
    static func isEcho(_ mic: Utterance, system: [Utterance]) -> Bool {
        let words = normalizedWords(mic.text)
        guard !words.isEmpty else { return false }
        let nearby = system.filter {
            $0.source == .system && $0.end >= mic.start - window && $0.start <= mic.end + window
        }.sorted { $0.start < $1.start }
        guard !nearby.isEmpty else { return false }
        if words.count <= 2 {
            return nearby.contains { abs($0.start - mic.start) <= shortStartGap && normalizedWords($0.text) == words }
        }
        return coverage(of: words, in: nearby.flatMap { normalizedWords($0.text) }) >= threshold(words.count)
    }

    /// True when interim microphone text repeats `reference`, recent call-audio text. Short text is never echo,
    /// because without timing a lone "yeah" says nothing.
    static func isEchoText(_ text: String, of reference: String) -> Bool {
        let words = normalizedWords(text)
        guard words.count >= 3 else { return false }
        return coverage(of: words, in: normalizedWords(reference)) >= threshold(words.count)
    }

    static func threshold(_ wordCount: Int) -> Double {
        wordCount >= 6 ? longThreshold : mediumThreshold
    }

    /// Lowercased words with punctuation removed, so "Yeah, sure." and "yeah sure" match.
    static func normalizedWords(_ text: String) -> [String] {
        text.lowercased()
            .split { !($0.isLetter || $0.isNumber || $0 == "'") }
            .map { $0.replacingOccurrences(of: "'", with: "") }
            .filter { !$0.isEmpty }
    }

    /// The share of `words` that appear in `reference` in the same order.
    static func coverage(of words: [String], in reference: [String]) -> Double {
        guard !words.isEmpty, !reference.isEmpty else { return 0 }
        var previous = [Int](repeating: 0, count: reference.count + 1)
        var current = previous
        for word in words {
            for j in 1...reference.count {
                current[j] = word == reference[j - 1] ? previous[j - 1] + 1 : max(previous[j], current[j - 1])
            }
            swap(&previous, &current)
        }
        return Double(previous[reference.count]) / Double(words.count)
    }
}
