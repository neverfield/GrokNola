import AppKit
import Foundation

/// The calendar source chosen in Settings.
enum CalendarChoice: String, CaseIterable, Identifiable {
    case automatic
    case googleFile
    case apple
    case none

    var id: String { rawValue }

    var label: String {
        switch self {
        case .automatic: return "Automatic"
        case .googleFile: return "Google via Cursor"
        case .apple: return "Apple Calendar"
        case .none: return "None"
        }
    }
}

/// Picks the calendar to read and keeps `calendar.json` loaded as a Cursor agent rewrites it.
@MainActor
final class CalendarHub: ObservableObject {
    enum Active: Equatable {
        case file
        case apple
        case none
    }

    /// A file synced longer ago than this is stale. Automatic then prefers Apple Calendar.
    static let freshness: TimeInterval = 24 * 3600
    static let syncPrompt = "Sync my calendar for Grok Notes"

    let apple = CalendarService()
    let fileURL = CalendarFile.defaultURL
    @Published private(set) var file: CalendarFile?
    @Published private(set) var fileError: String?
    @Published private(set) var fileModified: Date?

    private var lastStamp: (Date, Int)?
    private var watcher: DispatchSourceFileSystemObject?
    private var timer: Timer?

    init() {
        reload(force: true)
        watch()
    }

    // MARK: Source

    var choice: CalendarChoice { Prefs.calendarSource }

    var active: Active {
        switch choice {
        case .none: return .none
        case .apple: return apple.isAuthorized ? .apple : .none
        case .googleFile: return .file
        case .automatic:
            if file != nil, !isStale { return .file }
            if apple.isAuthorized { return .apple }
            return file != nil ? .file : .none
        }
    }

    private var source: CalendarSource? {
        switch active {
        case .file: return file
        case .apple: return apple
        case .none: return nil
        }
    }

    func currentEvent(at now: Date = Date()) -> CalendarEvent? { source?.currentEvent(at: now) }

    func upcoming(within interval: TimeInterval, from now: Date = Date()) -> [CalendarEvent] {
        source?.upcoming(within: interval, from: now) ?? []
    }

    /// Events that have not ended yet today.
    func remainingToday(now: Date = Date()) -> [CalendarEvent] {
        let calendar = Calendar.current
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        return upcoming(within: end.timeIntervalSince(now), from: now)
    }

    // MARK: File status

    /// When the file was last synced: its `syncedAt`, else its modification time.
    var syncedAt: Date? { file?.syncedAt ?? fileModified }

    var isStale: Bool {
        guard let syncedAt else { return true }
        return Date().timeIntervalSince(syncedAt) > Self.freshness
    }

    var hasFreshFile: Bool { file != nil && !isStale }

    /// One line for Settings, such as "Google via Cursor · synced 12 min ago · 14 events".
    var statusLine: String {
        switch active {
        case .none:
            switch choice {
            case .none: return "Calendar is off."
            case .apple: return "Apple Calendar access is not granted."
            default: return "No calendar.json yet, and Apple Calendar access is not granted."
            }
        case .apple:
            return choice == .automatic && file != nil
                ? "Apple Calendar · calendar.json is stale (synced \(Self.ago(syncedAt)))"
                : "Apple Calendar · access granted"
        case .file:
            if let fileError { return "calendar.json could not be read: \(fileError)" }
            guard let file else { return "No calendar.json yet" }
            if isStale { return "Stale: last synced \(Self.ago(syncedAt)) · \(file.events.count) events" }
            var line = "Google via Cursor · synced \(Self.ago(syncedAt)) · \(file.events.count) events"
            if file.skipped > 0 { line += " · \(file.skipped) unreadable" }
            return line
        }
    }

    static func ago(_ date: Date?) -> String {
        guard let date else { return "never" }
        if Date().timeIntervalSince(date) < 60 { return "just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    func revealFile() {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        } else {
            NSWorkspace.shared.open(fileURL.deletingLastPathComponent())
        }
    }

    func copySyncPrompt() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Self.syncPrompt, forType: .string)
    }

    // MARK: Loading

    /// Reads the file again when its modification time or size changed.
    func reload(force: Bool = false) {
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        guard let attributes, let modified = attributes[.modificationDate] as? Date else {
            if file != nil || fileError != nil || fileModified != nil {
                file = nil
                fileError = nil
                fileModified = nil
            }
            lastStamp = nil
            return
        }
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        if !force, let lastStamp, lastStamp == (modified, size) { return }
        lastStamp = (modified, size)
        fileModified = modified
        do {
            file = try CalendarFile.load(from: fileURL)
            fileError = nil
        } catch {
            // Keep the last good events while an agent rewrites or fixes the file.
            fileError = Self.describe(error)
        }
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case DecodingError.dataCorrupted(let context): return context.debugDescription
        case DecodingError.keyNotFound(let key, _): return "missing \"\(key.stringValue)\""
        case DecodingError.typeMismatch(_, let context): return "wrong type at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
        default: return error.localizedDescription
        }
    }

    /// The agent replaces the file with a rename, so watch the folder, and poll as a fallback.
    private func watch() {
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fd = open(dir.path, O_EVTONLY)
        if fd >= 0 {
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.reload() }
            }
            source.setCancelHandler { close(fd) }
            source.resume()
            watcher = source
        }
        timer = Timer.scheduledTimer(withTimeInterval: 45, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
    }
}
