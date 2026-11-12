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
        let firstHide = list.hide(1, updatedAt: "t1")
        #expect(firstHide)
        #expect(list.ids == [1])
        let secondHide = list.hide(1, updatedAt: "t2")
        #expect(!secondHide)
    }

    @Test("reveal removes only the given ids and reports whether anything changed")
    func revealRemovesGivenIDs() {
        var list = PRHiddenList(entries: [1: "a", 2: "b", 3: "c"])
        let firstReveal = list.reveal([2])
        #expect(firstReveal)
        #expect(list.ids == [1, 3])
        let secondReveal = list.reveal([2])
        #expect(!secondReveal)
        let thirdReveal = list.reveal([1, 3, 99])
        #expect(thirdReveal)
        #expect(list.ids.isEmpty)
    }

    @Test("reconcile drops ids no longer present and reports whether anything changed")
    func reconcileDropsAbsentIDs() {
        var list = PRHiddenList(entries: [1: "a", 2: "b", 3: "c"])
        let first = list.reconcile(current: [2: "b", 3: "c", 4: "d"])
        #expect(first)
        #expect(list.ids == [2, 3])
        let second = list.reconcile(current: [2: "b", 3: "c", 4: "d"])
        #expect(!second)
    }

    @Test("reconcile un-hides a PR whose updated_at changed and keeps unchanged ones hidden")
    func reconcileUnhidesUpdatedPR() {
        var list = PRHiddenList(entries: [1: "a", 2: "b"])
        let changed = list.reconcile(current: [1: "a2", 2: "b"])
        #expect(changed)
        #expect(list.ids == [2])
    }

    @Test("reconcile adopts the current updated_at for a nil baseline and keeps it hidden")
    func reconcileAdoptsNilBaseline() {
        var list = PRHiddenList(entries: [1: nil])
        let adopted = list.reconcile(current: [1: "a"])
        #expect(adopted)
        #expect(list.entries == [1: "a"])
        let changedAgain = list.reconcile(current: [1: "b"])
        #expect(changedAgain)
        #expect(list.ids.isEmpty)
    }

    @Test("split partitions in order, hidden ids landing in the hidden list")
    func splitPartitionsInOrder() {
        let list = PRHiddenList(entries: [2: "b"])
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
