import Foundation

public enum DiffServiceError: Error, Sendable {
    case gitFailed(String)
}

/// Produces a parsed diff between two revisions, optionally folding in uncommitted working-tree
/// changes (staged, unstaged, and untracked files).
public struct DiffService: Sendable {
    public let git: GitRunner

    public init(git: GitRunner) {
        self.git = git
    }

    /// Fetches and parses the diff for the given request.
    ///
    /// - When `includeUncommitted` is `false`, this is a plain PR-style range diff
    ///   (`git diff base...head`), i.e. `head`'s changes since it diverged from `base`.
    /// - When `true`, the range is recomputed against the merge-base and diffed straight against
    ///   the working tree (`git diff <merge-base>`), so both committed and uncommitted changes
    ///   show up without double-counting; untracked files are appended as synthetic additions.
    public func diff(base: String, head: String, includeUncommitted: Bool) async throws -> [DiffFile] {
        guard includeUncommitted else {
            return try await runDiff(["diff", "--no-color", "\(base)...\(head)"])
        }
        let mergeBase = await resolvedMergeBase(base: base, head: head)
        var files = try await runDiff(["diff", "--no-color", mergeBase])
        files.append(contentsOf: try await untrackedFilesAsAdditions())
        return files
    }

    /// Fetches the full content of `path` as it exists at `ref`, split into lines with any
    /// trailing newline dropped — used to reveal a diff hunk's collapsed context lines, which
    /// aren't present in the unified diff output itself.
    public func fileContent(ref: String, path: String) async throws -> [String] {
        let result = try await git.run(["show", "\(ref):\(path)"])
        guard result.succeeded else {
            throw DiffServiceError.gitFailed(result.standardError)
        }
        var lines = result.standardOutput.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if result.standardOutput.hasSuffix("\n") { lines.removeLast() }
        return lines
    }

    private func resolvedMergeBase(base: String, head: String) async -> String {
        guard let result = try? await git.run(["merge-base", base, head]), result.succeeded else {
            return base
        }
        let sha = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        return sha.isEmpty ? base : sha
    }

    private func runDiff(_ arguments: [String]) async throws -> [DiffFile] {
        let result = try await git.run(arguments)
        guard result.succeeded else {
            throw DiffServiceError.gitFailed(result.standardError)
        }
        return UnifiedDiffParser.parse(result.standardOutput)
    }

    private func untrackedFilesAsAdditions() async throws -> [DiffFile] {
        let listing = try await git.run(["ls-files", "--others", "--exclude-standard"])
        guard listing.succeeded else { return [] }
        let paths = listing.standardOutput.split(separator: "\n").map(String.init)

        var files: [DiffFile] = []
        for path in paths where !path.isEmpty {
            // `--no-index` against /dev/null exits 1 (a diff was found), not 0 — check the output
            // itself rather than the exit code.
            guard let result = try? await git.run(["diff", "--no-color", "--no-index", "/dev/null", path]),
                !result.standardOutput.isEmpty
            else { continue }
            files.append(contentsOf: UnifiedDiffParser.parse(result.standardOutput))
        }
        return files
    }
}
