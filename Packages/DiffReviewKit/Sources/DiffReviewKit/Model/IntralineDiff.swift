import Foundation

/// Computes word-level differences between the old and new text of a single modified line, so the
/// UI can highlight only the spans that actually changed instead of tinting the whole line.
public enum IntralineDiff {
    /// Lines longer than this are assumed to be minified/generated content — tokenizing per
    /// character run and diffing would be quadratic in line length, so these fall back to
    /// whole-line highlighting instead.
    private static let maxLineLength = 400

    /// Returns the character ranges in `old` and `new` that differ, aligned by a token-level LCS
    /// (a run of word characters, or a single other character, is one token).
    public static func changedRanges(
        old: String,
        new: String
    ) -> (old: [Range<String.Index>], new: [Range<String.Index>]) {
        guard old.count <= maxLineLength, new.count <= maxLineLength else {
            return (old: [old.startIndex..<old.endIndex], new: [new.startIndex..<new.endIndex])
        }

        let oldTokens = tokenize(old)
        let newTokens = tokenize(new)
        let (oldChanged, newChanged) = diffTokenIndices(oldTokens.map(\.text), newTokens.map(\.text))
        return (oldChanged.map { oldTokens[$0].range }, newChanged.map { newTokens[$0].range })
    }

    private struct Token {
        let text: String
        let range: Range<String.Index>
    }

    private static func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var index = text.startIndex
        while index < text.endIndex {
            let isWordChar = text[index].isLetter || text[index].isNumber || text[index] == "_"
            var end = text.index(after: index)
            if isWordChar {
                while end < text.endIndex, text[end].isLetter || text[end].isNumber || text[end] == "_" {
                    end = text.index(after: end)
                }
            }
            tokens.append(Token(text: String(text[index..<end]), range: index..<end))
            index = end
        }
        return tokens
    }

    /// Standard LCS-based diff: returns the indices of tokens in `old`/`new` that are NOT part of
    /// the longest common subsequence, i.e. the tokens that changed.
    private static func diffTokenIndices(_ old: [String], _ new: [String]) -> (old: [Int], new: [Int]) {
        let oldCount = old.count
        let newCount = new.count
        guard oldCount > 0 || newCount > 0 else { return ([], []) }

        var lcs = Array(repeating: Array(repeating: 0, count: newCount + 1), count: oldCount + 1)
        for oldIndex in stride(from: oldCount - 1, through: 0, by: -1) {
            for newIndex in stride(from: newCount - 1, through: 0, by: -1) {
                lcs[oldIndex][newIndex] =
                    old[oldIndex] == new[newIndex]
                    ? lcs[oldIndex + 1][newIndex + 1] + 1
                    : max(lcs[oldIndex + 1][newIndex], lcs[oldIndex][newIndex + 1])
            }
        }

        var oldChanged: [Int] = []
        var newChanged: [Int] = []
        var oldPos = 0
        var newPos = 0
        while oldPos < oldCount, newPos < newCount {
            if old[oldPos] == new[newPos] {
                oldPos += 1
                newPos += 1
            } else if lcs[oldPos + 1][newPos] >= lcs[oldPos][newPos + 1] {
                oldChanged.append(oldPos)
                oldPos += 1
            } else {
                newChanged.append(newPos)
                newPos += 1
            }
        }
        while oldPos < oldCount {
            oldChanged.append(oldPos)
            oldPos += 1
        }
        while newPos < newCount {
            newChanged.append(newPos)
            newPos += 1
        }

        return (oldChanged, newChanged)
    }
}
