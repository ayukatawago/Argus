import Foundation

/// Writes hook scripts to App Support and wires them into a worktree's
/// .claude/settings.local.json automatically when a pane is first opened.
/// The file is gitignored by default, so no repo pollution.
enum WorktreeHookManager {
    enum Failure: Error, LocalizedError {
        case noAppSupport
        var errorDescription: String? { "Cannot locate Application Support directory." }
    }

    private struct HookPaths {
        let running: URL
        let done: URL
        let approval: URL
        let userPrompt: URL
        let preCompact: URL
        let postCompact: URL
        let postToolUse: URL
        let sessionEnd: URL
    }

    static var isFishShell: Bool {
        (ProcessInfo.processInfo.environment["SHELL"] ?? "").hasSuffix("/fish")
    }

    /// Idempotent: writes the shared hook scripts once and merges argus's hook
    /// entries into the worktree's .claude/settings.local.json.
    static func install(worktreePath: String) throws {
        installFishHooksIfNeeded()
        let hooksDir = try argusHooksDir()
        let eventLogPath = HookIPC.eventLogPath
        let paths = HookPaths(
            running: hooksDir.appendingPathComponent("claude-running.sh"),
            done: hooksDir.appendingPathComponent("claude-done.sh"),
            approval: hooksDir.appendingPathComponent("claude-waiting-approval.sh"),
            userPrompt: hooksDir.appendingPathComponent("claude-user-prompt.sh"),
            preCompact: hooksDir.appendingPathComponent("claude-pre-compact.sh"),
            postCompact: hooksDir.appendingPathComponent("claude-post-compact.sh"),
            postToolUse: hooksDir.appendingPathComponent("claude-post-tool-use.sh"),
            sessionEnd: hooksDir.appendingPathComponent("claude-session-end.sh")
        )
        try writeExecutable(at: paths.running, content: hookScript(state: "running", eventLogPath: eventLogPath))
        try writeExecutable(at: paths.done, content: hookScript(state: "done", eventLogPath: eventLogPath))
        try writeExecutable(
            at: paths.approval,
            content: hookScript(state: "waitingForApproval", eventLogPath: eventLogPath)
        )
        try writeExecutable(at: paths.userPrompt, content: hookScript(state: "running", eventLogPath: eventLogPath))
        try writeExecutable(at: paths.preCompact, content: hookScript(state: "running", eventLogPath: eventLogPath))
        try writeExecutable(at: paths.postCompact, content: hookScript(state: "done", eventLogPath: eventLogPath))
        // PostToolUse keeps the timestamp fresh so long-running tools don't trip the staleness monitor.
        try writeExecutable(at: paths.postToolUse, content: hookScript(state: "running", eventLogPath: eventLogPath))
        // SessionEnd fires when the session terminates (e.g. /exit, window close).
        try writeExecutable(at: paths.sessionEnd, content: hookScript(state: "idle", eventLogPath: eventLogPath))
        try patchLocalSettings(worktreePath: worktreePath, paths: paths)
    }

