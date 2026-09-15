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
/// Lives in App/ (not AgentStateKit) because it needs `WorktreePane.tmuxExecutable`/
/// `sessionName(for:path:)` from GhosttyBridge, which AgentStateKit cannot import — same reasoning
/// as `ShellStateBus`. `TmuxPaneCaptureBatch` (Monitors) holds the pure batching/parsing logic;
/// this file is the glue that runs it against real tmux processes and folds the result into
/// `AgentStateBus`.
@MainActor
final class AgentPaneDisplayWatcher: ObservableObject {
    private weak var agentBus: AgentStateBus?
    private var knownPaths: Set<String> = []
    private var pollTask: Task<Void, Never>?

    /// Per-key latch: has this pane shown a running/finished signal at least once since Argus
    /// started watching it? Needed only for Codex's `.ready` signal, which is ambiguous on its
    /// own — its `· Ready ·` status segment shows both before the first turn and after one
    /// finishes. Claude needs no equivalent (its `finished` marker is unambiguous, and its
    /// `Patterns.ready` list is deliberately empty).
    private var hasRunSinceObserved: Set<AgentKey> = []

    /// Keys covered on the previous poll, so a session that disappears between polls (tmux
    /// session killed outside Argus's own reset paths, which already call
    /// `AgentStateBus.reset(for:agent:)` directly on tab close/reload) can be told apart from one
    /// simply not covered yet, and proactively emitted as idle rather than left to go stale with
    /// no further signal at all.
    private var previouslyFoundKeys: Set<AgentKey> = []

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
            return
        }

        var sessionToKey: [String: AgentKey] = [:]
        for path in knownPaths {
            for entry in Self.roles {
                let session = WorktreePane.sessionName(for: entry.role, path: path)
                sessionToKey[session] = AgentKey(worktreePath: path, agent: entry.agent)
            }
        }

        let tmux = WorktreePane.tmuxExecutable
        let listResult = await ProcessRunner.run(
            tmux, ["list-panes", "-a", "-F", "#{session_name}|#{pane_height}"])
        let heightBySession = TmuxPaneCaptureBatch.parseSessionHeights(from: listResult.standardOutput)
        let foundSessionNames = Array(Set(heightBySession.keys).intersection(sessionToKey.keys))
        let foundKeys = Set(foundSessionNames.compactMap { sessionToKey[$0] })

        emitIdleForVanishedSessions(previouslyFoundKeys.subtracting(foundKeys))

        var textBySession: [String: String] = [:]
        if !foundSessionNames.isEmpty {
            let captureArgs = TmuxPaneCaptureBatch.captureArguments(
                sessionNames: foundSessionNames, heightBySession: heightBySession)
            let captureResult = await ProcessRunner.run(tmux, captureArgs)
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

        agentBus?.setDisplayCovered(foundKeys)
        previouslyFoundKeys = foundKeys
    }

    private func applySignal(paneText: String, key: AgentKey) {
        guard let signal = AgentPaneDisplayParser.signal(fromPane: paneText, patterns: resolvedPatterns(for: key.agent))
        else { return }  // indeterminate — keep whatever state is already published

        let state: String
        switch signal {
        case .awaitingApproval:
            state = "waitingForApproval"

        case .running:
            hasRunSinceObserved.insert(key)
            state = "running"

        case .finished:
            hasRunSinceObserved.insert(key)
            state = "done"

        case .ready:
            state = hasRunSinceObserved.contains(key) ? "done" : "idle"

        case .noAgentUI:
            hasRunSinceObserved.remove(key)
            state = "idle"
        }

        agentBus?.apply(
            HookPayload(worktreePath: key.worktreePath, state: state, agent: Self.hookAgentString(for: key.agent)),
            source: .display
        )
    }

    /// A key covered on the previous poll but gone now — explicit `.display` idle rather than
    /// letting it go stale with no further signal. `hasRunSinceObserved` is cleared too: if this
    /// worktree's agent tab reopens later, it starts a fresh session (see
    /// `AgentTabsStore.closeTab`'s doc comment) that hasn't run yet either.
    private func emitIdleForVanishedSessions(_ keys: Set<AgentKey>) {
        for key in keys {
            hasRunSinceObserved.remove(key)
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
