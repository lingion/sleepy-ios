import XCTest
@testable import Sleepy

final class FixedDateImportExportTests: XCTestCase {
    private let table = TimeTableEntity(name: "秋季", startDate: "2026-09-07", maxWeek: 2, id: 1)
    private func course(_ fixed: String? = "2026-09-07") -> CourseEntity {
        CourseEntity(groupId: "math", tableId: 1, courseName: "数学", day: 1, startNode: 1, step: 2,
                     startWeek: 1, endWeek: 2, color: "#FF6750A4", id: 7, fixedDate: fixed)
    }

    func testNativeTextTwelfthColumnPreservesEmptyAliasPlaceholder() throws {
        let text = SleepyNativeExporter.exportFile(tableName: table.name, startDate: table.startDate, maxWeek: table.maxWeek,
            nodesPerDay: table.nodesPerDay, timeJson: table.timeJson, courses: [course()])
        let line = try XCTUnwrap(text.components(separatedBy: "\n").first { $0.hasPrefix("C数学|") })
        let columns = line.components(separatedBy: "|")
        XCTAssertEqual(columns.count, 12)
        XCTAssertEqual(columns[10], "")
        XCTAssertEqual(columns[11], "2026-09-07")
        let parsed = try SleepyNativeParser.parse(text, defaultTableId: 9, defaultColor: "#FF6750A4")
        XCTAssertEqual(parsed.courses.first?.fixedDate, "2026-09-07")
        XCTAssertEqual(parsed.courses.first?.alias, "")
    }

    func testOldNativeTenAndElevenColumnsRemainRecurring() throws {
        for suffix in ["", "|别名"] {
            let text = "#sleepy-v1\nC数学|1|1-2|1-2||||||\(suffix)"
            let result = try SleepyNativeParser.parse(text, defaultTableId: 1, defaultColor: "#FF6750A4")
            XCTAssertEqual(result.courses.count, 1)
            XCTAssertNil(result.courses.first?.fixedDate)
        }
    }

    func testWakeUpJsonAndShareRoundTripFixedDate() throws {
        for text in [ScheduleExporter.exportWakeUpJson(table, [course()]), ScheduleExporter.exportWakeUpShareText(table, [course()])] {
            let result = try ScheduleParser.parse(text, defaultTableId: 1).get()
            XCTAssertEqual(result.courses.first?.fixedDate, "2026-09-07")
        }
    }

    func testMigrationPackageRoundTripAndMissingFieldCompatibility() throws {
        let snapshot = MigrationDatabaseCodec.DatabaseSnapshot(courses: [MigrationDatabaseCodec.toRow(course())])
        let text = try MigrationDatabaseCodec.encode(snapshot)
        let decoded = try MigrationDatabaseCodec.decode(text)
        XCTAssertEqual(MigrationDatabaseCodec.toEntity(decoded.courses[0]).fixedDate, "2026-09-07")
        let legacy = text.replacingOccurrences(of: "\"fixedDate\":\"2026-09-07\",", with: "")
        XCTAssertNil(try MigrationDatabaseCodec.decode(legacy).courses[0].fixedDate)
    }

    func testFixedIcsHasOneDateQualifiedEventWithoutRecurrence() throws {
        let text = try ScheduleExporter.exportIcsOrThrow(table, [course()])
        XCTAssertEqual(text.components(separatedBy: "BEGIN:VEVENT").count - 1, 1)
        XCTAssertTrue(text.contains("-2026-09-07@sleepy"))
        XCTAssertTrue(text.contains("DTSTART:20260907T080000"))
        XCTAssertFalse(text.contains("RRULE:"))
    }

    func testHolidayIcsExpandsAllDatesIncludingOutsideSemesterTarget() throws {
        let transfer = HolidayTransferEntry(sourceDate: CourseOccurrences.parseDate("2026-09-07")!,
            targetDate: CourseOccurrences.parseDate("2026-09-27")!, segmentId: "holiday")
        let text = try ScheduleExporter.exportIcsOrThrow(table, [course(nil)], transfers: [transfer])
        XCTAssertEqual(text.components(separatedBy: "BEGIN:VEVENT").count - 1, 2)
        XCTAssertFalse(text.contains("DTSTART:20260907"))
        XCTAssertTrue(text.contains("DTSTART:20260914"))
        XCTAssertTrue(text.contains("DTSTART:20260927"))
        XCTAssertTrue(text.contains("-2026-09-14@sleepy"))
        XCTAssertTrue(text.contains("-2026-09-27@sleepy"))
        XCTAssertFalse(text.contains("RRULE:"))
        let legacy = try ScheduleExporter.exportIcsOrThrow(table, [course(nil)])
        XCTAssertTrue(legacy.contains("RRULE:FREQ=WEEKLY"), "无调休的旧重复课程保持兼容")
    }

    func testHolidayIcsRetainsFixedCourseOnSourceAndMovesOnlyRecurringRow() throws {
        var fixed = course(); fixed.id = 8
        let transfer = HolidayTransferEntry(sourceDate: CourseOccurrences.parseDate("2026-09-07")!,
            targetDate: CourseOccurrences.parseDate("2026-09-13")!, segmentId: "holiday")
        let text = try ScheduleExporter.exportIcsOrThrow(table, [fixed, course(nil)], transfers: [transfer])
        XCTAssertEqual(text.components(separatedBy: "BEGIN:VEVENT").count - 1, 3)
        XCTAssertTrue(text.contains("DTSTART:20260907"))
        XCTAssertTrue(text.contains("DTSTART:20260913"))
        XCTAssertFalse(text.contains("RRULE:"))
    }
}
