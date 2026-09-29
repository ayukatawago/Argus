import Testing

@testable import Workspaces

@Suite("RepoLookup")
struct RepoLookupTests {
    private static func worktree(_ path: String, isMain: Bool = false) -> GitWorktree {
        GitWorktree(path: path, branch: nil, isMain: isMain)
    }

    private static func repo(_ mainPath: String, worktrees: [GitWorktree]) -> GitRepo {
        GitRepo(name: mainPath, mainPath: mainPath, worktrees: worktrees)
    }

    @Test("resolves the repo owning its main worktree")
    func resolvesMainWorktree() {
        let repos = [Self.repo("/repos/a", worktrees: [Self.worktree("/repos/a", isMain: true)])]
        #expect(RepoLookup.mainPath(forWorktreePath: "/repos/a", in: repos) == "/repos/a")
    }

    @Test("resolves the repo owning a linked worktree")
    func resolvesLinkedWorktree() {
        let worktrees = [Self.worktree("/repos/a", isMain: true), Self.worktree("/repos/a-feature")]
        let repos = [Self.repo("/repos/a", worktrees: worktrees)]
        #expect(RepoLookup.mainPath(forWorktreePath: "/repos/a-feature", in: repos) == "/repos/a")
    }

    @Test("an untracked path resolves to nil")
    func untrackedPathResolvesToNil() {
        let repos = [Self.repo("/repos/a", worktrees: [Self.worktree("/repos/a", isMain: true)])]
        #expect(RepoLookup.mainPath(forWorktreePath: "/repos/unknown", in: repos) == nil)
    }

    @Test("an empty repo list resolves to nil")
    func emptyRepoListResolvesToNil() {
        #expect(RepoLookup.mainPath(forWorktreePath: "/repos/a", in: []) == nil)
    }
}
