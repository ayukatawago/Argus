import Foundation

/// Best-effort classification of a changed file as test code, based on path/name conventions
/// common across languages (this package isn't Swift-specific).
public enum DiffFileClassifier {
    private static let testDirectoryNames: Set<String> = [
        "test", "tests", "__tests__", "spec", "specs", "androidtest",
    ]

    private static let testFileSuffixes = [
        "test.swift", "tests.swift",
        "test.kt", "test.java",
        "_test.go",
        "_test.py",
        ".test.ts", ".test.tsx", ".test.js", ".test.jsx",
        ".spec.ts", ".spec.tsx", ".spec.js", ".spec.jsx",
        "spec.rb",
    ]

    public static func isTestFile(_ path: String) -> Bool {
        let components = path.lowercased().split(separator: "/").map(String.init)
        if components.dropLast().contains(where: { testDirectoryNames.contains($0) }) {
            return true
        }

        guard let fileName = components.last else { return false }
        if testFileSuffixes.contains(where: { fileName.hasSuffix($0) }) {
            return true
        }
        return fileName.hasPrefix("test_")
    }
}
