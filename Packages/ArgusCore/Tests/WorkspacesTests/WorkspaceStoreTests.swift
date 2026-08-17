import Combine
import Foundation
import Testing

@testable import Workspaces

@MainActor
@Suite("WorkspaceStore")
struct WorkspaceStoreTests {
    private static func makeTempRepoRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("workspace-store-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("repo/.git"), withIntermediateDirectories: true)
        return root
    }

    @Test("a failed scan keeps the previously discovered worktrees instead of collapsing to one")
    func failedScanKeepsPreviousWorktrees() async throws {
        let root = try Self.makeTempRepoRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repoPath = root.appendingPathComponent("repo").path

        let callCount = Counter()
        let store = WorkspaceStore { path, fallback in
            let count = await callCount.increment()
            if count == 1 {
                return [
                    GitWorktree(path: path, branch: "main", isMain: true),
                    GitWorktree(path: path + "-feature", branch: "feature", isMain: false),
                ]
            }
            // Every scan after the first simulates a failed `git worktree list`. The real
            // WorkspaceStore.fetchWorktrees falls back to `fallback` on failure — this fake does
            // the same, to prove WorkspaceStore.refresh() actually threads the previous worktrees
            // through rather than the scan silently losing them.
            return fallback ?? []
        }
        store.configureForTesting(roots: [root.path])

        await store.refresh()
        #expect(store.repos.count == 1)
        #expect(store.repos.first?.worktrees.count == 2)

        await store.refresh()
        #expect(store.repos.count == 1)
        #expect(store.repos.first?.mainPath == repoPath)
        #expect(store.repos.first?.worktrees.count == 2)
    }

    @Test("rapid requestRefresh calls coalesce into a single scan")
    func rapidRequestsCoalesceIntoOneScan() async throws {
        let root = try Self.makeTempRepoRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let callCount = Counter()
        let store = WorkspaceStore { path, _ in
            _ = await callCount.increment()
            return [GitWorktree(path: path, branch: "main", isMain: true)]
        }
        store.configureForTesting(roots: [root.path])

        for _ in 0..<20 {
            store.requestRefresh()
        }
        // The scan itself is in-memory and fast; give the coalescer's Task time to run to
        // completion without depending on its private internals.
        try await Task.sleep(nanoseconds: 300_000_000)

        let scans = await callCount.value
        #expect(scans <= 2)
        #expect(store.repos.first?.worktrees.count == 1)
    }

    @Test("a scan that finds nothing new does not republish repos")
    func unchangedScanDoesNotRepublish() async throws {
        let root = try Self.makeTempRepoRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = WorkspaceStore { path, _ in [GitWorktree(path: path, branch: "main", isMain: true)] }
        store.configureForTesting(roots: [root.path])
        await store.refresh()

        var changeCount = 0
        let cancellable = store.objectWillChange.sink { changeCount += 1 }
        defer { cancellable.cancel() }

        await store.refresh()
        #expect(changeCount == 0)
    }
}

private actor Counter {
    private var count = 0

    @discardableResult
    func increment() -> Int {
        count += 1
        return count
    }

    var value: Int { count }
}
