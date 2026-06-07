import Foundation

/// Writes hook scripts into App Support and patches ~/.claude/settings.json.
/// Run once via the "Install Claude Code Hooks" menu item.
enum HookInstaller {
    enum Failure: Error, LocalizedError {
        case noAppSupport
        var errorDescription: String? { "Cannot locate Application Support directory." }
    }

    static func install() throws {
        let hooksDir = try kottyHooksDir()
        let socketPath = HookIPC.socketPath
        let runningURL = hooksDir.appendingPathComponent("claude-running.sh")
        let doneURL = hooksDir.appendingPathComponent("claude-done.sh")
        try writeExecutable(at: runningURL, content: hookScript(state: "running", socketPath: socketPath))
        try writeExecutable(at: doneURL, content: hookScript(state: "done", socketPath: socketPath))
        try patchClaudeSettings(running: runningURL.path, done: doneURL.path)
    }

    private static func kottyHooksDir() throws -> URL {
        guard
            let support = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first
        else { throw Failure.noAppSupport }
        let dir = support.appendingPathComponent("kotty/hooks")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func hookScript(state: String, socketPath: String) -> String {
        """
        #!/bin/bash
        WORKTREE=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
        [ -z "$WORKTREE" ] && exit 0
        SOCK='\(socketPath)'
        [ -S "$SOCK" ] || exit 0
        printf '{"worktreePath":"%s","state":"\(state)"}\\n' "$WORKTREE" \\
            | nc -w 1 -U "$SOCK" 2>/dev/null || true
        """
    }

    private static func writeExecutable(at url: URL, content: String) throws {
        try content.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: url.path
        )
    }

    // MARK: - ~/.claude/settings.json patching

    private static func patchClaudeSettings(running: String, done: String) throws {
        let url = claudeSettingsURL()
        var settings = loadSettings(at: url)
        settings["hooks"] = mergedHooks(in: settings, running: running, done: done)
        try saveSettings(settings, to: url)
    }

    private static func claudeSettingsURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    private static func loadSettings(at url: URL) -> [String: Any] {
        guard let data = try? Data(contentsOf: url),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return obj
    }

    private static func mergedHooks(
        in settings: [String: Any],
        running: String,
        done: String
    ) -> [String: Any] {
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        hooks["PreToolUse"] = [
            ["matcher": ".*", "hooks": [["type": "command", "command": running]]]
        ]
        hooks["Stop"] = [
            ["matcher": ".*", "hooks": [["type": "command", "command": done]]]
        ]
        return hooks
    }

    private static func saveSettings(_ settings: [String: Any], to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: url, options: .atomic)
    }
}
