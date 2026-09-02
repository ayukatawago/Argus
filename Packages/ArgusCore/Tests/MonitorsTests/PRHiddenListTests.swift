import Testing

@testable import Monitors

private struct FakeIdentifiable: Identifiable, Equatable {
    let id: Int
}

@Suite("PRHiddenList")
struct PRHiddenListTests {
    @Test("hiding an id reports a change the first time, not on repeat")
    func hideReportsChangeOnce() {
        var list = PRHiddenList()
        let firstHide = list.hide(1)
        #expect(firstHide)
        #expect(list.ids == [1])
        let secondHide = list.hide(1)
        #expect(!secondHide)
    }

    @Test("reveal removes only the given ids and reports whether anything changed")
    func revealRemovesGivenIDs() {
        var list = PRHiddenList(ids: [1, 2, 3])
        let firstReveal = list.reveal([2])
        #expect(firstReveal)
        #expect(list.ids == [1, 3])
        let secondReveal = list.reveal([2])
        #expect(!secondReveal)
        let thirdReveal = list.reveal([1, 3, 99])
        #expect(thirdReveal)
        #expect(list.ids.isEmpty)
    }

    @Test("prune drops ids no longer present and reports whether anything changed")
    func pruneDropsAbsentIDs() {
        var list = PRHiddenList(ids: [1, 2, 3])
        let firstPrune = list.prune(keeping: [2, 3, 4])
        #expect(firstPrune)
        #expect(list.ids == [2, 3])
        let secondPrune = list.prune(keeping: [2, 3, 4])
        #expect(!secondPrune)
    }

    @Test("split partitions in order, hidden ids landing in the hidden list")
    func splitPartitionsInOrder() {
        let list = PRHiddenList(ids: [2])
        let items = [FakeIdentifiable(id: 1), FakeIdentifiable(id: 2), FakeIdentifiable(id: 3)]
        let (visible, hidden) = list.split(items)
        #expect(visible == [FakeIdentifiable(id: 1), FakeIdentifiable(id: 3)])
        #expect(hidden == [FakeIdentifiable(id: 2)])
    }

    @Test("split with an empty hidden set leaves everything visible")
    func splitWithNoHiddenIDs() {
        let list = PRHiddenList()
        let items = [FakeIdentifiable(id: 1), FakeIdentifiable(id: 2)]
        let (visible, hidden) = list.split(items)
        #expect(visible == items)
        #expect(hidden.isEmpty)
    }
}
