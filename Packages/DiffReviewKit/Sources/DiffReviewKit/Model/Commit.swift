import Foundation

/// A single commit in the `base..head` range shown in the diff review's commit sidebar.
public struct Commit: Sendable, Identifiable, Equatable {
    public let hash: String
    public let shortHash: String
    public let subject: String
    public let author: String
    public let relativeDate: String

    public var id: String { hash }

    public init(hash: String, shortHash: String, subject: String, author: String, relativeDate: String) {
        self.hash = hash
        self.shortHash = shortHash
        self.subject = subject
        self.author = author
        self.relativeDate = relativeDate
    }
}
