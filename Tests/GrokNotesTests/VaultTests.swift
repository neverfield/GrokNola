import CryptoKit
import XCTest
@testable import GrokNotes

final class VaultTests: XCTestCase {
    private let key = SymmetricKey(size: .bits256)

    private func bytes(_ count: Int) -> Data {
        Data((0..<count).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) })
    }

    func testRoundTripsEmptySmallAndMultiChunk() throws {
        for count in [0, 1, 1000, Vault.chunkSize, Vault.chunkSize * 2 + 123] {
            let plain = bytes(count)
            let sealed = try Vault.seal(plain, key: key)
            XCTAssertTrue(Vault.isSealed(sealed))
            XCTAssertNotEqual(sealed.dropFirst(4).prefix(64), plain.prefix(64))
            XCTAssertEqual(try Vault.open(sealed, key: key), plain, "\(count) bytes")
        }
    }

    func testRejectsChangedByteWrongKeyAndCutOffFile() throws {
        let sealed = try Vault.seal(bytes(Vault.chunkSize + 500), key: key)

        var changed = sealed
        changed[changed.count / 2] ^= 0x01
        XCTAssertThrowsError(try Vault.open(changed, key: key))

        XCTAssertThrowsError(try Vault.open(sealed, key: SymmetricKey(size: .bits256)))

        let firstChunkOnly = sealed.prefix(4 + Vault.chunkSize + 28)
        XCTAssertThrowsError(try Vault.open(Data(firstChunkOnly), key: key), "a file cut at a chunk boundary must not open")
    }

    func testRejectsSwappedChunks() throws {
        let sealed = try Vault.seal(bytes(Vault.chunkSize * 3), key: key)
        let size = Vault.chunkSize + 28
        let header = sealed.prefix(4)
        let chunks = (0..<3).map { sealed.subdata(in: 4 + $0 * size..<4 + ($0 + 1) * size) }
        let swapped = header + chunks[1] + chunks[0] + chunks[2]
        XCTAssertThrowsError(try Vault.open(Data(swapped), key: key))
    }

    func testSealFileStreamsToTheSameFormatAndRemovesThePlainFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("mic.wav")
        let plain = bytes(Vault.chunkSize * 2)
        try plain.write(to: url)

        try Vault.sealFile(at: url, key: key)

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        let sealed = try Data(contentsOf: Vault.sealedURL(url))
        XCTAssertEqual(try Vault.open(sealed, key: key), plain)
        XCTAssertNoThrow(try Vault.sealFile(at: url, key: key), "sealing again with no plain file does nothing")
    }

    func testReadFallsBackToPlainFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("meeting.json")
        try Data("{}".utf8).write(to: url)
        XCTAssertTrue(Vault.exists(url))
        XCTAssertEqual(try Vault.read(url), Data("{}".utf8))
    }

    func testNotesMarkdownLeavesOutTheTranscript() {
        var meeting = Meeting(title: "Pricing call", autoTitle: false, startedAt: Date(timeIntervalSince1970: 0))
        meeting.utterances = [Utterance(source: .system, speakerKey: "r0", start: 3, end: 5, text: "Forty dollars per seat")]
        meeting.enhancedNotes = "## Decisions\n- Price is set"
        let notes = meeting.notesMarkdown(myName: "Me")
        XCTAssertTrue(notes.contains("Price is set"))
        XCTAssertFalse(notes.contains("## Transcript"))
        XCTAssertFalse(notes.contains("Forty dollars per seat"))
        XCTAssertTrue(meeting.markdown(myName: "Me").contains("Forty dollars per seat"))
    }
}
