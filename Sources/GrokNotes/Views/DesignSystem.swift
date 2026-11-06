import AppKit
import SwiftUI

// MARK: - Spacing & layout

enum GrokSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let sidebarInset: CGFloat = 10
    static let contentInset: CGFloat = 20
    static let notesEditorInset: CGFloat = 24
    /// The widest a column of reading text gets: notes, transcript, and answers.
    static let measure: CGFloat = 680
}

enum GrokRadius {
    static let panel: CGFloat = 12
    static let row: CGFloat = 8
    static let control: CGFloat = 6
}

// MARK: - Palette

extension NSColor {
    /// An sRGB color from `0xRRGGBB`.
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    /// Resolves per appearance at draw time. Increase Contrast picks the `high` values when given.
    static func grok(light: UInt32, dark: UInt32, lightHigh: UInt32? = nil, darkHigh: UInt32? = nil) -> NSColor {
        NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua]) {
            case .darkAqua?: return NSColor(hex: dark)
            case .accessibilityHighContrastDarkAqua?: return NSColor(hex: darkHigh ?? dark)
            case .accessibilityHighContrastAqua?: return NSColor(hex: lightHigh ?? light)
            default: return NSColor(hex: light)
            }
        }
    }
}

/// The GrokNola palette, from the app icon: a cream page, graphite ink, and an amber waveform.
/// Text tokens meet WCAG AA (4.5:1) on both `paper` and `paper2` in light and dark; `inkFaint` is for placeholders and decoration.
enum GrokNSColor {
    /// The notes canvas: warm cream, or warm graphite in dark mode.
    static let paper = NSColor.grok(light: 0xFBF8F1, dark: 0x1C1B19)
    /// Side columns, panels, and cards on the paper.
    static let paper2 = NSColor.grok(light: 0xF4EFE4, dark: 0x252320)
    /// Hover and pressed rows on `paper2`, and small tiles.
    static let paper3 = NSColor.grok(light: 0xECE5D6, dark: 0x2F2C28)
    static let ink = NSColor.grok(light: 0x1F2124, dark: 0xECE8DF, lightHigh: 0x111214, darkHigh: 0xF8F5EF)
    static let inkMuted = NSColor.grok(light: 0x655F55, dark: 0xABA497, lightHigh: 0x4F4A42, darkHigh: 0xC4BEB2)
    static let inkFaint = NSColor.grok(light: 0x8C8476, dark: 0x7F786D, lightHigh: 0x655F55, darkHigh: 0xABA497)
    static let hairline = NSColor.grok(light: 0xE4DCCB, dark: 0x38342E, lightHigh: 0xBDB29E, darkHigh: 0x5E574D)
    /// Control tint: prominent buttons, toggles, selection. White labels on it are at least 3:1.
    static let accent = NSColor.grok(light: 0xB8741A, dark: 0xC7832A, lightHigh: 0x9A5F12, darkHigh: 0xD9964A)
    /// Amber for text and links on the paper.
    static let amberText = NSColor.grok(light: 0x94590E, dark: 0xF0B867, lightHigh: 0x7A4A0B, darkHigh: 0xF6C783)
    /// The brand amber of the icon's waveform, for marks and fills rather than text.
    static let amber = NSColor.grok(light: 0xE8A33D, dark: 0xEBA94A)
    /// Amber-tinted fill for citation pills, search matches, and selected rows. Ink on it is AA.
    static let amberSoft = NSColor.grok(light: 0xF5E2BF, dark: 0x45361F, lightHigh: 0xEFD3A0, darkHigh: 0x5A4526)
    /// Warm red for recording only, kept apart from the amber.
    static let recording = NSColor.grok(light: 0xBE3F2C, dark: 0xEF6B57)
    static let success = NSColor.grok(light: 0x4C7650, dark: 0x93BF96)
    static let warning = NSColor.grok(light: 0x8F620C, dark: 0xE0B157)
    static let info = NSColor.grok(light: 0x3E6890, dark: 0x8EB2D8)
    static let error = NSColor.grok(light: 0xA63A2B, dark: 0xEC7A68)
}

/// SwiftUI views of the palette. Use these instead of `.secondary`, `.quaternary`, and system blue.
enum GrokColors {
    static let paper = Color(nsColor: GrokNSColor.paper)
    static let paper2 = Color(nsColor: GrokNSColor.paper2)
    static let paper3 = Color(nsColor: GrokNSColor.paper3)
    static let ink = Color(nsColor: GrokNSColor.ink)
    static let inkMuted = Color(nsColor: GrokNSColor.inkMuted)
    static let inkFaint = Color(nsColor: GrokNSColor.inkFaint)
    static let hairline = Color(nsColor: GrokNSColor.hairline)
    static let accent = Color(nsColor: GrokNSColor.accent)
    static let amberText = Color(nsColor: GrokNSColor.amberText)
    static let amber = Color(nsColor: GrokNSColor.amber)
    static let amberSoft = Color(nsColor: GrokNSColor.amberSoft)
    static let recording = Color(nsColor: GrokNSColor.recording)
    static let recordingSoft = Color(nsColor: GrokNSColor.recording).opacity(0.12)
    static let success = Color(nsColor: GrokNSColor.success)
    static let warning = Color(nsColor: GrokNSColor.warning)
    static let info = Color(nsColor: GrokNSColor.info)
    static let error = Color(nsColor: GrokNSColor.error)

