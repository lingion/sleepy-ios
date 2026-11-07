import XCTest
import GRDB
@testable import Sleepy

final class FixedDateCourseTests: XCTestCase {
    private let table = TimeTableEntity(name: "定日课", startDate: "2026-09-07", maxWeek: 3, id: 1)

    private func course(fixed: String? = nil) -> CourseEntity {
        CourseEntity(groupId: "math", tableId: 1, courseName: "数学", day: 1, startNode: 1, step: 2,
                     startWeek: 1, endWeek: 3, color: "#FF6750A4", id: 7, fixedDate: fixed)
    }
    private func date(_ value: String) -> Date { CourseOccurrences.parseDate(value)! }

    func testFixedDateStaysOnHolidayAndDoesNotDuplicateOnTransferTarget() {
        let transfer = HolidayTransferEntry(sourceDate: date("2026-09-07"), targetDate: date("2026-09-20"), segmentId: "holiday")
        let recurring = course()
        var fixed = course(fixed: "2026-09-07")
        fixed.id = 8
        let source = CourseOccurrences.coursesForDate(date("2026-09-07"), startDate: table.startDate, maxWeek: 3,
                                                     courses: [recurring, fixed], transfers: [transfer])
        let target = CourseOccurrences.coursesForDate(date("2026-09-20"), startDate: table.startDate, maxWeek: 3,
                                                     courses: [recurring, fixed], transfers: [transfer])
        XCTAssertEqual(source.map(\.id), [8])
        XCTAssertEqual(target.map(\.id), [7])
        XCTAssertEqual(CourseOccurrences.resolve(course: recurring, displayDate: date("2026-09-20"), table: table,
                                                 transfers: [transfer])?.sourceDate, transfer.sourceDate)
        XCTAssertNil(CourseOccurrences.resolve(course: fixed, displayDate: date("2026-09-20"), table: table, transfers: [transfer]))
    }

    func testFixedDateDisplayDoesNotDependOnStaleWeekOrDayMetadata() {
        var fixed = course(fixed: "2026-10-04")
        fixed.day = 4
        fixed.startWeek = 1
        fixed.endWeek = 1
        XCTAssertEqual(CourseOccurrences.coursesForDate(date("2026-10-04"), startDate: table.startDate, maxWeek: 3,
                                                       courses: [fixed], transfers: []), [fixed])
        XCTAssertTrue(CourseOccurrences.coursesForDate(date("2026-09-10"), startDate: table.startDate, maxWeek: 3,
                                                      courses: [fixed], transfers: []).isEmpty)
    }

    func testDateParsingRejectsCalendarRolloverAndUsesCivilDate() {
        for invalid in ["2026-02-30", "2026-13-01", "2026-9-7", "", "2026-09-07T00:00:00Z"] {
            XCTAssertNil(CourseOccurrences.parseDate(invalid))
        }
        XCTAssertEqual(CourseOccurrences.day(date("2026-09-07")), 1)
        XCTAssertEqual(CourseOccurrences.week(startDate: "2026-09-09", date: date("2026-09-14")), 2)
        XCTAssertEqual(CourseOccurrences.date(startDate: "2026-09-09", week: 2, day: 7), date("2026-09-20"))
    }

    func testRemovingOddOccurrenceKeepsExactTeachingWeeksAndMetadata() throws {
        var row = course()
        row.type = 1; row.endWeek = 9; row.alias = "数"; row.note = "保留"; row.colorMode = 2
        let remaining = try CourseOccurrences.without(row, sourceDate: date("2026-10-05"), startDate: table.startDate)
        XCTAssertEqual(remaining.map(\.startWeek), [1, 7])
        XCTAssertEqual(remaining.map(\.endWeek), [3, 9])
        XCTAssertEqual(remaining.map(\.id), [7, 0])
        XCTAssertTrue(remaining.allSatisfy { $0.type == 1 && $0.alias == "数" && $0.note == "保留" && $0.colorMode == 2 })
        XCTAssertThrowsError(try CourseOccurrences.without(row, sourceDate: date("2026-09-14"), startDate: table.startDate))
    }

    func testMergeUsesExactWeekSetsAndPreservesDuplicateOccurrencesAndFixedRows() {
        var left = course(); left.endWeek = 1
        var right = left; right.id = 9; right.startWeek = 3; right.endWeek = 3
        let merged = CourseOccurrences.mergeMatchingRows([left, right])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.id, 7)
        XCTAssertEqual(merged.first?.type, 1)
        XCTAssertEqual(merged.first?.endWeek, 3)
        XCTAssertEqual(CourseOccurrences.mergeMatchingRows([left, left]).count, 2)
        right.fixedDate = "2026-09-21"
        XCTAssertEqual(CourseOccurrences.mergeMatchingRows([left, right]).count, 2)
    }

    func testConflictPreviewUsesTransferredDisplayDatesAndFixedDates() {
        var fixed = course(fixed: "2026-09-20"); fixed.courseName = "实验"
        let transfer = HolidayTransferEntry(sourceDate: date("2026-09-07"), targetDate: date("2026-09-20"), segmentId: "holiday")
        let details = CourseOccurrences.conflictDetails(drafts: [fixed], stored: [course()], table: table, transfers: [transfer])
        XCTAssertEqual(details.count, 1)
        XCTAssertTrue(details[0].hasPrefix("2026-09-20"))
        XCTAssertTrue(CourseOccurrences.conflictDetails(drafts: [fixed], stored: [course()], table: table, transfers: []).isEmpty)
    }

    func testOldDatabaseUpgradePreservesRowsAndAddsNullableFixedDate() throws {
        let template = try AppDatabase.inMemory()
        let queue = try DatabaseQueue()
        try template.migrator.migrate(queue, upTo: "v12.createCourseColors")
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO time_tables (id,name,startDate,maxWeek,nodesPerDay,timeJson,color,isDefault,smartConfigJson,createdAt)
                VALUES (1,'旧表','2026-09-07',16,12,'[]','#FF6750A4',1,'',0)
                """)
            try db.execute(sql: """
                INSERT INTO courses (id,groupId,tableId,courseName,teacher,room,note,day,startNode,step,startWeek,endWeek,type,color,ownTime,startTime,endTime,credit,level)
                VALUES (7,'math',1,'旧课程','','','',1,1,2,1,16,0,'#FF6750A4',0,'','',0,0)
                """)
        }
        let upgraded = try AppDatabase(queue: queue)
        var row = try XCTUnwrap(upgraded.courseDao.getById(7))
        XCTAssertEqual(row.courseName, "旧课程")
        XCTAssertNil(row.fixedDate)
        row.fixedDate = "2026-09-07"
        try upgraded.courseDao.update(row)
        XCTAssertEqual(try upgraded.courseDao.getById(7)?.fixedDate, "2026-09-07")
    }

    func testGroupEditorRoundTripKeepsFixedDateAndSeparateBlocks() {
        let fixed = course(fixed: "2026-09-07")
        let block = AddCourseScreen.initialMeetingBlock(fixed)
        let rebuilt = AddCourseScreen.buildCourseEntity(tableId: 1, groupId: "math", courseName: "数学", day: 1, block: block)
        XCTAssertEqual(rebuilt.fixedDate, "2026-09-07")
        XCTAssertEqual(AddCourseScreen.groupSlotsForEdit([course(), fixed]).count, 2)
    }
}
