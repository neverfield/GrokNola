import Foundation

struct CalendarAttendee: Codable, Hashable {
    var name: String?
    var email: String?
    var isSelf: Bool?
    var response: String?

    enum CodingKeys: String, CodingKey {
        case name, email, response
        case isSelf = "self"
    }

    /// The name if it is a real name, else a name built from the email's local part.
    var displayName: String? {
        if let name = name?.trimmingCharacters(in: .whitespaces), !name.isEmpty, !name.contains("@") { return name }
        let address = (name?.contains("@") == true ? name : nil) ?? email ?? ""
        guard let local = address.split(separator: "@").first, !local.isEmpty else { return nil }
        return local
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}

struct CalendarPerson: Codable, Hashable {
    var name: String?
    var email: String?
}

/// One calendar event from any source.
struct CalendarEvent: Identifiable, Hashable {
    var id: String
    var title: String
    var start: Date
    var end: Date
    var allDay = false
    var attendees: [CalendarAttendee] = []
    var organizer: CalendarPerson?
    var conferenceURL: URL?
    var location: String?
    var notes: String?

    /// Invitees other than the current user.
    var others: [CalendarAttendee] { attendees.filter { $0.isSelf != true } }
    var attendeeNames: [String] { uniqueNames(others.compactMap(\.displayName)) }
    var attendeeEmails: [String] {
        var seen = Set<String>()
        return others.compactMap { $0.email?.lowercased() }.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// The meeting app implied by the conference link, used when no running app was detected.
    var meetingAppName: String? { conferenceURL.flatMap(Self.meetingApp(for:)) }

    static func meetingApp(for url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        func matches(_ domain: String) -> Bool { host == domain || host.hasSuffix("." + domain) }
        if matches("meet.google.com") { return "Google Meet" }
        if matches("zoom.us") { return "Zoom" }
        if matches("teams.microsoft.com") || matches("teams.live.com") { return "Microsoft Teams" }
        return nil
    }

    /// The first meeting link found in free text, for sources without a conference field.
    static func conferenceLink(in text: String?) -> URL? {
        guard let text, !text.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, range: range).compactMap(\.url).first { meetingApp(for: $0) != nil }
    }
}

/// A source of calendar events: Apple Calendar or the file a Cursor agent writes.
protocol CalendarSource {
    func events(from start: Date, to end: Date) -> [CalendarEvent]
}

extension CalendarSource {
    /// The event happening now (or starting within 10 minutes), preferring events with invitees.
    func currentEvent(at now: Date = Date()) -> CalendarEvent? {
        CalendarMatch.current(in: events(from: now.addingTimeInterval(-6 * 3600), to: now.addingTimeInterval(3600)), at: now)
    }

    /// Events that have not ended yet and start within the interval, in start order.
    func upcoming(within interval: TimeInterval, from now: Date = Date()) -> [CalendarEvent] {
        CalendarMatch.remaining(in: events(from: now, to: now.addingTimeInterval(interval)), at: now, until: now.addingTimeInterval(interval))
    }
}

enum CalendarMatch {
    /// How early an event counts as current.
    static let lead: TimeInterval = 600

    static func current(in events: [CalendarEvent], at now: Date) -> CalendarEvent? {
        let live = events.filter { !$0.allDay && $0.start <= now.addingTimeInterval(lead) && $0.end >= now }
        return live.max { a, b in
            let aHas = !a.others.isEmpty, bHas = !b.others.isEmpty
            if aHas != bHas { return !aHas }
            return abs(a.start.timeIntervalSince(now)) > abs(b.start.timeIntervalSince(now))
        }
    }

    static func remaining(in events: [CalendarEvent], at now: Date, until end: Date) -> [CalendarEvent] {
        events
            .filter { $0.end > now && $0.start < end }
            .sorted { ($0.start, $0.title) < ($1.start, $1.title) }
    }
}

// MARK: - calendar.json

/// The file a Cursor agent writes from Google Calendar. See README "Calendar".
struct CalendarFile: CalendarSource {
    static let maxDescription = 2000

    var version: Int
    var source: String?
    var syncedAt: Date?
    var timeZone: TimeZone?
    var rangeStart: Date?
    var rangeEnd: Date?
    var events: [CalendarEvent]
    /// Entries that could not be read and were left out.
    var skipped = 0

    static var defaultURL: URL {
        if let path = ProcessInfo.processInfo.environment["GROK_NOTES_CALENDAR_FILE"], !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GrokNotes/calendar.json")
    }

    func events(from start: Date, to end: Date) -> [CalendarEvent] {
        events.filter { $0.end > start && $0.start < end }
    }

