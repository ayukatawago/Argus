import ArgusConfigKit
import ArgusSupport
import Foundation
import Monitors

/// A sidebar bucket (My Open PRs, My Drafts, Assigned, Do Not Merge) split into what's currently
/// shown and what the user hid, so `PRMonitorView` can render a hidden count and a reveal-all
/// button per section without re-deriving the split itself.
struct PRSection {
    var visible: [GitHubPR] = []
    var hidden: [GitHubPR] = []

    var hiddenIDs: Set<Int> { Set(hidden.map(\.id)) }
    var isEmpty: Bool { visible.isEmpty && hidden.isEmpty }
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
    /// The login resolved for `resolvedCredentials`; re-resolved when the token or API base changes,
    /// otherwise a token swapped in Settings kept searching as the previous account.
    private var resolvedUsername: String?
    private var resolvedCredentials: String?
    private var isRefreshing = false
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
                return ArgusConfig.intervalNanoseconds(seconds, default: 300)
            },
            action: { [weak self] in await self?.refresh() }
        )
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        resolvedUsername = nil
        resolvedCredentials = nil
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
        // The poll timer and the manual refresh button can both land here; two overlapping fetches
        // would race on `lastCategorized` and the highlight tracker.
        guard !isRefreshing else { return }
        isRefreshing = true
        isLoading = true
        lastError = nil
        defer {
            isRefreshing = false
            isLoading = false
        }
        let client = GitHubClient(apiBaseURL: config.apiBaseURL, token: config.token)
        do {
            let credentials = config.apiBaseURL + "\n" + config.token
            if resolvedUsername == nil || resolvedCredentials != credentials {
                resolvedUsername = try await client.authenticatedUser()
                resolvedCredentials = credentials
            }
            guard let username = resolvedUsername else { return }
            try await fetchAndCategorize(username: username, client: client)
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Private

    private func fetchAndCategorize(username: String, client: GitHubClient) async throws {
        async let authored = client.searchPullRequests(query: "is:pr is:open author:\(username)")
        async let assigned = client.searchPullRequests(query: "is:pr is:open assignee:\(username)")
        let (authoredPRs, assignedPRs) = try await (authored, assigned)

        var seen = Set<Int>()
        let allPRs = (authoredPRs + assignedPRs).filter { seen.insert($0.id).inserted }
        let enrichments = await enrichDetails(for: allPRs, client: client)

        func enrich(_ prs: [GitHubPR]) -> [GitHubPR] {
            prs.map { pullRequest in
                var copy = pullRequest
                let enrichment = enrichments[pullRequest.id]
                copy.baseBranch = enrichment?.baseBranch
                copy.approvedBy = enrichment?.approvedBy ?? []
                // Drives the dimming of PRs the user has already approved; never set before.
                copy.approvedByMe = copy.approvedBy.contains(username)
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

    private func enrichDetails(for prs: [GitHubPR], client: GitHubClient) async -> [Int: PREnrichment] {
        await withTaskGroup(of: (Int, PREnrichment).self) { group in
            for pullRequest in prs {
                group.addTask { (pullRequest.id, await client.enrichment(for: pullRequest)) }
            }
            var result: [Int: PREnrichment] = [:]
            for await (prID, enrichment) in group {
                result[prID] = enrichment
            }
            return result
        }
    }

    private nonisolated static var hiddenPRsURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("argus/hidden-prs.json")
            ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/argus/hidden-prs.json")
    }
}
