import Foundation

/// Reads the same UserDefaults keys that `SettingsView` binds with `@AppStorage`.
enum Prefs {
    static let defaultModel = "grok-4.7"
    /// The only models GrokNola uses for notes, naming, tags, and Ask Grok.
    static let notesModels = ["grok-4.7", "grok-4.6", "grok-4.3", "grok-4.20-non-reasoning"]
    private static var defaults: UserDefaults { .standard }

    static var myName: String { nonEmpty(defaults.string(forKey: "myName")) ?? NSFullUserName() }
    /// The chosen notes model. An id that is not in `notesModels`, such as one typed in an older build, means the default.
    static var model: String { allowedModel(defaults.string(forKey: "chatModel")) }

    static func allowedModel(_ id: String?) -> String {
        guard let id = nonEmpty(id), notesModels.contains(id) else { return defaultModel }
        return id
    }
    static var language: String { defaults.string(forKey: "language") ?? "en" }
    static var echoCancellation: Bool { defaults.object(forKey: "echoCancellation") as? Bool ?? true }
    static var keepAudio: Bool { defaults.object(forKey: "keepAudio") as? Bool ?? false }
    /// Post a notification offering to start notes when a meeting app starts a call.
    static var notifyOnMeetingDetected: Bool { defaults.object(forKey: "notifyOnMeetingDetected") as? Bool ?? true }
    /// Offer to stop a recording that seems to have outlived its call, and stop it if nobody answers.
    static var autoStopForgotten: Bool { defaults.object(forKey: "autoStopForgotten") as? Bool ?? true }
    /// Minutes with nobody speaking before a recording counts as forgotten.
    static var autoStopSilenceMinutes: Int {
        let minutes = defaults.integer(forKey: "autoStopSilenceMinutes")
        return minutes > 0 ? minutes : 5
    }
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
    /// Save snapshots of the call window and send them to xAI to name speakers. Off unless turned on.
    static var useSnapshots: Bool { defaults.object(forKey: "useSnapshots") as? Bool ?? false }
    /// Read the meeting app's "who is talking" labels through Accessibility. Off unless turned on.
    static var useAccessibilitySpeakers: Bool { defaults.object(forKey: "useAccessibilitySpeakers") as? Bool ?? false }
    /// Put names on speakers while recording, not only after the meeting.
    static var liveSpeakerID: Bool { defaults.object(forKey: "liveSpeakerID") as? Bool ?? true }
    /// While recording, ask Grok about snapshots for a voice that stays unnamed, at most once a minute. Off unless turned on.
    static var liveSpeakerSnapshots: Bool { defaults.object(forKey: "liveSpeakerSnapshots") as? Bool ?? false }
    /// When a recording starts, remind you to ask for consent if invitees are outside your company.
    static var consentReminder: Bool { defaults.object(forKey: "consentReminder") as? Bool ?? true }
    /// Your company's email domains, typed in Settings, such as "example.com, example.org".
    static var companyDomains: Set<String> { ConsentReminder.domains(in: defaults.string(forKey: "companyDomains")) }
    static var exportToGoogleDrive: Bool { defaults.object(forKey: "exportToGoogleDrive") as? Bool ?? false }
    static var googleDriveSubfolder: String? { nonEmpty(defaults.string(forKey: "googleDriveSubfolder")) }
    static var autoTag: Bool { defaults.object(forKey: "autoTag") as? Bool ?? true }
    static var dynamicTags: Bool { defaults.object(forKey: "dynamicTags") as? Bool ?? true }
    static var defaultTemplateID: String { nonEmpty(defaults.string(forKey: "defaultTemplate")) ?? SummaryTemplate.generalID }
    static var calendarSource: CalendarChoice {
        defaults.string(forKey: "calendarSource").flatMap(CalendarChoice.init(rawValue:)) ?? .automatic
    }

    /// Names confirmed in past meetings. Matched on this Mac only: never sent as transcription key terms or in prompts.
    static var knownPeople: [String] {
        get { defaults.stringArray(forKey: "knownPeople") ?? [] }
        set { defaults.set(Array(newValue.suffix(200)), forKey: "knownPeople") }
    }

    /// Remembers names confirmed in a meeting. Only plausible names are kept.
    static func remember(_ names: [String]) {
        var people = knownPeople.filter(SpeakerResolver.isPlausibleName)
        for name in names where SpeakerResolver.isPlausibleName(name)
            && !people.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
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
