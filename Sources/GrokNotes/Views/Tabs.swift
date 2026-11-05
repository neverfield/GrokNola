import SwiftUI

struct NotesTab: View {
    @EnvironmentObject private var state: AppState
    let meetingID: UUID
    @State private var showMyNotes = false

    var body: some View {
        let meeting = state.meeting(meetingID)
        let recording = state.recordingID == meetingID
        let processing = state.processing.contains(meetingID)
        let enhanced = meeting?.enhancedNotes

        VStack(spacing: 0) {
            if !recording {
                notesToolbar(enhanced: enhanced, processing: processing)
                Divider()
            }

            let hasTranscript = !recording && !(meeting?.utterances.isEmpty ?? true)
            let showEnhanced = enhanced != nil && !recording && !showMyNotes
            // The editor shows the summary only when there are no enhanced notes to switch to.
            let showSummary = hasTranscript && (showEnhanced || enhanced == nil)
            GeometryReader { geo in
                let wide = showSummary && geo.size.width >= Self.sideColumnMinWidth
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        if showSummary, !wide, !showEnhanced {
                            CallSummaryCard(meetingID: meetingID)
                                .padding([.horizontal, .top], GrokSpacing.contentInset)
                                .frame(maxWidth: 680, alignment: .leading)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .background(GrokColors.notesSurface)
                        }
                        if showEnhanced, let enhanced {
                            enhancedNotes(enhanced, summaryAbove: showSummary && !wide)
                        } else {
                            notesEditor(meeting: meeting, recording: recording)
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
        }
    }

    /// Below this pane width the call summary goes above the notes instead of beside them.
    private static let sideColumnMinWidth: CGFloat = 900
    private static let sideColumnWidth: CGFloat = 290

    private func enhancedNotes(_ enhanced: String, summaryAbove: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GrokSpacing.lg) {
                if summaryAbove { CallSummaryCard(meetingID: meetingID) }
                let playable = state.canPlayClips(meetingID)
                MarkdownView(markdown: enhanced, citationMeetingID: meetingID, playable: playable)
                if !playable, !Prefs.keepAudio, Citations.contains(enhanced) {
                    KeepAudioHint().padding(.top, GrokSpacing.sm)
                }
            }
            .padding(GrokSpacing.contentInset)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    @ViewBuilder
    private func notesToolbar(enhanced: String?, processing: Bool) -> some View {
        HStack(spacing: GrokSpacing.sm) {
            if enhanced != nil {
                Picker("", selection: $showMyNotes) {
                    Text("Enhanced").tag(false)
                    Text("My notes").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
            }
            if processing {
                ProgressView().controlSize(.small)
                Text("Writing notes…")
                    .font(GrokTypography.captionMuted())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if enhanced != nil, let pending = state.pendingTemplate(for: meetingID) {
                Button("Regenerate with \(pending.name)") { Task { await state.regenerateNotes(meetingID) } }
                    .buttonStyle(.borderedProminent)
                    .disabled(processing)
                    .help("These notes were written with another template")
            } else {
                Button(enhanced == nil ? "Write notes" : "Regenerate") { Task { await state.regenerateNotes(meetingID) } }
                    .disabled(processing)
            }
            Button("Copy Markdown") { state.copyMarkdown(meetingID) }
            Button("Show in Finder") { state.revealInFinder(meetingID) }
        }
        .padding(.horizontal, GrokSpacing.lg)
        .padding(.vertical, GrokSpacing.sm)
    }

    @ViewBuilder
    private func notesEditor(meeting: Meeting?, recording: Bool) -> some View {
        TextEditor(text: state.binding(meetingID, \.userNotes, default: ""))
            .font(recording ? GrokTypography.placeholder() : .body)
            .scrollContentBackground(.hidden)
            .padding(GrokSpacing.notesEditorInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(GrokColors.notesSurface)
            .overlay(alignment: .topLeading) {
                if (meeting?.userNotes ?? "").isEmpty {
                    Text(recording
                         ? "Jot rough notes here while you talk…"
                         : "Jot rough notes here. When the meeting ends, Grok merges them with the transcript.")
                        .font(recording ? GrokTypography.placeholder() : .body)
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
        let blocks = TranscriptText.blocks(from: utterances)
        let playable = state.canPlayClips(meetingID)
        let headers = recording ? [:] : chapterHeaders(meeting?.chapters ?? [], blocks: blocks)
        let hasChapters = !headers.isEmpty
        let playing = playable && clips.isPlaying && clips.loadedID == meetingID

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
                                current: playable && clips.loadedID == meetingID && currentBlock == block.id,
                                inChapter: hasChapters
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
                    // Keeps text out from under the copy button in a narrow pane.
                    .padding(.horizontal, blocks.isEmpty ? 0 : Self.copyButtonGutter)
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 8).onChanged { _ in stickToBottom = false }
                )
                .onChange(of: utterances.count) {
                    if recording, stickToBottom {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("live", anchor: .bottom)
                        }
                    }
                }
                .onChange(of: state.liveMe) { _, _ in scrollIfStuck(proxy) }
                .onChange(of: state.liveThem) { _, _ in scrollIfStuck(proxy) }
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

            if playing {
                Toggle(isOn: $follow) {
                    Label("Follow", systemImage: "text.line.first.and.arrowtriangle.forward")
                }
                .toggleStyle(.button)
                .help("Scroll the transcript along with playback")
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
        .overlay(alignment: .topTrailing) {
            if !blocks.isEmpty {
                CopyButton(label: "Copy transcript", help: "Copy the whole transcript as text") {
                    state.copyTranscript(meetingID, .all)
                }
                .padding(.horizontal, GrokSpacing.sm)
                .padding(.vertical, GrokSpacing.xs)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.quaternary))
                .padding(GrokSpacing.md)
            }
        }
    }

    private static let copyButtonGutter: CGFloat = 36

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
                    Text(line.text)
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
    @EnvironmentObject private var state: AppState
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
            if !state.liveThem.isEmpty {
                liveLine(label: "Them", text: state.liveThem)
            }
            if !state.liveMe.isEmpty {
                liveLine(label: "Me", text: state.liveMe)
            }
            if state.liveThem.isEmpty && state.liveMe.isEmpty {
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
                                playable: state.canPlayClips(meetingID)
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

/// Renders the subset of Markdown that Grok's notes use: headings, bullets, checkboxes, and inline styles.
struct MarkdownView: View {
    let markdown: String
    /// When set, `[mm:ss]` citations link to this meeting's transcript.
    var citationMeetingID: UUID?
    /// Adds a play link after each citation. Set only when the meeting's audio is on disk.
    var playable = false

    var body: some View {
        VStack(alignment: .leading, spacing: GrokSpacing.sm) {
            ForEach(Array(markdown.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                row(line)
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func row(_ raw: String) -> some View {
        let line = raw.trimmingCharacters(in: .whitespaces)
        let indent = CGFloat(raw.prefix(while: { $0 == " " }).count / 2) * 16
        if line.hasPrefix("# ") {
            inline(String(line.dropFirst(2))).font(.title2.bold()).padding(.top, GrokSpacing.xs)
        } else if line.hasPrefix("## ") {
            inline(String(line.dropFirst(3))).font(.title3.bold()).padding(.top, GrokSpacing.md)
        } else if line.hasPrefix("### ") {
            inline(String(line.dropFirst(4))).font(.headline).padding(.top, GrokSpacing.sm)
        } else if line.hasPrefix("- [ ] ") || line.lowercased().hasPrefix("- [x] ") {
            HStack(alignment: .firstTextBaseline, spacing: GrokSpacing.sm) {
                Image(systemName: line.hasPrefix("- [ ] ") ? "square" : "checkmark.square")
                inline(String(line.dropFirst(6)))
            }
            .padding(.leading, indent)
        } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
            HStack(alignment: .firstTextBaseline, spacing: GrokSpacing.sm) {
                Text("•")
                inline(String(line.dropFirst(2)))
            }
            .padding(.leading, indent)
        } else if line.isEmpty {
            Spacer().frame(height: GrokSpacing.xs)
        } else {
            inline(line)
        }
    }

    private func inline(_ text: String) -> Text {
        let source = citationMeetingID.map { Citations.linkify(text, meetingID: $0, playable: playable) } ?? text
        var attributed = (try? AttributedString(markdown: source)) ?? AttributedString(text)
        if citationMeetingID != nil { Citations.style(&attributed) }
        return Text(attributed)
    }
}
