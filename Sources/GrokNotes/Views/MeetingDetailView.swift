import SwiftUI

struct MeetingDetailView: View {
    @EnvironmentObject private var state: AppState
    let meetingID: UUID
    @State private var tab: Tab = .notes

    enum Tab: String, CaseIterable {
        case notes = "Notes"
        case transcript = "Transcript"
        case ask = "Ask Grok"
    }

    var body: some View {
        if let meeting = state.meeting(meetingID) {
            VStack(alignment: .leading, spacing: 0) {
                header(meeting)
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal)
                .padding(.bottom, 8)
                Divider()
                switch tab {
                case .notes: NotesTab(meetingID: meetingID)
                case .transcript: TranscriptTab(meetingID: meetingID)
                case .ask: AskTab(meetingID: meetingID)
                }
            }
        }
    }

    private func header(_ meeting: Meeting) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Title", text: state.titleBinding(meetingID))
                .textFieldStyle(.plain)
                .font(.title2.bold())
            HStack(spacing: 8) {
                Text(meeting.startedAt.formatted(date: .abbreviated, time: .shortened))
                if let app = meeting.appName { Text("· \(app)") }
                if !meeting.attendees.isEmpty {
                    Text("· \(meeting.attendees.count) invited").help(meeting.attendees.joined(separator: ", "))
                }
                MeetingCostLabel(meetingID: meetingID)
                ModeBadge(mode: meeting.mode)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            if !meeting.speakerKeys.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(meeting.speakerKeys, id: \.self) { key in
                            SpeakerChip(meetingID: meetingID, key: key, showDetail: true)
                        }
                    }
                }
            }
        }
        .padding()
    }
}

private struct ModeBadge: View {
    let mode: AttributionMode

    var body: some View {
        Text(mode.label)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
            .help(help)
    }

    private var help: String {
        switch mode {
        case .detecting: return "Names are matched while you talk and again when the meeting ends."
        case .named: return "At least one remote speaker has a real name. Click a name to fix it."
        case .meThem: return "No reliable names were found. Click Them to name a speaker."
        case .micOnly: return "System audio was not available, so speakers come from the microphone alone."
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
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(meeting?.displayName(for: key, myName: Prefs.myName) ?? key).fontWeight(.medium)
                if showDetail, let info {
                    Text(detail(info)).foregroundStyle(.secondary)
                }
            }
            .font(.callout)
            .padding(.horizontal, 8)
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
        VStack(alignment: .leading, spacing: 10) {
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
        VStack(alignment: .leading, spacing: 4) {
            ForEach(names, id: \.self) { name in
                Button(name) { pick(name) }.buttonStyle(.link)
            }
        }
    }
}
