import Foundation

/// Derives stable tmux session names from a worktree path.
public enum TmuxSessionName {
    /// Example: "argus-a-my-feature-a3f91c"
    ///
    /// The 6-hex-char suffix is FNV-1a over the full path, which is deterministic across process
    /// launches (unlike Swift's randomised `hashValue`) — the same path always yields the same
    /// session name, so a worktree's tmux session survives an Argus relaunch.
    public static func make(type: String, path: String) -> String {
        let last = URL(fileURLWithPath: path).lastPathComponent
        let hash = String(format: "%06x", fnv1a(path) & 0x00FF_FFFF)
        let safe = last.prefix(20).replacingOccurrences(
            of: #"[^a-zA-Z0-9_-]"#, with: "-", options: .regularExpression)
        return "argus-\(type)-\(safe)-\(hash)"
    }

    /// FNV-1a 32-bit hash — fast, deterministic, no seed randomisation.
    private static func fnv1a(_ string: String) -> UInt32 {
        string.utf8.reduce(into: UInt32(2_166_136_261)) { hash, byte in
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
    }
}
