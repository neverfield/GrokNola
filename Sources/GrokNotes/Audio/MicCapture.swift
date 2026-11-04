import AVFoundation

/// Captures the local user's microphone as 16 kHz mono PCM16.
final class MicCapture {
    var onPCM: ((Data) -> Void)?
    /// False when echo cancellation was requested but the audio hardware refused it.
    private(set) var echoCancellationActive = false

    private var engine = AVAudioEngine()
    private let converter = PCM16Converter()

    static func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    /// Echo cancellation keeps remote voices that leak from the speakers out of the "Me" channel.
    /// Voice processing fails to initialize (-10875) on some device combinations, such as
    /// Bluetooth headsets or mismatched input and output sample rates. Then the plain mic is used.
    func start(echoCancellation: Bool) throws {
        if echoCancellation {
            do {
                try startEngine(voiceProcessing: true)
                echoCancellationActive = true
                return
            } catch {
                NSLog("GrokNotes: voice processing failed, using the plain microphone: \(error)")
                teardown()
                engine = AVAudioEngine()
            }
        }
        echoCancellationActive = false
        try startEngine(voiceProcessing: false)
    }

    func stop() {
        teardown()
    }

    private func startEngine(voiceProcessing: Bool) throws {
        let input = engine.inputNode
        if voiceProcessing {
            try input.setVoiceProcessingEnabled(true)
            // Voice processing ducks other audio by default, which would quiet the meeting itself.
            input.voiceProcessingOtherAudioDuckingConfiguration = .init(enableAdvancedDucking: false, duckingLevel: .min)
        }
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw XAIError(message: "No microphone input device is available.")
        }
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            guard let self, let data = self.converter.convert(buffer) else { return }
            self.onPCM?(data)
        }
        _ = engine.mainMixerNode
        engine.prepare()
        try engine.start()
    }

    private func teardown() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        if engine.inputNode.isVoiceProcessingEnabled {
            try? engine.inputNode.setVoiceProcessingEnabled(false)
        }
    }
}
