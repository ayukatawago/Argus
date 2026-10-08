import Foundation
import Testing

@testable import Workspaces

@Suite("Workspaces fixes")
struct Phase1WorkspacesFixTests {
    // MARK: WorkspaceScanner.isRelevant

    @Test(
        "paths inside a .git directory are relevant",
        arguments: ["/r/repo/.git/HEAD", "/r/repo/.git/worktrees/x/gitdir", "/r/repo/.git"])
    func gitDirectoryRelevant(_ path: String) {
        #expect(WorkspaceScanner.isRelevant([path], watchedRoots: ["/r"]))
    }

    @Test(
        "files that merely start with .git are not relevant",
        arguments: [
            "/r/repo/.github/workflows/ci.yml", "/r/repo/.gitignore", "/r/repo/.gitattributes", "/r/repo/src/.gitkeep",
        ])
    func gitLookalikesIgnored(_ path: String) {
        #expect(!WorkspaceScanner.isRelevant([path], watchedRoots: ["/r"]))
    }

    @Test("a change reported on a watched root itself is relevant")
    func rootRelevant() {
        #expect(WorkspaceScanner.isRelevant(["/r"], watchedRoots: ["/r"]))
        #expect(!WorkspaceScanner.isRelevant(["/r/other/file.swift"], watchedRoots: ["/r"]))
    }

    // MARK: WorktreeListParser

    @Test("the first parsed worktree is main even when a malformed block precedes it")
    func mainSurvivesMalformedLeadingBlock() {
        let output =
            "garbage without a path\n\nworktree /repo/main\nbranch refs/heads/main\n\nworktree /repo/f\nbranch refs/heads/f"
        let worktrees = WorktreeListParser.parse(output)
        #expect(worktrees.map(\.path) == ["/repo/main", "/repo/f"])
        #expect(worktrees.map(\.isMain) == [true, false])
    }

    // MARK: WorkspaceConfigFile

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ws-\(UUID().uuidString).json")
    }

    @Test("a file missing `roots` keeps its hidden/excluded/order state and uses the default roots")
    func missingRootsKeepsState() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{"hiddenWorktreeIDs":["/a"],"repoOrder":["/b"]}"#.utf8).write(to: url)
        let config = WorkspaceConfigFile.load(from: url, defaultRoots: ["/default"])
        #expect(config.roots == ["/default"])
        #expect(config.hiddenWorktreeIDs == ["/a"])
        #expect(config.repoOrder == ["/b"])
    }

    @Test("saving is byte-stable: set contents are written sorted")
    func saveIsStable() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let config = WorkspaceConfig(roots: ["/r"], hiddenWorktreeIDs: ["/c", "/a", "/b", "/e", "/d"])
        WorkspaceConfigFile.save(config, to: url)
        let first = try Data(contentsOf: url)
        WorkspaceConfigFile.save(config, to: url)
        #expect(try Data(contentsOf: url) == first)
        let text = String(decoding: first, as: UTF8.self)
        let positions = ["/a", "/b", "/c", "/d", "/e"].compactMap { text.range(of: "\"\($0)\"")?.lowerBound }
        #expect(positions == positions.sorted())
    }

    @Test("an undecodable workspaces.json is backed up before defaults are returned")
    func corruptBackedUp() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ws-dir-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("workspaces.json")
        try Data("not json".utf8).write(to: url)
        #expect(WorkspaceConfigFile.load(from: url, defaultRoots: ["/d"]) == WorkspaceConfig(roots: ["/d"]))
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).contains { $0.contains(".corrupt-") })
    }
}
