import Combine
import Foundation
import Testing

@testable import AgentStateKit

@MainActor
@Suite("AgentStateBus")
struct AgentStateBusTests {
    @Test("running/waitingForApproval/done/idle payloads map to the matching state")
    func stateTransitions() {
        let bus = AgentStateBus()
        let path = "/tmp/does-not-need-to-exist"

        bus.apply(HookPayload(worktreePath: path, state: "running", agent: "claude"))
        #expect(bus.state(for: path, agent: .claude) == .running)

        bus.apply(HookPayload(worktreePath: path, state: "waitingForApproval", agent: "claude"))
        #expect(bus.state(for: path, agent: .claude) == .waitingForApproval)

        bus.apply(HookPayload(worktreePath: path, state: "done", agent: "claude"))
        #expect(bus.state(for: path, agent: .claude) == .done)

        // Any unrecognized state string (including the literal "idle") maps to .idle.
        bus.apply(HookPayload(worktreePath: path, state: "somethingUnexpected", agent: "claude"))
        #expect(bus.state(for: path, agent: .claude) == .idle)
    }

    @Test("an unknown worktree path defaults to idle for either agent")
    func unknownPathDefaultsToIdle() {
        let bus = AgentStateBus()
        #expect(bus.state(for: "/never/seen", agent: .claude) == .idle)
        #expect(bus.state(for: "/never/seen", agent: .codex) == .idle)
    }

    @Test("Claude and Codex state for the same worktree are tracked independently")
    func claudeAndCodexStatesAreIndependent() {
        let bus = AgentStateBus()
        let path = "/tmp/independent"

        bus.apply(HookPayload(worktreePath: path, state: "waitingForApproval", agent: "codex"))
        bus.apply(HookPayload(worktreePath: path, state: "running", agent: "claude"))

        #expect(bus.state(for: path, agent: .codex) == .waitingForApproval)
        #expect(bus.state(for: path, agent: .claude) == .running)
    }

    @Test("a payload with no agent field is attributed to Claude")
    func payloadWithoutAgentFieldIsAttributedToClaude() {
        let bus = AgentStateBus()
        let path = "/tmp/no-agent-field"
        bus.apply(HookPayload(worktreePath: path, state: "done", agent: nil))
        #expect(bus.state(for: path, agent: .claude) == .done)
        #expect(bus.state(for: path, agent: .codex) == .idle)
    }

    @Test("a payload from a non-agent producer is dropped, not attributed to Claude")
    func payloadFromANonAgentProducerIsIgnored() {
        let bus = AgentStateBus()
        let path = "/tmp/shell-producer"
        bus.apply(HookPayload(worktreePath: path, state: "running", agent: "shell"))
        #expect(bus.state(for: path, agent: .claude) == .idle)
        #expect(bus.state(for: path, agent: .codex) == .idle)

        bus.apply(HookPayload(worktreePath: path, state: "running", agent: "gemini"))
        #expect(bus.state(for: path, agent: .claude) == .idle)
        #expect(bus.state(for: path, agent: .codex) == .idle)
    }

    @Test("reset(for:) without an agent clears every agent for that worktree")
    func resetWithoutAgentClearsEveryAgent() {
        let bus = AgentStateBus()
        let path = "/tmp/reset-all"
        bus.apply(HookPayload(worktreePath: path, state: "done", agent: "codex"))
        bus.apply(HookPayload(worktreePath: path, state: "waitingForApproval", agent: "claude"))

        bus.reset(for: path)

        #expect(bus.state(for: path, agent: .codex) == .idle)
        #expect(bus.state(for: path, agent: .claude) == .idle)
    }

    @Test("reset(for:agent:) clears only that agent")
    func resetWithAgentClearsOnlyThatAgent() {
        let bus = AgentStateBus()
        let path = "/tmp/reset-one"
        bus.apply(HookPayload(worktreePath: path, state: "done", agent: "codex"))
        bus.apply(HookPayload(worktreePath: path, state: "running", agent: "claude"))

        bus.reset(for: path, agent: .codex)

        #expect(bus.state(for: path, agent: .codex) == .idle)
        #expect(bus.state(for: path, agent: .claude) == .running)
    }

