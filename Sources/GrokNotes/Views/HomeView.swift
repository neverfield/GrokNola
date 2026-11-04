import SwiftUI

/// The landing page: this week at a glance, trends, recent meetings, and open action items.
struct HomeView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var usage: UsageLedger
    @EnvironmentObject private var catalog: TagCatalog
    @AppStorage("homeTrendDays") private var trendDays = 7
    @State private var question = ""
    @State private var listing: MeetingListing?
    /// Items checked off from Home this session, kept visible so they can be unchecked.
    @State private var completed: Set<String> = []
    @State private var showAllActions = false

    private static let maxWidth: CGFloat = 960
    private static let recentLimit = 6
    private static let actionLimit = 8

    var body: some View {
        let snapshot = HomeSnapshot(meetings: state.meetings, trendDays: trendDays, completed: completed, recentLimit: Self.recentLimit)
        ScrollView {
            VStack(alignment: .leading, spacing: GrokSpacing.xl) {
                header
                if state.meetings.isEmpty {
                    OnboardingCard()
                } else {
                    glance(snapshot)
                    recentMeetings(snapshot.recent)
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 360), spacing: GrokSpacing.lg, alignment: .top)],
                        alignment: .leading,
                        spacing: GrokSpacing.lg
                    ) {
                        actionItems(snapshot.actions)
                        trends(snapshot)
                        if !snapshot.decisions.isEmpty {
                            decisions(snapshot.decisions)
                        }
                    }
                }
            }
            .padding(GrokSpacing.xl)
            .frame(maxWidth: Self.maxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Home")
        .environment(\.openURL, OpenURLAction { url in
            if let target = Citations.target(from: url) {
                state.openTranscript(target.meetingID, at: target.seconds)
                return .handled
            }
            if let id = LibraryAsk.meetingID(from: url) {
                state.openMeeting(id)
                return .handled
            }
            return .systemAction
        })
        .sheet(item: $listing) { listing in
            MeetingListSheet(listing: listing) { id in
                self.listing = nil
                state.openMeeting(id)
            }
        }
        .onAppear { state.refreshPermissions() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: GrokSpacing.lg) {
            HStack(alignment: .center, spacing: GrokSpacing.lg) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(greeting)
                        .font(.largeTitle.weight(.semibold))
                    Text(Date().formatted(date: .complete, time: .omitted))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                recordControl
            }
            quickAsk
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let part = hour < 12 ? "Good morning" : (hour < 18 ? "Good afternoon" : "Good evening")
        guard let first = Prefs.myName.split(separator: " ").first, !first.isEmpty else { return part }
        return "\(part), \(first)"
    }

    @ViewBuilder
    private var recordControl: some View {
        if let id = state.recordingID {
            HStack(spacing: GrokSpacing.sm) {
                RecordingPulse()
                Text("Recording · \(Meeting.timestamp(state.elapsed))")
                    .monospacedDigit()
                Button("Open Live Notes") { state.openMeeting(id) }
                    .buttonStyle(.bordered)
            }
            .controlSize(.large)
        } else {
            Button {
                Task { await state.startMeeting() }
            } label: {
                Label(state.detectedApp.map { "Start notes · \($0.name)" } ?? "Start notes", systemImage: "record.circle")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .help("Start capturing notes for this meeting (Command-Shift-R)")
        }
    }

    private var quickAsk: some View {
        HStack(spacing: GrokSpacing.sm) {
            Image(systemName: "sparkle.magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Ask across your notes…", text: $question)
                .textFieldStyle(.plain)
                .onSubmit(ask)
            Button(action: ask) {
                Image(systemName: "arrow.up.circle.fill").font(.title2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(canAsk ? Color.accentColor : .secondary)
            .disabled(!canAsk)
            .help("Ask Grok across all meetings")
        }
        .padding(GrokSpacing.md)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
        .disabled(state.meetings.isEmpty)
    }

    private var canAsk: Bool {
        !state.libraryAsking && !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func ask() {
        guard canAsk else { return }
        state.askFromHome(question)
        question = ""
    }

    // MARK: This week

    private func glance(_ s: HomeSnapshot) -> some View {
        VStack(alignment: .leading, spacing: GrokSpacing.sm) {
            Text("This week")
                .font(GrokTypography.sectionTitle())
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: GrokSpacing.md)], spacing: GrokSpacing.md) {
                StatTile(
                    title: "Meetings", systemImage: "calendar",
                    value: "\(s.week.meetings)",
                    detail: "\(s.lastWeek.meetings) last week"
                )
                StatTile(
                    title: "In meetings", systemImage: "clock",
                    value: Self.hours(s.week.seconds),
                    detail: "\(Self.hours(s.lastWeek.seconds)) last week"
                )
                StatTile(
                    title: "Your talk time", systemImage: "waveform",
                    value: s.week.myShare.map { "\(Int(($0 * 100).rounded()))%" } ?? "—",
                    detail: s.week.myShare == nil ? "No transcripts yet" : "Share of everything said"
                )
                StatTile(
                    title: "API spend", systemImage: "dollarsign.circle",
                    value: usage.total(since: s.weekStart).usd,
                    detail: "Since \(s.weekStart.formatted(.dateTime.weekday(.wide)))"
                )
            }
        }
    }

    private static func hours(_ seconds: Double) -> String {
        if seconds < 3600 { return Meeting.durationLabel((seconds / 60).rounded() * 60) }
        return String(format: "%.1fh", seconds / 3600)
    }

    // MARK: Recent meetings

    private func recentMeetings(_ meetings: [Meeting]) -> some View {
        HomeCard(title: "Recent meetings", systemImage: "clock.arrow.circlepath") {
            VStack(spacing: 0) {
                ForEach(Array(meetings.enumerated()), id: \.element.id) { index, meeting in
                    if index > 0 { Divider().padding(.leading, 40) }
                    RecentMeetingRow(meeting: meeting)
                }
            }
        }
    }

    // MARK: Action items

    private func actionItems(_ items: [HomeActionItem]) -> some View {
        let open = items.filter { !$0.item.done }.count
        let shown = showAllActions ? items : Array(items.prefix(Self.actionLimit))
        return HomeCard(title: "Open action items", systemImage: "checklist", trailing: open > 0 ? "\(open)" : nil) {
            if items.isEmpty {
                Text("Nothing open from the last 30 days.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: GrokSpacing.md) {
                    ForEach(shown) { entry in
                        ActionItemRow(entry: entry, busy: state.processing.contains(entry.item.meetingID)) { done in
                            if done { completed.insert(entry.key) }
                            state.setActionItem(entry.item, done: done)
                        }
                    }
                    if items.count > Self.actionLimit {
                        Button(showAllActions ? "Show fewer" : "Show all \(items.count)") { showAllActions.toggle() }
                            .buttonStyle(.link)
                    }
                }
            }
        }
    }

    // MARK: Trends

    private func trends(_ s: HomeSnapshot) -> some View {
        HomeCard(title: "Trending topics", systemImage: "chart.line.uptrend.xyaxis") {
            VStack(alignment: .leading, spacing: GrokSpacing.md) {
                Picker("Window", selection: $trendDays) {
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()

                if s.topics.isEmpty {
                    Text("No topics in the last \(trendDays) days. Grok finds topics when it writes notes.")
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: GrokSpacing.xs) {
                        ForEach(Array(s.topics.prefix(8).enumerated()), id: \.element.id) { index, topic in
                            TrendRow(rank: index + 1, item: topic, days: trendDays) {
                                listing = MeetingListing(
                                    title: topic.name,
                                    subtitle: "Topic · last \(trendDays) days",
                                    meetings: s.meetings(since: s.trendStart, matching: topic.name) { $0.topics ?? [] }
                                )
                            }
                        }
                    }
                }

                if !s.tags.isEmpty {
                    Divider()
                    Text("Top tags")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    FlowLayout(spacing: GrokSpacing.sm) {
                        ForEach(s.tags.prefix(10)) { tag in
                            Button {
                                listing = MeetingListing(
                                    title: tag.name,
                                    subtitle: "Tag · last \(trendDays) days",
                                    meetings: s.meetings(since: s.trendStart, matching: tag.name) { $0.tagList }
                                )
                            } label: {
                                HStack(spacing: 3) {
                                    TagChip(name: tag.name, color: catalog.color(for: tag.name))
                                    Text("\(tag.count)")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .help("Show meetings tagged \(tag.name)")
                        }
                    }
                }
            }
        }
    }

    // MARK: Decisions

    private func decisions(_ items: [HomeDecision]) -> some View {
        HomeCard(title: "Recent decisions", systemImage: "checkmark.seal") {
            VStack(alignment: .leading, spacing: GrokSpacing.md) {
                ForEach(items) { d in
                    VStack(alignment: .leading, spacing: 2) {
                        HomeMarkdownText(text: d.text, meetingID: d.meetingID)
                        SourceLink(title: d.meetingTitle, date: d.date, meetingID: d.meetingID)
                    }
                }
            }
        }
    }
}

// MARK: - Snapshot

private struct HomeActionItem: Identifiable {
    var item: Insights.ActionItem
    var meetingTitle: String
    var date: Date
    var id: String { item.id }
    /// Survives the line being rewritten from unchecked to checked.
    var key: String { "\(item.meetingID.uuidString)|\(item.task)" }
}

private struct HomeDecision: Identifiable {
    var text: String
    var meetingID: UUID
    var meetingTitle: String
    var date: Date
    var id: String { "\(meetingID.uuidString)|\(text)" }
}

/// Everything the dashboard shows, computed once per body evaluation.
private struct HomeSnapshot {
    let all: [Meeting]
    let weekStart: Date
    let trendStart: Date
    var week = Insights.Glance()
    var lastWeek = Insights.Glance()
    var topics: [Insights.Trending] = []
    var tags: [Insights.Trending] = []
    var recent: [Meeting] = []
    var actions: [HomeActionItem] = []
    var decisions: [HomeDecision] = []

    init(meetings: [Meeting], trendDays: Int, completed: Set<String>, recentLimit: Int, now: Date = Date(), calendar: Calendar = .current) {
        let sorted = meetings.sorted { $0.startedAt > $1.startedAt }
        all = sorted
        let today = calendar.startOfDay(for: now)
        weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? today
        let lastWeekStart = calendar.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart
        week = Insights.glance(sorted, since: weekStart)
        lastWeek = Insights.glance(sorted, since: lastWeekStart, until: weekStart)

        trendStart = calendar.date(byAdding: .day, value: -trendDays, to: now) ?? now
        let previousStart = calendar.date(byAdding: .day, value: -trendDays, to: trendStart) ?? trendStart
        topics = Insights.trending(
            current: Insights.topicCounts(in: sorted, since: trendStart),
            previous: Insights.topicCounts(in: sorted, since: previousStart, until: trendStart)
        )
        tags = Insights.trending(
            current: Insights.tagCounts(in: sorted, since: trendStart),
            previous: Insights.tagCounts(in: sorted, since: previousStart, until: trendStart)
        )

        recent = Array(sorted.prefix(recentLimit))

        let monthStart = calendar.date(byAdding: .day, value: -30, to: now) ?? now
        let decisionStart = calendar.date(byAdding: .day, value: -14, to: now) ?? now
        for m in sorted where m.startedAt >= monthStart {
            guard let notes = m.enhancedNotes, !notes.isEmpty else { continue }
            for item in Insights.actionItems(in: notes, meetingID: m.id) {
                let entry = HomeActionItem(item: item, meetingTitle: m.title, date: m.startedAt)
                if !item.done || completed.contains(entry.key) { actions.append(entry) }
            }
            if m.startedAt >= decisionStart, decisions.count < 6 {
                for text in Insights.decisions(in: notes).prefix(6 - decisions.count) {
                    decisions.append(HomeDecision(text: text, meetingID: m.id, meetingTitle: m.title, date: m.startedAt))
                }
            }
        }
    }

    func meetings(since: Date, matching name: String, _ values: (Meeting) -> [String]) -> [Meeting] {
        all.filter { m in
            m.startedAt >= since && values(m).contains { $0.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(name) == .orderedSame }
        }
    }
}

// MARK: - Cards and rows

private struct HomeCard<Content: View>: View {
    let title: String
    let systemImage: String
    var trailing: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: GrokSpacing.md) {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(GrokTypography.sectionTitle())
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            content
        }
        .padding(GrokSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct StatTile: View {
    let title: String
    let systemImage: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: GrokSpacing.xs) {
            Label(title, systemImage: systemImage)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(detail)
                .font(GrokTypography.captionMuted())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(GrokSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

private struct RecentMeetingRow: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var catalog: TagCatalog
    let meeting: Meeting
    @State private var hovering = false

    var body: some View {
        Button {
            state.openMeeting(meeting.id)
        } label: {
            HStack(alignment: .top, spacing: GrokSpacing.md) {
                icon
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(meeting.title)
                            .font(.body.weight(.medium))
                            .lineLimit(1)
                        Spacer(minLength: GrokSpacing.sm)
                        Text(GrokFormat.relativeDay(meeting.startedAt))
                            .font(GrokTypography.captionMuted())
                            .foregroundStyle(.secondary)
                    }
                    Text(subtitle)
                        .font(GrokTypography.captionMuted())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let summary = summary {
                        Text(summary)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    if !meeting.tagList.isEmpty {
                        HStack(spacing: GrokSpacing.xs) {
                            ForEach(meeting.tagList.prefix(4), id: \.self) { tag in
                                TagChip(name: tag, color: catalog.color(for: tag), compact: true)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, GrokSpacing.sm)
            .padding(.horizontal, GrokSpacing.xs)
            .contentShape(Rectangle())
            .background(hovering ? Color.primary.opacity(0.05) : .clear, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Open \(meeting.title)")
    }

    private var summary: String? {
        if state.recordingID == meeting.id { return "Recording now." }
        if state.processing.contains(meeting.id) { return "Grok is writing the notes…" }
        return Insights.summary(of: meeting)
    }

    private var subtitle: String {
        var parts: [String] = []
        if let app = meeting.appName, !app.isEmpty { parts.append(app) }
        if meeting.duration > 0 { parts.append(Meeting.durationLabel(meeting.duration)) }
        let people = Insights.participants(of: meeting, myName: Prefs.myName)
        if !people.isEmpty {
            let shown = people.prefix(3).joined(separator: ", ")
            parts.append(people.count > 3 ? "\(shown) +\(people.count - 3)" : shown)
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var icon: some View {
        Group {
            if state.recordingID == meeting.id {
                RecordingPulse()
            } else if state.processing.contains(meeting.id) {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: MeetingAppIcon.symbol(for: meeting.appName))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 28, height: 28)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct ActionItemRow: View {
    let entry: HomeActionItem
    let busy: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: GrokSpacing.sm) {
            Button {
                onToggle(!entry.item.done)
            } label: {
                Image(systemName: entry.item.done ? "checkmark.square.fill" : "square")
                    .foregroundStyle(entry.item.done ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(busy)
            .help(busy ? "Grok is still writing these notes" : (entry.item.done ? "Mark as open" : "Mark as done"))
            .accessibilityLabel(entry.item.done ? "Mark as open" : "Mark as done")

            VStack(alignment: .leading, spacing: 2) {
                HomeMarkdownText(text: entry.item.task, meetingID: entry.item.meetingID, owner: entry.item.owner)
                    .strikethrough(entry.item.done)
                    .foregroundStyle(entry.item.done ? .secondary : .primary)
                SourceLink(title: entry.meetingTitle, date: entry.date, meetingID: entry.item.meetingID)
            }
        }
    }
}

/// One line of notes with working `[mm:ss]` citations.
private struct HomeMarkdownText: View {
    let text: String
    let meetingID: UUID
    var owner: String?

    var body: some View {
        var attributed = (try? AttributedString(markdown: Citations.linkify(text, meetingID: meetingID))) ?? AttributedString(text)
        let citations = attributed.runs.filter { $0.link.map { Citations.target(from: $0) != nil } ?? false }.map(\.range)
        for range in citations {
            attributed[range].font = GrokTypography.citation()
            attributed[range].baselineOffset = 2
        }
        if let owner {
            var name = AttributedString("\(owner): ")
            name.font = .body.weight(.semibold)
            attributed = name + attributed
        }
        return Text(attributed)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct SourceLink: View {
    @EnvironmentObject private var state: AppState
    let title: String
    let date: Date
    let meetingID: UUID

    var body: some View {
        Button {
            state.openMeeting(meetingID)
        } label: {
            Text("\(title) · \(GrokFormat.relativeDay(date))")
                .lineLimit(1)
        }
        .buttonStyle(.link)
        .font(GrokTypography.captionMuted())
    }
}

private struct TrendRow: View {
    let rank: Int
    let item: Insights.Trending
    let days: Int
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: GrokSpacing.sm) {
                Text("\(rank)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .frame(width: 18, alignment: .trailing)
                Text(item.name)
                    .lineLimit(1)
                Spacer()
                Text("\(item.count)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                trendBadge
                    .frame(width: 36, alignment: .trailing)
            }
            .padding(.vertical, 3)
            .padding(.horizontal, GrokSpacing.xs)
            .contentShape(Rectangle())
            .background(hovering ? Color.primary.opacity(0.05) : .clear, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("\(item.count) meetings in the last \(days) days, \(item.previous) in the \(days) days before")
    }

    @ViewBuilder
    private var trendBadge: some View {
        switch item.trend {
        case .new:
            Text("New")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.accentColor.opacity(0.15), in: Capsule())
                .foregroundStyle(Color.accentColor)
        case .up:
            Image(systemName: "arrow.up.right").foregroundStyle(.green)
        case .down:
            Image(systemName: "arrow.down.right").foregroundStyle(.orange)
        case .flat:
            Image(systemName: "minus").foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Meetings for a topic or tag

private struct MeetingListing: Identifiable {
    let id = UUID()
    var title: String
    var subtitle: String
    var meetings: [Meeting]
}

private struct MeetingListSheet: View {
    @Environment(\.dismiss) private var dismiss
    let listing: MeetingListing
    let onOpen: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(listing.title).font(.title3.weight(.semibold))
                Text("\(listing.subtitle) · \(listing.meetings.count == 1 ? "1 meeting" : "\(listing.meetings.count) meetings")")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(GrokSpacing.lg)
            Divider()
            List(listing.meetings) { m in
                Button {
                    onOpen(m.id)
                } label: {
                    HStack(spacing: GrokSpacing.sm) {
                        Image(systemName: MeetingAppIcon.symbol(for: m.appName))
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.title).lineLimit(1)
                            Text(GrokFormat.meetingSubtitle(date: m.startedAt, appName: m.appName))
                                .font(GrokTypography.captionMuted())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(GrokSpacing.md)
        }
        .frame(width: 440, height: 420)
    }
}

// MARK: - First run

private struct OnboardingCard: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: GrokSpacing.lg) {
            Label("Welcome to Grok Notes", systemImage: "note.text")
                .font(.title2.weight(.semibold))
            Text("Start notes when a call begins. Type rough thoughts while you talk, and Grok turns them into polished notes, action items, and topics when you stop. This page fills in as you record meetings.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            PermissionSummary()
            if state.recordingID == nil {
                Button {
                    Task { await state.startMeeting() }
                } label: {
                    Label("Start notes", systemImage: "record.circle")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(GrokSpacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }
}
