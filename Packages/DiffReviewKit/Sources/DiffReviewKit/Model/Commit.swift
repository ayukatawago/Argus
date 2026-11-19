import Foundation

/// A single commit in the `base..head` range shown in the diff review's commit sidebar.
public struct Commit: Sendable, Identifiable, Equatable {
    public let hash: String
    public let shortHash: String
    public let subject: String
    public let author: String
    public let relativeDate: String
    /// Full commit message (subject and body), for the row's hover tooltip.
    public let message: String
    /// True for a root commit (no parent), whose `hash^` doesn't exist.
    public let isRoot: Bool

    public var id: String { hash }

    public init(
        hash: String, shortHash: String, subject: String, author: String, relativeDate: String, message: String = "",
        isRoot: Bool = false
    ) {
        self.hash = hash
        self.shortHash = shortHash
        self.subject = subject
        self.author = author
        self.relativeDate = relativeDate
        self.message = message.isEmpty ? subject : message
        self.isRoot = isRoot
    }
}
