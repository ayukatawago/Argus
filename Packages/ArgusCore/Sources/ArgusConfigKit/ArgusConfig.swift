import Combine
import Foundation

// Flexible string-keyed CodingKey for reading arbitrary JSON keys in custom decoders.
private struct RawStringKey: CodingKey {
    let stringValue: String
    init(_ string: String) { self.stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    var intValue: Int? { nil }
    init?(intValue: Int) { nil }
}

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
        leaderKey = (try? container.decodeIfPresent(String.self, forKey: .leaderKey)) ?? "ctrl+b"
        leaderTimeoutSeconds = (try? container.decodeIfPresent(Double.self, forKey: .leaderTimeoutSeconds)) ?? 1.5
        keyBindings = (try? container.decodeIfPresent(KeyBindings.self, forKey: .keyBindings)) ?? KeyBindings()
        agent = (try? container.decodeIfPresent(AgentSelection.self, forKey: .agent)) ?? .claude
        layout = (try? container.decodeIfPresent(WindowLayout.self, forKey: .layout)) ?? .terminalAgent
        agentPaneMode = (try? container.decodeIfPresent(AgentPaneMode.self, forKey: .agentPaneMode)) ?? .full
        claudeCommand = (try? container.decodeIfPresent(String.self, forKey: .claudeCommand)) ?? "claude --continue"
        codexCommand = (try? container.decodeIfPresent(String.self, forKey: .codexCommand)) ?? "codex resume"
        diskMonitor = (try? container.decodeIfPresent(DiskMonitor.self, forKey: .diskMonitor)) ?? DiskMonitor()
        github = (try? container.decodeIfPresent(GitHub.self, forKey: .github)) ?? GitHub()
        environmentVariables =
            (try? container.decodeIfPresent([String: String].self, forKey: .environmentVariables)) ?? [:]
        // Element by element: one malformed shortcut (a missing `command`, a wrong type) drops only
        // itself rather than failing the array decode and silently discarding every shortcut.
        popupShortcuts =
            (try? container.decodeIfPresent([LossyElement<PopupShortcut>].self, forKey: .popupShortcuts))?
            .compactMap(\.value) ?? [.lazygitDefault]
        agentDisplayPatterns =
            (try? container.decodeIfPresent(AgentDisplayPatterns.self, forKey: .agentDisplayPatterns))
            ?? AgentDisplayPatterns()
        codexUsage = (try? container.decodeIfPresent(CodexUsage.self, forKey: .codexUsage)) ?? CodexUsage()
        // Decoded as raw strings first rather than `[String: AgentSelection]` directly, so one
        // unrecognized value (a future third agent, a hand-edited typo) drops just that entry
        // instead of failing the whole dictionary decode and resetting every override to none.
        let rawProjectAgents =
            (try? container.decodeIfPresent([String: String].self, forKey: .projectAgents)) ?? [:]
        projectAgents = rawProjectAgents.compactMapValues(AgentSelection.init(rawValue:))
        onboardingDismissed = (try? container.decodeIfPresent(Bool.self, forKey: .onboardingDismissed)) ?? false
        agentsOverTerminalRatio =
            (try? container.decodeIfPresent(Double.self, forKey: .agentsOverTerminalRatio))
            ?? Self.defaultAgentsOverTerminalRatio
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

    public struct KeyBindings: Codable, Equatable, Sendable {
        public var focusPaneLeft: String = "["
        public var focusPaneRight: String = "]"
        // These four send a literal `tmux select-pane -L/-D/-U/-R` to whichever tmux session
        // `focusedRole` currently points to — distinct from focusPaneLeft/Right above, which
        // switch which of Argus's own shell/claude/codex roles is focused. Only meaningful if
        // that session's window was manually split with tmux's own `split-window`; a no-op
        // otherwise.
        public var tmuxPaneLeft: String = "h"
        public var tmuxPaneDown: String = "j"
        public var tmuxPaneUp: String = "k"
        public var tmuxPaneRight: String = "l"
        public var selectNextWorktree: String = "n"
        public var selectPreviousWorktree: String = "p"
        public var openNvim: String = "v"
        public var refreshWorkspace: String = "r"
        public var openMarkdownPreview: String = "m"
        public var openSettings: String = ","
        public var reloadAgentPane: String = "a"
        public var openDiskStatus: String = "d"
        public var openDiffReview: String = "w"
        public var openCodexUsage: String = "u"
        // These four act on whichever pane has focus: tmux windows in the shell pane, agent tabs
        // in the agent pane. No default key (still user-settable) — freed up for focusPaneLeft/Right.
        public var newTerminalTab: String = "t"
        public var nextTerminalTab: String = ""
        public var previousTerminalTab: String = ""
        public var closeTerminalTab: String = "x"
        public var toggleAgentSplit: String = "s"
        public var openCommandPalette: String = "/"
        // Not "g": the default lazygit popup shortcut already claims it.
        public var jumpToAttention: String = "e"
        public var focusSidebarFilter: String = "f"

