import XCTest
@testable import Sleepy

final class FixedDateProductionWiringTests: XCTestCase {
    private let table = TimeTableEntity(name: "定日接线", startDate: "2026-09-07", maxWeek: 3,
        timeJson: "[{\"node\":1,\"start\":\"08:00\",\"end\":\"08:45\"},{\"node\":2,\"start\":\"09:00\",\"end\":\"09:45\"}]", id: 190620631)
    private func date(_ key: String) -> Date { CourseOccurrences.parseDate(key)! }
    private func course(id: Int64 = 7, fixed: String? = nil) -> CourseEntity {
        CourseEntity(groupId: "math", tableId: table.id, courseName: "数学", day: 1, startNode: 1, step: 1,
                     startWeek: 1, endWeek: 3, color: "#FF6750A4", id: id, fixedDate: fixed)
    }
    private var transfer: HolidayTransferEntry {
        HolidayTransferEntry(sourceDate: date("2026-09-07"), targetDate: date("2026-09-20"), segmentId: "holiday")
    }

    func testSharedRendererKeepsFixedCourseOnHolidayAndProjectsOnlyRecurringCourse() {
        let fixed = course(id: 8, fixed: "2026-09-07")
        let sourcePage = renderCoursesForWeek(table, week: 1, courses: [course(), fixed], transfers: [transfer], timeJson: table.timeJson)
        XCTAssertEqual(sourcePage.map(\.id), [8])
        let targetPage = renderCoursesForWeek(table, week: 2, courses: [course(), fixed], transfers: [transfer], timeJson: table.timeJson)
        XCTAssertEqual(targetPage.filter { $0.day == 7 }.map(\.id), [7])
        XCTAssertFalse(targetPage.contains { $0.id == 8 })
    }

    @MainActor
    func testNativeLiftResolvesFixedCourseOnHolidayAndRejectsWrongDisplayDate() throws {
        let fixed = course(fixed: "2026-09-07")
        let drag = CourseDragContext()
        XCTAssertNotNil(drag.begin(fixed, week: 1, frame: CGRect(x: 0, y: 0, width: 80, height: 50), touch: nil,
                                  table: table, allCourses: [fixed], transfers: [transfer]))
        XCTAssertEqual(drag.source?.occurrence, CourseOccurrenceIdentity(week: 1, day: 1))
        drag.end()
        XCTAssertNil(drag.begin(fixed, week: 2, frame: .zero, touch: nil, table: table, allCourses: [fixed], transfers: [transfer]))
    }

    func testFixedDragCandidateUsesNaturalTargetAndDoesNotLeaveGhostSourceCopies() throws {
        let fixed = course(fixed: "2026-09-07")
        let destination = CourseOccurrenceDestination(startNode: 2, endNode: 2, startTime: "09:00", endTime: "09:45", usesOwnTime: false)
        let candidate = CourseDropCandidateLayout(week: 2, courses: [], timeJson: table.timeJson,
            baseSlots: TimeTableUtils.renderSlots(timeJson: table.timeJson), configuration: .init(),
            startDate: table.startDate, maxWeek: table.maxWeek, transfers: [transfer], allCourses: [fixed])
        let snapshot = try XCTUnwrap(candidate.snapshot(source: fixed, sourceOccurrence: .init(week: 1, day: 1), day: 7, destination: destination))
        XCTAssertEqual(snapshot.targetOccurrence, CourseOccurrenceIdentity(week: 2, day: 7))
        XCTAssertEqual(snapshot.allCourses.count, 1)
        XCTAssertEqual(snapshot.allCourses.first?.fixedDate, "2026-09-20")
        XCTAssertEqual(snapshot.courses.first?.day, 7)
        XCTAssertEqual(CourseOccurrenceIdentity.destination(course: course(), startDate: table.startDate, maxWeek: table.maxWeek,
            displayWeek: 2, displayDay: 7, transfers: [transfer]), CourseOccurrenceIdentity(week: 1, day: 1))
        XCTAssertNotNil(CourseOccurrenceIdentity.destination(course: fixed, startDate: table.startDate, maxWeek: table.maxWeek,
            displayWeek: 1, displayDay: 1, transfers: [transfer]), "定日课允许落在放假原日")
    }

