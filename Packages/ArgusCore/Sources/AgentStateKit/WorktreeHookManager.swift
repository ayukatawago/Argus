import ArgusSupport
import Foundation

/// Writes hook scripts to App Support and wires them into a worktree's
/// .claude/settings.local.json automatically when a pane is first opened.
/// The file is gitignored by default, so no repo pollution.
public enum WorktreeHookManager {
    public enum Failure: Error, LocalizedError {
        case noAppSupport
        public var errorDescription: String? { "Cannot locate Application Support directory." }
    }

    public static var isFishShell: Bool {
        LoginShell.current.hasSuffix("/fish")
    }

    /// Scripts an older Argus version wrote for hook events that are now inferred from the
    /// transcript by ClaudeTranscriptWatcher instead. Removed on install so upgraded machines
    /// don't keep dead scripts around (harmless since ClaudeSettingsPatcher no longer references
    /// them, but they'd otherwise linger forever and keep appending to the retired event log).
    private static let obsoleteScriptNames = [
        "claude-running.sh", "claude-done.sh", "claude-user-prompt.sh", "claude-pre-compact.sh",
        "claude-post-compact.sh", "claude-post-tool-use.sh", "claude-session-end.sh",
    ]

    /// Idempotent: writes the one remaining hook script and merges argus's hook
    /// entry into the worktree's .claude/settings.local.json.
    ///
    /// - Parameters:
    ///   - hooksDirectory: where the script is written; defaults to `~/Library/Application
    ///     Support/argus/hooks`. Injectable so tests never touch the real one.
    ///   - installFishHooks: also (once per process) install the fish shell-busy hooks. Tests pass
    ///     `false` so they don't write the real `~/.config/fish`.
    public static func install(
        worktreePath: String, hooksDirectory: URL? = nil, installFishHooks: Bool = true
    ) throws {
        if installFishHooks { installFishHooksIfNeeded() }
        let hooksDir = try hooksDirectory.map(ensureDirectory) ?? argusHooksDir()
        let eventLogPath = HookIPC.eventLogPath
        let paths = ClaudeHookPaths(approval: hooksDir.appendingPathComponent("claude-waiting-approval.sh"))
        try writeExecutable(
            at: paths.approval,
            content: hookScript(state: "waitingForApproval", eventLogPath: eventLogPath)
        )
        removeObsoleteScripts(in: hooksDir)
        try patchLocalSettings(worktreePath: worktreePath, paths: paths)
    }

    private static func removeObsoleteScripts(in hooksDir: URL) {
        for name in obsoleteScriptNames {
            try? FileManager.default.removeItem(at: hooksDir.appendingPathComponent(name))
        }
    }

    private static func argusHooksDir() throws -> URL {
        guard
            let support = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first
        else { throw Failure.noAppSupport }
        return try ensureDirectory(support.appendingPathComponent("argus/hooks"))
    }

    private static func ensureDirectory(_ dir: URL) throws -> URL {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// The path is JSON-escaped in bash before being printed into the event line: a worktree path
    /// containing `"` or `\` (both legal in POSIX paths) would otherwise produce an invalid line,
    /// which the reader silently drops — the approval state would simply never appear. Parameter
    /// expansion keeps this dependency-free (no `jq`/`sed`) and works on macOS's bash 3.2.
    static func hookScript(state: String, eventLogPath: String) -> String {
        #"""
        #!/bin/bash
        WORKTREE=$(git rev-parse --show-toplevel 2>/dev/null)
        WORKTREE="${WORKTREE:-$PWD}"
        [ -z "$WORKTREE" ] && exit 0
        EVENT_LOG='\#(eventLogPath)'
        ESCAPED=${WORKTREE//\\/\\\\}
        ESCAPED=${ESCAPED//\"/\\\"}
        ESCAPED=${ESCAPED//$'\n'/\\n}
        ESCAPED=${ESCAPED//$'\t'/\\t}
        printf '{"worktreePath":"%s","state":"\#(state)","agent":"claude"}\n' "$ESCAPED" \
            >> "$EVENT_LOG" 2>/dev/null || true
        """#
    }

    private static func writeExecutable(at url: URL, content: String) throws {
        try content.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: url.path
        )
    }

    // MARK: - .claude/settings.local.json

    private static func patchLocalSettings(worktreePath: String, paths: ClaudeHookPaths) throws {
        let claudeDir = URL(fileURLWithPath: worktreePath).appendingPathComponent(".claude")
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        let settingsURL = claudeDir.appendingPathComponent("settings.local.json")
        let settings = loadSettings(at: settingsURL)
        let merged = ClaudeSettingsPatcher.merged(into: settings, paths: paths)
        try saveSettings(merged, to: settingsURL)
    }

    private static func loadSettings(at url: URL) -> [String: Any] {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return [:] }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // A user-edited file (comments, a trailing comma) we can't parse is about to be replaced
            // by the merged result; keep a copy so nothing they wrote is lost.
            CorruptFileBackup.preserve(url)
            return [:]
        }
        return obj
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
        let hookFile = confDir.appendingPathComponent("argus.fish")
        let content = fishHookScript(eventLogPath: HookIPC.shellEventLogPath)
        do {
            try FileManager.default.createDirectory(at: confDir, withIntermediateDirectories: true)
            try content.write(to: hookFile, atomically: true, encoding: .utf8)
            // Only after a successful write: marking it installed on failure would stop every later
            // attempt, leaving shell-busy detection silently on the slower tmux fallback.
            fishHooksInstalled = true
        } catch {
            return
        }
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
