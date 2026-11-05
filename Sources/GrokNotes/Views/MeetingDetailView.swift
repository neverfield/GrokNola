import SwiftUI

/// What the menu bar can do to the meeting on screen. Published by `MeetingDetailView` while it is shown.
struct MeetingActions {
    var selectTab: (MeetingDetailView.Tab) -> Void
    var toggleInspector: () -> Void
    var copyMarkdown: () -> Void
    /// Nil while it cannot run, for example while recording or writing notes.
    var regenerate: (() -> Void)?
    var findInTranscript: (() -> Void)?
}

private struct MeetingActionsKey: FocusedValueKey {
    typealias Value = MeetingActions
}

extension FocusedValues {
    var meetingActions: MeetingActions? {
        get { self[MeetingActionsKey.self] }
        set { self[MeetingActionsKey.self] = newValue }
    }
}

struct MeetingDetailView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var liveAnswers: LiveAnswersEngine
    @Environment(\.undoManager) private var undoManager
    let meetingID: UUID
    @State private var tab: Tab = .notes
    @State private var showInspector = false
    @State private var pane: InspectorPane = .info
    @State private var editingNotes = false
    @State private var findRequested = false

    enum Tab: String, CaseIterable {
        case notes = "Notes"
        case transcript = "Transcript"
        case ask = "Ask"
    }

    var body: some View {
        if let meeting = state.meeting(meetingID) {
            NavigationStack {
                Group {
                    switch tab {
                    case .notes: NotesTab(meetingID: meetingID, editing: $editingNotes)
                    case .transcript: TranscriptTab(meetingID: meetingID, findRequested: $findRequested)
                    case .ask: AskTab(meetingID: meetingID)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if state.canPlayClips(meetingID) {
                        MeetingPlayerBar(meetingID: meetingID) { chapter in
                            if tab == .transcript { state.focusTranscript(meetingID, at: chapter.start) }
                        }
                    }
                }
                .environment(\.openURL, OpenURLAction { url in
                    if let target = Citations.playTarget(from: url) {
                        state.toggleClip(target.meetingID, at: target.seconds)
                        return .handled
                    }
                    guard let target = Citations.target(from: url) else { return .systemAction }
                    state.focusTranscript(target.meetingID, at: target.seconds)
                    return .handled
                })
                .onChange(of: state.transcriptFocus) { _, focus in
                    if focus?.meetingID == meetingID { tab = .transcript }
                }
                .navigationTitle("")
                .focusedSceneValue(\.meetingActions, actions(meeting))
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        TextField("Title", text: state.titleBinding(meetingID))
                            .textFieldStyle(.plain)
                            .font(GrokTypography.meetingTitle())
                            .frame(minWidth: 160, idealWidth: 300, maxWidth: 380)
                            .accessibilityLabel("Meeting title")
                    }
                    ToolbarItem(placement: .principal) {
                        Picker("View", selection: $tab) {
                            ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                        .help("Notes (Command-1), Transcript (Command-2), Ask (Command-3)")
                    }
                    ToolbarItemGroup(placement: .automatic) {
                        if state.recordingID == meetingID {
                            HStack(spacing: GrokSpacing.xs) {
                                RecordingPulse()
                                RecordingElapsedText()
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    if recording {
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                toggleLiveAnswers()
                            } label: {
                                Label("Live answers", systemImage: liveAnswers.enabled ? "bolt.fill" : "bolt.slash")
                            }
                            .help(liveAnswers.enabled ? "Live answers are on. Click to turn them off." : "Answer questions heard in the call")
                        }
                    }
                    if !recording {
                        ToolbarItem(placement: .primaryAction) {
                            ShareLink(
                                item: meeting.markdown(myName: Prefs.myName),
                                subject: Text(meeting.title),
                                preview: SharePreview(meeting.title)
                            ) {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                            .help("Share the notes and transcript as Markdown")
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        moreMenu(meeting)
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: toggleInspector) {
                            Label("Meeting info", systemImage: "info.circle")
                        }
                        .help("Tags, speakers, attendees, and attribution (Option-Command-I)")
                    }
                }
                .inspector(isPresented: $showInspector) {
                    Group {
                        if hasAnswersPane {
                            VStack(spacing: 0) {
                                Picker("", selection: $pane) {
                                    ForEach(InspectorPane.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                                }
                                .pickerStyle(.segmented)
                                .labelsHidden()
                                .padding(.horizontal, GrokSpacing.md)
                                .padding(.vertical, GrokSpacing.sm)
                                Divider()
                                switch pane {
                                case .answers: LiveAnswersPanel(meetingID: meetingID)
                                case .info: MeetingInspectorView(meetingID: meetingID)
                                }
                            }
                        } else {
                            MeetingInspectorView(meetingID: meetingID)
                        }
                    }
                    .inspectorColumnWidth(min: 260, ideal: 320, max: 420)
                }
                .confirmationDialog("Regenerate notes?", isPresented: confirmingRegenerate) {
                    Button("Regenerate", role: .destructive) {
                        editingNotes = false
                        state.confirmRegenerate(meetingID, saveEdits: false, undoManager: undoManager)
                    }
                    Button("Save edits to My notes, then regenerate") {
                        editingNotes = false
                        state.confirmRegenerate(meetingID, saveEdits: true, undoManager: undoManager)
                    }
                    Button("Keep my edits", role: .cancel) { state.regenerateConfirmation = nil }
                } message: {
                    Text("Your edits to the enhanced notes will be replaced.")
                }
                .onAppear(perform: openAnswersIfRecording)
                .onChange(of: state.recordingID) { openAnswersIfRecording() }
            }
        }
    }

    enum InspectorPane: String, CaseIterable {
        case answers = "Answers"
        case info = "Info"
    }

    private var recording: Bool { state.recordingID == meetingID }
    private var processing: Bool { state.processing.contains(meetingID) }

    private func canWriteNotes(_ meeting: Meeting) -> Bool {
        !recording && !processing && (!meeting.utterances.isEmpty || !meeting.userNotes.isEmpty)
    }

    private func regenerate() {
        editingNotes = false
        state.requestRegenerate(meetingID, undoManager: undoManager)
    }

    private var confirmingRegenerate: Binding<Bool> {
        Binding(
            get: { state.regenerateConfirmation == meetingID },
            set: { if !$0, state.regenerateConfirmation == meetingID { state.regenerateConfirmation = nil } }
        )
    }

    private func findInTranscript() {
        tab = .transcript
        findRequested = true
    }

    private func toggleInspector() {
        if showInspector, pane == .answers, hasAnswersPane {
            pane = .info
        } else {
            pane = .info
            showInspector.toggle()
        }
    }

    private func actions(_ meeting: Meeting) -> MeetingActions {
        MeetingActions(
            selectTab: { tab = $0 },
            toggleInspector: toggleInspector,
            copyMarkdown: { state.copyMarkdown(meetingID) },
            regenerate: canWriteNotes(meeting) ? regenerate : nil,
            findInTranscript: meeting.utterances.isEmpty ? nil : findInTranscript
        )
    }

    /// Everything that used to sit in a row above the notes, plus the transcript copy.
    private func moreMenu(_ meeting: Meeting) -> some View {
        let enhanced = meeting.enhancedNotes != nil
        return Menu {
            if enhanced, let pending = state.pendingTemplate(for: meetingID) {
                Button("Regenerate with \(pending.name)", action: regenerate)
                    .disabled(!canWriteNotes(meeting))
            }
            Button(enhanced ? "Regenerate Notes" : "Write Notes", action: regenerate)
                .disabled(!canWriteNotes(meeting))
            if enhanced {
                Button(editingNotes ? "Stop Editing Notes" : "Edit Notes") {
                    tab = .notes
                    editingNotes.toggle()
                }
                .disabled(recording || processing)
            }
            Divider()
            Button("Copy Markdown") { state.copyMarkdown(meetingID) }
            Button("Copy Transcript") { state.copyTranscript(meetingID, .all) }
                .disabled(meeting.utterances.isEmpty)
            Button("Find in Transcript", action: findInTranscript)
                .disabled(meeting.utterances.isEmpty)
            Button("Show in Finder") { state.revealInFinder(meetingID) }
            Divider()
            Button("Delete Meeting", role: .destructive) { state.moveToTrash(meetingID, undoManager: undoManager) }
                .disabled(recording)
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
        .menuIndicator(.hidden)
        .help("Regenerate, edit, copy, find, and delete")
    }

    /// Answers show while recording, and afterwards while pinned cards from this recording remain.
    private var hasAnswersPane: Bool {
        recording || liveAnswers.cards.contains { $0.meetingID == meetingID }
    }

    private func openAnswersIfRecording() {
        guard recording, liveAnswers.enabled else {
            if !hasAnswersPane { pane = .info }
            return
        }
        pane = .answers
        showInspector = true
    }

    private func toggleLiveAnswers() {
        let on = !liveAnswers.enabled
        liveAnswers.setEnabled(on)
        if on {
            pane = .answers
            showInspector = true
        } else if pane == .answers {
            showInspector = false
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

extension SpeakerColor {
    /// The speaker's color in this meeting, by the order speakers first talk.
    static func color(for key: String, in meeting: Meeting?) -> Color {
        guard let meeting else { return color(for: key) }
        return color(for: key, among: meeting.speakerKeys)
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
        let color = SpeakerColor.color(for: key, in: meeting)
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
