import EventKit

final class CalendarService {
    private let store = EKEventStore()

    var isAuthorized: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    /// The event happening now (or starting within 10 minutes), preferring events with invitees.
    func currentEvent() -> (title: String, attendees: [String])? {
        guard isAuthorized else { return nil }
        let now = Date()
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-6 * 3600), end: now.addingTimeInterval(3600), calendars: nil)
        let events = store.events(matching: predicate).filter {
            !$0.isAllDay && $0.startDate <= now.addingTimeInterval(600) && $0.endDate >= now
        }
        let best = events.max { a, b in
            let aHas = !(a.attendees ?? []).isEmpty, bHas = !(b.attendees ?? []).isEmpty
            if aHas != bHas { return !aHas }
            return abs(a.startDate.timeIntervalSince(now)) > abs(b.startDate.timeIntervalSince(now))
        }
        guard let event = best else { return nil }
        let attendees = (event.attendees ?? []).filter { !$0.isCurrentUser }.compactMap(Self.displayName)
        return (event.title ?? "Meeting", uniqueNames(attendees))
    }

    private static func displayName(_ participant: EKParticipant) -> String? {
        if let name = participant.name, !name.isEmpty, !name.contains("@") { return name }
        let email = participant.name ?? participant.url.absoluteString.replacingOccurrences(of: "mailto:", with: "")
        guard let local = email.split(separator: "@").first, !local.isEmpty else { return nil }
        return local
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}
