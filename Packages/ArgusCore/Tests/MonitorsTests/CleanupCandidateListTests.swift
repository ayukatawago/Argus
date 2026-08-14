import Testing

@testable import Monitors

private struct FakeCandidate: SizedCandidate, Equatable {
    let displayName: String
    let sizeBytes: Int64?
}

@Suite("CleanupCandidateList")
struct CleanupCandidateListTests {
    private static let oneGiB = CleanupCandidateList.smallSizeThresholdBytes

    @Test("a candidate with a nil size is kept even when hiding small candidates")
    func nilSizeKeptWhenHidingSmall() {
        let candidates = [FakeCandidate(displayName: "still-scanning", sizeBytes: nil)]
        let visible = CleanupCandidateList.visible(candidates, hideSmall: true, sortedBy: CleanupCandidateList.byName)
        #expect(visible.map(\.displayName) == ["still-scanning"])
    }

    @Test("a candidate below the 1 GiB threshold is hidden when hideSmall is true")
    func belowThresholdHiddenWhenHidingSmall() {
        let candidates = [FakeCandidate(displayName: "tiny", sizeBytes: Self.oneGiB - 1)]
        let visible = CleanupCandidateList.visible(candidates, hideSmall: true, sortedBy: CleanupCandidateList.byName)
        #expect(visible.isEmpty)
    }

    @Test("a candidate exactly at the 1 GiB threshold is not hidden")
    func atThresholdNotHidden() {
        let candidates = [FakeCandidate(displayName: "exactly-1gib", sizeBytes: Self.oneGiB)]
        let visible = CleanupCandidateList.visible(candidates, hideSmall: true, sortedBy: CleanupCandidateList.byName)
        #expect(visible.map(\.displayName) == ["exactly-1gib"])
    }

    @Test("hideSmall false shows everything regardless of size")
    func hideSmallFalseShowsEverything() {
        let candidates = [
            FakeCandidate(displayName: "tiny", sizeBytes: 100),
            FakeCandidate(displayName: "unknown", sizeBytes: nil),
        ]
        let visible = CleanupCandidateList.visible(candidates, hideSmall: false, sortedBy: CleanupCandidateList.byName)
        #expect(visible.count == 2)
    }

    @Test("byName sorts alphabetically")
    func byNameSortsAlphabetically() {
        let candidates = [
            FakeCandidate(displayName: "zebra", sizeBytes: 1),
            FakeCandidate(displayName: "alpha", sizeBytes: 1),
        ]
        let visible = CleanupCandidateList.visible(candidates, hideSmall: false, sortedBy: CleanupCandidateList.byName)
        #expect(visible.map(\.displayName) == ["alpha", "zebra"])
    }

    @Test("bySizeDescending sorts largest first")
    func bySizeDescendingSortsLargestFirst() {
        let candidates = [
            FakeCandidate(displayName: "small", sizeBytes: 100),
            FakeCandidate(displayName: "large", sizeBytes: 1_000),
        ]
        let visible = CleanupCandidateList.visible(
            candidates, hideSmall: false, sortedBy: CleanupCandidateList.bySizeDescending)
        #expect(visible.map(\.displayName) == ["large", "small"])
    }

    @Test("bySizeDescending sorts a nil size last")
    func bySizeDescendingSortsNilLast() {
        let candidates = [
            FakeCandidate(displayName: "unknown", sizeBytes: nil),
            FakeCandidate(displayName: "known", sizeBytes: 1),
        ]
        let visible = CleanupCandidateList.visible(
            candidates, hideSmall: false, sortedBy: CleanupCandidateList.bySizeDescending)
        #expect(visible.map(\.displayName) == ["known", "unknown"])
    }
}
