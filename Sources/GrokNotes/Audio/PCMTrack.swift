import Darwin
import Foundation

/// The samples of a 16 kHz mono PCM16 WAV file. A plain file is memory-mapped so long recordings stay out of RAM;
/// a file sealed by `Vault` is decrypted into memory. Immutable after init, so the audio render thread may read it.
final class PCMTrack: @unchecked Sendable {
    static let sampleRate = 16_000.0

    let url: URL
    let samples: UnsafePointer<Int16>
    let frames: Int
    let fileSize: Int
    private let mapping: UnsafeMutableRawPointer
    private let mappedBytes: Int
    /// False when `mapping` is a heap buffer holding decrypted bytes.
    private let mapped: Bool

    var duration: Double { Double(frames) / Self.sampleRate }

    /// The recording at `url`, from its sealed copy when there is one.
    static func load(_ url: URL) -> PCMTrack? {
        let sealed = Vault.sealedURL(url)
        guard FileManager.default.fileExists(atPath: sealed.path) else { return PCMTrack(url: url) }
        do {
            return PCMTrack(data: try Vault.read(url), url: url)
        } catch {
            NSLog("GrokNotes: could not open \(sealed.lastPathComponent): \(error.localizedDescription)")
            return nil
        }
    }

    /// Whether `url` likely holds at least `seconds` of audio, sealed or plain, without reading the samples.
    static func exists(_ url: URL, minDuration seconds: Double) -> Bool {
        let fm = FileManager.default
        let minBytes = 44 + Int(seconds * sampleRate) * 2
        for (candidate, extra) in [(Vault.sealedURL(url), 32), (url, 0)] {
            if let size = (try? fm.attributesOfItem(atPath: candidate.path))?[.size] as? Int, size >= minBytes + extra {
                return true
            }
        }
        return false
    }

    /// A WAV decrypted into memory. Nil when the bytes are not 16 kHz mono PCM16 or hold no samples.
    init?(data: Data, url: URL) {
        guard data.count > 44 else { return nil }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: data.count, alignment: MemoryLayout<Int16>.alignment)
        data.copyBytes(to: raw.assumingMemoryBound(to: UInt8.self), count: data.count)
        guard let (offset, count) = Self.dataChunk(UnsafeRawBufferPointer(start: raw, count: data.count)) else {
            raw.deallocate()
            return nil
        }
        self.url = url
        mapping = raw
        mappedBytes = data.count
        mapped = false
        fileSize = data.count
        frames = count
        samples = UnsafePointer((raw + offset).assumingMemoryBound(to: Int16.self))
    }

    /// Nil when the file is missing, not 16 kHz mono PCM16, or holds no samples.
    /// A header that reports no length, as after a crash, falls back to the bytes on disk.
    init?(url: URL) {
        let fd = open(url.path, O_RDONLY)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_size > 44 else { return nil }
        let size = Int(info.st_size)
        guard let raw = mmap(nil, size, PROT_READ, MAP_PRIVATE, fd, 0), raw != MAP_FAILED else { return nil }
        guard let (offset, count) = Self.dataChunk(UnsafeRawBufferPointer(start: raw, count: size)) else {
            munmap(raw, size)
            return nil
        }
        self.url = url
        mapping = raw
        mappedBytes = size
        mapped = true
        fileSize = size
        frames = count
        samples = UnsafePointer((raw + offset).assumingMemoryBound(to: Int16.self))
    }

    deinit {
        if mapped { munmap(mapping, mappedBytes) } else { mapping.deallocate() }
    }

    /// The byte offset and frame count of the sample data, after checking the format.
    private static func dataChunk(_ bytes: UnsafeRawBufferPointer) -> (Int, Int)? {
        func u32(_ at: Int) -> Int { Int(bytes.loadUnaligned(fromByteOffset: at, as: UInt32.self).littleEndian) }
        func u16(_ at: Int) -> Int { Int(bytes.loadUnaligned(fromByteOffset: at, as: UInt16.self).littleEndian) }
        func tag(_ at: Int) -> String { String(decoding: bytes[at..<at + 4], as: UTF8.self) }
        guard tag(0) == "RIFF", tag(8) == "WAVE" else { return nil }
        var at = 12
        var formatOK = false
        while at + 8 <= bytes.count {
            let size = u32(at + 4)
            switch tag(at) {
            case "fmt ":
                guard at + 24 <= bytes.count else { return nil }
                formatOK = u16(at + 8) == 1 && u16(at + 10) == 1 && u32(at + 12) == Int(sampleRate) && u16(at + 22) == 16
            case "data":
                guard formatOK else { return nil }
                let available = bytes.count - (at + 8)
                let length = size > 0 && size <= available ? size : available
                let frames = length / 2
                return frames > 0 ? (at + 8, frames) : nil
            default:
                break
            }
            at += 8 + size + (size & 1)
        }
        return nil
    }
}
