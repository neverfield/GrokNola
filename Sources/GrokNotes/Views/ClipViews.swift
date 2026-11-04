import SwiftUI

extension Citations {
    /// Small, raised styling for citation and play links in rendered Markdown.
    static func style(_ attributed: inout AttributedString) {
        let ranges = attributed.runs.filter { run in
            run.link.map { target(from: $0) != nil || playTarget(from: $0) != nil } ?? false
        }.map(\.range)
        for range in ranges {
            attributed[range].font = GrokTypography.citation()
            attributed[range].baselineOffset = 2
        }
    }
}

/// A slim bar along the bottom while a clip plays: who, when, progress, and Stop (Escape).
struct NowPlayingBar: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var clips: ClipPlayer
    /// Shows the meeting title, for places outside the meeting itself.
    var showsMeetingTitle = false

    var body: some View {
        if let playing = clips.nowPlaying, let meeting = state.meeting(playing.meetingID) {
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: GrokSpacing.md) {
                    Image(systemName: "waveform")
                        .foregroundStyle(Color.accentColor)
                        .symbolEffect(.variableColor.iterative, options: .repeating)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title(playing, meeting))
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                        Text("\(Meeting.timestamp(playing.start)) – \(Meeting.timestamp(playing.end))")
                            .font(GrokTypography.captionMuted().monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                        ProgressView(value: clips.elapsed, total: max(0.1, playing.end - playing.start))
                            .progressViewStyle(.linear)
                    }
                    .frame(maxWidth: 240)
                    Spacer(minLength: 0)
                    Button {
                        clips.stop()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .keyboardShortcut(.escape, modifiers: [])
                    .help("Stop playback (Escape)")
                }
                .padding(.horizontal, GrokSpacing.lg)
                .padding(.vertical, GrokSpacing.sm)
            }
            .background(.bar)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func title(_ playing: ClipPlayer.NowPlaying, _ meeting: Meeting) -> String {
        let speaker = playing.speakerKey.map { meeting.displayName(for: $0, myName: Prefs.myName) }
        if showsMeetingTitle {
            return [speaker, meeting.title].compactMap { $0 }.joined(separator: " · ")
        }
        return speaker ?? "Clip"
    }
}

/// Plays a transcript block from its start to its end, shown on hover and while that block plays.
struct ClipPlayButton: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var clips: ClipPlayer
    let meetingID: UUID
    let start: Double
    let end: Double
    var visible: Bool

    var body: some View {
        let playing = clips.isPlaying(meetingID, at: start)
        Button {
            state.toggleClip(meetingID, at: start, until: end)
        } label: {
            Image(systemName: playing ? "stop.circle.fill" : "play.circle")
                .foregroundStyle(playing ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
        .help(playing ? "Stop" : "Play this part of the recording")
        .accessibilityLabel(playing ? "Stop clip" : "Play clip")
        .opacity(visible || playing ? 1 : 0)
    }
}

/// One quiet line under notes with citations when this meeting's audio was not kept.
struct KeepAudioHint: View {
    var body: some View {
        Label("Turn on Keep audio in Settings to play clips from future meetings.", systemImage: "speaker.slash")
            .font(GrokTypography.captionMuted())
            .foregroundStyle(.tertiary)
    }
}
