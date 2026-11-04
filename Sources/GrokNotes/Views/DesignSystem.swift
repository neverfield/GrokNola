import SwiftUI

// MARK: - Spacing & layout

enum GrokSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let sidebarInset: CGFloat = 10
    static let contentInset: CGFloat = 20
    static let notesEditorInset: CGFloat = 24
}

// MARK: - Typography

enum GrokTypography {
    static func meetingTitle() -> Font { .title2.weight(.semibold) }
    static func sectionTitle() -> Font { .headline }
    static func captionMuted() -> Font { .caption }
    static func transcriptSpeaker() -> Font { .subheadline.weight(.semibold) }
    static func transcriptBody() -> Font { .body }
    static func liveLine() -> Font { .body.italic() }
    static func placeholder() -> Font { .title3.weight(.regular) }
    static func emptyStateTitle() -> Font { .largeTitle.weight(.semibold) }
    static func emptyStateBody() -> Font { .body }
}

// MARK: - Semantic colors (system)

enum GrokColors {
    static var recording: Color { .red }
    static var recordingSoft: Color { .red.opacity(0.12) }
    static var notesSurface: Color { Color(nsColor: .textBackgroundColor) }
    static var liveText: Color { .secondary }
    static var timestamp: Color { Color(nsColor: .tertiaryLabelColor) }
}

// MARK: - Recording pulse

struct RecordingPulse: View {
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(GrokColors.recording)
            .frame(width: 8, height: 8)
            .overlay {
                Circle()
                    .stroke(GrokColors.recording.opacity(0.45), lineWidth: 2)
                    .scaleEffect(pulse ? 1.8 : 1)
                    .opacity(pulse ? 0 : 0.9)
            }
            .onAppear {
                withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) {
                    pulse = true
                }
            }
            .accessibilityLabel("Recording")
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
