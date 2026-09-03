import AppKit
import SwiftUI

struct LogFile: Identifiable {
    let title: String
    let path: String
    var id: String { path }
}

struct InspectorView: View {
    @ObservedObject var controller: LaunchdController
    @State private var logToView: LogFile?
    @State private var showDeleteConfirmation = false

    var body: some View {
        Group {
            if controller.selection.isEmpty {
                placeholder(title: "No Selection", subtitle: "Select a job to see its details")
            } else if controller.selection.count > 1 {
                multiSelection
            } else if let service = controller.selectedServices.first {
                single(service)
            } else {
                placeholder(title: "No Selection", subtitle: "Select a job to see its details")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 420)
        .onChange(of: controller.selection) { _ in
            if controller.selection.count == 1,
               let service = controller.selectedServices.first {
                controller.loadRuntimeInfo(for: service)
            }
        }
        .sheet(item: $logToView) { LogViewerView(log: $0) }
    }

    private func placeholder(title: String, subtitle: String) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.headline).foregroundStyle(.secondary)
            Text(subtitle).font(.callout).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Single selection

    private func single(_ service: LaunchdService) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(service)
                actionGrid(service)
                if service.isLoaded || !controller.runtimeInfo.isEmpty {
                    section("Runtime") {
                        infoRow("State", controller.runtimeInfo["state"] ?? (service.isLoaded ? "loaded" : "not loaded"))
                        if let pid = service.pid { infoRow("PID", String(pid)) }
                        if let exit = controller.runtimeInfo["last exit code"] { infoRow("Last exit", exit) }
                        if let runs = controller.runtimeInfo["runs"] { infoRow("Runs", runs) }
                    }
                }
                section("Details") {
                    infoRow("Program", service.executableDescription.isEmpty ? "—" : service.executableDescription)
                    infoRow("Schedule", service.scheduleDescription)
                    infoRow("Plist", service.plistPath)
                }
                if service.standardOutPath != nil || service.standardErrorPath != nil {
                    section("Logs") {
                        if let path = service.standardOutPath {
                            logRow(title: "stdout", path: path)
                        }
                        if let path = service.standardErrorPath {
                            logRow(title: "stderr", path: path)
                        }
                    }
                }
                section("File") {
                    HStack(spacing: 8) {
                        Button("Edit…") { controller.openEditor(for: service) }
                        Button("Duplicate") { controller.duplicate(service) }
                    }
                    HStack(spacing: 8) {
                        Button("Reveal in Finder") { controller.revealInFinder([service]) }
                        Button("Delete…", role: .destructive) { showDeleteConfirmation = true }
                    }
                }
            }
            .padding(12)
        }
        .alert("Delete Job", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) { controller.delete(service) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Unload \(service.label) and move its plist to the Trash?")
        }
    }

    private func header(_ service: LaunchdService) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(service.label)
                .font(.headline)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Circle().fill(statusColor(service)).frame(width: 8, height: 8)
                Text(statusText(service)).font(.subheadline)
                if service.isDisabled {
                    Text("Disabled")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
            }
            Text(service.domain.rawValue)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func actionGrid(_ service: LaunchdService) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            if service.isLoaded {
                Button("Unload") { controller.perform(.unload, on: [service]) }
            } else {
                Button("Load") { controller.perform(.load, on: [service]) }
            }
            if service.pid != nil {
                Button("Stop") { controller.perform(.stop, on: [service]) }
            } else {
                Button("Start") { controller.perform(.start, on: [service]) }
                    .disabled(!service.isLoaded)
            }
            Button("Restart") { controller.perform(.restart, on: [service]) }
                .disabled(!service.isLoaded)
            if service.isDisabled {
                Button("Enable") { controller.perform(.enable, on: [service]) }
            } else {
                Button("Disable") { controller.perform(.disable, on: [service]) }
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    // MARK: - Multi selection

    private var multiSelection: some View {
        let targets = controller.selectedServices
        return VStack(alignment: .leading, spacing: 16) {
            Text("\(targets.count) jobs selected")
                .font(.headline)
            VStack(spacing: 8) {
                Button("Load All") { controller.perform(.load, on: targets) }
                Button("Unload All") { controller.perform(.unload, on: targets) }
                Button("Start All") { controller.perform(.start, on: targets) }
                Button("Stop All") { controller.perform(.stop, on: targets) }
                Button("Enable All") { controller.perform(.enable, on: targets) }
                Button("Disable All") { controller.perform(.disable, on: targets) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Helpers

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .trailing)
            Text(value)
                .textSelection(.enabled)
                .lineLimit(4)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.callout)
    }

    private func logRow(title: String, path: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .trailing)
            Text(path)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("View") { logToView = LogFile(title: "\(title): \(path)", path: path) }
                .controlSize(.small)
        }
    }

    private func statusColor(_ service: LaunchdService) -> Color {
        switch service.runState {
        case .running: return .green
        case .failed: return .red
        case .stopped: return .orange
        case .notLoaded: return .gray
        }
    }

    private func statusText(_ service: LaunchdService) -> String {
        switch service.runState {
        case .running: return "Running"
        case .failed:
            if let status = service.lastExitStatus { return "Failed (exit \(status))" }
            return "Failed"
        case .stopped: return "Loaded, not running"
        case .notLoaded: return "Not loaded"
        }
    }
}
