import SwiftUI

// MARK: - Waveform mark

/// The amber waveform from the app icon: symmetric rounded bars, tallest in the middle.
/// Used sparingly: the sidebar wordmark, empty states, the Home greeting, and live recording.
/// When `animating`, the bars breathe; Reduce Motion keeps them still.
struct WaveformMark: View {
    var bars = 7
    var height: CGFloat = 16
    var color: Color = GrokColors.amber
    var animating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if animating, !reduceMotion {
                TimelineView(.animation(minimumInterval: 1 / 20)) { context in
                    shape(phase: context.date.timeIntervalSinceReferenceDate)
                }
            } else {
                shape(phase: nil)
            }
        }
        .frame(width: width, height: height)
        .accessibilityHidden(true)
    }

    private var barWidth: CGFloat { max(1.5, (height / 6.5).rounded(.toNearestOrEven)) }
    private var gap: CGFloat { max(1, barWidth * 0.8) }
    private var width: CGFloat { CGFloat(bars) * barWidth + CGFloat(bars - 1) * gap }

    private func shape(phase: Double?) -> some View {
        HStack(alignment: .center, spacing: gap) {
            ForEach(0..<bars, id: \.self) { i in
                Capsule()
                    .fill(color)
                    .frame(width: barWidth, height: max(barWidth, height * scale(i, phase: phase)))
            }
        }
    }

    /// The icon's profile: full height in the middle, falling to 30% at the ends.
    private func scale(_ i: Int, phase: Double?) -> CGFloat {
        let mid = Double(bars - 1) / 2
        let x = mid > 0 ? abs(Double(i) - mid) / mid : 0
        var s = 1 - 0.7 * pow(x, 1.1)
        if let phase {
            s *= 0.62 + 0.38 * (0.5 + 0.5 * sin(phase * 5.2 + Double(i) * 1.3))
        }
        return CGFloat(s)
    }
}

/// The wordmark at the top of the sidebar.
struct SidebarBrandHeader: View {
    var body: some View {
        HStack(spacing: GrokSpacing.sm) {
            WaveformMark(bars: 5, height: 14)
            Text("GrokNola")
                .font(GrokTypography.wordmark)
                .foregroundStyle(GrokColors.ink)
        }
        .padding(.vertical, GrokSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Panels

/// The one card style: `paper2` fill, a warm hairline, 12-point corners. Increase Contrast thickens the border.
struct GrokPanelBackground: ViewModifier {
    var fill: Color = GrokColors.paper2
    var radius: CGFloat = GrokRadius.panel
    var border: Color = GrokColors.hairline
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(border, lineWidth: contrast == .increased ? 1.5 : 1)
            )
    }
}

extension View {
    func grokPanel(fill: Color = GrokColors.paper2, radius: CGFloat = GrokRadius.panel, border: Color = GrokColors.hairline) -> some View {
        modifier(GrokPanelBackground(fill: fill, radius: radius, border: border))
    }

    /// The paper canvas behind notes, transcripts, and answers, with warm ink as the default text color.
    func grokPaper() -> some View {
        foregroundStyle(GrokColors.ink).background(GrokColors.paper)
    }
}

/// A padded panel that fills its width.
struct GrokPanel<Content: View>: View {
    var padding: CGFloat = GrokSpacing.lg
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .grokPanel()
    }
}

/// A panel's title row: an SF Symbol, the title, and an optional count or note on the right.
struct GrokSectionHeader: View {
    let title: String
    var systemImage: String?
    var trailing: String?

    var body: some View {
        HStack(spacing: GrokSpacing.sm) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(GrokColors.inkMuted)
                    .frame(width: 18)
                    .accessibilityHidden(true)
            }
            Text(title).font(GrokTypography.heading)
            Spacer(minLength: GrokSpacing.sm)
            if let trailing {
                Text(trailing)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(GrokColors.inkMuted)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A small uppercase label over a group in a side column.
struct GrokEyebrow: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(GrokTypography.eyebrow)
            .tracking(0.6)
            .foregroundStyle(GrokColors.inkMuted)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Chips

/// Speaker, tag, and topic chips share one shape: a capsule with ink text.
struct GrokChip: View {
    enum Style {
        /// A color dot on a faint wash of the color: speakers and tags.
        case tinted(Color)
        /// Paper with a hairline: topics and neutral labels.
        case quiet
        /// Amber wash: "New" and other highlights.
        case accent
    }

    enum Size { case regular, compact }

    let title: String
    var style: Style = .quiet
    var size: Size = .regular
    var detail: String?
    var onRemove: (() -> Void)?
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: size == .compact ? 3 : 5) {
            if case .tinted(let color) = style {
                Circle().fill(color).frame(width: size == .compact ? 6 : 7, height: size == .compact ? 6 : 7)
            }
            Text(title)
                .fontWeight(.medium)
                .lineLimit(1)
                .foregroundStyle(GrokColors.ink)
            if let detail {
                Text(detail).foregroundStyle(GrokColors.inkMuted).lineLimit(1)
            }
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark").font(.caption2.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(GrokColors.inkMuted)
                .accessibilityLabel("Remove \(title)")
            }
        }
        .font(size == .compact ? .caption2 : .callout)
        .padding(.horizontal, size == .compact ? 6 : GrokSpacing.sm + 1)
        .padding(.vertical, size == .compact ? 1.5 : 3)
        .background(fill, in: Capsule())
        .overlay(Capsule().strokeBorder(border, lineWidth: 1))
    }

    private var fill: Color {
        switch style {
        case .tinted(let color): return color.opacity(0.15)
        case .quiet: return GrokColors.paper
        case .accent: return GrokColors.amberSoft
        }
    }

    private var border: Color {
        switch style {
        case .tinted(let color): return contrast == .increased ? color.opacity(0.6) : .clear
        case .quiet: return GrokColors.hairline
        case .accent: return contrast == .increased ? GrokColors.amberText.opacity(0.6) : .clear
        }
    }
}

