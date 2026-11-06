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
    private var window: SCWindow?
    private var windowCheckedAt = Date.distantPast
    private var loop: Task<Void, Never>?

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
                if self.speech.isRecent(1.5) { await self.capture() }
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
        let time = Date().timeIntervalSince(start)
        let url = directory.appendingPathComponent(String(format: "%08.1f.jpg", time))
        do {
            try jpeg.write(to: url)
            frames.append(Frame(time: time, url: url))
        } catch {
            NSLog("GrokNotes: could not save snapshot: \(error)")
        }
    }

    /// The call window: a titled call window first ("Zoom Meeting", "Huddle", "Meet - "), else the largest window.
    /// Rechecked every 30 seconds so a call that starts after recording is still found.
    private func meetingWindow() async -> SCWindow? {
        if let window, Date().timeIntervalSince(windowCheckedAt) < 30 { return window }
        windowCheckedAt = Date()
        if app == nil { app = MeetingDetector.detect(micInUse: true) }
        guard let app,
              let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        else {
            window = nil
            return nil
        }
        let windows = content.windows.filter {
            $0.owningApplication?.processID == app.pid && $0.frame.width >= 320 && $0.frame.height >= 240
        }
        let callHints = ["Zoom Meeting", "Zoom Webinar", "Huddle", "Meet - ", "Google Meet", "Meeting", "Call"]
        let titled = windows.filter { w in callHints.contains { (w.title ?? "").localizedCaseInsensitiveContains($0) } }
        let pool = app.isBrowser ? titled : (titled.isEmpty ? windows : titled)
        window = pool.max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
        return window
    }
}
