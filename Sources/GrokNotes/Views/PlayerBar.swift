import AppKit
import SwiftUI

enum ChapterColor {
    private static let palette: [Color] = [.blue, .purple, .teal, .orange, .pink, .indigo, .mint, .brown]

    static func color(_ index: Int) -> Color { palette[index % palette.count] }
}

/// The bottom bar of a meeting with kept audio: transport, rate, and a timeline of the whole meeting with its chapters.
/// Space plays or pauses and the arrow keys move 5 seconds, unless a text field has focus.
struct MeetingPlayerBar: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var clips: ClipPlayer
    let meetingID: UUID
    /// Called when a chapter on the timeline is clicked, after playback moves there.
    var onChapter: (Chapter) -> Void = { _ in }
    @State private var keys = PlayerKeyMonitor()
    @State private var showVoices = false

    var body: some View {
        if let meeting = state.meeting(meetingID) {
            let loaded = clips.loadedID == meetingID
            let playing = loaded && clips.isPlaying
            let total = loaded && clips.duration > 0 ? clips.duration : Chapters.end(of: meeting)
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: GrokSpacing.md) {
                    transport(playing: playing)
                    TimelineView(.animation(minimumInterval: 0.1, paused: !playing)) { _ in
                        let now = loaded ? clips.currentTime : 0
                        HStack(spacing: GrokSpacing.sm) {
                            Text(Meeting.timestamp(now))
                                .frame(minWidth: 44, alignment: .trailing)
                            PlayerTimeline(
                                now: now,
                                total: total,
                                chapters: meeting.chapters ?? [],
                                seek: { state.seekPlayback(meetingID, to: $0) },
                                chapter: { chapter in
                                    state.playMeeting(meetingID, from: chapter.start)
                                    onChapter(chapter)
                                }
                            )
                            Text(Meeting.timestamp(total))
                                .frame(minWidth: 44, alignment: .leading)
                        }
                        .font(GrokTypography.captionMuted().monospacedDigit())
                        .foregroundStyle(.secondary)
                    }
                    rateMenu
                    voiceButton
                }
                .padding(.horizontal, GrokSpacing.lg)
                .padding(.vertical, GrokSpacing.sm)
            }
            .background(.bar)
            .background(HostWindowReader { keys.window = $0 })
            .onAppear {
                clips.load(meeting)
                keys.start { handle($0) }
            }
            .onDisappear { keys.stop() }
        }
    }

    private func transport(playing: Bool) -> some View {
        HStack(spacing: GrokSpacing.sm) {
            Button { state.skipPlayback(meetingID, by: -15) } label: {
                Image(systemName: "gobackward.15")
            }
            .help("Back 15 seconds")
            Button { state.togglePlayback(meetingID) } label: {
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.title2)
                    .frame(width: 22)
            }
            .help(playing ? "Pause (Space)" : "Play (Space)")
            .accessibilityLabel(playing ? "Pause" : "Play")
            Button { state.skipPlayback(meetingID, by: 15) } label: {
                Image(systemName: "goforward.15")
            }
            .help("Forward 15 seconds")
        }
        .font(.title3)
        .buttonStyle(.borderless)
    }

    private var rateMenu: some View {
        Menu {
            ForEach(ClipPlayer.rates, id: \.self) { rate in
                Toggle(Self.label(rate), isOn: Binding(get: { clips.rate == rate }, set: { _ in clips.setRate(rate) }))
            }
        } label: {
            Text(Self.label(clips.rate)).monospacedDigit()
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Playback speed")
    }

    private var voiceButton: some View {
        Button { showVoices.toggle() } label: {
            Image(systemName: voiceSymbol)
                .frame(width: 20)
                .foregroundStyle(clips.voicesAdjusted ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary))
        }
        .buttonStyle(.borderless)
        .help("Voice levels: set your voice and the other participants separately")
        .accessibilityLabel("Voice levels")
        .popover(isPresented: $showVoices, arrowEdge: .top) {
            VoiceLevelsPanel().environmentObject(clips)
        }
    }

    private var voiceSymbol: String {
        switch (clips.myVoiceMuted, clips.othersMuted) {
        case (true, true): "speaker.slash"
        case (false, false): "speaker.wave.2"
        default: "speaker.wave.1"
        }
    }

    private static func label(_ rate: Float) -> String {
        (rate == rate.rounded() ? String(format: "%.0f", rate) : String(format: "%g", rate)) + "×"
    }

    private func handle(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.numericPad, .function])
        guard modifiers.isEmpty else { return false }
        switch event.keyCode {
        case 49: state.togglePlayback(meetingID)
        case 123: state.skipPlayback(meetingID, by: -5)
        case 124: state.skipPlayback(meetingID, by: 5)
        default: return false
        }
        return true
    }
}

