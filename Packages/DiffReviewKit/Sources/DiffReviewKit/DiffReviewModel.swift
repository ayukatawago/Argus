import Foundation
import Observation

/// Owns git state (revisions, parsed diff), review comments, and in-flight agent runs for a
/// single `DiffReviewView`. Public so a host app can drive the review programmatically if it
/// doesn't want to embed the full view (e.g. to prefetch a diff).
@MainActor
@Observable
public final class DiffReviewModel {
    public let repositoryPath: String
    public var agent: DiffReviewAgent

    public var baseRef: String = ""
    public var headRef: String = "HEAD"
    public var availableRefs: [String] = []

    /// Commits in `baseRef..headRef`, newest first (see `RevisionResolver.listCommits`).
    public var commits: [Commit] = []
    /// Indices into `commits` (0 = newest) currently selected in the commit sidebar, with `-1`
    /// standing for the synthetic "Uncommitted changes" row pinned above the newest commit.
    /// `nil` means "every real commit, no uncommitted changes" — the default full range. A range
    /// whose `lowerBound` is `-1` includes uncommitted changes, optionally combined with a
    /// contiguous run of the newest commits (`0...upperBound`).
    public var selectedCommitRange: ClosedRange<Int>?

    public var files: [DiffFile] = []
    public var selectedFilePath: String?
    public var comments: [ReviewComment] = []

    /// Viewed and collapsed state for the file list. In memory only, like comments.
    private var fileViewState = FileViewState()

    public var isLoadingDiff = false
    public var loadError: String?

    private let diffService: DiffService
    private let revisionResolver: RevisionResolver
    private var activeAgentTasks: [UUID: Task<Void, Never>] = [:]
    /// Identifies the latest run per comment, so a superseded (cancelled) run can't append its
    /// reply or clear the newer run's bookkeeping.
    private var activeRunTokens: [UUID: UUID] = [:]
    /// Bumped on every diff refresh; an in-flight gap expansion from an older diff is discarded.
    private var diffGeneration = 0
    /// Per-file cache of the file's full content (as `DiffService.fileContent` / disk returns it).
    /// Cleared on every refresh: a bottom gap's length and the revealed lines both come from it, and
    /// the working tree may have changed since it was read.
    private var fileSourceLines: [String: [String]] = [:]

    /// Bumped whenever some file's rows change (diff refresh, gap expansion). Views read it through
    /// `layout(for:)`, so they re-run; the cache itself is invalidated per file.
    private(set) var layoutRevision = 0
    @ObservationIgnored private var layoutCache: [String: DiffFileLayout] = [:]

    public init(repositoryPath: String, agent: DiffReviewAgent) {
        self.repositoryPath = repositoryPath
        self.agent = agent
        let git = GitRunner(repositoryPath: repositoryPath)
        diffService = DiffService(git: git)
        revisionResolver = RevisionResolver(git: git)
    }

    public var selectedFile: DiffFile? {
        files.first { $0.path == selectedFilePath }
    }

    /// Whether the current selection includes the synthetic "Uncommitted changes" row.
    public var includesUncommitted: Bool {
        currentRange?.lowerBound == -1
    }

    /// The base/head actually diffed: narrowed to the selected commit sub-range (and/or
    /// uncommitted changes) when one is set, otherwise the full `baseRef..headRef` range. Falls
    /// back to `baseRef`/`headRef` verbatim when there's no commit list to narrow against.
    var effectiveBase: String {
        guard let range = currentRange else { return baseRef }
        guard range.upperBound >= 0 else { return headRef }
        let oldest = commits[range.upperBound]
        // A root commit has no parent, so `hash^` doesn't exist: diff against the empty tree.
        return oldest.isRoot ? DiffService.emptyTreeHash : "\(oldest.hash)^"
    }

    var effectiveHead: String {
        guard let range = currentRange, range.lowerBound >= 0 else { return headRef }
        return commits[range.lowerBound].hash
    }

