import Testing

@testable import Workspaces

@Suite("RepoOrdering")
struct RepoOrderingTests {
    private static func repo(_ path: String) -> GitRepo {
        GitRepo(name: path, mainPath: path, worktrees: [])
    }

    // MARK: - apply

    @Test("an empty order leaves discovered repos unchanged")
    func emptyOrderLeavesUnchanged() {
        let discovered = [Self.repo("/a"), Self.repo("/b")]
        let result = RepoOrdering.apply(order: [], to: discovered)
        #expect(result.map(\.mainPath) == ["/a", "/b"])
    }

    @Test("repos are reordered to match the persisted order")
    func reordersToMatchPersistedOrder() {
        let discovered = [Self.repo("/a"), Self.repo("/b"), Self.repo("/c")]
        let result = RepoOrdering.apply(order: ["/c", "/a", "/b"], to: discovered)
        #expect(result.map(\.mainPath) == ["/c", "/a", "/b"])
    }

    @Test("a newly discovered repo not in the persisted order is appended at the end")
    func newRepoAppendedAtEnd() {
        let discovered = [Self.repo("/a"), Self.repo("/b"), Self.repo("/new")]
        let result = RepoOrdering.apply(order: ["/b", "/a"], to: discovered)
        #expect(result.map(\.mainPath) == ["/b", "/a", "/new"])
    }

    @Test("a persisted path no longer among discovered repos is silently dropped")
    func staleOrderedPathIsDropped() {
        let discovered = [Self.repo("/a")]
        let result = RepoOrdering.apply(order: ["/gone", "/a"], to: discovered)
        #expect(result.map(\.mainPath) == ["/a"])
    }

    // MARK: - move

    @Test("moving to the same index is a no-op")
    func sameIndexIsNoOp() {
        let repos = [Self.repo("/a"), Self.repo("/b")]
        #expect(RepoOrdering.move(fromIndex: 0, toIndex: 0, in: repos) == nil)
    }

    @Test("an out-of-bounds index is a no-op")
    func outOfBoundsIsNoOp() {
        let repos = [Self.repo("/a"), Self.repo("/b")]
        #expect(RepoOrdering.move(fromIndex: 0, toIndex: 5, in: repos) == nil)
        #expect(RepoOrdering.move(fromIndex: -1, toIndex: 1, in: repos) == nil)
    }

    @Test("moving a repo forward inserts it just before its drop target")
    func moveForward() {
        // The real call site is a drop-onto-row target (SidebarView's .dropDestination), not
        // SwiftUI's onMove — toIndex is always another existing repo's current index (the row the
        // drag landed on), never repos.count. Moving 0 -> 2 inserts the dragged item immediately
        // before what was at index 2, which (after removal) is index 1.
        let repos = [Self.repo("/a"), Self.repo("/b"), Self.repo("/c"), Self.repo("/d")]
        let order = RepoOrdering.move(fromIndex: 0, toIndex: 2, in: repos)
        #expect(order == ["/b", "/a", "/c", "/d"])
    }

    @Test("moving a repo backward shifts the intervening repos forward")
    func moveBackward() {
        let repos = [Self.repo("/a"), Self.repo("/b"), Self.repo("/c"), Self.repo("/d")]
        let order = RepoOrdering.move(fromIndex: 3, toIndex: 1, in: repos)
        #expect(order == ["/a", "/d", "/b", "/c"])
    }

    @Test("dropping onto the last row's target index still inserts one position before it")
    func moveForwardOntoLastRow() {
        let repos = [Self.repo("/a"), Self.repo("/b"), Self.repo("/c")]
        let order = RepoOrdering.move(fromIndex: 0, toIndex: 2, in: repos)
        #expect(order == ["/b", "/a", "/c"])
    }
}
