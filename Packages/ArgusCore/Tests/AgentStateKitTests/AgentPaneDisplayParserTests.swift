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

    /// Real capture: a live Claude pane (genuinely running — see the `✽ Marinating…` line) whose
    /// visible window also contains unrelated quoted diff text mentioning "for 3m 37s" (a `git
    /// diff` line from a completely different, Codex-authored file this same session had open).
    /// The old bare `\sfor\s+\d+[hms]` match (with no line-start/glyph anchor) read that quoted
    /// text as `.finished`, clobbering the correctly-detected `.running` state from the real
    /// marker below it — this must resolve to `.running`.
    private static let claudeRunningWithUnrelatedForText = """
        ✽ Marinating… (8m 44s · ↓ 20.2k tokens)
              85 +        ─ Worked for 3m 37s ───────────────────────────────────────────────
          ⎿  Tip: Use /btw to ask a quick side question without interrupting Claude's current work
        ────────────────────────────────────────────────────────────
        ❯
        ────────────────────────────────────────────────────────────
          [Sonnet 5 (high)] [ctx:22%] [5h:2%/20:30] [7d:5%/Mon 13:00]
          ⏵⏵ auto mode on (shift+tab to cycle) · ← for agents
        """

    /// Same unrelated quoted text, but with no genuine running/done marker anywhere in the
    /// window at all (e.g. the real marker has already scrolled out of the captured tail) — must
    /// resolve to `nil` (indeterminate), not `.finished` from the quoted "for 3m 37s" text alone.
    private static let claudeOnlyUnrelatedForText = """
              85 +        ─ Worked for 3m 37s ───────────────────────────────────────────────
          ⎿  Tip: Use /btw to ask a quick side question without interrupting Claude's current work
        ────────────────────────────────────────────────────────────
        ❯
        ────────────────────────────────────────────────────────────
          [Sonnet 5 (high)] [ctx:22%] [5h:2%/20:30] [7d:5%/Mon 13:00]
          ⏵⏵ auto mode on (shift+tab to cycle) · ← for agents
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

    /// Real capture from a genuinely idle Codex pane (`· Ready ·` in its status line) whose
    /// scrollback happens to contain the literal word "Working" from an unrelated `git status`
    /// recap — the exact regression a bare `\bWorking\b` match (this codebase's previous pattern)
    /// produced live: the row stuck on `.running` forever. `running` must not match this text.
    private static let codexIdleWithWorkingInScrollback = """
        • Updated and renamed pr-form to pr-approve (plugins/line-android-tools/skills/pr-approve/SKILL.md).

          It now:

          - Accepts an explicit PR URL
          - Validates PR state and author
          - Prevents duplicate approval
          - Confirms before approval
          - Runs gh pr review --approve
          - Verifies the approval

        create-fork-pr retains form generation through an internal reference. Skill and plugin
        validation passed. The unrelated my-commit edit remains untouched. Changes are uncommitted.

        ─ Worked for 3m 37s ───────────────────────────────────────────────

        › Ask Codex to do anything

          gpt-5.6-sol xhigh · ~/.claude/my-plugins · xhigh · Ready · Context 71% left · 0.153.4 · 258K window
        """

    /// The dot-delimited status-line slot the verified `· Ready ·` occupies is confirmed by
    /// `strings` on the Codex binary to hold one of exactly three "compact session run-state"
    /// values: `Ready`, `Working`, `Thinking`. Not independently live-captured mid-run the way
    /// `Ready` is (no live pane was caught actually running while investigating this), but this is
    /// the same slot, not a guess at a new location.
    private static let codexRunningStatusLine = """
        › Ask Codex to do anything

          gpt-5.6-sol xhigh · ~/workspace/app/Argus · xhigh · Working · Context 68% left · 0.153.4 · 258K window
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

    @Test(
        """
        the reported regression: unrelated quoted text mentioning "for 3m 37s" elsewhere in the \
        captured window must not clobber a genuine .running marker — the old unanchored finished \
        pattern read the quoted text as .finished instead
        """
    )
    func unrelatedForTextInScrollbackDoesNotClobberRealRunningMarker() {
        #expect(
            AgentPaneDisplayParser.signal(
                fromPane: Self.claudeRunningWithUnrelatedForText, patterns: .claudeDefaults) == .running)
    }

    @Test("unrelated quoted \"for 3m 37s\" text with no real marker present at all is indeterminate, not .finished")
    func unrelatedForTextAloneIsIndeterminate() {
        #expect(
            AgentPaneDisplayParser.signal(
                fromPane: Self.claudeOnlyUnrelatedForText, patterns: .claudeDefaults) == nil)
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

    @Test(
        """
        the reported regression: an idle Codex pane ("· Ready ·") whose scrollback happens to \
        contain the word "Working" (from an unrelated git-status recap) must map to .ready, not \
        .running — a bare \\bWorking\\b match anywhere in the pane (this codebase's previous \
        pattern) read this live capture as permanently running
        """
    )
    func codexIdleWithWorkingInScrollbackMapsToReadyNotRunning() {
        #expect(
            AgentPaneDisplayParser.signal(fromPane: Self.codexIdleWithWorkingInScrollback, patterns: .codexDefaults)
                == .ready)
    }

    @Test("a Codex status line reading \"· Working ·\" in the same slot as Ready maps to .running")
    func codexWorkingStatusLineMapsToRunning() {
        #expect(
            AgentPaneDisplayParser.signal(fromPane: Self.codexRunningStatusLine, patterns: .codexDefaults)
                == .running)
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
