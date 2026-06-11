import Foundation

/// Writes Codex CLI hook scripts and wires them into Codex's active hook config
/// automatically when a pane is first opened.
enum CodexHookManager {
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
    }

    /// Idempotent: writes the shared hook scripts once and merges kotty's hook
    /// entries into Codex hook config.
    static func install(worktreePath: String) throws {
        let worktreePath = canonicalPath(worktreePath)
        let hooksDir = try kottyHooksDir()
        let eventLogPath = HookIPC.eventLogPath
        let paths = HookPaths(
            running: hooksDir.appendingPathComponent("codex-running.sh"),
            done: hooksDir.appendingPathComponent("codex-done.sh"),
            approval: hooksDir.appendingPathComponent("codex-waiting-approval.sh"),
            userPrompt: hooksDir.appendingPathComponent("codex-user-prompt.sh"),
            preCompact: hooksDir.appendingPathComponent("codex-pre-compact.sh"),
            postCompact: hooksDir.appendingPathComponent("codex-post-compact.sh")
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
        try patchHooksJSON(worktreePath: worktreePath, paths: paths)
        try patchGlobalTrust(worktreePath: worktreePath)
    }

    private static func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
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

    private static func hookScript(state: String, eventLogPath: String) -> String {
        """
        #!/bin/bash
        WORKTREE=$(git rev-parse --show-toplevel 2>/dev/null)
        WORKTREE="${WORKTREE:-$PWD}"
        [ -z "$WORKTREE" ] && exit 0
        EVENT_LOG='\(eventLogPath)'
        printf '{"worktreePath":"%s","state":"\(state)","agent":"codex"}\\n' "$WORKTREE" \\
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

    // MARK: - ~/.codex/config.toml (project trust)

    /// Adds `[projects."<worktreePath>"] trust_level = "trusted"` to the global Codex
    /// config so that hooks registered in the project's .codex/hooks.json execute
    /// without requiring the user to run `/trust` inside Codex CLI.
    private static func patchGlobalTrust(worktreePath: String) throws {
        let configURL: URL
        if let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"], !codexHome.isEmpty {
            configURL = URL(fileURLWithPath: codexHome).appendingPathComponent("config.toml")
        } else {
            configURL = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex/config.toml")
        }
        try FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let existing = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        let escapedPath =
            worktreePath
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let sectionHeader = "[projects.\"\(escapedPath)\"]"
        guard !existing.contains(sectionHeader) else { return }
        var updated = existing.trimmingCharacters(in: .newlines)
        if !updated.isEmpty { updated += "\n\n" }
        updated += "\(sectionHeader)\ntrust_level = \"trusted\"\n"
        try updated.write(to: configURL, atomically: true, encoding: .utf8)
    }

    // MARK: - .codex/hooks.json

    private static func patchHooksJSON(worktreePath: String, paths: HookPaths) throws {
        let codexDir = URL(fileURLWithPath: worktreePath).appendingPathComponent(".codex")
        try FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)
        let hooksURL = codexDir.appendingPathComponent("hooks.json")
        var root = loadJSON(at: hooksURL)
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        hooks["PreToolUse"] = upsertKottyEntry(
            in: hooks["PreToolUse"] as? [[String: Any]] ?? [],
            entry: ["matcher": ".*", "hooks": [commandHook(paths.running)]]
        )
        hooks["Stop"] = upsertKottyEntry(
            in: hooks["Stop"] as? [[String: Any]] ?? [],
            entry: ["matcher": "", "hooks": [commandHook(paths.done)]]
        )
        hooks["PreCompact"] = upsertKottyEntry(
            in: hooks["PreCompact"] as? [[String: Any]] ?? [],
            entry: ["matcher": "", "hooks": [commandHook(paths.preCompact)]]
        )
        hooks["PostCompact"] = upsertKottyEntry(
            in: hooks["PostCompact"] as? [[String: Any]] ?? [],
            entry: ["matcher": "", "hooks": [commandHook(paths.postCompact)]]
        )
        hooks["PermissionRequest"] = upsertKottyEntry(
            in: hooks["PermissionRequest"] as? [[String: Any]] ?? [],
            entry: ["matcher": "", "hooks": [commandHook(paths.approval)]]
        )
        hooks["UserPromptSubmit"] = upsertKottyEntry(
            in: hooks["UserPromptSubmit"] as? [[String: Any]] ?? [],
            entry: ["matcher": "", "hooks": [commandHook(paths.userPrompt)]]
        )
        root["hooks"] = hooks
        try saveJSON(root, to: hooksURL)
    }

    private static func loadJSON(at url: URL) -> [String: Any] {
        guard let data = try? Data(contentsOf: url),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return obj
    }

    private static func quoted(_ path: String) -> String { "\"\(path)\"" }

    private static func commandHook(_ url: URL) -> [String: Any] {
        ["type": "command", "command": quoted(url.path), "async": false]
    }

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

    private static func saveJSON(_ obj: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(
            withJSONObject: obj,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: url, options: .atomic)
    }
}
