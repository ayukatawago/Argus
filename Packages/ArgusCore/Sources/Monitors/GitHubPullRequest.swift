import Foundation

/// One pull request as returned by GitHub's `/search/issues`, plus the per-PR detail
/// (`baseBranch`, `approvedBy`, `approvedByMe`) filled in afterwards by `GitHubClient.enrichment`.
public struct GitHubPR: Decodable, Identifiable, Sendable {
    public let id: Int
    public let number: Int
    public let title: String
    public let htmlURL: URL
    public let repositoryURL: URL
    public let draft: Bool
    public let authorLogin: String
    public let labelNames: [String]
    public var baseBranch: String?
    public var approvedBy: [String] = []
    public var approvedByMe: Bool = false

    private struct UserField: Decodable {
        let login: String
    }

    private struct LabelField: Decodable {
        let name: String
    }

    enum CodingKeys: String, CodingKey {
        case id, number, title, draft, user, labels
        case htmlURL = "html_url"
        case repositoryURL = "repository_url"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        number = try container.decode(Int.self, forKey: .number)
        title = try container.decode(String.self, forKey: .title)
        draft = try container.decode(Bool.self, forKey: .draft)
        htmlURL = try container.decode(URL.self, forKey: .htmlURL)
        repositoryURL = try container.decode(URL.self, forKey: .repositoryURL)
        authorLogin = try container.decode(UserField.self, forKey: .user).login
        labelNames = try container.decode([LabelField].self, forKey: .labels).map(\.name)
        baseBranch = nil
        approvedBy = []
    }

    public var repoName: String { repositoryURL.lastPathComponent }
}

extension GitHubPR: CategorizablePullRequest {}
extension GitHubPR: ApprovalTrackable {}

/// What the follow-up per-PR requests add to a search hit.
public struct PREnrichment: Sendable, Equatable {
    public var baseBranch: String?
    public var approvedBy: [String] = []

    public init(baseBranch: String? = nil, approvedBy: [String] = []) {
        self.baseBranch = baseBranch
        self.approvedBy = approvedBy
    }
}

public enum PRMonitorError: Error, LocalizedError, Equatable {
    case badURL
    case missingCredentials
    case httpError(Int, body: String)

    public var errorDescription: String? {
        switch self {
        case .badURL: return "Invalid API base URL."
        case .missingCredentials: return "Token is required."

        case .httpError(let code, let body):
            let snippet = body.isEmpty ? "" : " — \(body.prefix(120))"
            return "GitHub API error (HTTP \(code))\(snippet)"
        }
    }
}
