import SwiftUI

extension Citations {
    /// Tinted, padded styling for citation links in SwiftUI text, matching the pills in rendered notes.
    static func style(_ attributed: inout AttributedString) {
        let ranges = attributed.runs.filter { run in
            run.link.map { target(from: $0) != nil || playTarget(from: $0) != nil } ?? false
        }.map(\.range)
        // Indices go stale after an insert, so work from character offsets, last citation first.
        let offsets = ranges.map {
            (attributed.characters.distance(from: attributed.startIndex, to: $0.lowerBound),
             attributed.characters.distance(from: attributed.startIndex, to: $0.upperBound))
        }
        for (lower, upper) in offsets.reversed() {
            let range = attributed.index(attributed.startIndex, offsetByCharacters: lower)..<attributed.index(attributed.startIndex, offsetByCharacters: upper)
            attributed[range].font = GrokTypography.citation()
            attributed[range].foregroundColor = GrokColors.ink
            attributed[range].backgroundColor = GrokColors.amberSoft
            let container = attributed[range].runs.first?.attributes ?? AttributeContainer()
            let pad = AttributedString("\u{202F}", attributes: container)
            attributed.insert(pad, at: attributed.index(attributed.startIndex, offsetByCharacters: upper))
            attributed.insert(pad, at: attributed.index(attributed.startIndex, offsetByCharacters: lower))
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
                    WaveformMark(bars: 5, height: 14, animating: true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title(clip, meeting))
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                            Text(clip.map { "\(Meeting.timestamp($0.start)) – \(Meeting.timestamp($0.end))" }
                                 ?? "\(Meeting.timestamp(clips.currentTime)) / \(Meeting.timestamp(clips.duration))")
                        }
                        .font(GrokTypography.captionMuted().monospacedDigit())
                        .foregroundStyle(GrokColors.inkMuted)
                    }
                    TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                        if let clip {
                            GrokBar(value: clips.elapsed / max(0.1, clip.end - clip.start), color: GrokColors.amber, height: 4)
                        } else {
                            GrokBar(value: clips.currentTime / max(0.1, clips.duration), color: GrokColors.amber, height: 4)
                        }
                    }
                    .frame(maxWidth: 240)
                    .accessibilityElement()
                    .accessibilityLabel("Playback progress")
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

/// Plays the recording from a transcript block on. Faint until hovered, focused, or playing that block.
struct ClipPlayButton: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var clips: ClipPlayer
    let meetingID: UUID
    let start: Double
    var visible: Bool
    /// Whether playback is inside this block.
    var current = false
    @FocusState private var focused: Bool

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
                .foregroundStyle(playing ? GrokColors.accent : GrokColors.inkMuted)
        }
        .buttonStyle(.plain)
        .help(playing ? "Pause" : "Play from here")
        .accessibilityLabel(playing ? "Pause" : "Play from \(Citations.label(start))")
        .focused($focused)
        .opacity(visible || playing || focused ? 1 : GrokOpacity.idleControl)
    }
}

/// One quiet line under notes with citations when this meeting's audio was not kept.
struct KeepAudioHint: View {
    var body: some View {
        Label("Turn on Keep audio in Settings to play clips from future meetings.", systemImage: "speaker.slash")
            .font(GrokTypography.captionMuted())
            .foregroundStyle(GrokColors.inkMuted)
    }
}
