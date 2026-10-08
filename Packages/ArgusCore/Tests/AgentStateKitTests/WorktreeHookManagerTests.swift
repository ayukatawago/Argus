import ArgusSupport
import Foundation
import Testing

@testable import AgentStateKit

@Suite("WorktreeHookManager", .serialized)
struct WorktreeHookManagerTests {
    private func makeDir(_ name: String = "hook-mgr") throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// `ClaudeSettingsPatcher` recognises its own entries by `/argus/hooks/` in the command path, so
    /// a test hooks directory must contain that segment to exercise the real upsert behaviour.
    private func makeHooksDir() throws -> URL {
        let dir = try makeDir("hooks").appendingPathComponent("argus/hooks")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("install writes an executable script and patches settings.local.json in a temp worktree")
    func installWritesScriptAndSettings() throws {
        let worktree = try makeDir()
        let hooks = try makeHooksDir()
        defer {
            try? FileManager.default.removeItem(at: worktree)
            try? FileManager.default.removeItem(at: hooks.deletingLastPathComponent().deletingLastPathComponent())
        }
        try WorktreeHookManager.install(worktreePath: worktree.path, hooksDirectory: hooks, installFishHooks: false)

        let script = hooks.appendingPathComponent("claude-waiting-approval.sh")
        #expect(FileManager.default.isExecutableFile(atPath: script.path))
        let settingsURL = worktree.appendingPathComponent(".claude/settings.local.json")
        let settings = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL)) as? [String: Any])
        let hooksObject = try #require(settings["hooks"] as? [String: Any])
        #expect(hooksObject["PermissionRequest"] != nil)
    }

    @Test("install is idempotent: a second run leaves identical settings")
    func idempotent() throws {
        let worktree = try makeDir()
        let hooks = try makeHooksDir()
        defer {
            try? FileManager.default.removeItem(at: worktree)
            try? FileManager.default.removeItem(at: hooks.deletingLastPathComponent().deletingLastPathComponent())
        }
        try WorktreeHookManager.install(worktreePath: worktree.path, hooksDirectory: hooks, installFishHooks: false)
        let settingsURL = worktree.appendingPathComponent(".claude/settings.local.json")
        let first = try Data(contentsOf: settingsURL)
        try WorktreeHookManager.install(worktreePath: worktree.path, hooksDirectory: hooks, installFishHooks: false)
        #expect(try Data(contentsOf: settingsURL) == first)
    }

    @Test("an unparseable settings.local.json is backed up, not silently destroyed")
    func unparseableSettingsBackedUp() throws {
        let worktree = try makeDir()
        let hooks = try makeHooksDir()
        defer {
            try? FileManager.default.removeItem(at: worktree)
            try? FileManager.default.removeItem(at: hooks.deletingLastPathComponent().deletingLastPathComponent())
        }
        let claudeDir = worktree.appendingPathComponent(".claude")
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        let original = Data("{ \"permissions\": {}, // user comment\n}".utf8)
        try original.write(to: claudeDir.appendingPathComponent("settings.local.json"))

        try WorktreeHookManager.install(worktreePath: worktree.path, hooksDirectory: hooks, installFishHooks: false)

        let backups = try FileManager.default.contentsOfDirectory(atPath: claudeDir.path).filter {
            $0.contains(".corrupt-")
        }
        let backup = try #require(backups.first)
        #expect(try Data(contentsOf: claudeDir.appendingPathComponent(backup)) == original)
    }

    @Test("the hook script emits valid JSON for a worktree path containing quotes and backslashes")
    func scriptEscapesPath() async throws {
        let base = try makeDir()
        defer { try? FileManager.default.removeItem(at: base) }
        let weird = base.appendingPathComponent(#"we"ird\dir"#)
        try FileManager.default.createDirectory(at: weird, withIntermediateDirectories: true)
        let log = base.appendingPathComponent("events.jsonl")
        let scriptURL = base.appendingPathComponent("hook.sh")
        try WorktreeHookManager.hookScript(state: "waitingForApproval", eventLogPath: log.path)
            .write(to: scriptURL, atomically: true, encoding: .utf8)

        let result = await ProcessRunner.run("/bin/bash", [scriptURL.path], currentDirectory: weird.path)
        #expect(result.succeeded)

        let text = try String(contentsOf: log, encoding: .utf8)
        let line = try #require(text.split(separator: "\n").first)
        let parsed = try JSONSerialization.jsonObject(with: Data(line.utf8))
        let object = try #require(parsed as? [String: String])
        // `$PWD` resolves symlinks on macOS (/var -> /private/var), so compare the final component.
        #expect(object["worktreePath"]?.hasSuffix(#"we"ird\dir"#) == true)
        #expect(object["state"] == "waitingForApproval")
        #expect(object["agent"] == "claude")
    }
}
