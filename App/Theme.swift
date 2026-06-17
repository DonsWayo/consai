import SwiftUI

/// Bonsai design tokens — the single source of truth for the redesign so every view stays
/// pixel-consistent. Organic dark palette, jade = alive, soft-blue = network/IP.
enum Theme {
    static let bg        = Color(hex: 0x15181A)   // panel background
    static let bgTop     = Color(hex: 0x1C2124)   // subtle elevated top (panel depth gradient)
    static let surface   = Color(hex: 0x1A1E1B)   // stack card
    static let hover     = Color(hex: 0x222826)   // row hover wash
    static let hairline  = Color(hex: 0x2B302C)   // separators, branch
    static let jade      = Color(hex: 0x7CC99A)   // alive / brand
    static let jadeDeep  = Color(hex: 0x3C7D55)   // mark gradient end
    static let jadeLite  = Color(hex: 0x8FD6A8)   // mark gradient start
    static let ip        = Color(hex: 0x9DB8D6)   // IP / network data
    static let text      = Color(hex: 0xE6ECE7)   // primary
    static let dim       = Color(hex: 0x7E8A80)   // secondary
    static let dim2      = Color(hex: 0x5A655C)   // tertiary / labels
    static let stopDot   = Color(hex: 0x4A514B)   // idle marker
    static let amber     = Color(hex: 0xF2B544)   // transitioning
    static let danger    = Color(hex: 0xE08585)   // error
    /// Palette for multi-log panes: one distinct accent per container stream.
    static let logPalette: [Color] = [
        Color(hex: 0x7CC99A),   // jade
        Color(hex: 0xF2B544),   // amber
        Color(hex: 0x9DB8D6),   // sky-blue
        Color(hex: 0xE08585),   // rose
        Color(hex: 0xA89BD4),   // lavender
    ]

    static func wordmark(_ size: CGFloat = 17) -> Font { .system(size: size, weight: .bold, design: .rounded) }
    static func mono(_ size: CGFloat = 10.5) -> Font { .system(size: size, design: .monospaced) }
    static func ui(_ size: CGFloat = 13, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight) }
    static let sectionLabel = Font.system(size: 10, weight: .semibold)

    static let panelWidth: CGFloat = 360
}

extension View {
    /// The shared Consai surface: a soft top-lit depth gradient (replaces flat `Theme.bg`) so
    /// every window — panel and secondary — reads as one app. One source of truth.
    func consaiSurface() -> some View {
        background(LinearGradient(colors: [Theme.bgTop, Theme.bg], startPoint: .top, endPoint: .bottom))
    }
}

extension Color {
    init(hex: UInt) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

/// The leaf/petal mark shape — one square corner, three rounded (matches the mockup leaf).
struct LeafShape: View {
    var size: CGFloat = 9
    var color: Color = Theme.jade
    var body: some View {
        UnevenRoundedRectangle(cornerRadii: .init(
            topLeading: 0, bottomLeading: size, bottomTrailing: size, topTrailing: size))
            .fill(color)
            .frame(width: size, height: size)
    }
}
