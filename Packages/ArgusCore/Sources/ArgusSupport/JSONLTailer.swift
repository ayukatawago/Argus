import Foundation

/// Tails a JSON-Lines file, yielding each newly appended line's UTF-8 bytes as it arrives.
///
/// Replaces the near-identical polling loop duplicated in HookIPC.pollEventLog and
/// ShellStateBus.tailShellEvents. The offset/carry/truncation bookkeeping lives in `JSONLCursor`;
/// a write that lands mid-line is held until its newline arrives. Consumers decode each line
/// themselves — this type only knows about bytes and newlines, not JSON.
public struct JSONLTailer: Sendable {
    public let path: String
    private let pollIntervalNanoseconds: UInt64

    public init(path: String, pollIntervalNanoseconds: UInt64 = 200_000_000) {
        self.path = path
        self.pollIntervalNanoseconds = pollIntervalNanoseconds
    }

    /// Starts tailing. The stream never finishes on its own — cancel the consuming task (e.g. by
    /// wrapping the `for await` loop in a `Task` and cancelling that `Task`) to stop.
    public func lines() -> AsyncStream<Data> {
        let path = path
        let interval = pollIntervalNanoseconds
        return AsyncStream { continuation in
            let task = Task.detached(priority: .utility) {
                await Self.pollLoop(path: path, intervalNanoseconds: interval, continuation: continuation)
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func pollLoop(
        path: String,
        intervalNanoseconds: UInt64,
        continuation: AsyncStream<Data>.Continuation
    ) async {
        var cursor = JSONLCursor()
        while !Task.isCancelled {
            for line in cursor.poll(path: path) {
                // A line that isn't valid UTF-8 is dropped on its own, never partially decoded; the
                // lines around it are unaffected.
                guard String(data: line, encoding: .utf8) != nil else { continue }
                continuation.yield(line)
            }
            try? await Task.sleep(nanoseconds: intervalNanoseconds)
        }
    }
}
