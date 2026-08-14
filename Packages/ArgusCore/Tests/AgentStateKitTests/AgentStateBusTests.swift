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
        #expect(bus.state(for: path) == .running)

        bus.apply(HookPayload(worktreePath: path, state: "waitingForApproval", agent: "claude"))
        #expect(bus.state(for: path) == .waitingForApproval)

        bus.apply(HookPayload(worktreePath: path, state: "done", agent: "claude"))
        #expect(bus.state(for: path) == .done)

        // Any unrecognized state string (including the literal "idle") maps to .idle.
        bus.apply(HookPayload(worktreePath: path, state: "somethingUnexpected", agent: "claude"))
        #expect(bus.state(for: path) == .idle)
    }

    @Test("an unknown worktree path defaults to idle")
    func unknownPathDefaultsToIdle() {
        let bus = AgentStateBus()
        #expect(bus.state(for: "/never/seen") == .idle)
    }

    @Test("agent \"codex\" maps to AgentType.codex, anything else maps to .claude")
    func agentTypeInference() {
        let bus = AgentStateBus()
        bus.apply(HookPayload(worktreePath: "/tmp/a", state: "running", agent: "codex"))
        #expect(bus.agentType(for: "/tmp/a") == .codex)

        bus.apply(HookPayload(worktreePath: "/tmp/b", state: "running", agent: "claude"))
        #expect(bus.agentType(for: "/tmp/b") == .claude)

        bus.apply(HookPayload(worktreePath: "/tmp/c", state: "running", agent: nil))
        #expect(bus.agentType(for: "/tmp/c") == .claude)

        bus.apply(HookPayload(worktreePath: "/tmp/d", state: "running", agent: "shell"))
        #expect(bus.agentType(for: "/tmp/d") == .claude)
    }

    @Test("an unknown worktree path defaults to AgentType.claude")
    func unknownPathDefaultsToClaudeAgentType() {
        let bus = AgentStateBus()
        #expect(bus.agentType(for: "/never/seen") == .claude)
    }

    @Test("setAgentType overrides the type independent of any hook payload")
    func setAgentTypeOverride() {
        let bus = AgentStateBus()
        bus.setAgentType(.codex, for: "/tmp/e")
        #expect(bus.agentType(for: "/tmp/e") == .codex)
    }

    @Test("reset returns both state and agent type to their defaults")
    func resetRestoresDefaults() {
        let bus = AgentStateBus()
        bus.apply(HookPayload(worktreePath: "/tmp/f", state: "done", agent: "codex"))
        #expect(bus.state(for: "/tmp/f") == .done)
        #expect(bus.agentType(for: "/tmp/f") == .codex)

        bus.reset(for: "/tmp/f")
        #expect(bus.state(for: "/tmp/f") == .idle)
        #expect(bus.agentType(for: "/tmp/f") == .claude)
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

        #expect(bus.state(for: link.path) == .running)
        #expect(bus.state(for: real.path) == .running)
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

        #expect(bus.state(for: link.path) == .idle)
        #expect(bus.state(for: real.path) == .idle)
    }
}
