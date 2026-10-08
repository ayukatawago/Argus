import Foundation
import Testing

@testable import Monitors

/// Serves canned responses to a `URLSession` and records what it was asked for.
private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (Int, String))?
    nonisolated(unsafe) static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        let (status, body) = Self.handler?(request) ?? (500, "")
        guard let url = request.url,
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("GitHubClient", .serialized)
struct GitHubClientTests {
    private static let searchBody = """
        {"items":[{"id":1,"number":7,"title":"Add thing","html_url":"https://ghe.example/o/r/pull/7",\
        "repository_url":"https://ghe.example/api/v3/repos/o/r","draft":false,"user":{"login":"me"},\
        "labels":[{"name":"x"}]}]}
        """

    private func client(
        base: String = "https://api.example.com", handler: @escaping @Sendable (URLRequest) -> (Int, String)
    ) -> GitHubClient {
        StubURLProtocol.handler = handler
        StubURLProtocol.requests = []
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return GitHubClient(apiBaseURL: base, token: "tok", session: URLSession(configuration: configuration))
    }

    @Test("a search requests the maximum page size, encodes the query and sends the bearer token")
    func searchRequestShape() async throws {
        let client = client { _ in (200, Self.searchBody) }
        let prs = try await client.searchPullRequests(query: "is:pr is:open author:me")
        #expect(prs.count == 1)
        #expect(prs[0].number == 7)
        #expect(prs[0].authorLogin == "me")
        #expect(prs[0].labelNames == ["x"])
        #expect(prs[0].repoName == "r")

        let request = try #require(StubURLProtocol.requests.first)
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.path == "/search/issues")
        #expect(components.queryItems?.first { $0.name == "q" }?.value == "is:pr is:open author:me")
        #expect(components.queryItems?.first { $0.name == "per_page" }?.value == "100")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github.v3+json")
    }

    @Test("an enterprise base URL with a path and trailing slash is joined correctly")
    func enterpriseBase() async throws {
        let client = client(base: "https://ghe.example/api/v3/") { _ in (200, #"{"login":"octo"}"#) }
        #expect(try await client.authenticatedUser() == "octo")
        #expect(StubURLProtocol.requests.first?.url?.path == "/api/v3/user")
    }

    @Test("a non-2xx response throws an HTTP error carrying the status and body")
    func httpError() async {
        let client = client { _ in (401, #"{"message":"Bad credentials"}"#) }
        await #expect(throws: PRMonitorError.httpError(401, body: #"{"message":"Bad credentials"}"#)) {
            _ = try await client.authenticatedUser()
        }
    }

    @Test("a malformed body throws a decoding error")
    func malformedBody() async {
        let client = client { _ in (200, "not json") }
        await #expect(throws: DecodingError.self) { _ = try await client.searchPullRequests(query: "x") }
    }

    @Test(
        "an unusable base URL is reported as badURL before any request is made",
        arguments: ["", "no scheme here", "/just/a/path"])
    func badBaseURL(base: String) async {
        let client = client(base: base) { _ in (200, "{}") }
        await #expect(throws: PRMonitorError.badURL) { _ = try await client.authenticatedUser() }
        #expect(StubURLProtocol.requests.isEmpty)
    }

    @Test("enrichment reads the base branch and the approving reviewers")
    func enrichment() async throws {
        let reviews = """
            [{"user":{"login":"alice"},"state":"APPROVED","submitted_at":"2026-01-01T00:00:00Z"},\
            {"user":{"login":"bob"},"state":"COMMENTED","submitted_at":"2026-01-01T00:00:00Z"}]
            """
        let client = client { request in
            let path = request.url?.path ?? ""
            if path.hasSuffix("/reviews") { return (200, reviews) }
            if path.hasSuffix("/pulls/7") { return (200, #"{"base":{"ref":"main"}}"#) }
            if path.hasSuffix("/search/issues") { return (200, Self.searchBody) }
            return (404, "")
        }
        let pr = try #require(try await client.searchPullRequests(query: "x").first)
        let result = await client.enrichment(for: pr)
        #expect(result == PREnrichment(baseBranch: "main", approvedBy: ["alice"]))
        #expect(StubURLProtocol.requests.contains { $0.url?.path == "/repos/o/r/pulls/7/reviews" })
    }

    @Test("enrichment degrades to empty when both detail requests fail")
    func enrichmentFailure() async throws {
        let client = client { request in
            request.url?.path.hasSuffix("/search/issues") == true ? (200, Self.searchBody) : (500, "boom")
        }
        let pr = try #require(try await client.searchPullRequests(query: "x").first)
        #expect(await client.enrichment(for: pr) == PREnrichment())
    }

    private func repoURL(_ string: String) -> URL { URL(string: string) ?? URL(fileURLWithPath: "/") }

    @Test("repoPath extracts owner/name and rejects URLs without a repos segment")
    func repoPath() {
        #expect(GitHubClient.repoPath(from: repoURL("https://api.github.com/repos/o/r")) == "o/r")
        #expect(GitHubClient.repoPath(from: repoURL("https://ghe.example/api/v3/repos/team/app")) == "team/app")
        #expect(GitHubClient.repoPath(from: repoURL("https://api.github.com/repos/o")) == nil)
        #expect(GitHubClient.repoPath(from: repoURL("https://api.github.com/users/o/r")) == nil)
    }

    @Test("error descriptions are readable and truncate long bodies")
    func errorDescriptions() {
        #expect(PRMonitorError.badURL.errorDescription == "Invalid API base URL.")
        #expect(PRMonitorError.missingCredentials.errorDescription == "Token is required.")
        #expect(PRMonitorError.httpError(403, body: "").errorDescription == "GitHub API error (HTTP 403)")
        let long = String(repeating: "x", count: 500)
        #expect((PRMonitorError.httpError(500, body: long).errorDescription ?? "").count < 200)
    }
}
