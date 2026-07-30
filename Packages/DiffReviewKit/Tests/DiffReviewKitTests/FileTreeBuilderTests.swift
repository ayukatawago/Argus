import Testing

@testable import DiffReviewKit

@Suite("FileTreeBuilder")
struct FileTreeBuilderTests {
    private func file(_ path: String) -> DiffFile {
        DiffFile(path: path, kind: .modified, hunks: [])
    }

    @Test("a single-child directory chain collapses into one node")
    func collapsesSingleChildChain() throws {
        let tree = FileTreeBuilder.build(from: [file("Sources/DiffReviewKit/UI/FileTreeView.swift")])

        let root = try #require(tree.first)
        #expect(tree.count == 1)
        #expect(root.name == "Sources/DiffReviewKit/UI")
        #expect(root.isDirectory)

        let leaf = try #require(root.children?.first)
        #expect(root.children?.count == 1)
        #expect(leaf.name == "FileTreeView.swift")
        #expect(leaf.file?.path == "Sources/DiffReviewKit/UI/FileTreeView.swift")
    }

    @Test("a directory with multiple children does not collapse past the branch point")
    func stopsAtBranchPoint() throws {
        let tree = FileTreeBuilder.build(from: [
            file("Sources/DiffReviewKit/UI/FileTreeView.swift"),
            file("Sources/DiffReviewKit/Git/GitRunner.swift"),
        ])

        let root = try #require(tree.first)
        #expect(tree.count == 1)
        #expect(root.name == "Sources/DiffReviewKit")

        let children = try #require(root.children)
        #expect(children.count == 2)
        #expect(Set(children.map(\.name)) == ["UI", "Git"])
    }

    @Test("a folder whose only child is a file is not merged with it")
    func doesNotMergeFolderWithSoleFileChild() throws {
        let tree = FileTreeBuilder.build(from: [file("Sources/Foo.swift")])

        let root = try #require(tree.first)
        #expect(root.name == "Sources")
        #expect(root.isDirectory)

        let leaf = try #require(root.children?.first)
        #expect(leaf.name == "Foo.swift")
        #expect(!leaf.isDirectory)
    }
}
