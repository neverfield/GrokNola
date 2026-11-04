import SwiftUI

/// One chat pane that searches and answers across every meeting.
struct LibraryChatView: View {
    @EnvironmentObject private var state: AppState
    @State private var question = ""
    @FocusState private var composerFocused: Bool

    private let suggestions = [
        "What did I commit to this week?",
        "Summarize my last three calls",
        "What open questions came up with customers?",
        "Draft a follow-up for my most recent meeting",
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: GrokSpacing.xl) {
                        if state.libraryChat.isEmpty {
                            emptyState
                        }
                        ForEach(state.libraryChat) { message in
                            messageView(message).id(message.id)
                        }
                        if state.libraryAsking {
                            HStack(spacing: GrokSpacing.sm) {
                                ProgressView().controlSize(.small)
                                Text("Searching \(state.meetings.count) meetings…").foregroundStyle(.secondary)
                            }
                            .id("thinking")
                        }
                    }
                    .padding(GrokSpacing.contentInset)
                    .frame(maxWidth: 720, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: state.libraryChat.count) {
                    withAnimation { proxy.scrollTo(state.libraryChat.last?.id, anchor: .bottom) }
                }
                .onChange(of: state.libraryAsking) {
                    if state.libraryAsking { withAnimation { proxy.scrollTo("thinking", anchor: .bottom) } }
                }
            }
            Divider()
            composer
        }
        .navigationTitle("Ask across notes")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    state.clearLibraryChat()
                } label: {
                    Label("New chat", systemImage: "square.and.pencil")
                }
                .help("Start a new conversation")
                .disabled(state.libraryChat.isEmpty || state.libraryAsking)
            }
        }
        .environment(\.openURL, OpenURLAction { url in
            if let id = LibraryAsk.meetingID(from: url) {
                state.openMeeting(id)
                return .handled
            }
            return .systemAction
        })
        .onAppear { composerFocused = true }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: GrokSpacing.lg) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
            Text("Ask across all your notes")
                .font(.title2.weight(.semibold))
            Text("Grok finds the relevant meetings, reads their notes and transcripts, and links each answer back to its source.")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: GrokSpacing.sm) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button {
                        send(suggestion)
                    } label: {
                        Label(suggestion, systemImage: "arrow.up.right")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.link)
                }
            }
            .disabled(state.meetings.isEmpty)
        }
        .padding(.top, GrokSpacing.xl)
    }

    private func messageView(_ message: ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: GrokSpacing.xs) {
            Text(message.role == "user" ? "You" : "Grok")
                .font(GrokTypography.captionMuted().weight(.semibold))
                .foregroundStyle(.secondary)
            if message.role == "user" {
                Text(message.content)
                    .font(.body.weight(.medium))
                    .textSelection(.enabled)
            } else {
                MarkdownView(markdown: message.content)
            }
        }
    }

    private var composer: some View {
        HStack(spacing: GrokSpacing.sm) {
            TextField("Ask about any meeting…", text: $question, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($composerFocused)
                .onSubmit { send(question) }
            Button {
                send(question)
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(.title2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(canSend ? Color.accentColor : .secondary)
            .disabled(!canSend)
            .keyboardShortcut(.return, modifiers: .command)
            .help("Send (Command-Return)")
        }
        .padding(GrokSpacing.md)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
        .padding(GrokSpacing.lg)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
    }

    private var canSend: Bool {
        !state.libraryAsking && !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send(_ text: String) {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !state.libraryAsking else { return }
        question = ""
        Task { await state.askLibrary(q) }
    }
}
