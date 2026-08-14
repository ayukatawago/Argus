import AppKit
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
    let isTrash: Bool
}

extension CleanupCandidate: SizedCandidate {}

@MainActor
final class DiskCleanupScanner: ObservableObject {
    @Published private(set) var candidates: [CleanupCandidate] = []
    @Published private(set) var isScanning = false
    @Published private(set) var isRemoving = false
    @Published private(set) var scanningCandidateIDs: Set<URL> = []

    private var backgroundTask: Task<Void, Never>?

    func start() {
        guard backgroundTask == nil else { return }
        backgroundTask = PollingTask.repeating(
            order: .actThenSleep,
            interval: {
                let seconds = await ArgusConfigStore.shared.config.diskMonitor.sizeCheckIntervalSeconds
                return UInt64(seconds * 1_000_000_000)
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

    private struct CatalogEntry {
        let name: String
        let relativePath: String
        let isTrash: Bool
    }

    private static let catalogEntries: [CatalogEntry] = [
        CatalogEntry(name: "Xcode Derived Data", relativePath: "Library/Developer/Xcode/DerivedData", isTrash: false),
        CatalogEntry(name: "Xcode Archives", relativePath: "Library/Developer/Xcode/Archives", isTrash: false),
        CatalogEntry(
            name: "iOS Device Support",
            relativePath: "Library/Developer/Xcode/iOS DeviceSupport", isTrash: false),
        CatalogEntry(
            name: "Simulator Runtimes",
            relativePath: "Library/Developer/CoreSimulator/Profiles/Runtimes", isTrash: false),
        CatalogEntry(name: "npm Cache", relativePath: ".npm/_cacache", isTrash: false),
        CatalogEntry(name: "pnpm Store", relativePath: ".pnpm-store", isTrash: false),
        CatalogEntry(name: "Android SDK", relativePath: ".android", isTrash: false),
        CatalogEntry(name: "Claude Cache", relativePath: ".claude", isTrash: false),
        CatalogEntry(name: "Codex Cache", relativePath: ".codex", isTrash: false),
        CatalogEntry(name: "Webview Workspace", relativePath: "workspace/webview", isTrash: false),
        CatalogEntry(name: "Trash", relativePath: ".Trash", isTrash: true),
    ]

    func loadCandidates() {
        let existingSizes = Dictionary(
            candidates.compactMap { candidate -> (URL, Int64)? in
                guard let size = candidate.sizeBytes else { return nil }
                return (candidate.path, size)
            },
            uniquingKeysWith: { first, _ in first }
        )
        let home = FileManager.default.homeDirectoryForCurrentUser
        var result = Self.catalogEntries.compactMap { entry -> CleanupCandidate? in
            let url = home.appendingPathComponent(entry.relativePath)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let modDate = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            return CleanupCandidate(
                displayName: entry.name,
                path: url,
                sizeBytes: nil,
                lastModifiedDate: modDate,
                isSelected: false,
                isTrash: entry.isTrash
            )
        }
        result += Self.gradleVersionCandidates(home: home)
        result += Self.libraryCandidates(home: home)
        result += Self.workspaceRepoCandidates(home: home)
        candidates = result
        for idx in candidates.indices {
            candidates[idx].sizeBytes = existingSizes[candidates[idx].path]
        }
    }

    private static func gradleVersionCandidates(home: URL) -> [CleanupCandidate] {
        let cachesURL = home.appendingPathComponent(".gradle/caches")
        guard
            let contents = try? FileManager.default.contentsOfDirectory(
                at: cachesURL,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
        else { return [] }
        return
            contents
            .filter { url in
                let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                let name = url.lastPathComponent
                let isVersion = name.range(of: #"^\d+(\.\d+)*$"#, options: .regularExpression) != nil
                return isDir && isVersion
            }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .map { url in
                let modDate = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                return CleanupCandidate(
                    displayName: "Gradle \(url.lastPathComponent)",
                    path: url,
                    sizeBytes: nil,
                    lastModifiedDate: modDate,
                    isSelected: false,
                    isTrash: false
                )
            }
    }

    private static func libraryCandidates(home: URL) -> [CleanupCandidate] {
        let libraryURL = home.appendingPathComponent("Library")
        guard
            let topLevel = try? FileManager.default.contentsOfDirectory(
                at: libraryURL,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
        else { return [] }
        var results: [CleanupCandidate] = []
        for url in topLevel.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            if url.lastPathComponent == "Caches",
                let cachesContents = try? FileManager.default.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                    options: [.skipsHiddenFiles]
                )
            {
                for child in cachesContents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    guard (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
                    let modDate =
                        try? child.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                    results.append(
                        CleanupCandidate(
                            displayName: "Library/Caches/\(child.lastPathComponent)",
                            path: child,
                            sizeBytes: nil,
                            lastModifiedDate: modDate,
                            isSelected: false,
                            isTrash: false
                        ))
                }
            } else {
                let modDate =
                    try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                results.append(
                    CleanupCandidate(
                        displayName: "Library/\(url.lastPathComponent)",
                        path: url,
                        sizeBytes: nil,
                        lastModifiedDate: modDate,
                        isSelected: false,
                        isTrash: false
                    ))
            }
        }
        return results
    }

    private static func workspaceRepoCandidates(home: URL) -> [CleanupCandidate] {
        let workspaceURL = home.appendingPathComponent("workspace")
        guard FileManager.default.fileExists(atPath: workspaceURL.path) else { return [] }
        var results: [CleanupCandidate] = []

        func scan(in dir: URL, depth: Int) {
            guard depth > 0 else { return }
            guard
                let contents = try? FileManager.default.contentsOfDirectory(
                    at: dir,
                    includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                    options: [.skipsHiddenFiles]
                )
            else { return }
            for url in contents {
                let vals = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
                guard vals?.isDirectory == true else { continue }
                if FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path) {
                    let relName = String(url.path.dropFirst(workspaceURL.path.count + 1))
                    results.append(
                        CleanupCandidate(
                            displayName: relName,
                            path: url,
                            sizeBytes: nil,
                            lastModifiedDate: vals?.contentModificationDate,
                            isSelected: false,
                            isTrash: false
                        ))
                } else {
                    scan(in: url, depth: depth - 1)
                }
            }
        }

        scan(in: workspaceURL, depth: 2)
        return results.sorted { $0.displayName < $1.displayName }
    }

    func scanSizes() async {
        guard !isScanning else { return }
        isScanning = true
        defer {
            isScanning = false
            scanningCandidateIDs = []
        }
        let items = candidates.map { ($0.id, $0.path) }
        await withTaskGroup(of: (URL, Int64).self) { group in
            var iterator = items.makeIterator()
            for _ in 0..<4 {
                guard let (id, url) = iterator.next() else { break }
                scanningCandidateIDs.insert(id)
                group.addTask { (id, await Self.measureDiskUsage(at: url)) }
            }
            for await (id, bytes) in group {
                guard !Task.isCancelled else { break }
                scanningCandidateIDs.remove(id)
                if let idx = candidates.firstIndex(where: { $0.id == id }) {
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

    func removeSelected() async {
        guard !isRemoving else { return }
        isRemoving = true
        defer { isRemoving = false }
        let toRemove = candidates.filter(\.isSelected)
        for candidate in toRemove {
            if candidate.isTrash {
                await emptyTrashContents(at: candidate.path)
            } else {
                await recycleToTrash(candidate.path)
            }
        }
        let sizeLookup = Dictionary(
            candidates.compactMap { ($0.path, $0.sizeBytes) },
            uniquingKeysWith: { first, _ in first }
        )
        loadCandidates()
        for idx in candidates.indices {
            candidates[idx].sizeBytes = sizeLookup[candidates[idx].path] ?? nil
        }
    }

    private static nonisolated func measureDiskUsage(at url: URL) async -> Int64 {
        let result = await ProcessRunner.run("/usr/bin/du", ["-sk", url.path])
        let parts = result.standardOutput.components(separatedBy: "\t")
        let kilobytes = Int64(parts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "0") ?? 0
        return kilobytes * 1_024
    }

    private func recycleToTrash(_ url: URL) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            NSWorkspace.shared.recycle([url]) { _, _ in
                continuation.resume()
            }
        }
    }

    private func emptyTrashContents(at url: URL) async {
        let fileManager = FileManager.default
        let contents = (try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
        for item in contents {
            try? fileManager.removeItem(at: item)
        }
    }
}