    func testImportDiffSeparatesFixedIdentityAndPreservesBothRowsOnEdit() {
        let recurring = course()
        let fixed = course(id: 8, fixed: "2026-09-07")
        var edited = fixed; edited.note = "仅修改这次备注"
        let diff = RowKeyDiffer.diff([recurring, edited], [recurring, fixed])
        XCTAssertTrue(diff.toInsert.isEmpty)
        XCTAssertTrue(diff.toDelete.isEmpty)
        XCTAssertEqual(diff.toUpdate.map(\.id), [8])
        XCTAssertEqual(diff.toUpdate.first?.fixedDate, "2026-09-07")
        let convert = RowKeyDiffer.diff([fixed], [recurring])
        XCTAssertEqual(convert.toInsert.count, 1)
        XCTAssertEqual(convert.toDelete, [7])
    }

    func testCalendarFixedTargetUsesNaturalWeekAndNoTransferDescription() throws {
        let previous = AppPrefs.shared.getHolidayTransfers(table.id)
        AppPrefs.shared.setHolidayTransfers(table.id, [transfer])
        defer { AppPrefs.shared.setHolidayTransfers(table.id, previous) }
        var fixed = course(id: 8, fixed: "2026-09-20")
        fixed.day = 7; fixed.startWeek = 2; fixed.endWeek = 2
        let result = SystemCalendarManager().buildEventSpecs(table: table, courses: [course(), fixed],
            options: CalendarImportOptions(calendarId: "test", applyHolidayTransfers: true),
            from: date("2026-09-20"), until: date("2026-09-21"))
        let fixedEvent = try XCTUnwrap(result.specs.first { $0.course.id == 8 })
        let recurringEvent = try XCTUnwrap(result.specs.first { $0.course.id == 7 })
        XCTAssertEqual(fixedEvent.week, 2)
        XCTAssertFalse(fixedEvent.description.contains("调课安排："))
        XCTAssertEqual(recurringEvent.week, 1)
        XCTAssertTrue(recurringEvent.description.contains("调课安排："))
        XCTAssertTrue(fixedEvent.key.hasSuffix(":2026-09-20"))
    }

    func testCalendarRangeKeepsSemesterTailAfterMidSemesterTransfer() {
        let range = SystemCalendarManager.selectedDateRange(table: table, range: .SEMESTER,
            today: date("2026-09-07"), transfers: [transfer])
        XCTAssertEqual(range.start, date("2026-09-07"))
        XCTAssertEqual(range.end, date("2026-09-28"))
        let preview = SystemCalendarManager().buildEventSpecs(table: table,
            courses: [course(fixed: "2026-09-21")], options: CalendarImportOptions(calendarId: "test"),
            from: range.start, until: range.end)
        XCTAssertEqual(preview.specs.map(\.date), [date("2026-09-21")])
    }

