import ArgusSupport
import Foundation

/// One de-duplicated assistant message's usage, already bucketed to a local day. `key` is the
/// `message.id` + `requestId` identity used to de-duplicate, or `nil` when the line carried neither.
public struct ClaudeUsageRecord: Equatable, Sendable {
    public let key: String?
    public let day: Date
    public let model: String
    public let usage: ClaudeTokenUsage
}

/// Parses Claude Code transcript JSONL lines into per-day, per-model token totals.
///
/// Claude Code writes one transcript line per *content block* (thinking, text, tool_use) of an
/// assistant message, and every one of those lines carries the same final `message.usage`. Summing
/// lines naively would count a message's tokens two to four times, so records are de-duplicated by
/// `message.id` + `requestId` — within a file by `scanRecords`, and across files (a resumed or
/// forked session can replay earlier messages into a new transcript) by `aggregate`.
public enum ClaudeUsageParser {
    /// Appended to the model name of a request whose prompt exceeded `longContextThreshold`, so a
    /// tier that is priced per request (not per daily total) survives aggregation into a
    /// per-model bucket. `ClaudeModelRate.defaultRate(forModel:)` understands the suffix.
    public static let longContextSuffix = " (>100K)"
    public static let longContextThreshold = 100_000
    /// Only these models have a prompt-size tier; every other model keeps its plain name.
    static let longContextModelPrefixes = ["claude-haiku-5-5"]

    private struct ParsedLine {
        let key: String?
        let model: String
        let timestamp: String?
        let usage: ClaudeTokenUsage
    }

    /// One file's usage records, de-duplicated within the file (the last line of a message wins) and
    /// in first-seen order.
    /// - Parameters:
    ///   - lines: one transcript file's lines, in file order.
    ///   - fallbackDay: start-of-day for a record whose `timestamp` is missing or unparseable.
    ///   - calendar: decides which timezone's midnight splits days (the user's local one).
    public static func scanRecords(
        lines: some Sequence<String>, fallbackDay: Date, calendar: Calendar
    ) -> [ClaudeUsageRecord] {
        var parsed: [String: ParsedLine] = [:]
        var order: [String] = []

        for (index, line) in lines.enumerated() {
            // Cheap pre-filter before any JSON decoding — most transcript lines carry no usage.
            guard line.contains("\"usage\""), let entry = parseLine(line) else { continue }
            // A line with neither id gets a unique key, so it is counted rather than merged.
            let slot = entry.key ?? "line-\(index)"
            if parsed[slot] == nil { order.append(slot) }
            parsed[slot] = entry
        }

        return order.compactMap { slot in
            guard let entry = parsed[slot] else { return nil }
            let day = calendar.startOfDay(for: entry.timestamp.flatMap(ISO8601Timestamp.parse) ?? fallbackDay)
            return ClaudeUsageRecord(key: entry.key, day: day, model: entry.model, usage: entry.usage)
        }
    }

    /// Sums several files' records into day -> model -> usage, counting a record whose `key`
    /// already appeared (in this or an earlier batch) only once. Records without a key always count.
    public static func aggregate(
        _ batches: some Sequence<[ClaudeUsageRecord]>
    ) -> [Date: [String: ClaudeTokenUsage]] {
        var seen: Set<String> = []
        var result: [Date: [String: ClaudeTokenUsage]] = [:]
        for batch in batches {
            for record in batch {
                if let key = record.key, !seen.insert(key).inserted { continue }
                result[record.day, default: [:]][record.model, default: .zero] += record.usage
            }
        }
        return result
    }

    /// Convenience for a single file: `scanRecords` then `aggregate`.
    public static func scanDaily(
        lines: some Sequence<String>, fallbackDay: Date, calendar: Calendar
    ) -> [Date: [String: ClaudeTokenUsage]] {
        aggregate([scanRecords(lines: lines, fallbackDay: fallbackDay, calendar: calendar)])
    }

    private static func parseLine(_ line: String) -> ParsedLine? {
        guard
            let data = line.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            obj["type"] as? String == "assistant",
            let message = obj["message"] as? [String: Any],
            let rawModel = message["model"] as? String,
            // Claude Code's own placeholder entries (e.g. the interrupt marker) carry zeroed usage.
            rawModel != "<synthetic>",
            let rawUsage = message["usage"] as? [String: Any]
        else { return nil }

        let usage = usage(from: rawUsage)
        let messageID = message["id"] as? String
        let requestID = obj["requestId"] as? String
        let key = (messageID == nil && requestID == nil) ? nil : "\(messageID ?? "")|\(requestID ?? "")"
        return ParsedLine(
            key: key, model: taggedModel(rawModel, usage: usage), timestamp: obj["timestamp"] as? String, usage: usage)
    }

    private static func usage(from raw: [String: Any]) -> ClaudeTokenUsage {
        func count(_ dict: [String: Any], _ key: String) -> Int? {
            dict[key].flatMap(CodexUsageParser.tokenCount)
        }
        let totalWrite = count(raw, "cache_creation_input_tokens") ?? 0
        var write5m = totalWrite
        var write1h = 0
        // The 5m/1h split is only present on newer Claude Code versions; without it every written
        // token is billed at the cheaper 5-minute rate rather than guessing at a 1-hour TTL.
        if let split = raw["cache_creation"] as? [String: Any] {
            let split5m = count(split, "ephemeral_5m_input_tokens") ?? 0
            let split1h = count(split, "ephemeral_1h_input_tokens") ?? 0
            if split5m + split1h > 0 {
                write5m = split5m
                write1h = split1h
            }
        }
        return ClaudeTokenUsage(
            inputTokens: count(raw, "input_tokens") ?? 0,
            cacheWrite5mTokens: write5m,
            cacheWrite1hTokens: write1h,
            cacheReadTokens: count(raw, "cache_read_input_tokens") ?? 0,
            outputTokens: count(raw, "output_tokens") ?? 0,
            responseCount: 1
        )
    }

    private static func taggedModel(_ model: String, usage: ClaudeTokenUsage) -> String {
        guard
            usage.promptTokens > longContextThreshold,
            longContextModelPrefixes.contains(where: { model.hasPrefix($0) })
        else { return model }
        return model + longContextSuffix
    }
}
