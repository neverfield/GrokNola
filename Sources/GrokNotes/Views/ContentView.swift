import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var catalog: TagCatalog
    @State private var searchText = ""
    @State private var tagFilter: String?
    @State private var searchIndex = MeetingSearchIndex()
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
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                if let banner = state.banner {
                    BannerView(text: banner, isError: true) { state.banner = nil }
                }
                if let status = state.streamStatus {
                    BannerView(text: status, isError: false, onClose: nil)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if state.recordingID != nil {
                RecordingStatusBar()
            }
        }
        .onAppear { state.refreshPermissions() }
        .onChange(of: state.selectedID) {
            if state.selectedID != nil { state.showLibraryChat = false }
        }
    }

    private struct SidebarContent {
        var pinned: [Meeting]
        var groups: [MeetingGroup]
        var resultCount: Int
        var isFiltering: Bool
        var tagCounts: [(name: String, count: Int)]
    }

    /// Filters and groups once per body evaluation.
    private func sidebarContent() -> SidebarContent {
        let terms = MeetingSearchIndex.terms(searchText)
        var visible = state.meetings
        if let tagFilter { visible = visible.filter { $0.hasTag(tagFilter) } }
        if !terms.isEmpty { visible = visible.filter { searchIndex.matches($0, terms: terms) } }
        let pinned = visible.filter(\.isPinned).sorted { $0.startedAt > $1.startedAt }
        let groups = MeetingGrouping.groups(visible.filter { !$0.isPinned })

        var counts: [String: (name: String, count: Int)] = [:]
        for m in state.meetings {
            for tag in m.tagList {
                let key = tag.lowercased()
                counts[key] = (counts[key]?.name ?? tag, (counts[key]?.count ?? 0) + 1)
            }
        }
        let tagCounts = counts.values.sorted {
            $0.count != $1.count ? $0.count > $1.count : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        return SidebarContent(
            pinned: pinned,
            groups: groups,
            resultCount: visible.count,
            isFiltering: tagFilter != nil || !terms.isEmpty,
            tagCounts: tagCounts
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
                    Label("Ask across notes", systemImage: "sparkle.magnifyingglass")
                        .fontWeight(state.showLibraryChat ? .semibold : .regular)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, GrokSpacing.xs)
                .listRowBackground(state.showLibraryChat ? Color.accentColor.opacity(0.15) : Color.clear)
                .help("Ask Grok about all your meetings (Command-K)")
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
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button("Delete", role: .destructive) {
                            state.delete(meeting.id)
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
        Button("Delete", role: .destructive) { state.delete(meeting.id) }
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

/// Recording status while a meeting is active (sidebar + global inset).
struct RecordingStatusBar: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        HStack(spacing: GrokSpacing.md) {
            RecordingPulse()
            Text(Meeting.timestamp(state.elapsed))
                .font(.body.monospacedDigit())
                .foregroundStyle(.primary)
            Text("Recording")
                .font(GrokTypography.captionMuted())
                .foregroundStyle(.secondary)

            Spacer()

            HStack(spacing: GrokSpacing.sm) {
                Label("Mic", systemImage: "mic.fill")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
                    .help("Microphone capture")
                if state.permissions.systemAudio {
                    Label("System", systemImage: "speaker.wave.2.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.secondary)
                        .help("System audio capture")
                }
            }

            Button {
                Task { await state.stopMeeting() }
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            .buttonStyle(.bordered)
            .tint(GrokColors.recording)
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .accessibilityLabel("Stop recording and write notes")
        }
        .padding(.horizontal, GrokSpacing.lg)
        .padding(.vertical, GrokSpacing.sm)
        .background(.bar)
    }
}

struct RecordButton: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        if state.recordingID != nil {
            Button {
                Task { await state.stopMeeting() }
            } label: {
                Label("Stop · \(Meeting.timestamp(state.elapsed))", systemImage: "stop.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(GrokColors.recording)
            .controlSize(.large)
        } else {
            Button {
                Task { await state.startMeeting() }
            } label: {
                Label(state.detectedApp.map { "Start notes · \($0.name)" } ?? "Start notes", systemImage: "record.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
}

private struct BannerView: View {
    let text: String
    let isError: Bool
    let onClose: (() -> Void)?

    var body: some View {
        HStack(alignment: .top) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundStyle(isError ? .orange : .blue)
            Text(text).font(.callout).textSelection(.enabled)
            Spacer()
            if let onClose {
                Button(action: onClose) { Image(systemName: "xmark") }.buttonStyle(.plain)
            }
        }
        .padding(GrokSpacing.sidebarInset)
        .background(.bar)
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
            row("Calendar", p.calendar, "Titles and invitee names")
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
