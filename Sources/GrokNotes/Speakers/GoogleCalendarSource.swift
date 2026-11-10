import AppKit
import Foundation

/// Events read once, from any source, for the synchronous `CalendarSource` lookups.
struct CalendarSnapshot: CalendarSource {
    var events: [CalendarEvent]

    func events(from start: Date, to end: Date) -> [CalendarEvent] {
        events.filter { $0.end > start && $0.start < end }
    }
}

/// Your primary Google Calendar, read with the signed-in account. Events stay in memory only: they are
/// fetched again every few minutes, when the Mac wakes, and on Reload, and the last good set is kept
/// through a network error.
@MainActor
final class GoogleCalendarSource: ObservableObject {
    static let refreshInterval: TimeInterval = 300

    let auth: GoogleOAuth
    @Published private(set) var snapshot: CalendarSnapshot?
    @Published private(set) var updatedAt: Date?
    @Published private(set) var error: String?

    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var loading = false

    init(auth: GoogleOAuth) {
        self.auth = auth
        timer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        Task { await refresh() }
    }

    /// Forgets the events, after you disconnect.
    func clear() {
        snapshot = nil
        updatedAt = nil
        error = nil
    }

    func refresh() async {
        guard auth.isConnected, !loading else { return }
        loading = true
        defer { loading = false }
        let now = Date()
        let calendar = Calendar.current
        let from = now.addingTimeInterval(-6 * 3600)
        let to = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(48 * 3600)
        do {
            var data = try await fetch(from: from, to: to, token: auth.accessToken())
            if data == nil {
                auth.invalidateAccessToken()
                data = try await fetch(from: from, to: to, token: auth.accessToken())
            }
            guard let data else { throw GoogleOAuth.OAuthError.reconnect }
            let page = try GoogleEvents.parse(data)
            snapshot = CalendarSnapshot(events: page.events)
            if let summary = page.summary, summary.contains("@") { auth.email = summary }
            updatedAt = Date()
            error = nil
        } catch {
            self.error = error.localizedDescription
            if !auth.isConnected { clear() }
        }
    }

    /// The events response, or nil when Google rejected the access token.
    private func fetch(from: Date, to: Date, token: String) async throws -> Data? {
        let iso = ISO8601DateFormatter()
        var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")!
        components.queryItems = [
            URLQueryItem(name: "timeMin", value: iso.string(from: from)),
            URLQueryItem(name: "timeMax", value: iso.string(from: to)),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "maxResults", value: "250"),
            URLQueryItem(name: "fields", value: GoogleEvents.fields),
        ]
        var request = URLRequest(url: components.url!, timeoutInterval: 30)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await Network.session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { return nil }
        guard (200..<300).contains(status) else { throw GoogleOAuth.OAuthError.server("Calendar request failed (HTTP \(status))") }
        return data
    }
}

/// Maps a Google Calendar API `events.list` response to `CalendarEvent`s.
enum GoogleEvents {
    /// Only the fields GrokNola uses are requested.
    static let fields = "summary,timeZone,items(id,status,summary,start,end,attendees(email,displayName,self,responseStatus),"
        + "organizer(email,displayName),hangoutLink,conferenceData(entryPoints(entryPointType,uri)),location,description)"

    struct Page {
        /// The calendar's name; for the primary calendar, the account's email.
        var summary: String?
        var events: [CalendarEvent]
    }

    static func parse(_ data: Data) throws -> Page {
        let raw = try JSONDecoder().decode(RawPage.self, from: data)
        let zone = raw.timeZone.flatMap(TimeZone.init(identifier:)) ?? .current
        let events = (raw.items ?? []).compactMap { $0.value?.event(in: zone) }
            .sorted { ($0.start, $0.title) < ($1.start, $1.title) }
        return Page(summary: raw.summary, events: events)
    }

    private struct RawPage: Decodable {
        var summary: String?
        var timeZone: String?
        var items: [Lossy<RawEvent>]?
    }

    private struct RawPerson: Decodable {
        var email: String?
        var displayName: String?
        var isSelf: Bool?
        var responseStatus: String?

        enum CodingKeys: String, CodingKey {
            case email, displayName, responseStatus
            case isSelf = "self"
        }
    }

    private struct RawEntryPoint: Decodable {
        var entryPointType: String?
        var uri: String?
    }

    private struct RawConference: Decodable {
        var entryPoints: [RawEntryPoint]?
    }

    private struct RawEvent: Decodable {
        var id: String
        var status: String?
        var summary: String?
        var start: FlexibleTime
        var end: FlexibleTime?
        var attendees: [RawPerson]?
        var organizer: RawPerson?
        var hangoutLink: String?
        var conferenceData: RawConference?
        var location: String?
        var description: String?

        /// Nil for cancelled events, events you declined, and events without a readable start.
        func event(in zone: TimeZone) -> CalendarEvent? {
            guard status != "cancelled", let start = start.date(in: zone) else { return nil }
            let people = (attendees ?? []).map {
                CalendarAttendee(name: $0.displayName, email: $0.email, isSelf: $0.isSelf, response: $0.responseStatus)
            }
            if people.contains(where: { $0.isSelf == true && $0.response == "declined" }) { return nil }
            let allDay = start.dateOnly
            var endDate = end?.date(in: zone)?.date ?? start.date.addingTimeInterval(allDay ? 86_400 : 3600)
            if endDate <= start.date { endDate = start.date.addingTimeInterval(allDay ? 86_400 : 0) }
            let video = conferenceData?.entryPoints?.first { $0.entryPointType == "video" }?.uri
            let link = [hangoutLink, video].compactMap { $0.flatMap(URL.init(string:)) }
                .first { ["http", "https"].contains($0.scheme?.lowercased() ?? "") }
                ?? CalendarEvent.conferenceLink(in: location)
                ?? CalendarEvent.conferenceLink(in: description)
            let title = summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return CalendarEvent(
                id: id,
                title: title.isEmpty ? "Untitled event" : title,
                start: start.date,
                end: endDate,
                allDay: allDay,
                attendees: people,
                organizer: organizer.map { CalendarPerson(name: $0.displayName, email: $0.email) },
                conferenceURL: link,
                location: location,
                notes: description.map { String($0.prefix(CalendarEvent.maxDescription)) }
            )
        }
    }
}
