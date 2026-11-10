import AVFoundation

/// Captures the local user's microphone as 16 kHz mono PCM16.
final class MicCapture {
    var onPCM: ((Data) -> Void)?
    /// Called on the main queue when echo cancellation started but delivered no audio, after the plain
    /// microphone took over.
    var onEchoCancellationLost: (() -> Void)?
    /// False when echo cancellation was requested but the audio hardware refused it.
    private(set) var echoCancellationActive = false

    private var engine = AVAudioEngine()
    private let converter = PCM16Converter()
    private let leveler = MicLeveler()
    private let buffers = BufferCounter()
    private var stopped = false

    /// Seconds echo cancellation may run without delivering audio before the plain microphone replaces it.
    private static let firstBufferTimeout: TimeInterval = 3

    static func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    /// How the engine's output side is matched to the voice-processed input.
    private enum OutputMatch: CaseIterable {
        /// The input's sample rate with the output device's channel count.
        case inputRate
        /// The input's sample rate and channel count.
        case inputFormat
    }

    /// Echo cancellation keeps remote voices that leak from the speakers out of the "Me" channel.
    /// Voice processing joins the default input and output into one unit, which fails to initialize (-10875,
    /// "client-side input and output formats do not match") when the engine's output side runs at the output
    /// device's rate, such as 48 kHz on a display's speakers, while voice processing gives the input 44.1 kHz.
    /// So the output side is set to the input's rate. When it still fails, the plain mic is used.
    func start(echoCancellation: Bool) throws {
        stopped = false
        if echoCancellation {
            for match in OutputMatch.allCases {
                do {
                    try startEngine(voiceProcessing: true, match: match)
                    echoCancellationActive = true
                    watchFirstBuffer()
                    return
                } catch {
                    NSLog("GrokNotes: voice processing failed (\(match)): \(error)")
                    reset()
                }
            }
        }
        echoCancellationActive = false
        try startEngine(voiceProcessing: false, match: .inputRate)
    }

    func stop() {
        stopped = true
        teardown()
    }

    private func startEngine(voiceProcessing: Bool, match: OutputMatch) throws {
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
        if voiceProcessing {
            let deviceChannels = engine.outputNode.outputFormat(forBus: 0).channelCount
            let channels = match == .inputRate ? deviceChannels : format.channelCount
            guard let outputFormat = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: min(max(channels, 1), 2)) else {
                throw XAIError(message: "No output format matches the microphone at \(format.sampleRate) Hz.")
            }
            engine.connect(engine.mainMixerNode, to: engine.outputNode, format: outputFormat)
        } else {
            _ = engine.mainMixerNode
        }
        buffers.reset()
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.buffers.increment()
            guard let data = self.converter.convert(buffer) else { return }
            self.onPCM?(self.leveler.process(data))
        }
        engine.prepare()
        try engine.start()
    }

    /// Voice processing can start and then deliver nothing, which would leave "Me" silent for the whole call.
    private func watchFirstBuffer() {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.firstBufferTimeout) { [weak self] in
            guard let self, !self.stopped, self.echoCancellationActive, self.buffers.count == 0 else { return }
            NSLog("GrokNotes: voice processing delivered no audio, using the plain microphone")
            self.reset()
            self.echoCancellationActive = false
            do {
                try self.startEngine(voiceProcessing: false, match: .inputRate)
            } catch {
                NSLog("GrokNotes: the plain microphone failed to start: \(error)")
            }
            self.onEchoCancellationLost?()
        }
    }

    private func reset() {
        teardown()
        engine = AVAudioEngine()
    }

    private func teardown() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        if engine.inputNode.isVoiceProcessingEnabled {
            try? engine.inputNode.setVoiceProcessingEnabled(false)
        }
    }
}

/// Counts tap buffers across the audio thread and the main queue.
private final class BufferCounter {
    private let lock = NSLock()
    private var value = 0

    var count: Int { lock.withLock { value } }
    func increment() { lock.withLock { value += 1 } }
    func reset() { lock.withLock { value = 0 } }
}
