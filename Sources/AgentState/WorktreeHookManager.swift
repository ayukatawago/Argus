import Foundation

/// Writes hook scripts to App Support and wires them into a worktree's
/// .claude/settings.local.json automatically when a pane is first opened.
/// The file is gitignored by default, so no repo pollution.
enum WorktreeHookManager {
    enum Failure: Error, LocalizedError {
        case noAppSupport
        var errorDescription: String? { "Cannot locate Application Support directory." }
    }

    /// Idempotent: writes the shared hook scripts once and merges kotty's hook
    /// entries into the worktree's .claude/settings.local.json.
    static func install(worktreePath: String) throws {
        let hooksDir = try kottyHooksDir()
        let socketPath = HookIPC.socketPath
        let runningURL = hooksDir.appendingPathComponent("claude-running.sh")
        let doneURL = hooksDir.appendingPathComponent("claude-done.sh")
        let approvalURL = hooksDir.appendingPathComponent("claude-waiting-approval.sh")
        let userPromptURL = hooksDir.appendingPathComponent("claude-user-prompt.sh")
        let preCompactURL = hooksDir.appendingPathComponent("claude-pre-compact.sh")
        let postCompactURL = hooksDir.appendingPathComponent("claude-post-compact.sh")
        try writeExecutable(at: runningURL, content: hookScript(state: "running", socketPath: socketPath))
        try writeExecutable(at: doneURL, content: hookScript(state: "done", socketPath: socketPath))
        try writeExecutable(at: approvalURL, content: hookScript(state: "waitingForApproval", socketPath: socketPath))
        try writeExecutable(at: userPromptURL, content: hookScript(state: "running", socketPath: socketPath))
        try writeExecutable(at: preCompactURL, content: hookScript(state: "running", socketPath: socketPath))
        try writeExecutable(at: postCompactURL, content: hookScript(state: "done", socketPath: socketPath))
        try patchLocalSettings(
            worktreePath: worktreePath,
            running: runningURL.path,
            done: doneURL.path,
            approval: approvalURL.path,
            userPrompt: userPromptURL.path,
            preCompact: preCompactURL.path,
            postCompact: postCompactURL.path
        )
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

    // MARK: - .claude/settings.local.json

    private static func patchLocalSettings(
        worktreePath: String,
        running: String,
        done: String,
        approval: String,
        userPrompt: String,
        preCompact: String,
        postCompact: String
    ) throws {
        let claudeDir = URL(fileURLWithPath: worktreePath).appendingPathComponent(".claude")
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        let settingsURL = claudeDir.appendingPathComponent("settings.local.json")
        var settings = loadSettings(at: settingsURL)
        settings["hooks"] = mergedHooks(
            in: settings, running: running, done: done,
            approval: approval, userPrompt: userPrompt,
            preCompact: preCompact, postCompact: postCompact
        )
        try saveSettings(settings, to: settingsURL)
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
        done: String,
        approval: String,
        userPrompt: String,
        preCompact: String,
        postCompact: String
    ) -> [String: Any] {
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        hooks["PreToolUse"] = upsertKottyEntry(
            in: hooks["PreToolUse"] as? [[String: Any]] ?? [],
            entry: ["matcher": ".*", "hooks": [["type": "command", "command": quoted(running)]]]
        )
        // Stop is a session-level event; "matcher": "" is required even though it's unused.
        hooks["Stop"] = upsertKottyEntry(
            in: hooks["Stop"] as? [[String: Any]] ?? [],
            entry: ["matcher": "", "hooks": [["type": "command", "command": quoted(done)]]]
        )
        // PreCompact fires when /compact begins — show running indicator during compaction.
        hooks["PreCompact"] = upsertKottyEntry(
            in: hooks["PreCompact"] as? [[String: Any]] ?? [],
            entry: ["matcher": "", "hooks": [["type": "command", "command": quoted(preCompact)]]]
        )
        // PostCompact fires after /compact finishes — Stop does not fire in this case.
        hooks["PostCompact"] = upsertKottyEntry(
            in: hooks["PostCompact"] as? [[String: Any]] ?? [],
            entry: ["matcher": "", "hooks": [["type": "command", "command": quoted(postCompact)]]]
        )
        // PermissionRequest fires when Claude Code shows an approval dialog (blocking).
        hooks["PermissionRequest"] = upsertKottyEntry(
            in: hooks["PermissionRequest"] as? [[String: Any]] ?? [],
            entry: ["matcher": "", "hooks": [["type": "command", "command": quoted(approval)]]]
        )
        // UserPromptSubmit fires when the user sends a message — transitions to running
        // before PreToolUse so the done/approval indicator clears immediately on reply.
        hooks["UserPromptSubmit"] = upsertKottyEntry(
            in: hooks["UserPromptSubmit"] as? [[String: Any]] ?? [],
            entry: ["matcher": "", "hooks": [["type": "command", "command": quoted(userPrompt)]]]
        )
        return hooks
    }

    private static func quoted(_ path: String) -> String { "\"\(path)\"" }

    private static func upsertKottyEntry(
        in existing: [[String: Any]],
        entry: [String: Any]
    ) -> [[String: Any]] {
        let filtered = existing.filter { item in
            guard let hooksList = item["hooks"] as? [[String: Any]] else { return true }
            return !hooksList.contains { ($0["command"] as? String)?.contains("/kotty/hooks/") == true }
        }
        return filtered + [entry]
    }

    private static func saveSettings(_ settings: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: url, options: .atomic)
    }
}
