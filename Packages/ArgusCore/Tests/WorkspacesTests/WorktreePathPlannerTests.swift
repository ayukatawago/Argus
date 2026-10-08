import Testing

@testable import Workspaces

@Suite("WorktreePathPlanner")
struct WorktreePathPlannerTests {
    @Test("the worktree is a sibling of the main checkout, named after the branch")
    func sibling() {
        #expect(WorktreePathPlanner.path(forBranch: "fix", repoMainPath: "/w/repo") == "/w/fix")
    }

    @Test("slashes in a branch name become dashes so it stays one folder")
    func slashesFlattened() {
        #expect(
            WorktreePathPlanner.path(forBranch: "feature/login/ui", repoMainPath: "/w/repo") == "/w/feature-login-ui")
    }

    @Test("surrounding whitespace is trimmed")
    func trimmed() {
        #expect(WorktreePathPlanner.path(forBranch: "  fix\n", repoMainPath: "/w/repo") == "/w/fix")
    }

    @Test("a trailing slash on the repo path does not change the parent", arguments: ["/w/repo/", "/w/repo"])
    func trailingSlash(repo: String) {
        #expect(WorktreePathPlanner.path(forBranch: "x", repoMainPath: repo) == "/w/x")
    }

    @Test("names that cannot be a safe folder are rejected", arguments: ["", "   ", ".", "..", "a\0b"])
    func rejected(branch: String) {
        #expect(WorktreePathPlanner.path(forBranch: branch, repoMainPath: "/w/repo") == nil)
    }

    @Test("a name with embedded dots is fine")
    func dots() {
        #expect(WorktreePathPlanner.path(forBranch: "v1.2..3", repoMainPath: "/w/repo") == "/w/v1.2..3")
    }
}
