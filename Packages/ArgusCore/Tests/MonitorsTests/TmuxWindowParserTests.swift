import Testing

@testable import Monitors

@Suite("TmuxWindowParser")
struct TmuxWindowParserTests {
    @Test("a window labels by the basename of its current path")
    func windowLabelsByPathBasename() {
        let output = "argus-s-repo-a\t0\t1\t/Users/taku/workspace/app/Argus\n"
        let windows = TmuxWindowParser.parse(output)
        #expect(windows.count == 1)
        #expect(windows[0].label == "Argus")
    }

    @Test("multiple windows parse in index order with exactly one active")
    func multipleWindowsParseInIndexOrder() {
        let output = "argus-s-repo-a\t1\t0\t/tmp/b\nargus-s-repo-a\t0\t1\t/tmp/a\n"
        let windows = TmuxWindowParser.parse(output)
        #expect(windows.map(\.index) == [0, 1])
        #expect(windows.filter(\.isActive).map(\.index) == [0])
    }

    @Test("a malformed line with too few fields is skipped")
    func malformedLineTooFewFieldsSkipped() {
        let output = "argus-s-repo-a\t0\t1\nargus-s-repo-a\t1\t0\t/tmp/b\n"
        let windows = TmuxWindowParser.parse(output)
        #expect(windows.map(\.index) == [1])
    }

    @Test("a non-integer window index is skipped")
    func nonIntegerIndexSkipped() {
        let output = "argus-s-repo-a\tx\t1\t/tmp/a\n"
        #expect(TmuxWindowParser.parse(output).isEmpty)
    }

    @Test("a pipe character in the path survives, since | isn't the delimiter")
    func pipeCharacterInPathPreserved() {
        let output = "argus-s-repo-a\t0\t1\t/tmp/weird|name\n"
        let windows = TmuxWindowParser.parse(output)
        #expect(windows.count == 1)
        #expect(windows[0].currentPath == "/tmp/weird|name")
        #expect(windows[0].label == "weird|name")
    }

    @Test("empty output produces no windows")
    func emptyOutputProducesNoWindows() {
        #expect(TmuxWindowParser.parse("").isEmpty)
    }

    @Test("a blank current path falls back to the index label")
    func blankPathFallsBackToIndex() {
        let output = "argus-s-repo-a\t2\t1\t\n"
        let windows = TmuxWindowParser.parse(output)
        #expect(windows.count == 1)
        #expect(windows[0].label == "2")
    }
}