    static func load(from url: URL) throws -> CalendarFile {
        try parse(Data(contentsOf: url))
    }

    static func parse(_ data: Data) throws -> CalendarFile {
        let raw = try JSONDecoder().decode(RawFile.self, from: data)
        let zone = raw.timeZone.flatMap(TimeZone.init(identifier:)) ?? .current
        var skipped = 0
        var events: [CalendarEvent] = []
        for entry in raw.events ?? [] {
            if let e = entry.value, let event = e.event(in: zone) {
                if !event.declinedBySelf { events.append(event.value) }
            } else {
                skipped += 1
            }
        }
        events.sort { ($0.start, $0.title) < ($1.start, $1.title) }
        return CalendarFile(
            version: raw.version ?? 1,
            source: raw.source,
            syncedAt: raw.syncedAt.flatMap { CalendarDates.parse($0, in: zone)?.date },
            timeZone: raw.timeZone.flatMap(TimeZone.init(identifier:)),
            rangeStart: raw.rangeStart.flatMap { CalendarDates.parse($0, in: zone)?.date },
            rangeEnd: raw.rangeEnd.flatMap { CalendarDates.parse($0, in: zone)?.date },
            events: events,
            skipped: skipped
        )
    }
}

enum CalendarDates {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain = ISO8601DateFormatter()

    private static func formatter(_ format: String, _ zone: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = zone
        f.dateFormat = format
        return f
    }

    /// ISO 8601 with or without fractional seconds, a local date-time, or a date (all-day).
    static func parse(_ string: String, in zone: TimeZone) -> (date: Date, dateOnly: Bool)? {
        let s = string.trimmingCharacters(in: .whitespaces)
        if let d = withFraction.date(from: s) ?? plain.date(from: s) { return (d, false) }
        if let d = formatter("yyyy-MM-dd'T'HH:mm:ss", zone).date(from: s) ?? formatter("yyyy-MM-dd'T'HH:mm", zone).date(from: s) {
            return (d, false)
        }
        if s.count == 10, let d = formatter("yyyy-MM-dd", zone).date(from: s) { return (d, true) }
        return nil
    }
}

private struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

/// A time as a string, or Google's `{ "dateTime": …, "date": … }` object.
private struct FlexibleTime: Decodable {
    var text: String
    var zone: String?

    private struct Object: Decodable {
        var dateTime: String?
        var date: String?
        var timeZone: String?
    }

    init(from decoder: Decoder) throws {
        if let s = try? decoder.singleValueContainer().decode(String.self) {
            text = s
            return
        }
        let o = try Object(from: decoder)
        guard let t = o.dateTime ?? o.date else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "No dateTime or date"))
        }
        text = t
        zone = o.timeZone
    }

    func date(in fallback: TimeZone) -> (date: Date, dateOnly: Bool)? {
        CalendarDates.parse(text, in: zone.flatMap(TimeZone.init(identifier:)) ?? fallback)
    }
}

private struct RawFile: Decodable {
    var version: Int?
    var source: String?
    var syncedAt: String?
    var timeZone: String?
    var rangeStart: String?
    var rangeEnd: String?
    var events: [Lossy<RawEvent>]?
}

private struct RawEvent: Decodable {
    var id: String
    var title: String?
    var start: FlexibleTime
    var end: FlexibleTime?
    var allDay: Bool?
    var attendees: [Lossy<CalendarAttendee>]?
    var organizer: CalendarPerson?
    var conferenceURL: String?
    var location: String?
    var description: String?

    func event(in zone: TimeZone) -> (value: CalendarEvent, declinedBySelf: Bool)? {
        guard let start = start.date(in: zone) else { return nil }
        let allDay = allDay ?? start.dateOnly
        var endDate = end?.date(in: zone)?.date ?? start.date.addingTimeInterval(allDay ? 86_400 : 3600)
        if endDate <= start.date { endDate = start.date.addingTimeInterval(allDay ? 86_400 : 0) }
        let people = (attendees ?? []).compactMap(\.value)
        let url = conferenceURL.flatMap(URL.init(string:)).flatMap { ["http", "https"].contains($0.scheme?.lowercased() ?? "") ? $0 : nil }
        let title = self.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let event = CalendarEvent(
            id: id,
            title: title.isEmpty ? "Untitled event" : title,
            start: start.date,
            end: endDate,
            allDay: allDay,
            attendees: people,
            organizer: organizer,
            conferenceURL: url,
            location: location,
            notes: description.map { String($0.prefix(CalendarFile.maxDescription)) }
        )
        let declined = people.contains { $0.isSelf == true && $0.response?.lowercased() == "declined" }
        return (event, declined)
    }
}
