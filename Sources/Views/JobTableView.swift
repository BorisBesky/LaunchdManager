import SwiftUI

/// Shared action menu items, used by both the toolbar menu and the table context menu.
struct JobActionsMenuContent: View {
    let controller: LaunchdController
    let targets: [LaunchdService]

    var body: some View {
        Button("Load") { controller.perform(.load, on: targets) }
        Button("Unload") { controller.perform(.unload, on: targets) }
        Divider()
        Button("Start") { controller.perform(.start, on: targets) }
        Button("Stop") { controller.perform(.stop, on: targets) }
        Button("Restart") { controller.perform(.restart, on: targets) }
        Divider()
        Button("Enable") { controller.perform(.enable, on: targets) }
        Button("Disable") { controller.perform(.disable, on: targets) }
        if targets.count == 1, let service = targets.first {
            Divider()
            Button("Edit…") { controller.openEditor(for: service) }
            Button("Duplicate") { controller.duplicate(service) }
        }
    }
}

struct JobTableView: View {
    @ObservedObject var controller: LaunchdController
    @State private var sortOrder = [KeyPathComparator(\LaunchdService.label)]
    @State private var pendingDelete: [LaunchdService] = []
    @State private var showDeleteConfirmation = false

    private var filtered: [LaunchdService] {
        var result = controller.services
        if let category = controller.category, case .domain(let domain) = category {
            result = result.filter { $0.domain == domain }
        }
        if let status = controller.statusFilter {
            result = result.filter { $0.runState == status }
        }
        if !controller.searchText.isEmpty {
            result = result.filter {
                $0.label.localizedCaseInsensitiveContains(controller.searchText)
                    || $0.executableDescription.localizedCaseInsensitiveContains(controller.searchText)
            }
        }
        return result.sorted(using: sortOrder)
    }

    var body: some View {
        Table(filtered, selection: $controller.selection, sortOrder: $sortOrder) {
            TableColumn("Status") { service in
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor(service))
                        .frame(width: 8, height: 8)
                    Text(statusText(service))
                        .foregroundStyle(service.isDisabled ? .secondary : .primary)
                }
            }
            .width(ideal: 95, max: 120)

            TableColumn("Label", value: \.label) { service in
                Text(service.label)
                    .foregroundStyle(service.isDisabled ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .width(min: 180, ideal: 320)

            TableColumn("PID") { service in
                Text(service.pid.map(String.init) ?? "—")
            }
            .width(ideal: 55, max: 80)

            TableColumn("Exit") { service in
                Text(service.lastExitStatus.map(String.init) ?? "—")
            }
            .width(ideal: 45, max: 60)

            TableColumn("Schedule") { service in
                Text(service.scheduleDescription).lineLimit(1)
            }
            .width(ideal: 130)

            TableColumn("Program") { service in
                Text(service.executableDescription)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
            }
            .width(min: 140, ideal: 260)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            let targets = controller.services.filter { ids.contains($0.id) }
            JobActionsMenuContent(controller: controller, targets: targets)
            Divider()
            Button("Reveal plist in Finder") { controller.revealInFinder(targets) }
            Button("Open plist") { targets.forEach { controller.openPlist($0) } }
            Divider()
            Button("Copy Label") { controller.copyLabels(targets) }
            if targets.count == 1, let service = targets.first {
                Button("Copy plist as XML") { controller.copyPlistXML(service) }
            }
            Divider()
            Button("Delete…", role: .destructive) {
                pendingDelete = targets
                showDeleteConfirmation = true
            }
        } primaryAction: { ids in
            if let id = ids.first,
               let service = controller.services.first(where: { $0.id == id }) {
                controller.openEditor(for: service)
            }
        }
        .alert("Delete Job", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                pendingDelete.forEach { controller.delete($0) }
                pendingDelete = []
            }
            Button("Cancel", role: .cancel) { pendingDelete = [] }
        } message: {
            if pendingDelete.count == 1, let service = pendingDelete.first {
                Text("Unload \(service.label) and move its plist to the Trash?")
            } else {
                Text("Unload \(pendingDelete.count) jobs and move their plists to the Trash?")
            }
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
            if let status = service.lastExitStatus { return "Failed (\(status))" }
            return "Failed"
        case .stopped: return "Loaded"
        case .notLoaded: return "Not loaded"
        }
    }
}
