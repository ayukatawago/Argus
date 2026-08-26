import Foundation
import Testing

@testable import DiffReviewKit

/// The number of fds this process currently has open, via `/dev/fd` (each entry there is one live
/// descriptor) — used to assert `GitRunner` releases every pipe fd it opens rather than relying on
/// ARC to eventually catch up.
private func openFileDescriptorCount() -> Int {
    (try? FileManager.default.contentsOfDirectory(atPath: "/dev/fd").count) ?? -1
}

private func makeTempGitRepo() async -> String {
    let path = NSTemporaryDirectory() + "GitRunnerTests-\(UUID().uuidString)"
    try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    let git = GitRunner(repositoryPath: path)
    _ = try? await git.run(["init", "-q"])
    _ = try? await git.run(
        ["-c", "user.email=test@example.com", "-c", "user.name=Test", "commit", "--allow-empty", "-q", "-m", "init"])
    return path
}

// `.serialized`: the fd-leak tests below count this process's *total* open fds, which swift-testing's
// default concurrent test execution would otherwise pollute with other tests' transient pipes.
@Suite("GitRunner", .serialized)
struct GitRunnerTests {
    @Test("runs git against the given repository path and captures stdout")
    func capturesStdout() async throws {
        let path = await makeTempGitRepo()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let git = GitRunner(repositoryPath: path)
        let result = try await git.run(["log", "--oneline"])
        #expect(result.succeeded)
        #expect(result.standardOutput.contains("init"))
    }

    @Test("a nonexistent repository path surfaces git's stderr and non-zero exit code, not a thrown error")
    func nonexistentPathIsNotThrown() async throws {
        let git = GitRunner(repositoryPath: "/no/such/repo/path")
        let result = try await git.run(["status"])
        #expect(!result.succeeded)
        #expect(!result.standardError.isEmpty)
    }

    @Test("a missing git executable throws executableNotFound")
    func missingExecutableThrows() async throws {
        let git = GitRunner(repositoryPath: "/tmp", executablePath: "/no/such/git")
        await #expect(throws: GitRunner.GitError.self) {
            _ = try await git.run(["status"])
        }
    }

    @Test("a process that outlives its timeout is terminated and reported as a failed result")
    func timeoutTerminatesAHungProcess() async throws {
        // `git` has no built-in "sleep" subcommand, so exercise the timeout via a repo whose
        // `executablePath` points at a real sleep binary instead of git — the timeout plumbing
        // doesn't care what the child binary is.
        let git = GitRunner(repositoryPath: "/tmp", executablePath: "/bin/sleep")
        let result = try await git.run(["5"], timeout: 0.2)
        #expect(!result.succeeded)
    }

    @Test("GitError.launchFailed and executableNotFound have readable descriptions")
    func errorsAreLocalized() {
        #expect(GitRunner.GitError.executableNotFound.localizedDescription.contains("git"))
        let fdError = GitRunner.GitError.launchFailed("Bad file descriptor")
        #expect(fdError.localizedDescription.contains("file descriptors"))
    }

    // MARK: - fd leak regressions
    //
    // Mirrors ArgusSupport's ProcessRunnerTests: every pipe fd `run` opens must be closed by the
    // time it returns, on every completion path.

    @Test("repeated successful runs do not leak file descriptors")
    func noLeakOnSuccess() async throws {
        let path = await makeTempGitRepo()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let git = GitRunner(repositoryPath: path)
        let before = openFileDescriptorCount()
        for _ in 0..<100 {
            _ = try await git.run(["log", "--oneline"])
        }
        let after = openFileDescriptorCount()
        #expect(after - before <= 5, "fd count grew from \(before) to \(after) over 100 successful runs")
    }

    @Test("repeated launch failures do not leak file descriptors")
    func noLeakOnLaunchFailure() async {
        let git = GitRunner(repositoryPath: "/tmp", executablePath: "/no/such/binary")
        let before = openFileDescriptorCount()
        for _ in 0..<100 {
            _ = try? await git.run(["status"])
        }
        let after = openFileDescriptorCount()
        #expect(after - before <= 5, "fd count grew from \(before) to \(after) over 100 launch failures")
    }

    @Test("repeated timeouts do not leak file descriptors")
    func noLeakOnTimeout() async throws {
        let git = GitRunner(repositoryPath: "/tmp", executablePath: "/bin/sleep")
        let before = openFileDescriptorCount()
        for _ in 0..<20 {
            _ = try await git.run(["5"], timeout: 0.05)
        }
        let after = openFileDescriptorCount()
        #expect(after - before <= 5, "fd count grew from \(before) to \(after) over 20 timeouts")
    }
}
