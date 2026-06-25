import AppKit
import Foundation

struct CleanupCandidate: Identifiable {
    let id: UUID
    let displayName: String
    let path: URL
    var sizeBytes: Int64?
    var isSelected: Bool
    let isTrash: Bool
}

@MainActor
final class DiskCleanupScanner: ObservableObject {
    @Published private(set) var candidates: [CleanupCandidate] = []
    @Published private(set) var isScanning = false
    @Published private(set) var isRemoving = false
    @Published private(set) var scanningCandidateID: UUID?

    private var backgroundTask: Task<Void, Never>?

    func start() {
        guard backgroundTask == nil else { return }
        backgroundTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.loadCandidates()
                await self?.scanSizes()
                let interval = ArgusConfigStore.shared.config.diskMonitor.sizeCheckIntervalSeconds
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
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
        CatalogEntry(name: "Homebrew Cache", relativePath: "Library/Caches/Homebrew", isTrash: false),
        CatalogEntry(name: "npm Cache", relativePath: ".npm/_cacache", isTrash: false),
        CatalogEntry(name: "CocoaPods Cache", relativePath: "Library/Caches/CocoaPods", isTrash: false),
        CatalogEntry(name: "Yarn Cache", relativePath: "Library/Caches/Yarn", isTrash: false),
        CatalogEntry(name: "pnpm Store", relativePath: ".pnpm-store", isTrash: false),
        CatalogEntry(name: "IntelliJ Caches", relativePath: "Library/Caches/JetBrains/analyzer", isTrash: false),
        CatalogEntry(name: "Trash", relativePath: ".Trash", isTrash: true),
    ]

    func loadCandidates() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var result = Self.catalogEntries.compactMap { entry -> CleanupCandidate? in
            let url = home.appendingPathComponent(entry.relativePath)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return CleanupCandidate(
                id: UUID(),
                displayName: entry.name,
                path: url,
                sizeBytes: nil,
                isSelected: false,
                isTrash: entry.isTrash
            )
        }
        result += Self.gradleVersionCandidates(home: home)
        candidates = result
    }

    private static func gradleVersionCandidates(home: URL) -> [CleanupCandidate] {
        let cachesURL = home.appendingPathComponent(".gradle/caches")
        guard
            let contents = try? FileManager.default.contentsOfDirectory(
                at: cachesURL,
                includingPropertiesForKeys: [.isDirectoryKey],
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
                CleanupCandidate(
                    id: UUID(),
                    displayName: "Gradle \(url.lastPathComponent)",
                    path: url,
                    sizeBytes: nil,
                    isSelected: false,
                    isTrash: false
                )
            }
    }

    func scanSizes() async {
        guard !isScanning else { return }
        isScanning = true
        defer {
            isScanning = false
            scanningCandidateID = nil
        }
        let ids = candidates.map(\.id)
        for candidateID in ids {
            guard !Task.isCancelled else { break }
            guard let idx = candidates.firstIndex(where: { $0.id == candidateID }) else { continue }
            scanningCandidateID = candidateID
            let url = candidates[idx].path
            let bytes = await measureDiskUsage(at: url)
            if let idx = candidates.firstIndex(where: { $0.id == candidateID }) {
                candidates[idx].sizeBytes = bytes
            }
        }
    }

    func toggleSelection(id: UUID) {
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

    private func measureDiskUsage(at url: URL) async -> Int64 {
        await withCheckedContinuation { continuation in
            let task = Process()
            let pipe = Pipe()
            task.launchPath = "/usr/bin/du"
            task.arguments = ["-sk", url.path]
            task.standardOutput = pipe
            task.standardError = Pipe()
            task.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                let parts = output.components(separatedBy: "\t")
                let kilobytes = Int64(parts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "0") ?? 0
                continuation.resume(returning: kilobytes * 1_024)
            }
            do {
                try task.run()
            } catch {
                continuation.resume(returning: 0)
            }
        }
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