/// Separate levels for the microphone (you) and system audio (everyone else). Changes apply while playing.
private struct VoiceLevelsPanel: View {
    @EnvironmentObject private var clips: ClipPlayer

    var body: some View {
        VStack(alignment: .leading, spacing: GrokSpacing.md) {
            Toggle("Balance voices", isOn: Binding(get: { clips.balanceVoices }, set: { clips.setBalanceVoices($0) }))
                .toggleStyle(.switch)
                .controlSize(.small)
                .help("Bring your microphone and the other participants to the same speech level")
            row(
                "My voice",
                gain: Binding(get: { clips.myVoiceGain }, set: { clips.setMyVoiceGain($0) }),
                muted: Binding(get: { clips.myVoiceMuted }, set: { clips.setMyVoiceMuted($0) })
            )
            row(
                "Others",
                gain: Binding(get: { clips.othersGain }, set: { clips.setOthersGain($0) }),
                muted: Binding(get: { clips.othersMuted }, set: { clips.setOthersMuted($0) })
            )
            HStack {
                Text(clips.balanceVoices ? "0 dB is the balanced level." : "0 dB is the level as recorded.")
                    .font(GrokTypography.captionMuted())
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Reset") { clips.resetVoices() }
                    .controlSize(.small)
                    .disabled(!clips.voicesAdjusted)
            }
        }
        .padding(GrokSpacing.lg)
        .frame(width: 300)
    }

    private func row(_ title: String, gain: Binding<Double>, muted: Binding<Bool>) -> some View {
        HStack(spacing: GrokSpacing.sm) {
            Button { muted.wrappedValue.toggle() } label: {
                Image(systemName: muted.wrappedValue ? "speaker.slash" : "speaker.wave.2")
                    .frame(width: 20)
                    .foregroundStyle(muted.wrappedValue ? AnyShapeStyle(Color.red) : AnyShapeStyle(.secondary))
            }
            .buttonStyle(.borderless)
            .help(muted.wrappedValue ? "Unmute \(title.lowercased())" : "Mute \(title.lowercased())")
            .accessibilityLabel(muted.wrappedValue ? "Unmute \(title)" : "Mute \(title)")
            Text(title)
                .frame(width: 64, alignment: .leading)
            Slider(value: gain, in: Prefs.voiceGainRange)
                .controlSize(.small)
                .disabled(muted.wrappedValue)
                .accessibilityLabel(title)
                .accessibilityValue(Self.label(gain.wrappedValue))
            Text(Self.label(gain.wrappedValue))
                .font(GrokTypography.captionMuted().monospacedDigit())
                .foregroundStyle(muted.wrappedValue ? .tertiary : .secondary)
                .frame(width: 44, alignment: .trailing)
        }
    }

    /// "+3 dB", "−6 dB", or "0 dB".
    static func label(_ dB: Double) -> String {
        let rounded = Int(dB.rounded())
        if rounded == 0 { return "0 dB" }
        return (rounded > 0 ? "+" : "−") + "\(abs(rounded)) dB"
    }
}

/// The whole meeting as a track: chapter segments with titles above, a scrub line below.
/// Click or drag the line to seek; click a chapter to play from its start. Hover shows the time and chapter.
private struct PlayerTimeline: View {
    let now: Double
    let total: Double
    let chapters: [Chapter]
    let seek: (Double) -> Void
    let chapter: (Chapter) -> Void
    @State private var hoverX: CGFloat?
    @State private var dragTime: Double?

