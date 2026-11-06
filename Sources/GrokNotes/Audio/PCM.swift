import AVFoundation
import CoreMedia

/// Converts any PCM buffer to 16 kHz mono PCM16, the native rate of the Grok STT models.
final class PCM16Converter {
    static let outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true)!

    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?

    func convert(_ buffer: AVAudioPCMBuffer) -> Data? {
        if inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: Self.outputFormat)
            converter?.downmix = true
            inputFormat = buffer.format
        }
        guard let converter, buffer.frameLength > 0 else { return nil }

        let ratio = Self.outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: Self.outputFormat, frameCapacity: capacity) else { return nil }

        var consumed = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, output.frameLength > 0, let samples = output.int16ChannelData else { return nil }
        return Data(bytes: samples[0], count: Int(output.frameLength) * 2)
    }
}

extension CMSampleBuffer {
    func makePCMBuffer() -> AVAudioPCMBuffer? {
        guard var description = formatDescription?.audioStreamBasicDescription,
              let format = AVAudioFormat(streamDescription: &description)
        else { return nil }
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(self))
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(self, at: 0, frameCount: Int32(frames), into: buffer.mutableAudioBufferList)
        return status == noErr ? buffer : nil
    }
}

/// Writes 16 kHz mono PCM16 to a WAV file for the full-recording diarization pass.
final class WAVWriter {
    let url: URL
    private let handle: FileHandle
    private let queue = DispatchQueue(label: "groknotes.wav")
    private var dataBytes: UInt32 = 0
    private var firstWrite: Double?
    private var closed = false

    init(url: URL) throws {
        self.url = url
        FileManager.default.createFile(atPath: url.path, contents: Self.header(dataBytes: 0))
        handle = try FileHandle(forWritingTo: url)
        handle.seekToEndOfFile()
    }

    /// Meeting time of the first sample in the file.
    var startOffset: Double? { queue.sync { firstWrite } }

    func write(_ data: Data, at meetingTime: Double) {
        queue.async {
            guard !self.closed else { return }
            if self.firstWrite == nil { self.firstWrite = meetingTime }
            self.handle.write(data)
            self.dataBytes += UInt32(data.count)
        }
    }

    /// Finalizes the header and returns the duration in seconds.
    @discardableResult
    func close() -> Double {
        queue.sync {
            if !closed {
                closed = true
                handle.seek(toFileOffset: 0)
                handle.write(Self.header(dataBytes: dataBytes))
                try? handle.close()
            }
            return Double(dataBytes) / 32_000
        }
    }

    private static func header(dataBytes: UInt32) -> Data {
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + dataBytes)
        d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16)
        u16(1); u16(1); u32(16_000); u32(32_000); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(dataBytes)
        return d
    }
}
