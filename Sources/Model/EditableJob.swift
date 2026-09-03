import Foundation

struct ValidationIssue: Identifiable {
    let message: String
    let isWarning: Bool
    var id: String { message }
}

struct EnvEntry: Identifiable, Equatable {
    var id = UUID()
    var key = ""
    var value = ""
}

/// A mutable, form-friendly representation of a launchd job plist.
/// Keys not understood by the form are preserved in `additionalKeys`
/// and merged back verbatim on save.
struct EditableJob {
    enum KeepAliveMode: String, CaseIterable, Hashable {
        case off = "Off"
        case on = "On"
        case custom = "Custom"
    }

    struct CalendarInterval: Equatable {
        var minute = ""
        var hour = ""
        var day = ""
        var weekday = ""
        var month = ""
        var isEmpty: Bool { minute.isEmpty && hour.isEmpty && day.isEmpty && weekday.isEmpty && month.isEmpty }
    }

    var label = ""
    var program = ""
    var programArguments: [String] = []
    var disabled = false
    var runAtLoad = false
    var keepAliveMode: KeepAliveMode = .off
    var customKeepAlive: Any? // original KeepAlive dictionary, preserved when mode == .custom

    var startInterval = "" // seconds, empty = unset
    var calendarInterval: CalendarInterval?
    var customCalendar: Any? // original StartCalendarInterval array, preserved when set

    var watchPaths: [String] = []
    var queueDirectories: [String] = []

    var standardInPath = ""
    var standardOutPath = ""
    var standardErrorPath = ""
    var workingDirectory = ""
    var environmentVariables: [EnvEntry] = []

    var nice = ""
    var timeOut = ""
    var exitTimeOut = ""
    var throttleInterval = ""
    var umask = ""
    var userName = ""
    var groupName = ""
    var processType = ""
    var lowPriorityIO = false
    var abandonProcessGroup = false
    var debug = false
    var launchOnlyOnce = false

    var additionalKeys: [String: Any] = [:]

    static let processTypes = ["", "Standard", "Background", "Interactive", "Adaptive"]

    static let knownKeys: Set<String> = [
        "Label", "Program", "ProgramArguments", "Disabled", "RunAtLoad", "KeepAlive",
        "StartInterval", "StartCalendarInterval", "WatchPaths", "QueueDirectories",
        "StandardInPath", "StandardOutPath", "StandardErrorPath", "WorkingDirectory",
        "EnvironmentVariables", "Nice", "TimeOut", "ExitTimeOut", "ThrottleInterval",
        "Umask", "UserName", "GroupName", "ProcessType", "LowPriorityIO",
        "AbandonProcessGroup", "Debug", "LaunchOnlyOnce",
    ]

    init() {}

