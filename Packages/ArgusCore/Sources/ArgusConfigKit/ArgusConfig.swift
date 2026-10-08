import Combine
import Foundation

public enum AgentSelection: String, Codable, CaseIterable, Identifiable, Sendable {
    case claude
    case codex

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        }
    }
}

public enum WindowLayout: String, Codable, CaseIterable, Identifiable, Sendable {
    case terminalAgent
    case agentsOverTerminal

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .terminalAgent: "Terminal + Agent"
        case .agentsOverTerminal: "Agents / Terminal"
        }
    }

    public var toolbarIcon: String {
        switch self {
        case .terminalAgent: "rectangle.split.2x1"
        case .agentsOverTerminal: "rectangle.split.1x2"
        }
    }
}

public struct ArgusConfig: Codable, Equatable, Sendable {
    public var leaderKey = "ctrl+b"
    public var leaderTimeoutSeconds = 1.5
    public var keyBindings = KeyBindings()
    public var agent: AgentSelection = .claude
    public var layout: WindowLayout = .terminalAgent
    public var agentPaneMode: AgentPaneMode = .full
    public var claudeCommand: String = "claude --continue"
    public var codexCommand: String = "codex resume"
    public var diskMonitor = DiskMonitor()
    public var github = GitHub()
    public var environmentVariables: [String: String] = [:]
    public var popupShortcuts: [PopupShortcut] = [.lazygitDefault]
    public var agentDisplayPatterns = AgentDisplayPatterns()
    public var codexUsage = CodexUsage()
    /// Per-project agent override, keyed by repo `mainPath` (the same key `Workspaces`' own
    /// `repoOrder`/`excludedRepoPaths` use). Absent key = use `agent`. Lives here rather than in
    /// `Workspaces`/`workspaces.json` because `AgentSelection` is an `ArgusConfigKit` type and that
    /// target may not import `Workspaces` (see CLAUDE.md's module layout rule).
    public var projectAgents: [String: AgentSelection] = [:]
    /// Set once the user dismisses the first-run checklist shown in the empty detail area.
    public var onboardingDismissed = false
    /// Fraction of the height the agent view takes in the `agentsOverTerminal` layout. Written back
    /// when the user drags the divider; clamped on read so a hand-edited value can't hide a pane.
    public var agentsOverTerminalRatio = ArgusConfig.defaultAgentsOverTerminalRatio
    public static let defaultAgentsOverTerminalRatio = 0.7

    // Needed because we declare a custom init(from:).
    public init() {}

    // Use decodeIfPresent for every field so that keys added or renamed in future
    // versions never cause the whole config to silently fall back to defaults.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Defaults are read from a default instance rather than restated as literals here, so the
        // property declarations above remain the single source of truth.
        let defaults = ArgusConfig()
        func read<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? container.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        leaderKey = read(.leaderKey, defaults.leaderKey)
        leaderTimeoutSeconds = read(.leaderTimeoutSeconds, defaults.leaderTimeoutSeconds)
        keyBindings = read(.keyBindings, defaults.keyBindings)
        agent = read(.agent, defaults.agent)
        layout = read(.layout, defaults.layout)
        agentPaneMode = read(.agentPaneMode, defaults.agentPaneMode)
        claudeCommand = read(.claudeCommand, defaults.claudeCommand)
        codexCommand = read(.codexCommand, defaults.codexCommand)
        diskMonitor = read(.diskMonitor, defaults.diskMonitor)
        github = read(.github, defaults.github)
        environmentVariables = read(.environmentVariables, defaults.environmentVariables)
        // Element by element: one malformed shortcut (a missing `command`, a wrong type) drops only
        // itself rather than failing the array decode and silently discarding every shortcut.
        popupShortcuts =
            (try? container.decodeIfPresent([LossyElement<PopupShortcut>].self, forKey: .popupShortcuts))?
            .compactMap(\.value) ?? defaults.popupShortcuts
        agentDisplayPatterns = read(.agentDisplayPatterns, defaults.agentDisplayPatterns)
        codexUsage = read(.codexUsage, defaults.codexUsage)
        // Decoded as raw strings first rather than `[String: AgentSelection]` directly, so one
        // unrecognized value (a future third agent, a hand-edited typo) drops just that entry
        // instead of failing the whole dictionary decode and resetting every override to none.
        let rawProjectAgents: [String: String] = read(.projectAgents, [:])
        projectAgents = rawProjectAgents.compactMapValues(AgentSelection.init(rawValue:))
        onboardingDismissed = read(.onboardingDismissed, defaults.onboardingDismissed)
        agentsOverTerminalRatio = read(.agentsOverTerminalRatio, defaults.agentsOverTerminalRatio)
    }

    private enum CodingKeys: String, CodingKey {
        case leaderKey, leaderTimeoutSeconds, keyBindings, agent, layout, agentPaneMode
        case claudeCommand, codexCommand, diskMonitor, github, environmentVariables, popupShortcuts
        case agentDisplayPatterns, projectAgents, codexUsage, onboardingDismissed
        case agentsOverTerminalRatio
    }

    /// `agentsOverTerminalRatio` limited to a range where both panes stay usable.
    public var clampedAgentsOverTerminalRatio: Double {
        guard agentsOverTerminalRatio.isFinite else { return Self.defaultAgentsOverTerminalRatio }
        return min(max(agentsOverTerminalRatio, 0.2), 0.9)
    }

    public func launchCommand(for selection: AgentSelection) -> String {
        switch selection {
        case .claude: claudeCommand
        case .codex: codexCommand
        }
    }

    /// The agent to use for a worktree belonging to the project at `projectPath` (a repo
    /// `mainPath`): its override if it has one, otherwise the global default `agent`. A nil or
    /// untracked path — e.g. a CLI-originated `argus diff` on a folder outside the sidebar — falls
    /// back too.
    public func agent(forProjectPath projectPath: String?) -> AgentSelection {
        guard let projectPath, let override = projectAgents[projectPath] else { return agent }
        return override
    }

    /// Sets `projectPath`'s agent override. `nil` clears it, restoring the global default.
    public mutating func setAgent(_ selection: AgentSelection?, forProjectPath projectPath: String) {
        projectAgents[projectPath] = selection
    }
}
