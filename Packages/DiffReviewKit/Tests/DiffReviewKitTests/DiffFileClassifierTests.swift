import Testing

@testable import DiffReviewKit

@Suite("DiffFileClassifier")
struct DiffFileClassifierTests {
    @Test(
        "test file paths are classified as test",
        arguments: [
            "Tests/DiffReviewKitTests/UnifiedDiffParserTests.swift",
            "Sources/Foo/FooTest.swift",
            "src/foo/foo.test.ts",
            "src/foo/foo.spec.tsx",
            "pkg/foo/foo_test.go",
            "app/test_foo.py",
            "spec/models/user_spec.rb",
            "src/__tests__/Foo.js",
        ]
    )
    func testFiles(path: String) {
        #expect(DiffFileClassifier.isTestFile(path))
    }

    @Test(
        "non-test file paths are classified as production",
        arguments: [
            "Sources/Foo/Foo.swift",
            "src/foo/foo.ts",
            "pkg/foo/foo.go",
            "app/foo.py",
            "app/models/user.rb",
            "README.md",
        ]
    )
    func productionFiles(path: String) {
        #expect(!DiffFileClassifier.isTestFile(path))
    }
}
