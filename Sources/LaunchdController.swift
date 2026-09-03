import AppKit
import Foundation
import UniformTypeIdentifiers

enum ServiceAction: String {
    case load = "Load"
    case unload = "Unload"
    case start = "Start"
    case stop = "Stop"
    case restart = "Restart"
    case enable = "Enable"
    case disable = "Disable"
}

final class LaunchdController: ObservableObject {
    static let shared = LaunchdController()

    @Published private(set) var services: [LaunchdService] = []
    @Published private(set) var isRefreshing = false
    @Published var selection = Set<String>()
    @Published var searchText = ""
    @Published var category: CategoryFilter? = .all
    @Published var statusFilter: JobRunState? = nil
    @Published var lastMessage: String?
    @Published var lastError: String?
    @Published var runtimeInfo: [String: String] = [:]

    private var statusTimer: Timer?
    private var runtimeInfoGeneration = 0

    var selectedServices: [LaunchdService] {
        services.filter { selection.contains($0.id) }
    }

    private init() {
        // Lightweight status polling keeps PID/exit-code columns live.
        statusTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refreshStatus()
        }
        statusTimer?.tolerance = 1
    }

    // MARK: - Scanning

    /// Full rescan: re-reads every plist on disk plus runtime state.
    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        DispatchQueue.global(qos: .userInitiated).async {
            var services = Self.scanAllDomains()
            let states = Self.runtimeStates()
            let disabled = Self.disabledOverrides()
            for index in services.indices {
                if let state = states[services[index].label] {
                    services[index].pid = state.pid
                    services[index].lastExitStatus = state.status
                }
                if let override = disabled[services[index].label] {
                    services[index].disabledOverride = override
                }
            }
            services.sort { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
            DispatchQueue.main.async {
                self.services = services
                self.isRefreshing = false
            }
        }
    }

    /// Cheap update: only queries launchd for runtime state, no disk I/O.
    func refreshStatus() {
        guard !isRefreshing else { return }
        isRefreshing = true
        DispatchQueue.global(qos: .userInitiated).async {
            let states = Self.runtimeStates()
            let disabled = Self.disabledOverrides()
            DispatchQueue.main.async {
                var services = self.services
                for index in services.indices {
                    services[index].pid = states[services[index].label]?.pid
                    services[index].lastExitStatus = states[services[index].label]?.status
                    if let override = disabled[services[index].label] {
                        services[index].disabledOverride = override
                    }
                }
                self.services = services
                self.isRefreshing = false
                if self.selection.count == 1,
                   let service = services.first(where: { self.selection.contains($0.id) }) {
                    self.loadRuntimeInfo(for: service)
                }
            }
        }
    }

    private static func scanAllDomains() -> [LaunchdService] {
        var result: [LaunchdService] = []
        let fileManager = FileManager.default
        for domain in ServiceDomain.allCases {
            guard let files = try? fileManager.contentsOfDirectory(atPath: domain.directory) else { continue }
            for file in files where file.hasSuffix(".plist") {
                let path = (domain.directory as NSString).appendingPathComponent(file)
                guard let plist = try? readPlist(at: path),
                      let label = plist["Label"] as? String, !label.isEmpty else { continue }
                result.append(LaunchdService(
                    label: label,
                    plistPath: path,
                    domain: domain,
                    plist: plist,
                    pid: nil,
                    lastExitStatus: nil,
                    disabledOverride: nil
                ))
            }
        }
        return result
    }

    static func readPlist(at path: String) throws -> [String: Any] {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let dict = object as? [String: Any] else {
            throw ShellError(command: path, exitCode: -1, output: "Not a dictionary plist.")
        }
        return dict
    }

    /// `launchctl list` → label → (pid, last exit status)
    private static func runtimeStates() -> [String: (pid: Int?, status: Int?)] {
        guard let output = try? Shell.run("/bin/launchctl", ["list"]) else { return [:] }
        var states: [String: (Int?, Int?)] = [:]
        for line in output.split(separator: "\n") {
            let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard columns.count >= 3 else { continue }
            let label = String(columns[2])
            states[label] = (Int(columns[0]), Int(columns[1]))
        }
        return states
    }

    /// `launchctl print-disabled` → label → disabled?
    private static func disabledOverrides() -> [String: Bool] {
        var result: [String: Bool] = [:]
        for domain in ["gui/\(getuid())", "system"] {
            guard let output = try? Shell.run("/bin/launchctl", ["print-disabled", domain]) else { continue }
            for line in output.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("\""),
                      let endQuote = trimmed.dropFirst().firstIndex(of: "\"") else { continue }
                let label = String(trimmed.dropFirst()[..<endQuote])
                if trimmed.contains("=> disabled") { result[label] = true }
                else if trimmed.contains("=> enabled") { result[label] = false }
            }
        }
        return result
    }

    // MARK: - Job actions

    func perform(_ action: ServiceAction, on targets: [LaunchdService]) {
        guard !targets.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            var failures: [String] = []
            for service in targets {
                do {
                    try self.execute(action, on: service)
                } catch {
                    failures.append("\(service.label): \(error.localizedDescription)")
                }
            }
            DispatchQueue.main.async {
                if failures.isEmpty {
                    let name = targets.count == 1 ? targets[0].label : "\(targets.count) jobs"
                    self.lastMessage = "\(action.rawValue) succeeded for \(name)"
                } else {
                    self.lastError = failures.joined(separator: "\n")
                }
                self.refreshStatus()
            }
        }
    }

    /// Synchronous launchctl invocation. Retries with administrator privileges
    /// for jobs outside the user domain when the direct call fails.
    func execute(_ action: ServiceAction, on service: LaunchdService) throws {
        let domain = service.domain.launchctlDomain
        let target = "\(domain)/\(service.label)"
        let arguments: [String]
        switch action {
        case .load: arguments = ["bootstrap", domain, service.plistPath]
        case .unload: arguments = ["bootout", domain, service.plistPath]
        case .start: arguments = ["kickstart", target]
        case .stop: arguments = ["kill", "SIGTERM", target]
        case .restart: arguments = ["kickstart", "-k", target]
        case .enable: arguments = ["enable", target]
        case .disable: arguments = ["disable", target]
        }
        do {
            try Shell.run("/bin/launchctl", arguments)
        } catch {
            if service.domain == .userAgent { throw error }
            let command = (["/bin/launchctl"] + arguments).map(Shell.shellQuote).joined(separator: " ")
            try Shell.runAdmin(command)
        }
    }

    /// Detailed runtime info for the inspector (`launchctl print`).
    func loadRuntimeInfo(for service: LaunchdService) {
        runtimeInfoGeneration += 1
        let generation = runtimeInfoGeneration
        let target = "\(service.domain.launchctlDomain)/\(service.label)"
        DispatchQueue.global(qos: .userInitiated).async {
            guard let output = try? Shell.run("/bin/launchctl", ["print", target]) else {
                DispatchQueue.main.async {
                    if self.runtimeInfoGeneration == generation { self.runtimeInfo = [:] }
                }
                return
            }
            var info: [String: String] = [:]
            let wanted: Set<String> = ["state", "pid", "last exit code", "runs"]
            for line in output.split(separator: "\n") {
                let parts = line.split(separator: "=", maxSplits: 1).map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
                guard parts.count == 2, wanted.contains(parts[0]) else { continue }
                info[parts[0]] = parts[1]
            }
            DispatchQueue.main.async {
                if self.runtimeInfoGeneration == generation { self.runtimeInfo = info }
            }
        }
    }

    // MARK: - File operations

    /// Saves a job plist. Writes directly for user agents; otherwise stages to a
    /// temp file and installs as root (with ownership/permissions launchd accepts).
    /// If the job is currently loaded it is reloaded so changes take effect.
    func saveJob(
        _ job: EditableJob,
        originalPath: String?,
        domain: ServiceDomain,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let path = originalPath ?? "\(domain.directory)/\(job.label).plist"
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let plist = job.toPlist()
                let data = try PropertyListSerialization.data(
                    fromPropertyList: plist, format: .xml, options: 0
                )
                if domain.isWritable {
                    try FileManager.default.createDirectory(
                        atPath: domain.directory, withIntermediateDirectories: true
                    )
                    try data.write(to: URL(fileURLWithPath: path), options: .atomic)
                } else {
                    let temp = NSTemporaryDirectory() + "launchdmanager-\(UUID().uuidString).plist"
                    try data.write(to: URL(fileURLWithPath: temp))
                    defer { try? FileManager.default.removeItem(atPath: temp) }
                    try Shell.runAdmin(
                        "cp \(Shell.shellQuote(temp)) \(Shell.shellQuote(path))" +
                        " && chown root:wheel \(Shell.shellQuote(path))" +
                        " && chmod 644 \(Shell.shellQuote(path))"
                    )
                }
                if let existing = self.services.first(where: { $0.label == job.label }), existing.isLoaded {
                    let reloaded = LaunchdService(
                        label: job.label, plistPath: path, domain: domain, plist: plist,
                        pid: existing.pid, lastExitStatus: existing.lastExitStatus,
                        disabledOverride: existing.disabledOverride
                    )
                    try? self.execute(.unload, on: reloaded)
                    try? self.execute(.load, on: reloaded)
                }
                DispatchQueue.main.async {
                    self.lastMessage = "Saved \((path as NSString).lastPathComponent)"
                    self.refresh()
                    completion(.success(path))
                }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    /// Unloads the job if needed and moves its plist to the Trash
    /// (falls back to a root delete for system locations).
    func delete(_ service: LaunchdService) {
        DispatchQueue.global(qos: .userInitiated).async {
            var errorMessage: String?
            if service.isLoaded { try? self.execute(.unload, on: service) }
            do {
                try FileManager.default.trashItem(
                    at: URL(fileURLWithPath: service.plistPath), resultingItemURL: nil
                )
            } catch {
                do {
                    try Shell.runAdmin("rm \(Shell.shellQuote(service.plistPath))")
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            DispatchQueue.main.async {
                if let errorMessage {
                    self.lastError = "Delete failed: \(errorMessage)"
                } else {
                    self.lastMessage = "Deleted \(service.label)"
                    self.selection.remove(service.id)
                }
                self.refresh()
            }
        }
    }

    /// Copies the plist under a new unique label (disabled by default).
    /// Apple/system jobs are duplicated into the user agents directory.
    func duplicate(_ service: LaunchdService) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                var plist = service.plist
                let directory = service.domain.isWritable
                    ? service.domain.directory
                    : ServiceDomain.userAgent.directory
                var newLabel = service.label + ".copy"
                var counter = 2
                while FileManager.default.fileExists(atPath: "\(directory)/\(newLabel).plist")
                        || self.services.contains(where: { $0.label == newLabel }) {
                    newLabel = "\(service.label).copy\(counter)"
                    counter += 1
                }
                plist["Label"] = newLabel
                plist["Disabled"] = true
                let data = try PropertyListSerialization.data(
                    fromPropertyList: plist, format: .xml, options: 0
                )
                try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
                try data.write(to: URL(fileURLWithPath: "\(directory)/\(newLabel).plist"), options: .atomic)
                DispatchQueue.main.async {
                    self.lastMessage = "Duplicated as \(newLabel)"
                    self.refresh()
                }
            } catch {
                DispatchQueue.main.async { self.lastError = "Duplicate failed: \(error.localizedDescription)" }
            }
        }
    }

    /// Imports a plist file chosen by the user into ~/Library/LaunchAgents.
    func importPlist() {
        let panel = NSOpenPanel()
        panel.title = "Import launchd plist"
        panel.allowedContentTypes = [.propertyList]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let plist = try Self.readPlist(at: url.path)
                guard let label = plist["Label"] as? String, !label.isEmpty else {
                    throw ShellError(command: url.path, exitCode: -1, output: "The plist has no Label key.")
                }
                let directory = ServiceDomain.userAgent.directory
                let destination = "\(directory)/\(label).plist"
                if FileManager.default.fileExists(atPath: destination) {
                    throw ShellError(command: url.path, exitCode: -1, output: "\(label).plist already exists in User Agents.")
                }
                try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
                try FileManager.default.copyItem(atPath: url.path, toPath: destination)
                DispatchQueue.main.async {
                    self.lastMessage = "Imported \(label)"
                    self.refresh()
                }
            } catch {
                DispatchQueue.main.async { self.lastError = "Import failed: \(error.localizedDescription)" }
            }
        }
    }

    // MARK: - Editor windows

    func openEditor(for service: LaunchdService) {
        let plist = (try? Self.readPlist(at: service.plistPath)) ?? service.plist
        EditorWindowManager.shared.open(
            job: EditableJob(plist: plist), path: service.plistPath, domain: service.domain
        )
    }

    func newJob() {
        var job = EditableJob()
        job.label = "com.\(NSUserName().lowercased()).newjob"
        job.runAtLoad = true
        EditorWindowManager.shared.open(job: job, path: nil, domain: .userAgent)
    }

    // MARK: - Clipboard / Finder

    func revealInFinder(_ targets: [LaunchdService]) {
        for service in targets {
            NSWorkspace.shared.selectFile(service.plistPath, inFileViewerRootedAtPath: "")
        }
    }

    func openPlist(_ service: LaunchdService) {
        NSWorkspace.shared.open(URL(fileURLWithPath: service.plistPath))
    }

    func copyLabels(_ targets: [LaunchdService]) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(targets.map(\.label).joined(separator: "\n"), forType: .string)
    }

    func copyPlistXML(_ service: LaunchdService) {
        guard let data = try? PropertyListSerialization.data(
            fromPropertyList: service.plist, format: .xml, options: 0
        ), let xml = String(data: data, encoding: .utf8) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(xml, forType: .string)
    }
}
