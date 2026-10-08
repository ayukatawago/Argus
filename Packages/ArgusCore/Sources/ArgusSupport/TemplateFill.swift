import Foundation

/// Fills `{{NAME}}` placeholders in a template in a single left-to-right pass over the template.
///
/// Chained `replacingOccurrences` calls re-scan text a previous call inserted, so a value that
/// happens to contain another placeholder (a markdown file that quotes `{{FILE_TREE_JSON}}`) gets
/// substituted into the wrong place. Here an inserted value is never rescanned. Unknown
/// placeholders are left as written.
public enum TemplateFill {
    public static func fill(_ template: String, with values: [String: String]) -> String {
        var output = ""
        var cursor = template.startIndex
        while let open = template.range(of: "{{", range: cursor..<template.endIndex),
            let close = template.range(of: "}}", range: open.upperBound..<template.endIndex)
        {
            output += template[cursor..<open.lowerBound]
            let name = String(template[open.upperBound..<close.lowerBound])
            if let value = values[name] {
                output += value
            } else {
                output += template[open.lowerBound..<close.upperBound]
            }
            cursor = close.upperBound
        }
        output += template[cursor...]
        return output
    }
}
