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
        try patchUserConfigTOML(paths: paths)
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

    // MARK: - ~/.codex/config.toml

    private static let configBlockStart = "# kotty-codex-hooks:start"
    private static let configBlockEnd = "# kotty-codex-hooks:end"

    private static func patchUserConfigTOML(paths: HookPaths) throws {
        let configURL = try codexConfigURL()
        try FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let existing = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        if let existingBlock = markedBlock(in: existing), containsExpectedHooks(existingBlock, paths: paths) {
            try ensureHooksFeatureEnabled(configURL: configURL)
            return
        }
        let withoutKottyBlock = removeMarkedBlock(from: existing)
        let block = "\(configBlockStart)\n\(hooksTOML(paths: paths))\n\(configBlockEnd)\n"
        let updated = insertTopLevelBlock(block, into: withoutKottyBlock)
        try updated.write(to: configURL, atomically: true, encoding: .utf8)
        try ensureHooksFeatureEnabled(configURL: configURL)
    }

    private static func codexConfigURL() throws -> URL {
        if let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"], !codexHome.isEmpty {
            return URL(fileURLWithPath: codexHome).appendingPathComponent("config.toml")
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/config.toml")
    }

    private static func markedBlock(in content: String) -> String? {
        guard
            let start = content.range(of: configBlockStart),
            let end = content.range(of: configBlockEnd, range: start.upperBound..<content.endIndex)
        else { return nil }
        return String(content[start.lowerBound..<end.upperBound])
    }

    private static func containsExpectedHooks(_ block: String, paths: HookPaths) -> Bool {
        [
            paths.running,
            paths.done,
            paths.approval,
            paths.userPrompt,
            paths.preCompact,
            paths.postCompact,
        ].allSatisfy { block.contains(tomlString(quoted($0.path))) }
    }

    private static func removeMarkedBlock(from content: String) -> String {
        guard
            let start = content.range(of: configBlockStart),
            let end = content.range(of: configBlockEnd, range: start.upperBound..<content.endIndex)
        else { return content }

        var removal = start.lowerBound..<end.upperBound
        if end.upperBound < content.endIndex, content[end.upperBound] == "\n" {
            removal = start.lowerBound..<content.index(after: end.upperBound)
        }
        var result = content
        result.removeSubrange(removal)
        return result
    }

    private static func insertTopLevelBlock(_ block: String, into content: String) -> String {
        var lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let insertionIndex =
            lines.firstIndex { line in
                line.trimmingCharacters(in: .whitespaces).hasPrefix("[")
            } ?? lines.count

        var blockLines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if blockLines.last == "" { blockLines.removeLast() }
        if insertionIndex > 0, lines[insertionIndex - 1].isEmpty == false {
            blockLines.insert("", at: 0)
        }
        if insertionIndex < lines.count, blockLines.last?.isEmpty == false {
            blockLines.append("")
        }
        lines.insert(contentsOf: blockLines, at: insertionIndex)
        return lines.joined(separator: "\n").trimmingCharacters(in: .newlines) + "\n"
    }

    private static func ensureHooksFeatureEnabled(configURL: URL) throws {
        let content = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var inFeatures = false
        var sawFeatures = false
        var sawHooks = false
        var output: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") {
                if inFeatures, !sawHooks {
                    output.append("hooks = true")
                    sawHooks = true
                }
                inFeatures = trimmed == "[features]"
                sawFeatures = sawFeatures || inFeatures
            }

            if inFeatures && (trimmed.hasPrefix("hooks ") || trimmed.hasPrefix("hooks=")) {
                output.append("hooks = true")
                sawHooks = true
            } else {
                output.append(line)
            }
        }

        if inFeatures, !sawHooks {
            output.append("hooks = true")
        } else if !sawFeatures {
            if output.last?.isEmpty == false { output.append("") }
            output.append("[features]")
            output.append("hooks = true")
        }

        let updated = output.joined(separator: "\n").trimmingCharacters(in: .newlines) + "\n"
        if updated != content {
            try updated.write(to: configURL, atomically: true, encoding: .utf8)
        }
    }

    private static func hooksTOML(paths: HookPaths) -> String {
        let emptyEvents = [
            "PostToolUse = []",
            "SessionStart = []",
            "SubagentStart = []",
            "SubagentStop = []",
        ]
        let configuredEvents = [
            tomlEvent("PreToolUse", matcher: ".*", command: paths.running.path),
            tomlEvent("PermissionRequest", matcher: "", command: paths.approval.path),
            tomlEvent("PreCompact", matcher: "", command: paths.preCompact.path),
            tomlEvent("PostCompact", matcher: "", command: paths.postCompact.path),
            tomlEvent("UserPromptSubmit", matcher: "", command: paths.userPrompt.path),
            tomlEvent("Stop", matcher: "", command: paths.done.path),
        ]
        let events = configuredEvents + emptyEvents
        return (["[hooks]"] + events + ["", "[hooks.state]"]).joined(separator: "\n")
    }

    private static func tomlEvent(_ name: String, matcher: String, command: String) -> String {
        "\(name) = [{ matcher = \(tomlString(matcher)), hooks = [\(tomlCommand(command))] }]"
    }

    private static func tomlCommand(_ command: String) -> String {
        "{ type = \"command\", command = \(tomlString(quoted(command))), async = false }"
    }

    private static func tomlString(_ value: String) -> String {
        let escaped =
            value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
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
