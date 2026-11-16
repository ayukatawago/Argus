import Foundation

/// The five-block bar GitHub draws next to a file's `+N −M` counts: green blocks for additions, red
/// for deletions, and gray for whatever is left over.
enum DiffStatBlocks {
    enum Kind: Equatable {
        case addition
        case deletion
        case neutral
    }

    static let blockCount = 5

    /// Blocks in display order (additions, deletions, then neutral). Each non-zero side gets at least
    /// one block, so a tiny change still shows up; with no changes every block is neutral.
    ///
    /// Shares are floored first, then the blocks lost to flooring go to the side with the larger
    /// fractional part (ties go to additions), so an even split comes out 3 green / 2 red rather than
    /// overflowing the bar.
    static func blocks(additions: Int, deletions: Int) -> [Kind] {
        let additions = max(0, additions)
        let deletions = max(0, deletions)
        let total = additions + deletions
        guard total > 0 else { return Array(repeating: .neutral, count: blockCount) }

        let greenExact = Double(additions) * Double(blockCount) / Double(total)
        let redExact = Double(deletions) * Double(blockCount) / Double(total)
        var green = Int(greenExact)
        var red = Int(redExact)
        if green + red < blockCount {
            if greenExact - Double(green) >= redExact - Double(red) {
                green += 1
            } else {
                red += 1
            }
        }
        // A side with changes keeps at least one block, taken from the other side.
        if additions > 0, green == 0 {
            green = 1
            red -= 1
        }
        if deletions > 0, red == 0 {
            red = 1
            green -= 1
        }
        return Array(repeating: .addition, count: green)
            + Array(repeating: .deletion, count: red)
            + Array(repeating: .neutral, count: blockCount - green - red)
    }
}
