import AgentStateKit
import ArgusConfigKit
import ArgusSupport
import Foundation
import Monitors

/// Polls every live Claude/Codex tmux pane Argus itself hosts, scraping what's on screen via a
/// single batched `tmux capture-pane` call per poll, and feeds `AgentStateBus` as the primary
/// (`.display`) state source — see `StateSource`'s doc comment for why this exists:
/// transcript/rollout inference has to guess liveness from a 15-minute staleness window, which
/// flips a genuinely busy agent (a long single tool call, or one blocked on a `Task` subagent —
/// both observed live) to idle. This reads what the pane actually shows instead, continuously
/// re-asserted, so it isn't subject to that heuristic at all.
///
/// Lives in App/ (not AgentStateKit) because it needs `Tmux.executable`/
/// `sessionName(for:path:)` from GhosttyBridge, which AgentStateKit cannot import — same reasoning
/// as `ShellStateBus`. `TmuxPaneCaptureBatch` (Monitors) holds the pure batching/parsing logic;
/// this file is the glue that runs it against real tmux processes and folds the result into
/// `AgentStateBus`.
@MainActor
final class AgentPaneDisplayWatcher: ObservableObject {
    private weak var agentBus: AgentStateBus?
    private var knownPaths: Set<String> = []
    private var pollTask: Task<Void, Never>?

    /// Per-key latch/debounce/dedup state — see `AgentPaneSignalReducer`'s doc comment for why
    /// this exists at all rather than calling `agentBus?.apply` straight from a `switch` on the
    /// signal: Claude's on-screen "finished" marker (`✻ Sautéed for 31m 19s`) persists unchanged
    /// until the *next* turn starts, so polling it every second without this would re-`apply(.done)`
    /// right past a user's dismissal (`AgentStateBus.dismissAttentionStates` publishes `.idle` but
    /// has no way to change what the pane itself displays) within one poll interval.
    private var keyStates: [AgentKey: AgentPaneSignalReducer.KeyState] = [:]

    /// Keys covered on the previous poll, so a session that disappears between polls (tmux
    /// session killed outside Argus's own reset paths, which already call
    /// `AgentStateBus.reset(for:agent:)` directly on tab close/reload) can be told apart from one
    /// simply not covered yet, and proactively emitted as idle rather than left to go stale with
    /// no further signal at all. Includes keys still inside `vanishDebouncePolls`'s grace period
    /// (see `missingStreaks`) so a transiently-missing key keeps being diffed against on the next
    /// poll instead of looking freshly "not covered yet".
    private var previouslyFoundKeys: Set<AgentKey> = []

    /// Consecutive polls (since last seen) a previously-covered key has been missing from
    /// `tmux list-panes -a`'s output. A key must miss `vanishDebouncePolls` polls in a row before
    /// `emitIdleForVanishedSessions` treats it as truly gone — one miss alone is indistinguishable
    /// from a transient listing hiccup (the same "no data this poll" hazard already guarded for a
    /// fully failed `list-panes` call below, just scoped to a single session's row instead of the
    /// whole command). Concluding "gone" on a single miss would wipe this key's
    /// `AgentPaneSignalReducer` memory (`keyStates`) and publish `.idle`; if the session reappears
    /// on the very next poll with its on-screen "finished" marker unchanged, that wiped memory
    /// reads it as a brand-new signal and republishes `.done` — a spontaneous done reappearing
    /// with nothing having actually happened.
    private var missingStreaks: [AgentKey: Int] = [:]

    private static let vanishDebouncePolls = 2

    private nonisolated static let pollIntervalNanoseconds: UInt64 = 1_000_000_000

    private static let roles: [(role: PaneRole, agent: AgentType)] = [
        (.claude, .claude),
        (.codex, .codex),
    ]

    func attach(agentBus: AgentStateBus) {
        self.agentBus = agentBus
    }

    /// Fed from `store.repos.flatMap(\.worktrees)` — every known worktree, not just
    /// `pool.activeIDs`: an agent's tmux session outlives its pane being closed in the UI.
    func updateKnownPaths(_ paths: Set<String>) {
        knownPaths = paths
    }

