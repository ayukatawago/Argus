import Foundation

/// Merges Argus's one remaining Claude Code hook entry (PermissionRequest) into a worktree's
/// `.claude/settings.local.json`, and prunes the eight now-obsolete Argus entries left over by
/// older Argus versions (running/done/etc. state is now inferred from the transcript by
/// ClaudeTranscriptWatcher instead).
public enum ClaudeSettingsPatcher {
    /// Events Argus used to install hooks for. Still pruned on every merge so upgraded worktrees
    /// don't keep firing dead scripts that append to the (also retired) hook event log.
    private static let obsoleteEvents = [
        "PreToolUse", "Stop", "StopFailure", "PreCompact", "PostCompact",
        "UserPromptSubmit", "PostToolUse", "SessionEnd",
    ]

    /// Returns `settings` with its `"hooks"` key merged against Argus's PermissionRequest hook.
    /// Idempotent: re-running replaces the previous Argus entry (identified by the command path
    /// containing `/argus/hooks/`) instead of accumulating duplicates. Non-Argus hook entries for
    /// the same event, and unrelated top-level keys, are left untouched.
    public static func merged(into settings: [String: Any], paths: ClaudeHookPaths) -> [String: Any] {
        var settings = settings
        settings["hooks"] = mergedHooks(in: settings, paths: paths)
        return settings
    }

    private static func mergedHooks(in settings: [String: Any], paths: ClaudeHookPaths) -> [String: Any] {
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        // PermissionRequest fires when Claude Code shows an approval dialog (blocking). Nothing
        // is written to the transcript while the dialog is open, so this is the one state the
        // transcript watcher cannot infer — hence the one hook Argus still installs.
        hooks["PermissionRequest"] = upsertArgusEntry(
            in: hooks["PermissionRequest"] as? [[String: Any]] ?? [],
            entry: ["matcher": "", "hooks": [["type": "command", "command": quoted(paths.approval.path)]]]
        )
        for event in obsoleteEvents {
            guard let existing = hooks[event] as? [[String: Any]] else { continue }
            let pruned = pruneArgusEntries(from: existing)
            if pruned.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = pruned
            }
        }
        return hooks
    }

    private static func quoted(_ path: String) -> String { "\"\(path)\"" }

    private static func isArgusEntry(_ item: [String: Any]) -> Bool {
        guard let hooksList = item["hooks"] as? [[String: Any]] else { return false }
        return hooksList.contains { ($0["command"] as? String)?.contains("/argus/hooks/") == true }
    }

    private static func upsertArgusEntry(
        in existing: [[String: Any]],
        entry: [String: Any]
    ) -> [[String: Any]] {
        pruneArgusEntries(from: existing) + [entry]
    }

    private static func pruneArgusEntries(from existing: [[String: Any]]) -> [[String: Any]] {
        existing.filter { !isArgusEntry($0) }
    }
}
