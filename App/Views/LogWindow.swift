import SwiftUI
import ConsaiCore
import AppKit

/// Streams a container's logs (`container logs -f`) into a scrolling, filterable view.
struct LogWindow: View {
    let containerID: String

    @State private var streamer = LogStreamer()
    @State private var lines: [String] = []
    @State private var filter = ""
    @State private var autoscroll = true
    @State private var streamTask: Task<Void, Never>?

    private var visibleLines: [(offset: Int, element: String)] {
        let filtered = filter.isEmpty
            ? lines
            : lines.filter { $0.localizedCaseInsensitiveContains(filter) }
        return Array(filtered.enumerated())
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(visibleLines, id: \.offset) { item in
                            Text(highlighted(item.element))
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(item.offset)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(8)
                }
                .onChange(of: lines.count) { _, _ in
                    if autoscroll { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
        }
        .frame(minWidth: 560, minHeight: 360)
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
            Toggle("Autoscroll", isOn: $autoscroll).toggleStyle(.checkbox)
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
        streamTask = Task {
            for await line in streamer.stream(id: containerID) {
                lines.append(line)
                if lines.count > 5000 { lines.removeFirst(lines.count - 5000) }
            }
        }
    }

    private func stop() {
        streamTask?.cancel()
        streamer.stop()
    }
}
