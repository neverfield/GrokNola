import Foundation

/// Reads the same UserDefaults keys that `SettingsView` binds with `@AppStorage`.
enum Prefs {
    static let defaultModel = "grok-4.7"
    private static var defaults: UserDefaults { .standard }

    static var myName: String { nonEmpty(defaults.string(forKey: "myName")) ?? NSFullUserName() }
    static var model: String { nonEmpty(defaults.string(forKey: "chatModel")) ?? defaultModel }
    static var language: String { defaults.string(forKey: "language") ?? "en" }
    static var echoCancellation: Bool { defaults.object(forKey: "echoCancellation") as? Bool ?? true }
    static var keepAudio: Bool { defaults.object(forKey: "keepAudio") as? Bool ?? false }
    static var inferNames: Bool { defaults.object(forKey: "inferNames") as? Bool ?? true }
    static var useSnapshots: Bool { defaults.object(forKey: "useSnapshots") as? Bool ?? true }
    static var exportToGoogleDrive: Bool { defaults.object(forKey: "exportToGoogleDrive") as? Bool ?? false }
    static var googleDriveSubfolder: String? { nonEmpty(defaults.string(forKey: "googleDriveSubfolder")) }
    static var autoTag: Bool { defaults.object(forKey: "autoTag") as? Bool ?? true }
    static var dynamicTags: Bool { defaults.object(forKey: "dynamicTags") as? Bool ?? true }
    static var defaultTemplateID: String { nonEmpty(defaults.string(forKey: "defaultTemplate")) ?? SummaryTemplate.generalID }

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
