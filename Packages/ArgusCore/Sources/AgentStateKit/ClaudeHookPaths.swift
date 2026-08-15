import Foundation

/// The on-disk path of Argus's one remaining Claude Code hook script, shared between
/// WorktreeHookManager (which writes the script) and ClaudeSettingsPatcher (which points
/// settings.local.json at it). Every other agent-state transition is now inferred by
/// ClaudeTranscriptWatcher from the session transcript; PermissionRequest is kept as a hook
/// because nothing is written to the transcript when a permission dialog opens.
public struct ClaudeHookPaths: Sendable {
    public let approval: URL

    public init(approval: URL) {
        self.approval = approval
    }
}
