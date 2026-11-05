import Foundation

/// Reads the same UserDefaults keys that `SettingsView` binds with `@AppStorage`.
enum Prefs {
    static let defaultModel = "grok-4.7"
    /// Models offered in Settings for notes. Any other id can be typed as a custom model.
    static let notesModels = ["grok-4.7", "grok-4.6", "grok-4.3", "grok-4.20-non-reasoning"]
    /// Models offered in Settings for live answers, fastest first.
    static let liveAnswersModels = ["grok-4.20-non-reasoning", "grok-4.3", "grok-4.7"]
    private static var defaults: UserDefaults { .standard }

    static var myName: String { nonEmpty(defaults.string(forKey: "myName")) ?? NSFullUserName() }
    static var model: String { nonEmpty(defaults.string(forKey: "chatModel")) ?? defaultModel }
    static var language: String { defaults.string(forKey: "language") ?? "en" }
    static var echoCancellation: Bool { defaults.object(forKey: "echoCancellation") as? Bool ?? true }
    static var keepAudio: Bool { defaults.object(forKey: "keepAudio") as? Bool ?? false }
    /// Days to keep audio recordings. Nil keeps them until the meeting is deleted.
    static var audioRetentionDays: Int? {
        let days = defaults.integer(forKey: "audioRetentionDays")
        return days > 0 ? days : nil
    }
    /// Playback brings the microphone and system audio to the same speech level.
    static var balanceVoices: Bool {
        get { defaults.object(forKey: "balanceVoices") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "balanceVoices") }
    }
    /// Playback gain range for "My voice" and "Others", in dB relative to the balanced level.
    static let voiceGainRange: ClosedRange<Double> = -12...12
    /// Extra playback gain for the microphone track, in dB. Older builds stored a step from -6 to +12 under this key.
    static var myVoiceGain: Double {
        get { clampVoiceGain(defaults.double(forKey: "myVoiceGain")) }
        set { defaults.set(clampVoiceGain(newValue), forKey: "myVoiceGain") }
    }
    /// Extra playback gain for the system audio track (the other participants), in dB.
    static var othersGain: Double {
        get { clampVoiceGain(defaults.double(forKey: "othersGain")) }
        set { defaults.set(clampVoiceGain(newValue), forKey: "othersGain") }
    }
    static var myVoiceMuted: Bool {
        get { defaults.bool(forKey: "myVoiceMuted") }
        set { defaults.set(newValue, forKey: "myVoiceMuted") }
    }
    static var othersMuted: Bool {
        get { defaults.bool(forKey: "othersMuted") }
        set { defaults.set(newValue, forKey: "othersMuted") }
    }
    static var inferNames: Bool { defaults.object(forKey: "inferNames") as? Bool ?? true }
    static var useSnapshots: Bool { defaults.object(forKey: "useSnapshots") as? Bool ?? true }
    static var exportToGoogleDrive: Bool { defaults.object(forKey: "exportToGoogleDrive") as? Bool ?? false }
    static var googleDriveSubfolder: String? { nonEmpty(defaults.string(forKey: "googleDriveSubfolder")) }
    static var autoTag: Bool { defaults.object(forKey: "autoTag") as? Bool ?? true }
    static var dynamicTags: Bool { defaults.object(forKey: "dynamicTags") as? Bool ?? true }
    static var defaultTemplateID: String { nonEmpty(defaults.string(forKey: "defaultTemplate")) ?? SummaryTemplate.generalID }
    /// Non-reasoning, so the first token arrives without a thinking phase.
    static let defaultLiveAnswersModel = "grok-4.20-non-reasoning"
    static var liveAnswers: Bool { defaults.object(forKey: "liveAnswers") as? Bool ?? true }
    static var liveAnswersModel: String { nonEmpty(defaults.string(forKey: "liveAnswersModel")) ?? defaultLiveAnswersModel }
    /// Empty leaves `reasoning_effort` out of the request, which non-reasoning models require.
    static var liveAnswersEffort: String { defaults.string(forKey: "liveAnswersEffort") ?? "" }
    static var liveAnswersPastMeetings: Bool { defaults.object(forKey: "liveAnswersPastMeetings") as? Bool ?? true }
    static var liveAnswersShowLatency: Bool { defaults.object(forKey: "liveAnswersShowLatency") as? Bool ?? false }
    static var liveAnswersPriority: Bool { defaults.object(forKey: "liveAnswersPriority") as? Bool ?? false }
    static var calendarSource: CalendarChoice {
        defaults.string(forKey: "calendarSource").flatMap(CalendarChoice.init(rawValue:)) ?? .automatic
    }

    /// Names confirmed in past meetings. Used as transcription key terms and naming candidates.
    static var knownPeople: [String] {
        get { defaults.stringArray(forKey: "knownPeople") ?? [] }
        set { defaults.set(Array(newValue.suffix(200)), forKey: "knownPeople") }
    }

    static func remember(_ names: [String]) {
        var people = knownPeople
        for name in names where !people.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            people.append(name)
        }
        knownPeople = people
    }

    private static func clampVoiceGain(_ dB: Double) -> Double {
        dB.isFinite ? min(max(dB, voiceGainRange.lowerBound), voiceGainRange.upperBound) : 0
    }

    private static func nonEmpty(_ s: String?) -> String? {
        guard let s = s?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        return s
    }
}

func uniqueNames(_ names: [String]) -> [String] {
    var seen = Set<String>()
    return names
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
}
