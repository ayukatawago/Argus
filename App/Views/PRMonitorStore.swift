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

    enum CodingKeys: String, CodingKey {
        case id, number, title, draft
        case htmlURL = "html_url"
        case repositoryURL = "repository_url"
    }

    var repoName: String { repositoryURL.lastPathComponent }
}

private struct GitHubUser: Decodable {
    let login: String
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
        let user: GitHubUser = try await githubRequest(url: url, token: config.token)
        return user.login
    }

    private func fetchAndCategorize(username: String, config: ArgusConfig.GitHub) async throws {
        async let authored = searchPRs(query: "is:pr+is:open+author:\(username)", config: config)
        async let reviewRequested = searchPRs(query: "is:pr+is:open+review-requested:\(username)", config: config)
        let (authoredPRs, reviewPRs) = try await (authored, reviewRequested)
        myOpenPRs = authoredPRs.filter { !$0.draft }
        myDraftPRs = authoredPRs.filter { $0.draft }
        // Exclude PRs the user authored from review-requested (they can't review their own)
        let authoredIDs = Set(authoredPRs.map(\.id))
        reviewRequestedPRs = reviewPRs.filter { !authoredIDs.contains($0.id) }
    }

    private func searchPRs(query: String, config: ArgusConfig.GitHub) async throws -> [GitHubPR] {
        guard let url = URL(string: "\(config.apiBaseURL)/search/issues?q=\(query)") else {
            throw PRMonitorError.badURL
        }
        let result: GitHubSearchResult = try await githubRequest(url: url, token: config.token)
        return result.items
    }

    private func githubRequest<T: Decodable>(url: URL, token: String) async throws -> T {
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
