import AppKit
import Combine
import Foundation

/// The calendar source chosen in Settings.
enum CalendarChoice: String, CaseIterable, Identifiable {
    case automatic
    case google
    case apple
    case none

    var id: String { rawValue }

    var label: String {
        switch self {
        case .automatic: return "Automatic"
        case .google: return "Google Calendar"
        case .apple: return "Apple Calendar"
        case .none: return "None"
        }
    }
}

/// Picks the calendar to read: Google Calendar through the app's own sign-in, or Apple Calendar.
@MainActor
final class CalendarHub: ObservableObject {
    enum Active: Equatable {
        case google
        case apple
        case none
    }

    let apple = CalendarService()
    let googleAuth = GoogleOAuth()
    let google: GoogleCalendarSource
    private var forwarding: Set<AnyCancellable> = []

    init() {
        google = GoogleCalendarSource(auth: googleAuth)
        googleAuth.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &forwarding)
        google.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &forwarding)
        Self.removeLegacyFile()
    }

    // MARK: Source

    var choice: CalendarChoice { Prefs.calendarSource }

    var active: Active {
        switch choice {
        case .none: return .none
        case .apple: return apple.isAuthorized ? .apple : .none
        case .google: return googleAuth.isConnected ? .google : .none
        case .automatic:
            if googleAuth.isConnected { return .google }
            return apple.isAuthorized ? .apple : .none
        }
    }

    private var source: CalendarSource? {
        switch active {
        case .google: return google.snapshot
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

    // MARK: Google

    func connectGoogle() async {
        await googleAuth.signIn()
        if googleAuth.isConnected { await google.refresh() }
    }

    func disconnectGoogle() async {
        await googleAuth.disconnect()
        google.clear()
    }

    func reload() async {
        await google.refresh()
    }

    // MARK: Status

    /// One line for Settings, such as "Google · you@example.com · updated 2 min ago · 9 events".
    var statusLine: String {
        switch active {
        case .none:
            switch choice {
            case .none: return "Calendar is off."
            case .apple: return "Apple Calendar access is not granted."
            case .google: return googleAuth.isConfigured ? "Google Calendar is not connected." : GoogleOAuth.OAuthError.notConfigured.localizedDescription
            case .automatic: return "Connect Google Calendar or allow Apple Calendar."
            }
        case .apple:
            return "Apple Calendar · access granted"
        case .google:
            var parts = ["Google"]
            if let email = googleAuth.email { parts.append(email) }
            if let error = google.error {
                parts.append(error)
            } else if let updated = google.updatedAt {
                parts.append("updated \(Self.ago(updated))")
                parts.append("\(google.snapshot?.events.count ?? 0) events")
            } else {
                parts.append("loading…")
            }
            return parts.joined(separator: " · ")
        }
    }

    var isHealthy: Bool {
        switch active {
        case .none: return choice == .none
        case .apple: return true
        case .google: return google.error == nil && google.updatedAt != nil
        }
    }

    static func ago(_ date: Date?) -> String {
        guard let date else { return "never" }
        if Date().timeIntervalSince(date) < 60 { return "just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    /// Older versions read Google Calendar from a plain `calendar.json` that a Cursor agent wrote. It is no
    /// longer read, and any app could read or rewrite it, so it is removed.
    private static func removeLegacyFile() {
        let file = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GrokNotes/calendar.json")
        try? FileManager.default.removeItem(at: file)
    }
}
