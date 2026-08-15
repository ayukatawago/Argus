import Foundation
import Testing

@testable import AgentStateKit

@Suite("ClaudeSettingsPatcher")
struct ClaudeSettingsPatcherTests {
    private static let obsoleteEvents = [
        "PreToolUse", "Stop", "StopFailure", "PreCompact", "PostCompact",
        "UserPromptSubmit", "PostToolUse", "SessionEnd",
    ]

    private static func makePaths(root: String = "/App Support/argus/hooks") -> ClaudeHookPaths {
        ClaudeHookPaths(approval: URL(fileURLWithPath: "\(root)/claude-waiting-approval.sh"))
    }

    private static func argusEntry(command: String) -> [String: Any] {
        ["matcher": "", "hooks": [["type": "command", "command": "\"\(command)\""]]]
    }

    @Test("merging into an empty settings dict installs exactly PermissionRequest")
    func onlyPermissionRequestPresent() {
        let merged = ClaudeSettingsPatcher.merged(into: [:], paths: Self.makePaths())
        let hooks = merged["hooks"] as? [String: Any]
        #expect(hooks?.keys.sorted() == ["PermissionRequest"])
    }

    @Test("a non-Argus hook entry for PermissionRequest survives the merge")
    func nonArgusEntrySurvives() {
        let otherToolEntry: [String: Any] = [
            "matcher": ".*",
            "hooks": [["type": "command", "command": "\"/some/other/tool.sh\""]],
        ]
        let existing: [String: Any] = ["hooks": ["PermissionRequest": [otherToolEntry]]]
        let merged = ClaudeSettingsPatcher.merged(into: existing, paths: Self.makePaths())
        let entries = (merged["hooks"] as? [String: Any])?["PermissionRequest"] as? [[String: Any]]
        #expect(entries?.count == 2)
        let commands = entries?.compactMap { entry -> String? in
            let hooksList = entry["hooks"] as? [[String: Any]]
            return hooksList?.first?["command"] as? String
        }
        #expect(commands?.contains("\"/some/other/tool.sh\"") == true)
    }

    @Test("re-running replaces the previous Argus entry instead of duplicating it")
    func rerunningReplacesStaleEntry() {
        let first = ClaudeSettingsPatcher.merged(into: [:], paths: Self.makePaths(root: "/old/argus/hooks"))
        let second = ClaudeSettingsPatcher.merged(into: first, paths: Self.makePaths(root: "/new/argus/hooks"))

        let entries = (second["hooks"] as? [String: Any])?["PermissionRequest"] as? [[String: Any]]
        #expect(entries?.count == 1)
        let command = (entries?.first?["hooks"] as? [[String: Any]])?.first?["command"] as? String
        #expect(command == "\"/new/argus/hooks/claude-waiting-approval.sh\"")
    }

    @Test("unrelated top-level keys are left untouched")
    func unrelatedTopLevelKeysUntouched() {
        let existing: [String: Any] = ["permissions": ["allow": ["Bash(npm run *)"]]]
        let merged = ClaudeSettingsPatcher.merged(into: existing, paths: Self.makePaths())
        #expect(merged["permissions"] != nil)
        #expect(merged["hooks"] != nil)
    }

    @Test("PermissionRequest has exactly one entry after merging into an empty settings dict")
    func freshEventGetsExactlyOneEntry() {
        let merged = ClaudeSettingsPatcher.merged(into: [:], paths: Self.makePaths())
        let entries = (merged["hooks"] as? [String: Any])?["PermissionRequest"] as? [[String: Any]]
        #expect(entries?.count == 1)
    }

    @Test("migration: all eight retired Argus events are pruned, and a user's own hook on one survives")
    func migrationPrunesRetiredEventsButKeepsUserHooks() {
        var existingHooks: [String: Any] = [:]
        for event in Self.obsoleteEvents {
            existingHooks[event] = [
                Self.argusEntry(command: "/App Support/argus/hooks/claude-running.sh")
            ]
        }
        // A user's own PreToolUse hook, alongside Argus's now-retired one, must survive.
        existingHooks["PreToolUse"] = [
            Self.argusEntry(command: "/App Support/argus/hooks/claude-running.sh"),
            ["matcher": ".*", "hooks": [["type": "command", "command": "\"/my/own/hook.sh\""]]],
        ]
        let existing: [String: Any] = ["hooks": existingHooks]

        let merged = ClaudeSettingsPatcher.merged(into: existing, paths: Self.makePaths())
        let hooks = merged["hooks"] as? [String: Any] ?? [:]

        // Every retired event except PreToolUse (which still has the surviving user hook) is
        // dropped entirely rather than left behind as an empty array.
        for event in Self.obsoleteEvents where event != "PreToolUse" {
            #expect(hooks[event] == nil, "expected \(event) to be pruned")
        }
        let preToolUse = hooks["PreToolUse"] as? [[String: Any]]
        #expect(preToolUse?.count == 1)
        let command = (preToolUse?.first?["hooks"] as? [[String: Any]])?.first?["command"] as? String
        #expect(command == "\"/my/own/hook.sh\"")

        #expect((hooks["PermissionRequest"] as? [[String: Any]])?.count == 1)
    }
}
