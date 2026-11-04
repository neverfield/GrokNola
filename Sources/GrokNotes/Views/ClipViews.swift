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

/// A slim bar along the bottom while audio plays outside its meeting: what, when, progress, and Stop (Escape).
struct NowPlayingBar: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var clips: ClipPlayer
    /// Shows the meeting title, for places outside the meeting itself.
    var showsMeetingTitle = false

    var body: some View {
        if clips.isPlaying, let id = clips.loadedID, let meeting = state.meeting(id) {
            let clip = clips.nowPlaying
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: GrokSpacing.md) {
                    Image(systemName: "waveform")
                        .foregroundStyle(Color.accentColor)
                        .symbolEffect(.variableColor.iterative, options: .repeating)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title(clip, meeting))
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                            Text(clip.map { "\(Meeting.timestamp($0.start)) – \(Meeting.timestamp($0.end))" }
                                 ?? "\(Meeting.timestamp(clips.currentTime)) / \(Meeting.timestamp(clips.duration))")
                        }
                        .font(GrokTypography.captionMuted().monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                    TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                        if let clip {
                            ProgressView(value: clips.elapsed, total: max(0.1, clip.end - clip.start))
                        } else {
                            ProgressView(value: clips.currentTime, total: max(0.1, clips.duration))
                        }
                    }
                    .progressViewStyle(.linear)
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

    private func title(_ clip: ClipPlayer.NowPlaying?, _ meeting: Meeting) -> String {
        let speaker = clip?.speakerKey.map { meeting.displayName(for: $0, myName: Prefs.myName) }
        if showsMeetingTitle || clip == nil {
            return [speaker, meeting.title].compactMap { $0 }.joined(separator: " · ")
        }
        return speaker ?? "Clip"
    }
}

/// Plays the recording from a transcript block on, shown on hover and while playback is in that block.
struct ClipPlayButton: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var clips: ClipPlayer
    let meetingID: UUID
    let start: Double
    var visible: Bool
    /// Whether playback is inside this block.
    var current = false

    var body: some View {
        let playing = current && clips.isPlaying && clips.loadedID == meetingID
        Button {
            if playing {
                clips.pause()
            } else {
                state.playMeeting(meetingID, from: max(0, start - 0.25))
            }
        } label: {
            Image(systemName: playing ? "pause.circle.fill" : "play.circle")
                .foregroundStyle(playing ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
        .help(playing ? "Pause" : "Play from here")
        .accessibilityLabel(playing ? "Pause" : "Play from here")
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
