import SwiftUI

struct NotesTab: View {
    @EnvironmentObject private var state: AppState
    let meetingID: UUID
    /// Editing the enhanced notes' Markdown. Owned by the meeting view so its menu can start an edit.
    @Binding var editing: Bool
    @State private var showMyNotes = false

    var body: some View {
        let meeting = state.meeting(meetingID)
        let recording = state.recordingID == meetingID
        let processing = state.processing.contains(meetingID)
        let enhanced = meeting?.enhancedNotes
        let awaitingNotes = enhanced == nil && [.pending, .running].contains(state.processingStage[meetingID]?.status(.writing))
        let hasTranscript = !recording && !(meeting?.utterances.isEmpty ?? true)
        let showEnhanced = enhanced != nil && !recording && !showMyNotes
        let editingEnhanced = showEnhanced && editing && !processing
        // The editor shows the summary only when there are no enhanced notes to switch to.
        let showSummary = hasTranscript && (showEnhanced || enhanced == nil)

        GeometryReader { geo in
            let wide = showSummary && geo.size.width >= Self.sideColumnMinWidth
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    header(meeting: meeting, recording: recording, processing: processing, showEnhanced: showEnhanced, awaitingNotes: awaitingNotes)
                    if !recording, state.processingStage[meetingID] != nil {
                        Divider()
                        ProcessingStepsRow(meetingID: meetingID)
                        Divider()
                    }
                    if showSummary, !wide, !showEnhanced {
                        CallSummaryCard(meetingID: meetingID)
                            .padding([.horizontal, .top], GrokSpacing.contentInset)
                            .frame(maxWidth: 680, alignment: .leading)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .background(GrokColors.notesSurface)
                    }
                    if editingEnhanced {
                        MarkdownSourceEditor(text: state.enhancedNotesBinding(meetingID))
                            .background(GrokColors.notesSurface)
                    } else if showEnhanced, let enhanced {
                        enhancedNotes(enhanced, summaryAbove: showSummary && !wide, processing: processing)
                    } else if awaitingNotes, !showMyNotes {
                        NotesSkeleton(template: state.template(for: meetingID))
                    } else {
                        notesEditor(meeting: meeting, recording: recording)
                    }
                    if recording {
                        Divider()
                        LiveTranscriptStrip()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if wide {
                    Divider()
                    ScrollView {
                        CallSummaryCard(meetingID: meetingID, style: .sidebar)
                    }
                    .frame(width: Self.sideColumnWidth)
                    .background(.quaternary.opacity(0.18))
                }
            }
        }
        .onChange(of: processing) { _, busy in
            if busy { editing = false }
        }
    }

    /// Below this pane width the call summary goes above the notes instead of beside them.
    private static let sideColumnMinWidth: CGFloat = 900
    private static let sideColumnWidth: CGFloat = 290

