import AppKit
import SwiftUI

/// Answers to questions heard in the call, newest first. Shown in the meeting inspector while recording.
struct LiveAnswersPanel: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var engine: LiveAnswersEngine
    @AppStorage("liveAnswersShowLatency") private var showLatency = false
    let meetingID: UUID
    @State private var draft = ""

    var body: some View {
        let recording = state.recordingID == meetingID
        let cards = engine.cards(for: meetingID)
        let pending = engine.cards.first { $0.meetingID == meetingID && !$0.isVisible }

        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: GrokSpacing.sm) {
                    if let pending {
                        HStack(spacing: GrokSpacing.xs) {
                            ProgressView().controlSize(.mini)
                            Text(pending.question).lineLimit(1)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help("Checking whether this question needs an answer")
                    }
                    if cards.isEmpty, pending == nil {
                        emptyState(recording: recording)
                    }
                    ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                        LiveAnswerCardView(card: card, showLatency: showLatency)
                            .opacity(card.isPinned ? 1 : max(0.5, 1 - Double(index) * 0.09))
                    }
                }
                .padding(GrokSpacing.md)
                .animation(.easeOut(duration: 0.15), value: cards.map(\.id))
            }
            if recording {
                Divider()
                askField
            }
        }
    }

    private var askField: some View {
        HStack(spacing: GrokSpacing.xs) {
            TextField("Ask now…", text: $draft)
                .textFieldStyle(.roundedBorder)
                .onSubmit(send)
            Button(action: send) { Image(systemName: "arrow.up.circle.fill") }
                .buttonStyle(.borderless)
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                .help("Answer with the live answers model")
        }
        .padding(GrokSpacing.sm)
    }

    @ViewBuilder
    private func emptyState(recording: Bool) -> some View {
        VStack(spacing: GrokSpacing.xs) {
            Image(systemName: recording && engine.enabled ? "waveform" : "bolt.slash")
                .font(.title3)
                .foregroundStyle(.tertiary)
            Text(!recording ? "Live answers appear while recording." : engine.enabled ? "Listening for questions" : "Live answers are off")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, GrokSpacing.xl)
    }

    private func send() {
        let q = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        draft = ""
        engine.ask(q)
    }
}

private struct LiveAnswerCardView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var engine: LiveAnswersEngine
    let card: LiveAnswerCard
    let showLatency: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: GrokSpacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: GrokSpacing.xs) {
                Text(card.asker).fontWeight(.semibold)
                Text(Meeting.timestamp(card.askedAt)).foregroundStyle(GrokColors.timestamp).monospacedDigit()
                if showLatency, let latency = card.latency {
                    Text(String(format: "%.1fs", latency)).foregroundStyle(GrokColors.timestamp).monospacedDigit()
                        .help("Time to first token")
                }
                Spacer(minLength: 0)
                if card.isPinned {
                    Image(systemName: "pin.fill").foregroundStyle(.orange).help("Pinned to your notes")
                }
            }
            .font(.caption)

            Text(card.question)
                .font(.callout.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)

            switch card.status {
            case .waiting:
                ProgressView().controlSize(.small)
            case .failed(let message):
                Text(message).font(.caption).foregroundStyle(.red).lineLimit(3)
            case .streaming, .done:
                MarkdownView(markdown: card.answer)
                    .font(.callout)
            }

            if !card.citedSources.isEmpty {
                Text("From " + card.citedSources.map { "\($0.title) · \($0.date.formatted(.dateTime.month(.abbreviated).day()))" }.joined(separator: ", "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: GrokSpacing.md) {
                Button {
                    if card.isPinned { state.unpinLiveAnswer(card.id) } else { state.pinLiveAnswer(card.id) }
                } label: {
                    Label(card.isPinned ? "Unpin" : "Pin", systemImage: card.isPinned ? "pin.slash" : "pin")
                }
                .disabled(card.status != .done)
                .help(card.isPinned ? "Remove from your notes" : "Add to your notes so it is kept")
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("Q: \(card.question)\nA: \(card.answer)", forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .disabled(card.answer.isEmpty)
                Spacer(minLength: 0)
                Button {
                    engine.dismiss(card.id)
                } label: {
                    Label("Dismiss", systemImage: "xmark")
                }
                .help("Dismiss")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(GrokSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(card.isPinned ? Color.orange.opacity(0.5) : Color.primary.opacity(0.06)))
    }
}
