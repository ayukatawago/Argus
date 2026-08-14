import Testing

@testable import Monitors

@Suite("DiskUsage")
struct DiskUsageTests {
    @Test("a normal total/free pair computes the expected percentage")
    func normalPercentage() {
        let usage = DiskUsage(total: 200, free: 50)
        #expect(usage.percentFree == 25)
    }

    @Test("a zero total defaults to 100% free rather than dividing by zero")
    func zeroTotalDefaultsToFullyFree() {
        let usage = DiskUsage(total: 0, free: 0)
        #expect(usage.percentFree == 100)
    }

    @Test("a negative total also defaults to 100% free")
    func negativeTotalDefaultsToFullyFree() {
        let usage = DiskUsage(total: -1, free: 0)
        #expect(usage.percentFree == 100)
    }

    @Test("isLow is true when percentFree is strictly below the threshold")
    func belowThresholdIsLow() {
        let usage = DiskUsage(total: 100, free: 4)
        #expect(usage.isLow(threshold: 5) == true)
    }

    @Test("isLow is false when percentFree exactly equals the threshold")
    func atThresholdIsNotLow() {
        let usage = DiskUsage(total: 100, free: 5)
        #expect(usage.isLow(threshold: 5) == false)
    }

    @Test("isLow is false when percentFree is above the threshold")
    func aboveThresholdIsNotLow() {
        let usage = DiskUsage(total: 100, free: 50)
        #expect(usage.isLow(threshold: 5) == false)
    }
}
