import Foundation
import Testing

@testable import AgentStateKit

@Suite("AgentStateKit smoke test")
struct AgentStateKitSmokeTests {
    @Test("HookPayload decodes a hook script's JSON line")
    func decodesHookPayload() throws {
        let json = Data(#"{"worktreePath":"/tmp/repo","state":"running","agent":"claude"}"#.utf8)
        let payload = try JSONDecoder().decode(HookPayload.self, from: json)
        #expect(payload.worktreePath == "/tmp/repo")
        #expect(payload.state == "running")
        #expect(payload.agent == "claude")
    }

    @Test("HookPayload decodes a payload with no agent field at all")
    func decodesHookPayloadWithoutAgentField() throws {
        let json = Data(#"{"worktreePath":"/tmp/repo","state":"done"}"#.utf8)
        let payload = try JSONDecoder().decode(HookPayload.self, from: json)
        #expect(payload.agent == nil)
    }
}
