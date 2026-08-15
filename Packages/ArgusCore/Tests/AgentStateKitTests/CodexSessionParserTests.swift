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

    // MARK: - extractThreadSource

    @Test("extracts thread_source from a realistic padded header")
    func extractsThreadSourceUser() {
        let header = #"{"type":"session_meta","payload":{"cwd":"/x","thread_source":"user","#
        let padding = String(repeating: "x", count: max(0, 512 - header.count))
        #expect(CodexSessionParser.extractThreadSource(from: header + padding) == "user")
    }

    @Test("extracts thread_source of subagent")
    func extractsThreadSourceSubagent() {
        #expect(CodexSessionParser.extractThreadSource(from: #"{"thread_source":"subagent"}"#) == "subagent")
    }

    @Test("returns nil when thread_source key is absent")
    func missingThreadSourceReturnsNil() {
        #expect(CodexSessionParser.extractThreadSource(from: #"{"cwd":"/x"}"#) == nil)
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

    @Test("turn_aborted maps to idle, matching Claude's Escape-interrupt behavior")
    func turnAbortedMapsToIdle() {
        let tail = #"{"type":"event_msg","payload":{"type":"turn_aborted"}}"#
        #expect(CodexSessionParser.inferState(from: tail) == "idle")
    }

    @Test("turn_started / turn_complete aliases map the same as task_started / task_complete")
    func turnAliasesMapCorrectly() {
        #expect(
            CodexSessionParser.inferState(from: #"{"type":"event_msg","payload":{"type":"turn_started"}}"#)
                == "running")
        #expect(
            CodexSessionParser.inferState(from: #"{"type":"event_msg","payload":{"type":"turn_complete"}}"#)
                == "done")
    }

    @Test(
        "each approval/input-request event maps to waitingForApproval",
        arguments: [
            "exec_approval_request", "apply_patch_approval_request", "request_user_input", "elicitation_request",
        ])
    func approvalEventsMapToWaitingForApproval(eventType: String) {
        let tail = #"{"type":"event_msg","payload":{"type":"\#(eventType)"}}"#
        #expect(CodexSessionParser.inferState(from: tail) == "waitingForApproval")
    }

    @Test("a later task_complete after an approval request wins (reverse scan takes the newest)")
    func laterTaskCompleteWinsOverEarlierApproval() {
        let tail = """
            {"type":"event_msg","payload":{"type":"exec_approval_request"}}
            {"type":"event_msg","payload":{"type":"task_complete"}}
            """
        #expect(CodexSessionParser.inferState(from: tail) == "done")
    }

    @Test("no event_msg lines at all is non-decisive")
    func noEventMsgIsNonDecisive() {
        let tail = #"{"type":"something_else","payload":{}}"#
        #expect(CodexSessionParser.inferState(from: tail) == nil)
    }

    @Test("an unrecognized event type is skipped in favor of an earlier recognized one")
    func unrecognizedEventTypeIsSkipped() {
        let tail = """
            {"type":"event_msg","payload":{"type":"task_complete"}}
            {"type":"event_msg","payload":{"type":"agent_message"}}
            """
        #expect(CodexSessionParser.inferState(from: tail) == "done")
    }

    @Test("a sub_agent_activity line is skipped in favor of an earlier decisive event")
    func subAgentActivityIsSkipped() {
        let tail = """
            {"type":"event_msg","payload":{"type":"task_started"}}
            {"type":"event_msg","payload":{"type":"sub_agent_activity"}}
            """
        #expect(CodexSessionParser.inferState(from: tail) == "running")
    }

    @Test("malformed JSON lines are skipped rather than throwing")
    func malformedLinesAreSkipped() {
        let tail = """
            not json at all
            {"type":"event_msg","payload":{"type":"task_started"}}
            """
        #expect(CodexSessionParser.inferState(from: tail) == "running")
    }

    @Test("empty tail text is non-decisive")
    func emptyTailIsNonDecisive() {
        #expect(CodexSessionParser.inferState(from: "") == nil)
    }
}
