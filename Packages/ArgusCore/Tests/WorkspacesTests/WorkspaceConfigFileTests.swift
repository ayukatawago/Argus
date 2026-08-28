import Foundation
import Testing

@testable import Workspaces

@Suite("WorkspaceConfigFile")
struct WorkspaceConfigFileTests {
    @Test("loading a missing file falls back to the given default roots")
    func missingFileFallsBackToDefaultRoots() {
        let url = Self.tempURL()
        let config = WorkspaceConfigFile.load(from: url, defaultRoots: ["/Users/taku/workspace"])
        #expect(config == WorkspaceConfig(roots: ["/Users/taku/workspace"]))
    }

    @Test("saving then loading round-trips a config")
    func roundTrips() {
        let url = Self.tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let config = WorkspaceConfig(
            roots: ["/a", "/b"],
            hiddenWorktreeIDs: ["/a/hidden"],
            excludedRepoPaths: ["/a/excluded"],
            repoOrder: ["/b", "/a"],
            openWorktreeIDs: ["/a", "/b/linked"]
        )
        WorkspaceConfigFile.save(config, to: url)
        let loaded = WorkspaceConfigFile.load(from: url, defaultRoots: ["/fallback"])
        #expect(loaded == config)
    }

    @Test("saving creates intermediate directories")
    func createsIntermediateDirectories() {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("workspace-config-file-tests-\(UUID().uuidString)")
        let url = base.appendingPathComponent("nested/deeper/workspaces.json")
        defer { try? FileManager.default.removeItem(at: base) }

        WorkspaceConfigFile.save(WorkspaceConfig(roots: ["/x"]), to: url)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test("loading malformed JSON falls back to defaults rather than throwing")
    func malformedJSONFallsBackToDefaults() throws {
        let url = Self.tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not valid json".utf8).write(to: url)

        let config = WorkspaceConfigFile.load(from: url, defaultRoots: ["/fallback"])
        #expect(config == WorkspaceConfig(roots: ["/fallback"]))
    }

    @Test("missing optional fields decode to empty rather than failing the whole load")
    func missingOptionalFieldsDecodeToEmpty() throws {
        let url = Self.tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{"roots":["/only-roots"]}"#.utf8).write(to: url)

        let config = WorkspaceConfigFile.load(from: url, defaultRoots: ["/fallback"])
        #expect(config == WorkspaceConfig(roots: ["/only-roots"]))
    }

    private static func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("workspace-config-file-tests-\(UUID().uuidString).json")
    }
}
