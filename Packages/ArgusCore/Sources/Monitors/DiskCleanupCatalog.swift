import Foundation

/// One thing the disk-cleanup popup can offer to delete.
public struct CleanupItem: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case cache
        case trash
        /// A git checkout under `~/workspace`. Deleting one can lose unpushed work, so the UI asks
        /// for a second, repo-naming confirmation before removing any.
        case gitRepository
    }

    public let displayName: String
    public let path: URL
    public let lastModifiedDate: Date?
    public let kind: Kind

    public init(displayName: String, path: URL, lastModifiedDate: Date?, kind: Kind) {
        self.displayName = displayName
        self.path = path
        self.lastModifiedDate = lastModifiedDate
        self.kind = kind
    }
}

/// A candidate's user-visible state that must survive a background reload of the candidate list.
public struct CleanupItemState: Equatable, Sendable {
    public var sizeBytes: Int64?
    public var isSelected: Bool

    public init(sizeBytes: Int64? = nil, isSelected: Bool = false) {
        self.sizeBytes = sizeBytes
        self.isSelected = isSelected
    }
}

/// What the cleanup popup offers, and the rules for what it may delete. Pure over a `home` URL so
/// discovery and the safety checks are testable against a temp directory.
public enum DiskCleanupCatalog {
    struct Entry {
        let name: String
        let relativePath: String
        let kind: CleanupItem.Kind
    }

    /// Fixed, well-known cache locations. Deliberately excludes places that hold user data or
    /// settings rather than disposable caches (`~/.claude`, `~/.codex`: session history and config).
    static let entries: [Entry] = [
        Entry(name: "Xcode Derived Data", relativePath: "Library/Developer/Xcode/DerivedData", kind: .cache),
        Entry(name: "Xcode Archives", relativePath: "Library/Developer/Xcode/Archives", kind: .cache),
        Entry(name: "iOS Device Support", relativePath: "Library/Developer/Xcode/iOS DeviceSupport", kind: .cache),
        Entry(
            name: "Simulator Runtimes", relativePath: "Library/Developer/CoreSimulator/Profiles/Runtimes",
            kind: .cache),
        Entry(name: "npm Cache", relativePath: ".npm/_cacache", kind: .cache),
        Entry(name: "pnpm Store", relativePath: ".pnpm-store", kind: .cache),
        Entry(name: "Android SDK", relativePath: ".android", kind: .cache),
        Entry(name: "Trash", relativePath: ".Trash", kind: .trash),
    ]

    /// `Library/Developer` children that overlap fixed entries above, or hold user data (Xcode's
    /// UserData: snippets, key bindings) — never offered as a whole.
    private static let excludedDeveloperChildren: Set<String> = ["Xcode", "CoreSimulator"]

    public static func discover(home: URL, fileManager: FileManager = .default) -> [CleanupItem] {
        var items = entries.compactMap { entry -> CleanupItem? in
            let url = home.appendingPathComponent(entry.relativePath)
            guard fileManager.fileExists(atPath: url.path) else { return nil }
            return item(named: entry.name, at: url, kind: entry.kind)
        }
        items += gradleVersionItems(home: home, fileManager: fileManager)
        items += libraryItems(home: home, fileManager: fileManager)
        items += workspaceRepoItems(home: home, fileManager: fileManager)
        return items
    }

    // MARK: - Discovery

