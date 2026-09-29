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

    @Test("a dropped layout raw value (terminalClaudeCodex) falls back to terminalAgent")
    func droppedLayoutValueFallsBackToTerminalAgent() throws {
        let decoded = try decode(
            """
            {"layout": "terminalClaudeCodex"}
            """)
        #expect(decoded.layout == .terminalAgent)
    }

    @Test("agentPaneMode defaults to full and decodes split, falling back to full on garbage")
    func agentPaneModeDecoding() throws {
        #expect(try decode("{}").agentPaneMode == .full)
        #expect(try decode(#"{"agentPaneMode": "split"}"#).agentPaneMode == .split)
        #expect(try decode(#"{"agentPaneMode": "nonsense"}"#).agentPaneMode == .full)
    }

    // MARK: - agentDisplayPatterns

    @Test("a missing agentDisplayPatterns key decodes to nil claude/codex overrides")
    func missingAgentDisplayPatternsDecodesToDefault() throws {
        let decoded = try decode("{}")
        #expect(decoded.agentDisplayPatterns.claude == nil)
        #expect(decoded.agentDisplayPatterns.codex == nil)
    }

    @Test("a partial claude override decodes only the fields present, leaving the rest nil")
    func partialClaudeOverrideDecodesOnlyPresentFields() throws {
        let decoded = try decode(
            """
            {"agentDisplayPatterns": {"claude": {"running": ["…\\\\(\\\\d+[hms]"]}}}
            """)
        #expect(decoded.agentDisplayPatterns.claude?.running == ["…\\(\\d+[hms]"])
        #expect(decoded.agentDisplayPatterns.claude?.finished == nil)
        #expect(decoded.agentDisplayPatterns.codex == nil)
    }

    @Test("a full agentDisplayPatterns round-trips through JSON for both agents")
    func fullAgentDisplayPatternsRoundTrips() throws {
        var config = ArgusConfig()
        config.agentDisplayPatterns = ArgusConfig.AgentDisplayPatterns(
            claude: ArgusConfig.AgentDisplayPatternOverrides(running: ["a"], finished: ["b"]),
            codex: ArgusConfig.AgentDisplayPatternOverrides(ready: ["c"], awaitingApproval: ["d"], agentUI: ["e"])
        )
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(ArgusConfig.self, from: data)
        #expect(decoded == config)
    }

    // MARK: - projectAgents

    @Test("a missing projectAgents key decodes to an empty map")
    func missingProjectAgentsDecodesToEmpty() throws {
        let decoded = try decode("{}")
        #expect(decoded.projectAgents.isEmpty)
    }

    @Test("an unrecognized projectAgents value drops only that entry")
    func unrecognizedProjectAgentValueDropsOnlyThatEntry() throws {
        let decoded = try decode(
            """
            {"projectAgents": {"/repos/a": "codex", "/repos/b": "nonsense"}}
            """)
        #expect(decoded.projectAgents == ["/repos/a": .codex])
    }

    @Test("agent(forProjectPath:) resolves the override, else the global default")
    func agentForProjectPathResolution() {
        var config = ArgusConfig()
        config.agent = .claude
        config.projectAgents["/repos/a"] = .codex

        #expect(config.agent(forProjectPath: "/repos/a") == .codex)
        #expect(config.agent(forProjectPath: "/repos/unmapped") == .claude)
        #expect(config.agent(forProjectPath: nil) == .claude)
    }

    @Test("setAgent(nil, forProjectPath:) clears an existing override")
    func setAgentNilClearsOverride() {
        var config = ArgusConfig()
        config.setAgent(.codex, forProjectPath: "/repos/a")
        #expect(config.projectAgents["/repos/a"] == .codex)

        config.setAgent(nil, forProjectPath: "/repos/a")
        #expect(config.projectAgents["/repos/a"] == nil)
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
