import Foundation

/// One folder per meeting under ~/Library/Application Support/GrokNotes/Meetings:
/// `meeting.json` is the source of truth, `notes.md` is a readable export.
struct MeetingStore {
    let root: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        root = support.appendingPathComponent("GrokNotes/Meetings", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func directory(for id: UUID) -> URL {
        let dir = root.appendingPathComponent(id.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func loadAll() -> [Meeting] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let dirs = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return dirs.compactMap { dir in
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("meeting.json")) else { return nil }
            return try? decoder.decode(Meeting.self, from: data)
        }
        .sorted { $0.startedAt > $1.startedAt }
    }

    func save(_ meeting: Meeting, myName: String) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let dir = directory(for: meeting.id)
        try encoder.encode(meeting).write(to: dir.appendingPathComponent("meeting.json"), options: .atomic)
        try meeting.markdown(myName: myName).write(to: dir.appendingPathComponent("notes.md"), atomically: true, encoding: .utf8)
    }

    func delete(_ id: UUID) {
        try? FileManager.default.removeItem(at: root.appendingPathComponent(id.uuidString, isDirectory: true))
    }
}
