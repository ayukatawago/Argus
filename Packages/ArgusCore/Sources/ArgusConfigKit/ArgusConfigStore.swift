import Combine
import Foundation

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
