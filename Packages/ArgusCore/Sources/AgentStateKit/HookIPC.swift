import ArgusSupport
import Darwin
import Foundation

/// Listens on a Unix-domain socket at a well-known path.
/// Hook scripts (installed by HookInstaller) connect, send one JSON payload, then close.
///
/// @unchecked Sendable: all mutable state is @MainActor-protected; the type is passed
/// into background tasks only as a strong let reference used solely via MainActor.run.
@MainActor
public final class HookIPC: @unchecked Sendable {
    public nonisolated static var socketPath: String {
        "/private/tmp/argus-\(getuid())-hook.sock"
    }

    public nonisolated static var eventLogPath: String {
        "/private/tmp/argus-\(getuid())-hook-events.jsonl"
    }

    public nonisolated static var shellEventLogPath: String {
        "/private/tmp/argus-\(getuid())-shell-events.jsonl"
    }

    public var onPayload: ((HookPayload) -> Void)?
    private var serverTask: Task<Void, Never>?
    private var fileTask: Task<Void, Never>?

    public init() {}

    public func start() {
        try? FileManager.default.removeItem(atPath: Self.socketPath)
        try? FileManager.default.removeItem(atPath: Self.eventLogPath)
        let path = Self.socketPath
        let eventLogPath = Self.eventLogPath
        serverTask = Task.detached(priority: .utility) { [weak self] in
            // Bind to a strong `let` so the inner @Sendable closure captures a non-var reference.
            guard let ipc = self else { return }
            await Self.runServer(socketPath: path) { payload in
                await MainActor.run { ipc.onPayload?(payload) }
            }
        }
        fileTask = Task.detached(priority: .utility) { [weak self] in
            guard let ipc = self else { return }
            await Self.pollEventLog(path: eventLogPath) { payload in
                await MainActor.run { ipc.onPayload?(payload) }
            }
        }
    }

    public func stop() {
        serverTask?.cancel()
        serverTask = nil
        fileTask?.cancel()
        fileTask = nil
        try? FileManager.default.removeItem(atPath: Self.socketPath)
        try? FileManager.default.removeItem(atPath: Self.eventLogPath)
    }

    private nonisolated static func runServer(
        socketPath: String,
        handler: @Sendable @escaping (HookPayload) async -> Void
    ) async {
        let serverFd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFd >= 0 else { return }
        defer { close(serverFd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathCapacity = MemoryLayout.size(ofValue: addr.sun_path)
        socketPath.withCString { src in
            withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: pathCapacity) { dest in
                    _ = strncpy(dest, src, pathCapacity - 1)
                }
            }
        }

        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(serverFd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, listen(serverFd, 8) == 0 else { return }

        while !Task.isCancelled {
            let clientFd = accept(serverFd, nil, nil)
            guard clientFd >= 0 else {
                if errno == EINTR { continue }
                break
            }
            Task.detached {
                defer { close(clientFd) }
                var accumulated = Data()
                var buf = [UInt8](repeating: 0, count: 4_096)
                while true {
                    let bytesRead = buf.withUnsafeMutableBytes { ptr -> Int in
                        guard let base = ptr.baseAddress else { return 0 }
                        return read(clientFd, base, ptr.count)
                    }
                    if bytesRead <= 0 { break }
                    accumulated.append(contentsOf: buf[..<bytesRead])
                }
                guard let payload = try? JSONDecoder().decode(HookPayload.self, from: accumulated) else { return }
                await handler(payload)
            }
        }
    }

    private nonisolated static func pollEventLog(
        path: String,
        handler: @Sendable @escaping (HookPayload) async -> Void
    ) async {
        for await lineData in JSONLTailer(path: path).lines() {
            guard let payload = try? JSONDecoder().decode(HookPayload.self, from: lineData) else { continue }
            await handler(payload)
        }
    }
}
