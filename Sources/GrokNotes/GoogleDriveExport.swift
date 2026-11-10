import Foundation

/// Mirrors meeting exports into Google Drive for desktop's synced `My Drive` folder (no OAuth).
/// Notes go only to one Drive account: the one picked in Settings, or else the one that matches your Google
/// sign-in or company domain. With several accounts and no match, nothing is copied until you pick one.
enum GoogleDriveExport {
    private static let cloudStorage = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/CloudStorage", isDirectory: true)
    static let mountPrefix = "GoogleDrive-"

    /// Folder names of mounted Google Drive accounts that have a `My Drive`, such as `GoogleDrive-ana@example.com`.
    static func mounts() -> [String] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: cloudStorage,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return entries.filter { mount in
            guard mount.lastPathComponent.hasPrefix(mountPrefix) else { return false }
            var isDir: ObjCBool = false
            let myDrive = mount.appendingPathComponent("My Drive", isDirectory: true)
            return FileManager.default.fileExists(atPath: myDrive.path, isDirectory: &isDir) && isDir.boolValue
        }.map(\.lastPathComponent).sorted()
    }

    /// The account email in a mount's folder name, or nil.
    static func account(ofMount name: String) -> String? {
        guard name.hasPrefix(mountPrefix) else { return nil }
        let email = String(name.dropFirst(mountPrefix.count))
        return ConsentReminder.domain(of: email) == nil ? nil : email
    }

    /// The mount to copy notes into. A mount picked in Settings wins, and is never replaced by another when it
    /// is missing. Otherwise the mount for `accountEmail`, else the only mount in your company's domains.
    static func chooseMount(from mounts: [String], pinned: String?, accountEmail: String?, companyDomains: Set<String>) -> String? {
        if let pinned { return mounts.contains(pinned) ? pinned : nil }
        if let email = accountEmail?.lowercased(),
           let match = mounts.first(where: { account(ofMount: $0)?.lowercased() == email }) {
            return match
        }
        guard !companyDomains.isEmpty else { return nil }
        let company = mounts.filter { mount in
            account(ofMount: mount).flatMap(ConsentReminder.domain(of:)).map { ConsentReminder.isOwn($0, own: companyDomains) } ?? false
        }
        return company.count == 1 ? company[0] : nil
    }

    /// The `My Drive` folder notes are copied into, or nil when no mount can be chosen safely.
    static func myDriveRoot(accountEmail: String?) -> URL? {
        guard let mount = chooseMount(
            from: mounts(), pinned: Prefs.googleDriveMount, accountEmail: accountEmail, companyDomains: Prefs.companyDomains
        ) else { return nil }
        return cloudStorage.appendingPathComponent(mount, isDirectory: true).appendingPathComponent("My Drive", isDirectory: true)
    }

    /// Writes the notes, without the transcript, as `notes.md` after a local save. The transcript and
    /// recordings leave the app only through the manual export. Do not call while the meeting records.
    /// Never blocks the caller; logs failures.
    static func mirrorIfEnabled(meeting: Meeting, myName: String, accountEmail: String?) {
        guard Prefs.exportToGoogleDrive else { return }
        let notes = meeting.notesMarkdown(myName: myName)
        guard let myDrive = myDriveRoot(accountEmail: accountEmail) else {
            NSLog("GrokNotes: Google Drive export skipped: \(ExportError.driveUnavailable.localizedDescription)")
            return
        }
        let subfolder = Prefs.googleDriveSubfolder
        Task.detached(priority: .utility) {
            do {
                try mirror(notes, for: meeting, into: myDrive, subfolder: subfolder)
            } catch {
                NSLog("GrokNotes: Google Drive export failed: \(error.localizedDescription)")
            }
        }
    }

    private static func mirror(_ notes: String, for meeting: Meeting, into myDrive: URL, subfolder: String?) throws {
        var destination = myDrive
        if let subfolder {
            guard isValidSubfolder(subfolder) else { throw ExportError.invalidSubfolder }
            destination = destination.appendingPathComponent(sanitizePathComponent(subfolder), isDirectory: true)
        }
        destination = destination.appendingPathComponent(folderName(for: meeting), isDirectory: true)

        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try notes.write(to: destination.appendingPathComponent(MeetingStore.notesFile), atomically: true, encoding: .utf8)
    }

    /// A subfolder name made only of dots, such as `..`, would point outside My Drive or at a hidden folder.
    static func isValidSubfolder(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !trimmed.allSatisfy { $0 == "." }
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

    /// One safe folder name: no path separators, no leading dot (leading dots become `_`), at most 120 characters.
    static func sanitizePathComponent(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let collapsed = trimmed.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        var name = collapsed.isEmpty ? "Untitled" : String(collapsed)
        let forbidden = CharacterSet(charactersIn: ":/\\")
        name = name.unicodeScalars.map { forbidden.contains($0) ? "-" : Character($0) }.map(String.init).joined()
        while name.contains("--") { name = name.replacingOccurrences(of: "--", with: "-") }
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: "- "))
        if name.allSatisfy({ $0 == "." }) { name = "" }
        let dots = name.prefix { $0 == "." }.count
        if dots > 0 { name = String(repeating: "_", count: dots) + name.dropFirst(dots) }
        if name.isEmpty { name = "Untitled" }
        if name.count > 120 {
            name = String(name.prefix(120)).trimmingCharacters(in: CharacterSet(charactersIn: "- "))
        }
        return name.isEmpty ? "Untitled" : name
    }

    enum ExportError: LocalizedError {
        case driveUnavailable
        case invalidSubfolder

        var errorDescription: String? {
            switch self {
            case .driveUnavailable:
                return "No Google Drive account is chosen. Pick one in Settings > Calendar & Drive."
            case .invalidSubfolder:
                return "The Google Drive subfolder name is not valid."
            }
        }
    }
}
