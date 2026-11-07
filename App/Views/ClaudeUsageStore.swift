import ArgusConfigKit
import ArgusSupport
import Foundation
import Monitors

/// Polls Claude Code's transcript JSONL files and publishes today's per-model token usage for the
/// toolbar's Claude usage chip. A sibling of `CodexUsageStore` — same poll-and-cache shape — over
/// `~/.claude/projects/*/*.jsonl` instead of Codex's date-sharded rollouts.
///
/// Counts every transcript that spent tokens today: top-level sessions, `Task`-subagent sidechains
/// (`<session>/subagents/*.jsonl`), and headless diff-review runs. Unlike `ClaudeTranscriptWatcher`
/// (which excludes `sdk-cli` runs so they don't flap the sidebar *state* dot), usage is additive
/// and all of it is real spend.
@MainActor
final class ClaudeUsageStore: ObservableObject {
    static let shared = ClaudeUsageStore()

    @Published private(set) var today: [String: ClaudeTokenUsage] = [:]
    /// Sorted models seen today, feeding Settings → Usage's override rows.
    @Published private(set) var detectedModels: [String] = []
    @Published private(set) var lastScan: Date?

    private var pollTask: Task<Void, Never>?

    private init() {}

    func start() {
        guard pollTask == nil else { return }
        let state = PollState()
        pollTask = PollingTask.repeating(
            order: .actThenSleep,
            interval: {
                let seconds = await ArgusConfigStore.shared.config.claudeUsage.refreshIntervalSeconds
                return ArgusConfig.intervalNanoseconds(seconds, default: 30)
            },
            action: { [weak self] in
                let result = await Self.scanOnce(state: state)
                await MainActor.run {
                    guard let self else { return }
                    self.today = result.today
                    self.detectedModels = result.detectedModels
                    self.lastScan = Date()
                }
            }
        )
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - Scanning

    /// One cached file's last-seen (mtime, size) and its already-parsed records — a sibling of
    /// `PollState`, not nested in it, for SwiftLint's one-level type-nesting limit.
    private struct CacheEntry {
        let mtime: Date
        let size: UInt64
        let records: [ClaudeUsageRecord]
    }

    /// Cross-poll mutable state; `PollingTask` calls the action strictly sequentially, so plain
    /// mutation needs no lock (same rationale as `CodexUsageStore.PollState`).
    private final class PollState: @unchecked Sendable {
        var cache: [URL: CacheEntry] = [:]
    }

    private struct ScanResult {
        let today: [String: ClaudeTokenUsage]
        let detectedModels: [String]
    }

    private nonisolated static func scanOnce(state: PollState) async -> ScanResult {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")

        // Only a file touched today can hold a record timestamped today (Claude Code appends, and
        // a resumed session keeps appending to its own file), so everything older is skipped here
        // and pruned from the cache below — yesterday's entries fall out at day rollover on their own.
        let files = candidateFiles(base: base, since: startOfToday)
        state.cache = state.cache.filter { files[$0.key] != nil }

        var batches: [[ClaudeUsageRecord]] = []
        for (url, mtime) in files.sorted(by: { $0.key.path < $1.key.path }) {
            let size = UInt64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            if let cached = state.cache[url], cached.mtime == mtime, cached.size == size {
                batches.append(cached.records)
                continue
            }
            var lines: [String] = []
            guard (try? JSONLFileReader.forEachLine(at: url) { lines.append($0) }) != nil else { continue }
            let records = ClaudeUsageParser.scanRecords(
                lines: lines, fallbackDay: calendar.startOfDay(for: mtime), calendar: calendar)
            state.cache[url] = CacheEntry(mtime: mtime, size: size, records: records)
            batches.append(records)
        }

        let todayUsage = ClaudeUsageParser.aggregate(batches)[startOfToday] ?? [:]
        return ScanResult(today: todayUsage, detectedModels: todayUsage.keys.sorted())
    }

    /// Every `*.jsonl` under `base` modified at or after `since`, with its mtime: each project's
    /// session transcripts plus its sessions' `subagents/` sidechains.
    private nonisolated static func candidateFiles(base: URL, since: Date) -> [URL: Date] {
        let fileManager = FileManager.default
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isDirectoryKey]
        var found: [URL: Date] = [:]

        func collect(from directory: URL) -> [URL] {
            let contents = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)
            return contents ?? []
        }
        func mtime(_ url: URL) -> Date? {
            try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }
        func addIfRecent(_ url: URL) {
            if url.pathExtension == "jsonl", let modified = mtime(url), modified >= since { found[url] = modified }
        }

        for project in collect(from: base) {
            for entry in collect(from: project) {
                if entry.pathExtension == "jsonl" {
                    addIfRecent(entry)
                } else if (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    // A session directory: its sidechains live one level down. The `subagents`
                    // directory's own mtime moves whenever a sidechain file is added, so a stat
                    // here avoids listing every old session's directory on every poll.
                    let subagents = entry.appendingPathComponent("subagents")
                    guard let modified = mtime(subagents), modified >= since else { continue }
                    collect(from: subagents).forEach(addIfRecent)
                }
            }
        }
        return found
    }
}
