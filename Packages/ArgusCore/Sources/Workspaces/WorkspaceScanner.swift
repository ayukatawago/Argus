import CoreServices
import Foundation

final class WorkspaceScanner: @unchecked Sendable {
    var onChange: (() -> Void)?
    private var streamRef: FSEventStreamRef?

    func start(paths: [String]) {
        stop()
        guard !paths.isEmpty else { return }
        var ctx = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer)
        let stream = FSEventStreamCreate(
            nil,
            { _, info, _, _, _, _ in
                guard let info else { return }
                let scanner = Unmanaged<WorkspaceScanner>.fromOpaque(info).takeUnretainedValue()
                DispatchQueue.main.async { scanner.onChange?() }
            },
            &ctx,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            2.0,
            flags
        )
        guard let stream else { return }
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
        streamRef = stream
    }

    func stop() {
        guard let stream = streamRef else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        streamRef = nil
    }

    deinit { stop() }
}
