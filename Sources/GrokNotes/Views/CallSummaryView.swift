import SwiftUI

/// Duration, who talked how much, and the main topics. A side column beside the notes in a wide pane,
/// or a collapsible card above them in a narrow one.
struct CallSummaryCard: View {
    enum Style { case card, sidebar }

    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var clips: ClipPlayer
    @Environment(\.undoManager) private var undoManager
    let meetingID: UUID
    var style: Style = .card
    @AppStorage("callSummaryExpanded") private var expanded = true
    /// The chapter under the playhead, from the player's ticks.
    @State private var currentChapter: Int?

    var body: some View {
        if let meeting = state.meeting(meetingID) {
            let stats = meeting.talkStats(myName: Prefs.myName)
            let chapters = meeting.chapters ?? []
            Group {
                switch style {
                case .card: card(meeting, stats: stats)
                case .sidebar: sidebar(meeting, stats: stats)
                }
            }
            .onAppear {
                if clips.loadedID == meetingID, clips.currentTime > 0 {
                    currentChapter = Chapters.index(at: clips.currentTime, in: chapters)
                }
            }
            .onReceive(clips.ticks) { tick in
                guard tick.meetingID == meetingID else { return }
                let i = Chapters.index(at: tick.seconds, in: chapters)
                if i != currentChapter { currentChapter = i }
            }
        }
    }

    // MARK: Layouts

