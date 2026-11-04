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
                HStack {
                    if enhanced != nil {
                        Picker("", selection: $showMyNotes) {
                            Text("Enhanced").tag(false)
                            Text("My notes").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 200)
                    }
                    if processing {
                        ProgressView().controlSize(.small)
                        Text("Grok is writing your notes…").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(enhanced == nil ? "Write notes" : "Regenerate") { Task { await state.regenerateNotes(meetingID) } }
                        .disabled(processing)
                    Button("Copy Markdown") { state.copyMarkdown(meetingID) }
                    Button("Show in Finder") { state.revealInFinder(meetingID) }
                }
                .padding(8)
                Divider()
            }

            if let enhanced, !recording, !showMyNotes {
                ScrollView {
                    MarkdownView(markdown: enhanced)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                TextEditor(text: state.binding(meetingID, \.userNotes, default: ""))
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .overlay(alignment: .topLeading) {
                        if (meeting?.userNotes ?? "").isEmpty {
                            Text("Jot rough notes here. When the meeting ends, Grok merges them with the transcript.")
                                .foregroundStyle(.tertiary)
                                .padding(15)
                                .allowsHitTesting(false)
                        }
                    }
            }
        }
    }
}

struct TranscriptTab: View {
    @EnvironmentObject private var state: AppState
    let meetingID: UUID

    var body: some View {
        let utterances = state.meeting(meetingID)?.utterances ?? []
        let recording = state.recordingID == meetingID

        ScrollViewReader { proxy in
            List {
                ForEach(utterances) { u in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(Meeting.timestamp(u.start))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 56, alignment: .trailing)
                        SpeakerChip(meetingID: meetingID, key: u.speakerKey)
                        Text(u.text).textSelection(.enabled)
                    }
                    .id(u.id)
                }
                if recording {
                    VStack(alignment: .leading, spacing: 4) {
                        if !state.liveThem.isEmpty { Text("Them: \(state.liveThem)") }
                        if !state.liveMe.isEmpty { Text("Me: \(state.liveMe)") }
                        if state.liveThem.isEmpty && state.liveMe.isEmpty { Text("Listening…") }
                    }
                    .italic()
                    .foregroundStyle(.secondary)
                    .id("live")
                } else if utterances.isEmpty {
                    Text("No transcript.").foregroundStyle(.secondary)
                }
            }
            .onChange(of: utterances.count) {
                if recording { proxy.scrollTo("live", anchor: .bottom) }
            }
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
                LazyVStack(alignment: .leading, spacing: 14) {
                    if chat.isEmpty {
                        Text("Ask anything about this meeting, for example \"What did we decide about pricing?\" or \"Draft a follow-up email.\"")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(chat) { message in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(message.role == "user" ? "You" : "Grok").font(.caption.bold()).foregroundStyle(.secondary)
                            MarkdownView(markdown: message.content)
                        }
                    }
                    if busy { ProgressView().controlSize(.small) }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                TextField("Ask about this meeting…", text: $question)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(send)
                Button("Ask", action: send).disabled(busy || question.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
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
        VStack(alignment: .leading, spacing: 6) {
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
            inline(String(line.dropFirst(2))).font(.title2.bold()).padding(.top, 4)
        } else if line.hasPrefix("## ") {
            inline(String(line.dropFirst(3))).font(.title3.bold()).padding(.top, 10)
        } else if line.hasPrefix("### ") {
            inline(String(line.dropFirst(4))).font(.headline).padding(.top, 6)
        } else if line.hasPrefix("- [ ] ") || line.lowercased().hasPrefix("- [x] ") {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: line.hasPrefix("- [ ] ") ? "square" : "checkmark.square")
                inline(String(line.dropFirst(6)))
            }
            .padding(.leading, indent)
        } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("•")
                inline(String(line.dropFirst(2)))
            }
            .padding(.leading, indent)
        } else if line.isEmpty {
            Spacer().frame(height: 2)
        } else {
            inline(line)
        }
    }

    private func inline(_ text: String) -> Text {
        Text((try? AttributedString(markdown: text)) ?? AttributedString(text))
    }
}
