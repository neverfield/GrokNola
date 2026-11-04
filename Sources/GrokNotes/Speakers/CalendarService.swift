import EventKit

/// Apple Calendar through EventKit.
final class CalendarService: CalendarSource {
    private let store = EKEventStore()

    var isAuthorized: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    func events(from start: Date, to end: Date) -> [CalendarEvent] {
        guard isAuthorized else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).map(Self.event)
    }

    private static func event(_ e: EKEvent) -> CalendarEvent {
        let attendees = (e.attendees ?? []).map { p in
            CalendarAttendee(
                name: p.name,
                email: p.url.absoluteString.hasPrefix("mailto:") ? String(p.url.absoluteString.dropFirst(7)) : nil,
                isSelf: p.isCurrentUser,
                response: nil
            )
        }
        let link = e.url.flatMap { CalendarEvent.meetingApp(for: $0) != nil ? $0 : nil }
            ?? CalendarEvent.conferenceLink(in: e.location)
            ?? CalendarEvent.conferenceLink(in: e.notes)
        return CalendarEvent(
            id: "\(e.eventIdentifier ?? e.calendarItemIdentifier)|\(Int(e.startDate.timeIntervalSince1970))",
            title: e.title ?? "Meeting",
            start: e.startDate,
            end: e.endDate,
            allDay: e.isAllDay,
            attendees: attendees,
            conferenceURL: link,
            location: e.location
        )
    }
}