        // Memberwise init needed because we declare a custom init(from:).
        public init() {}

        // Decode using decodeIfPresent so that missing or renamed keys use Swift defaults
        // rather than failing the entire config load. Legacy key names are tried as fallbacks.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: RawStringKey.self)
            func read(_ key: String, legacy: String? = nil, default dflt: String) -> String {
                if let value = try? container.decodeIfPresent(String.self, forKey: RawStringKey(key)) {
                    return value
                }
                if let alt = legacy,
                    let value = try? container.decodeIfPresent(String.self, forKey: RawStringKey(alt))
                {
                    return value
                }
                return dflt
            }
            focusPaneLeft = read("focusPaneLeft", legacy: "focusShellPane", default: "[")
            focusPaneRight = read("focusPaneRight", legacy: "focusAgentPane", default: "]")
            tmuxPaneLeft = read("tmuxPaneLeft", default: "h")
            tmuxPaneDown = read("tmuxPaneDown", default: "j")
            tmuxPaneUp = read("tmuxPaneUp", default: "k")
            tmuxPaneRight = read("tmuxPaneRight", default: "l")
            selectNextWorktree = read("selectNextWorktree", default: "n")
            selectPreviousWorktree = read("selectPreviousWorktree", default: "p")
            openNvim = read("openNvim", default: "v")
            refreshWorkspace = read("refreshWorkspace", default: "r")
            openMarkdownPreview = read("openMarkdownPreview", default: "m")
            openSettings = read("openSettings", default: ",")
            reloadAgentPane = read("reloadAgentPane", default: "a")
            openDiskStatus = read("openDiskStatus", default: "d")
            openDiffReview = read("openDiffReview", default: "w")
            openCodexUsage = read("openCodexUsage", default: "u")
            newTerminalTab = read("newTerminalTab", default: "t")
            nextTerminalTab = read("nextTerminalTab", default: "")
            previousTerminalTab = read("previousTerminalTab", default: "")
            closeTerminalTab = read("closeTerminalTab", default: "x")
            toggleAgentSplit = read("toggleAgentSplit", default: "s")
            openCommandPalette = read("openCommandPalette", default: "/")
            jumpToAttention = read("jumpToAttention", default: "e")
            focusSidebarFilter = read("focusSidebarFilter", default: "f")
        }
    }

    public struct PopupShortcut: Codable, Equatable, Identifiable, Sendable {
        public var id: String
        public var name: String
        public var key: String
        public var command: String
        public var sizePercent: Int

        public init(id: String, name: String, key: String, command: String, sizePercent: Int) {
            self.id = id
            self.name = name
            self.key = key
            self.command = command
            self.sizePercent = sizePercent
        }

        /// `key` and `command` are what make a shortcut meaningful, so a shortcut lacking either is
        /// rejected (and dropped by the lossy array decode). `id`/`name`/`sizePercent` fall back to
        /// sensible values; `sizePercent` is clamped to a window size that can actually be shown.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: RawStringKey.self)
            let key = try container.decode(String.self, forKey: RawStringKey("key"))
            let command = try container.decode(String.self, forKey: RawStringKey("command"))
            let name = (try? container.decodeIfPresent(String.self, forKey: RawStringKey("name"))) ?? command
            self.init(
                id: (try? container.decodeIfPresent(String.self, forKey: RawStringKey("id"))) ?? name,
                name: name,
                key: key,
                command: command,
                sizePercent: min(
                    max((try? container.decodeIfPresent(Int.self, forKey: RawStringKey("sizePercent"))) ?? 80, 10), 100)
            )
        }

        public static let lazygitDefault = PopupShortcut(
            id: "lazygit",
            name: "lazygit",
            key: "g",
            command: "lazygit",
            sizePercent: 80
        )
    }

    /// A polling interval that is safe to turn into a sleep: finite and at least one second. A
    /// hand-edited negative, zero or NaN value would otherwise spin the poll loop or trap converting
    /// to `UInt64` nanoseconds.
    public static func sanitizedInterval(_ seconds: Double, default fallback: Double) -> Double {
        guard seconds.isFinite else { return fallback }
        return max(seconds, 1)
    }

    /// `sanitizedInterval` as a `Task.sleep`-ready nanosecond count (capped at one day, so the
    /// multiplication can never overflow `UInt64`).
    public static func intervalNanoseconds(_ seconds: Double, default fallback: Double) -> UInt64 {
        UInt64(min(sanitizedInterval(seconds, default: fallback), 86_400) * 1_000_000_000)
    }

    public struct DiskMonitor: Codable, Equatable, Sendable {
        public var checkIntervalSeconds: Double = 60
        public var alertThresholdPercent: Double = 5.0
        public var sizeCheckIntervalSeconds: Double = 1800

        public init() {}

        // Per-key defaults, so `{"diskMonitor":{"checkIntervalSeconds":30}}` keeps the other fields
        // instead of failing the decode and resetting the whole config.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: RawStringKey.self)
            func read(_ key: String, _ fallback: Double) -> Double {
                (try? container.decodeIfPresent(Double.self, forKey: RawStringKey(key))) ?? fallback
            }
            checkIntervalSeconds = ArgusConfig.sanitizedInterval(read("checkIntervalSeconds", 60), default: 60)
            alertThresholdPercent = read("alertThresholdPercent", 5.0)
            sizeCheckIntervalSeconds = ArgusConfig.sanitizedInterval(
                read("sizeCheckIntervalSeconds", 1800), default: 1800)
        }
    }

    public struct GitHub: Codable, Equatable, Sendable {
        public var apiBaseURL: String = "https://api.github.com"
        public var token: String = ""
        public var refreshIntervalSeconds: Double = 300

        public init() {}

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: RawStringKey.self)
            func read<T: Decodable>(_ key: String, _ fallback: T) -> T {
                (try? container.decodeIfPresent(T.self, forKey: RawStringKey(key))) ?? fallback
            }
            apiBaseURL = read("apiBaseURL", "https://api.github.com")
            token = read("token", "")
            refreshIntervalSeconds = ArgusConfig.sanitizedInterval(read("refreshIntervalSeconds", 300), default: 300)
        }
    }

    /// Escape hatch for `AgentPaneDisplayWatcher` (App/) — an override for the built-in regex
    /// vocabulary `AgentStateKit.AgentPaneDisplayParser.Patterns` uses to scrape a live agent
    /// pane's on-screen state. Lives in ArgusConfigKit rather than AgentStateKit because it's
    /// plain config data with no tmux/regex knowledge of its own — ArgusConfigKit cannot import
    /// AgentStateKit (see the module layout's "no edges between those four" rule), so it's App/
    /// that merges this with `Patterns.claudeDefaults`/`.codexDefaults` at read time.
    ///
    /// Each field is nil by default (Swift's synthesized `Decodable` treats a missing JSON key as
    /// nil for an `Optional`-typed property, needing no custom decoder here) so a CLI's TUI
    /// wording can be worked around one pattern at a time without an app release, without having
    /// to restate every other pattern. An absent or empty array both mean "use the built-in
    /// default for this field" — the merge itself happens on the AgentStateKit side, which is
    /// what actually knows what "default" means for a given field.
    public struct AgentDisplayPatterns: Codable, Equatable, Sendable {
        public var claude: AgentDisplayPatternOverrides?
        public var codex: AgentDisplayPatternOverrides?

        public init(claude: AgentDisplayPatternOverrides? = nil, codex: AgentDisplayPatternOverrides? = nil) {
            self.claude = claude
            self.codex = codex
        }
    }

    /// One agent's override fields within `AgentDisplayPatterns` — a sibling of that type, rather
    /// than nested inside it, to stay within SwiftLint's one-level type-nesting limit.
    public struct AgentDisplayPatternOverrides: Codable, Equatable, Sendable {
        public var running: [String]?
        public var finished: [String]?
        public var ready: [String]?
        public var awaitingApproval: [String]?
        public var agentUI: [String]?

        public init(
            running: [String]? = nil,
            finished: [String]? = nil,
            ready: [String]? = nil,
            awaitingApproval: [String]? = nil,
            agentUI: [String]? = nil
        ) {
            self.running = running
            self.finished = finished
            self.ready = ready
            self.awaitingApproval = awaitingApproval
            self.agentUI = agentUI
        }
    }
}

@MainActor
public final class ArgusConfigStore: ObservableObject {
    public static let shared = ArgusConfigStore()

    @Published public var config = ArgusConfig()

    private static var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/argus/argus.json")
    }

    private init() {
        load()
    }

    public func load() {
        config = ArgusConfigFile.load(from: Self.configURL)
    }

    public func save() {
        ArgusConfigFile.save(config, to: Self.configURL)
    }
}

/// Decodes to `nil` instead of throwing, so an array of these keeps every well-formed element.
private struct LossyElement<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}
