import Foundation

/// One folder per meeting under ~/Library/Application Support/GrokNotes/Meetings.
/// `meeting.json` is the source of truth, sealed by `Vault` as `meeting.json.enc`. Older folders may still
/// hold a plain `meeting.json` and `notes.md` until the launch sweep seals them.
struct MeetingStore {
    static let meetingFile = "meeting.json"
    static let notesFile = "notes.md"

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
        let dirs = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return dirs.compactMap(Self.decode(at:)).sorted { $0.startedAt > $1.startedAt }
    }

    func load(_ id: UUID) -> Meeting? {
        Self.decode(at: root.appendingPathComponent(id.uuidString, isDirectory: true))
    }

    private static func decode(at dir: URL) -> Meeting? {
        let url = dir.appendingPathComponent(meetingFile)
        guard Vault.exists(url) else { return nil }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(Meeting.self, from: Vault.read(url))
        } catch {
            NSLog("GrokNotes: could not open \(dir.lastPathComponent): \(error.localizedDescription)")
            return nil
        }
    }

    static func encode(_ meeting: Meeting) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(meeting)
    }

    func save(_ meeting: Meeting, myName: String) throws {
        let dir = directory(for: meeting.id)
        try Vault.write(Self.encode(meeting), to: dir.appendingPathComponent(Self.meetingFile))
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(Self.notesFile))
        GoogleDriveExport.mirrorIfEnabled(meeting: meeting, myName: myName)
    }

    /// Seals plain files left by older versions or a crash in each meeting folder under `roots`, and removes the
    /// old local `notes.md`. Call at launch, before any recording starts. `meeting.json` is sealed here, on the
    /// caller's actor, so it cannot race a save; recordings and frames are sealed in the background.
    static func sealLeftovers(in roots: [URL]) {
        let fm = FileManager.default
        var large: [URL] = []
        let dirs = roots.flatMap { (try? fm.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil)) ?? [] }
        for dir in dirs {
            try? fm.removeItem(at: dir.appendingPathComponent(notesFile))
            let meeting = dir.appendingPathComponent(meetingFile)
            do {
                if fm.fileExists(atPath: Vault.sealedURL(meeting).path) {
                    try? fm.removeItem(at: meeting)
                } else {
                    try Vault.sealFile(at: meeting)
                }
            } catch {
                NSLog("GrokNotes: could not encrypt \(dir.lastPathComponent): \(error.localizedDescription)")
                return
            }
            let frames = dir.appendingPathComponent("frames", isDirectory: true)
            let files = [dir.appendingPathComponent("mic.wav"), dir.appendingPathComponent("system.wav")]
                + ((try? fm.contentsOfDirectory(at: frames, includingPropertiesForKeys: nil)) ?? [])
            for file in files {
                if file.pathExtension == "partial" { try? fm.removeItem(at: file) }
                if ["wav", "jpg"].contains(file.pathExtension), fm.fileExists(atPath: file.path) { large.append(file) }
            }
            try? fm.removeItem(at: Vault.sealedURL(files[0]).appendingPathExtension("partial"))
            try? fm.removeItem(at: Vault.sealedURL(files[1]).appendingPathExtension("partial"))
        }
        guard !large.isEmpty else { return }
        Task.detached(priority: .utility) {
            for file in large {
                do {
                    try Vault.sealFile(at: file)
                } catch {
                    NSLog("GrokNotes: could not encrypt \(file.lastPathComponent): \(error.localizedDescription)")
                }
            }
        }
    }

    /// Writes plain copies of a meeting into a new folder inside `parent`: `notes.md` with the transcript,
    /// `meeting.json`, and any kept recordings. Returns the folder.
    func export(_ meeting: Meeting, myName: String, to parent: URL) throws -> URL {
        let fm = FileManager.default
        let name = GoogleDriveExport.folderName(for: meeting)
        var folder = parent.appendingPathComponent(name, isDirectory: true)
        var n = 2
        while fm.fileExists(atPath: folder.path) {
            folder = parent.appendingPathComponent("\(name) \(n)", isDirectory: true)
            n += 1
        }
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try meeting.markdown(myName: myName).write(to: folder.appendingPathComponent(Self.notesFile), atomically: true, encoding: .utf8)
        try Self.encode(meeting).write(to: folder.appendingPathComponent(Self.meetingFile), options: .atomic)
        let dir = root.appendingPathComponent(meeting.id.uuidString, isDirectory: true)
        for file in ["mic.wav", "system.wav"] where Vault.exists(dir.appendingPathComponent(file)) {
            try Vault.read(dir.appendingPathComponent(file)).write(to: folder.appendingPathComponent(file))
        }
        return folder
    }

    func delete(_ id: UUID) {
        try? FileManager.default.removeItem(at: root.appendingPathComponent(id.uuidString, isDirectory: true))
    }
}
