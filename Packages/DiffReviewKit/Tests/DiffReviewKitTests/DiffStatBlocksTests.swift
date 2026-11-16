import Testing

@testable import DiffReviewKit

@Suite("DiffStatBlocks")
struct DiffStatBlocksTests {
    @Test("zero changes shows five neutral blocks")
    func zeroChanges() {
        #expect(DiffStatBlocks.blocks(additions: 0, deletions: 0) == Array(repeating: .neutral, count: 5))
    }

    @Test("all additions fill five green blocks")
    func allAdd() {
        #expect(DiffStatBlocks.blocks(additions: 40, deletions: 0) == Array(repeating: .addition, count: 5))
    }

    @Test("all deletions fill five red blocks")
    func allDelete() {
        #expect(DiffStatBlocks.blocks(additions: 0, deletions: 3) == Array(repeating: .deletion, count: 5))
    }

    @Test("a mixed change splits the five blocks in proportion, green first")
    func mixed() {
        // 3 of 4 changed lines are additions: 3.75 blocks round to 4 green, 1.25 round to 1 red.
        #expect(
            DiffStatBlocks.blocks(additions: 3, deletions: 1)
                == [.addition, .addition, .addition, .addition, .deletion]
        )
    }

    @Test("an even split is pinned at three green and two red, using all five blocks")
    func evenSplit() {
        #expect(
            DiffStatBlocks.blocks(additions: 5, deletions: 5)
                == [.addition, .addition, .addition, .deletion, .deletion]
        )
        #expect(
            DiffStatBlocks.blocks(additions: 50, deletions: 50)
                == DiffStatBlocks.blocks(additions: 5, deletions: 5)
        )
    }

    @Test("a side with more changes never gets fewer blocks than the other")
    func monotonic() {
        for deletions in 1...12 {
            let greens = (1...12).map { additions in
                DiffStatBlocks.blocks(additions: additions, deletions: deletions).filter { $0 == .addition }.count
            }
            #expect(greens == greens.sorted())
        }
    }

    @Test("a tiny side still gets one block, so it stays visible")
    func tinySideVisible() {
        let blocks = DiffStatBlocks.blocks(additions: 1, deletions: 500)
        #expect(blocks.count == 5)
        #expect(blocks.contains(.addition))
        #expect(blocks.filter { $0 == .deletion }.count == 4)
    }

    @Test("always returns exactly five blocks")
    func alwaysFive() {
        for additions in 0...12 {
            for deletions in 0...12 {
                #expect(DiffStatBlocks.blocks(additions: additions, deletions: deletions).count == 5)
            }
        }
    }
}