    init(plist: [String: Any]) {
        label = plist["Label"] as? String ?? ""
        program = plist["Program"] as? String ?? ""
        programArguments = plist["ProgramArguments"] as? [String] ?? []
        disabled = plist["Disabled"] as? Bool ?? false
        runAtLoad = plist["RunAtLoad"] as? Bool ?? false
        if let keepAlive = plist["KeepAlive"] as? Bool {
            keepAliveMode = keepAlive ? .on : .off
        } else if let value = plist["KeepAlive"] {
            keepAliveMode = .custom
            customKeepAlive = value
        }
        if let interval = plist["StartInterval"] as? Int { startInterval = String(interval) }
        if let calendar = plist["StartCalendarInterval"] as? [String: Any] {
            var interval = CalendarInterval()
            if let v = calendar["Minute"] as? Int { interval.minute = String(v) }
            if let v = calendar["Hour"] as? Int { interval.hour = String(v) }
            if let v = calendar["Day"] as? Int { interval.day = String(v) }
            if let v = calendar["Weekday"] as? Int { interval.weekday = String(v) }
            if let v = calendar["Month"] as? Int { interval.month = String(v) }
            calendarInterval = interval
        } else if let value = plist["StartCalendarInterval"] {
            customCalendar = value // array form — edited via Raw XML
        }
        watchPaths = plist["WatchPaths"] as? [String] ?? []
        queueDirectories = plist["QueueDirectories"] as? [String] ?? []
        standardInPath = plist["StandardInPath"] as? String ?? ""
        standardOutPath = plist["StandardOutPath"] as? String ?? ""
        standardErrorPath = plist["StandardErrorPath"] as? String ?? ""
        workingDirectory = plist["WorkingDirectory"] as? String ?? ""
        if let env = plist["EnvironmentVariables"] as? [String: String] {
            environmentVariables = env.sorted { $0.key < $1.key }.map { EnvEntry(key: $0.key, value: $0.value) }
        }
        if let v = plist["Nice"] as? Int { nice = String(v) }
        if let v = plist["TimeOut"] as? Int { timeOut = String(v) }
        if let v = plist["ExitTimeOut"] as? Int { exitTimeOut = String(v) }
        if let v = plist["ThrottleInterval"] as? Int { throttleInterval = String(v) }
        if let v = plist["Umask"] as? Int { umask = String(v) }
        userName = plist["UserName"] as? String ?? ""
        groupName = plist["GroupName"] as? String ?? ""
        processType = plist["ProcessType"] as? String ?? ""
        lowPriorityIO = plist["LowPriorityIO"] as? Bool ?? false
        abandonProcessGroup = plist["AbandonProcessGroup"] as? Bool ?? false
        debug = plist["Debug"] as? Bool ?? false
        launchOnlyOnce = plist["LaunchOnlyOnce"] as? Bool ?? false
        additionalKeys = plist.filter { !Self.knownKeys.contains($0.key) }
    }

    func toPlist() -> [String: Any] {
        var dict = additionalKeys
        dict["Label"] = label
        if !program.isEmpty { dict["Program"] = program }
        let args = programArguments.filter { !$0.isEmpty }
        if !args.isEmpty { dict["ProgramArguments"] = args }
        if disabled { dict["Disabled"] = true }
        if runAtLoad { dict["RunAtLoad"] = true }
        switch keepAliveMode {
        case .off: break
        case .on: dict["KeepAlive"] = true
        case .custom:
            if let value = customKeepAlive { dict["KeepAlive"] = value }
        }
        if !startInterval.isEmpty, let interval = Int(startInterval) {
            dict["StartInterval"] = interval
        }
        if let custom = customCalendar {
            dict["StartCalendarInterval"] = custom
        } else if let calendar = calendarInterval, !calendar.isEmpty {
            var value: [String: Int] = [:]
            if let v = Int(calendar.minute) { value["Minute"] = v }
            if let v = Int(calendar.hour) { value["Hour"] = v }
            if let v = Int(calendar.day) { value["Day"] = v }
            if let v = Int(calendar.weekday) { value["Weekday"] = v }
            if let v = Int(calendar.month) { value["Month"] = v }
            if !value.isEmpty { dict["StartCalendarInterval"] = value }
        }
        let paths = watchPaths.filter { !$0.isEmpty }
        if !paths.isEmpty { dict["WatchPaths"] = paths }
        let queues = queueDirectories.filter { !$0.isEmpty }
        if !queues.isEmpty { dict["QueueDirectories"] = queues }
        if !standardInPath.isEmpty { dict["StandardInPath"] = standardInPath }
        if !standardOutPath.isEmpty { dict["StandardOutPath"] = standardOutPath }
        if !standardErrorPath.isEmpty { dict["StandardErrorPath"] = standardErrorPath }
        if !workingDirectory.isEmpty { dict["WorkingDirectory"] = workingDirectory }
        let env = environmentVariables.filter { !$0.key.isEmpty }
        if !env.isEmpty {
            var value: [String: String] = [:]
            for entry in env { value[entry.key] = entry.value }
            dict["EnvironmentVariables"] = value
        }
        if !nice.isEmpty, let v = Int(nice) { dict["Nice"] = v }
        if !timeOut.isEmpty, let v = Int(timeOut) { dict["TimeOut"] = v }
        if !exitTimeOut.isEmpty, let v = Int(exitTimeOut) { dict["ExitTimeOut"] = v }
        if !throttleInterval.isEmpty, let v = Int(throttleInterval) { dict["ThrottleInterval"] = v }
        if !umask.isEmpty, let v = Int(umask) { dict["Umask"] = v }
        if !userName.isEmpty { dict["UserName"] = userName }
        if !groupName.isEmpty { dict["GroupName"] = groupName }
        if !processType.isEmpty { dict["ProcessType"] = processType }
        if lowPriorityIO { dict["LowPriorityIO"] = true }
        if abandonProcessGroup { dict["AbandonProcessGroup"] = true }
        if debug { dict["Debug"] = true }
        if launchOnlyOnce { dict["LaunchOnlyOnce"] = true }
        return dict
    }

