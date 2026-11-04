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

    @ViewBuilder
    private func topics(_ meeting: Meeting) -> some View {
        let finding = state.findingTopics.contains(meetingID)
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
        } else if finding {
            HStack(spacing: GrokSpacing.sm) {
                ProgressView().controlSize(.small)
                Text("Finding topics…").font(GrokTypography.captionMuted()).foregroundStyle(.secondary)
            }
        } else if !state.processing.contains(meetingID) {
            Button {
                Task { await state.findTopics(meetingID) }
            } label: {
                Label("Find topics", systemImage: "sparkles")
            }
            .controlSize(.small)
        }
    }
}
