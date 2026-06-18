import SwiftUI
import AppKit

/// The README hero banner — the 心 mark, wordmark, and tagline on the organic dark palette.
/// Rendered to a 1600×800 PNG (2:1, retina-crisp at GitHub's typical display sizes) via
/// `--render-hero <path>`; `swift run hero` writes it to docs/hero.png. Pure `ImageRenderer`
/// (like `IconRenderer`) so it needs no daemon and no Screen Recording permission.
struct HeroView: View {
    var body: some View {
        ZStack {
            // Depth gradient — same bgTop→bg the app windows use, but deeper for a banner.
            LinearGradient(colors: [Theme.bgTop, Theme.bg], startPoint: .topLeading, endPoint: .bottomTrailing)

            // Soft jade glow behind the mark, top-left, echoing the icon's radial light.
            RadialGradient(colors: [Theme.jadeDeep.opacity(0.28), .clear],
                           center: .init(x: 0.26, y: 0.34), startRadius: 12, endRadius: 480)

            // Faint container-mark watermark field, low-contrast, bottom-right.
            watermark
                .opacity(0.05)
                .frame(width: 600, height: 400)
                .offset(x: 380, y: 160)

            HStack(spacing: 48) {
                mark
                VStack(alignment: .leading, spacing: 12) {
                    Text("Consai")
                        .font(.system(size: 88, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.text)
                    Text("Your containers, grouped into stacks — right from the menu bar.")
                        .font(.system(size: 26, weight: .regular, design: .rounded))
                        .foregroundStyle(Theme.dim)
                        .frame(maxWidth: 660, alignment: .leading)
                    HStack(spacing: 10) {
                        pill("macOS 26")
                        pill("SwiftUI")
                        pill("Apple container")
                    }
                    .padding(.top, 6)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 96)
        }
        .frame(width: 1600, height: 800)
    }

    /// The jade squircle + 心 mark, matching the app icon at banner scale.
    private var mark: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 88, style: .continuous)
                .fill(RadialGradient(colors: [Theme.jadeLite, Theme.jadeDeep],
                                     center: .init(x: 0.34, y: 0.28), startRadius: 16, endRadius: 440))
            RoundedRectangle(cornerRadius: 88, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 3)
            Text("心")
                .font(.system(size: 220, weight: .bold, design: .rounded))
                .foregroundStyle(Color(hex: 0x0E2A1D))
                .shadow(color: .black.opacity(0.12), radius: 4, y: 3)
        }
        .frame(width: 400, height: 400)
        .shadow(color: .black.opacity(0.35), radius: 28, y: 16)
    }

    private func pill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 20, weight: .medium, design: .monospaced))
            .foregroundStyle(Theme.jade)
            .padding(.horizontal, 18).padding(.vertical, 8)
            .background(Capsule().fill(Theme.jade.opacity(0.12)))
            .overlay(Capsule().stroke(Theme.jade.opacity(0.25), lineWidth: 1))
    }

    /// A tiled grid of leaf marks as a subtle background texture.
    private var watermark: some View {
        VStack(spacing: 36) {
            ForEach(0..<5, id: \.self) { _ in
                HStack(spacing: 36) {
                    ForEach(0..<6, id: \.self) { _ in
                        LeafShape(size: 40, color: Theme.jade)
                    }
                }
            }
        }
    }
}

@MainActor
enum HeroRenderer {
    static func render(to url: URL) {
        let renderer = ImageRenderer(content: HeroView())
        renderer.scale = 1
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
        FileHandle.standardError.write(Data("rendered hero to \(url.path)\n".utf8))
    }
}
