import Foundation

/// The user's configured login shell, queried via directory services (`dscl`) — more reliable
/// than `$SHELL`, which may be inherited from a parent process running a different shell (e.g. a
/// terminal with zsh active while the user's actual login shell is fish).
///
/// Deliberately synchronous, not routed through `ProcessRunner`: every call site (pane creation,
/// hook install) is itself synchronous, and making the lookup async would force an async refactor
/// of unrelated code just to reach a couple of duplicated `dscl` invocations.
public enum LoginShell {
    public static var current: String {
        parse(dsclOutput: runDscl(), fallback: fallbackShell())
    }

    private static func runDscl() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/dscl")
        process.arguments = [".", "-read", "/Users/\(NSUserName())", "UserShell"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return "" }
        process.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    /// Parses `dscl -read <user> UserShell`'s `"UserShell: /bin/zsh"` output, falling back to
    /// `fallback` when the output is empty or doesn't contain the expected "key: value" shape.
    public static func parse(dsclOutput: String, fallback: String) -> String {
        let shell =
            dsclOutput.components(separatedBy: ": ").last?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return shell.isEmpty ? fallback : shell
    }

    public static func fallbackShell() -> String {
        ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    }
}
