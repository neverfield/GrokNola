import AVFoundation
import ScreenCaptureKit

/// Captures what the other participants say by recording system audio with ScreenCaptureKit.
/// This needs the Screen & System Audio Recording permission. No video is kept.
/// With a known meeting app, only that app's audio is captured; otherwise all audio except GrokNola's.
final class SystemAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    var onPCM: ((Data) -> Void)?
    var onError: ((String) -> Void)?

    private let app: MeetingDetector.App?
    private var stream: SCStream?
    private let converter = PCM16Converter()
    private let queue = DispatchQueue(label: "groknotes.system-audio")

    init(app: MeetingDetector.App?) {
        self.app = app
    }

    /// Whether a running process is part of the meeting app: the app itself or one of its helpers, such as
    /// `com.google.Chrome.helper`, which plays a browser tab's audio.
    static func belongsToMeetingApp(bundleID: String, pid: pid_t, app: MeetingDetector.App) -> Bool {
        pid == app.pid || bundleID == app.bundleID || bundleID.hasPrefix(app.bundleID + ".")
    }

    func start() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first else {
            throw XAIError(message: "No display is available for audio capture.")
        }
        let meetingApps = app.map { app in
            content.applications.filter { Self.belongsToMeetingApp(bundleID: $0.bundleIdentifier, pid: $0.processID, app: app) }
        } ?? []
        let filter: SCContentFilter
        if !meetingApps.isEmpty {
            filter = SCContentFilter(display: display, including: meetingApps, exceptingWindows: [])
        } else {
            NSLog("GrokNotes: no meeting app found for system audio; capturing all apps except GrokNola")
            let ownApp = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
            filter = SCContentFilter(display: display, excludingApplications: ownApp, exceptingWindows: [])
        }

        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48_000
        config.channelCount = 1
        // ScreenCaptureKit always produces video. Keep it as small and slow as possible.
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() async {
        try? await stream?.stopCapture()
        stream = nil
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid,
              let buffer = sampleBuffer.makePCMBuffer(),
              let data = converter.convert(buffer)
        else { return }
        onPCM?(data)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onError?("System audio stopped: \(error.localizedDescription)")
    }
}