    private static let trackHeight: CGFloat = 6
    private static let labelHeight: CGFloat = 16

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            VStack(spacing: 3) {
                if !chapters.isEmpty { labels(width: width) }
                track(width: width)
            }
            .overlay(alignment: .topLeading) { hoverLabel(width: width) }
            .onContinuousHover { phase in
                switch phase {
                case .active(let point): hoverX = point.x
                case .ended: hoverX = nil
                }
            }
        }
        .frame(height: chapters.isEmpty ? 14 : Self.labelHeight + 3 + 14)
        .frame(minWidth: 160)
    }

    private func labels(width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(chapters.enumerated()), id: \.offset) { i, c in
                let x = position(c.start, width)
                let w = max(1, position(min(c.end, total), width) - x - 1)
                Button { chapter(c) } label: {
                    Text(w > 44 ? c.title : "")
                        .font(.caption2.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, 4)
                        .frame(width: w, height: Self.labelHeight, alignment: .leading)
                        .background(ChapterColor.color(i).opacity(0.14), in: RoundedRectangle(cornerRadius: 3))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .help("\(c.title) · \(Meeting.timestamp(c.start)) · \(Meeting.durationLabel(c.length))")
                .offset(x: x)
            }
        }
        .frame(width: width, height: Self.labelHeight, alignment: .topLeading)
    }

    private func track(width: CGFloat) -> some View {
        let shown = dragTime ?? now
        let playedWidth = position(shown, width)
        return ZStack(alignment: .leading) {
            segments(width: width, opacity: 0.25)
            segments(width: width, opacity: 0.9)
                .mask(alignment: .leading) { Rectangle().frame(width: playedWidth) }
            Circle()
                .fill(.white)
                .shadow(color: .black.opacity(0.3), radius: 1)
                .frame(width: 10, height: 10)
                .offset(x: playedWidth - 5)
        }
        .frame(width: width, height: 14)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { dragTime = time(at: $0.location.x, width) }
                .onEnded { value in
                    seek(time(at: value.location.x, width))
                    dragTime = nil
                }
        )
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue(Meeting.timestamp(shown))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: seek(now + 15)
            case .decrement: seek(now - 15)
            @unknown default: break
            }
        }
    }

    /// One colored run per chapter with a one-point gap between them, or a single gray run without chapters.
    private func segments(width: CGFloat, opacity: Double) -> some View {
        ZStack(alignment: .leading) {
            if chapters.isEmpty {
                Capsule().fill(Color.secondary.opacity(opacity))
            } else {
                ForEach(Array(chapters.enumerated()), id: \.offset) { i, c in
                    let x = position(c.start, width)
                    let w = max(1, position(min(c.end, total), width) - x - (i == chapters.count - 1 ? 0 : 1))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(ChapterColor.color(i).opacity(opacity))
                        .frame(width: w)
                        .offset(x: x)
                }
            }
        }
        .frame(width: width, height: Self.trackHeight, alignment: .leading)
    }

    @ViewBuilder
    private func hoverLabel(width: CGFloat) -> some View {
        if let x = dragTime.map({ position($0, width) }) ?? hoverX {
            let t = dragTime ?? time(at: x, width)
            let title = Chapters.index(at: t, in: chapters).map { chapters[$0].title }
            Text([Meeting.timestamp(t), title].compactMap { $0 }.joined(separator: " · "))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
                .fixedSize()
                .alignmentGuide(.leading) { d in -min(max(0, x - d.width / 2), max(0, width - d.width)) }
                .offset(y: -24)
                .allowsHitTesting(false)
        }
    }

    private func position(_ seconds: Double, _ width: CGFloat) -> CGFloat {
        guard total > 0 else { return 0 }
        return CGFloat(min(max(0, seconds / total), 1)) * width
    }

    private func time(at x: CGFloat, _ width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return Double(min(max(0, x / width), 1)) * total
    }
}

/// Watches key presses in one window for the player, leaving them to text fields that are being edited.
@MainActor
final class PlayerKeyMonitor {
    weak var window: NSWindow?
    private var token: Any?

    func start(_ handle: @escaping (NSEvent) -> Bool) {
        stop()
        token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window, event.window === window, window.attachedSheet == nil else { return event }
            if let text = window.firstResponder as? NSTextView, text.isEditable { return event }
            return handle(event) ? nil : event
        }
    }

    func stop() {
        if let token { NSEvent.removeMonitor(token) }
        token = nil
    }
}

/// Reports the window that hosts a view.
private struct HostWindowReader: NSViewRepresentable {
    let found: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { found(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { found(nsView.window) }
    }
}
