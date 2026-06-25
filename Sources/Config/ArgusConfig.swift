import Combine
import Foundation

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

struct ArgusConfig: Codable, Equatable {
    var leaderKey = "ctrl+b"
    var leaderTimeoutSeconds = 1.5
    var keyBindings = KeyBindings()
    var agent: AgentSelection = .claude
    var claudeCommand: String = "claude --continue"
    var codexCommand: String = "codex resume --last"
    var diskMonitor = DiskMonitor()

    func launchCommand(for selection: AgentSelection) -> String {
        switch selection {
        case .claude: claudeCommand
        case .codex: codexCommand
        }
    }

    struct KeyBindings: Codable, Equatable {
        var focusShellPane: String = "h"
        var focusAgentPane: String = "l"
        var selectNextWorktree: String = "j"
        var selectPreviousWorktree: String = "k"
        var openLazygit: String = "g"
        var openNvim: String = "n"
        var refreshWorkspace: String = "r"
        var openMarkdownPreview: String = "m"
        var openSettings: String = ","
        var reloadAgentPane: String = "a"
        var openDiskStatus: String = "d"
    }

    struct DiskMonitor: Codable, Equatable {
        var checkIntervalSeconds: Double = 60
        var alertThresholdPercent: Double = 5.0
        var sizeCheckIntervalSeconds: Double = 300
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
