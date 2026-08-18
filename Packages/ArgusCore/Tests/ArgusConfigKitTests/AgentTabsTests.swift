import Testing

@testable import ArgusConfigKit

@Suite("AgentTabs")
struct AgentTabsTests {
    @Test("init seeds exactly the default agent's tab, active")
    func initSeedsDefaultAgent() {
        let claude = AgentTabs(defaultAgent: .claude)
        #expect(claude.open == [.claude])
        #expect(claude.active == .claude)
        #expect(claude.closed == .codex)

        let codex = AgentTabs(defaultAgent: .codex)
        #expect(codex.open == [.codex])
        #expect(codex.active == .codex)
        #expect(codex.closed == .claude)
    }

    @Test("open yields canonical [claude, codex] order regardless of which opened first")
    func openIsCanonicallyOrdered() {
        var fromClaude = AgentTabs(defaultAgent: .claude)
        fromClaude.open(.codex)
        #expect(fromClaude.open == [.claude, .codex])

        var fromCodex = AgentTabs(defaultAgent: .codex)
        fromCodex.open(.claude)
        #expect(fromCodex.open == [.claude, .codex])
    }

    @Test("open activates the newly opened tab")
    func openActivatesTheNewTab() {
        var tabs = AgentTabs(defaultAgent: .claude)
        let changed = tabs.open(.codex)
        #expect(changed)
        #expect(tabs.active == .codex)
    }

    @Test("opening an already-open tab returns false but still activates it")
    func openingAlreadyOpenTabStillActivates() {
        var tabs = AgentTabs(defaultAgent: .claude)
        tabs.open(.codex)
        tabs.activate(.codex)
        #expect(tabs.active == .codex)

        let changed = tabs.open(.claude)
        #expect(!changed)
        #expect(tabs.active == .claude)
    }

    @Test("closing the active tab with both open moves active to the survivor")
    func closeActiveMovesToSurvivor() {
        var tabs = AgentTabs(defaultAgent: .claude)
        tabs.open(.codex)
        let survivor = tabs.close(.codex)
        #expect(survivor == .claude)
        #expect(tabs.open == [.claude])
        #expect(tabs.active == .claude)
    }

    @Test("closing the non-active tab leaves active alone")
    func closeNonActiveLeavesActiveAlone() {
        var tabs = AgentTabs(defaultAgent: .claude)
        tabs.open(.codex)
        tabs.activate(.codex)
        let survivor = tabs.close(.claude)
        #expect(survivor == .codex)
        #expect(tabs.active == .codex)
        #expect(tabs.open == [.codex])
    }

    @Test("closing the last open tab is refused")
    func closeLastTabIsRefused() {
        var tabs = AgentTabs(defaultAgent: .claude)
        let result = tabs.close(.claude)
        #expect(result == nil)
        #expect(tabs.open == [.claude])
        #expect(tabs.active == .claude)
    }

    @Test("activateRelative wraps with two tabs open and no-ops with one")
    func activateRelativeWraps() {
        var tabs = AgentTabs(defaultAgent: .claude)
        tabs.open(.codex)
        tabs.activate(.claude)

        var changed = tabs.activateRelative(1)
        #expect(changed)
        #expect(tabs.active == .codex)

        changed = tabs.activateRelative(1)
        #expect(changed)
        #expect(tabs.active == .claude)

        changed = tabs.activateRelative(-1)
        #expect(changed)
        #expect(tabs.active == .codex)

        var single = AgentTabs(defaultAgent: .claude)
        let singleChanged = single.activateRelative(1)
        #expect(!singleChanged)
        #expect(single.active == .claude)
    }

    @Test("closed is nil when both tabs are open")
    func closedIsNilWhenBothOpen() {
        var tabs = AgentTabs(defaultAgent: .claude)
        tabs.open(.codex)
        #expect(tabs.closed == nil)
    }
}