    static var notesSurface: Color { paper }
    static var liveText: Color { inkMuted }
    static var timestamp: Color { inkMuted }
    /// Track behind progress and talk-time bars.
    static var track: Color { hairline }
    /// Hover on rows over the paper.
    static var hover: Color { ink.opacity(0.05) }
}

// MARK: - Typography

/// One scale for the app. Grok's writing (notes, answers) and titles use the system serif, New York;
/// controls and chrome stay SF Pro; times and counts use monospaced digits.
enum GrokTypography {
    /// Home's greeting.
    static let display: Font = .system(size: 30, weight: .semibold, design: .serif)
    /// Meeting titles and empty-state titles.
    static let title: Font = .system(size: 22, weight: .semibold, design: .serif)
    /// Headings inside the reading column, such as transcript chapters.
    static let readingHeading: Font = .system(size: 15, weight: .semibold, design: .serif)
    /// Section titles in panels and side columns.
    static let heading: Font = .headline
    static let body: Font = .body
    static let secondary: Font = .callout
    static let meta: Font = .caption
    /// Small uppercase labels above groups in side columns.
    static let eyebrow: Font = .caption.weight(.semibold)
    static let wordmark: Font = .system(size: 16, weight: .semibold, design: .serif)
    /// Large numbers in stat tiles.
    static let figure: Font = .system(size: 26, weight: .semibold).monospacedDigit()

    static func meetingTitle() -> Font { .system(size: 17, weight: .semibold, design: .serif) }
    static func sectionTitle() -> Font { heading }
    static func captionMuted() -> Font { meta }
    static func transcriptSpeaker() -> Font { .subheadline.weight(.semibold) }
    static func transcriptBody() -> Font { .system(size: 14) }
    static func liveLine() -> Font { .body.italic() }
    static func placeholder() -> Font { .title3.weight(.regular) }
    static func emptyStateTitle() -> Font { title }
    static func emptyStateBody() -> Font { body }
    /// One step above caption on macOS, where caption and footnote are both 10 points.
    static func citation() -> Font { .subheadline.monospacedDigit().weight(.medium) }

    // MARK: Reading text (AppKit)

    /// New York at a reading size: 15 points for body notes, a step above the style otherwise.
    static func readingFont(_ style: NSFont.TextStyle, weight: NSFont.Weight = .regular) -> NSFont {
        let size: CGFloat = style == .body ? 15 : NSFont.preferredFont(forTextStyle: style).pointSize + 1
        return serif(size: size, weight: weight)
    }

    static func serif(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let system = NSFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = system.fontDescriptor.withDesign(.serif) else { return system }
        return NSFont(descriptor: descriptor, size: size) ?? system
    }

    /// Line spacing that gives reading text about 1.45 line height.
    static func readingLineSpacing(_ font: NSFont) -> CGFloat { (font.pointSize * 0.33).rounded() }
}

enum GrokOpacity {
    /// Hover-revealed controls when the pointer is elsewhere: visible enough to find, quiet enough to read past.
    static let idleControl: Double = 0.35
}

// MARK: - Recording pulse

/// Fixed-size recording indicator. The ring is driven by a clock rather than
/// `withAnimation(.repeatForever)`, which would also loop any layout change in
/// the same transaction and make the dot slide around inside rows and toolbars.
struct RecordingPulse: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let period: Double = 1.2
    private static let dotSize: CGFloat = 8
    private static let containerSize: CGFloat = 16

    var body: some View {
        ZStack {
            if !reduceMotion {
                TimelineView(.animation) { context in
                    let progress = Self.progress(at: context.date)
                    Circle()
                        .stroke(GrokColors.recording.opacity(0.45), lineWidth: 2)
                        .frame(width: Self.dotSize, height: Self.dotSize)
                        .scaleEffect(1 + 0.8 * progress)
                        .opacity(0.9 * (1 - progress))
                }
            }
            Circle()
                .fill(GrokColors.recording)
                .frame(width: Self.dotSize, height: Self.dotSize)
        }
        .frame(width: Self.containerSize, height: Self.containerSize)
        .transaction { $0.animation = nil }
        .accessibilityElement()
        .accessibilityLabel("Recording")
    }

    /// Ease-out progress through the current pulse cycle, in 0...1.
    private static func progress(at date: Date) -> Double {
        let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
        return 1 - (1 - t) * (1 - t)
    }
}

// MARK: - Relative dates

enum GrokFormat {
    static func relativeDay(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    static func meetingSubtitle(date: Date, appName: String?) -> String {
        let day = relativeDay(date)
        if let appName, !appName.isEmpty { return "\(day) · \(appName)" }
        return day
    }
}

// MARK: - App icon helper

enum MeetingAppIcon {
    static func symbol(for appName: String?) -> String {
        guard let name = appName?.lowercased() else { return "video.fill" }
        if name.contains("zoom") { return "video.fill" }
        if name.contains("teams") { return "person.3.fill" }
        if name.contains("slack") { return "number" }
        if name.contains("meet") { return "video.badge.checkmark" }
        if name.contains("webex") { return "phone.fill" }
        return "video.fill"
    }
}
