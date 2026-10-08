import Foundation
import Testing

@testable import ArgusSupport

@Suite("CorruptFileBackup")
struct CorruptFileBackupTests {
    private func makeDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("corrupt-backup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("a non-empty file is copied beside the original, leaving the original in place")
    func copiesAside() throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("argus.json")
        try Data("{ not json".utf8).write(to: file)

        let backup = try #require(CorruptFileBackup.preserve(file, now: Date(timeIntervalSince1970: 1_790_000_000)))
        #expect(backup.lastPathComponent == "argus.json.corrupt-1790000000")
        #expect(try Data(contentsOf: backup) == Data("{ not json".utf8))
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test("a missing or empty file has nothing to preserve")
    func nothingToPreserve() throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(CorruptFileBackup.preserve(dir.appendingPathComponent("absent.json")) == nil)
        let empty = dir.appendingPathComponent("empty.json")
        try Data().write(to: empty)
        #expect(CorruptFileBackup.preserve(empty) == nil)
    }

    @Test("the same bad contents are not backed up twice, but changed contents are")
    func deduplicates() throws {
        let dir = try makeDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("a.json")
        try Data("bad".utf8).write(to: file)
        #expect(CorruptFileBackup.preserve(file, now: Date(timeIntervalSince1970: 100)) != nil)
        #expect(CorruptFileBackup.preserve(file, now: Date(timeIntervalSince1970: 200)) == nil)
        try Data("worse".utf8).write(to: file)
        #expect(CorruptFileBackup.preserve(file, now: Date(timeIntervalSince1970: 300)) != nil)
        let backups = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.contains(".corrupt-") }
        #expect(backups.count == 2)
    }
}