    private var fullCommitRange: ClosedRange<Int>? {
        commits.isEmpty ? nil : 0...(commits.count - 1)
    }

    /// The selection actually in effect: the explicit `selectedCommitRange` when set, otherwise
    /// every real commit (never uncommitted changes) by default.
    private var currentRange: ClosedRange<Int>? {
        selectedCommitRange ?? fullCommitRange
    }

    // MARK: - Loading

    /// Resolves branch list + default base (if not already set) and loads the initial commit
    /// list + diff.
    public func start() async {
        async let branches = revisionResolver.listBranches()
        async let base = revisionResolver.defaultBase()
        let (branchList, defaultBase) = await (branches, base)
        availableRefs = branchList
        if baseRef.isEmpty { baseRef = defaultBase }
        await reload()
    }

    /// Re-resolves the commit list for the current `baseRef..headRef` (resetting the commit
    /// sub-selection to "all") and reloads the diff. Call this when the header base/head refs
    /// change; call `refreshDiff()` directly for changes that don't affect the commit range
    /// (e.g. the "include uncommitted" toggle, or a manual refresh).
    public func reload() async {
        await loadCommits()
        await refreshDiff()
    }

    private func loadCommits() async {
        commits = await revisionResolver.listCommits(base: baseRef, head: headRef)
        selectedCommitRange = nil
    }

    public func refreshDiff() async {
        isLoadingDiff = true
        loadError = nil
        diffGeneration += 1
        defer { isLoadingDiff = false }
        do {
            let newFiles = try await diffService.diff(
                base: effectiveBase,
                head: effectiveHead,
                includeUncommitted: includesUncommitted
            )
            files = newFiles
            // Line numbers (and gap ids) refer to the previous diff; revealed context is stale. Cleared
            // only once the new diff is in, so a failed refresh keeps what the reviewer had open.
            gapExpansions = [:]
            fileSourceLines = [:]
            layoutCache = [:]
            layoutRevision += 1
            fileViewState.reconcile(with: newFiles)
            if selectedFilePath == nil || !newFiles.contains(where: { $0.path == selectedFilePath }) {
                selectedFilePath = newFiles.first?.path
            }
        } catch {
            loadError = error.localizedDescription
        }
    }

    // MARK: - Viewed and collapsed files

    public var viewedFiles: [String: Int] { fileViewState.viewedFiles }
    public var collapsedFilePaths: Set<String> { fileViewState.collapsedFilePaths }

    /// Marks `path` Viewed (which also collapses it), or un-marks it (which expands it).
    public func toggleViewed(_ path: String) {
        guard let file = files.first(where: { $0.path == path }) else { return }
        fileViewState.toggleViewed(file)
    }

    /// Expands `path` if it is collapsed (search uses this to reveal a match). Leaves it alone otherwise.
    func expandFile(_ path: String) {
        fileViewState.collapsedFilePaths.remove(path)
    }

    public func toggleCollapsed(_ path: String) {
        if fileViewState.collapsedFilePaths.contains(path) {
            fileViewState.collapsedFilePaths.remove(path)
        } else {
            fileViewState.collapsedFilePaths.insert(path)
        }
    }

    // MARK: - Comments

    public func addComment(
        filePath: String,
        side: ReviewComment.Side,
        startLineNumber: Int? = nil,
        lineNumber: Int,
        body: String
    ) {
        comments.append(
            ReviewComment(
                filePath: filePath,
                side: side,
                startLineNumber: startLineNumber,
                lineNumber: lineNumber,
                body: body
            )
        )
    }

    public func comments(for filePath: String) -> [ReviewComment] {
        comments.filter { $0.filePath == filePath }
    }

    // MARK: - Hidden-context expansion

    /// Gap ids ("top", "bottom", "mid-…") repeat across files, so every key carries the file path.
    private struct GapKey: Hashable {
        let filePath: String
        let gapID: String
    }

    private var gapExpansions: [GapKey: GapExpansion] = [:]
    private var loadingGapKeys: Set<GapKey> = []

