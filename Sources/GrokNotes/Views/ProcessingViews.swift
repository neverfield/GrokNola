import SwiftUI

/// The after-meeting steps as one row: done, running, waiting, or failed with Retry.
struct ProcessingStepsRow: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.undoManager) private var undoManager
    let meetingID: UUID

    var body: some View {
        if let progress = state.processingStage[meetingID] {
            let busy = state.processing.contains(meetingID)
            VStack(alignment: .leading, spacing: GrokSpacing.xs) {
                ViewThatFits(in: .horizontal) {
                    steps(progress, short: false)
                    steps(progress, short: true)
                }
                ForEach(progress.failures, id: \.step) { failure in
                    failureLine(failure.step, failure.message, busy: busy)
                }
            }
            .padding(.horizontal, GrokSpacing.lg)
            .padding(.vertical, GrokSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GrokColors.paper2)
            .overlay(alignment: .top) { GrokColors.hairline.frame(height: 1) }
            .overlay(alignment: .bottom) { GrokColors.hairline.frame(height: 1) }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Processing steps")
        }
    }

    private func steps(_ progress: ProcessingProgress, short: Bool) -> some View {
        HStack(spacing: GrokSpacing.lg) {
            ForEach(progress.visibleSteps) { step in
                StepLabel(step: step, entry: progress.entry(step) ?? .init(), short: short)
            }
        }
        .fixedSize()
    }

    private func failureLine(_ step: ProcessingProgress.Step, _ message: String, busy: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: GrokSpacing.sm) {
            Text("\(step.title) failed: \(message)")
                .font(GrokTypography.captionMuted())
                .foregroundStyle(GrokColors.inkMuted)
                .lineLimit(2)
                .textSelection(.enabled)
            Spacer(minLength: GrokSpacing.sm)
            if step.isRetryable {
                Button("Retry") { Task { await state.retry(step, for: meetingID, undoManager: undoManager) } }
                    .controlSize(.small)
                    .disabled(busy)
                    .help("Run \(step.title.lowercased()) again")
            }
            Button {
                state.dismissProcessingStage(meetingID)
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .foregroundStyle(GrokColors.inkMuted)
            .disabled(busy)
            .help("Hide these steps")
            .accessibilityLabel("Hide processing steps")
        }
    }
}

private struct StepLabel: View {
    let step: ProcessingProgress.Step
    let entry: ProcessingProgress.Entry
    let short: Bool

    var body: some View {
        HStack(spacing: GrokSpacing.xs) {
            icon.frame(width: 14, height: 14)
            Text(short ? shortTitle : step.title)
                .font(GrokTypography.captionMuted())
                .foregroundStyle(entry.status == .pending ? GrokColors.inkFaint : GrokColors.inkMuted)
            if entry.status == .running, let started = entry.startedAt {
                TimelineView(.periodic(from: started, by: 1)) { context in
                    Text("\(max(0, Int(context.date.timeIntervalSince(started))))s")
                        .font(GrokTypography.captionMuted().monospacedDigit())
                        .foregroundStyle(GrokColors.inkFaint)
                }
            }
        }
        .help(help)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(step.title), \(statusText)")
    }

    @ViewBuilder
    private var icon: some View {
        switch entry.status {
        case .done, .skipped:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(GrokColors.success)
        case .running:
            ProgressView().controlSize(.mini)
        case .pending:
            Image(systemName: "circle").foregroundStyle(GrokColors.inkFaint)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(GrokColors.warning)
        }
    }

    private var shortTitle: String {
        switch step {
        case .transcribing: return "Transcript"
        case .naming: return "Speakers"
        case .writing: return "Notes"
        case .tagging: return "Tags"
        }
    }

    private var statusText: String {
        switch entry.status {
        case .done, .skipped: return "done"
        case .running: return "running"
        case .pending: return "waiting"
        case .failed(let message): return "failed: \(message)"
        }
    }

    private var help: String {
        if case .failed(let message) = entry.status { return message }
        if let start = entry.startedAt, let end = entry.endedAt {
            return "\(step.title): \(statusText) in \(max(1, Int(end.timeIntervalSince(start))))s"
        }
        return "\(step.title): \(statusText)"
    }
}

