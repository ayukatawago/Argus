import Foundation
import Testing

@testable import ArgusConfigKit

@Suite("ArgusConfig decoding")
struct ArgusConfigTests {
    @Test("a default-constructed config round-trips through JSON")
    func defaultConfigRoundTrips() throws {
        let config = ArgusConfig()
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(ArgusConfig.self, from: data)
        #expect(decoded == config)
    }

    @Test("an empty object decodes to every field's default")
    func emptyObjectUsesDefaults() throws {
        let decoded = try decode("{}")
        #expect(decoded == ArgusConfig())
    }

    @Test("unknown keys are ignored without disturbing known siblings")
    func unknownKeysIgnored() throws {
        let decoded = try decode(
            """
            {"thisKeyDoesNotExist": 42, "agent": "codex"}
            """)
        #expect(decoded.agent == .codex)
        #expect(decoded.layout == .terminalAgent)
    }

    @Test("a wrong-typed field falls back to its default alone, siblings still decode")
    func wrongTypedFieldFallsBackAlone() throws {
        let decoded = try decode(
            """
            {"leaderTimeoutSeconds": "not a number", "agent": "codex"}
            """)
        #expect(decoded.leaderTimeoutSeconds == 1.5)
        #expect(decoded.agent == .codex)
    }

    @Test("KeyBindings falls back to legacy focusShellPane/focusAgentPane key names")
    func legacyKeyBindingNames() throws {
        let decoded = try decode(
            """
            {"keyBindings": {"focusShellPane": "j", "focusAgentPane": "k"}}
            """)
        #expect(decoded.keyBindings.focusPaneLeft == "j")
        #expect(decoded.keyBindings.focusPaneRight == "k")
    }

    @Test("the current key name wins over the legacy name when both are present")
    func currentKeyBindingNameWinsOverLegacy() throws {
        let decoded = try decode(
            """
            {"keyBindings": {"focusPaneLeft": "j", "focusShellPane": "z"}}
            """)
        #expect(decoded.keyBindings.focusPaneLeft == "j")
    }

    @Test("an explicit empty popupShortcuts array is not re-seeded with the lazygit default")
    func explicitEmptyPopupShortcutsStaysEmpty() throws {
        let decoded = try decode(
            """
            {"popupShortcuts": []}
            """)
        #expect(decoded.popupShortcuts.isEmpty)
    }

    @Test("a missing popupShortcuts key seeds the lazygit default")
    func missingPopupShortcutsSeedsLazygit() throws {
        let decoded = try decode("{}")
        #expect(decoded.popupShortcuts == [.lazygitDefault])
    }

    @Test("launchCommand(for:) maps to the matching command field")
    func launchCommandMapping() {
        var config = ArgusConfig()
        config.claudeCommand = "claude --resume"
        config.codexCommand = "codex resume --last"
        #expect(config.launchCommand(for: .claude) == "claude --resume")
        #expect(config.launchCommand(for: .codex) == "codex resume --last")
    }

    private func decode(_ json: String) throws -> ArgusConfig {
        try JSONDecoder().decode(ArgusConfig.self, from: Data(json.utf8))
    }
}