    private func enhancedNotes(_ enhanced: String, summaryAbove: Bool, processing: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GrokSpacing.lg) {
                if summaryAbove { CallSummaryCard(meetingID: meetingID) }
                let playable = state.canPlayClips(meetingID)
                MarkdownView(
                    markdown: enhanced,
                    citationMeetingID: meetingID,
                    playable: playable,
                    onToggleCheckbox: processing ? nil : { state.toggleNotesCheckbox(meetingID, line: $0) },
                    quote: { state.transcriptQuote(meetingID, at: $0) }
                )
                if !playable, !Prefs.keepAudio, Citations.contains(enhanced) {
                    KeepAudioHint().padding(.top, GrokSpacing.sm)
                }
            }
            .padding(GrokSpacing.contentInset)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(GrokColors.notesSurface)
    }

    /// Enhanced / My notes, the template, and Edit, at the top left of the notes.
    private func header(meeting: Meeting?, recording: Bool, processing: Bool, showEnhanced: Bool, awaitingNotes: Bool) -> some View {
        let enhanced = meeting?.enhancedNotes
        return HStack(spacing: GrokSpacing.md) {
            if enhanced != nil || awaitingNotes, !recording {
                Picker("Notes", selection: $showMyNotes) {
                    Text("Enhanced").tag(false)
                    Text("My notes").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
                .disabled(editing && showEnhanced)
                .help("Grok's notes, or the rough notes you typed")
            }
            TemplatePickerMenu(meetingID: meetingID, compact: true)
            if processing {
                // The step list below shows progress; this covers a run that has no step list.
                if state.processingStage[meetingID] == nil {
                    HStack(spacing: GrokSpacing.xs) {
                        ProgressView().controlSize(.small)
                        Text("Writing notes…")
                    }
                    .font(GrokTypography.captionMuted())
                    .foregroundStyle(.secondary)
                }
            } else if enhanced != nil, !recording, let pending = state.pendingTemplate(for: meetingID) {
                Button("Regenerate with \(pending.name)") {
                    editing = false
                    Task { await state.regenerateNotes(meetingID) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .help("These notes were written with another template")
            } else if enhanced == nil, !recording, let meeting, !meeting.utterances.isEmpty || !meeting.userNotes.isEmpty {
                Button("Write notes") { Task { await state.regenerateNotes(meetingID) } }
                    .controlSize(.small)
            }
            Spacer(minLength: 0)
            if showEnhanced {
                Button(editing ? "Done" : "Edit") { editing.toggle() }
                    .controlSize(.small)
                    .disabled(processing)
                    .help(editing ? "Show the notes as formatted text" : "Edit the notes' Markdown, for example to fix a name")
            }
        }
        .padding(.horizontal, GrokSpacing.contentInset)
        .padding(.vertical, GrokSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GrokColors.notesSurface)
    }

    @ViewBuilder
    private func notesEditor(meeting: Meeting?, recording: Bool) -> some View {
        TextEditor(text: state.binding(meetingID, \.userNotes, default: ""))
            .font(.body)
            .scrollContentBackground(.hidden)
            .padding(GrokSpacing.notesEditorInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(GrokColors.notesSurface)
            .overlay(alignment: .topLeading) {
                if (meeting?.userNotes ?? "").isEmpty {
                    Text(recording
                         ? "Jot rough notes here while you talk…"
                         : "Jot rough notes here. When the meeting ends, Grok merges them with the transcript.")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(GrokSpacing.notesEditorInset + 4)
                        .allowsHitTesting(false)
                }
            }
    }
}

// MARK: - Transcript

/// The last block that starts at or before `seconds`. Citations are whole seconds, so allow up to one second of rounding.
private func blockID(containing seconds: Double, in blocks: [TranscriptBlock]) -> UUID? {
    (blocks.last { $0.start < seconds + 1 } ?? blocks.first)?.id
}

/// The chapter that starts at each block where the chapter changes, keyed by block id.
private func chapterHeaders(_ chapters: [Chapter], blocks: [TranscriptBlock]) -> [UUID: (index: Int, chapter: Chapter)] {
    var headers: [UUID: (index: Int, chapter: Chapter)] = [:]
    var last: Int?
    for block in blocks {
        guard let i = TranscriptText.chapterIndex(ofBlockAt: block.start, in: chapters), i != last else { continue }
        headers[block.id] = (i, chapters[i])
        last = i
    }
    return headers
}

struct TranscriptTab: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var clips: ClipPlayer
    let meetingID: UUID
    /// Set by the meeting's menu to open the find bar.
    @Binding var findRequested: Bool
    @State private var finding = false
    @State private var query = ""
    @State private var matchIndex = 0
    @FocusState private var findFocused: Bool
    @State private var hoveringFollow = false
    @FocusState private var followFocused: Bool
    @State private var stickToBottom = true
    @State private var scrollToLiveRequest = 0
    @State private var highlightedBlock: UUID?
    @State private var highlightTask: Task<Void, Never>?
    /// The block under the playhead, while this meeting's audio is loaded.
    @State private var currentBlock: UUID?
    @AppStorage("transcriptFollowsPlayback") private var follow = true

    var body: some View {
        let meeting = state.meeting(meetingID)
        let utterances = meeting?.utterances ?? []
        let recording = state.recordingID == meetingID
        let blocks = TranscriptBlockCache.blocks(meetingID: meetingID, revision: state.meetingsRevision, utterances: utterances)
        let playable = state.canPlayClips(meetingID)
        let headers = recording ? [:] : chapterHeaders(meeting?.chapters ?? [], blocks: blocks)
        let hasChapters = !headers.isEmpty
        let loaded = playable && clips.loadedID == meetingID
        let matches = finding ? TranscriptSearch.matches(query, in: blocks) : []
        let currentMatch = matches.isEmpty ? nil : matches[min(matchIndex, matches.count - 1)]

        VStack(spacing: 0) {
            if finding {
                findBar(count: matches.count)
                Divider()
            }
            transcript(
                blocks: blocks, headers: headers, hasChapters: hasChapters, recording: recording,
                playable: playable, loaded: loaded, utteranceCount: utterances.count, currentMatch: currentMatch
            )
        }
        .background {
            Button("Find in Transcript") { openFind() }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        .onAppear { if findRequested { openFind() } }
        .onChange(of: findRequested) { _, requested in if requested { openFind() } }
        .onChange(of: query) { matchIndex = 0 }
    }

    // MARK: Find

    private func openFind() {
        findRequested = false
        finding = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            findFocused = true
        }
    }

    private func closeFind() {
        finding = false
        query = ""
    }

    private func step(_ delta: Int, count: Int) {
        guard count > 0 else { return }
        matchIndex = ((min(matchIndex, count - 1) + delta) % count + count) % count
    }

    private func findBar(count: Int) -> some View {
        HStack(spacing: GrokSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Find in transcript", text: $query)
                .textFieldStyle(.plain)
                .focused($findFocused)
                .onSubmit { step(1, count: count) }
                .onKeyPress(.return, phases: .down) { press in
                    guard press.modifiers.contains(.shift) else { return .ignored }
                    step(-1, count: count)
                    return .handled
                }
                .onKeyPress(.escape) {
                    closeFind()
                    return .handled
                }
            if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                Text(count == 0 ? "No matches" : "\(min(matchIndex, count - 1) + 1) of \(count)")
                    .font(GrokTypography.captionMuted().monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.updatesFrequently)
            }
            Button { step(-1, count: count) } label: { Image(systemName: "chevron.up") }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(count == 0)
                .help("Previous match (Shift-Return or Shift-Command-G)")
                .accessibilityLabel("Previous match")
            Button { step(1, count: count) } label: { Image(systemName: "chevron.down") }
                .keyboardShortcut("g", modifiers: .command)
                .disabled(count == 0)
                .help("Next match (Return or Command-G)")
                .accessibilityLabel("Next match")
            Button("Done", action: closeFind)
                .controlSize(.small)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, GrokSpacing.lg)
        .padding(.vertical, GrokSpacing.sm)
        .background(.bar)
    }

    // MARK: Blocks

    private func transcript(
        blocks: [TranscriptBlock], headers: [UUID: (index: Int, chapter: Chapter)], hasChapters: Bool, recording: Bool,
        playable: Bool, loaded: Bool, utteranceCount: Int, currentMatch: TranscriptSearch.Match?
    ) -> some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: GrokSpacing.lg) {
                        if blocks.isEmpty, !recording {
                            Text("No transcript yet.")
                                .foregroundStyle(.secondary)
                                .padding(GrokSpacing.contentInset)
                        }
                        ForEach(blocks) { block in
                            if let header = headers[block.id] {
                                ChapterHeader(meetingID: meetingID, index: header.index, chapter: header.chapter, first: block.id == blocks.first?.id)
                            }
                            TranscriptBlockView(
                                meetingID: meetingID,
                                block: block,
                                playable: playable,
                                highlighted: highlightedBlock == block.id,
                                current: loaded && currentBlock == block.id,
                                inChapter: hasChapters,
                                query: finding ? query : "",
                                currentMatch: currentMatch?.blockID == block.id ? currentMatch : nil
                            )
                            .id(block.id)
                        }
                        if recording {
                            LiveTranscriptRegion(meetingID: meetingID)
                                .id("live")
                        }
                    }
                    .padding(GrokSpacing.contentInset)
                    .frame(maxWidth: 720, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 8).onChanged { _ in stickToBottom = false }
                )
                .onChange(of: currentMatch) { _, match in
                    guard let match else { return }
                    stickToBottom = false
                    withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(match.blockID, anchor: .center) }
                }
                .onChange(of: utteranceCount) {
                    if recording, stickToBottom {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("live", anchor: .bottom)
                        }
                    }
                }
                // Subscribe without observing, so interim text scrolls the list but does not re-evaluate it.
                .onReceive(state.recording.$liveMe.removeDuplicates()) { _ in scrollIfStuck(proxy) }
                .onReceive(state.recording.$liveThem.removeDuplicates()) { _ in scrollIfStuck(proxy) }
                .onAppear {
                    if state.transcriptFocus?.meetingID == meetingID {
                        focus(blocks: blocks, proxy: proxy)
                    } else if recording {
                        proxy.scrollTo("live", anchor: .bottom)
                    }
                }
                .onChange(of: state.transcriptFocus) { _, focus in
                    if focus?.meetingID == meetingID { self.focus(blocks: blocks, proxy: proxy) }
                }
                .onChange(of: scrollToLiveRequest) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("live", anchor: .bottom)
                    }
                }
                .onReceive(clips.ticks) { tick in
                    guard tick.meetingID == meetingID, !recording else { return }
                    let id = (blocks.last { $0.start <= tick.seconds } ?? blocks.first)?.id
                    guard id != currentBlock else { return }
                    currentBlock = id
                    if follow, clips.isPlaying, let id {
                        withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(id, anchor: .center) }
                    }
                }
                .onChange(of: follow) { _, on in
                    if on, let currentBlock {
                        withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(currentBlock, anchor: .center) }
                    }
                }
            }

            if loaded {
                Toggle(isOn: $follow) {
                    Label("Follow", systemImage: "text.line.first.and.arrowtriangle.forward")
                }
                .toggleStyle(.button)
                .help("Scroll the transcript along with playback")
                .focused($followFocused)
                .onHover { hoveringFollow = $0 }
                .opacity(hoveringFollow || followFocused ? 1 : GrokOpacity.idleControl)
                .padding(GrokSpacing.lg)
            }

            if recording, !stickToBottom {
                Button {
                    stickToBottom = true
                    scrollToLiveRequest += 1
                } label: {
                    Label("Jump to latest", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .padding(GrokSpacing.lg)
            }
        }
    }

    /// Scrolls to the block that contains the requested time and highlights it briefly.
    private func focus(blocks: [TranscriptBlock], proxy: ScrollViewProxy) {
        guard let request = state.transcriptFocus, request.meetingID == meetingID else { return }
        state.transcriptFocus = nil
        guard let target = blockID(containing: request.seconds, in: blocks) else { return }
        stickToBottom = false
        highlightTask?.cancel()
        highlightTask = Task { @MainActor in
            // Let a freshly shown tab lay out before scrolling.
            try? await Task.sleep(for: .milliseconds(60))
            withAnimation(.easeInOut(duration: 0.25)) {
                proxy.scrollTo(target, anchor: .center)
                highlightedBlock = target
            }
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.4)) { highlightedBlock = nil }
        }
    }

    private func scrollIfStuck(_ proxy: ScrollViewProxy) {
        guard state.recordingID == meetingID, stickToBottom else { return }
        withAnimation(.easeOut(duration: 0.15)) {
            proxy.scrollTo("live", anchor: .bottom)
        }
    }
}

