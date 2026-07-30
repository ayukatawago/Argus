import Foundation

/// Aggregate file/addition/deletion counts for a category of changed files (e.g. all files, or
/// just production/test code).
public struct DiffSizeStat: Sendable, Equatable {
    public let label: String
    public let fileCount: Int
    public let additions: Int
    public let deletions: Int

    public init(label: String, files: [DiffFile]) {
        self.label = label
        fileCount = files.count
        additions = files.reduce(0) { $0 + $1.additionCount }
        deletions = files.reduce(0) { $0 + $1.deletionCount }
    }
}
