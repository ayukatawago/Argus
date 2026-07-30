import Testing

@testable import DiffReviewKit

@Suite("UnifiedDiffParser")
struct UnifiedDiffParserTests {
    @Test("empty input produces no files")
    func emptyInput() {
        #expect(UnifiedDiffParser.parse("").isEmpty)
    }

    @Test("modified file with a single hunk")
    func modifiedFile() throws {
        let text = """
            diff --git a/Sources/Foo.swift b/Sources/Foo.swift
            index e69de29..4b825dc 100644
            --- a/Sources/Foo.swift
            +++ b/Sources/Foo.swift
            @@ -1,3 +1,4 @@
             func foo() {
            -    return 1
            +    return 2
            +    // comment
             }
            """
        let files = UnifiedDiffParser.parse(text)
        #expect(files.count == 1)

        let file = try #require(files.first)
        #expect(file.path == "Sources/Foo.swift")
        #expect(file.oldPath == nil)
        #expect(file.kind == .modified)
        #expect(file.additionCount == 2)
        #expect(file.deletionCount == 1)

        let hunk = try #require(file.hunks.first)
        #expect(hunk.header == "@@ -1,3 +1,4 @@")
        #expect(hunk.lines.count == 5)

        #expect(hunk.lines[0].kind == .context)
        #expect(hunk.lines[0].text == "func foo() {")
        #expect(hunk.lines[0].oldLineNumber == 1)
        #expect(hunk.lines[0].newLineNumber == 1)

        #expect(hunk.lines[1].kind == .deletion)
        #expect(hunk.lines[1].text == "    return 1")
        #expect(hunk.lines[1].oldLineNumber == 2)
        #expect(hunk.lines[1].newLineNumber == nil)

        #expect(hunk.lines[2].kind == .addition)
        #expect(hunk.lines[2].text == "    return 2")
        #expect(hunk.lines[2].oldLineNumber == nil)
        #expect(hunk.lines[2].newLineNumber == 2)

        #expect(hunk.lines[3].kind == .addition)
        #expect(hunk.lines[3].text == "    // comment")
        #expect(hunk.lines[3].newLineNumber == 3)

        #expect(hunk.lines[4].kind == .context)
        #expect(hunk.lines[4].text == "}")
        #expect(hunk.lines[4].oldLineNumber == 3)
        #expect(hunk.lines[4].newLineNumber == 4)
    }

    @Test("new file shows as added with no old path")
    func newFile() throws {
        let text = """
            diff --git a/Sources/New.swift b/Sources/New.swift
            new file mode 100644
            index 0000000..4b825dc
            --- /dev/null
            +++ b/Sources/New.swift
            @@ -0,0 +1,2 @@
            +struct New {}
            +
            """
        let file = try #require(UnifiedDiffParser.parse(text).first)
        #expect(file.kind == .added)
        #expect(file.path == "Sources/New.swift")
        #expect(file.oldPath == nil)
        #expect(file.additionCount == 2)
        #expect(file.deletionCount == 0)
    }

    @Test("deleted file shows as deleted, keeping the original path")
    func deletedFile() throws {
        let text = """
            diff --git a/Sources/Old.swift b/Sources/Old.swift
            deleted file mode 100644
            index 4b825dc..0000000
            --- a/Sources/Old.swift
            +++ /dev/null
            @@ -1,2 +0,0 @@
            -struct Old {}
            -
            """
        let file = try #require(UnifiedDiffParser.parse(text).first)
        #expect(file.kind == .deleted)
        #expect(file.path == "Sources/Old.swift")
        #expect(file.deletionCount == 2)
        #expect(file.additionCount == 0)
    }

    @Test("renamed file with content changes tracks both paths")
    func renamedFileWithChanges() throws {
        let text = """
            diff --git a/Old.swift b/New.swift
            similarity index 90%
            rename from Old.swift
            rename to New.swift
            index e69de29..4b825dc 100644
            --- a/Old.swift
            +++ b/New.swift
            @@ -1,1 +1,1 @@
            -old
            +new
            """
        let file = try #require(UnifiedDiffParser.parse(text).first)
        #expect(file.kind == .renamed)
        #expect(file.path == "New.swift")
        #expect(file.oldPath == "Old.swift")
        #expect(file.hunks.first?.lines.count == 2)
    }

    @Test("pure rename with no content change has no hunks")
    func pureRename() throws {
        let text = """
            diff --git a/Old.txt b/New.txt
            similarity index 100%
            rename from Old.txt
            rename to New.txt
            """
        let file = try #require(UnifiedDiffParser.parse(text).first)
        #expect(file.kind == .renamed)
        #expect(file.path == "New.txt")
        #expect(file.oldPath == "Old.txt")
        #expect(file.hunks.isEmpty)
        #expect(file.isBinaryOrHunkless)
    }

    @Test("binary file diff has no hunks but resolves the path from the header")
    func binaryFile() throws {
        let text = """
            diff --git a/image.png b/image.png
            index 4b825dc..e69de29 100644
            Binary files a/image.png and b/image.png differ
            """
        let file = try #require(UnifiedDiffParser.parse(text).first)
        #expect(file.path == "image.png")
        #expect(file.kind == .modified)
        #expect(file.hunks.isEmpty)
    }

    @Test("multiple files in one diff are all parsed, in order")
    func multipleFiles() {
        let text = """
            diff --git a/A.swift b/A.swift
            index e69de29..4b825dc 100644
            --- a/A.swift
            +++ b/A.swift
            @@ -1,1 +1,1 @@
            -a
            +A
            diff --git a/B.swift b/B.swift
            index e69de29..4b825dc 100644
            --- a/B.swift
            +++ b/B.swift
            @@ -1,1 +1,1 @@
            -b
            +B
            """
        let files = UnifiedDiffParser.parse(text)
        #expect(files.map(\.path) == ["A.swift", "B.swift"])
    }

    @Test("multiple hunks within one file are all captured")
    func multipleHunks() throws {
        let text = """
            diff --git a/A.swift b/A.swift
            index e69de29..4b825dc 100644
            --- a/A.swift
            +++ b/A.swift
            @@ -1,2 +1,2 @@
            -one
            +ONE
             two
            @@ -10,2 +10,2 @@
             nine
            -ten
            +TEN
            """
        let file = try #require(UnifiedDiffParser.parse(text).first)
        #expect(file.hunks.count == 2)
        #expect(file.hunks.first?.lines.first?.oldLineNumber == 1)
        #expect(file.hunks.last?.lines.first?.oldLineNumber == 10)
    }
}
