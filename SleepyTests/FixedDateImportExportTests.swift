import XCTest
@testable import Sleepy

final class FixedDateImportExportTests: XCTestCase {
    private let table = TimeTableEntity(name: "秋季", startDate: "2026-09-07", maxWeek: 2, id: 1)
    private func course(_ fixed: String? = "2026-09-07") -> CourseEntity {
        CourseEntity(groupId: "math", tableId: 1, courseName: "数学", day: 1, startNode: 1, step: 2,
                     startWeek: 1, endWeek: 2, color: "#FF6750A4", id: 7, fixedDate: fixed)
    }

    func testSchoolIdentityRoundTripsNativeFileShareAndWakeUpFormatsUnchanged() throws {
        let identity = #"{ "schemaVersion": 1, "sourceType":"jw","school":{"name":"Ａ校（东区）🍂|砂\n糖","sortKey":"A","type":"qz","url":"https://jw.example.edu/?p=１"} }"#
        let suggestions = #"{"config":{"semesterStartDate":null},"schemaVersion":1}"#
        var original = table
        original.importSourceJson = suggestions
        original.jwSchoolSourceJson = identity
        let files = [
            SleepyNativeExporter.exportFile(tableName: table.name, startDate: table.startDate, maxWeek: table.maxWeek,
                nodesPerDay: table.nodesPerDay, timeJson: table.timeJson, courses: [course()],
                importSourceJson: suggestions, jwSchoolSourceJson: identity),
            SleepyNativeExporter.exportShareText(tableName: table.name, startDate: table.startDate, maxWeek: table.maxWeek,
                nodesPerDay: table.nodesPerDay, timeJson: table.timeJson, courses: [course()],
                importSourceJson: suggestions, jwSchoolSourceJson: identity),
            ScheduleExporter.exportWakeUpJson(original, [course()]),
            ScheduleExporter.exportWakeUpShareText(original, [course()])
        ]
        for text in files {
            let result = try ScheduleParser.parse(text, defaultTableId: 1).get()
            XCTAssertEqual(result.jwSchoolSourceJson, identity)
            XCTAssertEqual(result.importSourceJson, suggestions)
            XCTAssertEqual(result.courses.first?.fixedDate, "2026-09-07")
        }
    }

    func testWakeUpRootSchoolIdentityIsFallbackOnly() throws {
        let root = #"{"name":"X","courses":[],"jwSchoolSourceJson":"ROOT Ａ🍂","tableInfo":{"jwSchoolSourceJson":"NESTED Ｑ"}}"#
        XCTAssertEqual(try ScheduleParser.parse(root, defaultTableId: 1).get().jwSchoolSourceJson, "NESTED Ｑ")
        let fallback = #"{"name":"X","courses":[],"jwSchoolSourceJson":"ROOT Ａ🍂"}"#
        XCTAssertEqual(try ScheduleParser.parse(fallback, defaultTableId: 1).get().jwSchoolSourceJson, "ROOT Ａ🍂")
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

    func testIcsUsesTheMakeupDaysCombinationAndPreservesFixedCourseClock() throws {
        let period = PeriodTableEntity(name: "Autumn", nodesPerDay: 2,
            timeJson: #"[{"node":1,"start":"08:00","end":"08:45"},{"node":2,"start":"09:00","end":"09:45"}]"#,
            comboScheduleJson: """
            {"publicSchedules":[{"name":"Late start","startDate":"2026-09-20","endDate":"2026-09-20",
              "timeSlots":[{"number":1,"startTime":"10:00","endTime":"10:45"},{"number":2,"startTime":"11:00","endTime":"11:45"}]}]}
            """)
        let transfer = HolidayTransferEntry(sourceDate: try XCTUnwrap(CourseOccurrences.parseDate("2026-09-07")),
            targetDate: try XCTUnwrap(CourseOccurrences.parseDate("2026-09-20")), segmentId: "holiday")
        var fixed = course("2026-10-25")
        fixed.id = 8
        fixed.ownTime = true
        fixed.startTime = "13:10:45"
        fixed.endTime = "13:55:50"
        let text = try ScheduleExporter.exportIcsOrThrow(table, [course(nil), fixed], transfers: [transfer], periodTable: period)
        XCTAssertFalse(text.contains("DTSTART:20260907"))
        XCTAssertTrue(text.contains("DTSTART:20260914T080000"))
        XCTAssertTrue(text.contains("DTSTART:20260920T100000"))
        XCTAssertTrue(text.contains("DTEND:20260920T114500"))
        XCTAssertTrue(text.contains("DTSTART:20261025T131045"))
        XCTAssertTrue(text.contains("DTEND:20261025T135550"))
        XCTAssertFalse(text.contains("RRULE:"))
        XCTAssertEqual(text.components(separatedBy: "BEGIN:VEVENT").count - 1, 3)
    }

    func testIcsCombinationWithoutTransfersExpandsWeeklyClocks() throws {
        let period = PeriodTableEntity(name: "Autumn", nodesPerDay: 2,
            timeJson: #"[{"node":1,"start":"08:00","end":"08:45"},{"node":2,"start":"09:00","end":"09:45"}]"#,
            comboScheduleJson: """
            {"publicSchedules":[{"name":"Late start","startDate":"2026-09-14","endDate":"2026-09-14",
              "timeSlots":[{"number":1,"startTime":"08:30","endTime":"09:00"}]}]}
            """)
        let text = try ScheduleExporter.exportIcsOrThrow(table, [course(nil)], periodTable: period)
        XCTAssertFalse(text.contains("RRULE:"))
        XCTAssertTrue(text.contains("DTSTART:20260907T080000"))
        XCTAssertTrue(text.contains("DTSTART:20260914T083000"))
        XCTAssertEqual(text.components(separatedBy: "BEGIN:VEVENT").count - 1, 2)
    }

}
