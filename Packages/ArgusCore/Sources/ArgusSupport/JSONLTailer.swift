import Foundation

/// Tails a JSON-Lines file, yielding each newly appended line's UTF-8 bytes as it arrives.
///
/// Replaces the near-identical polling loop duplicated in HookIPC.pollEventLog and
/// ShellStateBus.tailShellEvents: track a byte offset, poll for the file to grow past it, read
/// the new bytes, split on newlines, and reset the offset to zero if the file shrank (log
/// rotation/truncation). Consumers decode each line themselves — this type only knows about
/// bytes and newlines, not JSON.
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
        let url = URL(fileURLWithPath: path)
        var offset: UInt64 = 0

        while !Task.isCancelled {
            guard
                let attrs = try? FileManager.default.attributesOfItem(atPath: path),
                let fileSize = attrs[.size] as? NSNumber
            else {
                offset = 0
                try? await Task.sleep(nanoseconds: intervalNanoseconds)
                continue
            }
            let size = fileSize.uint64Value

            if size < offset { offset = 0 }
            guard size > offset, let handle = try? FileHandle(forReadingFrom: url) else {
                try? await Task.sleep(nanoseconds: intervalNanoseconds)
                continue
            }

            do {
                try handle.seek(toOffset: offset)
                let data = try handle.readToEnd() ?? Data()
                offset = try handle.offset()
                try handle.close()

                // A chunk that isn't valid UTF-8 is dropped whole, not partially decoded — matches
                // the original per-call-site behavior rather than attempting lossy recovery.
                guard let text = String(data: data, encoding: .utf8) else { continue }
                for line in text.split(separator: "\n") {
                    guard let lineData = line.data(using: .utf8) else { continue }
                    continuation.yield(lineData)
                }
            } catch {
                try? handle.close()
            }
            try? await Task.sleep(nanoseconds: intervalNanoseconds)
        }
    }
}
