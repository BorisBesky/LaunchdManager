import AppKit
import SwiftUI

struct StringListEditor: View {
    let title: String
    @Binding var items: [String]
    var placeholder: String

    var body: some View {
        Section(title) {
            ForEach(Array(items.indices), id: \.self) { index in
                HStack {
                    TextField(placeholder, text: itemBinding(at: index))
                    Button { items.remove(at: index) } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
            Button { items.append("") } label: {
                Label("Add", systemImage: "plus.circle")
            }
            .buttonStyle(.borderless)
        }
    }

    private func itemBinding(at index: Int) -> Binding<String> {
        Binding(
            get: { items.indices.contains(index) ? items[index] : "" },
            set: { newValue in
                if items.indices.contains(index) { items[index] = newValue }
            }
        )
    }
}

struct EnvListEditor: View {
    @Binding var entries: [EnvEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach($entries) { $entry in
                HStack {
                    TextField("NAME", text: $entry.key)
                    TextField("value", text: $entry.value)
                    Button { entries.removeAll { $0.id == entry.id } } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
            Button { entries.append(EnvEntry()) } label: {
                Label("Add variable", systemImage: "plus.circle")
            }
            .buttonStyle(.borderless)
        }
    }
}

struct JobEditorView: View {
    @State private var job: EditableJob
    let plistPath: String?
    let domain: ServiceDomain
    var onClose: (() -> Void)?

    @State private var selectedTab = 0
    @State private var rawXML = ""
    @State private var rawParseError: String?
    @State private var saveError: String?
    @State private var showSaveError = false
    @State private var isSaving = false

    init(job: EditableJob, plistPath: String?, domain: ServiceDomain, onClose: (() -> Void)? = nil) {
        _job = State(initialValue: job)
        self.plistPath = plistPath
        self.domain = domain
        self.onClose = onClose
    }

    private var issues: [ValidationIssue] { job.validate() }
    private var errors: [ValidationIssue] { issues.filter { !$0.isWarning } }

    var body: some View {
        VStack(spacing: 0) {
            if !issues.isEmpty { issuesBanner }
            TabView(selection: $selectedTab) {
                generalTab
                    .tabItem { Label("General", systemImage: "doc") }.tag(0)
                scheduleTab
                    .tabItem { Label("Schedule", systemImage: "clock") }.tag(1)
                ioTab
                    .tabItem { Label("I/O & Env", systemImage: "terminal") }.tag(2)
                advancedTab
                    .tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }.tag(3)
                rawTab
                    .tabItem { Label("Raw XML", systemImage: "chevron.left.forwardslash.chevron.right") }.tag(4)
            }
            .onChange(of: selectedTab) { newTab in
                if newTab == 4 {
                    rawXML = (try? job.xmlString()) ?? ""
                    rawParseError = nil
                } else {
                    applyRawIfNeeded()
                }
            }
            Divider()
            footer
        }
        .frame(minWidth: 620, minHeight: 560)
        .alert("Cannot Save", isPresented: $showSaveError) {
            Button("OK") {}
        } message: {
            Text(saveError ?? "")
        }
    }

    // MARK: - Tabs

    private var generalTab: some View {
        Form {
            Section("Identity") {
                TextField("Label:", text: $job.label)
                HStack {
                    Text("Destination:")
                    Text(plistPath ?? "\(domain.directory)/\(job.label).plist")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Section("Program") {
                HStack {
                    TextField("Program:", text: $job.program)
                    Button("Choose…") { chooseProgram() }
                }
                StringListEditor(
                    title: "Arguments",
                    items: $job.programArguments,
                    placeholder: "/path/or/argument"
                )
            }
            Section("Options") {
                Toggle("Disabled", isOn: $job.disabled)
                Toggle("Run at load", isOn: $job.runAtLoad)
                Picker("Keep alive:", selection: $job.keepAliveMode) {
                    ForEach(EditableJob.KeepAliveMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                if job.keepAliveMode == .custom {
                    Text("This job uses a custom KeepAlive dictionary — edit it in Raw XML.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var scheduleTab: some View {
        Form {
            Section("Interval") {
                TextField("Start interval (seconds):", text: $job.startInterval)
            }
            Section("Calendar") {
                if job.customCalendar != nil {
                    Text("This job uses a complex calendar schedule (array) — edit it in Raw XML.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Toggle("Run on a calendar schedule", isOn: calendarEnabled)
                    if job.calendarInterval != nil {
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                            GridRow {
                                Text("Minute (0–59):")
                                TextField("any", text: calendarField(\.minute))
                            }
                            GridRow {
                                Text("Hour (0–23):")
                                TextField("any", text: calendarField(\.hour))
                            }
                            GridRow {
                                Text("Day (1–31):")
                                TextField("any", text: calendarField(\.day))
                            }
                            GridRow {
                                Text("Weekday (0–7):")
                                TextField("any", text: calendarField(\.weekday))
                            }
                            GridRow {
                                Text("Month (1–12):")
                                TextField("any", text: calendarField(\.month))
                            }
                        }
                    }
                }
            }
            StringListEditor(
                title: "Watch paths",
                items: $job.watchPaths,
                placeholder: "/path/to/watch"
            )
            StringListEditor(
                title: "Queue directories",
                items: $job.queueDirectories,
                placeholder: "/path/to/dir"
            )
        }
        .formStyle(.grouped)
    }

    private var ioTab: some View {
        Form {
            Section("Standard I/O") {
                TextField("Standard input:", text: $job.standardInPath)
                TextField("Standard output:", text: $job.standardOutPath)
                TextField("Standard error:", text: $job.standardErrorPath)
            }
            Section("Environment") {
                TextField("Working directory:", text: $job.workingDirectory)
                EnvListEditor(entries: $job.environmentVariables)
            }
        }
        .formStyle(.grouped)
    }

    private var advancedTab: some View {
        Form {
            Section("Execution") {
                TextField("Nice (-20…20):", text: $job.nice)
                TextField("Timeout (s):", text: $job.timeOut)
                TextField("Exit timeout (s):", text: $job.exitTimeOut)
                TextField("Throttle interval (s):", text: $job.throttleInterval)
                TextField("Umask (decimal):", text: $job.umask)
            }
            Section("Identity") {
                TextField("User name:", text: $job.userName)
                TextField("Group name:", text: $job.groupName)
                Picker("Process type:", selection: $job.processType) {
                    ForEach(EditableJob.processTypes, id: \.self) { type in
                        Text(type.isEmpty ? "Default" : type).tag(type)
                    }
                }
            }
            Section("Flags") {
                Toggle("Low priority I/O", isOn: $job.lowPriorityIO)
                Toggle("Abandon process group", isOn: $job.abandonProcessGroup)
                Toggle("Debug", isOn: $job.debug)
                Toggle("Launch only once", isOn: $job.launchOnlyOnce)
            }
            if !job.additionalKeys.isEmpty {
                Section("Preserved Keys") {
                    Text("Kept as-is: \(job.additionalKeys.keys.sorted().joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var rawTab: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let rawParseError {
                Label(rawParseError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            TextEditor(text: $rawXML)
                .font(.system(.body, design: .monospaced))
        }
        .padding(8)
    }

    // MARK: - Banner & footer

    private var issuesBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(issues.prefix(4)) { issue in
                HStack(spacing: 6) {
                    Image(systemName: issue.isWarning ? "exclamationmark.triangle.fill" : "xmark.octagon.fill")
                        .foregroundStyle(issue.isWarning ? .yellow : .red)
                    Text(issue.message).font(.callout)
                }
            }
            if issues.count > 4 {
                Text("…and \(issues.count - 4) more")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.yellow.opacity(0.08))
    }

    private var footer: some View {
        HStack {
            Text(plistPath ?? "New job → \(domain.directory)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if isSaving { ProgressView().controlSize(.small) }
            Button("Cancel") { onClose?() }
                .keyboardShortcut(.cancelAction)
            Button("Save") { save() }
                .keyboardShortcut(.defaultAction)
                .disabled(!errors.isEmpty || isSaving)
        }
        .padding(10)
    }

    // MARK: - Actions

    private var calendarEnabled: Binding<Bool> {
        Binding(
            get: { job.calendarInterval != nil },
            set: { job.calendarInterval = $0 ? EditableJob.CalendarInterval() : nil }
        )
    }

    private func calendarField(_ keyPath: WritableKeyPath<EditableJob.CalendarInterval, String>) -> Binding<String> {
        Binding(
            get: { job.calendarInterval?[keyPath: keyPath] ?? "" },
            set: { newValue in
                if job.calendarInterval != nil {
                    job.calendarInterval?[keyPath: keyPath] = newValue
                }
            }
        )
    }

    private func chooseProgram() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            job.program = url.path
        }
    }

    private func applyRawIfNeeded() {
        guard !rawXML.isEmpty else { return }
        do {
            job = try EditableJob.from(xml: rawXML)
            rawParseError = nil
        } catch {
            rawParseError = "Invalid plist XML: \(error.localizedDescription)"
            selectedTab = 4
        }
    }

    private func save() {
        if selectedTab == 4 {
            applyRawIfNeeded()
            if rawParseError != nil { return }
        }
        if let error = job.validate().first(where: { !$0.isWarning }) {
            saveError = error.message
            showSaveError = true
            return
        }
        isSaving = true
        LaunchdController.shared.saveJob(job, originalPath: plistPath, domain: domain) { result in
            isSaving = false
            switch result {
            case .success:
                onClose?()
            case .failure(let failure):
                saveError = failure.localizedDescription
                showSaveError = true
            }
        }
    }
}
