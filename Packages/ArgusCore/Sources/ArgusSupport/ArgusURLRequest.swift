import Foundation

/// A parsed `argus://<subcommand>?…` request from `script/argus` (or any other `open`-based caller).
///
/// Parsing and validation live here, apart from `AppDelegate`, so the URL scheme — which any local
/// process or web page can invoke — is unit-testable. `argus://capture` in particular makes the app
/// *write a file at a caller-chosen path*, so its `output` is validated here rather than trusted.
/// What an `argus://capture` request records.
public enum CaptureMode: String, Sendable {
    case screenshot
    case video
}

public enum ArgusURLRequest: Equatable, Sendable {
    case diff(workspace: String, base: String, head: String)
    case capture(Capture)

    public struct Capture: Equatable, Sendable {
        public let mode: CaptureMode
        public let outputPath: String
        public let duration: Double
    }

    public enum Rejection: Error, Equatable, Sendable {
        case unsupportedHost
        case missingWorkspace
        case missingOutput
        case outputNotAbsolute
        case unknownMode
        case badOutputExtension
        case outputTargetNotRegularFile
    }

    /// What currently sits at a path, as far as the capture overwrite check cares.
    public enum ItemKind: Sendable {
        case missing
        case regularFile
        case other  // directory, symlink, device, …
    }

    /// Output extensions a capture may write, by mode.
    static let allowedExtensions: [CaptureMode: Set<String>] = [.screenshot: ["png"], .video: ["mov", "mp4"]]
    public static let defaultCaptureDuration = 10.0
    public static let maxCaptureDuration = 300.0

    /// Parses `url`. `itemKind` reports what exists at a path (without following symlinks); it is
    /// injectable so the overwrite rule can be tested without touching the real file system.
    public static func parse(
        _ url: URL,
        itemKind: (String) -> ItemKind = ArgusURLRequest.fileSystemItemKind
    ) -> Result<ArgusURLRequest, Rejection> {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first(where: { $0.name == name })?.value }

        switch url.host {
        case "diff":
            guard let workspace = value("workspace"), !workspace.isEmpty else { return .failure(.missingWorkspace) }
            return .success(.diff(workspace: workspace, base: value("from") ?? "", head: value("to") ?? "HEAD"))

        case "capture":
            return parseCapture(value: value, itemKind: itemKind).map(ArgusURLRequest.capture)

        default:
            return .failure(.unsupportedHost)
        }
    }

    private static func parseCapture(
        value: (String) -> String?, itemKind: (String) -> ItemKind
    ) -> Result<Capture, Rejection> {
        guard let rawOutput = value("output"), !rawOutput.isEmpty else { return .failure(.missingOutput) }
        guard rawOutput.hasPrefix("/"), !rawOutput.contains("\0") else { return .failure(.outputNotAbsolute) }
        guard let mode = value("mode").flatMap(CaptureMode.init(rawValue:)) else { return .failure(.unknownMode) }

        let output = (rawOutput as NSString).standardizingPath
        let ext = (output as NSString).pathExtension.lowercased()
        guard allowedExtensions[mode]?.contains(ext) == true else { return .failure(.badOutputExtension) }
        // Overwriting is allowed only for a plain file (a previous capture). A symlink, directory or
        // device at the target is refused, so this can't be aimed at something that isn't ours.
        guard itemKind(output) != .other else { return .failure(.outputTargetNotRegularFile) }

        let requested = value("duration").flatMap(Double.init) ?? defaultCaptureDuration
        let duration = requested.isFinite && requested > 0 ? min(requested, maxCaptureDuration) : defaultCaptureDuration
        return .success(Capture(mode: mode, outputPath: output, duration: duration))
    }

    /// `lstat`-style: a symlink reports as `.other`, never as the file it points to.
    public static func fileSystemItemKind(_ path: String) -> ItemKind {
        guard let type = (try? FileManager.default.attributesOfItem(atPath: path))?[.type] as? FileAttributeType else {
            return .missing
        }
        return type == .typeRegular ? .regularFile : .other
    }
}
