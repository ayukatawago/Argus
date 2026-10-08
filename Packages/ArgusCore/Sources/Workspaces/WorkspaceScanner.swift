import CoreServices
import Foundation

final class WorkspaceScanner: @unchecked Sendable {
    var onChange: (() -> Void)?
    private var streamRef: FSEventStreamRef?
    private var watchedRoots: Set<String> = []

    func start(paths: [String]) {
        stop()
        guard !paths.isEmpty else { return }
        watchedRoots = Set(paths)
        var ctx = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let stream = FSEventStreamCreate(
            nil,
            { _, info, _, eventPaths, _, _ in
                guard let info else { return }
                let scanner = Unmanaged<WorkspaceScanner>.fromOpaque(info).takeUnretainedValue()
                let cfArray = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue()
                let changedPaths = (cfArray as? [String]) ?? []
                guard WorkspaceScanner.isRelevant(changedPaths, watchedRoots: scanner.watchedRoots) else { return }
                DispatchQueue.main.async { scanner.onChange?() }
            },
            &ctx,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            2.0,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes)
        )
        guard let stream else { return }
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
        streamRef = stream
    }

    /// Only rescan for changes that could plausibly add, remove, or rename a repo or worktree:
    /// writes inside a `.git` directory (branch switches, `worktree add`/`remove`, commits) or a
    /// change reported directly on one of the watched roots themselves (a new repo cloned in, or
    /// an existing top-level repo folder deleted). Without this filter, any write anywhere under a
    /// root — an agent editing source files, a build — triggered a full rescan of every repo on
    /// every settle of the 2s coalescing window, for as long as anything was writing.
    ///
    /// `.git` is matched as a whole path component: a bare `contains("/.git")` also matched
    /// `.github/`, `.gitignore`, `.gitattributes` and `.gitlab-ci.yml` — ordinary source files whose
    /// edits triggered exactly the full rescans this filter exists to avoid.
    static func isRelevant(_ changedPaths: [String], watchedRoots: Set<String>) -> Bool {
        changedPaths.contains { path in
            watchedRoots.contains(path) || path.split(separator: "/").contains(".git")
        }
    }

    func stop() {
        guard let stream = streamRef else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        streamRef = nil
    }

    deinit { stop() }
}
