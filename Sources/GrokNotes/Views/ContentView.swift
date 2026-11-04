import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var state: AppState
    @State private var searchText = ""

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            if state.showLibraryChat {
                LibraryChatView()
            } else if let id = state.selectedID, state.meeting(id) != nil {
                MeetingDetailView(meetingID: id).id(id)
            } else {
                EmptyStateView()
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

    private var filteredMeetings: [Meeting] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return state.meetings }
        return state.meetings.filter { m in
            m.title.lowercased().contains(query)
                || (m.enhancedNotes ?? m.userNotes).lowercased().contains(query)
                || m.attendees.contains { $0.lowercased().contains(query) }
                || m.speakers.values.contains { ($0.name ?? "").lowercased().contains(query) }
                || m.utterances.contains { $0.text.lowercased().contains(query) }
        }
    }

    private var sidebar: some View {
        List(selection: $state.selectedID) {
            Section {
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
            } else if filteredMeetings.isEmpty {
                Text("No meetings match “\(searchText)”.")
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            } else {
                Section("Meetings") {
                ForEach(filteredMeetings) { meeting in
                    MeetingRow(meeting: meeting)
                        .tag(meeting.id)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button("Delete", role: .destructive) {
                                state.delete(meeting.id)
                            }
                            .disabled(state.recordingID == meeting.id)
                        }
                        .contextMenu {
                            Button("Copy as Markdown") { state.copyMarkdown(meeting.id) }
                            Button("Show in Finder") { state.revealInFinder(meeting.id) }
                            Divider()
                            Button("Delete", role: .destructive) { state.delete(meeting.id) }
                                .disabled(state.recordingID == meeting.id)
                        }
                }
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
}

private struct MeetingRow: View {
    @EnvironmentObject private var state: AppState
    let meeting: Meeting

    var body: some View {
        HStack(spacing: GrokSpacing.sm) {
            rowIcon
            VStack(alignment: .leading, spacing: 2) {
                Text(meeting.title)
                    .lineLimit(1)
                    .font(.body)
                Text(GrokFormat.meetingSubtitle(date: meeting.startedAt, appName: meeting.appName))
                    .font(GrokTypography.captionMuted())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, GrokSpacing.xs)
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

private struct EmptyStateView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: GrokSpacing.xl) {
            Image(systemName: "note.text")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.tertiary)
                .symbolRenderingMode(.hierarchical)
            Text("Your notepad for calls")
                .font(GrokTypography.emptyStateTitle())
            Text("Start notes when a call begins. Type rough thoughts while you talk—Grok turns them into polished notes when you stop.")
                .font(GrokTypography.emptyStateBody())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            RecordButton().frame(width: 280)
            PermissionSummary()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PermissionSummary: View {
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