    func start() {
        guard pollTask == nil else { return }
        pollTask = PollingTask.repeating(
            order: .actThenSleep,
            interval: { Self.pollIntervalNanoseconds },
            action: { [weak self] in await self?.poll() }
        )
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func poll() async {
        guard !knownPaths.isEmpty else {
            emitIdleForVanishedSessions(previouslyFoundKeys)
            agentBus?.setDisplayCovered([])
            previouslyFoundKeys = []
            missingStreaks.removeAll()
            return
        }

        var sessionToKey: [String: AgentKey] = [:]
        for path in knownPaths {
            for entry in Self.roles {
                let session = WorktreePane.sessionName(for: entry.role, path: path)
                sessionToKey[session] = AgentKey(worktreePath: path, agent: entry.agent)
            }
        }

        let listResult = await Tmux.run(TmuxCommand.listAllPanes(format: "#{session_name}|#{pane_height}"))
        // A failed launch/exit (e.g. around system sleep/wake, or transient resource pressure)
        // returns exit code -1 with empty output — indistinguishable, if fed straight into
        // parseSessionHeights, from "there are now zero live sessions". Treating that as a real
        // "everything vanished" would force-idle and wipe every key's AgentPaneSignalReducer
        // memory, and the very next successful poll would then read the SAME still-on-screen
        // "done" marker (Claude's finished text persists on screen until the next turn) against
        // fresh memory as a brand-new signal, republishing "done" immediately — a periodic
        // idle-then-done flicker with nothing having actually happened. Bail out and retry next
        // poll instead, same "no data this poll" treatment already given to a mid-batch capture
        // failure below.
        guard listResult.succeeded else { return }
        let heightBySession = TmuxPaneCaptureBatch.parseSessionHeights(from: listResult.standardOutput)
        let foundSessionNames = Array(Set(heightBySession.keys).intersection(sessionToKey.keys))
        let foundKeys = Set(foundSessionNames.compactMap { sessionToKey[$0] })

        let stillMissing = debounceVanished(foundKeys: foundKeys)

        var textBySession: [String: String] = [:]
        if !foundSessionNames.isEmpty {
            let captureArgs = TmuxPaneCaptureBatch.captureArguments(
                sessionNames: foundSessionNames, heightBySession: heightBySession)
            let captureResult = await Tmux.run(captureArgs)
            textBySession = TmuxPaneCaptureBatch.splitCapture(
                captureResult.standardOutput, sessionNames: foundSessionNames)
        }

        for session in foundSessionNames {
            guard let key = sessionToKey[session], let paneText = textBySession[session], !paneText.isEmpty
            else { continue }
            // An empty capture means this session's own capture-pane failed mid-batch (see
            // TmuxPaneCaptureBatch.splitCapture) — not a legitimate blank pane, since a real tmux
            // pane is never actually empty. Skipping it here (rather than feeding "" to the
            // parser, which would read as .noAgentUI -> idle) keeps a transient capture failure
            // from wrongly demoting a genuinely busy agent; the key stays covered either way, so
            // the previous state simply holds until a later poll succeeds.
            applySignal(paneText: paneText, key: key)
        }

        let coveredKeys = foundKeys.union(stillMissing)
        agentBus?.setDisplayCovered(coveredKeys)
        previouslyFoundKeys = coveredKeys
    }

    private func applySignal(paneText: String, key: AgentKey) {
        let signal = AgentPaneDisplayParser.signal(fromPane: paneText, patterns: resolvedPatterns(for: key.agent))
        let (next, publish) = AgentPaneSignalReducer.reduce(signal, previous: keyStates[key] ?? .init())
        keyStates[key] = next
        guard let publish else { return }  // indeterminate, or an unchanged conclusion — nothing to do

        agentBus?.apply(
            HookPayload(worktreePath: key.worktreePath, state: publish, agent: Self.hookAgentString(for: key.agent)),
            source: .display
        )
    }

    /// Splits `previouslyFoundKeys.subtracting(foundKeys)` into keys that have now missed
    /// `vanishDebouncePolls` polls in a row (calls `emitIdleForVanishedSessions` on those directly)
    /// and keys still inside their grace period (returned, so the caller keeps covering them —
    /// see `missingStreaks`'s doc comment for why a single miss must not be treated as gone).
    private func debounceVanished(foundKeys: Set<AgentKey>) -> Set<AgentKey> {
        for key in foundKeys { missingStreaks.removeValue(forKey: key) }
        var stillMissing: Set<AgentKey> = []
        var newlyVanished: Set<AgentKey> = []
        for key in previouslyFoundKeys.subtracting(foundKeys) {
            let streak = (missingStreaks[key] ?? 0) + 1
            if streak >= Self.vanishDebouncePolls {
                missingStreaks.removeValue(forKey: key)
                newlyVanished.insert(key)
            } else {
                missingStreaks[key] = streak
                stillMissing.insert(key)
            }
        }
        emitIdleForVanishedSessions(newlyVanished)
        return stillMissing
    }

    /// A key covered on the previous poll but gone now — explicit `.display` idle rather than
    /// letting it go stale with no further signal. Its reducer state is dropped entirely: if this
    /// worktree's agent tab reopens later, it starts a fresh session (see
    /// `AgentTabsStore.closeTab`'s doc comment) that hasn't run yet either, and its first signal
    /// must not be suppressed by a dedup entry left over from the session that just vanished.
    private func emitIdleForVanishedSessions(_ keys: Set<AgentKey>) {
        for key in keys {
            keyStates.removeValue(forKey: key)
            agentBus?.apply(
                HookPayload(worktreePath: key.worktreePath, state: "idle", agent: Self.hookAgentString(for: key.agent)),
                source: .display
            )
        }
    }

    /// Merges the user's `agentDisplayPatterns` config override (if any) with the built-in
    /// defaults, per field — an absent or empty override array means "use the built-in default
    /// for this field", not "match nothing".
    private func resolvedPatterns(for agent: AgentType) -> AgentPaneDisplayParser.Patterns {
        let defaults: AgentPaneDisplayParser.Patterns
        let overrides: ArgusConfig.AgentDisplayPatternOverrides?
        switch agent {
        case .claude:
            defaults = .claudeDefaults
            overrides = ArgusConfigStore.shared.config.agentDisplayPatterns.claude

        case .codex:
            defaults = .codexDefaults
            overrides = ArgusConfigStore.shared.config.agentDisplayPatterns.codex
        }
        guard let overrides else { return defaults }
        return AgentPaneDisplayParser.Patterns(
            running: nonEmpty(overrides.running) ?? defaults.running,
            finished: nonEmpty(overrides.finished) ?? defaults.finished,
            ready: nonEmpty(overrides.ready) ?? defaults.ready,
            awaitingApproval: nonEmpty(overrides.awaitingApproval) ?? defaults.awaitingApproval,
            agentUI: nonEmpty(overrides.agentUI) ?? defaults.agentUI
        )
    }

    private func nonEmpty(_ patterns: [String]?) -> [String]? {
        guard let patterns, !patterns.isEmpty else { return nil }
        return patterns
    }

    private static func hookAgentString(for agent: AgentType) -> String {
        switch agent {
        case .claude: "claude"
        case .codex: "codex"
        }
    }
}
