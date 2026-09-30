import ArgusConfigKit
import ArgusSupport
import Foundation
import Monitors

/// Polls Codex's rollout JSONL files and publishes today's per-model token usage for the
/// toolbar's usage chip. Modeled on `DiskMonitorStore` (poll-and-publish) and
/// `CodexSessionWatcher` (nonisolated static scan over `PollState`, off the main actor).
@MainActor
final class CodexUsageStore: ObservableObject {
    static let shared = CodexUsageStore()

    @Published private(set) var today: [String: CodexTokenUsage] = [:]
    /// Sorted union of every model name seen across the scan window, independent of `today` —
    /// feeds the Settings → Usage page's row list so a model used only yesterday still gets a
    /// price row today.
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
                let seconds = await ArgusConfigStore.shared.config.codexUsage.refreshIntervalSeconds
                return UInt64(max(1, seconds) * 1_000_000_000)
            },
            action: { [weak self] in
                let window = await ArgusConfigStore.shared.config.codexUsage.scanDayWindow
                let result = await Self.scanOnce(state: state, scanDayWindow: window)
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

    /// One cached file's last-seen (mtime, size) and its already-parsed per-day totals — a sibling
    /// of `PollState`, not nested inside it, to stay within SwiftLint's one-level type-nesting limit
    /// (same workaround as `AgentDisplayPatternOverrides`/`AgentDisplayPatterns` in ArgusConfigKit).
    private struct CacheEntry {
        let mtime: Date
        let size: UInt64
        let byDay: [Date: [String: CodexTokenUsage]]
    }

    /// Cross-poll mutable state, threaded through `scanOnce` by `PollingTask`'s action closure
    /// rather than captured `var`s in a loop — same rationale as `CodexSessionWatcher.PollState`:
    /// `PollingTask` calls the action strictly sequentially, so plain mutation here needs no lock.
    private final class PollState: @unchecked Sendable {
        var cache: [URL: CacheEntry] = [:]
    }

    private struct ScanResult {
        let today: [String: CodexTokenUsage]
        let detectedModels: [String]
    }

    private nonisolated static func scanOnce(state: PollState, scanDayWindow: Int) async -> ScanResult {
        let now = Date()
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        let home = FileManager.default.homeDirectoryForCurrentUser
        let base = home.appendingPathComponent(".codex/sessions")

        let dayDirs = CodexRolloutLocator.dayDirectories(
            base: base, days: max(1, scanDayWindow), now: now, calendar: calendar)
        var files: [URL] = []
        for dir in dayDirs {
            guard
                let contents = try? FileManager.default.contentsOfDirectory(
                    at: dir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])
            else { continue }
            files.append(contentsOf: contents.filter { $0.pathExtension == "jsonl" })
        }
        let fileSet = Set(files)

        // A file untouched since before today's start cannot have contributed any of today's
        // tokens — prune it from the cache so a long lookback window doesn't keep re-checking
        // (mtime, size) on files that can never matter again, and so yesterday's entries fall out
        // on their own at day rollover without any special-cased date-change handling.
        for url in state.cache.keys where !fileSet.contains(url) || isStale(url, before: startOfToday) {
            state.cache.removeValue(forKey: url)
        }

        var byDay: [Date: [String: CodexTokenUsage]] = [:]
        var models: Set<String> = []

        for url in fileSet {
            guard
                let attrs = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                let mtime = attrs.contentModificationDate
            else { continue }
            // Anything not touched since before today's start was already dropped from `state.cache`
            // above and can be skipped outright — it cannot contain a record timestamped today.
            guard mtime >= startOfToday else { continue }
            let size = UInt64(attrs.fileSize ?? 0)

            let parsed: [Date: [String: CodexTokenUsage]]
            if let cached = state.cache[url], cached.mtime == mtime, cached.size == size {
                parsed = cached.byDay
            } else {
                var lines: [String] = []
                if (try? JSONLFileReader.forEachLine(at: url) { lines.append($0) }) == nil {
                    continue
                }
                parsed = CodexUsageParser.scanDaily(
                    lines: lines, fallbackDay: calendar.startOfDay(for: mtime), calendar: calendar)
                state.cache[url] = CacheEntry(mtime: mtime, size: size, byDay: parsed)
            }

            for (day, byModel) in parsed {
                for (model, usage) in byModel {
                    byDay[day, default: [:]][model, default: .zero] += usage
                    models.insert(model)
                }
            }
        }

        return ScanResult(today: byDay[startOfToday] ?? [:], detectedModels: models.sorted())
    }

    private nonisolated static func isStale(_ url: URL, before startOfToday: Date) -> Bool {
        guard
            let attrs = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
            let mtime = attrs.contentModificationDate
        else { return true }
        return mtime < startOfToday
    }
}
