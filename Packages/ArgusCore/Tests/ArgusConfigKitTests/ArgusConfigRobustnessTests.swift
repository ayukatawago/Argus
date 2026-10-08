import Foundation
import Testing

@testable import ArgusConfigKit

@Suite("ArgusConfig decoding robustness")
struct ArgusConfigRobustnessTests {
    private func decode(_ json: String) throws -> ArgusConfig {
        try JSONDecoder().decode(ArgusConfig.self, from: Data(json.utf8))
    }

    @Test("a partial diskMonitor object keeps its other fields at defaults and does not reset the config")
    func partialDiskMonitor() throws {
        let config = try decode(#"{"leaderKey":"ctrl+a","diskMonitor":{"checkIntervalSeconds":30}}"#)
        #expect(config.leaderKey == "ctrl+a")
        #expect(config.diskMonitor.checkIntervalSeconds == 30)
        #expect(config.diskMonitor.alertThresholdPercent == 5.0)
        #expect(config.diskMonitor.sizeCheckIntervalSeconds == 1800)
    }

    @Test("a partial github object keeps defaults for what is missing")
    func partialGitHub() throws {
        let config = try decode(#"{"github":{"token":"abc"}}"#)
        #expect(config.github.token == "abc")
        #expect(config.github.apiBaseURL == "https://api.github.com")
        #expect(config.github.refreshIntervalSeconds == 300)
    }

    @Test("a malformed popup shortcut drops only itself")
    func lossyPopupShortcuts() throws {
        let json = """
            {"popupShortcuts":[
              {"id":"a","name":"A","key":"a","command":"cmd-a","sizePercent":60},
              {"id":"broken","name":"B"},
              {"key":"c","command":"cmd-c"}
            ]}
            """
        let shortcuts = try decode(json).popupShortcuts
        #expect(shortcuts.map(\.command) == ["cmd-a", "cmd-c"])
        #expect(shortcuts[1].sizePercent == 80)
        #expect(shortcuts[1].name == "cmd-c")
    }

    @Test("an explicitly empty popupShortcuts array stays empty; a non-array falls back to the default")
    func emptyVersusInvalid() throws {
        #expect(try decode(#"{"popupShortcuts":[]}"#).popupShortcuts.isEmpty)
        #expect(try decode(#"{"popupShortcuts":"nope"}"#).popupShortcuts == [.lazygitDefault])
    }

    @Test("a popup size outside 10...100 is clamped")
    func sizeClamped() throws {
        let json =
            #"{"popupShortcuts":[{"key":"a","command":"x","sizePercent":500},{"key":"b","command":"y","sizePercent":-3}]}"#
        #expect(try decode(json).popupShortcuts.map(\.sizePercent) == [100, 10])
    }

    @Test("negative, zero and non-finite intervals are clamped to at least one second")
    func intervalClamped() throws {
        let config = try decode(
            #"{"diskMonitor":{"checkIntervalSeconds":-5,"sizeCheckIntervalSeconds":0},"github":{"refreshIntervalSeconds":-1}}"#
        )
        #expect(config.diskMonitor.checkIntervalSeconds == 1)
        #expect(config.diskMonitor.sizeCheckIntervalSeconds == 1)
        #expect(config.github.refreshIntervalSeconds == 1)
        #expect(ArgusConfig.sanitizedInterval(.nan, default: 60) == 60)
        #expect(ArgusConfig.sanitizedInterval(.infinity, default: 60) == 60)
    }

    @Test("intervalNanoseconds never traps and is capped at one day")
    func nanoseconds() {
        #expect(ArgusConfig.intervalNanoseconds(2, default: 60) == 2_000_000_000)
        #expect(ArgusConfig.intervalNanoseconds(-9, default: 60) == 1_000_000_000)
        #expect(ArgusConfig.intervalNanoseconds(.nan, default: 60) == 60_000_000_000)
        #expect(ArgusConfig.intervalNanoseconds(1e30, default: 60) == 86_400_000_000_000)
    }

    @Test("loading an undecodable argus.json backs it up before falling back to defaults")
    func corruptFileIsBackedUp() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("argus-cfg-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("argus.json")
        try Data("{ // hand-edited, with a comment\n}".utf8).write(to: url)

        #expect(ArgusConfigFile.load(from: url) == ArgusConfig())
        let backups = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.contains(".corrupt-") }
        #expect(backups.count == 1)
    }

    @Test("decoding an empty object yields exactly the default config (decoder and declarations agree)")
    func emptyObjectIsDefault() throws {
        #expect(try decode("{}") == ArgusConfig())
        #expect(try decode(#"{"keyBindings":{}}"#).keyBindings == ArgusConfig.KeyBindings())
    }

    @Test("legacy key-binding names still populate the renamed fields, and new names win")
    func legacyKeyBindings() throws {
        let legacy = try decode(#"{"keyBindings":{"focusShellPane":"<","focusAgentPane":">"}}"#)
        #expect(legacy.keyBindings.focusPaneLeft == "<")
        #expect(legacy.keyBindings.focusPaneRight == ">")
        let both = try decode(#"{"keyBindings":{"focusShellPane":"<","focusPaneLeft":"("}}"#)
        #expect(both.keyBindings.focusPaneLeft == "(")
    }

    @Test("a wrong-typed value for one field falls back for that field only")
    func wrongTypeIsolated() throws {
        let config = try decode(#"{"leaderKey":42,"claudeCommand":"claude -c"}"#)
        #expect(config.leaderKey == ArgusConfig().leaderKey)
        #expect(config.claudeCommand == "claude -c")
    }

    @Test("an unknown project agent value drops only that entry")
    func unknownProjectAgent() throws {
        let config = try decode(#"{"projectAgents":{"/a":"codex","/b":"gemini"}}"#)
        #expect(config.projectAgents == ["/a": .codex])
    }
}
