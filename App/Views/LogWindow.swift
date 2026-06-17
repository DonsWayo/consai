import SwiftUI
import ConsaiCore
import AppKit

/// Streams a container's logs (`container logs -f`) into a scrolling, filterable view.
struct LogWindow: View {
    let containerID: String

    private struct LogLine: Identifiable { let id: Int; let text: String }

    @State private var streamer = LogStreamer()
    @State private var lines: [LogLine] = []
    @State private var nextID = 0
    @State private var filter = ""
    /// Follow the tail only while the view is parked at the bottom. Scrolling up pauses it
    /// (so you can read); scrolling back to the bottom — or hitting "Jump to latest" — resumes.
    @State private var following = true
    @State private var streamTask: Task<Void, Never>?

    private var visibleLines: [LogLine] {
        filter.isEmpty ? lines : lines.filter { $0.text.localizedCaseInsensitiveContains(filter) }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
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
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(8)
                }
                // Pause following the moment the user scrolls away from the bottom; resume
                // when they return. This is what lets you actually read scrollback.
                .onScrollGeometryChange(for: Bool.self) { geo in
                    geo.contentOffset.y >= geo.contentSize.height - geo.bounds.height - 28
                } action: { _, atBottom in
                    following = atBottom
                }
                // Key off the last line's monotonic id (not count) so following keeps working
                // after the 5000-line cap, where count stops changing.
                .onChange(of: visibleLines.last?.id) { _, _ in
                    if following { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .overlay(alignment: .bottomTrailing) {
                    if !following {
                        Button { following = true; proxy.scrollTo("bottom", anchor: .bottom) } label: {
                            Label("Jump to latest", systemImage: "arrow.down.to.line")
                                .font(.caption).padding(.horizontal, 10).padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent).tint(Theme.jade)
                        .padding(12)
                    }
                }
            }
        }
        .frame(minWidth: 560, minHeight: 360)
        .consaiSurface()
        .preferredColorScheme(.dark).tint(Theme.jade)
        .navigationTitle("Logs — \(containerID)")
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
            start()
        }
        .onDisappear { stop() }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass").foregroundStyle(.secondary)
            TextField("Filter", text: $filter).textFieldStyle(.roundedBorder).frame(maxWidth: 220)
            Label(following ? "Following" : "Paused", systemImage: following ? "dot.radiowaves.up.forward" : "pause.circle")
                .font(.caption).foregroundStyle(following ? Theme.jade : .secondary)
                .help(following ? "Following new log lines — scroll up to pause" : "Paused — scroll to the bottom or tap Jump to latest to resume")
            Spacer()
            Text("\(lines.count) lines").font(.caption).foregroundStyle(.secondary)
            Button("Clear") { lines.removeAll() }
        }
        .padding(8)
    }

    private func highlighted(_ line: String) -> AttributedString {
        var attributed = AttributedString(line)
        guard !filter.isEmpty,
              let range = attributed.range(of: filter, options: .caseInsensitive) else { return attributed }
        attributed[range].backgroundColor = .yellow.opacity(0.4)
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
