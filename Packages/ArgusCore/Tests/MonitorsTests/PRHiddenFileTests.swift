import Foundation
import Testing

@testable import Monitors

@Suite("PRHiddenFile")
struct PRHiddenFileTests {
    @Test("loading a missing file falls back to an empty set")
    func missingFileFallsBackToEmptySet() {
        let url = Self.tempURL()
        #expect(PRHiddenFile.load(from: url).isEmpty)
    }

    @Test("saving then loading round-trips the hidden ids")
    func roundTrips() {
        let url = Self.tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let ids: Set<Int> = [1, 2, 3]
        PRHiddenFile.save(ids, to: url)
        #expect(PRHiddenFile.load(from: url) == ids)
    }

    @Test("saving creates intermediate directories")
    func createsIntermediateDirectories() {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("pr-hidden-file-tests-\(UUID().uuidString)")
        let url = base.appendingPathComponent("nested/deeper/hidden-prs.json")
        defer { try? FileManager.default.removeItem(at: base) }

        PRHiddenFile.save([42], to: url)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test("a corrupt file loads as an empty set rather than throwing")
    func corruptFileLoadsAsEmptySet() {
        let url = Self.tempURL()
        defer { try? FileManager.default.removeItem(at: url) }

        try? Data("not json".utf8).write(to: url)
        #expect(PRHiddenFile.load(from: url).isEmpty)
    }

    private static func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("pr-hidden-file-tests-\(UUID().uuidString).json")
    }
}