    func testSystemCalendarUsesDatedBellsAndRealLocalInstants() throws {
        let period = PeriodTableEntity(name: "Later", nodesPerDay: 1,
            timeJson: #"[{"node":1,"start":"08:00","end":"08:45"}]"#,
            comboScheduleJson: """
            {"publicSchedules":[{"name":"Late start","startDate":"2026-09-14","endDate":"2026-09-14",
              "timeSlots":[{"number":1,"startTime":"09:30","endTime":"10:15"}]}]}
            """)
        let zone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let options = CalendarImportOptions(calendarId: "fixture", range: .SEMESTER,
                                           applyHolidayTransfers: false, reminderMinutes: nil,
                                           firstPeriodAlarmEnabled: false, firstPeriodAlarmMinutes: 60)
        var explicit = course(id: 10, fixed: "2026-09-14")
        explicit.ownTime = true
        explicit.startTime = "13:10:45"
        explicit.endTime = "13:55:50"
        var regular = course()
        regular.step = 1
        let projected = SystemCalendarManager().buildEventSpecs(table: table, courses: [regular, explicit],
            options: options, from: date("2026-09-07"), until: date("2026-09-21"),
            periodTable: period, timeZone: zone)
        XCTAssertEqual(projected.invalid, 0)
        XCTAssertEqual(projected.specs.map(\.startHHmm), ["08:00", "09:30", "13:10:45"])
        let clock = CourseReminderCalendar(timeZone: zone)
        XCTAssertEqual(projected.specs[1].start, clock.instant(on: date("2026-09-14"), wallSeconds: 9 * 3600 + 30 * 60))
        XCTAssertEqual(projected.specs[2].end, clock.instant(on: date("2026-09-14"), wallSeconds: 13 * 3600 + 55 * 60 + 50))
    }

    func testCalendarRangeExtendsThroughPostSemesterTransferTarget() {
        let later = HolidayTransferEntry(sourceDate: date("2026-09-21"), targetDate: date("2026-10-04"), segmentId: "holiday")
        let range = SystemCalendarManager.selectedDateRange(table: table, range: .SEMESTER,
            today: date("2026-09-07"), transfers: [later])
        XCTAssertEqual(range.end, date("2026-10-05"))
    }

    func testDailyAgendaUsesOnlySelectedTableAndBellsForTheDisplayDate() async throws {
        let database = try AppDatabase.inMemory()
        let repository = ScheduleRepository(database)
        let periodID = try database.periodTableDao.insert(PeriodTableEntity(name: "Autumn bells", nodesPerDay: 2,
            timeJson: #"[{"node":1,"start":"09:30","end":"10:15"},{"node":2,"start":"10:30","end":"11:15"}]"#,
            comboScheduleJson: """
              {"publicSchedules":[{"name":"Makeup schedule","startDate":"2026-09-20","endDate":"2026-09-20",
                "timeSlots":[{"number":1,"startTime":"08:30","endTime":"09:15"}]}]}
              """))
        var selected = table
        selected.periodTableId = periodID
        try database.timeTableDao.insert(selected)
        let backup = TimeTableEntity(name: "Backup", startDate: table.startDate, id: table.id + 1)
        try database.timeTableDao.insert(backup)
        try database.timeTableDao.setDefault(selected.id)

        var recurring = course()
        recurring.type = 1 // Transfer lands in an even week, but must use the odd source week.
        try database.courseDao.insert(recurring)
        let fixed = course(id: 8, fixed: "2026-09-07")
        try database.courseDao.insert(fixed)
        var old = course(id: 9)
        old.tableId = backup.id
        old.courseName = "Backup course"
        try database.courseDao.insert(old)

        let transfers: (Int64) -> [HolidayTransferEntry] = { id in id == selected.id ? [self.transfer] : [] }
        let holiday = try await loadDailyAgenda(repository: repository, targetDate: transfer.sourceDate,
            allowsReminder: { _, _ in true }, transfersFor: transfers).agenda
        let makeup = try await loadDailyAgenda(repository: repository, targetDate: transfer.targetDate,
            allowsReminder: { _, _ in true }, transfersFor: transfers).agenda
        XCTAssertEqual(holiday.sourceTables.map(\.id), [selected.id])
        XCTAssertEqual(holiday.items.map { $0.first.course.id }, [fixed.id])
        XCTAssertEqual(makeup.items.map { $0.first.course.id }, [recurring.id])
        XCTAssertEqual(holiday.items.first?.first.startTimeText, "09:30")
        XCTAssertEqual(makeup.items.first?.first.startTimeText, "08:30")

        try database.timeTableDao.setDefault(backup.id)
        let switched = try await loadDailyAgenda(repository: repository, targetDate: transfer.sourceDate,
            allowsReminder: { _, _ in true }, transfersFor: transfers).agenda
        XCTAssertEqual(switched.sourceTables.map(\.id), [backup.id])
        XCTAssertEqual(switched.items.map { $0.first.course.id }, [old.id])
    }

