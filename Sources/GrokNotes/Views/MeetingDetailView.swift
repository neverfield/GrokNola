import SwiftUI

struct MeetingDetailView: View {
    @EnvironmentObject private var state: AppState
    let meetingID: UUID
    @State private var tab: Tab = .notes
    @State private var showInspector = false

    enum Tab: String, CaseIterable {
        case notes = "Notes"
        case transcript = "Transcript"
        case ask = "Ask Grok"
    }

    var body: some View {
        if state.meeting(meetingID) != nil {
            NavigationStack {
                VStack(alignment: .leading, spacing: 0) {
                    Picker("", selection: $tab) {
                        ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .padding(.horizontal, GrokSpacing.lg)
                    .padding(.vertical, GrokSpacing.sm)

                    switch tab {
                    case .notes: NotesTab(meetingID: meetingID)
                    case .transcript: TranscriptTab(meetingID: meetingID)
                    case .ask: AskTab(meetingID: meetingID)
                    }
                }
                .navigationTitle("")
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        TextField("Title", text: state.titleBinding(meetingID))
                            .textFieldStyle(.plain)
                            .font(GrokTypography.meetingTitle())
                            .frame(minWidth: 200, maxWidth: 420)
                    }
                    ToolbarItemGroup(placement: .automatic) {
                        if state.recordingID == meetingID {
                            HStack(spacing: GrokSpacing.xs) {
                                RecordingPulse()
                                Text(Meeting.timestamp(state.elapsed))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showInspector.toggle()
                        } label: {
                            Label("Meeting info", systemImage: "info.circle")
                        }
                        .help("Tags, speakers, attendees, and attribution")
                    }
                }
                .inspector(isPresented: $showInspector) {
                    MeetingInspectorView(meetingID: meetingID)
                }
            }
        }
    }
}

struct MeetingInspectorView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var usage: UsageLedger
    let meetingID: UUID

    var body: some View {
        if let meeting = state.meeting(meetingID) {
            Form {
                Section("When") {
                    LabeledContent("Started") {
                        Text(meeting.startedAt.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let app = meeting.appName {
                        LabeledContent("App") { Text(app) }
                    }
                    if let ended = meeting.endedAt {
                        LabeledContent("Ended") {
                            Text(ended.formatted(date: .abbreviated, time: .shortened))
                        }
                    }
                }

                Section("Tags") {
                    MeetingTagsEditor(meetingID: meetingID)
                }

                Section("Attribution") {
                    LabeledContent("Mode") {
                        Text(meeting.mode.label)
                            .help(modeHelp(meeting.mode))
                    }
                    let cost = usage.total(for: meetingID)
                    if cost > 0 {
                        LabeledContent("API cost") { Text(cost.usd).monospacedDigit() }
                    }
                }

                if !meeting.attendees.isEmpty {
                    Section("Invitees") {
                        ForEach(meeting.attendees, id: \.self) { name in
                            Text(name)
                        }
                    }
                }

                if !meeting.speakerKeys.isEmpty {
                    Section("Speakers") {
                        Text("Click a name to rename.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(meeting.speakerKeys, id: \.self) { key in
                            SpeakerChip(meetingID: meetingID, key: key, showDetail: true)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .inspectorColumnWidth(min: 260, ideal: 300, max: 360)
        }
    }

    private func modeHelp(_ mode: AttributionMode) -> String {
        switch mode {
        case .detecting: return "Names are matched while you talk and again when the meeting ends."
        case .named: return "At least one remote speaker has a real name."
        case .meThem: return "No reliable names were found. Click Them to name a speaker."
        case .micOnly: return "System audio was not available."
        }
    }
}

enum SpeakerColor {
    private static let palette: [Color] = [.blue, .orange, .purple, .pink, .teal, .indigo, .brown, .mint, .cyan, .red]

    static func color(for key: String) -> Color {
        if key == Meeting.meKey { return .green }
        let hash = key.utf8.reduce(5381) { ($0 &* 33) &+ Int($1) }
        return palette[abs(hash) % palette.count]
    }
}

struct SpeakerChip: View {
    @EnvironmentObject private var state: AppState
    let meetingID: UUID
    let key: String
    var showDetail = false
    @State private var editing = false

    var body: some View {
        let meeting = state.meeting(meetingID)
        let info = meeting?.speakers[key]
        let color = SpeakerColor.color(for: key)
        Button {
            editing = true
        } label: {
            HStack(spacing: GrokSpacing.xs) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(meeting?.displayName(for: key, myName: Prefs.myName) ?? key).fontWeight(.medium)
                if showDetail, let info {
                    Text(detail(info)).foregroundStyle(.secondary)
                }
            }
            .font(.callout)
            .padding(.horizontal, GrokSpacing.sm)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
        }
        .buttonStyle(.plain)
        .help(info?.evidence ?? "Click to name this speaker")
        .popover(isPresented: $editing) {
            RenameSpeakerView(meetingID: meetingID, key: key, initial: info?.name ?? "") { editing = false }
        }
    }

    private func detail(_ info: SpeakerInfo) -> String {
        guard let confidence = info.confidence, [.inferred, .activeSpeaker, .onScreen].contains(info.attribution) else {
            return info.attribution.label
        }
        return "\(info.attribution.label) \(Int(confidence * 100))%"
    }
}

private struct RenameSpeakerView: View {
    @EnvironmentObject private var state: AppState
    let meetingID: UUID
    let key: String
    let initial: String
    let done: () -> Void
    @State private var name = ""

    var body: some View {
        let suggestions = uniqueNames((state.meeting(meetingID)?.attendees ?? []) + Prefs.knownPeople.reversed()).prefix(8)
        VStack(alignment: .leading, spacing: GrokSpacing.sidebarInset) {
            Text("Who is this?").font(.headline)
            TextField("Name", text: $name).onSubmit(save).frame(width: 240)
            if !suggestions.isEmpty {
                FlowButtons(names: Array(suggestions)) { name = $0; save() }
            }
            HStack {
                Button("Clear name") { name = ""; save() }
                Spacer()
                Button("Save", action: save).keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .onAppear { name = initial }
    }

    private func save() {
        state.renameSpeaker(meetingID, key: key, to: name)
        done()
    }
}

private struct FlowButtons: View {
    let names: [String]
    let pick: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: GrokSpacing.xs) {
            ForEach(names, id: \.self) { name in
                Button(name) { pick(name) }.buttonStyle(.link)
            }
        }
    }
}
