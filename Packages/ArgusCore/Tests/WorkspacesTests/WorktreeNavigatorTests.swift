import Testing

@testable import Workspaces

@Suite("WorktreeNavigator")
struct WorktreeNavigatorTests {
    private static let list = ["a", "b", "c"]

    @Test("moving forward from the middle selects the next item")
    func forwardFromMiddle() {
        #expect(WorktreeNavigator.next(from: "b", in: Self.list, forward: true) == "c")
    }

    @Test("moving forward from the last item wraps around to the first")
    func forwardWrapsAround() {
        #expect(WorktreeNavigator.next(from: "c", in: Self.list, forward: true) == "a")
    }

    @Test("moving backward from the middle selects the previous item")
    func backwardFromMiddle() {
        #expect(WorktreeNavigator.next(from: "b", in: Self.list, forward: false) == "a")
    }

    @Test("moving backward from the first item wraps around to the last")
    func backwardWrapsAround() {
        #expect(WorktreeNavigator.next(from: "a", in: Self.list, forward: false) == "c")
    }

    @Test("a nil current selection picks the first eligible worktree")
    func nilCurrentPicksFirst() {
        #expect(WorktreeNavigator.next(from: nil, in: Self.list, forward: true) == "a")
        #expect(WorktreeNavigator.next(from: nil, in: Self.list, forward: false) == "a")
    }

    @Test("a current selection no longer among the eligible list picks the first, not nil")
    func currentNotInListPicksFirst() {
        #expect(WorktreeNavigator.next(from: "gone", in: Self.list, forward: true) == "a")
    }

    @Test("an empty eligible list returns nil regardless of current or direction")
    func emptyListReturnsNil() {
        #expect(WorktreeNavigator.next(from: "a", in: [], forward: true) == nil)
        #expect(WorktreeNavigator.next(from: nil, in: [], forward: false) == nil)
    }

    @Test("a single-element list wraps to itself in both directions")
    func singleElementWrapsToItself() {
        #expect(WorktreeNavigator.next(from: "only", in: ["only"], forward: true) == "only")
        #expect(WorktreeNavigator.next(from: "only", in: ["only"], forward: false) == "only")
    }
}

struct WorktreeNavigatorAttentionTests {
    private let ids = ["a", "b", "c", "d"]

    @Test func picksHighestPriorityOverNearer() {
        let priorities = ["b": 1, "d": 2]
        #expect(WorktreeNavigator.nextAttention(from: "a", in: ids) { priorities[$0] } == "d")
    }

    @Test func tiesResolveToNextAfterCurrentWrappingAround() {
        let priorities = ["a": 1, "c": 1]
        #expect(WorktreeNavigator.nextAttention(from: "c", in: ids) { priorities[$0] } == "a")
        #expect(WorktreeNavigator.nextAttention(from: "a", in: ids) { priorities[$0] } == "c")
    }

    @Test func neverReturnsCurrent() {
        let priorities = ["a": 5]
        #expect(WorktreeNavigator.nextAttention(from: "a", in: ids) { priorities[$0] } == nil)
    }

    @Test func nilWhenNothingNeedsAttentionOrListEmpty() {
        #expect(WorktreeNavigator.nextAttention(from: "a", in: ids) { _ in nil } == nil)
        #expect(WorktreeNavigator.nextAttention(from: nil, in: []) { _ in 1 } == nil)
    }

    @Test func nilCurrentStartsFromTheTop() {
        let priorities = ["b": 1, "c": 1]
        #expect(WorktreeNavigator.nextAttention(from: nil, in: ids) { priorities[$0] } == "b")
    }
}
