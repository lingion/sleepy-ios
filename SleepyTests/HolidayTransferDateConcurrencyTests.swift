import Foundation
import XCTest
@testable import Sleepy

final class HolidayTransferDateConcurrencyTests: XCTestCase {
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

    private func instant(_ value: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: value))
    }

    func testFormattingAndDecodingRemainConsistentAcrossConcurrentCallers() throws {
        let dates = try [
            (instant("2026-12-31T15:59:59Z"), "2026-12-31"),
            (instant("2026-12-31T16:00:00Z"), "2027-01-01"),
            (instant("2028-02-28T16:00:00Z"), "2028-02-29"),
            (instant("2028-02-29T16:00:00Z"), "2028-03-01"),
        ]
        let json = """
        [{"sourceDate":"2028-02-29","targetDate":"2028-03-05","segmentId":"leap"}]
        """
        let failures = Failures()

        DispatchQueue.concurrentPerform(iterations: 16) { index in
            for offset in 0..<8 {
                let (date, expected) = dates[(index + offset) % dates.count]
                if HolidayTransferOps.dayKey(date) != expected {
                    failures.record("Civil day changed for \(expected)")
                }
                let decoded = HolidayTransferOps.decodeTransfers(json)
                guard let entry = decoded.first, decoded.count == 1 else {
                    failures.record("Valid leap-day mapping failed to decode")
                    continue
                }
                if HolidayTransferOps.dayKey(entry.sourceDate) != "2028-02-29" ||
                    HolidayTransferOps.dayKey(entry.targetDate) != "2028-03-05" || entry.segmentId != "leap" {
                    failures.record("Decoded mapping changed during concurrent formatting")
                }
            }
        }

        XCTAssertEqual(failures.snapshot, [])
    }

    func testNonMidnightTransfersUseShanghaiCivilDayAndSourceWeek() throws {
        let source = try instant("2026-09-07T01:15:00Z")
        let target = try instant("2026-09-19T16:30:00Z")
        let transfer = HolidayTransferEntry(sourceDate: source, targetDate: target, segmentId: "holiday")
        let sourceMidnight = try instant("2026-09-06T16:00:00Z")
        let targetLastSecond = try instant("2026-09-20T15:59:59Z")
        XCTAssertEqual(HolidayTransferOps.transferFor(sourceMidnight, [transfer]), transfer)
        XCTAssertEqual(HolidayTransferOps.courseDateForDate(targetLastSecond, [transfer]), source)
        XCTAssertNil(HolidayTransferOps.courseDateForDate(sourceMidnight, [transfer]))

        let odd = CourseEntity(groupId: "odd", tableId: 1, courseName: "单周课", day: 1,
            startNode: 1, step: 2, startWeek: 1, endWeek: 3, type: 1, color: "#FF6750A4", id: 1)
        var fixedSource = odd
        fixedSource.id = 2
        fixedSource.fixedDate = "2026-09-07"
        var fixedTarget = odd
        fixedTarget.id = 3
        fixedTarget.startNode = 3
        fixedTarget.fixedDate = "2026-09-20"
        let rows = [odd, fixedSource, fixedTarget]
        let sourceRows = CourseOccurrences.coursesForDate(sourceMidnight, startDate: "2026-09-07",
            maxWeek: 3, courses: rows, transfers: [transfer])
        let targetRows = CourseOccurrences.coursesForDate(targetLastSecond, startDate: "2026-09-07",
            maxWeek: 3, courses: rows, transfers: [transfer])
        XCTAssertEqual(sourceRows.map(\.id), [2])
        XCTAssertEqual(targetRows.map(\.id), [1, 3])
    }

    func testExclusiveReplacementComparesCivilDaysInsteadOfTimestamps() throws {
        let first = HolidayTransferEntry(sourceDate: try instant("2026-09-07T00:00:00Z"),
            targetDate: try instant("2026-09-20T00:00:00Z"), segmentId: "first")
        let second = HolidayTransferEntry(sourceDate: try instant("2026-09-08T00:00:00Z"),
            targetDate: try instant("2026-09-21T00:00:00Z"), segmentId: "second")
        let replacement = HolidayTransferEntry(sourceDate: try instant("2026-09-07T12:00:00Z"),
            targetDate: try instant("2026-09-21T12:00:00Z"), segmentId: "replacement")

        XCTAssertEqual(HolidayTransferOps.withTargetExclusivity([first, second], replacement), [replacement])
    }
}
