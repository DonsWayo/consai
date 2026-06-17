import SwiftUI
import ConsaiCore
import ConsaiKit
import AppKit

/// Side-by-side log viewer for up to 5 containers. Each pane owns its own LogStreamer
/// and scroll position; a shared filter bar narrows all panes at once.
struct MultiLogWindow: View {
    @Environment(AppState.self) private var appState

    /// Ordered list of container IDs being watched.
    @State private var watching: [String] = []
    @State private var globalFilter = ""

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if watching.isEmpty {
                EmptyState(
                    symbol: "doc.text.below.ecg",
                    title: "No containers selected",
                    subtitle: "Add up to 5 containers from the toolbar to watch their logs side by side."
                )
            } else {
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        ForEach(Array(watching.enumerated()), id: \.element) { index, id in
                            if index > 0 {
                                Rectangle().fill(Theme.hairline).frame(width: 0.5)
                            }
                            LogPane(
                                containerID: id,
                                accentColor: Theme.logPalette[index % Theme.logPalette.count],
                                globalFilter: globalFilter,
                                onClose: { watching.removeAll { $0 == id } }
                            )
                            .frame(width: geo.size.width / CGFloat(watching.count))
                        }
                    }
                }
            }
        }
        .frame(minWidth: CGFloat(max(watching.count, 1)) * 380, minHeight: 420)
        .consaiSurface()
        .preferredColorScheme(.dark).tint(Theme.jade)
        .navigationTitle("Multi-log")
        .onAppear { NSApp.activate(ignoringOtherApps: true) }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            // Add container picker
            Menu {
                let available = appState.containers.filter { !watching.contains($0.id) }
                if available.isEmpty {
                    Text("No other containers").foregroundStyle(Theme.dim2)
                } else {
                    ForEach(available) { container in
                        Button { watching.append(container.id) } label: {
                            Label(container.name, systemImage: container.status == .running ? "circle.fill" : "circle")
                        }
                    }
                }
            } label: {
                Label("Add", systemImage: "plus.circle")
                    .font(Theme.ui(12))
            }
            .disabled(watching.count >= 5)
            .help("Add a container stream (max 5)")

            // Active pane chips
            ForEach(Array(watching.enumerated()), id: \.element) { index, id in
                let name = appState.containers.first(where: { $0.id == id })?.name ?? String(id.prefix(8))
                let color = Theme.logPalette[index % Theme.logPalette.count]
                PaneChip(name: name, color: color) { watching.removeAll { $0 == id } }
            }

            Spacer(minLength: 8)

            // Global filter
            HStack(spacing: 5) {
                Image(systemName: "line.3.horizontal.decrease").foregroundStyle(Theme.dim)
                TextField("Filter all panes", text: $globalFilter)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 180)
                if !globalFilter.isEmpty {
                    Button { globalFilter = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(Theme.dim)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }
}

/// Small labeled chip identifying one active pane; click × to close.
private struct PaneChip: View {
    let name: String
    let color: Color
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(name).font(Theme.ui(11, .medium)).lineLimit(1)
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain).foregroundStyle(Theme.dim)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
        .foregroundStyle(color)
    }
}

/// One container's log stream — self-contained with its own LogStreamer, scroll position,
/// and follow state. Receives a globalFilter that ANDs with its local search.
private struct LogPane: View {
    let containerID: String
    let accentColor: Color
    let globalFilter: String
    let onClose: () -> Void

    private struct LogLine: Identifiable { let id: Int; let text: String }

    @State private var streamer = LogStreamer()
    @State private var lines: [LogLine] = []
    @State private var nextID = 0
    @State private var localFilter = ""
    @State private var following = true
    @State private var streamTask: Task<Void, Never>?

    private var visibleLines: [LogLine] {
        lines.filter { line in
            let matchGlobal = globalFilter.isEmpty || line.text.localizedCaseInsensitiveContains(globalFilter)
            let matchLocal  = localFilter.isEmpty  || line.text.localizedCaseInsensitiveContains(localFilter)
            return matchGlobal && matchLocal
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            paneHeader
            Rectangle().fill(Theme.hairline).frame(height: 0.5)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(visibleLines) { line in
                            Text(highlighted(line.text))
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(line.id)
                        }
                        Color.clear.frame(height: 1).id("bottom-\(containerID)")
                    }
                    .padding(6)
                }
                .onScrollGeometryChange(for: Bool.self) { geo in
                    geo.contentOffset.y >= geo.contentSize.height - geo.bounds.height - 28
                } action: { _, atBottom in
                    following = atBottom
                }
                .onChange(of: visibleLines.last?.id) { _, _ in
                    if following { proxy.scrollTo("bottom-\(containerID)", anchor: .bottom) }
                }
                .overlay(alignment: .bottomTrailing) {
                    if !following {
                        Button {
                            following = true
                            proxy.scrollTo("bottom-\(containerID)", anchor: .bottom)
                        } label: {
                            Image(systemName: "arrow.down.to.line")
                                .font(.caption).padding(6)
                        }
                        .buttonStyle(.borderedProminent).tint(accentColor)
                        .padding(8)
                    }
                }
            }
        }
        .onAppear { start() }
        .onDisappear { stop() }
    }

    private var paneHeader: some View {
        HStack(spacing: 6) {
            Circle().fill(accentColor).frame(width: 7, height: 7)
            Text(containerID).font(Theme.ui(11, .medium)).foregroundStyle(accentColor).lineLimit(1)

            Spacer(minLength: 4)

            TextField("Filter", text: $localFilter)
                .textFieldStyle(.roundedBorder)
                .font(Theme.mono(10))
                .frame(maxWidth: 100)

            Text("\(lines.count)")
                .font(Theme.mono(10)).foregroundStyle(Theme.dim2)

            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain).foregroundStyle(Theme.dim).help("Close pane")
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
    }

    private func highlighted(_ line: String) -> AttributedString {
        var attributed = AttributedString(line)
        let term = localFilter.isEmpty ? globalFilter : localFilter
        guard !term.isEmpty,
              let range = attributed.range(of: term, options: .caseInsensitive) else { return attributed }
        attributed[range].backgroundColor = .yellow.opacity(0.35)
        return attributed
    }

    private func start() {
        streamTask = Task { @MainActor in
            for await line in streamer.stream(id: containerID) {
                lines.append(LogLine(id: nextID, text: line))
                nextID += 1
                if lines.count > 5000 { lines.removeFirst(lines.count - 5000) }
            }
        }
    }

    private func stop() {
        streamTask?.cancel()
        streamer.stop()
    }
}
