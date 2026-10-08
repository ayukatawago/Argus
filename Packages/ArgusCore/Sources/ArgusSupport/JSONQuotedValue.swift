import Foundation

/// Cheap `"key":"value"` extraction from raw JSON text, for the cases where full parsing is
/// impractical (a ~22 KB `session_meta` line read through a fixed-size header window would be
/// truncated mid-JSON) or wasteful (a hot polling path).
///
/// The value is decoded per JSON string rules — `\"`, `\\`, `\/`, `\n`, `\t`, `\uXXXX` and so on —
/// so a path or timestamp containing an escaped quote is neither cut short nor returned with its
/// backslashes still in it. POSIX paths *can* contain `"`; macOS ones merely rarely do.
public enum JSONQuotedValue {
    /// Returns the decoded string value of the first `"key":"…"` in `text`, or `nil` when the key
    /// is absent, its value is empty, or the closing quote isn't within `text` (a truncated window).
    public static func first(forKey key: String, in text: some StringProtocol) -> String? {
        guard let keyRange = text.range(of: "\"\(key)\":\"") else { return nil }
        return decodeString(startingAt: keyRange.upperBound, in: text)
    }

    /// Number of times the unescaped `"key":"` marker occurs in `text`. An occurrence inside a JSON
    /// string value is written `\"key\":\"` and so never matches.
    public static func occurrences(ofKey key: String, in text: some StringProtocol) -> Int {
        var count = 0
        var searchStart = text.startIndex
        let marker = "\"\(key)\":\""
        while let range = text.range(of: marker, range: searchStart..<text.endIndex) {
            count += 1
            searchStart = range.upperBound
        }
        return count
    }

    private static func decodeString(startingAt start: String.Index, in text: some StringProtocol) -> String? {
        var result = ""
        var index = start
        while index < text.endIndex {
            let char = text[index]
            index = text.index(after: index)
            if char == "\"" { return result.isEmpty ? nil : result }
            guard char == "\\" else {
                result.append(char)
                continue
            }
            guard index < text.endIndex else { return nil }
            let escaped = text[index]
            index = text.index(after: index)
            guard let decoded = decodeEscape(escaped, in: text, at: &index) else { return nil }
            result.unicodeScalars.append(contentsOf: decoded.unicodeScalars)
        }
        return nil
    }

    /// Decodes one escape sequence whose introducing character (the one after the backslash) is
    /// `escaped`; `index` is already past it, and is advanced past any `XXXX` hex digits for `\u`.
    private static func decodeEscape(
        _ escaped: Character, in text: some StringProtocol, at index: inout String.Index
    ) -> String? {
        switch escaped {
        case "n": return "\n"
        case "t": return "\t"
        case "r": return "\r"
        case "b": return "\u{8}"
        case "f": return "\u{C}"
        case "u": return decodeUnicodeEscape(in: text, at: &index).map { String(Character($0)) }
        default: return String(escaped)
        }
    }

    /// Decodes `XXXX` (and a following `\uXXXX` low surrogate when the first is a high surrogate).
    private static func decodeUnicodeEscape(
        in text: some StringProtocol, at index: inout String.Index
    ) -> Unicode.Scalar? {
        guard let high = hexUnit(in: text, at: &index) else { return nil }
        if (0xD800...0xDBFF).contains(high) {
            var lookahead = index
            guard lookahead < text.endIndex, text[lookahead] == "\\" else { return nil }
            lookahead = text.index(after: lookahead)
            guard lookahead < text.endIndex, text[lookahead] == "u" else { return nil }
            lookahead = text.index(after: lookahead)
            guard let low = hexUnit(in: text, at: &lookahead), (0xDC00...0xDFFF).contains(low) else { return nil }
            index = lookahead
            return Unicode.Scalar(0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00))
        }
        return Unicode.Scalar(high)
    }

    private static func hexUnit(in text: some StringProtocol, at index: inout String.Index) -> UInt32? {
        var value: UInt32 = 0
        for _ in 0..<4 {
            guard index < text.endIndex, let digit = text[index].hexDigitValue else { return nil }
            value = value << 4 | UInt32(digit)
            index = text.index(after: index)
        }
        return value
    }
}
