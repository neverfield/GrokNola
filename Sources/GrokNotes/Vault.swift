import CryptoKit
import Foundation

/// Encrypts meeting files at rest with a key kept in the Keychain, so other apps see only ciphertext.
///
/// A sealed file sits next to where the plain file would be, as `<name>.enc`: the bytes `GNV1`, then the
/// plaintext in 1 MiB chunks, each sealed with AES-GCM. Each chunk's index and whether it is the last one
/// are authenticated, so chunks cannot be reordered, dropped, or cut off without `open` failing.
/// Readers fall back to the plain file, for meetings saved before encryption.
enum Vault {
    static let fileExtension = "enc"
    static let chunkSize = 1 << 20

    private static let magic = Data("GNV1".utf8)
    private static let keyAccount = "vault_key"
    /// AES-GCM adds a 12-byte nonce and a 16-byte tag to each chunk.
    private static let overhead = 28

    enum VaultError: LocalizedError {
        case badFormat
        case noKey

        var errorDescription: String? {
            switch self {
            case .badFormat: "The encrypted file is damaged or was sealed with a different key."
            case .noKey: "The encryption key is missing from the Keychain, so encrypted meetings cannot be opened."
            }
        }
    }

    // MARK: Key

    private final class KeyCache: @unchecked Sendable {
        let lock = NSLock()
        var key: SymmetricKey?
    }

    private static let cache = KeyCache()

    /// The key, created the first time something is sealed. Throws when the Keychain refuses it, rather than
    /// creating a new key that could not open meetings sealed with the old one. Reading never creates a key.
    static func key(create: Bool = true) throws -> SymmetricKey {
        cache.lock.lock()
        defer { cache.lock.unlock() }
        if let key = cache.key { return key }
        let key: SymmetricKey
        if let data = try Keychain.data(for: keyAccount) {
            guard data.count == 32 else { throw VaultError.badFormat }
            key = SymmetricKey(data: data)
        } else {
            guard create else { throw VaultError.noKey }
            key = SymmetricKey(size: .bits256)
            try Keychain.add(key.withUnsafeBytes { Data($0) }, for: keyAccount)
        }
        cache.key = key
        return key
    }

    // MARK: Bytes

    static func seal(_ plaintext: Data, key: SymmetricKey) throws -> Data {
        var out = magic
        out.reserveCapacity(magic.count + plaintext.count + (plaintext.count / chunkSize + 1) * overhead)
        var index: UInt64 = 0
        var start = plaintext.startIndex
        repeat {
            let end = min(start + chunkSize, plaintext.endIndex)
            out += try sealChunk(plaintext[start..<end], index: index, final: end == plaintext.endIndex, key: key)
            start = end
            index += 1
        } while start < plaintext.endIndex
        return out
    }

    static func open(_ sealed: Data, key: SymmetricKey) throws -> Data {
        guard sealed.count >= magic.count + overhead, sealed.prefix(magic.count) == magic else { throw VaultError.badFormat }
        var out = Data()
        out.reserveCapacity(sealed.count)
        var index: UInt64 = 0
        var start = sealed.startIndex + magic.count
        while start < sealed.endIndex {
            let end = min(start + chunkSize + overhead, sealed.endIndex)
            let box = try AES.GCM.SealedBox(combined: sealed[start..<end])
            out += try AES.GCM.open(box, using: key, authenticating: aad(index, final: end == sealed.endIndex))
            start = end
            index += 1
        }
        return out
    }

    static func isSealed(_ data: Data) -> Bool {
        data.prefix(magic.count) == magic
    }

    private static func sealChunk(_ chunk: Data, index: UInt64, final: Bool, key: SymmetricKey) throws -> Data {
        guard let combined = try AES.GCM.seal(chunk, using: key, authenticating: aad(index, final: final)).combined else {
            throw VaultError.badFormat
        }
        return combined
    }

    private static func aad(_ index: UInt64, final: Bool) -> Data {
        var data = withUnsafeBytes(of: index.littleEndian) { Data($0) }
        data.append(final ? 1 : 0)
        return data
    }

    // MARK: Files

    /// Where the sealed copy of `url` lives.
    static func sealedURL(_ url: URL) -> URL {
        url.appendingPathExtension(fileExtension)
    }

    /// True when `url` exists sealed or plain.
    static func exists(_ url: URL) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: sealedURL(url).path) || fm.fileExists(atPath: url.path)
    }

    /// The plain bytes of `url`, from its sealed copy when there is one.
    static func read(_ url: URL) throws -> Data {
        let sealed = sealedURL(url)
        if FileManager.default.fileExists(atPath: sealed.path) {
            return try open(Data(contentsOf: sealed, options: .mappedIfSafe), key: key(create: false))
        }
        return try Data(contentsOf: url)
    }

    /// Writes `data` sealed to `<url>.enc` and removes any plain file at `url`.
    static func write(_ data: Data, to url: URL) throws {
        try seal(data, key: key()).write(to: sealedURL(url), options: .atomic)
        try? FileManager.default.removeItem(at: url)
    }

    /// Seals the plain file at `url` in place, a chunk at a time so long recordings stay out of memory.
    /// Does nothing when there is no plain file.
    static func sealFile(at url: URL) throws {
        try sealFile(at: url, key: key())
    }

    static func sealFile(at url: URL, key: SymmetricKey) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return }
        let target = sealedURL(url)
        let temp = target.appendingPathExtension("partial")
        try? fm.removeItem(at: temp)
        fm.createFile(atPath: temp.path, contents: nil)
        do {
            let input = try FileHandle(forReadingFrom: url)
            defer { try? input.close() }
            let output = try FileHandle(forWritingTo: temp)
            defer { try? output.close() }
            try output.write(contentsOf: magic)
            var index: UInt64 = 0
            var chunk = try readChunk(input)
            while true {
                let next = chunk.count == chunkSize ? try readChunk(input) : Data()
                try output.write(contentsOf: sealChunk(chunk, index: index, final: next.isEmpty, key: key))
                if next.isEmpty { break }
                chunk = next
                index += 1
            }
            try output.synchronize()
        } catch {
            try? fm.removeItem(at: temp)
            throw error
        }
        try? fm.removeItem(at: target)
        try fm.moveItem(at: temp, to: target)
        try fm.removeItem(at: url)
    }

    /// A full chunk, or less only at the end of the file. `open` relies on every chunk but the last being full.
    private static func readChunk(_ handle: FileHandle) throws -> Data {
        var chunk = Data()
        while chunk.count < chunkSize, let more = try handle.read(upToCount: chunkSize - chunk.count), !more.isEmpty {
            chunk += more
        }
        return chunk
    }

    /// Removes `url` and its sealed copy.
    static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: sealedURL(url))
        try? FileManager.default.removeItem(at: url)
    }
}
