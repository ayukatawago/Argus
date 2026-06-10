import Combine
import Foundation

struct KottyConfig: Codable, Equatable {
    var leaderKey = "ctrl+b"
    var leaderTimeoutSeconds = 1.5
    var keyBindings = KeyBindings()

    struct KeyBindings: Codable, Equatable {
        var focusShellPane: String = "h"
        var focusAgentPane: String = "l"
        var selectNextWorktree: String = "j"
        var selectPreviousWorktree: String = "k"
        var openLazygit: String = "g"
        var refreshWorkspace: String = "r"
        var openMarkdownPreview: String = "m"
        var openSettings: String = ","
    }
}

@MainActor
final class KottyConfigStore: ObservableObject {
    static let shared = KottyConfigStore()

    @Published var config = KottyConfig()

    private static var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/kotty/kotty.json")
    }

    private init() {
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: Self.configURL),
            let decoded = try? JSONDecoder().decode(KottyConfig.self, from: data)
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