    private final class Source: NotificationSchedulerBeforeClassDataSource {
        let table: TimeTableEntity
        let rows: [CourseEntity]
        let transfers: [HolidayTransferEntry]
        var allowed = true
        init(table: TimeTableEntity, rows: [CourseEntity], transfers: [HolidayTransferEntry]) {
            self.table = table; self.rows = rows; self.transfers = transfers
        }
        func resolveCurrentTable() -> TimeTableEntity? { table }
        func coursesForDay(tableId: Int64, dayOfWeek: Int) -> [CourseEntity] { rows.filter { $0.day == dayOfWeek } }
        func allCourseIds() -> [Int64] { rows.map(\.id) }
        func courseDateForDate(tableId: Int64?, date: Date) -> Date? { HolidayTransferOps.courseDateForDate(date, transfers) }
        func allowsReminder(tableId: Int64, date: Date) async -> Bool { allowed }
    }

    func testReminderKeepsFixedOnHolidayAndDoesNotMoveItToMakeupDay() async {
        let today = date("2026-09-07")
        let withinWindow = HolidayTransferEntry(sourceDate: today, targetDate: date("2026-09-13"), segmentId: "holiday")
        let source = Source(table: table, rows: [course(), course(id: 8, fixed: "2026-09-07")], transfers: [withinWindow])
        let env = NotificationSchedulerTests.FakeEnv(today: today)
        env.nowMs = { Int64(today.timeIntervalSince1970 * 1000) }
        let port = NotificationSchedulerTests.FakeAlarmPort()
        let scheduler = NotificationScheduler(env: env, dataSource: source, alarmPort: port)
        await scheduler.scheduleNext7DaysExactAlarms()
        let prefix = NotificationScheduler.NOTIFY_BEFORE_CLASS_PREFIX
        let fixedStart = date("2026-09-07").addingTimeInterval(8 * 60 * 60)
        let recurringStart = date("2026-09-13").addingTimeInterval(8 * 60 * 60)
        let fixedID = prefix + "\(table.id)_8_\(Int64(fixedStart.timeIntervalSince1970))"
        let recurringID = prefix + "\(table.id)_7_\(Int64(recurringStart.timeIntervalSince1970))"
        XCTAssertEqual(Set(port.armed.keys), Set([fixedID, recurringID]))
        let fixedExtras = port.lastExtras[fixedID] ?? [:]
        let recurringExtras = port.lastExtras[recurringID] ?? [:]
        XCTAssertEqual((fixedExtras["reminderDate"] ?? nil) as? String, "2026-09-07")
        XCTAssertEqual((recurringExtras["reminderDate"] ?? nil) as? String, "2026-09-13")
        source.allowed = false
        await scheduler.scheduleNext7DaysExactAlarms()
        XCTAssertTrue(port.armed.isEmpty, "定日课也遵守提醒开关/节假日策略")
    }

    func testReminderDoesNotRepeatFixedCourseOnItsMetadataWeekday() async {
        var fixed = course(fixed: "2026-09-07")
        fixed.endWeek = 3
        let today = date("2026-09-14")
        let env = NotificationSchedulerTests.FakeEnv(today: today)
        env.nowMs = { Int64(today.timeIntervalSince1970 * 1000) }
        let source = Source(table: table, rows: [fixed], transfers: [])
        let port = NotificationSchedulerTests.FakeAlarmPort()
        await NotificationScheduler(env: env, dataSource: source, alarmPort: port).scheduleNext7DaysExactAlarms()
        XCTAssertTrue(port.armed.isEmpty)
    }
}
