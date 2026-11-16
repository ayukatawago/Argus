import Foundation
import Testing

@testable import DiffReviewKit

private func makeRepo() async throws -> (path: String, git: GitRunner) {
    let path = NSTemporaryDirectory() + "DiffServiceTests-\(UUID().uuidString)"
    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    let git = GitRunner(repositoryPath: path)
    _ = try await git.run(["init", "-q"])
    return (path, git)
}

private func commit(_ git: GitRunner, _ message: String) async throws {
    _ = try await git.run(["add", "-A"])
    _ = try await git.run(["-c", "user.email=t@example.com", "-c", "user.name=T", "commit", "-q", "-m", message])
}

@Suite("DiffService")
struct DiffServiceTests {
    @Test("a working-tree file with invalid UTF-8 still produces a diff instead of an empty one")
    func invalidUTF8() async throws {
        let (path, git) = try await makeRepo()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let file = path + "/a.txt"
        try Data("one\n".utf8).write(to: URL(fileURLWithPath: file))
        try await commit(git, "init")
        var bytes = Data("two ".utf8)
        bytes.append(0xFF)
        bytes.append(Data("\n".utf8))
        try bytes.write(to: URL(fileURLWithPath: file))

        let files = try await DiffService(git: git).diff(base: "HEAD", head: "HEAD", includeUncommitted: true)
        #expect(files.map(\.path) == ["a.txt"])
        #expect(files.first?.additionCount == 1)
    }

    @Test("non-ASCII and spaced paths come back literal")
    func unicodePath() async throws {
        let (path, git) = try await makeRepo()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let name = "caf\u{e9} x.txt"
        try Data("one\n".utf8).write(to: URL(fileURLWithPath: path + "/" + name))
        try await commit(git, "init")
        try Data("two\n".utf8).write(to: URL(fileURLWithPath: path + "/" + name))
        try Data("new\n".utf8).write(to: URL(fileURLWithPath: path + "/\u{65e5}\u{672c}.txt"))

        let files = try await DiffService(git: git).diff(base: "HEAD", head: "HEAD", includeUncommitted: true)
        #expect(Set(files.map(\.path)) == [name, "\u{65e5}\u{672c}.txt"])
    }

    @Test("a root commit can be diffed against the empty tree")
    func rootCommit() async throws {
        let (path, git) = try await makeRepo()
        defer { try? FileManager.default.removeItem(atPath: path) }
        try Data("one\n".utf8).write(to: URL(fileURLWithPath: path + "/a.txt"))
        try await commit(git, "init")

        let files = try await DiffService(git: git).diff(
            base: DiffService.emptyTreeHash, head: "HEAD", includeUncommitted: false)
        #expect(files.map(\.path) == ["a.txt"])
        #expect(files.first?.kind == .added)
    }

