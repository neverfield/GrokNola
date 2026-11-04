import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        NavigationSplitView {
            List(selection: $state.selectedID) {
                ForEach(state.meetings) { meeting in
                    MeetingRow(meeting: meeting)
                        .tag(meeting.id)
                        .contextMenu {
                            Button("Copy as Markdown") { state.copyMarkdown(meeting.id) }
                            Button("Show in Finder") { state.revealInFinder(meeting.id) }
                            Divider()
                            Button("Delete", role: .destructive) { state.delete(meeting.id) }
                                .disabled(state.recordingID == meeting.id)
                        }
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
            .safeAreaInset(edge: .bottom) {
                RecordButton().padding(10)
            }
        } detail: {
            if let id = state.selectedID, state.meeting(id) != nil {
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
        .onAppear { state.refreshPermissions() }
    }
}

private struct MeetingRow: View {
    @EnvironmentObject private var state: AppState
    let meeting: Meeting

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if state.recordingID == meeting.id {
                    Image(systemName: "record.circle.fill").foregroundStyle(.red)
                } else if state.processing.contains(meeting.id) {
                    ProgressView().controlSize(.small)
                }
                Text(meeting.title).lineLimit(1)
            }
            Text(meeting.startedAt.formatted(date: .abbreviated, time: .shortened) + (meeting.appName.map { " · \($0)" } ?? ""))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
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
            .buttonStyle(.borderedProminent)
            .tint(.red)
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
        .padding(10)
        .background(.bar)
    }
}

private struct EmptyStateView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform").font(.system(size: 48)).foregroundStyle(.secondary)
            Text("Grok Notes").font(.largeTitle).bold()
            Text("Start notes when a call begins. Type rough notes while you talk, and Grok writes the rest.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            RecordButton().frame(width: 260)
            PermissionSummary()
        }
        .padding(40)
    }
}

private struct PermissionSummary: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        let p = state.permissions
        let hasKey = XAIClient.storedAPIKey() != nil
        VStack(alignment: .leading, spacing: 6) {
            row("xAI API key", hasKey, "Required")
            row("Microphone", p.microphone, "Required")
            row("Screen & System Audio Recording", p.systemAudio, "Separates you from the other side")
            row("Accessibility", p.accessibility, "Reads who is talking in Zoom, Teams, Meet, and Slack")
            row("Calendar", p.calendar, "Titles and invitee names")
            SettingsLink { Text("Open Settings") }.padding(.top, 4)
        }
        .font(.callout)
        .padding()
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private func row(_ title: String, _ ok: Bool, _ detail: String) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle").foregroundStyle(ok ? .green : .secondary)
            Text(title)
            Text("· \(detail)").foregroundStyle(.secondary)
        }
    }
}
