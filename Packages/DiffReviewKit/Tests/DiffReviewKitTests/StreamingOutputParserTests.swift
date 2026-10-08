import Foundation
import Testing

@testable import DiffReviewKit

private func texts(_ events: [AgentEvent]) -> [String] {
    events.compactMap { if case .text(let text) = $0 { text } else { nil } }
}

private func sessionIDs(_ events: [AgentEvent]) -> [String] {
    events.compactMap { if case .sessionID(let id) = $0 { id } else { nil } }
}

@Suite("StreamingOutputParser")
struct StreamingOutputParserTests {
    @Test("Claude: assistant text streams, and the final result is not duplicated")
    func claudeNoDuplicate() {
        var parser = StreamingOutputParser(kind: .claude)
        var events: [AgentEvent] = []
        events += parser.consumeLine(#"{"type":"system","session_id":"s1"}"#)
        let assistant = #"{"type":"assistant","session_id":"s1","message":{"content":"#
            + #"[{"type":"text","text":"Hello"},{"type":"tool_use","id":"x"}]}}"#
        events += parser.consumeLine(assistant)
        events += parser.consumeLine(#"{"type":"result","session_id":"s1","result":"Hello"}"#)
        #expect(texts(events) == ["Hello"])
        #expect(sessionIDs(events) == ["s1", "s1", "s1"])
    }

    @Test("Claude: result text is used when no assistant text was streamed")
    func claudeResultFallback() {
        var parser = StreamingOutputParser(kind: .claude)
        let events = parser.consumeLine(#"{"type":"result","result":"Only result"}"#)
        #expect(texts(events) == ["Only result"])
    }

    @Test("Claude: non-JSON lines fall back to raw text and empty lines are ignored")
    func claudeRaw() {
        var parser = StreamingOutputParser(kind: .claude)
        #expect(texts(parser.consumeLine("plain output")) == ["plain output"])
        #expect(parser.consumeLine("").isEmpty)
    }

    @Test("Codex: thread_id and item.text of an agent message are read")
    func codexItems() {
        var parser = StreamingOutputParser(kind: .codex)
        #expect(sessionIDs(parser.consumeLine(#"{"type":"thread.started","thread_id":"t-9"}"#)) == ["t-9"])
        let message = #"{"type":"item.completed","item":{"id":"i","type":"agent_message","text":"Done"}}"#
        let reply = parser.consumeLine(message)
        #expect(texts(reply) == ["Done"])
        let thought = #"{"type":"item.completed","item":{"type":"reasoning","text":"thinking"}}"#
        let reasoning = parser.consumeLine(thought)
        #expect(texts(reasoning).isEmpty)
    }

    @Test("Codex: legacy top-level fields still work")
    func codexLegacy() {
        var parser = StreamingOutputParser(kind: .codex)
        let events = parser.consumeLine(#"{"conversation_id":"c1","message":"hi"}"#)
        #expect(sessionIDs(events) == ["c1"])
        #expect(texts(events) == ["hi"])
    }
}

@Suite("AgentRunner command construction")
struct AgentRunnerShellEscapeTests {
    @Test("shellEscape single-quotes and escapes embedded quotes")
    func escape() {
        #expect(AgentRunner.shellEscape("plain") == "'plain'")
        #expect(AgentRunner.shellEscape("it's") == #"'it'\''s'"#)
        #expect(AgentRunner.shellEscape("$(rm -rf /) `x` \"q\"") == "'$(rm -rf /) `x` \"q\"'")
        #expect(AgentRunner.shellEscape("") == "''")
    }

    @Test("the escaped value round-trips through /bin/sh")
    func roundTrip() throws {
        let nasty = "a'b\"c $HOME `id` \\ \n end"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "printf %s \(AgentRunner.shellEscape(nasty))"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(String(decoding: data, as: UTF8.self) == nasty)
    }
}
