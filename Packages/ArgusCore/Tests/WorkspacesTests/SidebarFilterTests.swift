import Testing

@testable import Workspaces

struct SidebarFilterTests {
    private let repos = [
        GitRepo(
            name: "Argus", mainPath: "/w/Argus",
            worktrees: [
                GitWorktree(path: "/w/Argus", branch: "main", isMain: true),
                GitWorktree(path: "/w/Argus-palette", branch: "feat/palette", isMain: false),
            ]),
        GitRepo(
            name: "Other", mainPath: "/w/Other",
            worktrees: [GitWorktree(path: "/w/Other", branch: "develop", isMain: true)]),
    ]

    @Test func noFilterReturnsInputUntouched() {
        #expect(SidebarFilter.apply(repos: repos, query: "  ", attentionIDs: nil) == repos)
    }

    @Test func queryMatchesBranchAndDropsEmptyRepos() {
        let result = SidebarFilter.apply(repos: repos, query: "palette", attentionIDs: nil)
        #expect(result.map(\.name) == ["Argus"])
        #expect(result.first?.worktrees.map(\.id) == ["/w/Argus-palette"])
    }

    @Test func repoNameMatchKeepsAllItsWorktrees() {
        let result = SidebarFilter.apply(repos: repos, query: "argus", attentionIDs: nil)
        #expect(result.map(\.name) == ["Argus"])
        #expect(result.first?.worktrees.count == 2)
    }

    @Test func attentionSetRestrictsWorktrees() {
        let result = SidebarFilter.apply(repos: repos, query: "", attentionIDs: ["/w/Other"])
        #expect(result.map(\.name) == ["Other"])
    }

    @Test func attentionAndQueryCombine() {
        let result = SidebarFilter.apply(repos: repos, query: "argus", attentionIDs: ["/w/Argus-palette"])
        #expect(result.first?.worktrees.map(\.id) == ["/w/Argus-palette"])
    }

    @Test func emptyAttentionSetShowsNothing() {
        #expect(SidebarFilter.apply(repos: repos, query: "", attentionIDs: []).isEmpty)
    }
}