    @Test("GitRunner reports a timeout distinctly and decodes invalid UTF-8 leniently")
    func runnerTimeoutFlag() async throws {
        // `GitRunner` prepends `-C <path>`, so use scripts that ignore their arguments.
        let sleeper = try fakeGit("sleep 5")
        let shell = try fakeGit(#"printf 'x\377y'"#)
        defer {
            try? FileManager.default.removeItem(atPath: sleeper)
            try? FileManager.default.removeItem(atPath: shell)
        }
        let result = try await GitRunner(repositoryPath: "/tmp", executablePath: sleeper).run(["a"], timeout: 0.3)
        #expect(result.timedOut)
        #expect(!result.succeeded)

        let printed = try await GitRunner(repositoryPath: "/tmp", executablePath: shell).run(["a"])
        #expect(printed.timedOut == false)
        #expect(printed.standardOutput.hasPrefix("x"))
        #expect(printed.standardOutput.hasSuffix("y"))
    }
}

private func fakeGit(_ body: String) throws -> String {
    let path = NSTemporaryDirectory() + "fake-git-\(UUID().uuidString).sh"
    try "#!/bin/sh\n\(body)\n".write(toFile: path, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
    return path
}

@MainActor
@Suite("DiffReviewModel")
struct DiffReviewModelTests {
    private func model(commits: [Commit]) -> DiffReviewModel {
        let model = DiffReviewModel(repositoryPath: "/tmp", agent: DiffReviewAgent(kind: .claude))
        model.baseRef = "main"
        model.headRef = "HEAD"
        model.commits = commits
        return model
    }

    @Test("effectiveBase uses the empty tree when the oldest selected commit is a root commit")
    func rootCommitBase() {
        let root = Commit(hash: "r", shortHash: "r", subject: "", author: "", relativeDate: "", isRoot: true)
        let child = Commit(hash: "c", shortHash: "c", subject: "", author: "", relativeDate: "")
        let model = model(commits: [child, root])
        #expect(model.effectiveBase == DiffService.emptyTreeHash)
        model.selectedCommitRange = 0...0
        #expect(model.effectiveBase == "c^")
    }

    /// Two files, each with one changed line in the middle of 100 lines, committed as `HEAD~1` → `HEAD`.
    /// Their hunks start at line 47, so each has a 46-line top gap and a 47-line bottom gap.
    private func repoWithTwoChangedFiles() async throws -> (path: String, model: DiffReviewModel) {
        let (path, git) = try await makeRepo()
        let body = (1...100).map { "line \($0)\n" }.joined()
        let changed = body.replacingOccurrences(of: "line 50\n", with: "LINE 50\n")
        for name in ["a.txt", "b.txt"] {
            try Data(body.utf8).write(to: URL(fileURLWithPath: path + "/" + name))
        }
        try await commit(git, "init")
        for name in ["a.txt", "b.txt"] {
            try Data(changed.utf8).write(to: URL(fileURLWithPath: path + "/" + name))
        }
        try await commit(git, "change")

        let model = DiffReviewModel(repositoryPath: path, agent: DiffReviewAgent(kind: .claude))
        model.baseRef = "HEAD~1"
        model.headRef = "HEAD"
        await model.refreshDiff()
        return (path, model)
    }

    private func gap(_ position: DiffGap.Position, in file: DiffFile) -> DiffGap? {
        DiffBlockBuilder.blocks(for: file).compactMap { block -> DiffGap? in
            guard case .gap(let gap) = block, gap.position == position else { return nil }
            return gap
        }.first
    }

    @Test("gap expansion is keyed per file, so the same gap id in two files stays independent")
    func gapKeyedPerFile() async throws {
        let (path, model) = try await repoWithTwoChangedFiles()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let fileA = try #require(model.files.first { $0.path == "a.txt" })

        let topA = try #require(gap(.top, in: fileA))
        await model.expandGap(topA, in: fileA, direction: .down)

        #expect(model.gapExpansion(forGapID: "top", filePath: "a.txt").revealedFromTop == 20)
        #expect(model.gapExpansion(forGapID: "top", filePath: "b.txt") == GapExpansion())
        #expect(!model.isLoadingGap("top", filePath: "b.txt"))
    }

    @Test("a top gap's ↑ reveals lines just above the hunk, counted from the bottom of the gap")
    func topGapUpRevealsNearHunk() async throws {
        let (path, model) = try await repoWithTwoChangedFiles()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let file = try #require(model.files.first { $0.path == "a.txt" })
        let top = try #require(gap(.top, in: file))

        await model.expandGap(top, in: file, direction: .up)

        let revealed = model.revealedLines(top, in: file)
        #expect(revealed.top.isEmpty)
        #expect(revealed.bottom.count == 20)
        #expect(revealed.bottom.first?.text == "line 27")
        #expect(revealed.bottom.last?.text == "line 46")
    }

    @Test("a bottom gap's length is unknown until its file is fetched, then resolves and fully expands with .all")
    func bottomGapResolvesThenExpands() async throws {
        let (path, model) = try await repoWithTwoChangedFiles()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let file = try #require(model.files.first { $0.path == "a.txt" })
        let bottom = try #require(gap(.bottom, in: file))

        #expect(model.resolvedLineCount(for: bottom, in: file) == nil)
        await model.expandGap(bottom, in: file, direction: .down)
        #expect(model.resolvedLineCount(for: bottom, in: file) == 47)
        #expect(model.revealedLines(bottom, in: file).top.count == 20)

        await model.expandGap(bottom, in: file, direction: .all)
        #expect(model.gapExpansion(forGapID: bottom.id, filePath: "a.txt").isFullyExpanded(lineCount: 47))
        #expect(model.revealedLines(bottom, in: file).top.count == 47)
    }

    @Test("a refresh discards revealed context along with the cached file content")
    func refreshClearsExpansions() async throws {
        let (path, model) = try await repoWithTwoChangedFiles()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let file = try #require(model.files.first { $0.path == "a.txt" })
        let top = try #require(gap(.top, in: file))
        await model.expandGap(top, in: file, direction: .down)

        await model.refreshDiff()

        #expect(model.gapExpansion(forGapID: "top", filePath: "a.txt") == GapExpansion())
        #expect(model.revealedLines(top, in: file).top.isEmpty)
    }

    @Test("toggling Viewed collapses the file, and a refresh with unchanged content keeps it that way")
    func viewedSurvivesUnchangedRefresh() async throws {
        let (path, model) = try await repoWithTwoChangedFiles()
        defer { try? FileManager.default.removeItem(atPath: path) }

        model.toggleViewed("a.txt")
        #expect(model.viewedFiles["a.txt"] != nil)
        #expect(model.collapsedFilePaths.contains("a.txt"))

        await model.refreshDiff()
        #expect(model.viewedFiles["a.txt"] != nil)
        #expect(model.collapsedFilePaths.contains("a.txt"))
    }
}