private struct TranscriptBlockView: View {
    @EnvironmentObject private var state: AppState
    let meetingID: UUID
    let block: TranscriptBlock
    var playable = false
    var highlighted = false
    /// Playback is inside this block.
    var current = false
    /// The transcript shows chapters, so "Copy from here to end of chapter" applies.
    var inChapter = false
    /// Text to highlight from the find bar.
    var query = ""
    /// The find bar's current match, when it is in this block.
    var currentMatch: TranscriptSearch.Match?
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: GrokSpacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: GrokSpacing.sm) {
                SpeakerChip(meetingID: meetingID, key: block.speakerKey)
                Text(Meeting.timestamp(block.start))
                    .font(GrokTypography.captionMuted().monospacedDigit())
                    .foregroundStyle(GrokColors.timestamp)
                if playable {
                    ClipPlayButton(meetingID: meetingID, start: block.start, visible: hovering, current: current)
                        .font(GrokTypography.captionMuted())
                }
            }
            VStack(alignment: .leading, spacing: GrokSpacing.xs) {
                ForEach(block.lines, id: \.id) { line in
                    Group {
                        if query.isEmpty {
                            Text(line.text)
                        } else {
                            Text(TranscriptSearch.highlighted(
                                line.text, query: query,
                                current: currentMatch?.lineID == line.id ? currentMatch?.occurrence : nil
                            ))
                        }
                    }
                    .font(GrokTypography.transcriptBody())
                    .textSelection(.enabled)
                }
            }
            .padding(.leading, 2)
        }
        .padding(GrokSpacing.sm)
        .background(
            Color.accentColor.opacity(highlighted ? 0.16 : current ? 0.08 : 0),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay(alignment: .leading) {
            if current {
                Capsule().fill(Color.accentColor).frame(width: 3).padding(.vertical, GrokSpacing.xs)
            }
        }
        .padding(-GrokSpacing.sm)
        .animation(.easeOut(duration: 0.2), value: current)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Copy") { state.copyTranscript(meetingID, .block(block.id)) }
            if inChapter {
                Button("Copy from Here to End of Chapter") { state.copyTranscript(meetingID, .toChapterEnd(block.id)) }
            }
        }
    }
}

