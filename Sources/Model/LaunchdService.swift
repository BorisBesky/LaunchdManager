import Foundation

enum ServiceDomain: String, CaseIterable, Identifiable {
    case userAgent = "User Agents"
    case globalAgent = "Global Agents"
    case systemDaemon = "Global Daemons"
    case appleAgent = "System Agents"
    case appleDaemon = "System Daemons"

    var id: String { rawValue }

    var directory: String {
        switch self {
        case .userAgent: return NSHomeDirectory() + "/Library/LaunchAgents"
        case .globalAgent: return "/Library/LaunchAgents"
        case .systemDaemon: return "/Library/LaunchDaemons"
        case .appleAgent: return "/System/Library/LaunchAgents"
        case .appleDaemon: return "/System/Library/LaunchDaemons"
        }
    }

    /// The launchctl domain target used for bootstrap/bootout/kickstart/...
    var launchctlDomain: String {
        switch self {
        case .userAgent, .globalAgent, .appleAgent: return "gui/\(getuid())"
        case .systemDaemon, .appleDaemon: return "system"
        }
    }

    var isApple: Bool { self == .appleAgent || self == .appleDaemon }

    /// Whether the current user can write to the domain directory directly.
    var isWritable: Bool { self == .userAgent }
}

/// Sidebar category selection. Using a real enum case (instead of a nil
/// optional) for "All Domains" so the row can actually stay selected.
enum CategoryFilter: Hashable {
    case all
    case domain(ServiceDomain)
}

enum JobRunState: CaseIterable {
    case running
    case failed    // loaded, not running, last exit != 0
    case stopped   // loaded, not running
    case notLoaded

    /// Label matching the status column text.
    var filterLabel: String {
        switch self {
        case .running: return "Running"
        case .failed: return "Failed"
        case .stopped: return "Loaded"
        case .notLoaded: return "Not loaded"
        }
    }

    var filterIcon: String {
        switch self {
        case .running: return "play.circle"
        case .failed: return "xmark.circle"
        case .stopped: return "pause.circle"
        case .notLoaded: return "minus.circle"
        }
    }
}

struct LaunchdService: Identifiable, Hashable {
    let label: String
    let plistPath: String
    let domain: ServiceDomain
    let plist: [String: Any]
    var pid: Int?
    var lastExitStatus: Int?
    var disabledOverride: Bool?

    var id: String { label }

    /// NOTE: equality covers every field the UI renders — pid, exit status,
    /// disabled state, and plist content. SwiftUI's `Table` skips re-rendering
    /// rows that compare equal, so an id-only `==` left stale status dots
    /// after Start/Stop (the inspector re-renders unconditionally and was
    /// already correct).
    static func == (lhs: LaunchdService, rhs: LaunchdService) -> Bool {
        lhs.label == rhs.label
            && lhs.plistPath == rhs.plistPath
            && lhs.domain == rhs.domain
            && lhs.pid == rhs.pid
            && lhs.lastExitStatus == rhs.lastExitStatus
            && lhs.disabledOverride == rhs.disabledOverride
            && NSDictionary(dictionary: lhs.plist).isEqual(to: rhs.plist)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(label)
        hasher.combine(plistPath)
        hasher.combine(domain)
        hasher.combine(pid)
        hasher.combine(lastExitStatus)
        hasher.combine(disabledOverride)
        hasher.combine(Self.plistFingerprint(plist))
    }

    /// Deterministic content fingerprint (Apple's XML serializer emits
    /// dictionary keys in sorted order). A pure function of content, so equal
    /// plists always fingerprint equal — keeping `hash` consistent with `==`.
    private static func plistFingerprint(_ plist: [String: Any]) -> Data {
        (try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)) ?? Data()
    }

    // MARK: - plist accessors

    var program: String? { plist["Program"] as? String }
    var programArguments: [String] { plist["ProgramArguments"] as? [String] ?? [] }
    var runAtLoad: Bool { plist["RunAtLoad"] as? Bool ?? false }
    var disabledInPlist: Bool { plist["Disabled"] as? Bool ?? false }
    var keepAlive: Bool {
        if let value = plist["KeepAlive"] as? Bool { return value }
        return plist["KeepAlive"] != nil // dictionary form counts as "conditional keep alive"
    }
    var startInterval: Int? { plist["StartInterval"] as? Int }
    var hasCalendarInterval: Bool { plist["StartCalendarInterval"] != nil }
    var watchPaths: [String] { plist["WatchPaths"] as? [String] ?? [] }
    var standardOutPath: String? { plist["StandardOutPath"] as? String }
    var standardErrorPath: String? { plist["StandardErrorPath"] as? String }

    // MARK: - derived state

    var isDisabled: Bool { disabledOverride ?? disabledInPlist }
    var isLoaded: Bool { pid != nil || lastExitStatus != nil }

    var runState: JobRunState {
        if pid != nil { return .running }
        if let status = lastExitStatus, status != 0 { return .failed }
        if lastExitStatus != nil { return .stopped }
        return .notLoaded
    }

    var executableDescription: String {
        if let program, !program.isEmpty {
            return ([program] + programArguments).joined(separator: " ")
        }
        return programArguments.joined(separator: " ")
    }

    var scheduleDescription: String {
        var parts: [String] = []
        if runAtLoad { parts.append("at load") }
        if let interval = startInterval { parts.append("every \(interval)s") }
        if hasCalendarInterval { parts.append("calendar") }
        if !watchPaths.isEmpty { parts.append("on file change") }
        if keepAlive { parts.append("keep alive") }
        return parts.isEmpty ? "on demand" : parts.joined(separator: ", ")
    }
}
