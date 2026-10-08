import Foundation
import Testing

@testable import ArgusSupport

@Suite("MarkdownFileTree")
struct MarkdownFileTreeTests {
    private func makeRoot(_ files: [String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("md-tree-\(UUID().uuidString)")
        for file in files {
            let url = root.appendingPathComponent(file)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("# x".utf8).write(to: url)
        }
        return root
    }

    private func names(_ nodes: [MarkdownTreeNode]) -> [String] {
        nodes.flatMap { [$0.name] + names($0.children ?? []) }
    }

    @Test("directories come first, then files, each sorted; non-markdown files are omitted")
    func ordering() throws {
        let root = try makeRoot(["b.md", "a.md", "docs/z.md", "notes.txt", "src/main.swift"])
        defer { try? FileManager.default.removeItem(at: root) }
        let tree = MarkdownFileTree.build(at: root.path)
        #expect(tree.map(\.name) == ["docs", "a.md", "b.md"])
        #expect(tree.first?.type == "dir")
        #expect(tree.first?.children?.first?.path == root.appendingPathComponent("docs/z.md").path)
    }

    @Test("hidden entries and dependency folders are skipped")
    func skipsNoise() throws {
        let root = try makeRoot([
            ".git/README.md", ".hidden.md", "node_modules/pkg/README.md", "Pods/x/y.md", "keep.md",
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(names(MarkdownFileTree.build(at: root.path)) == ["keep.md"])
    }

    @Test("a directory with no markdown inside is dropped")
    func dropsEmptyDirectories() throws {
        let root = try makeRoot(["empty/a.txt", "full/b.md"])
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(names(MarkdownFileTree.build(at: root.path)) == ["full", "b.md"])
    }

    @Test("a symlink loop terminates and symlinked directories are not followed")
    func symlinkLoop() throws {
        let root = try makeRoot(["real/a.md"])
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("real/loop"), withDestinationURL: root)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("alias"), withDestinationURL: root.appendingPathComponent("real"))
        #expect(names(MarkdownFileTree.build(at: root.path)) == ["real", "a.md"])
    }

    @Test("depth is capped")
    func depthCap() throws {
        let root = try makeRoot(["a/b/c/d.md", "top.md"])
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(names(MarkdownFileTree.build(at: root.path, maxDepth: 2)) == ["top.md"])
        #expect(names(MarkdownFileTree.build(at: root.path, maxDepth: 4)).contains("d.md"))
    }

    @Test("the node count is capped")
    func nodeCap() throws {
        let root = try makeRoot((0..<20).map { "f\($0).md" })
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(MarkdownFileTree.build(at: root.path, maxNodes: 5).count == 5)
    }

    @Test("a missing directory yields an empty tree")
    func missing() {
        #expect(MarkdownFileTree.build(at: "/nonexistent/\(UUID().uuidString)").isEmpty)
    }

    @Test("the encoded JSON keeps the keys the preview page reads")
    func jsonShape() throws {
        let node = MarkdownTreeNode(type: "file", name: "a.md", path: "/a.md", children: nil)
        let json = try String(decoding: JSONEncoder().encode(node), as: UTF8.self)
        #expect(json.contains(#""type":"file""#))
        #expect(json.contains(#""name":"a.md""#))
        #expect(json.contains(#""path":"\/a.md""#))
    }
}

@Suite("TemplateFill")
struct TemplateFillTests {
    @Test("placeholders are replaced")
    func replaces() {
        #expect(TemplateFill.fill("a {{X}} b {{Y}}", with: ["X": "1", "Y": "2"]) == "a 1 b 2")
    }

    @Test("a value containing another placeholder is inserted literally, never re-substituted")
    func valuesNotRescanned() {
        let result = TemplateFill.fill("{{A}}|{{B}}", with: ["A": "has {{B}} inside", "B": "bee"])
        #expect(result == "has {{B}} inside|bee")
    }

    @Test("unknown placeholders and unbalanced braces are left as written")
    func unknownLeftAlone() {
        #expect(TemplateFill.fill("{{NOPE}} {{X", with: ["X": "1"]) == "{{NOPE}} {{X")
        #expect(TemplateFill.fill("plain", with: [:]) == "plain")
    }

    @Test("repeated placeholders are all replaced")
    func repeated() {
        #expect(TemplateFill.fill("{{X}}{{X}}", with: ["X": "ab"]) == "abab")
    }

    @Test("an empty template stays empty")
    func empty() {
        #expect(TemplateFill.fill("", with: ["X": "1"]).isEmpty)
    }
}