    @Test("dismissAttentionStates leaves a running agent alone")
    func dismissAttentionStatesLeavesARunningAgentAlone() {
        let bus = AgentStateBus()
        let path = "/tmp/dismiss-leaves-running"
        bus.apply(HookPayload(worktreePath: path, state: "done", agent: "claude"))
        bus.apply(HookPayload(worktreePath: path, state: "running", agent: "codex"))

        bus.dismissAttentionStates(for: path)

        #expect(bus.state(for: path, agent: .claude) == .idle)
        #expect(bus.state(for: path, agent: .codex) == .running)
    }

    @Test("dismissAttentionStates clears waitingForApproval on every agent")
    func dismissAttentionStatesClearsWaitingForApprovalOnEveryAgent() {
        let bus = AgentStateBus()
        let path = "/tmp/dismiss-both-waiting"
        bus.apply(HookPayload(worktreePath: path, state: "waitingForApproval", agent: "claude"))
        bus.apply(HookPayload(worktreePath: path, state: "waitingForApproval", agent: "codex"))

        bus.dismissAttentionStates(for: path)

        #expect(bus.state(for: path, agent: .claude) == .idle)
        #expect(bus.state(for: path, agent: .codex) == .idle)
    }

    @Test("worktreeState reflects the higher-priority agent")
    func worktreeStateReflectsTheHigherPriorityAgent() {
        let bus = AgentStateBus()
        let path = "/tmp/worktree-aggregate"
        bus.apply(HookPayload(worktreePath: path, state: "running", agent: "claude"))
        bus.apply(HookPayload(worktreePath: path, state: "waitingForApproval", agent: "codex"))

        let worktreeState = bus.worktreeState(for: path)
        #expect(worktreeState.state == .waitingForApproval)
        #expect(worktreeState.agent == .codex)
    }

    @Test("a payload applied through a symlinked path is also visible under its canonical path")
    func canonicalPathMirroring() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-state-bus-tests-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        let real = base.appendingPathComponent("real")
        let link = base.appendingPathComponent("link")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        defer { try? FileManager.default.removeItem(at: base) }

        let bus = AgentStateBus()
        bus.apply(HookPayload(worktreePath: link.path, state: "running", agent: "claude"))

        #expect(bus.state(for: link.path, agent: .claude) == .running)
        #expect(bus.state(for: real.path, agent: .claude) == .running)
    }

    @Test("canonical mirroring is per agent: a Codex payload does not touch the canonical path's Claude slot")
    func canonicalMirroringIsPerAgent() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-state-bus-tests-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        let real = base.appendingPathComponent("real")
        let link = base.appendingPathComponent("link")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        defer { try? FileManager.default.removeItem(at: base) }

        let bus = AgentStateBus()
        bus.apply(HookPayload(worktreePath: link.path, state: "running", agent: "codex"))

        #expect(bus.state(for: real.path, agent: .codex) == .running)
        #expect(bus.state(for: real.path, agent: .claude) == .idle)
    }

    @Test("reset through the symlinked path also clears the canonical path's entry")
    func resetClearsCanonicalPathToo() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-state-bus-tests-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        let real = base.appendingPathComponent("real")
        let link = base.appendingPathComponent("link")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        defer { try? FileManager.default.removeItem(at: base) }

        let bus = AgentStateBus()
        bus.apply(HookPayload(worktreePath: link.path, state: "done", agent: "codex"))
        bus.reset(for: link.path)

        #expect(bus.state(for: link.path, agent: .codex) == .idle)
        #expect(bus.state(for: real.path, agent: .codex) == .idle)
    }

    @Test("repeated identical payloads do not republish objectWillChange")
    func repeatedIdenticalPayloadDoesNotRepublish() {
        let bus = AgentStateBus()
        let path = "/tmp/no-republish"
        var count = 0
        let cancellable = bus.objectWillChange.sink { count += 1 }
        defer { cancellable.cancel() }

        bus.apply(HookPayload(worktreePath: path, state: "running", agent: "claude"))
        bus.apply(HookPayload(worktreePath: path, state: "running", agent: "claude"))
        bus.apply(HookPayload(worktreePath: path, state: "running", agent: "claude"))

        #expect(count == 1)
    }
}
