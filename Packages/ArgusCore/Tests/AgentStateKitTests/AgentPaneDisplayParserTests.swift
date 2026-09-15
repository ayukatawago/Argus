import Foundation
import Testing

@testable import AgentStateKit

@Suite("AgentPaneDisplayParser")
struct AgentPaneDisplayParserTests {
    // MARK: - Real captures (Claude Code 2.1.236, `tmux capture-pane -p -J`, taken live while
    // planning this change — not hand-written approximations of what the TUI "probably" looks
    // like).

    private static let claudeRunning = """
        ✽ Marinating… (8m 44s · ↓ 20.2k tokens)
          ⎿  Tip: Use /btw to ask a quick side question without interrupting Claude's current work
        ────────────────────────────────────────────────────────────
        ❯
        ────────────────────────────────────────────────────────────
          [Sonnet 5 (high)] [ctx:22%] [5h:2%/20:30] [7d:5%/Mon 13:00]
          ⏵⏵ auto mode on (shift+tab to cycle) · ← for agents
        """

    private static let claudeDone = """
        ✻ Sautéed for 31m 19s
        ※ recap: Removed 4 released LIFF feature flags across 4 clean commits. (disable recaps in /config)
        ────────────────────────────────────────────────────────────
        ❯
        ────────────────────────────────────────────────────────────
          [Sonnet 5 (high)] [ctx:22%] [5h:2%/20:30] [7d:5%/Mon 13:00]
          ⏵⏵ auto mode on (shift+tab to cycle) · ← for agents
        """

    /// The near-miss that motivates the whole "indeterminate, don't guess idle" contract: a live
    /// pane switched to this line mid-investigation while blocked on a `Task` subagent. It must
    /// resolve to `nil` (keep the previously-published `.running`), not `.finished` — "for 1
    /// background agent" does not satisfy the `finished` pattern because the digit "1" is followed
    /// by a space, not an [hms] unit.
    private static let claudeSubagentBlocked = """
        ✻ Waiting for 1 background agent to finish
          ⎿  Tip: Use /btw to ask a quick side question without interrupting Claude's current work
        ────────────────────────────────────────────────────────────
        ❯
        ────────────────────────────────────────────────────────────
          [Sonnet 5 (high)] [ctx:50%] [5h:4%/20:30] [7d:5%/Mon 13:00]
          ⏵⏵ auto mode on (shift+tab to cycle) · ← for agents
          ⏺ main
          ◯ general-purpose  Research LiffFragment public surface for Phase 7d
        """

    private static let codexWelcome = """
        ╭────────────────────────────────────────────────╮
        │ >_ OpenAI Codex (v0.153.4)                     │
        │                                                │
        │ model:     gpt-5.6-sol high   /model to change │
        │ directory: ~/workspace/app/Argus               │
        ╰────────────────────────────────────────────────╯
          Tip: New Build faster with the Desktop app. Run 'codex app' or visit chatgpt.com/codex
        › Ask Codex to do anything
          gpt-5.6-sol high · ~/workspace/app/Argus · high · Ready · Context 100% left · 0.153.4
        """

    private static let bareShellPrompt = """
        takuya.ogawa@Mac Argus % ls
        Argus.xcodeproj  CLAUDE.md  Packages  Sources
        takuya.ogawa@Mac Argus %
        """

    // MARK: - Claude

    @Test("a live running-turn capture maps to .running")
    func claudeRunningMapsToRunning() {
        #expect(
            AgentPaneDisplayParser.signal(fromPane: Self.claudeRunning, patterns: .claudeDefaults) == .running)
    }

    @Test("a live finished-turn capture maps to .finished")
    func claudeDoneMapsToFinished() {
        #expect(
            AgentPaneDisplayParser.signal(fromPane: Self.claudeDone, patterns: .claudeDefaults) == .finished)
    }

    @Test(
        """
        a pane blocked on a background Task subagent is indeterminate (nil), not .finished — \
        "for 1 background agent" must not satisfy the finished pattern, and there is no running \
        pattern to match either, so the caller keeps whatever state was already published rather \
        than guessing idle
        """
    )
    func claudeSubagentBlockedIsIndeterminate() {
        #expect(
            AgentPaneDisplayParser.signal(fromPane: Self.claudeSubagentBlocked, patterns: .claudeDefaults) == nil)
    }

    @Test("a bare shell prompt with no Claude chrome maps to .noAgentUI")
    func bareShellPromptMapsToNoAgentUIUnderClaudePatterns() {
        #expect(
            AgentPaneDisplayParser.signal(fromPane: Self.bareShellPrompt, patterns: .claudeDefaults) == .noAgentUI)
    }

    @Test("an approval-dialog phrase outranks a running spinner also present in the same capture")
    func approvalOutranksRunningWhenBothPresent() {
        let text = Self.claudeRunning + "\nDo you want to proceed?"
        #expect(
            AgentPaneDisplayParser.signal(fromPane: text, patterns: .claudeDefaults) == .awaitingApproval)
    }

    // MARK: - Codex

    @Test("a live idle Codex status line (\"· Ready ·\") maps to .ready")
    func codexWelcomeMapsToReady() {
        #expect(
            AgentPaneDisplayParser.signal(fromPane: Self.codexWelcome, patterns: .codexDefaults) == .ready)
    }

    @Test("a bare shell prompt with no Codex chrome maps to .noAgentUI")
    func bareShellPromptMapsToNoAgentUIUnderCodexPatterns() {
        #expect(
            AgentPaneDisplayParser.signal(fromPane: Self.bareShellPrompt, patterns: .codexDefaults) == .noAgentUI)
    }

    // MARK: - Robustness

    @Test("an invalid user-supplied regex is skipped rather than crashing, and other patterns still match")
    func invalidRegexIsSkippedNotCrashing() {
        let patterns = AgentPaneDisplayParser.Patterns(
            running: ["("],  // invalid: unbalanced group
            finished: [#"\sfor\s+\d+[hms]"#],
            ready: [],
            awaitingApproval: [],
            agentUI: []
        )
        #expect(AgentPaneDisplayParser.signal(fromPane: Self.claudeDone, patterns: patterns) == .finished)
        #expect(AgentPaneDisplayParser.signal(fromPane: Self.claudeRunning, patterns: patterns) == nil)
    }

    @Test("empty pane text is indeterminate under patterns with no agentUI markers configured")
    func emptyTextIsIndeterminateWithoutAgentUIMarkers() {
        let patterns = AgentPaneDisplayParser.Patterns(
            running: [#"…\s*\(\d+[hms]"#], finished: [], ready: [], awaitingApproval: [], agentUI: [])
        #expect(AgentPaneDisplayParser.signal(fromPane: "", patterns: patterns) == nil)
    }
}
