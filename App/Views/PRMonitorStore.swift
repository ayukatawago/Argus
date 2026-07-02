import Foundation

// MARK: - Models

struct GitHubSearchResult: Decodable {
    let items: [GitHubPR]
}

struct GitHubPR: Decodable, Identifiable {
    let id: Int
    let number: Int
    let title: String
    let htmlURL: URL
    let repositoryURL: URL
    let draft: Bool
    let authorLogin: String
    let labelNames: [String]
    var baseBranch: String?

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

    init(from decoder: Decoder) throws {
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
    }

    var repoName: String { repositoryURL.lastPathComponent }
}

private struct GitHubAuthUser: Decodable {
    let login: String
}

private struct GitHubPRDetail: Decodable {
    struct Base: Decodable {
        let ref: String
    }

    let base: Base
}

enum PRMonitorError: Error, LocalizedError {
    case badURL
    case missingCredentials
    case httpError(Int, body: String)

    var errorDescription: String? {
        switch self {
        case .badURL: return "Invalid API base URL."
        case .missingCredentials: return "Token is required."

        case .httpError(let code, let body):
            let snippet = body.isEmpty ? "" : " — \(body.prefix(120))"
            return "GitHub API error (HTTP \(code))\(snippet)"
        }
    }
}

// MARK: - Store

@MainActor
final class PRMonitorStore: ObservableObject {
    @Published private(set) var myOpenPRs: [GitHubPR] = []
    @Published private(set) var myDraftPRs: [GitHubPR] = []
    @Published private(set) var reviewRequestedPRs: [GitHubPR] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?

    private var pollTask: Task<Void, Never>?
    private var resolvedUsername: String?

    var hasAnyPRs: Bool { !myOpenPRs.isEmpty || !myDraftPRs.isEmpty || !reviewRequestedPRs.isEmpty }

    func start() {
        guard pollTask == nil else { return }
        Task { await refresh() }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                let interval = ArgusConfigStore.shared.config.github.refreshIntervalSeconds
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                await self?.refresh()
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        resolvedUsername = nil
    }

    func refresh() async {
        let config = ArgusConfigStore.shared.config.github
        guard !config.token.isEmpty else { return }
        isLoading = true
        lastError = nil
        do {
            if resolvedUsername == nil {
                resolvedUsername = try await fetchUsername(config: config)
            }
            guard let username = resolvedUsername else { return }
            try await fetchAndCategorize(username: username, config: config)
        } catch {
            lastError = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Private

    private func fetchUsername(config: ArgusConfig.GitHub) async throws -> String {
        guard let url = URL(string: "\(config.apiBaseURL)/user") else {
            throw PRMonitorError.badURL
        }
        let user: GitHubAuthUser = try await Self.githubFetch(url: url, token: config.token)
        return user.login
    }

    private func fetchAndCategorize(username: String, config: ArgusConfig.GitHub) async throws {
        async let authored = searchPRs(query: "is:pr+is:open+author:\(username)", config: config)
        async let assigned = searchPRs(query: "is:pr+is:open+assignee:\(username)", config: config)
        var (authoredPRs, assignedPRs) = try await (authored, assigned)
        authoredPRs = authoredPRs.filter { !$0.labelNames.contains("!!! DONT' MERGE !!!") }
        assignedPRs = assignedPRs.filter { !$0.labelNames.contains("!!! DONT' MERGE !!!") }

        let allPRs = Array(Set(authoredPRs.map(\.id)).union(Set(assignedPRs.map(\.id))))
            .compactMap { id in (authoredPRs + assignedPRs).first(where: { $0.id == id }) }
        let branches = await fetchBranches(for: allPRs, config: config)

        func enrich(_ prs: [GitHubPR]) -> [GitHubPR] {
            prs.map { pullRequest in
                var copy = pullRequest
                copy.baseBranch = branches[pullRequest.id]
                return copy
            }
        }

        authoredPRs = enrich(authoredPRs)
        assignedPRs = enrich(assignedPRs)

        myOpenPRs = authoredPRs.filter { !$0.draft }
        myDraftPRs = authoredPRs.filter { $0.draft }
        let authoredIDs = Set(authoredPRs.map(\.id))
        reviewRequestedPRs = assignedPRs.filter { !authoredIDs.contains($0.id) }
    }

    private func fetchBranches(for prs: [GitHubPR], config: ArgusConfig.GitHub) async -> [Int: String] {
        await withTaskGroup(of: (Int, String?).self) { group in
            for pullRequest in prs {
                let apiBase = config.apiBaseURL
                let token = config.token
                let prID = pullRequest.id
                let prNumber = pullRequest.number
                let components = pullRequest.repositoryURL.pathComponents
                guard let reposIdx = components.firstIndex(of: "repos"),
                    reposIdx + 2 < components.count
                else { continue }
                let repoPath = "\(components[reposIdx + 1])/\(components[reposIdx + 2])"
                group.addTask {
                    guard let url = URL(string: "\(apiBase)/repos/\(repoPath)/pulls/\(prNumber)") else {
                        return (prID, nil)
                    }
                    let detail: GitHubPRDetail? = try? await PRMonitorStore.githubFetch(url: url, token: token)
                    return (prID, detail?.base.ref)
                }
            }
            var result: [Int: String] = [:]
            for await (prID, branch) in group {
                if let branch {
                    result[prID] = branch
                }
            }
            return result
        }
    }

    private func searchPRs(query: String, config: ArgusConfig.GitHub) async throws -> [GitHubPR] {
        guard let url = URL(string: "\(config.apiBaseURL)/search/issues?q=\(query)") else {
            throw PRMonitorError.badURL
        }
        let result: GitHubSearchResult = try await Self.githubFetch(url: url, token: config.token)
        return result.items
    }

    private nonisolated static func githubFetch<T: Decodable>(url: URL, token: String) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        fputs("[PRMonitor] \(url.absoluteString) → HTTP \(statusCode)\n", stderr)
        guard (200..<300).contains(statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            fputs("[PRMonitor] body: \(body)\n", stderr)
            throw PRMonitorError.httpError(statusCode, body: body)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            fputs("[PRMonitor] decode error: \(error)\n", stderr)
            throw error
        }
    }
}
