import Testing

@testable import Workspaces

@Suite("Workspaces smoke test")
struct WorkspacesSmokeTests {
    @Test("GitWorktree.id is its path")
    func worktreeIDIsPath() {
        let worktree = GitWorktree(path: "/tmp/repo", branch: "main", isMain: true)
        #expect(worktree.id == "/tmp/repo")
    }

    @Test("GitRepo.id is its main path")
    func repoIDIsMainPath() {
        let repo = GitRepo(name: "repo", mainPath: "/tmp/repo", worktrees: [])
        #expect(repo.id == "/tmp/repo")
    }
}