/// The selected template's headings with placeholder lines, while Grok writes the notes.
struct NotesSkeleton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let template: SummaryTemplate

    private static let fallbackSections = ["Summary", "Key points", "Action items"]
    private static let lineWidths: [[CGFloat]] = [[0.92, 0.78, 0.55], [0.86, 0.64], [0.95, 0.7, 0.82, 0.4]]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GrokSpacing.lg) {
                HStack(spacing: GrokSpacing.sm) {
                    WaveformMark(bars: 5, height: 12, animating: true)
                    Text("Grok is writing your notes with \(template.name)…")
                        .font(.callout)
                        .foregroundStyle(GrokColors.inkMuted)
                }
                let sections = template.sections.isEmpty ? Self.fallbackSections : template.sections
                ForEach(Array(sections.enumerated()), id: \.offset) { index, title in
                    VStack(alignment: .leading, spacing: GrokSpacing.sm) {
                        Text(title)
                            .font(.system(size: 19, weight: .semibold, design: .serif))
                            .foregroundStyle(GrokColors.inkFaint)
                        placeholderLines(Self.lineWidths[index % Self.lineWidths.count], phase: Double(index) * 0.35)
                    }
                }
            }
            .padding(GrokSpacing.contentInset)
            .frame(maxWidth: GrokSpacing.measure + 2 * GrokSpacing.contentInset, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(GrokColors.paper)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Writing notes with the \(template.name) template")
    }

    private func placeholderLines(_ widths: [CGFloat], phase: Double) -> some View {
        GeometryReader { geo in
            if reduceMotion {
                lines(widths, width: geo.size.width, opacity: 0.5)
            } else {
                TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    lines(widths, width: geo.size.width, opacity: 0.35 + 0.3 * (0.5 + 0.5 * sin(t * 2.4 - phase)))
                }
            }
        }
        .frame(height: CGFloat(widths.count) * 18)
    }

    private func lines(_ widths: [CGFloat], width: CGFloat, opacity: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(widths.enumerated()), id: \.offset) { _, fraction in
                RoundedRectangle(cornerRadius: 4)
                    .fill(GrokColors.ink.opacity(opacity * 0.16))
                    .frame(width: width * fraction, height: 10)
            }
        }
    }
}

/// Two lines of what is being said, under the notepad while recording. Click the header to collapse it.
struct LiveTranscriptStrip: View {
    @EnvironmentObject private var recording: RecordingModel
    let meetingID: UUID
    @AppStorage("notesLiveStripExpanded") private var expanded = true

    var body: some View {
        let them = recording.liveThem.isEmpty ? recording.lastThem : recording.liveThem
        let me = recording.liveMe.isEmpty ? recording.lastMe : recording.liveMe
        VStack(alignment: .leading, spacing: GrokSpacing.xs) {
            Button {
                expanded.toggle()
            } label: {
                HStack(spacing: GrokSpacing.xs) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .frame(width: 10)
                    WaveformMark(bars: 5, height: 11, animating: true)
                    Text("Live")
                        .font(GrokTypography.captionMuted().weight(.semibold))
                    if !expanded, let latest = [them, me].first(where: { !$0.isEmpty }) {
                        Text(latest)
                            .font(GrokTypography.captionMuted())
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                    Spacer()
                }
                .foregroundStyle(GrokColors.inkMuted)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(expanded ? "Hide the live transcript" : "Show the live transcript")
            .accessibilityLabel(expanded ? "Collapse live transcript" : "Expand live transcript")

            if expanded {
                line(
                    recording.liveThem.isEmpty ? "Them" : recording.liveThemTalker ?? "Them",
                    key: recording.liveThem.isEmpty ? recording.lastThemKey : recording.liveThemKey,
                    them.isEmpty ? "Listening…" : them, live: !recording.liveThem.isEmpty
                )
                line("You", me.isEmpty ? "Listening…" : me, live: !recording.liveMe.isEmpty)
            }
        }
        .padding(.horizontal, GrokSpacing.lg)
        .padding(.vertical, GrokSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GrokColors.paper2)
        .overlay(alignment: .top) { GrokColors.hairline.frame(height: 1) }
    }

    private func line(_ label: String, key: String? = nil, _ text: String, live: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: GrokSpacing.sm) {
            LiveSpeakerLabel(meetingID: meetingID, label: label, key: key)
            Text(text)
                .font(GrokTypography.liveLine())
                .foregroundStyle(live ? GrokColors.ink : GrokColors.inkMuted)
                .lineLimit(1)
                .truncationMode(.head)
        }
        .accessibilityElement(children: .contain)
    }
}

/// The speaker beside a live line: the name of the voice on that line once it is known, or a fixed label.
/// Click a name to rename that speaker while recording.
struct LiveSpeakerLabel: View {
    let meetingID: UUID
    let label: String
    let key: String?

    var body: some View {
        Group {
            if let key {
                SpeakerChip(
                    meetingID: meetingID, key: key, plain: true,
                    plainFont: GrokTypography.captionMuted().weight(.semibold)
                )
                .lineLimit(1)
            } else {
                Text(label)
                    .font(GrokTypography.captionMuted().weight(.semibold))
                    .foregroundStyle(GrokColors.inkMuted)
            }
        }
        .frame(minWidth: 36, maxWidth: 200, alignment: .trailing)
        .layoutPriority(1)
    }
}
