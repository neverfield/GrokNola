import AppKit
import ScreenCaptureKit

/// Thread-safe "was a remote participant talking just now?" flag, set from the audio thread.
final class SpeechActivity {
    private let lock = NSLock()
    private var last = Date.distantPast

    func mark() { lock.withLock { last = Date() } }
    func isRecent(_ seconds: TimeInterval) -> Bool { lock.withLock { Date().timeIntervalSince(last) < seconds } }

    /// Root-mean-square level of 16-bit PCM, from 0 to 32767.
    static func level(_ pcm: Data) -> Double {
        pcm.withUnsafeBytes { raw in
            let samples = raw.bindMemory(to: Int16.self)
            guard !samples.isEmpty else { return 0 }
            var sum = 0.0
            var count = 0
            for i in stride(from: 0, to: samples.count, by: 4) {
                let v = Double(samples[i])
                sum += v * v
                count += 1
            }
            return (sum / Double(count)).squareRoot()
        }
    }
}

/// Saves a snapshot of the meeting window every few seconds while remote participants talk.
/// After the meeting, Grok reads the active-speaker highlight and name tiles from these frames.
@MainActor
final class WindowSnapshotter {
    struct Frame {
        let time: Double
        let url: URL
    }

    private static let interval: Duration = .seconds(4)
    private static let maxWidth = 1600.0

    private(set) var frames: [Frame] = []
    private(set) var app: MeetingDetector.App?
    private let directory: URL
    private let start: Date
    private let speech: SpeechActivity
    private var detectedAt = Date.distantPast
    private var loop: Task<Void, Never>?
    /// While the recording is paused, no snapshot is taken or saved.
    var paused = false

    init(directory: URL, start: Date, app: MeetingDetector.App?, speech: SpeechActivity) {
        self.directory = directory
        self.start = start
        self.app = app
        self.speech = speech
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func begin() {
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.interval)
                guard let self, !Task.isCancelled else { return }
                if !self.paused, self.speech.isRecent(1.5) { await self.capture() }
            }
        }
    }

    func end() {
        loop?.cancel()
        loop = nil
    }

    func deleteFrames() {
        try? FileManager.default.removeItem(at: directory)
        frames = []
    }

    private func capture() async {
        guard let window = await meetingWindow() else { return }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        let scale = min(2, Self.maxWidth / max(window.frame.width, 1))
        config.width = Int(window.frame.width * scale)
        config.height = Int(window.frame.height * scale)
        config.showsCursor = false
        guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config),
              let jpeg = NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: 0.7])
        else { return }
        // The capture may have started before a pause.
        guard !paused else { return }
        let time = Date().timeIntervalSince(start)
        let url = directory.appendingPathComponent(String(format: "%08.1f.jpg", time))
        do {
            try Vault.write(jpeg, to: url)
            frames.append(Frame(time: time, url: url))
        } catch {
            NSLog("GrokNotes: could not save snapshot: \(error)")
        }
    }

    /// The largest window of the meeting app whose title marks it as the call ("Zoom Meeting", "Huddle", "Meet - "),
    /// read fresh on every capture so a window that stops being the call is not captured. Apps without a known
    /// call-window title, such as Teams, are never captured.
    private func meetingWindow() async -> SCWindow? {
        if app == nil, Date().timeIntervalSince(detectedAt) >= 30 {
            detectedAt = Date()
            app = MeetingDetector.detect(micInUse: false)
        }
        guard let app,
              let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        else { return nil }
        let windows = content.windows.filter { w in
            w.owningApplication?.processID == app.pid && w.frame.width >= 320 && w.frame.height >= 240
                && Self.isCallWindow(title: w.title, app: app)
        }
        return windows.max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
    }

    /// Only a window titled as the app's call is captured.
    nonisolated static func isCallWindow(title: String?, app: MeetingDetector.App) -> Bool {
        guard let title, !title.isEmpty else { return false }
        return MeetingDetector.isCallWindowTitle(title, bundleID: app.bundleID, isBrowser: app.isBrowser) == true
    }
}
