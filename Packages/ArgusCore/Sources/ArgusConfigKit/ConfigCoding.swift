import Foundation

/// Dynamic string-keyed `CodingKey`, for decoding a container field by field (with per-key defaults)
/// or entry by entry (a user-keyed dictionary) rather than through a synthesized `CodingKeys` enum.
struct RawStringKey: CodingKey {
    let stringValue: String
    init(_ string: String) { self.stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    var intValue: Int? { nil }
    init?(intValue: Int) { nil }
}

/// Decodes to `nil` instead of throwing, so an array of these keeps every well-formed element.
struct LossyElement<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}
