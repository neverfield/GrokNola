import AppKit
import CoreAudio

enum MeetingDetector {
    struct App: Equatable {
        let bundleID: String
        let name: String
        let pid: pid_t
        let isBrowser: Bool
    }

    private static let nativeApps: [String: String] = [
        "us.zoom.xos": "Zoom",
        "com.microsoft.teams2": "Microsoft Teams",
        "com.microsoft.teams": "Microsoft Teams",
        "com.tinyspeck.slackmacgap": "Slack",
        "Cisco-Systems.Spark": "Webex",
        "com.cisco.webexmeetingsapp": "Webex",
        "com.apple.FaceTime": "FaceTime",
    ]

    private static let browsers: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.apple.Safari", "company.thebrowser.Browser",
        "com.microsoft.edgemac", "com.brave.Browser", "org.mozilla.firefox", "com.vivaldi.Vivaldi",
    ]

    /// True when any process, not only this app, is reading from the default input device.
    static func micInUse() -> Bool {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr else {
            return false
        }
        var running: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        address.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running) == noErr else { return false }
        return running != 0
    }

    /// Window titles that show an app is in a call, not just open in the background.
    private static let callWindowHints: [String: [String]] = [
        "us.zoom.xos": ["Zoom Meeting", "Zoom Webinar"],
        "com.tinyspeck.slackmacgap": ["Huddle"],
    ]

    /// Whether the app's call window can be told apart by its title: Google Meet tabs, Zoom, and Slack huddles.
    static func knowsCallWindowTitle(bundleID: String, isBrowser: Bool) -> Bool {
        isBrowser || callWindowHints[bundleID] != nil
    }

    /// Whether a window title is the app's call window. Nil for an app whose call window has no known title.
    static func isCallWindowTitle(_ title: String, bundleID: String, isBrowser: Bool) -> Bool? {
        if isBrowser { return isMeetTitle(title) }
        guard let hints = callWindowHints[bundleID] else { return nil }
        return hints.contains { title.localizedCaseInsensitiveContains($0) }
    }

    private static func isMeetTitle(_ title: String) -> Bool {
        title.hasPrefix("Meet - ") || title.localizedCaseInsensitiveContains("Google Meet")
    }

    /// Returns the app that is in a call right now, or nil.
    /// Pass `micInUse` from before this app opens the microphone.
    /// With readable window titles, Zoom and Slack need a call window. Otherwise an app
    /// counts only while another process is using the microphone.
    /// Preference: frontmost, then Zoom/Teams/Webex, then a Meet tab, then Slack.
    static func detect(micInUse: Bool) -> App? {
        let titles = windowTitlesByPID()
        let canReadTitles = CGPreflightScreenCaptureAccess()
        var candidates: [App] = []
        for app in NSWorkspace.shared.runningApplications {
            guard let id = app.bundleIdentifier else { continue }
            let pid = app.processIdentifier
            if let name = nativeApps[id] {
                let inCall: Bool
                if canReadTitles, callWindowHints[id] != nil {
                    inCall = (titles[pid] ?? []).contains { isCallWindowTitle($0, bundleID: id, isBrowser: false) == true }
                } else {
                    inCall = micInUse
                }
                if inCall { candidates.append(App(bundleID: id, name: name, pid: pid, isBrowser: false)) }
            } else if browsers.contains(id) || id.hasPrefix("com.google.Chrome.app."),
                      (titles[pid] ?? []).contains(where: isMeetTitle) {
                candidates.append(App(bundleID: id, name: "Google Meet", pid: pid, isBrowser: true))
            }
        }
        if let front = NSWorkspace.shared.frontmostApplication,
           let match = candidates.first(where: { $0.pid == front.processIdentifier }) {
            return match
        }
        let slack = "com.tinyspeck.slackmacgap"
        return candidates.first { !$0.isBrowser && $0.bundleID != slack }
            ?? candidates.first { $0.isBrowser }
            ?? candidates.first
    }

    /// Whether `app` still has its call open, for noticing a recording left running after the call.
    /// False once the app quits. Nil when it cannot tell: no Screen Recording permission, or an app such as
    /// Teams whose call window has no known title, since the microphone is always in use while recording.
    static func callWindowOpen(for app: App) -> Bool? {
        guard let running = NSRunningApplication(processIdentifier: app.pid), !running.isTerminated else { return false }
        guard CGPreflightScreenCaptureAccess() else { return nil }
        let titles = windowTitlesByPID()[app.pid] ?? []
        guard knowsCallWindowTitle(bundleID: app.bundleID, isBrowser: app.isBrowser) else { return nil }
        return titles.contains { isCallWindowTitle($0, bundleID: app.bundleID, isBrowser: app.isBrowser) == true }
    }

    /// Window titles are only visible with the Screen Recording permission.
    private static func windowTitlesByPID() -> [pid_t: [String]] {
        guard let windows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return [:]
        }
        var titles: [pid_t: [String]] = [:]
        for window in windows {
            guard let name = window[kCGWindowName as String] as? String, !name.isEmpty,
                  let pid = window[kCGWindowOwnerPID as String] as? pid_t
            else { continue }
            titles[pid, default: []].append(name)
        }
        return titles
    }
}
