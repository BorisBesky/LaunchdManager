# LaunchdManager

A native macOS app for browsing and managing `launchd` jobs — LaunchAgents and
LaunchDaemons — inspired by LaunchControl. Built with SwiftUI, distributed as a
plain `.app` bundle compiled with `swiftc` (no Xcode project required).

## Features

**Browse all launchd domains**

- User Agents (`~/Library/LaunchAgents`)
- Global Agents (`/Library/LaunchAgents`)
- Global Daemons (`/Library/LaunchDaemons`)
- System Agents (`/System/Library/LaunchAgents`)
- System Daemons (`/System/Library/LaunchDaemons`)

Each category in the sidebar shows a live job count; selecting one filters the
job table.

**Live job status**

- Status indicator per job: running (green), failed with exit code (red),
  loaded-but-idle (orange), not loaded (gray)
- PID and last exit status, polled from `launchctl list` every 60 seconds
- Disabled state read from the launchd overrides database
  (`launchctl print-disabled`)
- Search filter, "Running only" toggle, sortable columns

**Manage jobs**

- Load / Unload (`launchctl bootstrap` / `bootout`)
- Start / Stop / Restart (`kickstart` / `kill SIGTERM`)
- Enable / Disable (launchd overrides database)
- Multi-select for batch operations
- Jobs outside the user domain automatically retry with administrator
  privileges (macOS password prompt) when a direct call fails

**Edit jobs**

- Double-click any job to open its editor window
- Tabbed form: General (label, program, arguments), Schedule (interval,
  calendar, watch paths), I/O & Environment (stdout/stderr, working directory,
  env vars), Advanced (nice, timeouts, umask, user/group, process type, …)
- Raw XML tab for direct plist editing
- Inline validation (missing label, missing/non-executable program, integer
  fields, calendar ranges); unknown plist keys are preserved untouched
- Saving a loaded job automatically reloads it so changes take effect
- Writing to system locations stages via a temp file and installs as root with
  the ownership (`root:wheel`, `0644`) launchd requires

**File operations**

- New Job (⌘N) — creates a plist in `~/Library/LaunchAgents`
- Import an existing plist file
- Duplicate a job (unique label, disabled by default)
- Delete a job (unload + move plist to Trash, root delete fallback)
- Reveal in Finder, open plist in default editor, copy label / plist XML

**Logs**

- View a job's `StandardOutPath` / `StandardErrorPath` tail in-app
- Open log in Console.app or reveal in Finder

## Requirements

- macOS 13 Ventura or later
- Swift toolchain (Xcode or Command Line Tools) — build only; the resulting
  app has no dependencies

## Build & run

```sh
./build.sh
open LaunchdManager.app
```

`build.sh` compiles all Swift sources with `swiftc -O` and assembles a minimal
`LaunchdManager.app` bundle (binary + `Info.plist`).

## How it works

The app is a thin, native front end over `launchctl`:

| Action  | launchctl command                              |
| ------- | ---------------------------------------------- |
| Load    | `bootstrap gui/<uid>\|system <path>`           |
| Unload  | `bootout gui/<uid>\|system <path>`             |
| Start   | `kickstart <domain>/<label>`                   |
| Stop    | `kill SIGTERM <domain>/<label>`                |
| Restart | `kickstart -k <domain>/<label>`                |
| Enable  | `enable <domain>/<label>`                      |
| Disable | `disable <domain>/<label>`                     |
| Status  | `list`, `print <domain>/<label>`, `print-disabled` |

Job plists are read/written with `PropertyListSerialization` (XML format).

## Project structure

```
build.sh                        Build script (swiftc → .app bundle)
Resources/Info.plist            App bundle metadata
Sources/
  LaunchdManagerApp.swift       @main app, menus, keyboard shortcuts
  LaunchdController.swift       Scanning, launchctl actions, file operations
  Shell.swift                   Process runner + admin-privilege escalation
  Model/
    LaunchdService.swift        Job model, domains, derived state
    EditableJob.swift           Form-friendly plist model + validation
  Views/
    ContentView.swift           Main window (sidebar / table / inspector)
    SidebarRow.swift            Sidebar category row
    JobTableView.swift          Job table + context menu
    InspectorView.swift         Selection details, actions, logs
    JobEditorView.swift         Job editor (tabs + raw XML)
    EditorWindowManager.swift   Standalone editor windows
    LogViewerView.swift         Log tail viewer
```

## Limitations

- Apple system jobs (`/System/Library/...`) are protected by SIP — they can be
  viewed, but macOS will refuse to load/unload them; the app surfaces the error.
- Privileged operations (writing to `/Library/LaunchDaemons`, managing the
  `system` domain) trigger a one-time-per-operation macOS password prompt via
  AppleScript (`with administrator privileges`).
- Complex `KeepAlive` dictionaries and array-form `StartCalendarInterval`
  values are preserved but editable only in the Raw XML tab.

## License

MIT — see [LICENSE](LICENSE).