    private func card(_ meeting: Meeting, stats: [TalkStat]) -> some View {
        VStack(alignment: .leading, spacing: GrokSpacing.md) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: GrokSpacing.sm) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(GrokColors.inkMuted)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                    Text("Call summary").font(.callout.weight(.semibold))
                    header(meeting)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(expanded ? "Hide the call summary" : "Show the call summary")
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            if expanded {
                VStack(alignment: .leading, spacing: GrokSpacing.sm) {
                    ForEach(stats, id: \.key) { stat in
                        participantRow(stat)
                    }
                }
                topics(meeting, compact: false)
            }
        }
        .padding(GrokSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .grokPanel()
    }

    private func sidebar(_ meeting: Meeting, stats: [TalkStat]) -> some View {
        VStack(alignment: .leading, spacing: GrokSpacing.xl) {
            VStack(alignment: .leading, spacing: 3) {
                Text(Meeting.durationLabel(meeting.duration))
                    .font(GrokTypography.figure)
                    .foregroundStyle(GrokColors.ink)
                Text(meeting.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.callout)
                    .foregroundStyle(GrokColors.inkMuted)
                if let app = meeting.appName, !app.isEmpty {
                    Label(app, systemImage: MeetingAppIcon.symbol(for: app))
                        .font(.callout)
                        .foregroundStyle(GrokColors.inkMuted)
                }
            }
            .accessibilityElement(children: .combine)
            if !stats.isEmpty {
                VStack(alignment: .leading, spacing: GrokSpacing.md) {
                    sectionTitle("Speakers")
                    ForEach(stats, id: \.key) { stat in
                        compactParticipantRow(stat)
                    }
                }
            }
            VStack(alignment: .leading, spacing: GrokSpacing.sm) {
                if !(meeting.chapters ?? []).isEmpty { sectionTitle("Chapters") }
                topics(meeting, compact: true)
            }
        }
        .padding(GrokSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionTitle(_ title: String) -> some View {
        GrokEyebrow(title)
    }

    private func header(_ meeting: Meeting) -> some View {
        HStack(spacing: GrokSpacing.sm) {
            Label(Meeting.durationLabel(meeting.duration), systemImage: "clock")
            Text("·").foregroundStyle(GrokColors.inkFaint)
            Text(meeting.startedAt.formatted(date: .abbreviated, time: .shortened))
            if let app = meeting.appName, !app.isEmpty {
                Text("·").foregroundStyle(GrokColors.inkFaint)
                Label(app, systemImage: MeetingAppIcon.symbol(for: app))
            }
        }
        .font(.callout)
        .foregroundStyle(GrokColors.inkMuted)
        .lineLimit(1)
    }

    // MARK: Speakers

    private func bar(_ share: Double, color: Color, height: CGFloat = 6) -> some View {
        GrokBar(value: share, color: color, height: height)
    }

    private func percent(_ share: Double) -> String { "\(Int((share * 100).rounded()))%" }

    private func participantRow(_ stat: TalkStat) -> some View {
        HStack(spacing: GrokSpacing.md) {
            SpeakerChip(meetingID: meetingID, key: stat.key)
                .frame(width: 150, alignment: .leading)
            bar(stat.share, color: SpeakerColor.color(for: stat.key, in: state.meeting(meetingID)))
            Text(percent(stat.share))
                .font(.callout.monospacedDigit().weight(.medium))
                .frame(width: 40, alignment: .trailing)
            Text(Meeting.durationLabel(stat.seconds))
                .font(GrokTypography.captionMuted().monospacedDigit())
                .foregroundStyle(GrokColors.inkMuted)
                .frame(width: 60, alignment: .trailing)
        }
        .help("\(stat.words) words")
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spokenTalkTime(stat))
        .contextMenu { mergeMenu(stat) }
    }

    @ViewBuilder
    private func mergeMenu(_ stat: TalkStat) -> some View {
        if stat.key != Meeting.meKey {
            MergeSpeakerMenu(meetingID: meetingID, key: stat.key, undoManager: undoManager)
        }
    }

    /// "Sani Yo, 47 percent, 25 minutes" for VoiceOver.
    private func spokenTalkTime(_ stat: TalkStat) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = stat.seconds >= 60 ? [.hour, .minute] : [.second]
        let duration = formatter.string(from: stat.seconds.rounded()) ?? Meeting.durationLabel(stat.seconds)
        return "\(stat.name), \(Int((stat.share * 100).rounded())) percent, \(duration)"
    }

    /// Chip and numbers on one line, a full-width bar beneath.
    private func compactParticipantRow(_ stat: TalkStat) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: GrokSpacing.sm) {
                SpeakerChip(meetingID: meetingID, key: stat.key)
                    .lineLimit(1)
                Spacer(minLength: GrokSpacing.xs)
                Text(percent(stat.share))
                    .font(.callout.monospacedDigit().weight(.medium))
                Text(Meeting.durationLabel(stat.seconds))
                    .font(GrokTypography.captionMuted().monospacedDigit())
                    .foregroundStyle(GrokColors.inkMuted)
            }
            bar(stat.share, color: SpeakerColor.color(for: stat.key, in: state.meeting(meetingID)), height: 5)
        }
        .help("\(stat.words) words")
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spokenTalkTime(stat))
        .contextMenu { mergeMenu(stat) }
    }

    // MARK: Chapters

    /// Chapters when the meeting has them; otherwise its topics and a Find chapters button.
    @ViewBuilder
    private func topics(_ meeting: Meeting, compact: Bool) -> some View {
        let finding = state.findingTopics.contains(meetingID)
        if let chapters = meeting.chapters, !chapters.isEmpty {
            chapterRows(chapters, compact: compact)
        } else {
            if let topics = meeting.topics, !topics.isEmpty {
                if compact { sectionTitle("Topics") }
                FlowLayout(spacing: GrokSpacing.xs) {
                    ForEach(topics, id: \.self) { topic in
                        GrokChip(title: topic)
                    }
                }
            }
            if finding {
                HStack(spacing: GrokSpacing.sm) {
                    ProgressView().controlSize(.small)
                    Text("Finding chapters…").font(GrokTypography.captionMuted()).foregroundStyle(GrokColors.inkMuted)
                }
            } else if !state.processing.contains(meetingID) {
                Button {
                    Task { await state.findChapters(meetingID) }
                } label: {
                    Label("Find chapters", systemImage: "sparkles")
                }
                .controlSize(.small)
                .help("Split the meeting into topic chapters")
            }
        }
    }

    private func chapterRows(_ chapters: [Chapter], compact: Bool) -> some View {
        let total = max(1, chapters.map(\.length).reduce(0, +))
        let playable = state.canPlayClips(meetingID)
        let loaded = clips.loadedID == meetingID
        return VStack(alignment: .leading, spacing: 2) {
            if !compact {
                sectionTitle("Chapters").padding(.bottom, 2)
            }
            ForEach(Array(chapters.enumerated()), id: \.offset) { i, chapter in
                let share = chapter.length / total
                let current = loaded && currentChapter == i
                Button {
                    state.openChapter(meetingID, chapter)
                } label: {
                    Group {
                        if compact {
                            compactChapterRow(i, chapter, share: share)
                        } else {
                            chapterRow(i, chapter, share: share)
                        }
                    }
                    .padding(.vertical, compact ? 5 : 3)
                    .padding(.horizontal, GrokSpacing.sm)
                    .background(GrokColors.amberSoft.opacity(current ? 0.8 : 0), in: RoundedRectangle(cornerRadius: GrokRadius.control))
                    .overlay(alignment: .leading) {
                        if current {
                            Capsule().fill(GrokColors.amber).frame(width: 3).padding(.vertical, 3)
                        }
                    }
                    .padding(.horizontal, -GrokSpacing.sm)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(playable ? "Play from \(Meeting.timestamp(chapter.start)) (\(Meeting.durationLabel(chapter.length)))" : "Show in the transcript")
                .accessibilityValue(current ? "Playing" : "")
            }
        }
        .animation(.easeOut(duration: 0.2), value: currentChapter)
    }

    private func chapterRow(_ i: Int, _ chapter: Chapter, share: Double) -> some View {
        HStack(spacing: GrokSpacing.md) {
            Text(Meeting.timestamp(chapter.start))
                .font(GrokTypography.captionMuted().monospacedDigit())
                .foregroundStyle(GrokColors.inkMuted)
                .frame(width: 52, alignment: .leading)
            Text(chapter.title)
                .font(.callout)
                .lineLimit(1)
            Spacer(minLength: GrokSpacing.sm)
            bar(share, color: ChapterColor.color(i))
                .frame(width: 90)
            Text(percent(share))
                .font(GrokTypography.captionMuted().monospacedDigit())
                .foregroundStyle(GrokColors.inkMuted)
                .frame(width: 34, alignment: .trailing)
        }
    }

    /// Time and title (up to two lines) with the share beneath.
    private func compactChapterRow(_ i: Int, _ chapter: Chapter, share: Double) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: GrokSpacing.sm) {
            Text(Meeting.timestamp(chapter.start))
                .font(GrokTypography.captionMuted().monospacedDigit())
                .foregroundStyle(GrokColors.inkMuted)
                .frame(width: 40, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text(chapter.title)
                    .font(.callout)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: GrokSpacing.sm) {
                    bar(share, color: ChapterColor.color(i), height: 4)
                    Text(percent(share))
                        .font(GrokTypography.captionMuted().monospacedDigit())
                        .foregroundStyle(GrokColors.inkMuted)
                        .frame(width: 30, alignment: .trailing)
                }
            }
        }
    }
}
