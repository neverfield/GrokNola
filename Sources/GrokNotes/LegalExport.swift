import CryptoKit
import Foundation

/// Which meetings the text retention removes.
enum Retention {
    /// Meetings that started more than `days` before `now`. None under legal hold or without a retention.
    static func expired(_ meetings: [Meeting], days: Int?, legalHold: Bool, now: Date = Date()) -> [UUID] {
        guard !legalHold, let days, days > 0 else { return [] }
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        return meetings.filter { $0.startedAt < cutoff }.map(\.id)
    }
}

/// Writes plain copies of every meeting, including those in the trash, with a manifest of SHA-256 hashes,
/// for a legal request. Each meeting gets the folder the per-meeting export writes, plus `transcript.txt`.
enum LegalExport {
    static let manifestFile = "manifest.json"

    struct FileEntry: Codable, Equatable {
        var name: String
        var bytes: Int
        var sha256: String
    }

    struct MeetingEntry: Codable {
        var id: UUID
        var title: String
        var startedAt: Date
        var inTrash: Bool
        var folder: String
        var files: [FileEntry]
    }

    struct Manifest: Codable {
        var exportedAt: Date
        var legalHold: Bool
        var meetings: [MeetingEntry]
    }

    /// The meetings in one storage folder: the library or the trash.
    struct Source {
        var store: MeetingStore
        var meetings: [Meeting]
        var inTrash: Bool
    }

    /// Writes the export into a new folder inside `parent` and returns it.
    static func run(_ sources: [Source], myName: String, legalHold: Bool, to parent: URL, now: Date = Date()) throws -> URL {
        let fm = FileManager.default
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let root = parent.appendingPathComponent("GrokNola Legal Export \(formatter.string(from: now))", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: false)

        var entries: [MeetingEntry] = []
        for source in sources {
            for meeting in source.meetings {
                let folder = try source.store.export(meeting, myName: myName, to: root, includeTranscript: true)
                let names = try fm.contentsOfDirectory(atPath: folder.path).filter { !$0.hasPrefix(".") }.sorted()
                let files = try names.map { name in
                    let url = folder.appendingPathComponent(name)
                    return FileEntry(name: name, bytes: try fileSize(url), sha256: try sha256(of: url))
                }
                entries.append(MeetingEntry(
                    id: meeting.id, title: meeting.title, startedAt: meeting.startedAt,
                    inTrash: source.inTrash, folder: folder.lastPathComponent, files: files
                ))
            }
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let manifest = Manifest(exportedAt: now, legalHold: legalHold, meetings: entries)
        try encoder.encode(manifest).write(to: root.appendingPathComponent(manifestFile), options: .atomic)
        return root
    }

    /// The lowercase hex SHA-256 of a file, read a megabyte at a time.
    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func fileSize(_ url: URL) throws -> Int {
        try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    }
}
