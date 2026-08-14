import Foundation

/// A single GitHub PR review, reduced to what `PRApprovalDigest` needs — independent of the
/// GitHub REST API's own JSON shape (`GitHubReview`, decoded in the App target).
public struct ReviewSubmission: Sendable {
    public let login: String
    public let state: String
    public let submittedAt: String

    public init(login: String, state: String, submittedAt: String) {
        self.login = login
        self.state = state
        self.submittedAt = submittedAt
    }
}

/// Reduces a PR's review history to who currently has it approved.
public enum PRApprovalDigest {
    /// Returns the sorted logins whose *latest* review (by `submittedAt` string comparison, which
    /// works because GitHub's timestamps are ISO 8601 and therefore lexicographically ordered) is
    /// `"APPROVED"`.
    ///
    /// Locks current behavior: only the most recent review per login counts, so a reviewer who
    /// approved and *then* left a later `COMMENTED` (or any non-approving) review drops out of the
    /// approved list entirely — their approval isn't remembered once superseded. This may not be
    /// what a user expects (GitHub's own UI keeps a review "stale" rather than erasing it), but
    /// it's the existing, shipped behavior.
    public static func approvedLogins(from reviews: [ReviewSubmission]) -> [String] {
        var latestByLogin: [String: (date: String, state: String)] = [:]
        for review in reviews {
            let login = review.login
            if let existing = latestByLogin[login], existing.date >= review.submittedAt {
                continue
            }
            latestByLogin[login] = (review.submittedAt, review.state)
        }
        return latestByLogin.compactMap { login, pair in
            pair.state == "APPROVED" ? login : nil
        }.sorted()
    }
}
