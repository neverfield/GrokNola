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
                                ProgressView().controlSize(.small)
                                Text(state.libraryRoute == .help ? "Checking the GrokNola guide…" : "Searching \(state.meetings.count) meetings…")
                                    .foregroundStyle(.secondary)
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
        VStack(alignment: .leading, spacing: GrokSpacing.lg) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
            Text("Ask about your meetings or GrokNola")
                .font(.title2.weight(.semibold))
            Text("Grok finds the relevant meetings, reads their notes and transcripts, and links each answer back to its source. Ask how the app works, too: answers come from the built-in guide.")
                .foregroundStyle(.secondary)
            suggestionGroup("Your meetings", meetingSuggestions)
                .disabled(state.meetings.isEmpty)
            suggestionGroup("How GrokNola works", helpSuggestions)
        }
        .padding(.top, GrokSpacing.xl)
    }

    private func suggestionGroup(_ title: String, _ suggestions: [String]) -> some View {
        VStack(alignment: .leading, spacing: GrokSpacing.sm) {
            Text(title)
                .font(GrokTypography.captionMuted().weight(.semibold))
                .foregroundStyle(.secondary)
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
            TextField("Ask about your meetings or GrokNola…", text: $question, axis: .vertical)
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
