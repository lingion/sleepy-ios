import XCTest
import GRDB
@testable import Sleepy

final class CourseOccurrenceEditTests: XCTestCase {
    private var db: AppDatabase!
    private var repo: ScheduleRepository!
    private var table: TimeTableEntity!
    private var previousTransfers: [HolidayTransferEntry] = []
    private var notifications = 0

    override func setUpWithError() throws {
        db = try AppDatabase.inMemory()
        repo = ScheduleRepository(db)
        var table = TimeTableEntity(name: "单次编辑", startDate: "2026-09-07", maxWeek: 9)
        table.id = try db.timeTableDao.insert(table)
        self.table = table
        previousTransfers = AppPrefs.shared.getHolidayTransfers(table.id)
        AppPrefs.shared.clearHolidayTransfers(table.id)
        Sleepy.UndoManager.shared.clear()
        notifications = 0
        repo.onDataChangedHook = { [weak self] in self?.notifications += 1 }
    }

    override func tearDown() {
        if let table { AppPrefs.shared.setHolidayTransfers(table.id, previousTransfers) }
        Sleepy.UndoManager.shared.clear()
        repo = nil; db = nil; table = nil
        super.tearDown()
    }

    private func seed(fixed: String? = nil) throws -> CourseEntity {
        var row = CourseEntity(groupId: "math", tableId: table.id, courseName: "数学", teacher: "张老师", room: "A101",
                               note: "保留", day: 1, startNode: 1, step: 2, startWeek: 1, endWeek: fixed == nil ? 9 : 1,
                               color: "#FF123456", colorMode: 2, alias: "高数", credit: 3, fixedDate: fixed)
        row.id = try db.courseDao.insert(row)
        return row
    }
    private func occurrence(_ row: CourseEntity, _ day: String = "2026-10-05") throws -> CourseOccurrence {
        try XCTUnwrap(CourseOccurrences.resolve(course: row, displayDate: CourseOccurrences.parseDate(day)!, table: table,
                                               transfers: AppPrefs.shared.getHolidayTransfers(table.id)))
    }
    private func save(_ occurrence: CourseOccurrence, replacement: CourseEntity?) throws -> Bool {
        try repo.saveOccurrence(occurrence, replacement: replacement, expectedCourses: repo.getCourses(table.id),
                                expectedTable: table, expectedTransfers: AppPrefs.shared.getHolidayTransfers(table.id))
    }

