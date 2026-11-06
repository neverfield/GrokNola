import Darwin
import Foundation

/// The samples of a 16 kHz mono PCM16 WAV file, memory-mapped so long recordings stay out of RAM.
/// Immutable after init, so the audio render thread may read it.
final class PCMTrack: @unchecked Sendable {
    static let sampleRate = 16_000.0

    let url: URL
    let samples: UnsafePointer<Int16>
    let frames: Int
    let fileSize: Int
    private let mapping: UnsafeMutableRawPointer
    private let mappedBytes: Int

    var duration: Double { Double(frames) / Self.sampleRate }

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
        fileSize = size
        frames = count
        samples = UnsafePointer((raw + offset).assumingMemoryBound(to: Int16.self))
    }

    deinit {
        munmap(mapping, mappedBytes)
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
