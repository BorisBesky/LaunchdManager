import Foundation

struct ShellError: Error, LocalizedError {
    let command: String
    let exitCode: Int32
    let output: String

    var errorDescription: String? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Command failed with exit code \(exitCode)" : trimmed
    }
}

enum Shell {
    /// Runs a process and returns its combined stdout/stderr. Throws on non-zero exit.
    @discardableResult
    static func run(_ launchPath: String, _ arguments: [String]) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            throw ShellError(command: launchPath, exitCode: -1, output: error.localizedDescription)
        }
        // Read before waiting to avoid pipe-buffer deadlock on large output.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw ShellError(
                command: ([launchPath] + arguments).joined(separator: " "),
                exitCode: process.terminationStatus,
                output: output
            )
        }
        return output
    }

    /// Runs a shell command as root via a macOS password prompt (AppleScript).
    @discardableResult
    static func runAdmin(_ command: String) throws -> String {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return try run(
            "/usr/bin/osascript",
            ["-e", "do shell script \"\(escaped)\" with administrator privileges"]
        )
    }

    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
