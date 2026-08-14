import Testing

@testable import AgentStateKit

@Suite("CodexSessionParser")
struct CodexSessionParserTests {
    // MARK: - extractCwd

    @Test("extracts cwd from a realistic 512-byte session_meta header")
    func extractsCwdFromRealisticHeader() {
        let header = #"{"type":"session_meta","payload":{"id":"abc123","cwd":"/Users/taku/workspace/app/Argus","#
        let padding = String(repeating: "x", count: max(0, 512 - header.count))
        let text = header + padding
        #expect(CodexSessionParser.extractCwd(from: text) == "/Users/taku/workspace/app/Argus")
    }

    @Test("returns nil when there's no cwd key at all")
    func missingCwdKeyReturnsNil() {
        #expect(CodexSessionParser.extractCwd(from: #"{"type":"session_meta","payload":{"id":"abc"}}"#) == nil)
    }

    @Test("returns nil for an empty cwd value")
    func emptyCwdValueReturnsNil() {
        #expect(CodexSessionParser.extractCwd(from: #"{"cwd":""}"#) == nil)
    }

    @Test("returns nil when the closing quote is missing (truncated header)")
    func unterminatedCwdReturnsNil() {
        #expect(CodexSessionParser.extractCwd(from: #"{"cwd":"/Users/taku/trunc"#) == nil)
    }

    // MARK: - inferState

    @Test("the last task_complete wins over an earlier task_started")
    func lastTaskCompleteWins() {
        let tail = """
            {"type":"event_msg","payload":{"type":"task_started"}}
            {"type":"event_msg","payload":{"type":"task_complete"}}
            """
        #expect(CodexSessionParser.inferState(from: tail) == "done")
    }

    @Test("the last task_started wins over an earlier task_complete")
    func lastTaskStartedWins() {
        let tail = """
            {"type":"event_msg","payload":{"type":"task_complete"}}
            {"type":"event_msg","payload":{"type":"task_started"}}
            """
        #expect(CodexSessionParser.inferState(from: tail) == "running")
    }

    @Test("turn_aborted maps to done")
    func turnAbortedMapsToDone() {
        let tail = #"{"type":"event_msg","payload":{"type":"turn_aborted"}}"#
        #expect(CodexSessionParser.inferState(from: tail) == "done")
    }

    @Test("no event_msg lines at all defaults to running")
    func noEventMsgDefaultsToRunning() {
        let tail = #"{"type":"something_else","payload":{}}"#
        #expect(CodexSessionParser.inferState(from: tail) == "running")
    }

    @Test("an unrecognized event type is skipped in favor of an earlier recognized one")
    func unrecognizedEventTypeIsSkipped() {
        let tail = """
            {"type":"event_msg","payload":{"type":"task_complete"}}
            {"type":"event_msg","payload":{"type":"agent_message"}}
            """
        #expect(CodexSessionParser.inferState(from: tail) == "done")
    }

    @Test("malformed JSON lines are skipped rather than throwing")
    func malformedLinesAreSkipped() {
        let tail = """
            not json at all
            {"type":"event_msg","payload":{"type":"task_started"}}
            """
        #expect(CodexSessionParser.inferState(from: tail) == "running")
    }

    @Test("empty tail text defaults to running")
    func emptyTailDefaultsToRunning() {
        #expect(CodexSessionParser.inferState(from: "") == "running")
    }
}
