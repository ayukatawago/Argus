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
    case terminalClaudeCodex

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .terminalAgent: "Terminal + Agent"
        case .agentsOverTerminal: "Agents / Terminal"
        case .terminalClaudeCodex: "Terminal + Claude + Codex"
        }
    }

    public var toolbarIcon: String {
        switch self {
        case .terminalAgent: "rectangle.split.2x1"
        case .agentsOverTerminal: "rectangle.split.1x2"
        case .terminalClaudeCodex: "rectangle.split.3x1"
        }
    }
}

public struct ArgusConfig: Codable, Equatable, Sendable {
    public var leaderKey = "ctrl+b"
    public var leaderTimeoutSeconds = 1.5
    public var keyBindings = KeyBindings()
    public var agent: AgentSelection = .claude
    public var layout: WindowLayout = .terminalAgent
    public var claudeCommand: String = "claude --continue"
    public var codexCommand: String = "codex resume --last"
    public var diskMonitor = DiskMonitor()
    public var github = GitHub()
    public var environmentVariables: [String: String] = [:]
    public var popupShortcuts: [PopupShortcut] = [.lazygitDefault]

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
        claudeCommand = (try? container.decodeIfPresent(String.self, forKey: .claudeCommand)) ?? "claude --continue"
        codexCommand = (try? container.decodeIfPresent(String.self, forKey: .codexCommand)) ?? "codex resume --last"
        diskMonitor = (try? container.decodeIfPresent(DiskMonitor.self, forKey: .diskMonitor)) ?? DiskMonitor()
        github = (try? container.decodeIfPresent(GitHub.self, forKey: .github)) ?? GitHub()
        environmentVariables =
            (try? container.decodeIfPresent([String: String].self, forKey: .environmentVariables)) ?? [:]
        popupShortcuts =
            (try? container.decodeIfPresent([PopupShortcut].self, forKey: .popupShortcuts)) ?? [.lazygitDefault]
    }

    private enum CodingKeys: String, CodingKey {
        case leaderKey, leaderTimeoutSeconds, keyBindings, agent, layout
        case claudeCommand, codexCommand, diskMonitor, github, environmentVariables, popupShortcuts
    }

    public func launchCommand(for selection: AgentSelection) -> String {
        switch selection {
        case .claude: claudeCommand
        case .codex: codexCommand
        }
    }

    public struct KeyBindings: Codable, Equatable, Sendable {
        public var focusPaneLeft: String = "h"
        public var focusPaneRight: String = "l"
        public var selectNextWorktree: String = "n"
        public var selectPreviousWorktree: String = "p"
        public var openNvim: String = "v"
        public var refreshWorkspace: String = "r"
        public var openMarkdownPreview: String = "m"
        public var openSettings: String = ","
        public var reloadAgentPane: String = "a"
        public var openDiskStatus: String = "d"
        public var openDiffReview: String = "w"
        public var newTerminalTab: String = "t"
        public var nextTerminalTab: String = "]"
        public var previousTerminalTab: String = "["
        public var closeTerminalTab: String = "x"

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
            focusPaneLeft = read("focusPaneLeft", legacy: "focusShellPane", default: "h")
            focusPaneRight = read("focusPaneRight", legacy: "focusAgentPane", default: "l")
            selectNextWorktree = read("selectNextWorktree", default: "n")
            selectPreviousWorktree = read("selectPreviousWorktree", default: "p")
            openNvim = read("openNvim", default: "v")
            refreshWorkspace = read("refreshWorkspace", default: "r")
            openMarkdownPreview = read("openMarkdownPreview", default: "m")
            openSettings = read("openSettings", default: ",")
            reloadAgentPane = read("reloadAgentPane", default: "a")
            openDiskStatus = read("openDiskStatus", default: "d")
            openDiffReview = read("openDiffReview", default: "w")
            newTerminalTab = read("newTerminalTab", default: "t")
            nextTerminalTab = read("nextTerminalTab", default: "]")
            previousTerminalTab = read("previousTerminalTab", default: "[")
            closeTerminalTab = read("closeTerminalTab", default: "x")
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

        public static let lazygitDefault = PopupShortcut(
            id: "lazygit",
            name: "lazygit",
            key: "g",
            command: "lazygit",
            sizePercent: 80
        )
    }

    public struct DiskMonitor: Codable, Equatable, Sendable {
        public var checkIntervalSeconds: Double = 60
        public var alertThresholdPercent: Double = 5.0
        public var sizeCheckIntervalSeconds: Double = 1800

        public init() {}
    }

    public struct GitHub: Codable, Equatable, Sendable {
        public var apiBaseURL: String = "https://api.github.com"
        public var token: String = ""
        public var refreshIntervalSeconds: Double = 300

        public init() {}
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
