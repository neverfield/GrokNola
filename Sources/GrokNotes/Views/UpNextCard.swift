import SwiftUI

/// Today's remaining calendar events on Home, each with Join and Start notes.
struct UpNextCard: View {
    @EnvironmentObject private var calendars: CalendarHub
    @AppStorage("calendarSource") private var calendarSource = CalendarChoice.automatic

    private static let rowLimit = 5

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            content(now: context.date)
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        if calendarSource == .none {
            EmptyView()
        } else if calendars.active == .none || (calendars.active == .file && calendars.file == nil) {
            setupHint
        } else {
            card(now: now)
        }
    }

    private var setupHint: some View {
        HStack(spacing: GrokSpacing.sm) {
            Image(systemName: "calendar.badge.plus").foregroundStyle(GrokColors.inkMuted)
            Text(calendars.fileError.map { "calendar.json could not be read: \($0)" }
                 ?? "See what's next here: in Cursor, say “\(CalendarHub.syncPrompt)”.")
                .foregroundStyle(GrokColors.inkMuted)
                .lineLimit(1)
            SettingsLink { Text("Calendar settings") }
                .buttonStyle(GrokLinkButtonStyle())
        }
        .font(.callout)
    }

    private func card(now: Date) -> some View {
        let events = calendars.remainingToday(now: now)
        let timed = events.filter { !$0.allDay }
        let allDay = events.filter(\.allDay)
        let currentID = calendars.currentEvent(at: now)?.id
        return HomeCard(title: "Up next", systemImage: "calendar", trailing: timed.isEmpty ? nil : "\(timed.count) left today") {
            VStack(alignment: .leading, spacing: GrokSpacing.sm) {
                if !allDay.isEmpty {
                    Text("All day: \(allDay.map(\.title).joined(separator: ", "))")
                        .font(GrokTypography.captionMuted())
                        .foregroundStyle(GrokColors.inkMuted)
                        .lineLimit(1)
                }
                if timed.isEmpty {
                    Text("Nothing else on your calendar today.")
                        .foregroundStyle(GrokColors.inkMuted)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(timed.prefix(Self.rowLimit).enumerated()), id: \.element.id) { index, event in
                            if index > 0 { GrokColors.hairline.frame(height: 1).padding(.leading, 76) }
                            UpNextRow(event: event, isNow: event.id == currentID || (event.start <= now && event.end > now))
                        }
                    }
                    if timed.count > Self.rowLimit {
                        Text("+\(timed.count - Self.rowLimit) more later today")
                            .font(GrokTypography.captionMuted())
                            .foregroundStyle(GrokColors.inkMuted)
                    }
                }
                if calendars.active == .file, calendars.isStale {
                    Label("Calendar last synced \(CalendarHub.ago(calendars.syncedAt)). Say “\(CalendarHub.syncPrompt)” in Cursor to refresh.", systemImage: "clock.badge.exclamationmark")
                        .font(GrokTypography.captionMuted())
                        .foregroundStyle(GrokColors.inkMuted)
                }
            }
        }
    }
}

private struct UpNextRow: View {
    @EnvironmentObject private var state: AppState
    let event: CalendarEvent
    let isNow: Bool

    var body: some View {
        HStack(alignment: .center, spacing: GrokSpacing.md) {
            Text(isNow ? "Now" : event.start.formatted(date: .omitted, time: .shortened))
                .font(.callout.weight(isNow ? .semibold : .medium).monospacedDigit())
                .foregroundStyle(isNow ? GrokColors.amberText : GrokColors.inkMuted)
                .frame(width: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .foregroundStyle(GrokColors.ink)
                    .lineLimit(1)
                Text(subtitle)
                    .font(GrokTypography.captionMuted())
                    .foregroundStyle(GrokColors.inkMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: GrokSpacing.sm)
            if let url = event.conferenceURL {
                Link(destination: url) { Label("Join", systemImage: "video") }
                    .buttonStyle(.bordered)
                    .help(url.absoluteString)
            }
            if state.recordingID == nil {
                Button {
                    Task { await state.startMeeting(event: event) }
                } label: {
                    Label("Start notes", systemImage: "record.circle")
                }
                .buttonStyle(.bordered)
                .help("Start notes titled \"\(event.title)\" with its invitees")
            }
        }
        .controlSize(.small)
        .padding(.vertical, GrokSpacing.sm)
    }

    private var subtitle: String {
        var parts = ["\(event.start.formatted(date: .omitted, time: .shortened)) – \(event.end.formatted(date: .omitted, time: .shortened))"]
        let count = event.others.count
        if count > 0 { parts.append(count == 1 ? "1 attendee" : "\(count) attendees") }
        if let app = event.meetingAppName { parts.append(app) }
        return parts.joined(separator: " · ")
    }
}
