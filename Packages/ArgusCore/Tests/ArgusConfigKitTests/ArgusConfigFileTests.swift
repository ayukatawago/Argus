import Foundation
import Testing

@testable import ArgusConfigKit

@Suite("ArgusConfigFile")
struct ArgusConfigFileTests {
    @Test("loading a missing file returns defaults")
    func missingFileReturnsDefaults() {
        let url = Self.tempURL()
        let config = ArgusConfigFile.load(from: url)
        #expect(config == ArgusConfig())
    }

    @Test("saving then loading round-trips a config")
    func roundTrips() {
        let url = Self.tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        var config = ArgusConfig()
        config.leaderKey = "cmd+k"
        config.agent = .codex
        config.claudeCommand = "claude --resume"

        ArgusConfigFile.save(config, to: url)
        let loaded = ArgusConfigFile.load(from: url)
        #expect(loaded == config)
    }

    @Test("saving creates intermediate directories")
    func createsIntermediateDirectories() {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("argus-config-file-tests-\(UUID().uuidString)")
        let url = base.appendingPathComponent("nested/deeper/argus.json")
        defer { try? FileManager.default.removeItem(at: base) }

        ArgusConfigFile.save(ArgusConfig(), to: url)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test("loading malformed JSON returns defaults rather than throwing")
    func malformedJSONReturnsDefaults() throws {
        let url = Self.tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not valid json".utf8).write(to: url)

        let config = ArgusConfigFile.load(from: url)
        #expect(config == ArgusConfig())
    }

    private static func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("argus-config-file-tests-\(UUID().uuidString).json")
    }
}
