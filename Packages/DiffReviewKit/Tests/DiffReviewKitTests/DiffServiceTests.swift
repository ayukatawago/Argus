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

    @Test("gap lines are keyed per file, so the same gap id in two files stays independent")
    func gapKeyedPerFile() async {
        let model = model(commits: [])
        #expect(model.expandedLines(forGapID: "top", filePath: "a") == nil)
        #expect(!model.isLoadingGap("top", filePath: "b"))
    }
}
