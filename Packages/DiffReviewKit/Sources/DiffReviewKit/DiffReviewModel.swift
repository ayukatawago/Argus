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

    public var isLoadingDiff = false
    public var loadError: String?

    private let diffService: DiffService
    private let revisionResolver: RevisionResolver
    private var activeAgentTasks: [UUID: Task<Void, Never>] = [:]

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
        return "\(commits[range.upperBound].hash)^"
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

    /// Total/production/test breakdown of the current diff, in that order.
    public var sizeStats: [DiffSizeStat] {
        let testFiles = files.filter { DiffFileClassifier.isTestFile($0.path) }
        let productionFiles = files.filter { !DiffFileClassifier.isTestFile($0.path) }
        return [
            DiffSizeStat(label: "Total", files: files),
            DiffSizeStat(label: "Production", files: productionFiles),
            DiffSizeStat(label: "Test", files: testFiles),
        ]
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
        defer { isLoadingDiff = false }
        do {
            let newFiles = try await diffService.diff(
                base: effectiveBase,
                head: effectiveHead,
                includeUncommitted: includesUncommitted
            )
            files = newFiles
            if selectedFilePath == nil || !newFiles.contains(where: { $0.path == selectedFilePath }) {
                selectedFilePath = newFiles.first?.path
            }
        } catch {
            loadError = String(describing: error)
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

    private var expandedGapLines: [String: [DiffLine]] = [:]
    private var loadingGapIDs: Set<String> = []

    /// The revealed lines for a previously collapsed gap, if `expandGap` has completed for it.
    public func expandedLines(forGapID gapID: String) -> [DiffLine]? {
        expandedGapLines[gapID]
    }

    public func isLoadingGap(_ gapID: String) -> Bool {
        loadingGapIDs.contains(gapID)
    }

    /// Fetches the file content needed to reveal a collapsed gap's lines (from disk for the
    /// working tree, otherwise via `git show`) and populates `expandedGapLines`. A no-op if the
    /// gap is already expanded or a fetch for it is already in flight.
    public func expandGap(_ gap: DiffGap, in file: DiffFile) async {
        guard expandedGapLines[gap.id] == nil, !loadingGapIDs.contains(gap.id) else { return }
        loadingGapIDs.insert(gap.id)
        defer { loadingGapIDs.remove(gap.id) }

        guard let sourceLines = await gapSourceLines(for: file) else { return }
        expandedGapLines[gap.id] = Self.gapLines(gap, in: file, sourceLines: sourceLines)
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
            return Self.splitLines(text)
        }
        return try? await diffService.fileContent(ref: effectiveHead, path: file.path)
    }

    private static func splitLines(_ text: String) -> [String] {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if text.hasSuffix("\n") { lines.removeLast() }
        return lines
    }

    private static func gapLines(_ gap: DiffGap, in file: DiffFile, sourceLines: [String]) -> [DiffLine] {
        let start = (file.kind == .deleted ? gap.oldStart : gap.newStart) - 1
        guard start >= 0, start < sourceLines.count else { return [] }
        let end = gap.lineCount.map { min(start + $0, sourceLines.count) } ?? sourceLines.count
        guard end > start else { return [] }

        return (start..<end).map { sourceIndex in
            let offset = sourceIndex - start
            return DiffLine(
                kind: .context,
                text: sourceLines[sourceIndex],
                oldLineNumber: file.kind == .added ? nil : gap.oldStart + offset,
                newLineNumber: file.kind == .deleted ? nil : gap.newStart + offset
            )
        }
    }

    // MARK: - Agent actions

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

        activeAgentTasks[commentID]?.cancel()
        activeAgentTasks[commentID] = Task { [weak self] in
            guard let self else { return }
            defer { self.activeAgentTasks[commentID] = nil }

            var replyText = ""
            var sessionID: String?

            for await event in runner.run(prompt: prompt, mode: mode, resumingSessionID: priorSessionID) {
                switch event {
                case .text(let text):
                    replyText += text

                case .sessionID(let id):
                    sessionID = id

                case .failed(let message):
                    self.appendReply(commentID: commentID, kind: .error, text: message, sessionID: sessionID)
                    self.setStatus(commentID: commentID, status: .open)
                    return

                case .finished:
                    break
                }
            }

            let finalText = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
            self.appendReply(
                commentID: commentID,
                kind: replyKind,
                text: finalText.isEmpty ? "(no output)" : finalText,
                sessionID: sessionID
            )
            self.setStatus(commentID: commentID, status: .resolved)
            if mode == .apply {
                await self.refreshDiff()
            }
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
