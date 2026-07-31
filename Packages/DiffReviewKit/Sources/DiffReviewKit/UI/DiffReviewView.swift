import SwiftUI

/// The complete side-by-side diff review UI: revision picker, file list, diff pane with inline
/// comments, and per-comment Reply/Apply actions run against a headless Claude Code / Codex
/// session in the given repository.
///
/// This is the package's single intended integration point — embed it in a window, sheet, or any
/// other SwiftUI container.
public struct DiffReviewView: View {
    @State private var model: DiffReviewModel

    /// - Parameters:
    ///   - repositoryPath: absolute path to the git repository or worktree to review.
    ///   - initialBase: starting base ref. Leave empty to auto-resolve (origin's default branch,
    ///     falling back to `main`/`master`).
    ///   - initialHead: starting head ref, defaulting to the checked-out branch (`HEAD`).
    ///   - agent: which CLI to run for Reply/Apply actions.
    public init(
        repositoryPath: String,
        initialBase: String = "",
        initialHead: String = "HEAD",
        agent: DiffReviewAgent
    ) {
        let model = DiffReviewModel(repositoryPath: repositoryPath, agent: agent)
        model.baseRef = initialBase
        model.headRef = initialHead
        _model = State(wrappedValue: model)
    }

    public var body: some View {
        VStack(spacing: 0) {
            DiffSummaryBar(stats: model.sizeStats)
            Divider()
            HStack(spacing: 0) {
                NavigationSplitView {
                    FileTreeView(model: model)
                        .navigationSplitViewColumnWidth(min: 240, ideal: 320)
                } detail: {
                    VStack(spacing: 0) {
                        RevisionPickerView(model: model)
                        Divider()
                        detailContent
                    }
                }
                Divider()
                CommitListView(model: model)
                    .frame(width: 300)
            }
        }
        .task {
            await model.start()
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        if let error = model.loadError {
            errorView(error)
        } else if let file = model.selectedFile {
            SideBySideDiffView(model: model, file: file)
                .id(file.path)
        } else if model.isLoadingDiff {
            ProgressView("Loading diff…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Text("No changes between \(model.baseRef.isEmpty ? "base" : model.baseRef) and \(model.headRef).")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await model.refreshDiff() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
