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

enum AgentSelection: String, Codable, CaseIterable, Identifiable {
    case claude
    case codex

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        }
    }
}

enum WindowLayout: String, Codable, CaseIterable, Identifiable {
    case terminalAgent
    case agentsOverTerminal
    case terminalClaudeCodex

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .terminalAgent: "Terminal + Agent"
        case .agentsOverTerminal: "Agents / Terminal"
        case .terminalClaudeCodex: "Terminal + Claude + Codex"
        }
    }

    var toolbarIcon: String {
        switch self {
        case .terminalAgent: "rectangle.split.2x1"
        case .agentsOverTerminal: "rectangle.split.1x2"
        case .terminalClaudeCodex: "rectangle.split.3x1"
        }
    }
}

struct ArgusConfig: Codable, Equatable {
    var leaderKey = "ctrl+b"
    var leaderTimeoutSeconds = 1.5
    var keyBindings = KeyBindings()
    var agent: AgentSelection = .claude
    var layout: WindowLayout = .terminalAgent
    var claudeCommand: String = "claude --continue"
    var codexCommand: String = "codex resume --last"
    var diskMonitor = DiskMonitor()
    var github = GitHub()
    var environmentVariables: [String: String] = [:]

    // Needed because we declare a custom init(from:).
    init() {}

    // Use decodeIfPresent for every field so that keys added or renamed in future
    // versions never cause the whole config to silently fall back to defaults.
    init(from decoder: Decoder) throws {
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
    }

    private enum CodingKeys: String, CodingKey {
        case leaderKey, leaderTimeoutSeconds, keyBindings, agent, layout
        case claudeCommand, codexCommand, diskMonitor, github, environmentVariables
    }

    func launchCommand(for selection: AgentSelection) -> String {
        switch selection {
        case .claude: claudeCommand
        case .codex: codexCommand
        }
    }

    struct KeyBindings: Codable, Equatable {
        var focusPaneLeft: String = "h"
        var focusPaneRight: String = "l"
        var selectNextWorktree: String = "j"
        var selectPreviousWorktree: String = "k"
        var openLazygit: String = "g"
        var openNvim: String = "n"
        var refreshWorkspace: String = "r"
        var openMarkdownPreview: String = "m"
        var openSettings: String = ","
        var reloadAgentPane: String = "a"
        var openDiskStatus: String = "d"

        // Memberwise init needed because we declare a custom init(from:).
        init() {}

        // Decode using decodeIfPresent so that missing or renamed keys use Swift defaults
        // rather than failing the entire config load. Legacy key names are tried as fallbacks.
        init(from decoder: Decoder) throws {
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
            selectNextWorktree = read("selectNextWorktree", default: "j")
            selectPreviousWorktree = read("selectPreviousWorktree", default: "k")
            openLazygit = read("openLazygit", default: "g")
            openNvim = read("openNvim", default: "n")
            refreshWorkspace = read("refreshWorkspace", default: "r")
            openMarkdownPreview = read("openMarkdownPreview", default: "m")
            openSettings = read("openSettings", default: ",")
            reloadAgentPane = read("reloadAgentPane", default: "a")
            openDiskStatus = read("openDiskStatus", default: "d")
        }
    }

    struct DiskMonitor: Codable, Equatable {
        var checkIntervalSeconds: Double = 60
        var alertThresholdPercent: Double = 5.0
        var sizeCheckIntervalSeconds: Double = 1800
    }

    struct GitHub: Codable, Equatable {
        var apiBaseURL: String = "https://api.github.com"
        var token: String = ""
        var refreshIntervalSeconds: Double = 300
    }
}

@MainActor
final class ArgusConfigStore: ObservableObject {
    static let shared = ArgusConfigStore()

    @Published var config = ArgusConfig()

    private static var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/argus/argus.json")
    }

    private init() {
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: Self.configURL),
            let decoded = try? JSONDecoder().decode(ArgusConfig.self, from: data)
        else { return }
        config = decoded
    }

    func save() {
        let url = Self.configURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(config) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
