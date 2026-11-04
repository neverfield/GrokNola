import SwiftUI

/// Duration, who talked how much, and the main topics, shown above the notes.
struct CallSummaryCard: View {
    @EnvironmentObject private var state: AppState
    let meetingID: UUID

    var body: some View {
        if let meeting = state.meeting(meetingID) {
            let stats = meeting.talkStats(myName: Prefs.myName)
            VStack(alignment: .leading, spacing: GrokSpacing.md) {
                header(meeting)
                VStack(alignment: .leading, spacing: GrokSpacing.sm) {
                    ForEach(stats, id: \.key) { stat in
                        participantRow(stat)
                    }
                }
                topics(meeting)
            }
            .padding(GrokSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func header(_ meeting: Meeting) -> some View {
        HStack(spacing: GrokSpacing.sm) {
            Label(Meeting.durationLabel(meeting.duration), systemImage: "clock")
            Text("·").foregroundStyle(.tertiary)
            Text(meeting.startedAt.formatted(date: .abbreviated, time: .shortened))
            if let app = meeting.appName, !app.isEmpty {
                Text("·").foregroundStyle(.tertiary)
                Label(app, systemImage: MeetingAppIcon.symbol(for: app))
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    private func participantRow(_ stat: TalkStat) -> some View {
        HStack(spacing: GrokSpacing.md) {
            SpeakerChip(meetingID: meetingID, key: stat.key)
                .frame(width: 150, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(SpeakerColor.color(for: stat.key))
                        .frame(width: max(4, geo.size.width * stat.share))
                }
            }
            .frame(height: 6)
            Text("\(Int((stat.share * 100).rounded()))%")
                .font(.callout.monospacedDigit().weight(.medium))
                .frame(width: 40, alignment: .trailing)
            Text(Meeting.durationLabel(stat.seconds))
                .font(GrokTypography.captionMuted().monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)
        }
        .help("\(stat.words) words")
    }

    /// Chapters when the meeting has them; otherwise its topics and a Find chapters button.
    @ViewBuilder
    private func topics(_ meeting: Meeting) -> some View {
        let finding = state.findingTopics.contains(meetingID)
        if let chapters = meeting.chapters, !chapters.isEmpty {
            chapterRows(chapters)
        } else {
            if let topics = meeting.topics, !topics.isEmpty {
                FlowLayout(spacing: GrokSpacing.xs) {
                    ForEach(topics, id: \.self) { topic in
                        Text(topic)
                            .font(.callout)
                            .padding(.horizontal, GrokSpacing.sm)
                            .padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                    }
                }
            }
            if finding {
                HStack(spacing: GrokSpacing.sm) {
                    ProgressView().controlSize(.small)
                    Text("Finding chapters…").font(GrokTypography.captionMuted()).foregroundStyle(.secondary)
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

    private func chapterRows(_ chapters: [Chapter]) -> some View {
        let total = max(1, chapters.map(\.length).reduce(0, +))
        let playable = state.canPlayClips(meetingID)
        return VStack(alignment: .leading, spacing: 2) {
            Text("Chapters")
                .font(GrokTypography.captionMuted().weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)
            ForEach(Array(chapters.enumerated()), id: \.offset) { i, chapter in
                let share = chapter.length / total
                Button {
                    state.openChapter(meetingID, chapter)
                } label: {
                    HStack(spacing: GrokSpacing.md) {
                        Text(Meeting.timestamp(chapter.start))
                            .font(GrokTypography.captionMuted().monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 52, alignment: .leading)
                        Text(chapter.title)
                            .font(.callout)
                            .lineLimit(1)
                        Spacer(minLength: GrokSpacing.sm)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.quaternary)
                                Capsule()
                                    .fill(ChapterColor.color(i))
                                    .frame(width: max(4, geo.size.width * share))
                            }
                        }
                        .frame(width: 90, height: 6)
                        Text("\(Int((share * 100).rounded()))%")
                            .font(GrokTypography.captionMuted().monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 34, alignment: .trailing)
                    }
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(playable ? "Play from \(Meeting.timestamp(chapter.start)) (\(Meeting.durationLabel(chapter.length)))" : "Show in the transcript")
            }
        }
    }
}
