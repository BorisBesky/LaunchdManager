import AppKit
import SwiftUI

/// Shows the tail of a job's stdout/stderr log file.
struct LogViewerView: View {
    let log: LogFile

    @State private var content = "Loading…"
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(log.path)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Open in Console") { openInConsole() }
                Button("Reveal in Finder") {
                    NSWorkspace.shared.selectFile(log.path, inFileViewerRootedAtPath: "")
                }
                Button("Refresh") { load() }
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(10)
            Divider()
            TextEditor(text: .constant(content))
                .font(.system(.body, design: .monospaced))
        }
        .frame(minWidth: 640, minHeight: 420)
        .onAppear(perform: load)
    }

    private func openInConsole() {
        DispatchQueue.global().async {
            _ = try? Shell.run("/usr/bin/open", ["-a", "Console", log.path])
        }
    }

    private func load() {
        DispatchQueue.global(qos: .userInitiated).async {
            let text = Self.tail(path: log.path, maxBytes: 256 * 1024)
            DispatchQueue.main.async { content = text }
        }
    }

    static func tail(path: String, maxBytes: Int) -> String {
        guard FileManager.default.fileExists(atPath: path) else { return "(file does not exist yet)" }
        guard let handle = FileHandle(forReadingAtPath: path) else { return "(cannot open file)" }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let offset = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        try? handle.seek(toOffset: offset)
        let data = handle.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? "(binary file, \(data.count) bytes)"
    }
}