/// A borderless copy icon that shows a checkmark for a moment after copying.
struct CopyButton: View {
    let label: String
    let help: String
    let action: () -> Void
    @State private var copied = false
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        Button {
            action()
            copied = true
            resetTask?.cancel()
            resetTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.2))
                guard !Task.isCancelled else { return }
                copied = false
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .foregroundStyle(copied ? AnyShapeStyle(Color.green) : AnyShapeStyle(.secondary))
                .frame(width: 16, height: 16)
                .contentTransition(.symbolEffect(.replace))
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(copied ? "Copied" : help)
        .accessibilityLabel(label)
        .accessibilityValue(copied ? "Copied" : "")
    }
}

/// A topic chapter's title and start, between transcript blocks. Click the time to play from there.
private struct ChapterHeader: View {
    @EnvironmentObject private var state: AppState
    let meetingID: UUID
    let index: Int
    let chapter: Chapter
    var first = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: GrokSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: GrokSpacing.sm) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(ChapterColor.color(index))
                    .frame(width: 3, height: 14)
                Text(chapter.title)
                    .font(.headline)
                Button {
                    state.openChapter(meetingID, chapter)
                } label: {
                    Text("\(Meeting.timestamp(chapter.start)) · \(Meeting.durationLabel(chapter.length))")
                        .font(GrokTypography.captionMuted().monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(state.canPlayClips(meetingID) ? "Play this chapter" : "Chapter start")
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            CopyButton(label: "Copy chapter \(chapter.title)", help: "Copy this chapter's transcript as text") {
                state.copyTranscript(meetingID, .chapter(index))
            }
            .font(GrokTypography.captionMuted())
            VStack { Divider() }
        }
        .padding(.top, first ? 0 : GrokSpacing.md)
    }
}

