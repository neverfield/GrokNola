import Foundation

/// A pilot build is made with `GROKNOLA_PILOT=1 ./scripts/build-app.sh`, which writes `GNPilotBuild` into the
/// signed Info.plist. It locks these settings: no Google Drive copy, internal meetings
/// only, no call-window snapshots, no Accessibility speaker reading, and the consent confirmation on every
/// recording. `Prefs` applies the locks; Settings shows them disabled.
enum PilotBuild {
    static let infoKey = "GNPilotBuild"
    static let lockedCaption = "Set by the pilot build."

    static let isOn = isPilot(info: Bundle.main.infoDictionary, environment: ProcessInfo.processInfo.environment)

    /// True when Info.plist sets `GNPilotBuild`, or `GROKNOLA_PILOT=1` is set for `swift run`. Either can only
    /// turn the pilot locks on.
    static func isPilot(info: [String: Any]?, environment: [String: String]) -> Bool {
        (info?[infoKey] as? Bool ?? false) || environment["GROKNOLA_PILOT"] == "1"
    }
}