    func validate() -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        if label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(ValidationIssue(message: "Label is required.", isWarning: false))
        } else if label.contains(" ") {
            issues.append(ValidationIssue(message: "Label should not contain spaces.", isWarning: true))
        }
        let hasProgram = !program.isEmpty || !programArguments.filter { !$0.isEmpty }.isEmpty
        if !hasProgram && additionalKeys["MachServices"] == nil && additionalKeys["Sockets"] == nil {
            issues.append(ValidationIssue(message: "A job needs either Program or ProgramArguments.", isWarning: false))
        }
        if !program.isEmpty {
            if !program.hasPrefix("/") {
                issues.append(ValidationIssue(message: "Program should be an absolute path.", isWarning: true))
            } else if !FileManager.default.fileExists(atPath: program) {
                issues.append(ValidationIssue(message: "Program does not exist: \(program)", isWarning: true))
            } else if !FileManager.default.isExecutableFile(atPath: program) {
                issues.append(ValidationIssue(message: "Program is not executable: \(program)", isWarning: true))
            }
        }
        let numericFields = [
            ("StartInterval", startInterval), ("Nice", nice), ("TimeOut", timeOut),
            ("ExitTimeOut", exitTimeOut), ("ThrottleInterval", throttleInterval), ("Umask", umask),
        ]
        for (name, value) in numericFields where !value.isEmpty && Int(value) == nil {
            issues.append(ValidationIssue(message: "\(name) must be an integer.", isWarning: false))
        }
        if let calendar = calendarInterval, !calendar.isEmpty {
            let fields: [(String, String, ClosedRange<Int>)] = [
                ("Minute", calendar.minute, 0...59), ("Hour", calendar.hour, 0...23),
                ("Day", calendar.day, 1...31), ("Weekday", calendar.weekday, 0...7),
                ("Month", calendar.month, 1...12),
            ]
            for (name, value, range) in fields where !value.isEmpty {
                guard let number = Int(value) else {
                    issues.append(ValidationIssue(message: "Calendar \(name) must be an integer.", isWarning: false))
                    continue
                }
                if !range.contains(number) {
                    issues.append(ValidationIssue(
                        message: "Calendar \(name) must be between \(range.lowerBound) and \(range.upperBound).",
                        isWarning: true
                    ))
                }
            }
        }
        return issues
    }

    func xmlString() throws -> String {
        let data = try PropertyListSerialization.data(fromPropertyList: toPlist(), format: .xml, options: 0)
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func from(xml: String) throws -> EditableJob {
        guard let data = xml.data(using: .utf8) else {
            throw ShellError(command: "parse", exitCode: -1, output: "Unable to encode XML text.")
        }
        let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let dict = object as? [String: Any] else {
            throw ShellError(command: "parse", exitCode: -1, output: "Top-level plist object must be a dictionary.")
        }
        return EditableJob(plist: dict)
    }
}
