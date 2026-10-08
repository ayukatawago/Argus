import Foundation

/// A small GitHub REST client for the PR monitor. The `URLSession` is injectable so every request
/// shape and response path is unit-testable with a stubbed `URLProtocol`, without the network.
public struct GitHubClient: Sendable {
    /// GitHub's search endpoint returns 30 results by default; 100 is its per-page maximum.
    public static let pageSize = 100

    private struct SearchResult: Decodable {
        let items: [GitHubPR]
    }

    private struct AuthUser: Decodable {
        let login: String
    }

    private struct PRDetail: Decodable {
        struct Base: Decodable {
            let ref: String
        }

        let base: Base
    }

    private struct Review: Decodable {
        struct Reviewer: Decodable {
            let login: String
        }

        enum CodingKeys: String, CodingKey {
            case user, state
            case submittedAt = "submitted_at"
        }

        let user: Reviewer
        let state: String
        let submittedAt: String
    }

    public let apiBaseURL: String
    public let token: String
    private let session: URLSession

    public init(apiBaseURL: String, token: String, session: URLSession = .shared) {
        self.apiBaseURL = apiBaseURL
        self.token = token
        self.session = session
    }

    // MARK: - Endpoints

    /// The authenticated user's login.
    public func authenticatedUser() async throws -> String {
        let user: AuthUser = try await fetch(try endpoint("/user"))
        return user.login
    }

    /// Open PRs matching a GitHub search `query` (e.g. `is:pr is:open author:me`). Reserved
    /// characters in the query are percent-encoded; up to `pageSize` results are requested.
    public func searchPullRequests(query: String) async throws -> [GitHubPR] {
        let url = try endpoint("/search/issues", query: [("q", query), ("per_page", String(Self.pageSize))])
        let result: SearchResult = try await fetch(url)
        return result.items
    }

    /// Base branch and approving reviewers for `pullRequest`. Best-effort: a failure of either
    /// request yields the corresponding field empty rather than failing the whole refresh.
    public func enrichment(for pullRequest: GitHubPR) async -> PREnrichment {
        guard let repoPath = Self.repoPath(from: pullRequest.repositoryURL) else { return PREnrichment() }
        let base = "/repos/\(repoPath)/pulls/\(pullRequest.number)"
        let detail: PRDetail? = try? await fetch(try endpoint(base))
        let reviews: [Review] =
            (try? await fetch(try endpoint(base + "/reviews", query: [("per_page", "100")]))) ?? []
        return PREnrichment(
            baseBranch: detail?.base.ref,
            approvedBy: Self.approvedLogins(from: reviews)
        )
    }

    // MARK: - Pure helpers

    /// `owner/name` from a search hit's `repository_url` (`…/repos/<owner>/<name>`).
    public static func repoPath(from repositoryURL: URL) -> String? {
        let components = repositoryURL.pathComponents
        guard let reposIndex = components.firstIndex(of: "repos"), reposIndex + 2 < components.count else {
            return nil
        }
        return "\(components[reposIndex + 1])/\(components[reposIndex + 2])"
    }

    private static func approvedLogins(from reviews: [Review]) -> [String] {
        PRApprovalDigest.approvedLogins(
            from: reviews.map { ReviewSubmission(login: $0.user.login, state: $0.state, submittedAt: $0.submittedAt) })
    }

    func endpoint(_ path: String, query: [(String, String)] = []) throws -> URL {
        guard var components = URLComponents(string: apiBaseURL) else { throw PRMonitorError.badURL }
        // `apiBaseURL` may carry a path (GitHub Enterprise: `https://host/api/v3`) and a trailing slash.
        components.path = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        components.path += path
        if !query.isEmpty { components.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) } }
        guard components.scheme != nil, components.host != nil, let url = components.url else {
            throw PRMonitorError.badURL
        }
        return url
    }

    // MARK: - Transport

    private func fetch<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(statusCode) else {
            throw PRMonitorError.httpError(statusCode, body: String(decoding: data, as: UTF8.self))
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
