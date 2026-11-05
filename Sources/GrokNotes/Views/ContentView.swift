import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var catalog: TagCatalog
    @Environment(\.undoManager) private var undoManager
    @State private var searchText = ""
    @State private var tagFilter: String?
    @State private var searchIndex = MeetingSearchIndex()
    @State private var sidebarCache = SidebarCache()
    @Environment(\.openWindow) private var openWindow
    /// Newline-separated ids of collapsed sidebar sections. Sections are expanded by default.
    @AppStorage("sidebarCollapsedSections") private var collapsedSections = ""
    private static let visibleTagLimit = 6

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            switch state.route {
            case .home: HomeView()
            case .library: LibraryChatView()
            case .meeting(let id): MeetingDetailView(meetingID: id).id(id)
            }
        }
        .overlay(alignment: .bottom) {
            TrashToast(trash: state.trash) { state.undoTrash($0, undoManager: undoManager) }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            BannerStack()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if state.recordingID != nil {
                RecordingStatusBar()
            }
        }
        .onAppear {
            state.refreshPermissions()
            state.notifications.openMainWindow = { [openWindow] in openWindow(id: "main") }
        }
        .onChange(of: state.selectedID) {
            if state.selectedID != nil { state.showLibraryChat = false }
        }
    }

    /// Filters and groups only when the meetings, the search, or the tag filter changed.
    private func sidebarContent() -> SidebarContent {
        sidebarCache.content(
            meetings: state.meetings,
            revision: state.meetingsRevision,
            search: searchText,
            tagFilter: tagFilter,
            index: searchIndex
        )
    }

    private var collapsedSet: Set<String> {
        Set(collapsedSections.split(separator: "\n").map(String.init))
    }

    /// Sections stay open while filtering so matches are never hidden.
    private func expansion(_ id: String, forceOpen: Bool) -> Binding<Bool> {
        Binding(
            get: { forceOpen || !collapsedSet.contains(id) },
            set: { expanded in
                var set = collapsedSet
                if expanded { set.remove(id) } else { set.insert(id) }
                collapsedSections = set.sorted().joined(separator: "\n")
            }
        )
    }

    private var sidebar: some View {
        let content = sidebarContent()
        return List(selection: $state.selectedID) {
            Section {
                let atHome = state.route == .home
                Button {
                    state.openHome()
                } label: {
                    Label("Home", systemImage: "house")
                        .fontWeight(atHome ? .semibold : .regular)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, GrokSpacing.xs)
                .listRowBackground(atHome ? Color.accentColor.opacity(0.15) : Color.clear)
                .help("Your week at a glance (Command-Shift-H)")
                Button {
                    state.openLibraryChat()
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Ask Grok")
                                .fontWeight(state.showLibraryChat ? .semibold : .regular)
                            Text("Meetings and app help")
                                .font(GrokTypography.captionMuted())
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "sparkle.magnifyingglass")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, GrokSpacing.xs)
                .listRowBackground(state.showLibraryChat ? Color.accentColor.opacity(0.15) : Color.clear)
                .help("Your meetings and how Grok Notes works (Command-K)")
            }
            if state.meetings.isEmpty {
                ContentUnavailableView {
                    Label("No meetings yet", systemImage: "note.text")
                } description: {
                    Text("Start notes when a call begins. Your rough notes guide what Grok writes.")
                }
                .listRowBackground(Color.clear)
            } else {
                if !content.tagCounts.isEmpty {
                    tagsSection(content.tagCounts)
                }
                if content.isFiltering {
                    filterSummary(count: content.resultCount)
                }
                if content.resultCount == 0 {
                    Text(searchText.isEmpty ? "No meetings have this tag." : "No meetings match “\(searchText)”.")
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
                if !content.pinned.isEmpty {
                    meetingSection(id: "pinned", title: "Pinned", meetings: content.pinned, dateStyle: .relative, forceOpen: content.isFiltering)
                }
                ForEach(content.groups) { group in
                    meetingSection(id: group.id, title: group.title, meetings: group.meetings, dateStyle: group.dateStyle, forceOpen: content.isFiltering)
                }
            }
        }
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search meetings")
        .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if state.recordingID == nil {
                    Button {
                        Task { await state.startMeeting() }
                    } label: {
                        Label(
                            state.detectedApp.map { "Start · \($0.name)" } ?? "Start notes",
                            systemImage: "record.circle"
                        )
                    }
                    .help("Start capturing notes for this meeting")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if state.recordingID == nil {
                StartNotesBar()
            }
        }
    }

    private func meetingSection(id: String, title: String, meetings: [Meeting], dateStyle: SidebarDateStyle, forceOpen: Bool) -> some View {
        Section(isExpanded: expansion(id, forceOpen: forceOpen)) {
            ForEach(meetings) { meeting in
                MeetingRow(meeting: meeting, dateStyle: dateStyle)
                    .tag(meeting.id)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Delete", role: .destructive) {
                            state.moveToTrash(meeting.id, undoManager: undoManager)
                        }
                        .disabled(state.recordingID == meeting.id)
                    }
                    .swipeActions(edge: .leading) {
                        Button(meeting.isPinned ? "Unpin" : "Pin") { state.togglePin(meeting.id) }
                            .tint(.orange)
                    }
                    .contextMenu { MeetingContextMenu(meeting: meeting) }
            }
        } header: {
            HStack(spacing: GrokSpacing.xs) {
                Text(title)
                Text("\(meetings.count)")
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func tagsSection(_ tagCounts: [(name: String, count: Int)]) -> some View {
        var shown = Array(tagCounts.prefix(Self.visibleTagLimit))
        if let tagFilter, !shown.contains(where: { $0.name.caseInsensitiveCompare(tagFilter) == .orderedSame }),
           let active = tagCounts.first(where: { $0.name.caseInsensitiveCompare(tagFilter) == .orderedSame }) {
            shown.append(active)
        }
        let rest = tagCounts.filter { tag in !shown.contains { $0.name == tag.name } }
        return Section(isExpanded: expansion("tags", forceOpen: false)) {
            ForEach(shown, id: \.name) { tag in
                tagFilterRow(tag.name, count: tag.count)
            }
            if !rest.isEmpty {
                Menu("\(rest.count) more tags") {
                    ForEach(rest, id: \.name) { tag in
                        Button("\(tag.name) (\(tag.count))") { tagFilter = tag.name }
                    }
                }
                .menuStyle(.borderlessButton)
                .foregroundStyle(.secondary)
            }
        } header: {
            Text("Tags")
        }
    }

    private func tagFilterRow(_ name: String, count: Int) -> some View {
        let active = tagFilter?.caseInsensitiveCompare(name) == .orderedSame
        return Button {
            tagFilter = active ? nil : name
        } label: {
            HStack(spacing: GrokSpacing.sm) {
                Circle().fill(catalog.color(for: name)).frame(width: 8, height: 8)
                Text(name)
                    .lineLimit(1)
                    .fontWeight(active ? .semibold : .regular)
                Spacer()
                Text("\(count)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(active ? Color.accentColor.opacity(0.15) : Color.clear)
        .help(active ? "Show all meetings" : "Show meetings tagged \(name)")
    }

    private func filterSummary(count: Int) -> some View {
        HStack(spacing: GrokSpacing.xs) {
            Text(count == 1 ? "1 meeting" : "\(count) meetings")
                .font(GrokTypography.captionMuted())
                .foregroundStyle(.secondary)
            if let tagFilter {
                TagChip(name: tagFilter, color: catalog.color(for: tagFilter), compact: true) { self.tagFilter = nil }
            }
            Spacer()
            Button("Clear") {
                tagFilter = nil
                searchText = ""
            }
            .buttonStyle(.link)
            .font(GrokTypography.captionMuted())
        }
        .listRowBackground(Color.clear)
    }
}

private struct MeetingContextMenu: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var catalog: TagCatalog
    @Environment(\.undoManager) private var undoManager
    let meeting: Meeting

    var body: some View {
        Button(meeting.isPinned ? "Unpin" : "Pin") { state.togglePin(meeting.id) }
        Menu("Tags") {
            ForEach(catalog.tags) { tag in
                Toggle(tag.name, isOn: Binding(
                    get: { meeting.hasTag(tag.name) },
                    set: { _ in state.toggleTag(tag.name, on: meeting.id) }
                ))
            }
            if !catalog.tags.isEmpty { Divider() }
            Button("Suggest Tags") { Task { await state.suggestTags(meeting.id) } }
                .disabled(catalog.tagging.contains(meeting.id) || state.processing.contains(meeting.id))
        }
        Divider()
        Button("Copy as Markdown") { state.copyMarkdown(meeting.id) }
        Button("Show in Finder") { state.revealInFinder(meeting.id) }
        Divider()
        Button("Delete", role: .destructive) { state.moveToTrash(meeting.id, undoManager: undoManager) }
            .disabled(state.recordingID == meeting.id)
    }
}

private struct MeetingRow: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var catalog: TagCatalog
    let meeting: Meeting
    let dateStyle: SidebarDateStyle
    private static let maxTags = 2

    var body: some View {
        HStack(spacing: GrokSpacing.sm) {
            rowIcon
            VStack(alignment: .leading, spacing: 2) {
                Text(meeting.title)
                    .lineLimit(1)
                    .font(.body)
                HStack(spacing: GrokSpacing.xs) {
                    Text(subtitle)
                        .font(GrokTypography.captionMuted())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .layoutPriority(1)
                    ForEach(meeting.tagList.prefix(Self.maxTags), id: \.self) { tag in
                        TagChip(name: tag, color: catalog.color(for: tag), compact: true)
                    }
                    if meeting.tagList.count > Self.maxTags {
                        Text("+\(meeting.tagList.count - Self.maxTags)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, GrokSpacing.xs)
        .help(meeting.tagList.isEmpty ? meeting.title : "\(meeting.title)\nTags: \(meeting.tagList.joined(separator: ", "))")
    }

    private var subtitle: String {
        let date = dateStyle.format(meeting.startedAt)
        if let app = meeting.appName, !app.isEmpty { return "\(date) · \(app)" }
        return date
    }

    @ViewBuilder
    private var rowIcon: some View {
        if state.recordingID == meeting.id {
            RecordingPulse()
                .frame(width: 28, height: 28)
        } else if state.processing.contains(meeting.id) {
            ProgressView()
                .controlSize(.small)
                .frame(width: 28, height: 28)
        } else {
            Image(systemName: MeetingAppIcon.symbol(for: meeting.appName))
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
        }
    }
}

/// Compact start control at the bottom of the sidebar when idle.
struct StartNotesBar: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Button {
            Task { await state.startMeeting() }
        } label: {
            Label(
                state.detectedApp.map { "Start notes · \($0.name)" } ?? "Start notes",
                systemImage: "record.circle"
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .padding(GrokSpacing.sidebarInset)
    }
}

/// Recording status while a meeting is active: the clock, live input levels, stream health, and Stop.
/// It observes neither the clock nor the levels itself; the small views inside do.
struct RecordingStatusBar: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        HStack(spacing: GrokSpacing.md) {
            RecordingPulse()
            RecordingElapsedText()
                .font(.body.monospacedDigit())
                .foregroundStyle(.primary)
            Text("Recording")
                .font(GrokTypography.captionMuted())
                .foregroundStyle(.secondary)

            Spacer()

            InputMeters(levels: state.recording.levels)

            Button {
                Task { await state.stopMeeting() }
            } label: {
                Label("Stop & Write Notes", systemImage: "stop.fill")
            }
            .buttonStyle(.bordered)
            .tint(GrokColors.recording)
            .help("Stop recording and write notes (Command-Shift-R)")
        }
        .padding(.horizontal, GrokSpacing.lg)
        .padding(.vertical, GrokSpacing.sm)
        .background(.bar)
    }
}

/// Stream reconnect messages and the mic and call-audio meters.
private struct InputMeters: View {
    @ObservedObject var levels: InputLevels

    var body: some View {
        HStack(spacing: GrokSpacing.md) {
            if let status = levels.system.streamStatus ?? levels.mic.streamStatus {
                Label(status, systemImage: "arrow.triangle.2.circlepath")
                    .font(GrokTypography.captionMuted())
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(status)
            }
            InputMeter(
                label: "Microphone", systemImage: "mic.fill", offImage: "mic.slash.fill", source: levels.mic,
                activeHelp: "Your microphone", offHelp: "The microphone is not recording."
            )
            InputMeter(
                label: "Call audio", systemImage: "speaker.wave.2.fill", offImage: "speaker.slash.fill", source: levels.system,
                activeHelp: "Audio from the meeting app",
                offHelp: "System audio is off, so only the microphone is recorded. Allow Screen & System Audio Recording to separate the other side."
            )
        }
    }
}

/// The recording clock. Only this text observes the once-a-second tick.
struct RecordingElapsedText: View {
    @EnvironmentObject private var recording: RecordingModel
    var prefix = ""

    var body: some View {
        Text(prefix + Meeting.timestamp(recording.elapsed))
    }
}

/// A source icon and a five-bar level meter. Orange when the source looks silent or its stream is reconnecting.
private struct InputMeter: View {
    let label: String
    let systemImage: String
    let offImage: String
    let source: InputLevels.Source
    let activeHelp: String
    let offHelp: String
    private static let bars = 5

    var body: some View {
        let warning = source.warning ?? source.streamStatus
        HStack(spacing: 4) {
            Image(systemName: source.active ? systemImage : offImage)
                .foregroundStyle(warning != nil ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.secondary))
            if source.active {
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(0..<Self.bars, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(barColor(lit: source.level >= Double(i + 1) / Double(Self.bars + 1), warning: warning != nil))
                            .frame(width: 3, height: 4 + CGFloat(i) * 2.5)
                    }
                }
                .frame(height: 14, alignment: .bottom)
            }
        }
        .contentShape(Rectangle())
        .help(warning ?? (source.active ? activeHelp : offHelp))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(warning ?? (source.active ? "Level \(Int(source.level * 100)) percent" : "Off"))
    }

    private func barColor(lit: Bool, warning: Bool) -> Color {
        guard lit else { return Color.secondary.opacity(0.25) }
        return warning ? .orange : .green
    }
}

/// Up to two banners across the top of the window, newest last, with a count of older ones.
private struct BannerStack: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let maxVisible = 2

    var body: some View {
        let visible = Array(state.banners.suffix(Self.maxVisible))
        let hidden = state.banners.count - visible.count
        VStack(spacing: 0) {
            if hidden > 0 {
                HStack {
                    Text(hidden == 1 ? "1 more message" : "\(hidden) more messages")
                        .font(GrokTypography.captionMuted())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Dismiss All") { state.dismissAllBanners() }
                        .buttonStyle(.link)
                        .font(GrokTypography.captionMuted())
                }
                .padding(.horizontal, GrokSpacing.sidebarInset)
                .padding(.vertical, GrokSpacing.xs)
                .background(.bar)
            }
            ForEach(visible) { item in
                BannerView(item: item) { state.dismissBanner(item.id) }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: state.banners.map(\.id))
    }
}

private struct BannerView: View {
    let item: BannerItem
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: GrokSpacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(item.message)
                .font(.callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: GrokSpacing.sm)
            if let action = item.action {
                Button(action.label) {
                    action.perform()
                    onClose()
                }
                .controlSize(.small)
            }
            Button(action: onClose) { Image(systemName: "xmark") }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Close")
        }
        .padding(GrokSpacing.sidebarInset)
        .background(tint.opacity(item.severity == .info ? 0.06 : 0.12))
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .contain)
    }

    private var icon: String {
        switch item.severity {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    private var tint: Color {
        switch item.severity {
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }
}

struct PermissionSummary: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        let p = state.permissions
        let hasKey = XAIClient.storedAPIKey() != nil
        VStack(alignment: .leading, spacing: GrokSpacing.sm) {
            row("xAI API key", hasKey, "Required")
            row("Microphone", p.microphone, "Required")
            row("Screen & System Audio Recording", p.systemAudio, "Separates you from the other side")
            row("Accessibility", p.accessibility, "Reads who is talking in Zoom, Teams, Meet, and Slack")
            row("Calendar", p.calendar || p.calendarFile, p.calendarFile ? "Google via Cursor (calendar.json)" : "Titles and invitee names")
            SettingsLink { Text("Open Settings") }.padding(.top, GrokSpacing.xs)
        }
        .font(.callout)
        .padding(GrokSpacing.lg)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }

    private func row(_ title: String, _ ok: Bool, _ detail: String) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle").foregroundStyle(ok ? .green : .secondary)
            Text(title)
            Text("· \(detail)").foregroundStyle(.secondary)
        }
    }
}
