import Foundation
import Testing

@testable import ArgusSupport

@Suite("CodexRolloutLocator")
struct CodexRolloutLocatorTests {
    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }

    @Test("a single day returns just today's directory")
    func singleDay() {
        let now = date("2026-09-30T12:00:00Z")
        let dirs = CodexRolloutLocator.dayDirectories(
            base: URL(fileURLWithPath: "/base"), days: 1, now: now, calendar: Self.utcCalendar)
        #expect(dirs == [URL(fileURLWithPath: "/base/2026/09/30")])
    }

    @Test("days are returned oldest first")
    func oldestFirst() {
        let now = date("2026-09-30T12:00:00Z")
        let dirs = CodexRolloutLocator.dayDirectories(
            base: URL(fileURLWithPath: "/base"), days: 3, now: now, calendar: Self.utcCalendar)
        #expect(
            dirs == [
                URL(fileURLWithPath: "/base/2026/09/28"),
                URL(fileURLWithPath: "/base/2026/09/29"),
                URL(fileURLWithPath: "/base/2026/09/30"),
            ])
    }

    @Test("a lookback window crosses a month boundary correctly")
    func crossesMonthBoundary() {
        let now = date("2026-10-02T00:00:00Z")
        let dirs = CodexRolloutLocator.dayDirectories(
            base: URL(fileURLWithPath: "/base"), days: 4, now: now, calendar: Self.utcCalendar)
        #expect(
            dirs == [
                URL(fileURLWithPath: "/base/2026/09/29"),
                URL(fileURLWithPath: "/base/2026/09/30"),
                URL(fileURLWithPath: "/base/2026/10/01"),
                URL(fileURLWithPath: "/base/2026/10/02"),
            ])
    }

    @Test("a lookback window crosses a year boundary correctly")
    func crossesYearBoundary() {
        let now = date("2027-01-01T00:00:00Z")
        let dirs = CodexRolloutLocator.dayDirectories(
            base: URL(fileURLWithPath: "/base"), days: 2, now: now, calendar: Self.utcCalendar)
        #expect(
            dirs == [
                URL(fileURLWithPath: "/base/2026/12/31"),
                URL(fileURLWithPath: "/base/2027/01/01"),
            ])
    }

    @Test("month and day are zero-padded to two digits")
    func zeroPadded() {
        let now = date("2026-01-05T00:00:00Z")
        let dirs = CodexRolloutLocator.dayDirectories(
            base: URL(fileURLWithPath: "/base"), days: 1, now: now, calendar: Self.utcCalendar)
        #expect(dirs == [URL(fileURLWithPath: "/base/2026/01/05")])
    }

    @Test("zero or fewer days returns no directories")
    func zeroDaysReturnsEmpty() {
        let now = date("2026-09-30T00:00:00Z")
        #expect(
            CodexRolloutLocator.dayDirectories(
                base: URL(fileURLWithPath: "/base"), days: 0, now: now, calendar: Self.utcCalendar
            ).isEmpty)
    }

    private func date(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        guard let value = formatter.date(from: iso) else {
            Issue.record("failed to parse fixture date \(iso)")
            return Date(timeIntervalSince1970: 0)
        }
        return value
    }
}