    /// How much of a gap has been revealed so far (nothing, if it hasn't been touched yet).
    public func gapExpansion(forGapID gapID: String, filePath: String) -> GapExpansion {
        gapExpansions[GapKey(filePath: filePath, gapID: gapID)] ?? GapExpansion()
    }

    public func isLoadingGap(_ gapID: String, filePath: String) -> Bool {
        loadingGapKeys.contains(GapKey(filePath: filePath, gapID: gapID))
    }

    /// The gap's length: from the diff for top and middle gaps, and from the cached file for a bottom
    /// gap. `nil` for a bottom gap whose file hasn't been fetched yet.
    public func resolvedLineCount(for gap: DiffGap, in file: DiffFile) -> Int? {
        if let lineCount = gap.lineCount { return lineCount }
        guard let sourceLines = fileSourceLines[file.path] else { return nil }
        return max(0, sourceLines.count - GapRevealedLines.sourceStart(of: gap, in: file))
    }

    /// The flat rows, intraline spans and line texts of `file`, memoized until the next layout revision.
    func layout(for file: DiffFile) -> DiffFileLayout {
        // Reading the revision is what subscribes the caller to changes: a cache hit reads no other
        // observed state, so without this a gap expansion would not re-render the rows.
        _ = layoutRevision
        if let cached = layoutCache[file.path] { return cached }
        let built = DiffFileLayout.make(file: file, gaps: revealedGaps(for: file))
        layoutCache[file.path] = built
        return built
    }

    /// The context lines revealed so far at each end of `gap`, in file order.
    public func revealedLines(_ gap: DiffGap, in file: DiffFile) -> (top: [DiffLine], bottom: [DiffLine]) {
        guard let sourceLines = fileSourceLines[file.path] else { return ([], []) }
        return GapRevealedLines.make(
            gap: gap,
            file: file,
            expansion: gapExpansion(forGapID: gap.id, filePath: file.path),
            lineCount: resolvedLineCount(for: gap, in: file),
            sourceLines: sourceLines
        )
    }

    /// Every gap in `file` with what it currently shows, keyed by gap id, for `DiffRowItemBuilder`.
    func revealedGaps(for file: DiffFile) -> [String: RevealedGap] {
        var result: [String: RevealedGap] = [:]
        for case .gap(let gap) in DiffBlockBuilder.blocks(for: file) {
            let revealed = revealedLines(gap, in: file)
            result[gap.id] = RevealedGap(
                expansion: gapExpansion(forGapID: gap.id, filePath: file.path),
                lineCount: resolvedLineCount(for: gap, in: file),
                top: revealed.top,
                bottom: revealed.bottom
            )
        }
        return result
    }

    /// Reveals more of a collapsed gap in `direction` (`.all` reveals the whole gap). Fetches and
    /// caches the file's content first if needed, so every gap in one file shares a single fetch.
    /// A no-op if the gap is already fully shown or a fetch for it is already in flight.
    public func expandGap(_ gap: DiffGap, in file: DiffFile, direction: GapExpansion.Direction) async {
        let key = GapKey(filePath: file.path, gapID: gap.id)
        guard !loadingGapKeys.contains(key) else { return }
        guard
            !gapExpansion(forGapID: gap.id, filePath: file.path)
                .isFullyExpanded(lineCount: resolvedLineCount(for: gap, in: file))
        else { return }
        loadingGapKeys.insert(key)
        defer { loadingGapKeys.remove(key) }

        let generation = diffGeneration
        if fileSourceLines[file.path] == nil {
            guard let sourceLines = await gapSourceLines(for: file), generation == diffGeneration else { return }
            fileSourceLines[file.path] = sourceLines
            invalidateLayout(for: file.path)
        }
        guard let lineCount = resolvedLineCount(for: gap, in: file) else { return }
        let current = gapExpansion(forGapID: gap.id, filePath: file.path)
        let updated = current.expanding(direction, lineCount: lineCount)
        guard updated != current else { return }
        gapExpansions[key] = updated
        invalidateLayout(for: file.path)
    }

