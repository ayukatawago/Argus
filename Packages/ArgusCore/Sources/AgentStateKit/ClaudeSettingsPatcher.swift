import Foundation

/// Merges Argus's Claude Code hook entries into a worktree's `.claude/settings.local.json`.
public enum ClaudeSettingsPatcher {
    /// Returns `settings` with its `"hooks"` key merged against Argus's nine hook events.
    /// Idempotent: re-running replaces the previous Argus entry for each event (identified by the
    /// command path containing `/argus/hooks/`) instead of accumulating duplicates. Non-Argus
    /// hook entries for the same event, and unrelated top-level keys, are left untouched.
    public static func merged(into settings: [String: Any], paths: ClaudeHookPaths) -> [String: Any] {
        var settings = settings
        settings["hooks"] = mergedHooks(in: settings, paths: paths)
        return settings
    }

    private static func mergedHooks(in settings: [String: Any], paths: ClaudeHookPaths) -> [String: Any] {
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
}
