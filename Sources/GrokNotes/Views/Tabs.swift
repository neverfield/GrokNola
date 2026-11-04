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

            if let enhanced, !recording, !showMyNotes {
                ScrollView {
                    MarkdownView(markdown: enhanced)
                        .padding(GrokSpacing.contentInset)
                        .frame(maxWidth: 680, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .background(Color(nsColor: .textBackgroundColor))
            } else {
                notesEditor(meeting: meeting, recording: recording)
            }
        }
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
            Button(enhanced == nil ? "Write notes" : "Regenerate") { Task { await state.regenerateNotes(meetingID) } }
                .disabled(processing)
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

private struct TranscriptBlock: Identifiable {
    let id: UUID
    let speakerKey: String
    let start: Double
    var lines: [(id: UUID, text: String)]
}

private func mergedBlocks(from utterances: [Utterance]) -> [TranscriptBlock] {
    var blocks: [TranscriptBlock] = []
    for u in utterances {
        if var last = blocks.last, last.speakerKey == u.speakerKey {
            last.lines.append((id: u.id, text: u.text))
            blocks[blocks.count - 1] = last
        } else {
            blocks.append(TranscriptBlock(id: u.id, speakerKey: u.speakerKey, start: u.start, lines: [(u.id, u.text)]))
        }
    }
    return blocks
}

struct TranscriptTab: View {
    @EnvironmentObject private var state: AppState
    let meetingID: UUID
    @State private var stickToBottom = true
    @State private var scrollToLiveRequest = 0

    var body: some View {
        let utterances = state.meeting(meetingID)?.utterances ?? []
        let recording = state.recordingID == meetingID
        let blocks = mergedBlocks(from: utterances)

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
                            TranscriptBlockView(meetingID: meetingID, block: block)
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
                    if recording { proxy.scrollTo("live", anchor: .bottom) }
                }
                .onChange(of: scrollToLiveRequest) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("live", anchor: .bottom)
                    }
                }
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

    var body: some View {
        VStack(alignment: .leading, spacing: GrokSpacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: GrokSpacing.sm) {
                SpeakerChip(meetingID: meetingID, key: block.speakerKey)
                Text(Meeting.timestamp(block.start))
                    .font(GrokTypography.captionMuted().monospacedDigit())
                    .foregroundStyle(GrokColors.timestamp)
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
                            MarkdownView(markdown: message.content)
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
        Text((try? AttributedString(markdown: text)) ?? AttributedString(text))
    }
}