// MARK: - Bars

/// A thin rounded bar for talk time, chapter share, and cost share.
struct GrokBar: View {
    let value: Double
    var color: Color = GrokColors.accent
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(GrokColors.track)
                Capsule()
                    .fill(color)
                    .frame(width: max(height * 0.66, geo.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

// MARK: - Empty states

/// A quiet empty state: the waveform mark, a serif title, and a line of guidance.
struct GrokEmptyState<Actions: View>: View {
    let title: String
    let message: String
    var alignment: HorizontalAlignment = .leading
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(alignment: alignment, spacing: GrokSpacing.md) {
            WaveformMark(bars: 7, height: 28)
                .padding(.bottom, GrokSpacing.xs)
            Text(title)
                .font(GrokTypography.title)
                .foregroundStyle(GrokColors.ink)
            Text(message)
                .foregroundStyle(GrokColors.inkMuted)
                .multilineTextAlignment(alignment == .center ? .center : .leading)
                .fixedSize(horizontal: false, vertical: true)
            actions
        }
    }
}

extension GrokEmptyState where Actions == EmptyView {
    init(title: String, message: String, alignment: HorizontalAlignment = .leading) {
        self.init(title: title, message: message, alignment: alignment) { EmptyView() }
    }
}

// MARK: - Chat

/// One turn of a conversation with Grok: your question in a bubble on the right, Grok's answer as serif text on the paper.
struct ChatTurnView<Answer: View>: View {
    let isUser: Bool
    let text: String
    @ViewBuilder var answer: Answer

    var body: some View {
        if isUser {
            HStack {
                Spacer(minLength: 80)
                Text(text)
                    .font(.body)
                    .foregroundStyle(GrokColors.ink)
                    .textSelection(.enabled)
                    .padding(.horizontal, GrokSpacing.md + 2)
                    .padding(.vertical, GrokSpacing.sm + 1)
                    .grokPanel(radius: 16)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("You: \(text)")
        } else {
            VStack(alignment: .leading, spacing: GrokSpacing.sm) {
                HStack(spacing: 6) {
                    WaveformMark(bars: 5, height: 10)
                    Text("Grok")
                        .font(GrokTypography.eyebrow)
                        .foregroundStyle(GrokColors.inkMuted)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Grok")
                answer
            }
        }
    }
}

/// The ask field: a rounded capsule with a send button, shared by Home, Ask Grok, and a meeting's Ask tab.
struct GrokComposer: View {
    let placeholder: String
    @Binding var text: String
    var canSend: Bool
    var systemImage: String?
    var multiline = false
    var focus: FocusState<Bool>.Binding?
    let send: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(alignment: multiline ? .bottom : .center, spacing: GrokSpacing.sm) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(GrokColors.amberText)
                    .accessibilityHidden(true)
            }
            field
            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(canSend ? Color.white : GrokColors.inkFaint)
                    .frame(width: 24, height: 24)
                    .background(canSend ? GrokColors.accent : GrokColors.paper3, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel("Send")
        }
        .padding(.leading, GrokSpacing.md + 2)
        .padding(.trailing, GrokSpacing.xs + 2)
        .padding(.vertical, GrokSpacing.xs + 2)
        .grokPanel(fill: GrokColors.paper, radius: 18)
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
        .opacity(isEnabled ? 1 : 0.6)
    }

    @ViewBuilder
    private var field: some View {
        let base = TextField(placeholder, text: $text, axis: multiline ? .vertical : .horizontal)
            .textFieldStyle(.plain)
            .lineLimit(multiline ? 1...5 : 1...1)
            .padding(.vertical, 4)
            .onSubmit(send)
        if let focus {
            base.focused(focus)
        } else {
            base
        }
    }
}

// MARK: - Links

/// A text link in amber, underlined on hover, for links on the paper.
struct GrokLinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        GrokLinkLabel(configuration: configuration)
    }

    private struct GrokLinkLabel: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .foregroundStyle(isEnabled ? GrokColors.amberText : GrokColors.inkFaint)
                .underline(hovering && isEnabled)
                .opacity(configuration.isPressed ? 0.7 : 1)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}

// MARK: - Paper edge

/// A faint shadow along the paper's edge where it meets a side column.
struct PageEdge: View {
    var body: some View {
        LinearGradient(colors: [Color.black.opacity(0.05), .clear], startPoint: .leading, endPoint: .trailing)
            .frame(width: 6)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
