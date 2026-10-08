import Foundation

/// Parses `du -sk`'s output.
public enum DiskUsageParser {
    /// `du -sk <path>` prints `"<kilobytes>\t<path>\n"`. Returns the size in bytes, or `0` if the
    /// output doesn't start with a parseable integer (e.g. `du` failed to launch, or the path
    /// doesn't exist) — matching the original call site's unconditional-parse-regardless-of-
    /// exit-status behavior.
    public static func bytes(fromDuOutput output: String) -> Int64 {
        let parts = output.components(separatedBy: "\t")
        let kilobytes = Int64(parts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "0") ?? 0
        // A negative or overflowing count (corrupt output) must neither trap nor report negative bytes.
        let (bytes, overflow) = max(0, kilobytes).multipliedReportingOverflow(by: 1_024)
        return overflow ? .max : bytes
    }
}
