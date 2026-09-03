import AppKit
import SwiftUI

/// Manages standalone editor windows (one per plist path), like LaunchControl's
/// double-click-to-edit job windows.
final class EditorWindowManager: NSObject, NSWindowDelegate {
    static let shared = EditorWindowManager()

    private var windows: [String: NSWindow] = [:]

    func open(job: EditableJob, path: String?, domain: ServiceDomain) {
        let key = path ?? "new-job"
        if let existing = windows[key] {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = path.map { ($0 as NSString).lastPathComponent } ?? "New Job"
        window.identifier = NSUserInterfaceItemIdentifier(key)
        window.isReleasedWhenClosed = false
        window.delegate = self

        let view = JobEditorView(job: job, plistPath: path, domain: domain) { [weak window] in
            window?.close()
        }
        window.contentViewController = NSHostingController(rootView: view)
        window.center()
        window.makeKeyAndOrderFront(nil)
        windows[key] = window
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let identifier = window.identifier?.rawValue else { return }
        windows.removeValue(forKey: identifier)
    }
}
