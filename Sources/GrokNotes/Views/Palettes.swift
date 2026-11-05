import SwiftUI

/// Speaker colors. You are always green. Remote speakers take palette colors in the order they first
/// speak in a meeting, so two speakers in one meeting share a color only past the palette's length.
/// Red is left out because it reads as recording or an error.
enum SpeakerColor {
    static let me: Color = .green
    static let palette: [Color] = [.blue, .orange, .purple, .pink, .teal, .indigo, .brown, .mint, .cyan, .yellow]

    /// The palette slot of a remote speaker among a meeting's speaker keys in first-spoken order.
    static func index(for key: String, among keys: [String]) -> Int? {
        guard key != Meeting.meKey else { return nil }
        let remote = keys.filter { $0 != Meeting.meKey }
        return remote.firstIndex(of: key).map { $0 % palette.count }
    }

    static func color(for key: String, among keys: [String]) -> Color {
        if key == Meeting.meKey { return me }
        return index(for: key, among: keys).map { palette[$0] } ?? color(for: key)
    }

    /// A stable color from the key alone, for places without the meeting's speaker order.
    static func color(for key: String) -> Color {
        if key == Meeting.meKey { return me }
        let hash = key.utf8.reduce(5381) { ($0 &* 33) &+ Int($1) }
        return palette[abs(hash) % palette.count]
    }
}

/// Chapter colors: muted tones that stay apart from the speaker colors.
enum ChapterColor {
    private static let palette: [Color] = [
        Color(red: 0.42, green: 0.53, blue: 0.66),
        Color(red: 0.62, green: 0.55, blue: 0.40),
        Color(red: 0.45, green: 0.60, blue: 0.52),
        Color(red: 0.60, green: 0.47, blue: 0.58),
        Color(red: 0.52, green: 0.52, blue: 0.62),
        Color(red: 0.64, green: 0.50, blue: 0.44),
        Color(red: 0.47, green: 0.58, blue: 0.62),
        Color(red: 0.57, green: 0.57, blue: 0.47),
    ]

    static func color(_ index: Int) -> Color { palette[index % palette.count] }
}
