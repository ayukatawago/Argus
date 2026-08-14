import Testing

@testable import Workspaces

@Suite("WorktreeListParser")
struct WorktreeListParserTests {
    @Test("the main worktree and a linked worktree both parse, in order")
    func mainAndLinkedWorktree() {
        let output = """
            worktree /repo/main
            HEAD abcdef0123456789abcdef0123456789abcdef01
            branch refs/heads/main

            worktree /repo/feature
            HEAD 1234567890abcdef1234567890abcdef12345678
            branch refs/heads/feature
            """
        let worktrees = WorktreeListParser.parse(output)
        #expect(worktrees.count == 2)
        #expect(worktrees[0].path == "/repo/main")
        #expect(worktrees[0].branch == "main")
        #expect(worktrees[1].path == "/repo/feature")
        #expect(worktrees[1].branch == "feature")
    }

    @Test("only the first (index 0) worktree is main")
    func isMainOnlyForFirstIndex() {
        let output = """
            worktree /repo/main
            branch refs/heads/main

            worktree /repo/feature-a
            branch refs/heads/a

            worktree /repo/feature-b
            branch refs/heads/b
            """
        let worktrees = WorktreeListParser.parse(output)
        #expect(worktrees.map(\.isMain) == [true, false, false])
    }

    @Test("a detached worktree has a nil branch")
    func detachedWorktreeHasNilBranch() {
        let output = """
            worktree /repo/main
            branch refs/heads/main

            worktree /repo/detached
            HEAD fedcba9876543210fedcba9876543210fedcba98
            detached
            """
        let worktrees = WorktreeListParser.parse(output)
        #expect(worktrees[1].branch == nil)
    }

    @Test("empty output produces no worktrees")
    func emptyOutput() {
        #expect(WorktreeListParser.parse("").isEmpty)
    }

    @Test("trailing blank lines don't produce phantom worktrees")
    func trailingBlankLines() {
        let output = """
            worktree /repo/main
            branch refs/heads/main


            """
        let worktrees = WorktreeListParser.parse(output)
        #expect(worktrees.count == 1)
        #expect(worktrees[0].path == "/repo/main")
    }

    @Test("a bare repository entry parses with a nil branch, not treated specially")
    func bareRepoEntry() {
        // Real `git worktree list --porcelain` output for a bare repo has a "bare" line instead
        // of "branch"/"detached" — the parser doesn't special-case it, so it comes through as an
        // ordinary worktree with no branch.
        let output = """
            worktree /repo/bare.git
            bare
            """
        let worktrees = WorktreeListParser.parse(output)
        #expect(worktrees.count == 1)
        #expect(worktrees[0].branch == nil)
    }

    @Test("branch is shortened to its last path component")
    func branchShortenedToLastComponent() {
        // Locks current behavior: refs/heads/feature/foo displays as "foo", not "feature/foo".
        let output = """
            worktree /repo/nested
            branch refs/heads/feature/foo
            """
        let worktrees = WorktreeListParser.parse(output)
        #expect(worktrees[0].branch == "foo")
    }

    @Test("a block with no worktree line is skipped")
    func blockWithoutWorktreeLineIsSkipped() {
        let output = """
            worktree /repo/main
            branch refs/heads/main

            HEAD abcdef0123456789abcdef0123456789abcdef01
            branch refs/heads/orphan
            """
        let worktrees = WorktreeListParser.parse(output)
        #expect(worktrees.count == 1)
        #expect(worktrees[0].path == "/repo/main")
    }
}