private struct LiveTranscriptRegion: View {
    @EnvironmentObject private var recording: RecordingModel
    let meetingID: UUID

    var body: some View {
        VStack(alignment: .leading, spacing: GrokSpacing.sm) {
            HStack(spacing: GrokSpacing.xs) {
                Image(systemName: "waveform")
                    .foregroundStyle(.secondary)
                Text("Live")
                    .font(GrokTypography.transcriptSpeaker())
                    .foregroundStyle(.secondary)
            }
            if !recording.liveThem.isEmpty {
                liveLine(label: "Them", text: recording.liveThem)
            }
            if !recording.liveMe.isEmpty {
                liveLine(label: "Me", text: recording.liveMe)
            }
            if recording.liveThem.isEmpty && recording.liveMe.isEmpty {
                Text("Listening…")
                    .font(GrokTypography.liveLine())
                    .foregroundStyle(GrokColors.liveText)
            }
        }
        .padding(GrokSpacing.md)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(.quaternary)
        )
    }

    private func liveLine(label: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: GrokSpacing.sm) {
            Text(label)
                .font(GrokTypography.captionMuted().weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
            Text(text)
                .font(GrokTypography.liveLine())
                .foregroundStyle(GrokColors.liveText)
                .textSelection(.enabled)
        }
    }
}

