import AppKit
import AVFoundation
import ScreenCaptureKit

/// Handles `argus://capture` requests (from `script/argus`'s `capture screenshot`/`capture video`)
/// by grabbing Argus's own main window via ScreenCaptureKit — the real on-screen composited pixels,
/// including the Metal-backed ghostty terminal surfaces, which an `NSView`-level re-render
/// (`cacheDisplay(in:to:)`) would not capture correctly.
///
/// Requires the user to have granted Argus Screen Recording permission once; like the per-folder
/// grants noted in CLAUDE.md, this persists across rebuilds under the stable `Argus Local Dev`
/// debug code-signing identity.
///
/// Both entry points are fire-and-forget from the caller's perspective: the CLI doesn't get a
/// return value over the `argus://` URL round trip, so success/failure is reported by writing the
/// requested output path (or an `<output>.error` sidecar) to disk, which the CLI polls for.
@MainActor
final class ScreenCaptureController {
    static let shared = ScreenCaptureController()

    private init() {}

    func captureScreenshot(outputPath: String) async {
        do {
            let target = try await resolveCaptureTarget()
            let config = SCStreamConfiguration()
            config.width = target.pixelWidth
            config.height = target.pixelHeight
            config.showsCursor = false

            let filter = SCContentFilter(desktopIndependentWindow: target.scWindow)
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            try writeImage(image, to: outputPath)
        } catch {
            writeError(error, for: outputPath)
        }
    }

    func captureVideo(outputPath: String, duration: TimeInterval) async {
        let tempPath = outputPath + ".tmp"
        do {
            let target = try await resolveCaptureTarget()
            try? FileManager.default.removeItem(atPath: tempPath)
            let session = try VideoCaptureSession(
                outputPath: tempPath,
                width: target.pixelWidth,
                height: target.pixelHeight
            )

            let config = SCStreamConfiguration()
            config.width = target.pixelWidth
            config.height = target.pixelHeight
            config.showsCursor = false
            config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.queueDepth = 6

            let filter = SCContentFilter(desktopIndependentWindow: target.scWindow)
            let stream = SCStream(filter: filter, configuration: config, delegate: session)
            try stream.addStreamOutput(session, type: .screen, sampleHandlerQueue: session.queue)

            try await stream.startCapture()
            try await Task.sleep(nanoseconds: UInt64(max(duration, 0.1) * 1_000_000_000))
            try await stream.stopCapture()
            try await session.finish()

            try moveIntoPlace(from: tempPath, to: outputPath)
        } catch {
            try? FileManager.default.removeItem(atPath: tempPath)
            writeError(error, for: outputPath)
        }
    }

    // MARK: - Target resolution

    private struct CaptureTarget {
        let scWindow: SCWindow
        let pixelWidth: Int
        let pixelHeight: Int
    }

    /// Prefers the main "Argus" window over `NSPanel`s (popups) and other scenes (e.g. Settings) —
    /// same filter `applicationShouldHandleReopen` in `ArgusApp.swift` uses to pick "the" window.
    private func mainArgusWindow() -> NSWindow? {
        NSApp.windows.first(where: { $0.isVisible && !($0 is NSPanel) && $0.title == "Argus" })
            ?? NSApp.windows.first(where: { $0.isVisible && !($0 is NSPanel) })
    }

    private func resolveCaptureTarget() async throws -> CaptureTarget {
        guard let nsWindow = mainArgusWindow() else { throw CaptureError.windowNotFound }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        let windowID = CGWindowID(nsWindow.windowNumber)
        guard let scWindow = content.windows.first(where: { $0.windowID == windowID }) else {
            throw CaptureError.windowNotFound
        }

        let scale = nsWindow.backingScaleFactor
        return CaptureTarget(
            scWindow: scWindow,
            pixelWidth: evenPixelCount(nsWindow.frame.width, scale: scale),
            pixelHeight: evenPixelCount(nsWindow.frame.height, scale: scale)
        )
    }

    /// H.264 rejects odd frame dimensions.
    private func evenPixelCount(_ points: CGFloat, scale: CGFloat) -> Int {
        let pixels = Int((points * scale).rounded())
        return pixels.isMultiple(of: 2) ? pixels : pixels + 1
    }

    // MARK: - Output

    private func writeImage(_ image: CGImage, to outputPath: String) throws {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw CaptureError.encodingFailed
        }
        let tempPath = outputPath + ".tmp"
        try data.write(to: URL(fileURLWithPath: tempPath))
        try moveIntoPlace(from: tempPath, to: outputPath)
    }

    /// Writes to a `.tmp` sibling first and renames into place, so the CLI's poll loop (which
    /// only checks for `outputPath`'s existence) never observes a partially-written file.
    private func moveIntoPlace(from tempPath: String, to outputPath: String) throws {
        let fileManager = FileManager.default
        try? fileManager.removeItem(atPath: outputPath)
        try fileManager.moveItem(atPath: tempPath, toPath: outputPath)
    }

    private func writeError(_ error: Error, for outputPath: String) {
        let message = (error as? CaptureError)?.message ?? error.localizedDescription
        try? message.write(toFile: outputPath + ".error", atomically: true, encoding: .utf8)
    }
}

private enum CaptureError: Error {
    case windowNotFound
    case encodingFailed
    case noFramesCaptured

    var message: String {
        switch self {
        case .windowNotFound:
            return "couldn't find Argus's main window to capture"

        case .encodingFailed:
            return "failed to encode the captured image"

        case .noFramesCaptured:
            return "no video frames were captured — check Argus has Screen Recording permission"
        }
    }
}

/// Buffers ScreenCaptureKit frames into an `AVAssetWriter`-backed `.mov` file. A plain
/// (non-actor) `NSObject` because `SCStreamOutput`'s callback arrives on `queue`, off the main
/// actor — hopping back to `@MainActor` per frame at 30fps would add needless overhead, and
/// nothing here touches AppKit/UI state.
private final class VideoCaptureSession: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "com.argus.capture.video")

    private let assetWriter: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private var didStartSession = false

    init(outputPath: String, width: Int, height: Int) throws {
        assetWriter = try AVAssetWriter(outputURL: URL(fileURLWithPath: outputPath), fileType: .mov)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ]
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        videoInput.expectsMediaDataInRealTime = true
        adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
        )
        super.init()
        assetWriter.add(videoInput)
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
            let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else { return }

        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if !didStartSession {
            assetWriter.startWriting()
            assetWriter.startSession(atSourceTime: presentationTime)
            didStartSession = true
        }
        guard videoInput.isReadyForMoreMediaData else { return }
        adaptor.append(pixelBuffer, withPresentationTime: presentationTime)
    }

    // Errors surface through `finish()`'s post-hoc check of `assetWriter.status` instead — by the
    // time this fires, `stream(_:didOutputSampleBuffer:of:)` has already stopped being called.
    func stream(_ stream: SCStream, didStopWithError error: Error) {}

    /// Only calls into `assetWriter` if at least one frame started its session — `finishWriting()`
    /// without a prior `startWriting()` is a programmer-error crash (`NSInternalInconsistencyException`),
    /// not a thrown Swift error, which a zero-frame capture (e.g. missing Screen Recording
    /// permission) would otherwise hit.
    func finish() async throws {
        guard didStartSession else { throw CaptureError.noFramesCaptured }
        videoInput.markAsFinished()
        await assetWriter.finishWriting()
        if assetWriter.status == .failed {
            throw assetWriter.error ?? CaptureError.encodingFailed
        }
    }
}
