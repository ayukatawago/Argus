import Testing

@testable import ArgusSupport

@Suite("GenerationCounter")
struct GenerationCounterTests {
    @Test("an untouched key stays at generation zero and is unchanged since its token")
    func untouched() {
        let counter = GenerationCounter<String>()
        let token = counter.current("a")
        #expect(token == 0)
        #expect(counter.isUnchanged("a", since: token))
    }

    @Test("bumping a key invalidates tokens taken before it, but not tokens taken after")
    func bumpInvalidates() {
        var counter = GenerationCounter<String>()
        let before = counter.current("a")
        counter.bump("a")
        #expect(!counter.isUnchanged("a", since: before))
        #expect(counter.isUnchanged("a", since: counter.current("a")))
    }

    @Test("keys are independent")
    func independentKeys() {
        var counter = GenerationCounter<String>()
        let token = counter.current("a")
        counter.bump("b")
        #expect(counter.isUnchanged("a", since: token))
    }

    @Test("several bumps keep counting up")
    func monotonic() {
        var counter = GenerationCounter<Int>()
        counter.bump(1)
        counter.bump(1)
        #expect(counter.current(1) == 2)
    }
}
