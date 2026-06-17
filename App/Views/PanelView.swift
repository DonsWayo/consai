import SwiftUI
import ConsaiCore
import ConsaiKit
import AppKit

/// Carries the scrollable list's natural height up so the panel can size to it.
private struct ListHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// The menu bar panel — Bonsai look: mark + wordmark, leaf-marked stacks on branches,
/// standalone containers, a tend-the-garden footer.
struct PanelView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    @AppStorage("setupCompleted") private var setupCompleted = false

    /// Natural height of the scrollable list, measured so the menu-bar window can size to its
    /// content instead of collapsing the ScrollView to ~0pt (MenuBarExtra sizes to ideal size).
    @State private var listHeight: CGFloat = 220
    private let listCap: CGFloat = 460     // scroll past this; never grow taller
    private let listFloor: CGFloat = 80    // a single row shouldn't look cramped

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.hairline).frame(height: 0.5)

            if !appState.isServiceRunning {
                ServiceBanner()
            }
            if let error = appState.lastError {
                ErrorBanner(message: error) { appState.clearError() }
            }
            if let u = appState.containerUpdate {
                UpdateBanner(update: u)
            }
            if let u = appState.composeUpdate {
                UpdateBanner(update: u)
            }

            content

            Rectangle().fill(Theme.hairline).frame(height: 0.5)
            footer
        }
        .frame(width: Theme.panelWidth)
        .consaiSurface()
        .preferredColorScheme(.dark)
        .tint(Theme.jade)
        .onAppear {
            appState.setPanelVisible(true)
            if !setupCompleted { openWindow(id: "setup") }
        }
        .onDisappear { appState.setPanelVisible(false) }
    }

    private var header: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(RadialGradient(colors: [Theme.jadeLite, Theme.jadeDeep],
                                     center: .init(x: 0.35, y: 0.3), startRadius: 1, endRadius: 26))
                .frame(width: 26, height: 26)
                .overlay(Text("心").font(.system(size: 13, weight: .bold)).foregroundStyle(Color(hex: 0x0E2A1D)))

            Text("Consai").font(Theme.wordmark(17)).foregroundStyle(Theme.text)

            Spacer(minLength: 8)

            if appState.isServiceRunning {
                HStack(spacing: 5) {
                    Text("\(appState.runningCount) alive").font(Theme.mono(11)).foregroundStyle(Theme.jade)
                    Text("· \(appState.containers.count) total").font(Theme.mono(11)).foregroundStyle(Theme.dim)
                }
            }
        }
        .padding(.horizontal, 16).padding(.top, 15).padding(.bottom, 12)
    }

    @ViewBuilder
    private var content: some View {
        if !appState.isServiceRunning {
            EmptyState(symbol: "leaf", title: "Garden's asleep",
                       subtitle: "Start the container service to tend your containers.")
        } else if appState.stacks.isEmpty && appState.standalone.isEmpty {
            EmptyState(symbol: "leaf", title: "Nothing growing yet",
                       subtitle: appState.composeAvailable
                        ? "Grow a container, or raise a stack from the footer."
                        : "Containers you run will appear here.")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !appState.stacks.isEmpty {
                        sectionLabel("STACKS")
                        ForEach(appState.stacks) { StackSection(stack: $0) }
                    }
                    if !appState.standalone.isEmpty {
                        sectionLabel("CONTAINERS")
                        ForEach(appState.standalone) { container in
                            ContainerRow(container: container)
                                .padding(.horizontal, 12)
                        }
                    }
                    if !appState.composeAvailable { composeHint }
                }
                .padding(.bottom, 6)
                .background(GeometryReader { g in
                    Color.clear.preference(key: ListHeightKey.self, value: g.size.height)
                })
            }
            // Size the panel to the list's natural height (floored so one row isn't cramped,
            // capped so long lists scroll) — without this the ScrollView collapses to ~0pt in
            // the self-sizing MenuBarExtra window and the rows become invisible.
            .frame(height: min(max(listHeight, listFloor), listCap))
            .onPreferenceChange(ListHeightKey.self) { listHeight = $0 }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(Theme.sectionLabel).tracking(2).foregroundStyle(Theme.dim2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 4)
    }

    private var composeHint: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
            Text("Install container-compose for stacks").font(Theme.mono(10))
        }
        .foregroundStyle(Theme.dim2)
        .padding(.horizontal, 18).padding(.vertical, 8)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            // Create
            footerButton("plus", "Grow", help: "New container") { openWindow(id: "create") }
            if appState.composeAvailable {
                footerButton("square.stack.3d.up", "Stack", help: "Start a compose stack") {
                    if let file = ComposeFilePicker.pick() { Task { await appState.composeUp(file: file) } }
                }
            }
            footerSep
            // Browse
            footerButton("photo.stack", nil, help: "Images") { openWindow(id: "images") }
            footerButton("network", nil, help: "Networks & volumes") { openWindow(id: "infra") }
            footerButton("doc.text.below.ecg", nil, help: "Multi-log viewer") { openWindow(id: "multi-logs") }
            Spacer(minLength: 8)
            // Utility
            footerButton("arrow.clockwise", nil, help: "Refresh") { Task { await appState.refresh() } }
            footerButton("gearshape", nil, help: "Settings") { openWindow(id: "settings") }
            Button { NSApplication.shared.terminate(nil) } label: {
                Image(systemName: "power").font(.system(size: 12))
            }
            .buttonStyle(.plain).foregroundStyle(Theme.dim).help("Quit Consai (⌘Q)")
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
    }

    /// Hairline separating footer action groups (create · browse).
    private var footerSep: some View {
        Rectangle().fill(Theme.hairline).frame(width: 1, height: 15).padding(.horizontal, 1)
    }

    private func footerButton(_ symbol: String, _ title: String?, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 12))
                if let title { Text(title).font(Theme.ui(12)) }
            }
        }
        .buttonStyle(.plain).foregroundStyle(Theme.dim).help(help)
    }
}
