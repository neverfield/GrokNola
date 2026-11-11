import Foundation

/// Checks that FileVault protects the disk that holds the meetings, before a recording starts.
///
/// The volume's `volumeIsEncrypted` resource value is read first. It can be false on a FileVault-protected
/// Apple silicon data volume, so only `true` is taken as an answer; otherwise `fdesetup status` decides.
enum DiskEncryption {
    static let offWarning = "FileVault is off, so meetings on this Mac are protected only by GrokNola's own encryption. Turn on FileVault in System Settings > Privacy & Security."
    static let pilotRefusal = "This pilot build records only when FileVault is on. Turn it on in System Settings > Privacy & Security > FileVault, then start again."
    static let unknownWarning = "GrokNola could not confirm that FileVault is on. Check System Settings > Privacy & Security > FileVault."

    enum Decision: Equatable {
        case ok
        case warn(String)
        case refuse(String)
    }

    /// A pilot build needs FileVault confirmed on. Other builds only warn.
    static func decide(encrypted: Bool?, pilot: Bool) -> Decision {
        switch encrypted {
        case true?: return .ok
        case false?: return pilot ? .refuse(pilotRefusal) : .warn(offWarning)
        case nil: return pilot ? .refuse(pilotRefusal) : .warn(unknownWarning)
        }
    }

    /// Whether the disk holding `url` is encrypted, or nil when neither check can tell. Runs `fdesetup`, so call
    /// it off the main thread.
    static func isEncrypted(_ url: URL) -> Bool? {
        if (try? url.resourceValues(forKeys: [.volumeIsEncryptedKey]).volumeIsEncrypted) == true { return true }
        return fdesetupStatus()
    }

    /// Reads "FileVault is On." or "FileVault is Off." from `fdesetup status` output.
    static func parseFdesetup(_ output: String) -> Bool? {
        if output.contains("FileVault is On") { return true }
        if output.contains("FileVault is Off") { return false }
        return nil
    }

    private static func fdesetupStatus() -> Bool? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/fdesetup")
        process.arguments = ["status"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return parseFdesetup(String(decoding: data, as: UTF8.self))
    }
}
