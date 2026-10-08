import ArgusSupport
import Foundation

/// Parses Codex rollout JSONL lines into per-day, per-model token totals.
///
/// Every API response Codex makes appends a `token_usage_record` line carrying token counts but
/// no model name; the model instead lives on that turn's `turn_context` line, which always
/// precedes its records in file order in every rollout observed locally. Rather than relying on
/// that ordering, this does a single pass collecting both, then joins by `turn_id` (falling back
/// to `root_turn_id`, then `unknownModel`) once the whole input has been seen — correct regardless
/// of line order, at the cost of buffering one file's records in memory.
public enum CodexUsageParser {
    /// Bucket used for a usage record whose turn has no matching `turn_context` line. Never
    /// observed locally (every record resolved to a model across two days of real rollouts), but
    /// tokens land here rather than being silently dropped so a day's total stays honest even if a
    /// future Codex version omits it.
    public static let unknownModel = "unknown"

    private struct BufferedRecord {
        let turnID: String?
        let rootTurnID: String?
        let timestamp: String?
        let usage: [String: Int]
    }

    /// - Parameters:
    ///   - lines: one rollout file's lines, in file order.
    ///   - fallbackDay: start-of-day to bucket a record whose `timestamp` is missing or
    ///     unparseable under. Callers pass the file's own mtime day, keeping this function itself
    ///     free of any dependency on the current date.
    ///   - calendar: used only for `startOfDay(for:)`, so callers control which timezone "today"
    ///     means (Codex's timestamps are UTC; the day boundary that matters is the user's local one).
    /// - Returns: day -> model name -> accumulated usage.
    public static func scanDaily(
        lines: some Sequence<String>, fallbackDay: Date, calendar: Calendar
    ) -> [Date: [String: CodexTokenUsage]] {
        var turnModels: [String: String] = [:]
        var records: [BufferedRecord] = []

        for line in lines {
            // Cheap pre-filter before any JSON decoding — most lines in a rollout are unrelated
            // response/reasoning content, and a substring `contains` check is far cheaper than a
            // failed JSONSerialization parse for each of them.
            if line.contains("\"turn_context\"") {
                if let (turnID, model) = parseTurnContext(line) {
                    turnModels[turnID] = model
                }
            } else if line.contains("\"token_usage_record\"") {
                if let record = parseUsageRecord(line) {
                    records.append(record)
                }
            }
        }

        var result: [Date: [String: CodexTokenUsage]] = [:]
        for record in records {
            let model =
                record.turnID.flatMap { turnModels[$0] }
                ?? record.rootTurnID.flatMap { turnModels[$0] }
                ?? unknownModel
            let day = calendar.startOfDay(
                for: record.timestamp.flatMap(ISO8601Timestamp.parse) ?? fallbackDay)
            result[day, default: [:]][model, default: .zero] += usage(from: record.usage)
        }
        return result
    }

    private static func usage(from raw: [String: Int]) -> CodexTokenUsage {
        CodexTokenUsage(
            inputTokens: raw["input_tokens"] ?? 0,
            cachedInputTokens: raw["cached_input_tokens"] ?? 0,
            cacheWriteInputTokens: raw["cache_write_input_tokens"] ?? 0,
            outputTokens: raw["output_tokens"] ?? 0,
            reasoningOutputTokens: raw["reasoning_output_tokens"] ?? 0,
            totalTokens: raw["total_tokens"] ?? 0,
            responseCount: 1
        )
    }

    private static func parseTurnContext(_ line: String) -> (turnID: String, model: String)? {
        guard
            let data = line.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            obj["type"] as? String == "turn_context",
            let payload = obj["payload"] as? [String: Any],
            let turnID = payload["turn_id"] as? String,
            let model = payload["model"] as? String
        else { return nil }
        return (turnID, model)
    }

    private static func parseUsageRecord(_ line: String) -> BufferedRecord? {
        guard
            let data = line.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            obj["type"] as? String == "token_usage_record",
            let payload = obj["payload"] as? [String: Any],
            let usage = payload["usage"] as? [String: Any]
        else { return nil }
        return BufferedRecord(
            turnID: payload["turn_id"] as? String,
            rootTurnID: payload["root_turn_id"] as? String,
            timestamp: obj["timestamp"] as? String,
            usage: usage.compactMapValues(Self.tokenCount)
        )
    }

    /// A token count is a non-negative whole JSON number that fits in `Int`. `as? Int` alone would
    /// also accept `true` (as 1), silently truncate `1.5`, and turn a number beyond `Int.max` into
    /// nothing at all while accepting negatives — none of which is a real count.
    static func tokenCount(_ value: Any) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        guard double >= 0, double < 9.2e18, double == double.rounded(.towardZero) else { return nil }
        return number.intValue
    }
}
