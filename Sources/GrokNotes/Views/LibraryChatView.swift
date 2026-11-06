import SwiftUI

/// One chat pane that answers across every meeting and about how GrokNola works.
struct LibraryChatView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @State private var question = ""
    @FocusState private var composerFocused: Bool

    private let meetingSuggestions = [
        "What did I commit to this week?",
        "Summarize my last three calls",
        "What open questions came up with customers?",
        "Draft a follow-up for my most recent meeting",
    ]

    private let helpSuggestions = [
        "How do speaker names work?",
        "How do I sync Google Calendar?",
        "Why is system audio off?",
        "How do I make a custom summary template?",
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
                                WaveformMark(bars: 5, height: 12, animating: true)
                                Text(state.libraryRoute == .help ? "Checking the GrokNola guide…" : "Searching \(state.meetings.count) meetings…")
                                    .foregroundStyle(GrokColors.inkMuted)
                            }
                            .accessibilityElement(children: .combine)
                            .id("thinking")
                        }
                    }
                    .padding(GrokSpacing.contentInset)
                    .padding(.bottom, GrokSpacing.lg)
                    .frame(maxWidth: GrokSpacing.measure + 2 * GrokSpacing.contentInset, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: state.libraryChat.count) {
                    withAnimation { proxy.scrollTo(state.libraryChat.last?.id, anchor: .bottom) }
                }
                .onChange(of: state.libraryAsking) {
                    if state.libraryAsking { withAnimation { proxy.scrollTo("thinking", anchor: .bottom) } }
                }
            }
            composer
        }
        .grokPaper()
        .navigationTitle("Ask Grok")
        .navigationSubtitle("Your meetings and how GrokNola works")
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
            guard let link = AppLink(url) else { return .systemAction }
            switch link {
            case .settings: openSettings()
            case .usage: openWindow(id: "usage")
            case .home: state.openHome()
            case .privacy(let anchor): state.openPrivacyPane(anchor)
            }
            NSApp.activate(ignoringOtherApps: true)
            return .handled
        })
        .onAppear { composerFocused = true }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: GrokSpacing.xl) {
            GrokEmptyState(
                title: "Ask about your meetings or GrokNola",
                message: "Grok finds the relevant meetings, reads their notes and transcripts, and links each answer back to its source. Ask how the app works, too: answers come from the built-in guide."
            )
            HStack(alignment: .top, spacing: GrokSpacing.lg) {
                suggestionGroup("Your meetings", meetingSuggestions)
                    .disabled(state.meetings.isEmpty)
                suggestionGroup("How GrokNola works", helpSuggestions)
            }
        }
        .padding(.top, GrokSpacing.xl)
    }

    private func suggestionGroup(_ title: String, _ suggestions: [String]) -> some View {
        VStack(alignment: .leading, spacing: GrokSpacing.sm) {
            GrokEyebrow(title)
            ForEach(suggestions, id: \.self) { suggestion in
                Button {
                    send(suggestion)
                } label: {
                    Label(suggestion, systemImage: "arrow.up.right")
                        .labelStyle(.titleAndIcon)
                        .font(.callout)
                }
                .buttonStyle(GrokLinkButtonStyle())
            }
        }
        .padding(GrokSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .grokPanel()
    }

    private func messageView(_ message: ChatMessage) -> some View {
        ChatTurnView(isUser: message.role == "user", text: message.content) {
            MarkdownView(markdown: message.content)
        }
    }

    private var composer: some View {
        GrokComposer(
            placeholder: "Ask about your meetings or GrokNola\u{2026}",
            text: $question,
            canSend: canSend,
            multiline: true,
            focus: $composerFocused
        ) { send(question) }
        .background {
            Button("Send") { send(question) }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!canSend)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        .help("Send (Command-Return)")
        .padding(GrokSpacing.lg)
        .frame(maxWidth: GrokSpacing.measure + 2 * GrokSpacing.lg)
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
