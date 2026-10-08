import Foundation

/// Resolves git refs and a sensible default base branch for a diff review.
public struct RevisionResolver: Sendable {
    public let git: GitRunner

    public init(git: GitRunner) {
        self.git = git
    }

    /// Local and remote branch names, most-recently-committed first.
    public func listBranches() async -> [String] {
        let result = try? await git.run([
            "for-each-ref",
            "--sort=-committerdate",
            "--format=%(refname)",
            "refs/heads/", "refs/remotes/",
        ])
        guard let result, result.succeeded else { return [] }
        return Self.parseBranches(result.standardOutput)
    }

    /// Turns full refnames into short branch names, dropping only the remotes' own `HEAD` symbolic
    /// refs (`refs/remotes/<remote>/HEAD`) — not a local or remote branch merely named `.../HEAD`.
    static func parseBranches(_ output: String) -> [String] {
        output
            .split(separator: "\n")
            .map(String.init)
            .compactMap { ref in
                if ref.hasPrefix("refs/heads/") { return String(ref.dropFirst("refs/heads/".count)) }
                guard ref.hasPrefix("refs/remotes/") else { return nil }
                let short = String(ref.dropFirst("refs/remotes/".count))
                let parts = short.split(separator: "/", omittingEmptySubsequences: false)
                return parts.count == 2 && parts[1] == "HEAD" ? nil : short
            }
    }

    /// Best-effort default base ref: the remote's default branch (origin/HEAD), falling back to
    /// `origin/main`, `origin/master`, `main`, then `master`.
    public func defaultBase() async -> String {
        if let symbolic = try? await git.run(["symbolic-ref", "refs/remotes/origin/HEAD"]),
            symbolic.succeeded
        {
            let ref = symbolic.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            let short = ref.replacingOccurrences(of: "refs/remotes/", with: "")
            if !short.isEmpty { return short }
        }
        for candidate in ["origin/main", "origin/master", "main", "master"] {
            if let check = try? await git.run(["rev-parse", "--verify", "--quiet", candidate]),
                check.succeeded
            {
                return candidate
            }
        }
        return "HEAD"
    }

    /// The worktree's current branch name (short form), or `nil` when detached.
    public func currentBranch() async -> String? {
        guard let result = try? await git.run(["symbolic-ref", "--short", "-q", "HEAD"]), result.succeeded
        else { return nil }
        let name = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    /// Commits reachable from `head` but not `base` (`base..head`), newest first. Empty when
    /// `base` is empty/unresolved or the log fails (e.g. either ref doesn't exist yet).
    public func listCommits(base: String, head: String) async -> [Commit] {
        guard !base.isEmpty else { return [] }
        let result = try? await git.run([
            "log", "--no-color",
            "--format=\(Self.logFormat)",
            "\(base)..\(head)",
        ])
        guard let result, result.succeeded else { return [] }
        return Self.parseCommits(result.standardOutput)
    }

    private static let fieldSeparator = "\u{1f}"
    private static let logFormat = ["%H", "%h", "%s", "%an", "%ar", "%P"].joined(separator: fieldSeparator)

    /// Parses `git log --format=<logFormat>` output (one commit per line, six unit-separated fields).
    static func parseCommits(_ output: String) -> [Commit] {
        output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line in
                let fields = String(line).components(separatedBy: fieldSeparator)
                guard fields.count == 6 else { return nil }
                return Commit(
                    hash: fields[0],
                    shortHash: fields[1],
                    subject: fields[2],
                    author: fields[3],
                    relativeDate: fields[4],
                    isRoot: fields[5].trimmingCharacters(in: .whitespaces).isEmpty
                )
            }
    }
}
