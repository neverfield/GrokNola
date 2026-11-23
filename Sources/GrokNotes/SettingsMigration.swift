import Foundation

/// Builds before com.neverfield.groknola kept settings under the old bundle ID. Copies them over once.
enum SettingsMigration {
    static let legacyDomain = "dev.local.groknotes"
    static let doneKey = "settingsMigratedFromLegacyDomain"

    static func run(defaults: UserDefaults = .standard) {
        guard Bundle.main.bundleIdentifier != legacyDomain, !defaults.bool(forKey: doneKey) else { return }
        let current = Bundle.main.bundleIdentifier.flatMap(defaults.persistentDomain(forName:)) ?? [:]
        for (key, value) in missing(legacy: defaults.persistentDomain(forName: legacyDomain) ?? [:], current: current) {
            defaults.set(value, forKey: key)
        }
        defaults.set(true, forKey: doneKey)
    }

    /// Old settings not already set in the new domain. Old settings stay in place.
    static func missing(legacy: [String: Any], current: [String: Any]) -> [String: Any] {
        legacy.filter { current[$0.key] == nil && $0.key != doneKey }
    }
}
