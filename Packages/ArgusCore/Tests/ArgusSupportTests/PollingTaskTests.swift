import Foundation
import Testing

@testable import ArgusSupport

private struct TimeoutError: Error {}

private actor Counter {
    private(set) var count = 0

    func increment() {
        count += 1
    }

    func waitForAtLeast(_ target: Int, timeoutNanoseconds: UInt64 = 2_000_000_000) async throws -> Int {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while count < target {
            guard DispatchTime.now().uptimeNanoseconds < deadline else { throw TimeoutError() }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        return count
    }
}

/// A lock-protected counter for use inside the synchronous `interval` closure, where capturing an
/// actor would force the closure to become async.
private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    @discardableResult
    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }

    var current: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

@Suite("PollingTask")
struct PollingTaskTests {
    @Test(".actThenSleep calls the action immediately, before the first sleep")
    func actThenSleepRunsImmediately() async throws {
        let counter = Counter()
        let task = PollingTask.repeating(
            order: .actThenSleep,
            interval: { 1_000_000_000 },
            action: { await counter.increment() }
        )
        defer { task.cancel() }

        // With a 1s interval, only the immediate call should land within a short wait.
        let count = try await counter.waitForAtLeast(1, timeoutNanoseconds: 300_000_000)
        #expect(count == 1)
    }

    @Test(".sleepThenAct waits out the interval before the first action call")
    func sleepThenActWaitsFirst() async throws {
        let counter = Counter()
        let task = PollingTask.repeating(
            order: .sleepThenAct,
            interval: { 60_000_000 },
            action: { await counter.increment() }
        )
        defer { task.cancel() }

        try await Task.sleep(nanoseconds: 20_000_000)
        let countBeforeInterval = await counter.count
        #expect(countBeforeInterval < 1)

        let count = try await counter.waitForAtLeast(1)
        #expect(count == 1)
    }

    @Test("the action repeats on the given interval")
    func repeatsUntilCancelled() async throws {
        let counter = Counter()
        let task = PollingTask.repeating(
            order: .actThenSleep,
            interval: { 10_000_000 },
            action: { await counter.increment() }
        )
        let count = try await counter.waitForAtLeast(3)
        task.cancel()
        #expect(count >= 3)
    }

    @Test("cancelling stops further action calls")
    func cancellingStopsFurtherCalls() async throws {
        let counter = Counter()
        let task = PollingTask.repeating(
            order: .actThenSleep,
            interval: { 5_000_000 },
            action: { await counter.increment() }
        )
        _ = try await counter.waitForAtLeast(2)
        task.cancel()
        let countAtCancel = await counter.count

        try await Task.sleep(nanoseconds: 100_000_000)
        let countAfterWait = await counter.count
        // At most one more call may already have been in flight when cancel() landed.
        #expect(countAfterWait <= countAtCancel + 1)
    }

    @Test("interval is re-evaluated before every sleep, not captured once")
    func intervalIsReevaluatedEachCycle() async throws {
        let counter = Counter()
        let evalCounter = LockedCounter()
        let task = PollingTask.repeating(
            order: .actThenSleep,
            interval: {
                evalCounter.increment()
                return 5_000_000
            },
            action: { await counter.increment() }
        )
        defer { task.cancel() }

        _ = try await counter.waitForAtLeast(3)
        #expect(evalCounter.current >= 3)
    }
}
