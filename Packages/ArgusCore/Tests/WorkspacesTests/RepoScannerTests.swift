import Foundation
import Testing

@testable import Workspaces

@Suite("RepoScanner")
struct RepoScannerTests {
    private static func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("repo-scanner-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func markAsGitRepo(_ url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.appendingPathComponent(".git"), withIntermediateDirectories: true)
    }

    private static func stubWorktree(for path: String) -> [GitWorktree] {
        [GitWorktree(path: path, branch: "main", isMain: true)]
    }

    @Test("a root that is itself a git repo returns a single GitRepo with the lister's worktrees")
    func rootIsGitRepo() async throws {
        let root = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.markAsGitRepo(root)

        let repos = try #require(
            await RepoScanner.findRepos(under: root.path, excluding: []) { path in
                Self.stubWorktree(for: path)
            })
        #expect(repos.count == 1)
        #expect(repos[0].mainPath == root.path)
        #expect(repos[0].isGitRepo == true)
        #expect(repos[0].worktrees.count == 1)
    }

    @Test("an excluded root that is a git repo is skipped")
    func excludedRootIsSkipped() async throws {
        let root = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.markAsGitRepo(root)

        let repos = await RepoScanner.findRepos(under: root.path, excluding: [root.path]) { path in
            Self.stubWorktree(for: path)
        }
        #expect(repos?.isEmpty == true)
    }

    @Test("a git repo root whose worktree lister returns nothing is treated as not found")
    func emptyWorktreesExcludesTheRepo() async throws {
        let root = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.markAsGitRepo(root)

        let repos = await RepoScanner.findRepos(under: root.path, excluding: []) { _ in [] }
        #expect(repos?.isEmpty == true)
    }

    @Test("only git-repo subdirectories are returned, sorted by name")
    func onlyGitSubdirectoriesReturned() async throws {
        let root = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.markAsGitRepo(root.appendingPathComponent("zebra"))
        try Self.markAsGitRepo(root.appendingPathComponent("alpha"))
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("not-a-repo"), withIntermediateDirectories: true)

        let repos = try #require(
            await RepoScanner.findRepos(under: root.path, excluding: []) { path in
                Self.stubWorktree(for: path)
            })
        #expect(repos.map(\.name) == ["alpha", "zebra"])
    }

    @Test("an excluded subdirectory is skipped even though it's a git repo")
    func excludedSubdirectoryIsSkipped() async throws {
        let root = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.markAsGitRepo(root.appendingPathComponent("keep"))
        try Self.markAsGitRepo(root.appendingPathComponent("skip"))

        let repos = try #require(
            await RepoScanner.findRepos(
                under: root.path,
                excluding: [root.appendingPathComponent("skip").path]
            ) { path in
                Self.stubWorktree(for: path)
            })
        #expect(repos.map(\.name) == ["keep"])
    }

    @Test("a root with no git-repo children falls back to a single non-git repo for the root itself")
    func noGitChildrenFallsBackToPlainFolder() async throws {
        let root = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("plain-file-tree"), withIntermediateDirectories: true)

        let repos = try #require(await RepoScanner.findRepos(under: root.path, excluding: []) { _ in [] })
        #expect(repos.count == 1)
        #expect(repos[0].mainPath == root.path)
        #expect(repos[0].isGitRepo == false)
        #expect(repos[0].worktrees.map(\.path) == [root.path])
    }

    @Test("the fallback plain-folder case is also skipped when the root itself is excluded")
    func fallbackSkippedWhenRootExcluded() async throws {
        let root = try Self.makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let repos = await RepoScanner.findRepos(under: root.path, excluding: [root.path]) { _ in [] }
        #expect(repos?.isEmpty == true)
    }

    @Test("a nonexistent root returns no repos (definite, not undetermined)")
    func nonexistentRootReturnsNoRepos() async {
        let repos = await RepoScanner.findRepos(under: "/no/such/path/at/all", excluding: []) { _ in [] }
        #expect(repos?.isEmpty == true)
    }

    @Test("a root that exists but can't be listed returns nil (undetermined), not empty")
    func unreadableRootReturnsNil() async throws {
        let root = try Self.makeTempDir()
        defer {
            chmod(root.path, 0o755)
            try? FileManager.default.removeItem(at: root)
        }
        chmod(root.path, 0)

        let repos = await RepoScanner.findRepos(under: root.path, excluding: []) { _ in [] }
        #expect(repos == nil)
    }
}
