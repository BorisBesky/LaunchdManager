import SwiftUI

struct ContentView: View {
    @StateObject private var controller = LaunchdController.shared
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } content: {
            JobTableView(controller: controller)
                .navigationTitle(contentTitle)
                .toolbar { toolbarContent }
                .searchable(text: $controller.searchText, placement: .toolbar, prompt: "Filter by label or program")
        } detail: {
            InspectorView(controller: controller)
        }
        .onAppear { controller.refresh() }
        .frame(minWidth: 1020, minHeight: 600)
        .alert("Action Failed", isPresented: errorBinding) {
            Button("OK") { controller.lastError = nil }
        } message: {
            Text(controller.lastError ?? "")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { controller.lastError != nil },
            set: { if !$0 { controller.lastError = nil } }
        )
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        ScrollView {
            VStack(spacing: 2) {
                SidebarRow(
                    title: "All Domains",
                    icon: "tray.full",
                    count: controller.services.count,
                    isSelected: selectedCategory == .all
                ) {
                    controller.category = .all
                }
                ForEach(ServiceDomain.allCases) { domain in
                    SidebarRow(
                        title: domain.rawValue,
                        icon: icon(for: domain),
                        count: count(for: domain),
                        isSelected: selectedCategory == .domain(domain)
                    ) {
                        controller.category = .domain(domain)
                    }
                }
            }
            .padding(6)
        }
        .navigationSplitViewColumnWidth(min: 170, ideal: 195, max: 250)
    }

    private var selectedCategory: CategoryFilter {
        controller.category ?? .all
    }

    private var contentTitle: String {
        guard let category = controller.category else { return "All Domains" }
        switch category {
        case .all: return "All Domains"
        case .domain(let domain): return domain.rawValue
        }
    }

    private func count(for domain: ServiceDomain) -> Int {
        controller.services.filter { $0.domain == domain }.count
    }

    private func icon(for domain: ServiceDomain) -> String {
        switch domain {
        case .userAgent: return "person"
        case .globalAgent: return "person.2"
        case .systemDaemon: return "gearshape.2"
        case .appleAgent, .appleDaemon: return "applelogo"
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { controller.newJob() } label: {
                Label("New Job", systemImage: "plus")
            }
            .help("Create a new user agent")
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                JobActionsMenuContent(controller: controller, targets: controller.selectedServices)
            } label: {
                Label("Actions", systemImage: "gearshape")
            }
            .disabled(controller.selection.isEmpty)
            .help("Actions for the selected jobs")
        }
        ToolbarItem(placement: .primaryAction) {
            Toggle(isOn: $controller.showOnlyRunning) {
                Label("Running Only", systemImage: "line.3.horizontal.decrease.circle")
            }
            .toggleStyle(.button)
            .help("Show only running jobs")
        }
        ToolbarItem(placement: .primaryAction) {
            Button { controller.refresh() } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r")
            .help("Rescan all domains")
            .disabled(controller.isRefreshing)
        }
        ToolbarItem(placement: .primaryAction) {
            // Fixed-size slot so the toolbar never reflows when the spinner appears.
            ProgressView()
                .controlSize(.small)
                .frame(width: 16, height: 16)
                .opacity(controller.isRefreshing ? 1 : 0)
        }
    }
}
