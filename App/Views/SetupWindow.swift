import SwiftUI
import ConsaiCore
import ConsaiKit

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
    @State private var appeared = false
    @State private var pollTask: Task<Void, Never>?

    private let checker = SetupChecker()

    private var allRequired: Bool { containerInstalled && serviceRunning }
    private var requiredCount: Int { (containerInstalled ? 1 : 0) + (serviceRunning ? 1 : 0) }

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
        .task {
            await runChecks()
            withAnimation(.spring(duration: 0.45, bounce: 0.15)) { appeared = true }
            startPollingIfNeeded()
        }
        .onDisappear {
            pollTask?.cancel()
            pollTask = nil
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(RadialGradient(
                        colors: allRequired
                            ? [Theme.jade, Theme.jadeDeep]
                            : [Theme.jadeLite, Theme.jadeDeep],
                        center: .init(x: 0.35, y: 0.3),
                        startRadius: 1, endRadius: 34))
                    .frame(width: 44, height: 44)
                    .animation(.easeInOut(duration: 0.4), value: allRequired)
                Text("心")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color(hex: 0x0E2A1D))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Welcome to Consai")
                    .font(Theme.wordmark(20))
                    .foregroundStyle(Theme.text)
                Text(allRequired
                     ? "You're all set — let's go."
                     : "Let's make sure everything is in order.")
                    .font(Theme.ui(12))
                    .foregroundStyle(allRequired ? Theme.jade : Theme.dim)
                    .animation(.easeInOut(duration: 0.3), value: allRequired)
            }

            Spacer(minLength: 0)

            if checking {
                ProgressView().controlSize(.small).tint(Theme.dim)
            }
        }
        .padding(.horizontal, 28).padding(.top, 28).padding(.bottom, 22)
    }

    // MARK: - Checklist

    private var checklist: some View {
        VStack(spacing: 0) {
            setupRow(index: 0,
                symbol: containerInstalled ? "checkmark.circle.fill" : "circle",
                symbolColor: containerInstalled ? Theme.jade : (checking ? Theme.dim2 : Theme.danger),
                title: "Apple Container CLI",
                badge: nil,
                status: statusLabel(installed: containerInstalled, version: containerVersion,
                                    missingText: "Required to manage containers")
            ) {
                if !containerInstalled {
                    installHint(text: "Download from Apple's GitHub releases:",
                                action: "Get container →",
                                url: "https://github.com/apple/container/releases")
                }
            }

            Rectangle().fill(Theme.hairline).frame(height: 0.5).padding(.horizontal, 28)

            setupRow(index: 1,
                symbol: serviceRunning ? "checkmark.circle.fill" : (containerInstalled ? "circle" : "minus.circle"),
                symbolColor: serviceRunning ? Theme.jade : (containerInstalled ? (checking ? Theme.dim2 : Theme.amber) : Theme.dim2),
                title: "Container Service",
                badge: nil,
                status: serviceRunning ? "running" : (containerInstalled ? "not running" : "requires container CLI")
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
                                startPollingIfNeeded()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                if startingService { ProgressView().controlSize(.mini) }
                                Text(startingService ? "Starting…" : "Start now")
                                    .font(Theme.ui(11, .medium))
                            }
                        }
                        .buttonStyle(.plain).foregroundStyle(Theme.jade).disabled(startingService)
                    }
                }
            }

            Rectangle().fill(Theme.hairline).frame(height: 0.5).padding(.horizontal, 28)

            setupRow(index: 2,
                symbol: composeInstalled ? "checkmark.circle.fill" : "circle.dotted",
                symbolColor: composeInstalled ? Theme.jade : (checking ? Theme.dim2 : Theme.dim),
                title: "container-compose",
                badge: "optional",
                status: statusLabel(installed: composeInstalled, version: composeVersion,
                                    missingText: "Stack support via compose files")
            ) {
                if !composeInstalled {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Install via Homebrew:").font(Theme.ui(11)).foregroundStyle(Theme.dim)
                        CopyableCommand("brew install container-compose")
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(alignment: .center) {
            if !checking {
                Text("\(requiredCount) of 2 required")
                    .font(Theme.ui(11))
                    .foregroundStyle(allRequired ? Theme.jade : Theme.dim2)
                    .animation(.easeInOut(duration: 0.3), value: requiredCount)
                    .transition(.opacity)
            }

            Spacer()

            Button {
                setupCompleted = true
            } label: {
                HStack(spacing: 7) {
                    Text(containerInstalled ? "Start using Consai" : "Skip for now")
                        .font(Theme.ui(13, .semibold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(allRequired ? Color(hex: 0x0E2A1D) : Theme.dim)
                .padding(.horizontal, 18).padding(.vertical, 9)
                .background(
                    allRequired ? Theme.jade : Theme.hairline,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .animation(.spring(duration: 0.35, bounce: 0.2), value: allRequired)
        }
        .padding(.horizontal, 28).padding(.vertical, 20)
    }

    // MARK: - Row builder

    @ViewBuilder
    private func setupRow<Expansion: View>(
        index: Int,
        symbol: String,
        symbolColor: Color,
        title: String,
        badge: String?,
        status: String,
        @ViewBuilder expansion: () -> Expansion
    ) -> some View {
        SetupRow(symbol: symbol, symbolColor: symbolColor,
                 title: title, badge: badge, status: status,
                 expansion: expansion)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 10)
        .animation(.spring(duration: 0.45, bounce: 0.12).delay(Double(index) * 0.07), value: appeared)
    }

    // MARK: - Helpers

    private func runChecks() async {
        checking = true
        async let c = checker.checkContainer()
        async let s = checker.checkService()
        async let q = checker.checkCompose()
        let (ci, si, qi) = await (c, s, q)
        withAnimation(.easeInOut(duration: 0.3)) {
            containerInstalled = ci.installed
            containerVersion = ci.version
            serviceRunning = si
            composeInstalled = qi.installed
            composeVersion = qi.version
            checking = false
        }
    }

    private func startPollingIfNeeded() {
        guard !allRequired else { return }
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled && !allRequired {
                try? await Task.sleep(for: .seconds(2.5))
                if Task.isCancelled { break }
                await runChecks()
            }
        }
    }

    private func statusLabel(installed: Bool, version: String?, missingText: String) -> String {
        if checking { return "checking…" }
        if installed { return version.map { "version \($0)" } ?? "installed" }
        return missingText
    }

    @ViewBuilder
    private func installHint(text: String, action: String, url: String) -> some View {
        HStack(spacing: 4) {
            Text(text).font(Theme.ui(11)).foregroundStyle(Theme.dim)
            if let u = URL(string: url) {
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
    @ViewBuilder let expansion: Expansion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(symbolColor)
                    .frame(width: 22)
                    .contentTransition(.symbolEffect(.replace))
                    .animation(.spring(duration: 0.4, bounce: 0.25), value: symbol)

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
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                        .animation(.easeInOut(duration: 0.25), value: status)
                }
            }

            expansion
                .padding(.leading, 34)
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
        .padding(.horizontal, 28).padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

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
                withAnimation(.spring(duration: 0.25)) { copied = true }
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    withAnimation(.easeOut(duration: 0.2)) { copied = false }
                }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10))
                    .foregroundStyle(copied ? Theme.jade : Theme.dim)
                    .contentTransition(.symbolEffect(.replace))
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