    /// Drops the cached layout of one file, and tells observers that some layout changed.
    private func invalidateLayout(for path: String) {
        layoutCache[path] = nil
        layoutRevision += 1
    }

    /// The unchanged lines a gap spans are identical on both sides of the diff, so either
    /// revision's content works; the deleted-file case is the only one where only the base
    /// revision still has the file at all.
    private func gapSourceLines(for file: DiffFile) async -> [String]? {
        if file.kind == .deleted {
            return try? await diffService.fileContent(ref: effectiveBase, path: file.path)
        }
        if includesUncommitted {
            let fullPath = (repositoryPath as NSString).appendingPathComponent(file.path)
            guard let data = FileManager.default.contents(atPath: fullPath),
                let text = String(data: data, encoding: .utf8)
            else { return nil }
            return GapRevealedLines.splitLines(text)
        }
        return try? await diffService.fileContent(ref: effectiveHead, path: file.path)
    }

    // MARK: - Agent actions

    private static func replyBody(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "(no output)" : trimmed
    }

    /// Runs the agent for a comment: `.reply` streams a read-only answer, `.apply` lets it edit
    /// files in the worktree and then refreshes the diff. Spawns an independent headless session
    /// (see `AgentRunner`) — this never touches a live, interactively-attached agent session.
    public func send(commentID: UUID, mode: AgentRunMode) {
        guard let index = comments.firstIndex(where: { $0.id == commentID }),
            let file = files.first(where: { $0.path == comments[index].filePath })
        else { return }

        comments[index].status = mode == .apply ? .applying : .replying
        let comment = comments[index]
        let prompt = PromptComposer.compose(comment: comment, file: file, mode: mode)
        let runner = AgentRunner(agent: agent, workingDirectory: repositoryPath)
        let priorSessionID = comment.replies.last?.sessionID
        let replyKind: ReviewReply.Kind = mode == .apply ? .apply : .reply

        let token = UUID()
        activeAgentTasks[commentID]?.cancel()
        activeRunTokens[commentID] = token
        activeAgentTasks[commentID] = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.activeRunTokens[commentID] == token {
                    self.activeAgentTasks[commentID] = nil
                    self.activeRunTokens[commentID] = nil
                }
            }

            var replyText = ""
            var sessionID: String?

            for await event in runner.run(prompt: prompt, mode: mode, resumingSessionID: priorSessionID) {
                switch event {
                case .text(let text):
                    replyText += text

                case .sessionID(let id):
                    sessionID = id

                case .failed(let message):
                    guard self.activeRunTokens[commentID] == token else { return }
                    self.appendReply(commentID: commentID, kind: .error, text: message, sessionID: sessionID)
                    self.setStatus(commentID: commentID, status: .open)
                    return

                case .finished:
                    break
                }
            }

            guard self.activeRunTokens[commentID] == token, !Task.isCancelled else { return }
            await self.completeRun(
                commentID: commentID, kind: replyKind, text: replyText, sessionID: sessionID, refreshes: mode == .apply
            )
        }
    }

    private func completeRun(
        commentID: UUID, kind: ReviewReply.Kind, text: String, sessionID: String?, refreshes: Bool
    )
        async
    {
        appendReply(commentID: commentID, kind: kind, text: Self.replyBody(from: text), sessionID: sessionID)
        setStatus(commentID: commentID, status: .resolved)
        if refreshes {
            await refreshDiff()
        }
    }

    private func appendReply(commentID: UUID, kind: ReviewReply.Kind, text: String, sessionID: String?) {
        guard let index = comments.firstIndex(where: { $0.id == commentID }) else { return }
        comments[index].replies.append(ReviewReply(kind: kind, text: text, sessionID: sessionID))
    }

    private func setStatus(commentID: UUID, status: ReviewComment.Status) {
        guard let index = comments.firstIndex(where: { $0.id == commentID }) else { return }
        comments[index].status = status
    }
}
