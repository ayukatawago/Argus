import Foundation
import Testing

@testable import Monitors

@Suite("DiskCleanupCatalog")
struct DiskCleanupCatalogTests {
    private func makeHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("cleanup-home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }

    private func mkdir(_ home: URL, _ relative: String) throws {
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(relative), withIntermediateDirectories: true)
    }

    private func names(_ items: [CleanupItem]) -> [String] { items.map(\.displayName) }

    @Test("fixed cache locations appear only when they exist")
    func fixedEntries() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try mkdir(home, "Library/Developer/Xcode/DerivedData")
        try mkdir(home, ".npm/_cacache")
        let found = names(DiskCleanupCatalog.discover(home: home))
        #expect(found.contains("Xcode Derived Data"))
        #expect(found.contains("npm Cache"))
        #expect(!found.contains("pnpm Store"))
    }

    @Test("~/.claude and ~/.codex (history and config, not caches) are never offered")
    func claudeAndCodexNotOffered() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try mkdir(home, ".claude/projects")
        try mkdir(home, ".codex/sessions")
        try mkdir(home, "workspace/webview")
        let found = names(DiskCleanupCatalog.discover(home: home))
        #expect(!found.contains { $0.contains("Claude") || $0.contains("Codex") })
        #expect(!found.contains("Webview Workspace"))
    }

    @Test("only allowlisted parts of ~/Library are offered, never Keychains, Mail or Application Support")
    func libraryAllowlist() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        for dir in [
            "Library/Keychains", "Library/Mail", "Library/Application Support/Thing", "Library/Caches/com.example.app",
            "Library/Logs", "Library/Developer/Toolchains", "Library/Developer/Xcode",
            "Library/Developer/CoreSimulator",
        ] {
            try mkdir(home, dir)
        }
        let found = names(DiskCleanupCatalog.libraryItems(home: home))
        #expect(found == ["Library/Caches/com.example.app", "Library/Logs", "Library/Developer/Toolchains"])
    }

    @Test("gradle version folders are listed newest first; non-version folders are ignored")
    func gradleVersions() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        for dir in [".gradle/caches/8.4", ".gradle/caches/8.10.2", ".gradle/caches/modules-2", ".gradle/caches/jars-9"]
        {
            try mkdir(home, dir)
        }
        #expect(
            names(DiskCleanupCatalog.gradleVersionItems(home: home)) == ["Gradle 8.4", "Gradle 8.10.2"].sorted(by: >))
    }

    @Test("git checkouts up to two levels deep are found and marked as repositories")
    func workspaceRepos() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        for dir in ["workspace/app/a/.git", "workspace/b/.git", "workspace/plain/notrepo", "workspace/deep/x/y/c/.git"]
        {
            try mkdir(home, dir)
        }
        let repos = DiskCleanupCatalog.workspaceRepoItems(home: home)
        #expect(names(repos) == ["app/a", "b"])
        #expect(repos.allSatisfy { $0.kind == .gitRepository })
    }

    @Test("a symlinked directory is never offered, so a link can't redirect a delete")
    func symlinksSkipped() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try mkdir(home, "Library/Caches/real")
        try mkdir(home, "elsewhere")
        try FileManager.default.createSymbolicLink(
            at: home.appendingPathComponent("Library/Caches/link"),
            withDestinationURL: home.appendingPathComponent("elsewhere"))
        #expect(names(DiskCleanupCatalog.libraryItems(home: home)) == ["Library/Caches/real"])
    }

    // MARK: reload + deletion rules

    @Test("a reload keeps size and selection for paths still present and drops vanished ones")
    func carriedStateOnReload() {
        let kept = URL(fileURLWithPath: "/h/kept")
        let gone = URL(fileURLWithPath: "/h/gone")
        let previous = [
            kept: CleanupItemState(sizeBytes: 5, isSelected: true),
            gone: CleanupItemState(sizeBytes: 9, isSelected: true),
        ]
        let items = [CleanupItem(displayName: "k", path: kept, lastModifiedDate: nil, kind: .cache)]
        #expect(DiskCleanupCatalog.carriedState(previous: previous, into: items) == [kept: previous[kept] ?? .init()])
    }

    @Test("a selected item hidden by the size filter is not removable")
    func hiddenSelectionNotRemoved() {
        let home = URL(fileURLWithPath: "/Users/me")
        let shown = home.appendingPathComponent(".npm/_cacache")
        let hidden = home.appendingPathComponent(".pnpm-store")
        let removable = DiskCleanupCatalog.removablePaths(selected: [shown, hidden], visible: [shown], home: home)
        #expect(removable == [shown])
    }

    @Test(
        "paths outside home, home itself, and protected top-level folders are never safe to delete",
        arguments: [
            "/", "/Users/me", "/Users/other/x", "/Users/me/Documents", "/Users/me/Library", "/Users/me/.ssh",
            "/Users/me/workspace", "/Users/me/../other", "/Users/me/.claude", "/Users/meX/.npm",
        ])
    func unsafe(_ path: String) {
        #expect(!DiskCleanupCatalog.isSafeToDelete(URL(fileURLWithPath: path), home: URL(fileURLWithPath: "/Users/me")))
    }

    @Test("a cache directory below home is safe")
    func safe() {
        let home = URL(fileURLWithPath: "/Users/me")
        #expect(DiskCleanupCatalog.isSafeToDelete(home.appendingPathComponent("Library/Caches/x"), home: home))
        #expect(DiskCleanupCatalog.isSafeToDelete(home.appendingPathComponent("workspace/repo"), home: home))
        #expect(DiskCleanupCatalog.isSafeToDelete(home.appendingPathComponent(".Trash/old"), home: home))
    }
}
