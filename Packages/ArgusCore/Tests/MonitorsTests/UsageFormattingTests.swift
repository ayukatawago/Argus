import Testing

@testable import Monitors

@Suite("TokenCountFormatter")
struct TokenCountFormatterTests {
    @Test("counts below 1,000 render as plain integers")
    func belowThousand() {
        #expect(TokenCountFormatter.short(0) == "0")
        #expect(TokenCountFormatter.short(999) == "999")
    }

    @Test("thousands render with a K suffix")
    func thousands() {
        #expect(TokenCountFormatter.short(1_000) == "1.00K")
        #expect(TokenCountFormatter.short(12_345) == "12.3K")
        #expect(TokenCountFormatter.short(999_999) == "1000.0K")
    }

    @Test("millions render with an M suffix")
    func millions() {
        #expect(TokenCountFormatter.short(1_000_000) == "1.00M")
        #expect(TokenCountFormatter.short(85_600_000) == "85.6M")
    }

    @Test("billions render with a B suffix")
    func billions() {
        #expect(TokenCountFormatter.short(1_240_000_000) == "1.24B")
    }
}

@Suite("CostFormatter")
struct CostFormatterTests {
    @Test("nil renders as an em dash")
    func nilRendersAsEmDash() {
        #expect(CostFormatter.usd(nil) == "—")
    }

    @Test("zero renders as $0.00")
    func zeroRendersAsZero() {
        #expect(CostFormatter.usd(0) == "$0.00")
    }

    @Test("a nonzero sub-cent amount renders as <$0.01 rather than rounding to $0.00")
    func subCentAmount() {
        #expect(CostFormatter.usd(0.004) == "<$0.01")
    }

    @Test("an ordinary amount rounds to two decimal places")
    func ordinaryAmount() {
        #expect(CostFormatter.usd(18.4) == "$18.40")
        #expect(CostFormatter.usd(18.426) == "$18.43")
    }
}
