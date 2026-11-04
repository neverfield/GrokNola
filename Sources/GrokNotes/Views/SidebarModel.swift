import Foundation

/// How a row shows its date. The section header already carries the coarse date.
enum SidebarDateStyle {
    case relative
    case time
    case weekdayTime
    case weekdayDay
    case monthDay

    func format(_ date: Date) -> String {
        switch self {
        case .relative: return GrokFormat.relativeDay(date)
        case .time: return date.formatted(date: .omitted, time: .shortened)
        case .weekdayTime: return date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        case .weekdayDay: return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        case .monthDay: return date.formatted(.dateTime.month(.abbreviated).day())
        }
    }
}

struct MeetingGroup: Identifiable {
    let id: String
    let title: String
    let dateStyle: SidebarDateStyle
    var meetings: [Meeting]
}

/// Mail and Notes style buckets: Today, Yesterday, Previous 7 Days, Previous 30 Days,
/// each month of the current year, then each older year.
enum MeetingGrouping {
    static func groups(_ meetings: [Meeting], now: Date = Date(), calendar: Calendar = .current) -> [MeetingGroup] {
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let week = calendar.date(byAdding: .day, value: -7, to: today) ?? today
        let month = calendar.date(byAdding: .day, value: -30, to: today) ?? today
        let thisYear = calendar.component(.year, from: now)

        var groups: [MeetingGroup] = []
        var indexByID: [String: Int] = [:]
        for m in meetings.sorted(by: { $0.startedAt > $1.startedAt }) {
            let date = m.startedAt
            let key: (id: String, title: String, style: SidebarDateStyle)
            if date >= today {
                key = ("today", "Today", .time)
            } else if date >= yesterday {
                key = ("yesterday", "Yesterday", .time)
            } else if date >= week {
                key = ("previous7", "Previous 7 Days", .weekdayTime)
            } else if date >= month {
                key = ("previous30", "Previous 30 Days", .weekdayDay)
            } else {
                let parts = calendar.dateComponents([.year, .month], from: date)
                let year = parts.year ?? thisYear
                if year == thisYear {
                    key = ("month-\(year)-\(parts.month ?? 0)", date.formatted(.dateTime.month(.wide).year()), .weekdayDay)
                } else {
                    key = ("year-\(year)", String(year), .monthDay)
                }
            }
            if let index = indexByID[key.id] {
                groups[index].meetings.append(m)
            } else {
                indexByID[key.id] = groups.count
                groups.append(MeetingGroup(id: key.id, title: key.title, dateStyle: key.style, meetings: [m]))
            }
        }
        return groups
    }
}

/// Lowercased search text per meeting, rebuilt only when a fingerprint of the meeting changes,
/// so typing in the search field does not lowercase every transcript on each keystroke.
/// The transcript is fingerprinted by count and first/last utterance ids rather than hashed in full.
final class MeetingSearchIndex {
    private var cache: [UUID: (stamp: Int, text: String)] = [:]

    func matches(_ meeting: Meeting, terms: [String]) -> Bool {
        let text = self.text(for: meeting)
        return terms.allSatisfy { text.contains($0) }
    }

    static func terms(_ query: String) -> [String] {
        query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private func text(for m: Meeting) -> String {
        let stamp = fingerprint(m)
        if let entry = cache[m.id], entry.stamp == stamp { return entry.text }
        let parts: [String] = [
            m.title,
            m.tagList.joined(separator: " "),
            m.appName ?? "",
            m.attendees.joined(separator: " "),
            m.speakers.values.compactMap(\.name).joined(separator: " "),
            m.userNotes,
            m.enhancedNotes ?? "",
            m.utterances.map(\.text).joined(separator: " "),
        ]
        let text = parts.joined(separator: "\n").lowercased()
        cache[m.id] = (stamp, text)
        return text
    }

    private func fingerprint(_ m: Meeting) -> Int {
        var hasher = Hasher()
        hasher.combine(m.title)
        hasher.combine(m.tagList)
        hasher.combine(m.appName)
        hasher.combine(m.attendees)
        hasher.combine(m.userNotes)
        hasher.combine(m.enhancedNotes)
        hasher.combine(m.utterances.count)
        hasher.combine(m.utterances.last?.id)
        hasher.combine(m.utterances.first?.id)
        for name in m.speakers.values.compactMap(\.name).sorted() { hasher.combine(name) }
        return hasher.finalize()
    }
}