    private static func argusHooksDir() throws -> URL {
        guard
            let support = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first
        else { throw Failure.noAppSupport }
        let dir = support.appendingPathComponent("argus/hooks")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func hookScript(state: String, eventLogPath: String) -> String {
        """
        #!/bin/bash
        WORKTREE=$(git rev-parse --show-toplevel 2>/dev/null)
        WORKTREE="${WORKTREE:-$PWD}"
        [ -z "$WORKTREE" ] && exit 0
        EVENT_LOG='\(eventLogPath)'
        printf '{"worktreePath":"%s","state":"\(state)","agent":"claude"}\\n' "$WORKTREE" \\
            >> "$EVENT_LOG" 2>/dev/null || true
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

    private static func patchLocalSettings(worktreePath: String, paths: HookPaths) throws {
        let claudeDir = URL(fileURLWithPath: worktreePath).appendingPathComponent(".claude")
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        let settingsURL = claudeDir.appendingPathComponent("settings.local.json")
        var settings = loadSettings(at: settingsURL)
        settings["hooks"] = mergedHooks(in: settings, paths: paths)
        try saveSettings(settings, to: settingsURL)
    }

    private static func loadSettings(at url: URL) -> [String: Any] {
        guard let data = try? Data(contentsOf: url),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return obj
    }

    private static func mergedHooks(in settings: [String: Any], paths: HookPaths) -> [String: Any] {
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        hooks["PreToolUse"] = upsertArgusEntry(
            in: hooks["PreToolUse"] as? [[String: Any]] ?? [],
            entry: ["matcher": ".*", "hooks": [["type": "command", "command": quoted(paths.running.path)]]]
        )
        // Stop is a session-level event; "matcher": "" is required even though it's unused.
        hooks["Stop"] = upsertArgusEntry(
            in: hooks["Stop"] as? [[String: Any]] ?? [],
            entry: ["matcher": "", "hooks": [["type": "command", "command": quoted(paths.done.path)]]]
        )
        // StopFailure fires when the turn ends due to an API error — Stop does not fire in this case.
        hooks["StopFailure"] = upsertArgusEntry(
            in: hooks["StopFailure"] as? [[String: Any]] ?? [],
            entry: ["matcher": "", "hooks": [["type": "command", "command": quoted(paths.done.path)]]]
        )
        // PreCompact fires when /compact begins — show running indicator during compaction.
        hooks["PreCompact"] = upsertArgusEntry(
            in: hooks["PreCompact"] as? [[String: Any]] ?? [],
            entry: ["matcher": "", "hooks": [["type": "command", "command": quoted(paths.preCompact.path)]]]
        )
        // PostCompact fires after /compact finishes — Stop does not fire in this case.
        hooks["PostCompact"] = upsertArgusEntry(
            in: hooks["PostCompact"] as? [[String: Any]] ?? [],
            entry: ["matcher": "", "hooks": [["type": "command", "command": quoted(paths.postCompact.path)]]]
        )
        // PermissionRequest fires when Claude Code shows an approval dialog (blocking).
        hooks["PermissionRequest"] = upsertArgusEntry(
            in: hooks["PermissionRequest"] as? [[String: Any]] ?? [],
            entry: ["matcher": "", "hooks": [["type": "command", "command": quoted(paths.approval.path)]]]
        )
        // UserPromptSubmit fires when the user sends a message — transitions to running
        // before PreToolUse so the done/approval indicator clears immediately on reply.
        hooks["UserPromptSubmit"] = upsertArgusEntry(
            in: hooks["UserPromptSubmit"] as? [[String: Any]] ?? [],
            entry: ["matcher": "", "hooks": [["type": "command", "command": quoted(paths.userPrompt.path)]]]
        )
        // PostToolUse refreshes the "running" timestamp so tools that take > 3 min don't
        // trip the staleness monitor that handles missing Stop events on Escape interrupt.
        hooks["PostToolUse"] = upsertArgusEntry(
            in: hooks["PostToolUse"] as? [[String: Any]] ?? [],
            entry: ["matcher": ".*", "hooks": [["type": "command", "command": quoted(paths.postToolUse.path)]]]
        )
        // SessionEnd fires when the claude session terminates (/exit, window close, etc.).
        hooks["SessionEnd"] = upsertArgusEntry(
            in: hooks["SessionEnd"] as? [[String: Any]] ?? [],
            entry: ["matcher": "", "hooks": [["type": "command", "command": quoted(paths.sessionEnd.path)]]]
        )
        return hooks
    }

    private static func quoted(_ path: String) -> String { "\"\(path)\"" }

    private static func upsertArgusEntry(
        in existing: [[String: Any]],
        entry: [String: Any]
    ) -> [[String: Any]] {
        let filtered = existing.filter { item in
            guard let hooksList = item["hooks"] as? [[String: Any]] else { return true }
            return !hooksList.contains { ($0["command"] as? String)?.contains("/argus/hooks/") == true }
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

    // MARK: - Fish shell integration

    nonisolated(unsafe) private static var fishHooksInstalled = false

    private static func installFishHooksIfNeeded() {
        guard !fishHooksInstalled, isFishShell else { return }
        guard let confDir = fishConfDir() else { return }
        try? FileManager.default.createDirectory(at: confDir, withIntermediateDirectories: true)
        let hookFile = confDir.appendingPathComponent("argus.fish")
        let content = fishHookScript(eventLogPath: HookIPC.shellEventLogPath)
        try? content.write(to: hookFile, atomically: true, encoding: .utf8)
        fishHooksInstalled = true
    }

    private static func fishConfDir() -> URL? {
        let base: URL
        if let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            base = URL(fileURLWithPath: xdg)
        } else {
            base = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".config")
        }
        return base.appendingPathComponent("fish/conf.d")
    }

    private static func fishHookScript(eventLogPath: String) -> String {
        """
        # Argus shell integration — auto-generated, do not edit.
        set -g __argus_log '\(eventLogPath)'

        function __argus_preexec --on-event fish_preexec
            set -q TMUX; or return 0
            string match -q 'argus-s-*' (tmux display-message -p '#S' 2>/dev/null); or return 0
            set -l worktree (git rev-parse --show-toplevel 2>/dev/null)
            test -n "$worktree"; or return 0
            printf '{"worktreePath":"%s","state":"running","agent":"shell"}\\n' \\
                "$worktree" >> $__argus_log 2>/dev/null; or true
        end

        function __argus_postexec --on-event fish_postexec
            set -q TMUX; or return 0
            string match -q 'argus-s-*' (tmux display-message -p '#S' 2>/dev/null); or return 0
            set -l worktree (git rev-parse --show-toplevel 2>/dev/null)
            test -n "$worktree"; or return 0
            printf '{"worktreePath":"%s","state":"idle","agent":"shell"}\\n' \\
                "$worktree" >> $__argus_log 2>/dev/null; or true
        end
        """
    }
}