struct AskTab: View {
    @EnvironmentObject private var state: AppState
    let meetingID: UUID
    @State private var question = ""

    var body: some View {
        let chat = state.meeting(meetingID)?.chat ?? []
        let busy = state.asking.contains(meetingID)

        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: GrokSpacing.lg) {
                    if chat.isEmpty {
                        Text("Ask anything about this meeting, for example \"What did we decide about pricing?\" or \"Draft a follow-up email.\"")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(chat) { message in
                        VStack(alignment: .leading, spacing: GrokSpacing.xs) {
                            Text(message.role == "user" ? "You" : "Grok")
                                .font(GrokTypography.captionMuted().weight(.semibold))
                                .foregroundStyle(.secondary)
                            MarkdownView(
                                markdown: message.content,
                                citationMeetingID: message.role == "assistant" ? meetingID : nil,
                                playable: state.canPlayClips(meetingID),
                                quote: { state.transcriptQuote(meetingID, at: $0) }
                            )
                        }
                    }
                    if busy { ProgressView().controlSize(.small) }
                }
                .padding(GrokSpacing.contentInset)
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            Divider()
            HStack {
                TextField("Ask about this meeting…", text: $question)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(send)
                Button("Ask", action: send).disabled(busy || question.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(GrokSpacing.lg)
        }
    }

    private func send() {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !state.asking.contains(meetingID) else { return }
        question = ""
        Task { await state.ask(meetingID, q) }
    }
}

/// Renders the Markdown that Grok writes as one selectable text: headings, lists, checkboxes, quotes, inline styles,
/// and `[mm:ss]` citations as pills. Links open through the environment's `openURL`.
struct MarkdownView: View {
    let markdown: String
    /// When set, `[mm:ss]` citations link to this meeting.
    var citationMeetingID: UUID?
    /// Citations play their clip. Set only when the meeting's audio is on disk.
    var playable = false
    var textStyle: NSFont.TextStyle = .body
    /// Makes checkboxes clickable. Gets the line number in `markdown`.
    var onToggleCheckbox: ((Int) -> Void)?
    /// The transcript line near a time, shown when hovering a citation.
    var quote: ((Double) -> String?)?

    var body: some View {
        RenderedMarkdownView(
            markdown: markdown,
            options: NotesRenderer.Options(
                textStyle: textStyle,
                citationMeetingID: citationMeetingID,
                playable: playable,
                checkboxes: onToggleCheckbox != nil
            ),
            quote: quote,
            onToggleCheckbox: onToggleCheckbox
        )
    }
}
