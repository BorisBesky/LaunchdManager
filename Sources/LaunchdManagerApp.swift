import SwiftUI

@main
struct LaunchdManagerApp: App {
    var body: some Scene {
        WindowGroup("launchd Manager") {
            ContentView()
        }
        .defaultSize(width: 1100, height: 680)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Job…") { LaunchdController.shared.newJob() }
                    .keyboardShortcut("n")
                Button("Import plist…") { LaunchdController.shared.importPlist() }
                Divider()
                Button("Refresh") { LaunchdController.shared.refresh() }
                    .keyboardShortcut("r")
            }
            CommandMenu("Job") {
                Button("Load") {
                    LaunchdController.shared.perform(.load, on: LaunchdController.shared.selectedServices)
                }
                Button("Unload") {
                    LaunchdController.shared.perform(.unload, on: LaunchdController.shared.selectedServices)
                }
                Divider()
                Button("Start") {
                    LaunchdController.shared.perform(.start, on: LaunchdController.shared.selectedServices)
                }
                Button("Stop") {
                    LaunchdController.shared.perform(.stop, on: LaunchdController.shared.selectedServices)
                }
                Button("Restart") {
                    LaunchdController.shared.perform(.restart, on: LaunchdController.shared.selectedServices)
                }
                Divider()
                Button("Enable") {
                    LaunchdController.shared.perform(.enable, on: LaunchdController.shared.selectedServices)
                }
                Button("Disable") {
                    LaunchdController.shared.perform(.disable, on: LaunchdController.shared.selectedServices)
                }
                Divider()
                Button("Edit…") {
                    if let service = LaunchdController.shared.selectedServices.first {
                        LaunchdController.shared.openEditor(for: service)
                    }
                }
                Button("Duplicate") {
                    if let service = LaunchdController.shared.selectedServices.first {
                        LaunchdController.shared.duplicate(service)
                    }
                }
            }
        }
    }
}