    static func gradleVersionItems(home: URL, fileManager: FileManager = .default) -> [CleanupItem] {
        directories(in: home.appendingPathComponent(".gradle/caches"), fileManager: fileManager)
            .filter { $0.lastPathComponent.range(of: #"^\d+(\.\d+)*$"#, options: .regularExpression) != nil }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .map { item(named: "Gradle \($0.lastPathComponent)", at: $0, kind: .cache) }
    }

    /// Only known-disposable parts of `~/Library`: each `Caches/*` folder, `Logs`, and the
    /// `Developer/*` folders not excluded above. The previous version offered every top-level
    /// `~/Library` folder — including Keychains, Mail and Application Support.
    static func libraryItems(home: URL, fileManager: FileManager = .default) -> [CleanupItem] {
        let library = home.appendingPathComponent("Library")
        var items: [CleanupItem] = []
        for child in directories(in: library.appendingPathComponent("Caches"), fileManager: fileManager) {
            items.append(item(named: "Library/Caches/\(child.lastPathComponent)", at: child, kind: .cache))
        }
        let logs = library.appendingPathComponent("Logs")
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: logs.path, isDirectory: &isDirectory), isDirectory.boolValue {
            items.append(item(named: "Library/Logs", at: logs, kind: .cache))
        }
        for child in directories(in: library.appendingPathComponent("Developer"), fileManager: fileManager)
        where !excludedDeveloperChildren.contains(child.lastPathComponent) {
            items.append(item(named: "Library/Developer/\(child.lastPathComponent)", at: child, kind: .cache))
        }
        return items
    }

    /// Git checkouts up to two levels below `~/workspace`.
    static func workspaceRepoItems(home: URL, fileManager: FileManager = .default) -> [CleanupItem] {
        let root = home.appendingPathComponent("workspace")
        var results: [CleanupItem] = []
        // The relative name is built up level by level rather than sliced off each URL's path: a
        // listed child's path can be spelled differently from `root`'s (`/private/var` vs `/var`).
        func scan(_ dir: URL, prefix: String, depth: Int) {
            guard depth > 0 else { return }
            for url in directories(in: dir, fileManager: fileManager) {
                let name = prefix + url.lastPathComponent
                if fileManager.fileExists(atPath: url.appendingPathComponent(".git").path) {
                    results.append(item(named: name, at: url, kind: .gitRepository))
                } else {
                    scan(url, prefix: name + "/", depth: depth - 1)
                }
            }
        }
        scan(root, prefix: "", depth: 2)
        return results.sorted { $0.displayName < $1.displayName }
    }

    /// Non-hidden subdirectories of `dir` (symlinks excluded, so a link can't redirect a delete).
    private static func directories(in dir: URL, fileManager: FileManager) -> [URL] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        let contents =
            (try? fileManager.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        return contents.sorted { $0.lastPathComponent < $1.lastPathComponent }.filter { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            return values?.isDirectory == true && values?.isSymbolicLink != true
        }
    }

    private static func item(named name: String, at url: URL, kind: CleanupItem.Kind) -> CleanupItem {
        let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        return CleanupItem(displayName: name, path: url, lastModifiedDate: modified, kind: kind)
    }

    // MARK: - Reload and deletion rules

    /// State to carry onto a freshly discovered list: whatever `previous` recorded (size, selection)
    /// for each path that is still present. Without this a background reload — the size scan runs
    /// on a timer — silently unticked everything the user had selected, even mid-confirmation.
    public static func carriedState(
        previous: [URL: CleanupItemState], into items: [CleanupItem]
    ) -> [URL: CleanupItemState] {
        Dictionary(
            items.compactMap { item in previous[item.path].map { (item.path, $0) } },
            uniquingKeysWith: { first, _ in first })
    }

    /// The paths a "Remove Selected" may actually delete: selected, currently visible under the
    /// popup's filter (a hidden-but-selected item must never be deleted unseen), and safe.
    public static func removablePaths(selected: [URL], visible: Set<URL>, home: URL) -> [URL] {
        selected.filter { visible.contains($0) && isSafeToDelete($0, home: home) }
    }

    /// Defence in depth for `rm -rf`: a path is deletable only if it sits strictly inside `home`
    /// (after resolving `..`), and is not one of the user's top-level data folders or dotfile
    /// configuration roots, however it ended up on the list.
    public static func isSafeToDelete(_ url: URL, home: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let homePath = home.standardizedFileURL.path
        guard path.hasPrefix(homePath + "/") else { return false }
        let relative = String(path.dropFirst(homePath.count + 1))
        guard !relative.isEmpty else { return false }
        return !protectedTopLevel.contains(relative)
    }

    private static let protectedTopLevel: Set<String> = [
        "Desktop", "Documents", "Downloads", "Library", "Movies", "Music", "Pictures", "Public", "Applications",
        "workspace", ".ssh", ".gnupg", ".config", ".claude", ".codex", ".zshrc", ".zprofile", ".bash_profile",
        ".gitconfig",
    ]
}
