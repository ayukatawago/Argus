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
    public var includeUncommitted = false
    public var availableRefs: [String] = []

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

    /// Resolves branch list + default base (if not already set) and loads the initial diff.
    public func start() async {
        async let branches = revisionResolver.listBranches()
        async let base = revisionResolver.defaultBase()
        let (branchList, defaultBase) = await (branches, base)
        availableRefs = branchList
        if baseRef.isEmpty { baseRef = defaultBase }
        await refreshDiff()
    }

    public func refreshDiff() async {
        isLoadingDiff = true
        loadError = nil
        defer { isLoadingDiff = false }
        do {
            let newFiles = try await diffService.diff(
                base: baseRef,
                head: headRef,
                includeUncommitted: includeUncommitted
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

    public func addComment(filePath: String, side: ReviewComment.Side, lineNumber: Int, body: String) {
        comments.append(ReviewComment(filePath: filePath, side: side, lineNumber: lineNumber, body: body))
    }

    public func comments(for filePath: String) -> [ReviewComment] {
        comments.filter { $0.filePath == filePath }
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
