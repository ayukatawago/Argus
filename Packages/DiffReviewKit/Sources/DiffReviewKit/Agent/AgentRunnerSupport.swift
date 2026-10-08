import Foundation

/// One-shot "the process exited" latch, usable whether the exit happens before or after `wait()`.
final class ExitSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var status: Int32?
    private var continuation: CheckedContinuation<Int32, Never>?

    func fulfill(_ newStatus: Int32) {
        lock.lock()
        status = newStatus
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: newStatus)
    }

    func wait() async -> Int32 {
        await withCheckedContinuation { (waiter: CheckedContinuation<Int32, Never>) in
            lock.lock()
            if let status {
                lock.unlock()
                waiter.resume(returning: status)
            } else {
                continuation = waiter
                lock.unlock()
            }
        }
    }
}

/// Thread-safe, size-capped stderr buffer (keeps the newest bytes).
final class StderrCapture: @unchecked Sendable {
    private static let limit = 16_384
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        data.append(chunk)
        if data.count > Self.limit { data = data.suffix(Self.limit) }
        lock.unlock()
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum PipeDrain {
    /// Reads whatever is immediately available without blocking (a grandchild that kept the write
    /// end open must not be able to hang the caller).
    static func nonBlocking(_ handle: FileHandle) -> Data {
        let descriptor = handle.fileDescriptor
        let flags = fcntl(descriptor, F_GETFL)
        guard flags != -1 else { return Data() }
        _ = fcntl(descriptor, F_SETFL, flags | O_NONBLOCK)
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 16384)
        while true {
            let bytesRead = buffer.withUnsafeMutableBytes { read(descriptor, $0.baseAddress, $0.count) }
            guard bytesRead > 0 else { break }
            result.append(buffer, count: bytesRead)
        }
        return result
    }
}

/// `Process` can't place its child in a new process group, so cancellation walks the child's
/// descendant tree instead: terminating only the login shell would orphan the `claude`/`codex`
/// process (and anything it spawned) it started.
enum ProcessTree {
    static func terminate(_ process: Process) {
        let pid = process.processIdentifier
        // Collect before signalling: once the parent dies, its children are reparented to launchd.
        let descendants = descendantPIDs(of: pid)
        if process.isRunning { process.terminate() }
        for child in descendants.reversed() { kill(child, SIGTERM) }
    }

    static func descendantPIDs(of root: pid_t) -> [pid_t] {
        var result: [pid_t] = []
        var queue: [pid_t] = [root]
        while let current = queue.popLast() {
            for child in childPIDs(of: current) where !result.contains(child) {
                result.append(child)
                queue.append(child)
            }
        }
        return result
    }

    private static func childPIDs(of parent: pid_t) -> [pid_t] {
        var buffer = [pid_t](repeating: 0, count: 256)
        let size = Int32(buffer.count * MemoryLayout<pid_t>.stride)
        let count = proc_listchildpids(parent, &buffer, size)
        guard count > 0 else { return [] }
        return Array(buffer.prefix(min(Int(count), buffer.count)))
    }
}

/// Best-effort parsing of each agent's streamed stdout into `AgentEvent`s. Both CLIs' line-delimited
/// JSON schemas are treated leniently — unrecognized shapes fall back to raw text rather than
/// dropping output, since the exact schema (especially Codex's) may vary across CLI versions.
struct StreamingOutputParser {
    let kind: DiffReviewAgent.Kind
    /// Claude emits each assistant message as it streams and then repeats the whole reply in the
    /// final `result` line; once any assistant text was seen, `result` must not be emitted again.
    private var sawAssistantText = false

    init(kind: DiffReviewAgent.Kind) {
        self.kind = kind
    }

    mutating func consumeLine(_ line: String) -> [AgentEvent] {
        guard !line.isEmpty else { return [] }
        switch kind {
        case .claude: return parseClaudeLine(line)
        case .codex: return parseCodexLine(line)
        }
    }

    // MARK: - Claude `--output-format stream-json`

    private mutating func parseClaudeLine(_ line: String) -> [AgentEvent] {
        guard let object = Self.jsonObject(from: line) else { return [.text(line)] }

        var events: [AgentEvent] = []
        if let sessionID = object["session_id"] as? String {
            events.append(.sessionID(sessionID))
        }

        switch object["type"] as? String {
        case "assistant":
            if let message = object["message"] as? [String: Any],
                let content = message["content"] as? [[String: Any]]
            {
                for block in content where block["type"] as? String == "text" {
                    if let text = block["text"] as? String {
                        sawAssistantText = true
                        events.append(.text(text))
                    }
                }
            }

        case "result":
            if !sawAssistantText, let text = object["result"] as? String {
                events.append(.text(text))
            }

        default:
            break
        }

        return events
    }

    // MARK: - Codex `exec --json`

    private func parseCodexLine(_ line: String) -> [AgentEvent] {
        guard let object = Self.jsonObject(from: line) else { return [.text(line)] }

        var events: [AgentEvent] = []
        if let sessionID = (object["session_id"] ?? object["conversation_id"] ?? object["thread_id"]) as? String {
            events.append(.sessionID(sessionID))
        }
        if let text = (object["text"] ?? object["message"] ?? object["content"]) as? String {
            events.append(.text(text))
        } else if let item = object["item"] as? [String: Any], let text = item["text"] as? String,
            // `item.completed` also carries reasoning / command items; only the agent's message is the reply.
            [nil, "agent_message", "assistant_message"].contains(item["type"] as? String)
        {
            events.append(.text(text))
        }
        return events
    }

    private static func jsonObject(from line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
