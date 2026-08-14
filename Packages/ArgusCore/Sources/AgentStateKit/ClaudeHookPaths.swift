import Foundation

/// The on-disk paths of Argus's Claude Code hook scripts, one per event, shared between
/// WorktreeHookManager (which writes the scripts) and ClaudeSettingsPatcher (which points
/// settings.local.json at them).
public struct ClaudeHookPaths: Sendable {
    public let running: URL
    public let done: URL
    public let approval: URL
    public let userPrompt: URL
    public let preCompact: URL
    public let postCompact: URL
    public let postToolUse: URL
    public let sessionEnd: URL

    public init(
        running: URL,
        done: URL,
        approval: URL,
        userPrompt: URL,
        preCompact: URL,
        postCompact: URL,
        postToolUse: URL,
        sessionEnd: URL
    ) {
        self.running = running
        self.done = done
        self.approval = approval
        self.userPrompt = userPrompt
        self.preCompact = preCompact
        self.postCompact = postCompact
        self.postToolUse = postToolUse
        self.sessionEnd = sessionEnd
    }
}
