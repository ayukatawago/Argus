import Foundation

/// Case-insensitive subsequence matching for the command palette and sidebar filter.
public enum FuzzyMatcher {
    /// A score for `query` as a subsequence of `candidate`, or nil if it isn't one. Higher is
    /// better: consecutive runs, word-boundary hits and an early first hit all add to the score.
    /// An empty query matches everything with score 0.
    public static func score(query: String, in candidate: String) -> Int? {
        let needle = Array(query.lowercased())
        if needle.isEmpty { return 0 }
        let hay = Array(candidate.lowercased())
        var score = 0
        var needleIndex = 0
        var previousMatch = -2
        for (index, char) in hay.enumerated() where needleIndex < needle.count && char == needle[needleIndex] {
            score += 1
            if index == previousMatch + 1 { score += 4 }
            if index == 0 || !hay[index - 1].isLetter && !hay[index - 1].isNumber { score += 3 }
            if needleIndex == 0 { score += max(0, 5 - index) }
            previousMatch = index
            needleIndex += 1
        }
        return needleIndex == needle.count ? score : nil
    }

    /// The best score of `query` across several candidate strings (e.g. repo name + branch), or
    /// nil if none match.
    public static func bestScore(query: String, in candidates: [String]) -> Int? {
        candidates.compactMap { score(query: query, in: $0) }.max()
    }

    /// `items` that match `query`, best first. Ties keep their original order; an empty query
    /// returns `items` unchanged.
    public static func rank<T>(_ items: [T], query: String, candidates: (T) -> [String]) -> [T] {
        if query.isEmpty { return items }
        let scored = items.indices.compactMap { index -> Scored? in
            bestScore(query: query, in: candidates(items[index])).map { Scored(score: $0, index: index) }
        }
        let ordered = scored.sorted { $0.score != $1.score ? $0.score > $1.score : $0.index < $1.index }
        return ordered.map { items[$0.index] }
    }

    private struct Scored {
        let score: Int
        let index: Int
    }
}
