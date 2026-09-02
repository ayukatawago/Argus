import ArgusConfigKit
import ArgusSupport
import Foundation
import Monitors

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
    var approvedBy: [String] = []
    var approvedByMe: Bool = false

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
        approvedBy = []
    }

    var repoName: String { repositoryURL.lastPathComponent }
}

extension GitHubPR: CategorizablePullRequest {}
extension GitHubPR: ApprovalTrackable {}

private struct GitHubAuthUser: Decodable {
    let login: String
}

private struct GitHubPRDetail: Decodable {
    struct Base: Decodable {
        let ref: String
    }

    let base: Base
}

private struct GitHubReview: Decodable {
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

private struct PREnrichment: Sendable {
    var baseBranch: String?
    var approvedBy: [String] = []
}

/// A sidebar bucket (My Open PRs, My Drafts, Assigned, Do Not Merge) split into what's currently
/// shown and what the user hid, so `PRMonitorView` can render a hidden count and a reveal-all
/// button per section without re-deriving the split itself.
struct PRSection {
    var visible: [GitHubPR] = []
    var hidden: [GitHubPR] = []

    var hiddenIDs: Set<Int> { Set(hidden.map(\.id)) }
    var isEmpty: Bool { visible.isEmpty && hidden.isEmpty }
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
    @Published private(set) var myOpen = PRSection()
    @Published private(set) var myDrafts = PRSection()
    @Published private(set) var assigned = PRSection()
    @Published private(set) var doNotMerge = PRSection()
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?
    @Published private(set) var highlightedPRIDs: Set<Int> = []

    private var pollTask: Task<Void, Never>?
    private var resolvedUsername: String?
    private let highlightTracker = PRHighlightTracker()
    private var hidden = PRHiddenList(ids: PRHiddenFile.load(from: PRMonitorStore.hiddenPRsURL))
    private var lastCategorized: PRCategorizer.Categorized<GitHubPR>?

    var hasAnyPRs: Bool {
        !myOpen.isEmpty || !myDrafts.isEmpty || !assigned.isEmpty || !doNotMerge.isEmpty
    }

    func start() {
        guard pollTask == nil else { return }
        Task { await refresh() }
        pollTask = PollingTask.repeating(
            order: .sleepThenAct,
            interval: {
                let seconds = await ArgusConfigStore.shared.config.github.refreshIntervalSeconds
                return UInt64(seconds * 1_000_000_000)
            },
            action: { [weak self] in await self?.refresh() }
        )
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        resolvedUsername = nil
    }

    func dismissHighlight(prID: Int) {
        highlightTracker.dismiss(id: prID)
        highlightedPRIDs = highlightTracker.highlightedIDs
    }

    /// Hides a single PR from the sidebar. Deliberately doesn't touch its approval highlight —
    /// a PR whose approvals changed while hidden should still show highlighted once revealed.
    func hide(prID: Int) {
        guard hidden.hide(prID) else { return }
        PRHiddenFile.save(hidden.ids, to: Self.hiddenPRsURL)
        applySections()
    }

    /// Reveals every given id (a section's "reveal all hidden" button).
    func reveal(ids: Set<Int>) {
        guard hidden.reveal(ids) else { return }
        PRHiddenFile.save(hidden.ids, to: Self.hiddenPRsURL)
        applySections()
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
        let (authoredPRs, assignedPRs) = try await (authored, assigned)

        var seen = Set<Int>()
        let allPRs = (authoredPRs + assignedPRs).filter { seen.insert($0.id).inserted }
        let enrichments = await enrichDetails(for: allPRs, config: config)

        func enrich(_ prs: [GitHubPR]) -> [GitHubPR] {
            prs.map { pullRequest in
                var copy = pullRequest
                copy.baseBranch = enrichments[pullRequest.id]?.baseBranch
                copy.approvedBy = enrichments[pullRequest.id]?.approvedBy ?? []
                return copy
            }
        }

        let categorized = PRCategorizer.categorize(
            authored: enrich(authoredPRs),
            assigned: enrich(assignedPRs),
            username: username
        )
        lastCategorized = categorized
        highlightTracker.update(trackable: categorized.myOpenPRs + categorized.reviewRequestedPRs)
        highlightedPRIDs = highlightTracker.highlightedIDs

        // Prune ids no longer present in this successful fetch (merged/closed/unassigned) so the
        // hidden set can't grow forever. Never runs on a failed fetch — the throw happens above.
        if hidden.prune(keeping: Set(allPRs.map(\.id))) {
            PRHiddenFile.save(hidden.ids, to: Self.hiddenPRsURL)
        }
        applySections()
    }

    /// Re-derives the four published sections from the last successful fetch, applying the
    /// current hidden set. Called after every fetch and every hide/reveal.
    private func applySections() {
        guard let categorized = lastCategorized else { return }
        func section(_ prs: [GitHubPR]) -> PRSection {
            let (visible, hiddenPRs) = hidden.split(prs)
            return PRSection(visible: visible, hidden: hiddenPRs)
        }
        myOpen = section(categorized.myOpenPRs)
        myDrafts = section(categorized.myDraftPRs)
        assigned = section(categorized.reviewRequestedPRs)
        doNotMerge = section(categorized.doNotMergePRs)
    }

    private func enrichDetails(for prs: [GitHubPR], config: ArgusConfig.GitHub) async -> [Int: PREnrichment] {
        await withTaskGroup(of: (Int, PREnrichment).self) { group in
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
                    guard let detailURL = URL(string: "\(apiBase)/repos/\(repoPath)/pulls/\(prNumber)"),
                        let reviewsURL = URL(string: "\(apiBase)/repos/\(repoPath)/pulls/\(prNumber)/reviews")
                    else {
                        return (prID, PREnrichment())
                    }
                    let detail: GitHubPRDetail? = try? await PRMonitorStore.githubFetch(url: detailURL, token: token)
                    let reviews: [GitHubReview] =
                        (try? await PRMonitorStore.githubFetch(url: reviewsURL, token: token)) ?? []
                    return (
                        prID,
                        PREnrichment(
                            baseBranch: detail?.base.ref,
                            approvedBy: PRMonitorStore.approvedLogins(from: reviews)
                        )
                    )
                }
            }
            var result: [Int: PREnrichment] = [:]
            for await (prID, enrichment) in group {
                result[prID] = enrichment
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

    private nonisolated static var hiddenPRsURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("argus/hidden-prs.json")
            ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/argus/hidden-prs.json")
    }

    private nonisolated static func approvedLogins(from reviews: [GitHubReview]) -> [String] {
        PRApprovalDigest.approvedLogins(
            from: reviews.map {
                ReviewSubmission(login: $0.user.login, state: $0.state, submittedAt: $0.submittedAt)
            })
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
