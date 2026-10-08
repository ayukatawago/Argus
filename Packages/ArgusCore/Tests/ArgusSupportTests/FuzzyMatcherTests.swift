import Testing

@testable import ArgusSupport

struct FuzzyMatcherTests {
    @Test func emptyQueryMatchesEverythingWithZero() {
        #expect(FuzzyMatcher.score(query: "", in: "anything") == 0)
    }

    @Test func nonSubsequenceDoesNotMatch() {
        #expect(FuzzyMatcher.score(query: "xyz", in: "feature-branch") == nil)
        #expect(FuzzyMatcher.score(query: "ba", in: "ab") == nil)
    }

    @Test func matchIsCaseInsensitive() {
        #expect(FuzzyMatcher.score(query: "FEAT", in: "feature") != nil)
    }

    @Test func consecutiveAndPrefixHitsOutscoreScatteredOnes() throws {
        let tight = try #require(FuzzyMatcher.score(query: "fea", in: "feature"))
        let scattered = try #require(FuzzyMatcher.score(query: "fea", in: "f-e-a-ture"))
        #expect(tight > scattered)
    }

    @Test func rankOrdersBestFirstAndKeepsTiesStable() {
        let items = ["xxfoo", "foo", "bar", "foobar"]
        let ranked = FuzzyMatcher.rank(items, query: "foo") { [$0] }
        #expect(ranked.first == "foo")
        #expect(!ranked.contains("bar"))
        #expect(FuzzyMatcher.rank(items, query: "") { [$0] } == items)
    }

    @Test func bestScoreTakesTheMaxAcrossCandidates() {
        #expect(FuzzyMatcher.bestScore(query: "main", in: ["zzz", "main"]) != nil)
        #expect(FuzzyMatcher.bestScore(query: "main", in: ["zzz"]) == nil)
    }
}
