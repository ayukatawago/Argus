import Testing

@testable import Workspaces

@Suite("RepoAddPlanner")
struct RepoAddPlannerTests {
    private func plan(
        _ path: String, roots: [String] = [], excluded: Set<String> = [], gitRepos: Set<String> = [],
        links: [String: String] = [:]
    ) -> RepoAddPlanner.Plan {
        RepoAddPlanner.plan(
            path: path, roots: roots, excluded: excluded,
            isGitRepo: { gitRepos.contains($0) }, resolve: { links[$0] ?? $0 })
    }

    @Test("an unrelated path becomes a new root")
    func unrelated() {
        #expect(plan("/x/repo", roots: ["/w"]).roots == ["/w", "/x/repo"])
    }

    @Test("a path that is already a root adds nothing")
    func alreadyRoot() {
        #expect(plan("/x/repo", roots: ["/x/repo"]).roots == ["/x/repo"])
    }

    @Test("a child of a non-git root is already scanned, so adds nothing")
    func childOfNonGitRoot() {
        #expect(plan("/w/repo", roots: ["/w"]).roots == ["/w"])
    }

    @Test("a child of a root that is itself a repo isn't scanned, so it needs its own root")
    func childOfGitRoot() {
        #expect(plan("/w/sub", roots: ["/w"], gitRepos: ["/w"]).roots == ["/w", "/w/sub"])
    }

    @Test("an excluded path that is covered is only un-excluded")
    func excludedAndCovered() {
        let result = plan("/w/repo", roots: ["/w"], excluded: ["/w/repo", "/w/other"])
        #expect(result.roots == ["/w"])
        #expect(result.excluded == ["/w/other"])
    }

    @Test("an excluded path that is not covered is un-excluded and added")
    func excludedNotCovered() {
        let result = plan("/x/repo", roots: ["/w"], excluded: ["/x/repo"])
        #expect(result.roots == ["/w", "/x/repo"])
        #expect(result.excluded.isEmpty)
    }

    @Test("a symlinked root spelling doesn't produce a duplicate root")
    func symlinkedRoot() {
        let links = ["/home/w": "/real/w", "/home/w/repo": "/real/w/repo"]
        #expect(plan("/real/w/repo", roots: ["/home/w"], links: links).roots == ["/home/w"])
        #expect(plan("/real/w", roots: ["/home/w"], links: links).roots == ["/home/w"])
    }

    @Test("a symlinked excluded spelling is still un-excluded")
    func symlinkedExcluded() {
        let links = ["/home/w/repo": "/real/w/repo"]
        #expect(plan("/real/w/repo", roots: ["/w"], excluded: ["/home/w/repo"], links: links).excluded.isEmpty)
    }
}
