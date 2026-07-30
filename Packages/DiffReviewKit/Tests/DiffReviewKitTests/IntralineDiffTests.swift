import Testing

@testable import DiffReviewKit

@Suite("IntralineDiff")
struct IntralineDiffTests {
    private func changedSubstrings(old: String, new: String) -> (old: [String], new: [String]) {
        let (oldRanges, newRanges) = IntralineDiff.changedRanges(old: old, new: new)
        return (oldRanges.map { String(old[$0]) }, newRanges.map { String(new[$0]) })
    }

    @Test("identical lines have no changed spans")
    func identicalLines() {
        let (old, new) = changedSubstrings(old: "let x = 1", new: "let x = 1")
        #expect(old.isEmpty)
        #expect(new.isEmpty)
    }

    @Test("a single renamed identifier is the only changed span")
    func renamedIdentifier() {
        let (old, new) = changedSubstrings(
            old: "let value = compute(foo)",
            new: "let value = compute(bar)"
        )
        #expect(old == ["foo"])
        #expect(new == ["bar"])
    }

    @Test("an appended argument only marks the new text as changed")
    func appendedText() {
        let (old, new) = changedSubstrings(
            old: "func greet(name: String)",
            new: "func greet(name: String, loudly: Bool)"
        )
        #expect(old.isEmpty)
        #expect(new.joined() == ", loudly: Bool")
    }

    @Test("completely different lines mark everything as changed")
    func completelyDifferent() {
        let (old, new) = changedSubstrings(old: "abc", new: "xyz")
        #expect(old.joined() == "abc")
        #expect(new.joined() == "xyz")
    }

    @Test("an empty old line marks the whole new line as changed")
    func emptyOldLine() {
        let (old, new) = changedSubstrings(old: "", new: "let x = 1")
        #expect(old.isEmpty)
        #expect(new.joined() == "let x = 1")
    }

    @Test("lines beyond the length cap fall back to whole-line ranges")
    func lengthCapFallsBackToWholeLine() {
        let old = String(repeating: "a", count: 500)
        let new = String(repeating: "b", count: 500)
        let (oldRanges, newRanges) = IntralineDiff.changedRanges(old: old, new: new)
        #expect(oldRanges == [old.startIndex..<old.endIndex])
        #expect(newRanges == [new.startIndex..<new.endIndex])
    }
}
