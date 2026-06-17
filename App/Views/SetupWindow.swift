import SwiftUI
import ConsaiCore
import ConsaiKit

/// First-run onboarding window. Checks whether `container`, the container service,
/// and `container-compose` are present and operational, and guides the user through
/// getting everything in order before they start using Consai.
struct SetupWindow: View {
    @Environment(AppState.self) private var appState
    @AppStorage("setupCompleted") private var setupCompleted = false
    @Environment(\.openURL) private var openURL

    @State private var containerInstalled = false
    @State private var containerVersion: String? = nil
    @State private var serviceRunning = false
    @State private var composeInstalled = false
    @State private var composeVersion: String? = nil
    @State private var checking = true
    @State private var startingService = false

    private let checker = SetupChecker()

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.hairline).frame(height: 0.5)
            checklist
            Rectangle().fill(Theme.hairline).frame(height: 0.5)
            footer
        }
        .frame(width: 480)
        .consaiSurface()
        .preferredColorScheme(.dark)
        .tint(Theme.jade)
        .task { await runChecks() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(RadialGradient(colors: [Theme.jadeLite, Theme.jadeDeep],
                                        center: .init(x: 0.35, y: 0.3),
                                        startRadius: 1, endRadius: 34))
                    .frame(width: 44, height: 44)
                    .overlay(Text("心").font(.system(size: 22, weight: .bold)).foregroundStyle(Color(hex: 0x0E2A1D)))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome to Consai")
                        .font(Theme.wordmark(20))
                        .foregroundStyle(Theme.text)
                    Text("Let's make sure everything is in order.")
                        .font(Theme.ui(12))
                        .foregroundStyle(Theme.dim)
                }

                Spacer(minLength: 0)

                if checking {
                    ProgressView().controlSize(.small).tint(Theme.dim)
                } else {
                    Button {
                        Task { await runChecks() }
                    } label: {
                        Image(systemName: "arrow.clockwise").font(.system(size: 13))
                    }
                    .buttonStyle(.plain).foregroundStyle(Theme.dim).help("Check again")
                }
            }
        }
        .padding(.horizontal, 28).padding(.top, 28).padding(.bottom, 22)
    }

    // MARK: - Checklist

    private var checklist: some View {
        VStack(spacing: 0) {
            SetupRow(
                symbol: containerInstalled ? "checkmark.circle.fill" : "circle",
                symbolColor: containerInstalled ? Theme.jade : (checking ? Theme.dim2 : Theme.danger),
                title: "Apple Container CLI",
                badge: nil,
                status: statusLabel(installed: containerInstalled, version: containerVersion,
                                    missingText: "Required to manage containers"),
                required: true
            ) {
                if !containerInstalled {
                    installHint(
                        text: "Download the installer from Apple's GitHub releases:",
                        action: "Get container →",
                        url: "https://github.com/apple/container/releases"
                    )
                }
            }

            Rectangle().fill(Theme.hairline).frame(height: 0.5).padding(.horizontal, 28)

            SetupRow(
                symbol: serviceRunning ? "checkmark.circle.fill" : (containerInstalled ? "circle" : "minus.circle"),
                symbolColor: serviceRunning ? Theme.jade : (containerInstalled ? (checking ? Theme.dim2 : Theme.amber) : Theme.dim2),
                title: "Container Service",
                badge: nil,
                status: serviceRunning ? "running" : (containerInstalled ? "not running" : "requires container CLI"),
                required: true
            ) {
                if !serviceRunning && containerInstalled {
                    VStack(alignment: .leading, spacing: 8) {
                        CopyableCommand("container system start")
                        Button {
                            startingService = true
                            Task {
                                await appState.startService()
                                await runChecks()
                                startingService = false
                            }
                        } label: {
                            if startingService {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.mini)
                                    Text("Starting…").font(Theme.ui(11, .medium))
                                }
                            } else {
                                Text("Start now").font(Theme.ui(11, .medium))
                            }
                        }
                        .buttonStyle(.plain).foregroundStyle(Theme.jade).disabled(startingService)
                    }
                }
            }

            Rectangle().fill(Theme.hairline).frame(height: 0.5).padding(.horizontal, 28)

            SetupRow(
                symbol: composeInstalled ? "checkmark.circle.fill" : "circle.dotted",
                symbolColor: composeInstalled ? Theme.jade : (checking ? Theme.dim2 : Theme.dim),
                title: "container-compose",
                badge: "optional",
                status: statusLabel(installed: composeInstalled, version: composeVersion,
                                    missingText: "Stack support via compose files"),
                required: false
            ) {
                if !composeInstalled {
                    installHint(
                        text: "Install via Homebrew:",
                        action: nil,
                        url: nil
                    )
                    CopyableCommand("brew install container-compose")
                }
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Spacer()
            Button {
                setupCompleted = true
            } label: {
                HStack(spacing: 7) {
                    Text(containerInstalled ? "Start using Consai" : "Skip for now")
                        .font(Theme.ui(13, .semibold))
                    Image(systemName: "arrow.right").font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(containerInstalled ? Color(hex: 0x0E2A1D) : Theme.dim)
                .padding(.horizontal, 18).padding(.vertical, 9)
                .background(containerInstalled ? Theme.jade : Theme.hairline,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .animation(.easeInOut(duration: 0.2), value: containerInstalled)
        }
        .padding(.horizontal, 28).padding(.vertical, 20)
    }

    // MARK: - Helpers

    private func runChecks() async {
        checking = true
        async let c = checker.checkContainer()
        async let s = checker.checkService()
        async let q = checker.checkCompose()
        let (ci, si, qi) = await (c, s, q)
        containerInstalled = ci.installed
        containerVersion = ci.version
        serviceRunning = si
        composeInstalled = qi.installed
        composeVersion = qi.version
        checking = false
    }

    private func statusLabel(installed: Bool, version: String?, missingText: String) -> String {
        if checking { return "checking…" }
        if installed { return version.map { "version \($0)" } ?? "installed" }
        return missingText
    }

    @ViewBuilder
    private func installHint(text: String, action: String?, url: String?) -> some View {
        HStack(spacing: 4) {
            Text(text).font(Theme.ui(11)).foregroundStyle(Theme.dim)
            if let action, let urlStr = url, let u = URL(string: urlStr) {
                Button(action) { openURL(u) }
                    .buttonStyle(.plain).font(Theme.ui(11, .medium)).foregroundStyle(Theme.jade)
            }
        }
    }
}

// MARK: - Sub-views

private struct SetupRow<Expansion: View>: View {
    let symbol: String
    let symbolColor: Color
    let title: String
    let badge: String?
    let status: String
    let required: Bool
    @ViewBuilder let expansion: Expansion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(symbolColor)
                    .frame(width: 22)
                    .animation(.easeInOut(duration: 0.3), value: symbol)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(Theme.ui(14, .semibold))
                            .foregroundStyle(Theme.text)
                        if let badge {
                            Text(badge)
                                .font(Theme.ui(9, .medium))
                                .foregroundStyle(Theme.dim2)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Theme.hairline, in: Capsule())
                        }
                    }
                    Text(status)
                        .font(Theme.ui(11))
                        .foregroundStyle(Theme.dim)
                        .animation(.easeInOut, value: status)
                }
            }

            expansion
                .padding(.leading, 34)
        }
        .padding(.horizontal, 28).padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A read-only code block with a clipboard copy button.
private struct CopyableCommand: View {
    let command: String
    @State private var copied = false

    init(_ command: String) { self.command = command }

    var body: some View {
        HStack(spacing: 8) {
            Text(command)
                .font(Theme.mono(11))
                .foregroundStyle(Theme.jade.opacity(0.9))
                .lineLimit(1)

            Spacer(minLength: 4)

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    copied = false
                }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10))
                    .foregroundStyle(copied ? Theme.jade : Theme.dim)
            }
            .buttonStyle(.plain)
            .help("Copy to clipboard")
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Theme.bg, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Theme.hairline, lineWidth: 0.5)
        )
    }
}
