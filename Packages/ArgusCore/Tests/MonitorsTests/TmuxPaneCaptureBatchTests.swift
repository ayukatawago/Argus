import Testing

@testable import Monitors

@Suite("TmuxPaneCaptureBatch")
struct TmuxPaneCaptureBatchTests {
    // MARK: - parseSessionHeights

    @Test("parses session|height lines into a name -> height dictionary")
    func parsesSessionHeights() {
        let output = "argus-a-repo-abc123|67\nargus-x-repo-abc123|24\n"
        let heights = TmuxPaneCaptureBatch.parseSessionHeights(from: output)
        #expect(heights == ["argus-a-repo-abc123": 67, "argus-x-repo-abc123": 24])
    }

    @Test("a line with a non-integer height is skipped")
    func nonIntegerHeightSkipped() {
        let output = "argus-a-repo-abc123|not-a-number\n"
        #expect(TmuxPaneCaptureBatch.parseSessionHeights(from: output).isEmpty)
    }

    @Test("a malformed line without a pipe separator is skipped")
    func malformedLineSkipped() {
        let output = "no-pipe-here\nargus-a-repo-abc123|67\n"
        let heights = TmuxPaneCaptureBatch.parseSessionHeights(from: output)
        #expect(heights == ["argus-a-repo-abc123": 67])
    }

    @Test("empty output produces no heights")
    func emptyOutputProducesNoHeights() {
        #expect(TmuxPaneCaptureBatch.parseSessionHeights(from: "").isEmpty)
    }

    // MARK: - captureArguments

    @Test("a single session with a known, tall-enough height gets a windowed -S capture")
    func singleSessionGetsWindowedCapture() {
        let args = TmuxPaneCaptureBatch.captureArguments(
            sessionNames: ["argus-a-repo-abc123"],
            heightBySession: ["argus-a-repo-abc123": 67],
            contextLines: 16
        )
        #expect(
            args == [
                "display-message", "-p", "ARGUS_PANE:argus-a-repo-abc123",
                ";",
                "capture-pane", "-p", "-J", "-t", "argus-a-repo-abc123", "-S", "51",
            ])
    }

    @Test("a session whose height is unknown is captured in full, with no -S argument")
    func unknownHeightCapturesInFull() {
        let args = TmuxPaneCaptureBatch.captureArguments(
            sessionNames: ["argus-a-repo-abc123"],
            heightBySession: [:],
            contextLines: 16
        )
        #expect(
            args == [
                "display-message", "-p", "ARGUS_PANE:argus-a-repo-abc123",
                ";",
                "capture-pane", "-p", "-J", "-t", "argus-a-repo-abc123",
            ])
    }

    @Test("a session whose height doesn't exceed contextLines is captured in full")
    func heightNotExceedingContextLinesCapturesInFull() {
        let args = TmuxPaneCaptureBatch.captureArguments(
            sessionNames: ["argus-a-repo-abc123"],
            heightBySession: ["argus-a-repo-abc123": 10],
            contextLines: 16
        )
        #expect(!args.contains("-S"))
    }

    @Test("multiple sessions are joined with bare semicolon arguments, not shell-escaped ones")
    func multipleSessionsJoinedWithBareSemicolon() {
        let args = TmuxPaneCaptureBatch.captureArguments(
            sessionNames: ["argus-a-repo-abc123", "argus-x-repo-abc123"],
            heightBySession: ["argus-a-repo-abc123": 67, "argus-x-repo-abc123": 24],
            contextLines: 16
        )
        // Three ";" arguments: one separating display-message from capture-pane within each of
        // the two sessions, plus one joining the two sessions themselves (verified live against
        // tmux run directly via argv, no shell — a shell-escaped "\;" would be a different, wrong
        // token here).
        #expect(args.filter { $0 == ";" }.count == 3)
        #expect(args.first == "display-message")
        #expect(args == [
            "display-message", "-p", "ARGUS_PANE:argus-a-repo-abc123",
            ";",
            "capture-pane", "-p", "-J", "-t", "argus-a-repo-abc123", "-S", "51",
            ";",
            "display-message", "-p", "ARGUS_PANE:argus-x-repo-abc123",
            ";",
            "capture-pane", "-p", "-J", "-t", "argus-x-repo-abc123", "-S", "8",
        ])
    }

    // MARK: - splitCapture

    @Test("splits a two-session batch back into a session -> text dictionary")
    func splitsTwoSessionBatch() {
        let output = """
            ARGUS_PANE:argus-a-repo-abc123
            ✻ Sautéed for 31m 19s
            ❯
            ARGUS_PANE:argus-x-repo-abc123
            · Ready ·
            """
        let result = TmuxPaneCaptureBatch.splitCapture(
            output, sessionNames: ["argus-a-repo-abc123", "argus-x-repo-abc123"])
        #expect(result["argus-a-repo-abc123"] == "✻ Sautéed for 31m 19s\n❯")
        #expect(result["argus-x-repo-abc123"] == "· Ready ·")
    }

    @Test(
        """
        the verified tmux abort-on-dead-target behavior: a session ordered after one whose \
        capture-pane failed never gets its delimiter printed at all, so it's absent from the \
        result — not present with empty text, which would be indistinguishable from a real \
        (if implausible) blank pane
        """
    )
    func sessionAfterAbortedOneIsAbsentNotEmpty() {
        // Reproduces the exact shape observed live: the failed session's own display-message
        // still printed (tmux ran it before the failing capture-pane), but nothing chained after
        // it ever ran, so the third session's marker is simply missing.
        let output = """
            ARGUS_PANE:argus-a-repo-abc123
            ✻ Sautéed for 31m 19s
            ARGUS_PANE:argus-a-repo-def456
            """
        let result = TmuxPaneCaptureBatch.splitCapture(
            output, sessionNames: ["argus-a-repo-abc123", "argus-a-repo-def456", "argus-x-repo-ghi789"])
        #expect(result["argus-a-repo-abc123"] == "✻ Sautéed for 31m 19s")
        // The session whose own capture-pane failed: present, but empty — callers must treat this
        // the same as "no data", not a legitimate empty pane.
        #expect(result["argus-a-repo-def456"] == "")
        // Never reached by the aborted chain at all: absent, not merely empty.
        #expect(result["argus-x-repo-ghi789"] == nil)
    }

    @Test("empty output produces an empty dictionary")
    func emptyOutputProducesEmptyDictionary() {
        #expect(TmuxPaneCaptureBatch.splitCapture("", sessionNames: ["argus-a-repo-abc123"]).isEmpty)
    }
}
