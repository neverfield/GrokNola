import AppKit
import SwiftUI

/// Speaker colors: earthy, muted tones that sit on the paper. Each is dark enough for a speaker's name in light
/// mode and light enough in dark mode (at least 4.5:1 on `paper` and `paper2`). You are always sage.
/// Remote speakers take palette colors in the order they first speak in a meeting, so two speakers in one
/// meeting share a color only past the palette's length. Red is left out because it reads as recording.
enum SpeakerColor {
    static let me = Color(nsColor: .grok(light: 0x4C7650, dark: 0x93BF96))
    static let palette: [Color] = [
        Color(nsColor: .grok(light: 0x3E6890, dark: 0x8EB2D8)), // slate blue
        Color(nsColor: .grok(light: 0xA4503A, dark: 0xE29A80)), // terracotta
        Color(nsColor: .grok(light: 0x7A4D78, dark: 0xC99CC6)), // plum
        Color(nsColor: .grok(light: 0x2D726E, dark: 0x7EC3BC)), // teal
        Color(nsColor: .grok(light: 0x86630F, dark: 0xD8B35C)), // ochre
        Color(nsColor: .grok(light: 0x575C9C, dark: 0xA5A8E2)), // indigo
        Color(nsColor: .grok(light: 0x8A5B3D, dark: 0xD4A27F)), // clay
    ]

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

/// Chapter colors: a quieter ramp of the speaker family, for timeline segments, bars, and marks.
enum ChapterColor {
    private static let palette: [Color] = [
        Color(nsColor: .grok(light: 0x7C97B2, dark: 0x7E98B3)), // slate
        Color(nsColor: .grok(light: 0xC8A65A, dark: 0xC4A45C)), // ochre
        Color(nsColor: .grok(light: 0x8FAA88, dark: 0x8DA987)), // sage
        Color(nsColor: .grok(light: 0xC99075, dark: 0xC48F76)), // terracotta
        Color(nsColor: .grok(light: 0x6FA6A1, dark: 0x6EA49F)), // teal
        Color(nsColor: .grok(light: 0xA889A6, dark: 0xA68AA4)), // plum
        Color(nsColor: .grok(light: 0x8E91BF, dark: 0x8C90BC)), // indigo
        Color(nsColor: .grok(light: 0xB39176, dark: 0xB09078)), // clay
    ]

    static func color(_ index: Int) -> Color { palette[index % palette.count] }
}
