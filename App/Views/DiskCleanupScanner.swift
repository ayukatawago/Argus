import ArgusConfigKit
import ArgusSupport
import Foundation
import Monitors

struct CleanupCandidate: Identifiable {
    var id: URL { path }
    let displayName: String
    let path: URL
    var sizeBytes: Int64?
    var lastModifiedDate: Date?
    var isSelected: Bool
    let kind: CleanupItem.Kind

    var isTrash: Bool { kind == .trash }
    var isGitRepository: Bool { kind == .gitRepository }
}

extension CleanupCandidate: SizedCandidate {}

@MainActor
final class DiskCleanupScanner: ObservableObject {
    @Published private(set) var candidates: [CleanupCandidate] = []
    @Published private(set) var isScanning = false
    @Published private(set) var isRemoving = false
    @Published private(set) var scanningCandidateIDs: Set<URL> = []
    /// Display names of items the last removal could not delete; nil when it fully succeeded.
    @Published var removalFailureMessage: String?

    private var backgroundTask: Task<Void, Never>?
    private let home = FileManager.default.homeDirectoryForCurrentUser

    func start() {
        guard backgroundTask == nil else { return }
        backgroundTask = PollingTask.repeating(
            order: .actThenSleep,
            interval: {
                let seconds = await ArgusConfigStore.shared.config.diskMonitor.sizeCheckIntervalSeconds
                return ArgusConfig.intervalNanoseconds(seconds, default: 1800)
            },
            action: { [weak self] in
                await self?.loadCandidates()
                await self?.scanSizes()
            }
        )
    }

    func stop() {
        backgroundTask?.cancel()
        backgroundTask = nil
    }

    /// Re-discovers candidates, carrying size and selection over for any path still present — the
    /// background poll calls this too, and must not untick what the user has selected.
    func loadCandidates() {
        let previous = Dictionary(
            candidates.map { ($0.path, CleanupItemState(sizeBytes: $0.sizeBytes, isSelected: $0.isSelected)) },
            uniquingKeysWith: { first, _ in first })
        let items = DiskCleanupCatalog.discover(home: home)
        let carried = DiskCleanupCatalog.carriedState(previous: previous, into: items)
        candidates = items.map { item in
            let state = carried[item.path]
            return CleanupCandidate(
                displayName: item.displayName,
                path: item.path,
                sizeBytes: state?.sizeBytes,
                lastModifiedDate: item.lastModifiedDate,
                isSelected: state?.isSelected ?? false,
                kind: item.kind
            )
        }
    }

    func scanSizes() async {
        guard !isScanning else { return }
        isScanning = true
        defer {
            isScanning = false
            scanningCandidateIDs = []
        }
        let items = candidates.map { ($0.id, $0.path) }
        await withTaskGroup(of: (URL, Int64?).self) { group in
            var iterator = items.makeIterator()
            for _ in 0..<4 {
                guard let (id, url) = iterator.next() else { break }
                scanningCandidateIDs.insert(id)
                group.addTask { (id, await Self.measureDiskUsage(at: url)) }
            }
            for await (id, bytes) in group {
                guard !Task.isCancelled else { break }
                scanningCandidateIDs.remove(id)
                if let bytes, let idx = candidates.firstIndex(where: { $0.id == id }) {
                    candidates[idx].sizeBytes = bytes
                }
                if let (nextID, nextURL) = iterator.next() {
                    scanningCandidateIDs.insert(nextID)
                    group.addTask { (nextID, await Self.measureDiskUsage(at: nextURL)) }
                }
            }
        }
    }

    func toggleSelection(id: URL) {
        guard let idx = candidates.firstIndex(where: { $0.id == id }) else { return }
        candidates[idx].isSelected.toggle()
    }

    /// Candidates that "Remove Selected" would delete right now: selected *and* among `visibleIDs`
    /// (the list as currently filtered) *and* passing the deletion safety check. The confirmation
    /// dialog lists exactly these, so what's confirmed is what's deleted.
    func pendingRemovals(visibleIDs: Set<URL>) -> [CleanupCandidate] {
        let allowed = Set(
            DiskCleanupCatalog.removablePaths(
                selected: candidates.filter(\.isSelected).map(\.path), visible: visibleIDs, home: home))
        return candidates.filter { allowed.contains($0.path) }
    }

    func removeSelected(visibleIDs: Set<URL>) async {
        guard !isRemoving else { return }
        isRemoving = true
        defer { isRemoving = false }
        var failed: [String] = []
        let toRemove = pendingRemovals(visibleIDs: visibleIDs)
        for candidate in toRemove {
            let succeeded =
                candidate.isTrash
                ? await Self.emptyTrashContents(at: candidate.path)
                : await Self.deletePermanently(candidate.path)
            if !succeeded { failed.append(candidate.displayName) }
        }
        removalFailureMessage = failed.isEmpty ? nil : failed.joined(separator: ", ")
        // Removed items' old sizes are stale; drop them (and their selection) so the rescan below
        // re-measures whatever survived (e.g. a partly emptied Trash) instead of showing old numbers.
        let removedPaths = Set(toRemove.map(\.path))
        for idx in candidates.indices where removedPaths.contains(candidates[idx].path) {
            candidates[idx].sizeBytes = nil
            candidates[idx].isSelected = false
        }
        loadCandidates()
        await scanSizes()
    }

    /// Returns `nil` (leaving the candidate's previously-known size untouched) when `du` fails,
    /// rather than surfacing a spurious `0`. `-H` makes `du` follow the candidate path itself if
    /// it's a symlink (e.g. a cache relocated to another volume) — without it, `du` reports only
    /// the symlink's own on-disk size, which is 0.
    private static nonisolated func measureDiskUsage(at url: URL) async -> Int64? {
        let result = await ProcessRunner.run("/usr/bin/du", ["-skH", url.path])
        guard result.succeeded else { return nil }
        return DiskUsageParser.bytes(fromDuOutput: result.standardOutput)
    }

    /// Shells out to `rm -rf` rather than calling `FileManager.removeItem` directly so the
    /// recursive delete (which can touch hundreds of thousands of files for things like
    /// DerivedData or a stale git worktree) runs on a separate process instead of blocking this
    /// `@MainActor`-isolated type's thread for the duration of the delete.
    private static nonisolated func deletePermanently(_ url: URL) async -> Bool {
        await ProcessRunner.run("/bin/rm", ["-rf", url.path]).succeeded
    }

    private static nonisolated func emptyTrashContents(at url: URL) async -> Bool {
        let fileManager = FileManager.default
        let contents = (try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
        var allSucceeded = true
        for item in contents where !(await deletePermanently(item)) {
            allSucceeded = false
        }
        return allSucceeded
    }
}