    func testEditOnlyOneOccurrenceAndUndoRestoresAllMetadata() throws {
        let original = try seed()
        let source = try occurrence(original)
        var edited = try CourseOccurrences.atDate(original, date: CourseOccurrences.parseDate("2026-10-07")!, table: table, fixed: true)
        edited.startNode = 3; edited.room = "B202"
        XCTAssertTrue(try save(source, replacement: edited))
        let rows = try repo.getCourses(table.id)
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows.filter { $0.fixedDate != nil }.first?.fixedDate, "2026-10-07")
        for week in 1...9 {
            XCTAssertEqual(rows.filter { $0.fixedDate == nil && $0.inWeek(week) }.count, week == 5 ? 0 : 1)
        }
        XCTAssertEqual(notifications, 1)
        XCTAssertTrue(try repo.restoreLastSnapshot())
        XCTAssertEqual(try repo.getCourses(table.id), [original])
        XCTAssertTrue(try repo.redoLastUndo())
        XCTAssertEqual(try repo.getCourses(table.id).sorted { $0.id < $1.id }, rows.sorted { $0.id < $1.id })
    }

    func testDeleteFixedOccurrencePreservesOtherRowsAndUndoRestoresIt() throws {
        let recurring = try seed()
        let fixed = try seed(fixed: "2026-09-07")
        XCTAssertTrue(try save(occurrence(fixed, "2026-09-07"), replacement: nil))
        XCTAssertEqual(try repo.getCourses(table.id), [recurring])
        XCTAssertTrue(try repo.restoreLastSnapshot())
        XCTAssertEqual(Set(try repo.getCourses(table.id).map(\.id)), Set([recurring.id, fixed.id]))
    }

    func testDeletingTransferredOccurrenceRemovesSourceWeekNotDisplayWeek() throws {
        let row = try seed()
        let transfer = HolidayTransferEntry(sourceDate: CourseOccurrences.parseDate("2026-09-07")!,
            targetDate: CourseOccurrences.parseDate("2026-09-20")!, segmentId: "holiday")
        AppPrefs.shared.setHolidayTransfers(table.id, [transfer])
        XCTAssertTrue(try save(occurrence(row, "2026-09-20"), replacement: nil))
        let rows = try repo.getCourses(table.id)
        XCTAssertFalse(rows.contains { $0.inWeek(1) })
        XCTAssertTrue(rows.contains { $0.inWeek(2) })
        XCTAssertTrue(rows.contains { $0.inWeek(3) })
    }

    func testPreviewRejectsCourseTableAndTransferChangesWithoutUndoOrNotification() throws {
        let row = try seed()
        let source = try occurrence(row)
        let expected = try repo.getCourses(table.id)
        var changed = row; changed.room = "变更"
        try db.courseDao.update(changed)
        XCTAssertFalse(try repo.saveOccurrence(source, replacement: nil, expectedCourses: expected, expectedTable: table, expectedTransfers: []))
        try db.courseDao.update(row)
        var nextTable = table!; nextTable.name = "新名称"
        try db.timeTableDao.update(nextTable)
        XCTAssertFalse(try repo.saveOccurrence(source, replacement: nil, expectedCourses: expected, expectedTable: table, expectedTransfers: []))
        try db.timeTableDao.update(table)
        let transfer = HolidayTransferEntry(sourceDate: source.sourceDate, targetDate: CourseOccurrences.parseDate("2026-10-11")!, segmentId: "holiday")
        AppPrefs.shared.setHolidayTransfers(table.id, [transfer])
        XCTAssertFalse(try repo.saveOccurrence(source, replacement: nil, expectedCourses: expected, expectedTable: table, expectedTransfers: []))
        XCTAssertEqual(try repo.getCourses(table.id), [row])
        XCTAssertFalse(repo.canUndo)
        XCTAssertEqual(notifications, 0)
    }

    func testWriteFailureRollsBackSourceAndDoesNotPublishUndoSnapshot() throws {
        let row = try seed()
        let source = try occurrence(row)
        let replacement = try CourseOccurrences.atDate(row, date: CourseOccurrences.parseDate("2026-10-07")!, table: table, fixed: true)
        try db.dbQueue.write { db in
            try db.execute(sql: "CREATE TRIGGER reject_occurrence BEFORE INSERT ON courses BEGIN SELECT RAISE(ABORT, 'injected'); END")
        }
        XCTAssertThrowsError(try save(source, replacement: replacement))
        XCTAssertEqual(try repo.getCourses(table.id), [row])
        XCTAssertFalse(repo.canUndo)
        XCTAssertEqual(notifications, 0)
    }

    func testRestoringEditedOccurrenceMergesExactRecurringRows() throws {
        let original = try seed()
        let source = try occurrence(original)
        var replacement = try CourseOccurrences.atDate(original, date: source.sourceDate, table: table, fixed: false)
        replacement.room = "B202"
        XCTAssertTrue(try save(source, replacement: replacement))
        let edited = try XCTUnwrap(repo.getCourses(table.id).first { $0.room == "B202" })
        var restored = edited; restored.room = original.room
        XCTAssertTrue(try save(occurrence(edited), replacement: restored))
        let rows = try repo.getCourses(table.id)
        XCTAssertEqual(rows, [original])
    }

    func testExistingMoveSignatureUpdatesFixedDateAndKeepsRecurringBehavior() throws {
        let row = try seed(fixed: "2026-09-07")
        XCTAssertTrue(try repo.moveCourseOccurrence(courseId: row.id, sourceWeek: 1, targetWeek: 2, targetDay: 3, targetNode: 3))
        let moved = try XCTUnwrap(repo.getCourses(table.id).first)
        XCTAssertEqual(moved.fixedDate, "2026-09-16")
        XCTAssertEqual(moved.startWeek, 2)
        XCTAssertEqual(moved.day, 3)
        XCTAssertEqual(try repo.getCourses(table.id).count, 1)
    }

    func testChangingFixedOccurrenceDateRequiresTransferDestinationAndSavesOneWeekProvenance() throws {
        let original = try seed(fixed: "2026-09-07")
        let selected = try XCTUnwrap(CourseOccurrences.parseDate("2026-09-20"))
        let sourceDate = try XCTUnwrap(CourseOccurrences.parseDate("2026-09-14"))
        let transfer = HolidayTransferEntry(sourceDate: sourceDate, targetDate: selected, segmentId: "holiday")
        AppPrefs.shared.setHolidayTransfers(table.id, [transfer])
        let source = try occurrence(original, "2026-09-07")
        let replacement = try CourseOccurrences.replacementForEdit(original, occurrence: source,
            selectedDate: selected, table: table)
        XCTAssertNil(replacement.fixedDate, "A changed date must enter the recurring timetable destination review")
        XCTAssertEqual(CourseOccurrences.dateApproval(originalDate: source.displayDate, selectedDate: selected,
                                                      transfers: [transfer]), .destination)
        XCTAssertTrue(CourseOccurrences.coursesForDate(selected, startDate: table.startDate, maxWeek: table.maxWeek,
            courses: [replacement], transfers: [transfer]).isEmpty, "Direct scheduling is hidden by the transferred timetable")

        let followed = try CourseOccurrences.atDate(replacement, date: sourceDate, table: table, fixed: false)
        XCTAssertEqual(CourseOccurrences.coursesForDate(selected, startDate: table.startDate, maxWeek: table.maxWeek,
            courses: [followed], transfers: [transfer]), [followed])
        XCTAssertEqual(CourseOccurrences.dateApproval(originalDate: source.displayDate, selectedDate: sourceDate,
                                                      transfers: [transfer]), .outgoing)
        XCTAssertTrue(try save(source, replacement: followed))
        let stored = try XCTUnwrap(repo.getCourses(table.id).first)
        XCTAssertNil(stored.fixedDate)
        XCTAssertEqual(stored.startWeek, 2)
        XCTAssertEqual(stored.endWeek, 2)
        XCTAssertEqual(stored.day, 1)
        XCTAssertEqual(try occurrence(stored, "2026-09-20").sourceDate, sourceDate)
    }

    func testUnchangedFixedDateAndTransferredDateRetainTheirOriginalProvenance() throws {
        let fixed = try seed(fixed: "2026-09-07")
        let fixedOccurrence = try occurrence(fixed, "2026-09-07")
        let unchanged = try CourseOccurrences.replacementForEdit(fixed, occurrence: fixedOccurrence,
            selectedDate: fixedOccurrence.displayDate, table: table)
        XCTAssertEqual(unchanged.fixedDate, "2026-09-07")
        XCTAssertEqual(CourseOccurrences.dateApproval(originalDate: fixedOccurrence.displayDate,
            selectedDate: fixedOccurrence.displayDate, transfers: []), .none)

        let recurring = try seed()
        let transfer = HolidayTransferEntry(sourceDate: fixedOccurrence.sourceDate,
            targetDate: try XCTUnwrap(CourseOccurrences.parseDate("2026-09-20")), segmentId: "holiday")
        AppPrefs.shared.setHolidayTransfers(table.id, [transfer])
        let transferred = try occurrence(recurring, "2026-09-20")
        let retained = try CourseOccurrences.replacementForEdit(recurring, occurrence: transferred,
            selectedDate: transferred.displayDate, table: table)
        XCTAssertNil(retained.fixedDate)
        XCTAssertEqual(retained.startWeek, 1)
        XCTAssertEqual(retained.day, 1)
        XCTAssertEqual(CourseOccurrences.dateApproval(originalDate: transferred.displayDate,
            selectedDate: transferred.displayDate, transfers: [transfer]), .none)
    }

    func testOccurrenceConflictDetailsUseProjectedDayPeriodAndWeekContext() throws {
        let original = try seed()
        let transfer = HolidayTransferEntry(sourceDate: try XCTUnwrap(CourseOccurrences.parseDate("2026-09-07")),
            targetDate: try XCTUnwrap(CourseOccurrences.parseDate("2026-09-20")), segmentId: "holiday")
        let incoming = try CourseOccurrences.atDate(original, date: transfer.sourceDate, table: table, fixed: false)
        var existing = incoming
        existing.courseName = "Existing class"
        let details = CourseOccurrences.conflictDetails(drafts: [incoming], stored: [existing], table: table, transfers: [transfer])
        let expected = "2026-09-20 · " + ConflictDetailReporter.formatDetail(
            ConflictDetail(existingName: "Existing class", draftName: original.courseName, day: 7,
                dayText: DateUtils.localizedDay(7), nodeRangeText: "1-2", weekText: "第2周"),
            template: L10n.t("conflict_detail_line"))
        XCTAssertEqual(details, [expected])

        let earlyTransfer = HolidayTransferEntry(sourceDate: transfer.sourceDate,
            targetDate: try XCTUnwrap(CourseOccurrences.parseDate("2026-09-06")), segmentId: "early")
        let earlyExpected = "2026-09-06 · " + ConflictDetailReporter.formatDetail(
            ConflictDetail(existingName: "Existing class", draftName: original.courseName, day: 7,
                dayText: DateUtils.localizedDay(7), nodeRangeText: "1-2", weekText: "第1周"),
            template: L10n.t("conflict_detail_line"))
        XCTAssertEqual(CourseOccurrences.conflictDetails(drafts: [incoming], stored: [existing],
            table: table, transfers: [earlyTransfer]), [earlyExpected])
    }
}
