import Testing

@testable import AgentStateKit

@Suite("VanishDebouncer")
struct VanishDebouncerTests {
    @Test("a key that has never been seen is neither missing nor vanished")
    func neverSeen() {
        var debouncer = VanishDebouncer<String>(threshold: 2)
        #expect(debouncer.update(found: []) == .init(stillMissing: [], vanished: []))
    }

    @Test("a single miss is a grace period; the second consecutive miss is gone")
    func twoMissesVanish() {
        var debouncer = VanishDebouncer<String>(threshold: 2)
        _ = debouncer.update(found: ["a"])
        #expect(debouncer.update(found: []) == .init(stillMissing: ["a"], vanished: []))
        #expect(debouncer.update(found: []) == .init(stillMissing: [], vanished: ["a"]))
    }

    @Test("reappearing during the grace period resets the streak")
    func reappearResets() {
        var debouncer = VanishDebouncer<String>(threshold: 2)
        _ = debouncer.update(found: ["a"])
        _ = debouncer.update(found: [])
        _ = debouncer.update(found: ["a"])
        // Missed once, came back, missed once again: still only one miss in a row.
        #expect(debouncer.update(found: []) == .init(stillMissing: ["a"], vanished: []))
    }

    @Test("a vanished key is reported once and then forgotten")
    func reportedOnce() {
        var debouncer = VanishDebouncer<String>(threshold: 1)
        _ = debouncer.update(found: ["a"])
        #expect(debouncer.update(found: []).vanished == ["a"])
        #expect(debouncer.update(found: []) == .init(stillMissing: [], vanished: []))
    }

    @Test("keys are tracked independently")
    func independent() {
        var debouncer = VanishDebouncer<String>(threshold: 2)
        _ = debouncer.update(found: ["a", "b"])
        #expect(debouncer.update(found: ["b"]) == .init(stillMissing: ["a"], vanished: []))
        #expect(debouncer.update(found: ["b"]) == .init(stillMissing: [], vanished: ["a"]))
    }

    @Test("a threshold below one is treated as one")
    func clampedThreshold() {
        var debouncer = VanishDebouncer<String>(threshold: 0)
        _ = debouncer.update(found: ["a"])
        #expect(debouncer.update(found: []).vanished == ["a"])
    }

    @Test("reset returns the covered keys (including ones in their grace period) and clears state")
    func reset() {
        var debouncer = VanishDebouncer<String>(threshold: 3)
        _ = debouncer.update(found: ["a", "b"])
        _ = debouncer.update(found: ["b"])
        #expect(debouncer.reset() == ["a", "b"])
        #expect(debouncer.reset().isEmpty)
        #expect(debouncer.update(found: []) == .init(stillMissing: [], vanished: []))
    }
}

@Suite("Patterns.overriding")
struct PatternsOverridingTests {
    private let base = AgentPaneDisplayParser.Patterns.claudeDefaults

    @Test("nil and empty overrides keep every built-in pattern")
    func keepsDefaults() {
        let merged = base.overriding(running: nil, finished: [], ready: nil, awaitingApproval: [], agentUI: nil)
        #expect(merged.running == base.running)
        #expect(merged.finished == base.finished)
        #expect(merged.awaitingApproval == base.awaitingApproval)
        #expect(merged.agentUI == base.agentUI)
    }

    @Test("a non-empty override replaces only its own field")
    func replacesOneField() {
        let merged = base.overriding(
            running: ["new-running"], finished: nil, ready: nil, awaitingApproval: nil, agentUI: nil)
        #expect(merged.running == ["new-running"])
        #expect(merged.finished == base.finished)
        #expect(merged.ready == base.ready)
    }
}
