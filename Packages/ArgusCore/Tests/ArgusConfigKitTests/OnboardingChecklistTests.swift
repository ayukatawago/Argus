import Foundation
import Testing

@testable import ArgusConfigKit

@Suite("OnboardingChecklist")
struct OnboardingChecklistTests {
    @Test("executable is the first token of the command")
    func firstToken() {
        #expect(OnboardingChecklist.executable(fromCommand: "claude --continue") == "claude")
        #expect(OnboardingChecklist.executable(fromCommand: "  codex   resume ") == "codex")
    }

    @Test("leading env assignments are skipped")
    func skipsEnvAssignments() {
        #expect(OnboardingChecklist.executable(fromCommand: "FOO=1 BAR=x claude -p") == "claude")
    }

    @Test("a path containing '=' is still an executable")
    func pathWithEquals() {
        #expect(OnboardingChecklist.executable(fromCommand: "/opt/a=b/claude --continue") == "/opt/a=b/claude")
    }

    @Test("a blank command has no executable")
    func blankCommand() {
        #expect(OnboardingChecklist.executable(fromCommand: "   ") == nil)
        #expect(OnboardingChecklist.executable(fromCommand: "") == nil)
    }

    @Test("only the default agent's CLI is required")
    func requiredFollowsDefaultAgent() {
        var config = ArgusConfig()
        config.agent = .codex
        let steps = OnboardingChecklist.steps(config: config, foundExecutables: ["claude"])
        #expect(steps.first { $0.id == "agent-claude" }?.isRequired == false)
        #expect(steps.first { $0.id == "agent-codex" }?.isRequired == true)
        #expect(OnboardingChecklist.isReady(steps) == false)
    }

    @Test("ready once the default agent's CLI is found, token optional")
    func readyWithoutToken() {
        let config = ArgusConfig()
        let steps = OnboardingChecklist.steps(config: config, foundExecutables: ["claude"])
        #expect(OnboardingChecklist.isReady(steps))
        #expect(steps.first { $0.id == "github-token" }?.isComplete == false)
    }

    @Test("a token marks the GitHub step complete")
    func tokenComplete() {
        var config = ArgusConfig()
        config.github.token = "ghp_x"
        let steps = OnboardingChecklist.steps(config: config, foundExecutables: [])
        #expect(steps.first { $0.id == "github-token" }?.isComplete == true)
    }

    @Test("onboardingDismissed defaults to false and round-trips")
    func dismissedFlag() throws {
        #expect(ArgusConfig().onboardingDismissed == false)
        var config = ArgusConfig()
        config.onboardingDismissed = true
        let data = try JSONEncoder().encode(config)
        #expect(try JSONDecoder().decode(ArgusConfig.self, from: data).onboardingDismissed)
    }
}
