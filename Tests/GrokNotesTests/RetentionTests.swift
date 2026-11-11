import XCTest
@testable import GrokNotes

final class RetentionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func meeting(daysAgo: Double, title: String = "T") -> Meeting {
        Meeting(title: title, autoTitle: false, startedAt: now.addingTimeInterval(-daysAgo * 86_400))
    }

    private func temp() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("gn-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testExpiredByStartDate() {
        let old = meeting(daysAgo: 31), recent = meeting(daysAgo: 29)
        XCTAssertEqual(Retention.expired([old, recent], days: 30, legalHold: false, now: now), [old.id])
    }

    func testNothingExpiresWithoutRetentionOrUnderHold() {
        let old = meeting(daysAgo: 400)
        XCTAssertEqual(Retention.expired([old], days: nil, legalHold: false, now: now), [])
        XCTAssertEqual(Retention.expired([old], days: 30, legalHold: true, now: now), [])
    }

    @MainActor
    func testTrashPurgeIsSuspendedUnderHold() throws {
        let root = try temp()
        let trash = MeetingTrash(root: root)
        let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try ISO8601DateFormatter().string(from: now.addingTimeInterval(-60 * 86_400))
            .write(to: folder.appendingPathComponent(".trashed-at"), atomically: true, encoding: .utf8)
        trash.purge(now: now, legalHold: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))
        trash.purge(now: now, legalHold: false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }

    func testSHA256OfKnownBytes() throws {
        let file = try temp().appendingPathComponent("abc.txt")
        try Data("abc".utf8).write(to: file)
        XCTAssertEqual(try LegalExport.sha256(of: file), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testLegalExportWritesFilesAndManifest() throws {
        let store = MeetingStore(root: try temp())
        let trashStore = MeetingStore(root: try temp())
        let parent = try temp()
        var live = meeting(daysAgo: 1, title: "Planning")
        live.utterances = [Utterance(source: .mic, speakerKey: Meeting.meKey, start: 1, end: 2, text: "Hello")]
        let trashed = meeting(daysAgo: 2, title: "Old")
        let folder = try LegalExport.run(
            [.init(store: store, meetings: [live], inTrash: false), .init(store: trashStore, meetings: [trashed], inTrash: true)],
            myName: "Ana", legalHold: true, to: parent, now: now
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(LegalExport.Manifest.self, from: Data(contentsOf: folder.appendingPathComponent(LegalExport.manifestFile)))
        XCTAssertTrue(manifest.legalHold)
        XCTAssertEqual(manifest.meetings.map(\.id), [live.id, trashed.id])
        XCTAssertEqual(manifest.meetings.map(\.inTrash), [false, true])
        let entry = manifest.meetings[0]
        XCTAssertEqual(entry.files.map(\.name), [MeetingStore.meetingFile, MeetingStore.notesFile, MeetingStore.transcriptFile])
        for file in entry.files {
            let url = folder.appendingPathComponent(entry.folder).appendingPathComponent(file.name)
            XCTAssertEqual(try LegalExport.sha256(of: url), file.sha256)
            XCTAssertGreaterThan(file.bytes, 0)
        }
        let transcript = try String(contentsOf: folder.appendingPathComponent(entry.folder).appendingPathComponent(MeetingStore.transcriptFile), encoding: .utf8)
        XCTAssertTrue(transcript.contains("Ana: Hello"))
    }
}
