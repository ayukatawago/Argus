import Foundation
import Testing

@testable import AgentStateKit

@Suite("ClaudeSettingsPatcher")
struct ClaudeSettingsPatcherTests {
    private static let allEvents = [
        "PreToolUse", "Stop", "StopFailure", "PreCompact", "PostCompact",
        "PermissionRequest", "UserPromptSubmit", "PostToolUse", "SessionEnd",
    ]

    private static func makePaths(root: String = "/App Support/argus/hooks") -> ClaudeHookPaths {
        ClaudeHookPaths(
            running: URL(fileURLWithPath: "\(root)/claude-running.sh"),
            done: URL(fileURLWithPath: "\(root)/claude-done.sh"),
            approval: URL(fileURLWithPath: "\(root)/claude-waiting-approval.sh"),
            userPrompt: URL(fileURLWithPath: "\(root)/claude-user-prompt.sh"),
            preCompact: URL(fileURLWithPath: "\(root)/claude-pre-compact.sh"),
            postCompact: URL(fileURLWithPath: "\(root)/claude-post-compact.sh"),
            postToolUse: URL(fileURLWithPath: "\(root)/claude-post-tool-use.sh"),
            sessionEnd: URL(fileURLWithPath: "\(root)/claude-session-end.sh")
        )
    }

    @Test("all nine hook events are present after merging into an empty settings dict")
    func allNineEventsPresent() {
        let merged = ClaudeSettingsPatcher.merged(into: [:], paths: Self.makePaths())
        let hooks = merged["hooks"] as? [String: Any]
        #expect(hooks?.keys.sorted() == Self.allEvents.sorted())
    }

    @Test("a non-Argus hook entry for the same event survives the merge")
    func nonArgusEntrySurvives() {
        let otherToolEntry: [String: Any] = [
            "matcher": ".*",
            "hooks": [["type": "command", "command": "\"/some/other/tool.sh\""]],
        ]
        let existing: [String: Any] = ["hooks": ["PreToolUse": [otherToolEntry]]]
        let merged = ClaudeSettingsPatcher.merged(into: existing, paths: Self.makePaths())
        let preToolUse = (merged["hooks"] as? [String: Any])?["PreToolUse"] as? [[String: Any]]
        #expect(preToolUse?.count == 2)
        let commands = preToolUse?.compactMap { entry -> String? in
            let hooksList = entry["hooks"] as? [[String: Any]]
            return hooksList?.first?["command"] as? String
        }
        #expect(commands?.contains("\"/some/other/tool.sh\"") == true)
    }

    @Test("re-running replaces the previous Argus entry instead of duplicating it")
    func rerunningReplacesStaleEntry() {
        let first = ClaudeSettingsPatcher.merged(into: [:], paths: Self.makePaths(root: "/old/argus/hooks"))
        let second = ClaudeSettingsPatcher.merged(into: first, paths: Self.makePaths(root: "/new/argus/hooks"))

        let preToolUse = (second["hooks"] as? [String: Any])?["PreToolUse"] as? [[String: Any]]
        #expect(preToolUse?.count == 1)
        let command = (preToolUse?.first?["hooks"] as? [[String: Any]])?.first?["command"] as? String
        #expect(command == "\"/new/argus/hooks/claude-running.sh\"")
    }

    @Test("unrelated top-level keys are left untouched")
    func unrelatedTopLevelKeysUntouched() {
        let existing: [String: Any] = ["permissions": ["allow": ["Bash(npm run *)"]]]
        let merged = ClaudeSettingsPatcher.merged(into: existing, paths: Self.makePaths())
        #expect(merged["permissions"] != nil)
        #expect(merged["hooks"] != nil)
    }

    @Test("a hook event with no Argus entry yet still gets exactly one after merging")
    func freshEventGetsExactlyOneEntry() {
        let merged = ClaudeSettingsPatcher.merged(into: [:], paths: Self.makePaths())
        let stop = (merged["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]]
        #expect(stop?.count == 1)
    }
}
