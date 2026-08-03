import Foundation

/// Builds the instruction text sent to the headless agent for a review comment.
public enum PromptComposer {
    /// Composes a prompt for a single comment, giving the agent enough context (file, line,
    /// surrounding hunk) to act without needing to re-read the whole diff.
    public static func compose(comment: ReviewComment, file: DiffFile, mode: AgentRunMode) -> String {
        var lines: [String] = []

        switch mode {
        case .reply:
            lines.append("You are reviewing a code change as a pull-request reviewer would.")
            lines.append("Answer the reviewer's question below. Do not modify any files.")

        case .apply:
            lines.append("You are addressing a pull-request review comment.")
            lines.append("Make the requested change directly in the working tree.")
        }

        lines.append("")
        lines.append("File: \(file.path)")
        lines.append("\(lineDescription(for: comment)) (\(comment.side == .old ? "old" : "new") side):")
        lines.append("")
        lines.append(contextSnippet(for: comment, in: file))
        lines.append("")
        lines.append("Reviewer comment:")
        lines.append(comment.body)

        return lines.joined(separator: "\n")
    }

    private static func lineDescription(for comment: ReviewComment) -> String {
        guard let startLineNumber = comment.startLineNumber, startLineNumber != comment.lineNumber else {
            return "Line \(comment.lineNumber)"
        }
        return "Lines \(startLineNumber)-\(comment.lineNumber)"
    }

    /// Extracts the hunk containing any commented line, rendered as plain text, to anchor the
    /// agent's attention without requiring it to re-derive the diff itself.
    private static func contextSnippet(for comment: ReviewComment, in file: DiffFile) -> String {
        let range = (comment.startLineNumber ?? comment.lineNumber)...comment.lineNumber
        for hunk in file.hunks {
            let matches = hunk.lines.contains { line in
                switch comment.side {
                case .old: line.oldLineNumber.map(range.contains) ?? false
                case .new: line.newLineNumber.map(range.contains) ?? false
                }
            }
            guard matches else { continue }
            let rendered = hunk.lines.map { line -> String in
                let marker: String
                switch line.kind {
                case .context: marker = " "
                case .addition: marker = "+"
                case .deletion: marker = "-"
                }
                return marker + line.text
            }
            return (["```", hunk.header] + rendered + ["```"]).joined(separator: "\n")
        }
        return "```\n(context not found)\n```"
    }
}
