import SwiftUI
import AppKit

/// The Consai app icon — the 心 bonsai mark on a jade squircle. Rendered to a 1024px PNG via
/// `--render-icon <path>`; scripts/make-icon.sh turns it into AppIcon.icns.
struct IconView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 224, style: .continuous)
                .fill(RadialGradient(colors: [Theme.jadeLite, Theme.jadeDeep],
                                     center: .init(x: 0.34, y: 0.28), startRadius: 40, endRadius: 1120))
            RoundedRectangle(cornerRadius: 224, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 6)
            Text("心")
                .font(.system(size: 560, weight: .bold, design: .rounded))
                .foregroundStyle(Color(hex: 0x0E2A1D))
                .shadow(color: .black.opacity(0.12), radius: 8, y: 6)
        }
        .frame(width: 1024, height: 1024)
    }
}

@MainActor
enum IconRenderer {
    static func render(to url: URL) {
        let renderer = ImageRenderer(content: IconView())
        renderer.scale = 1
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
        FileHandle.standardError.write(Data("rendered icon to \(url.path)\n".utf8))
    }
}
