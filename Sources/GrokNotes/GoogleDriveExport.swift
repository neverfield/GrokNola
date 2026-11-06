import Foundation

/// Mirrors meeting exports into Google Drive for desktop's synced `My Drive` folder (no OAuth).
enum GoogleDriveExport {
    private static let cloudStorage = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/CloudStorage", isDirectory: true)

    /// First mounted `GoogleDrive-*` account with a `My Drive` directory.
    static func myDriveRoot() -> URL? {
        guard let mounts = try? FileManager.default.contentsOfDirectory(
            at: cloudStorage,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        for mount in mounts where mount.lastPathComponent.hasPrefix("GoogleDrive") {
            let myDrive = mount.appendingPathComponent("My Drive", isDirectory: true)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: myDrive.path, isDirectory: &isDir), isDir.boolValue {
                return myDrive
            }
        }
        return nil
    }

    /// Writes the notes, without the transcript, as `notes.md` after a local save. The transcript and
    /// recordings leave the app only through the manual export. Never blocks the caller; logs failures.
    static func mirrorIfEnabled(meeting: Meeting, myName: String) {
        guard Prefs.exportToGoogleDrive else { return }
        let notes = meeting.notesMarkdown(myName: myName)
        Task.detached(priority: .utility) {
            do {
                try mirror(notes, for: meeting)
            } catch {
                NSLog("GrokNotes: Google Drive export failed: \(error.localizedDescription)")
            }
        }
    }

    private static func mirror(_ notes: String, for meeting: Meeting) throws {
        guard let myDrive = myDriveRoot() else {
            throw ExportError.driveUnavailable
        }

        var destination = myDrive
        if let subfolder = Prefs.googleDriveSubfolder {
            destination = destination.appendingPathComponent(sanitizePathComponent(subfolder), isDirectory: true)
        }
        destination = destination.appendingPathComponent(folderName(for: meeting), isDirectory: true)

        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try notes.write(to: destination.appendingPathComponent(MeetingStore.notesFile), atomically: true, encoding: .utf8)
    }

    static func folderName(for meeting: Meeting) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        let datePart = formatter.string(from: meeting.startedAt)
        let titlePart = sanitizePathComponent(meeting.title)
        return "\(datePart) \(titlePart)"
    }

    static func sanitizePathComponent(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let collapsed = trimmed.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        var name = collapsed.isEmpty ? "Untitled" : String(collapsed)
        let forbidden = CharacterSet(charactersIn: ":/\\")
        name = name.unicodeScalars.map { forbidden.contains($0) ? "-" : Character($0) }.map(String.init).joined()
        while name.contains("--") { name = name.replacingOccurrences(of: "--", with: "-") }
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: "- "))
        if name.isEmpty { name = "Untitled" }
        if name.count > 120 {
            name = String(name.prefix(120)).trimmingCharacters(in: CharacterSet(charactersIn: "- "))
        }
        return name.isEmpty ? "Untitled" : name
    }

    enum ExportError: LocalizedError {
        case driveUnavailable

        var errorDescription: String? {
            switch self {
            case .driveUnavailable:
                return "Google Drive for desktop is not mounted."
            }
        }
    }
}
