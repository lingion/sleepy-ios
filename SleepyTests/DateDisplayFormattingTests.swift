import Foundation
import XCTest
@testable import Sleepy

final class DateDisplayFormattingTests: XCTestCase {
    private final class Failures: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [String] = []

        func record(_ value: String) {
            lock.lock()
            defer { lock.unlock() }
            values.append(value)
        }

        var snapshot: [String] {
            lock.lock()
            defer { lock.unlock() }
            return values
        }
    }

    private func fixtures() throws -> [(date: Date, short: String, full: String)] {
        let parser = ISO8601DateFormatter()
        return try [
            (XCTUnwrap(parser.date(from: "2026-12-31T15:59:59Z")), "12-31", "2026-12-31"),
            (XCTUnwrap(parser.date(from: "2026-12-31T16:00:00Z")), "01-01", "2027-01-01"),
            (XCTUnwrap(parser.date(from: "2028-02-28T16:00:00Z")), "02-29", "2028-02-29"),
            (XCTUnwrap(parser.date(from: "2028-02-29T15:59:59Z")), "02-29", "2028-02-29"),
            (XCTUnwrap(parser.date(from: "2028-02-29T16:00:00Z")), "03-01", "2028-03-01"),
        ]
    }

    func testDisplayFormatsPreserveShanghaiCivilDayAndLeadingZeros() throws {
        for item in try fixtures() {
            XCTAssertEqual(DateUtils.shortDate(item.date), item.short)
            XCTAssertEqual(DateUtils.fullDate(item.date), item.full)
        }
    }

    func testRepeatedAndAlternatingCallsKeepTheirOwnFormat() throws {
        for item in try fixtures() {
            for _ in 0..<64 {
                XCTAssertEqual(DateUtils.shortDate(item.date), item.short)
            }
            for _ in 0..<64 {
                XCTAssertEqual(DateUtils.fullDate(item.date), item.full)
            }
            for _ in 0..<64 {
                XCTAssertEqual(DateUtils.shortDate(item.date), item.short)
                XCTAssertEqual(DateUtils.fullDate(item.date), item.full)
            }
        }
    }

    func testConcurrentShortAndFullFormattingNeverMixFormats() throws {
        let dates = try fixtures()
        let failures = Failures()

        DispatchQueue.concurrentPerform(iterations: 16) { worker in
            for offset in 0..<500 {
                let item = dates[(worker + offset) % dates.count]
                let actualShort = DateUtils.shortDate(item.date)
                let actualFull = DateUtils.fullDate(item.date)
                if actualShort != item.short {
                    failures.record("Short date \(actualShort) != \(item.short)")
                }
                if actualFull != item.full {
                    failures.record("Full date \(actualFull) != \(item.full)")
                }
            }
        }

        XCTAssertEqual(failures.snapshot, [])
    }
}
