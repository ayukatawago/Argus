import Foundation

/// A user comment anchored to a single line in a specific file within a diff review.
public struct ReviewComment: Identifiable, Hashable, Sendable {
    /// Which column of the side-by-side view the comment is anchored to.
    public enum Side: Sendable, Hashable {
        case old
        case new
    }

    public enum Status: Sendable, Hashable {
        case open
        case replying
        case applying
        case resolved
    }

    public let id: UUID
    public let filePath: String
    public let side: Side
    /// First line of the commented range. `nil` for an ordinary single-line comment, in which
    /// case the comment covers only `lineNumber`.
    public let startLineNumber: Int?
    /// Last line of the commented range (the anchor line comments render under, matching
    /// GitHub's convention of anchoring a multi-line comment to its final line).
    public let lineNumber: Int
    public var body: String
    public var status: Status
    public var replies: [ReviewReply]

    public init(
        id: UUID = UUID(),
        filePath: String,
        side: Side,
        startLineNumber: Int? = nil,
        lineNumber: Int,
        body: String,
        status: Status = .open,
        replies: [ReviewReply] = []
    ) {
        self.id = id
        self.filePath = filePath
        self.side = side
        self.startLineNumber = startLineNumber
        self.lineNumber = lineNumber
        self.body = body
        self.status = status
        self.replies = replies
    }
}

/// One turn of agent output attached to a `ReviewComment` thread.
public struct ReviewReply: Identifiable, Hashable, Sendable {
    public enum Kind: Sendable, Hashable {
        /// Read-only answer from the agent; no files were modified.
        case reply
        /// The agent was asked to make the change; files may have been modified.
        case apply
        case error
    }

    public let id: UUID
    public let kind: Kind
    public var text: String
    /// The agent CLI's session id, when available, so a follow-up can resume the same thread.
    public var sessionID: String?

    public init(id: UUID = UUID(), kind: Kind, text: String, sessionID: String? = nil) {
        self.id = id
        self.kind = kind
        self.text = text
        self.sessionID = sessionID
    }
}
