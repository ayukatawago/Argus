import Foundation

/// Pure parsing of one on-screen tmux pane capture into a positive signal about what the hosted
/// CLI (Claude Code or Codex) is doing right now — the display-scraping counterpart to
/// `ClaudeTranscriptParser`/`CodexSessionParser`. Unlike those, this reads what the TUI currently
/// renders rather than a log of past events, so it is immune to the "no transcript entry for 15
/// minutes" false-idle failure mode a long single tool call or a `Task` subagent run triggers —
/// see `ClaudeTranscriptWatcher.activityWindow`'s doc comment for the motivating bug: live captures
/// showed a 31-minute turn and a 9m10s-timeout tool call, both well past that window.
public enum AgentPaneDisplayParser {
    /// What one pane capture positively asserts. `signal(fromPane:patterns:)` returns `nil` when
    /// none of `patterns` match anything in the text — the caller (`AgentPaneDisplayWatcher`) must
    /// treat `nil` as "indeterminate, keep whatever state is already published", never as idle.
    /// Verified live: a Claude pane mid-`Task`-subagent shows "Waiting for 1 background agent to
    /// finish", which matches neither `running` nor `finished` — exactly the case this contract
    /// exists for. Never infer `.finished`/idle from the mere absence of a running marker.
    public enum PaneSignal: Equatable, Sendable {
        case running
        case finished
        case ready
        case awaitingApproval
        case noAgentUI
    }

    /// One agent's regex vocabulary. Every field is a list of alternative regex patterns (an empty
    /// list never matches); a config override (`ArgusConfig.agentDisplayPatterns`) replaces a field
    /// wholesale rather than appending to it.
    public struct Patterns: Equatable, Sendable {
        public var running: [String]
        public var finished: [String]
        public var ready: [String]
        public var awaitingApproval: [String]
        /// Chrome that's on-screen whenever this CLI's TUI is present at all, running or not —
        /// e.g. its status-line footer. Its *absence* is what makes `.noAgentUI` a positive signal
        /// (the CLI has exited back to a bare shell prompt) rather than a guess from silence.
        public var agentUI: [String]

        public init(
            running: [String],
            finished: [String],
            ready: [String],
            awaitingApproval: [String],
            agentUI: [String]
        ) {
            self.running = running
            self.finished = finished
            self.ready = ready
            self.awaitingApproval = awaitingApproval
            self.agentUI = agentUI
        }

        /// Verified against live Claude Code 2.1.236 panes (see `AgentPaneDisplayParserTests`'s
        /// fixtures, captured today). The spinner glyph (✻ ✽ ✶ ✳) and verb (Marinating, Sautéed,
        /// Baked, ...) both rotate through the CLI's own randomized vocabulary, so neither is
        /// matched — only the stable timer shape is: `running` is "…" then a "(" duration " ·"
        /// counter that's still ticking; `finished` is "for" then a duration with nothing after,
        /// once the counter stops. Claude prints no distinct idle/"ready" marker of its own — an
        /// empty `ready` list is intentional, not an oversight; the `nil` (indeterminate, keep
        /// previous state) fallback covers it.
        public static let claudeDefaults = Patterns(
            running: [#"…\s*\(\d+[hms]"#],
            finished: [#"\sfor\s+\d+[hms]"#],
            ready: [],
            awaitingApproval: [
                #"Do you want to proceed\?"#,
                #"Do you want to continue\?"#,
                #"Do you want to allow"#,
                #"No, and tell Claude what to do differently"#,
            ],
            agentUI: [
                #"\[ctx:\d+%\]"#,
                #"auto mode on"#,
                #"plan mode on"#,
                #"shift\+tab to cycle"#,
            ]
        )

        /// `ready`/`agentUI` are verified against a live idle Codex 0.153/0.154 pane (its
        /// `· Ready ·` status-line segment and startup banner). `running` used to be bare
        /// `\bWorking\b`/`\bReviewing\b`/`to interrupt\)` word matches anywhere in the pane,
        /// recovered from `strings` on the Codex binary with no live verification — that false-
        /// positived live: an idle pane whose scrollback merely contained a `git status` recap
        /// ("Working tree is clean.") or a directory-trust prompt ("Working with untrusted
        /// contents...") read as permanently `.running`, and `Reviewing` turned out on inspection
        /// to bind to an unrelated internal string ("Reviewing approval request"), not a run
        /// state at all. The binary also confirms (`strings`: "Compact session run-state text
        /// (Ready, Working, Thinking)") that the verified `· Ready ·` status-line segment is one
        /// of exactly three values for that slot — so `running` now matches `Working`/`Thinking`
        /// anchored to the same dot-delimited slot as `ready`, rather than as a bare word anywhere
        /// in the pane. The other two values themselves are not yet independently live-verified
        /// the way `Ready` is. `awaitingApproval` is likewise NOT independently verified against a
        /// live capture — recovered from `strings` on the Codex binary, the same epistemic status
        /// CLAUDE.md already records for Codex's `EventMsg` names — so a miss here degrades to the
        /// hook/transcript fallback rather than breaking anything.
        public static let codexDefaults = Patterns(
            running: [#"·\s*Working\s*·"#, #"·\s*Thinking\s*·"#],
            finished: [],
            ready: [#"·\s*Ready\s*·"#],
            awaitingApproval: [
                #"Allow this request and continue"#,
                #"Allow for this session"#,
                #"Approve app tool call\?"#,
            ],
            agentUI: [
                #"Ask Codex to do anything"#,
                #"OpenAI Codex"#,
                #"Context \d+% left"#,
            ]
        )
    }

    /// Checked in this order because an open approval dialog freezes the spinner — the pane can
    /// simultaneously look "not running" and be blocked on the user, so approval must outrank
    /// running/finished rather than lose to whichever happens to be checked first. `noAgentUI` is
    /// checked last and only once every other, more specific signal has failed to match.
    public static func signal(fromPane text: String, patterns: Patterns) -> PaneSignal? {
        if matchesAny(patterns.awaitingApproval, in: text) { return .awaitingApproval }
        if matchesAny(patterns.running, in: text) { return .running }
        if matchesAny(patterns.finished, in: text) { return .finished }
        if matchesAny(patterns.ready, in: text) { return .ready }
        if !patterns.agentUI.isEmpty, !matchesAny(patterns.agentUI, in: text) { return .noAgentUI }
        return nil
    }

    private static func matchesAny(_ patterns: [String], in text: String) -> Bool {
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        return patterns.contains { pattern in
            guard let regex = cachedRegex(for: pattern) else { return false }
            return regex.firstMatch(in: text, range: range) != nil
        }
    }

    // NSCache is internally thread-safe (Apple's documented guarantee) despite predating Sendable,
    // so repeated calls from the watcher's background poll loop (roughly once per second per pane)
    // don't pay recompilation cost. `nonisolated(unsafe)` records that this is a deliberate,
    // verified exception rather than an oversight. An invalid user-supplied pattern (from the
    // agentDisplayPatterns config override) simply never matches rather than crashing —
    // `cachedRegex` returns nil for it and `matchesAny` treats that alternative as a non-match.
    private nonisolated(unsafe) static let regexCache = NSCache<NSString, NSRegularExpression>()

    private static func cachedRegex(for pattern: String) -> NSRegularExpression? {
        let key = pattern as NSString
        if let cached = regexCache.object(forKey: key) { return cached }
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        regexCache.setObject(regex, forKey: key)
        return regex
    }
}
