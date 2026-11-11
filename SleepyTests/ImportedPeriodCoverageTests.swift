import XCTest
@testable import Sleepy

final class ImportedPeriodCoverageTests: XCTestCase {
    private let sharedTimes = #"[{"node":1,"start":"08:00","end":"08:45"},{"node":2,"start":"09:00","end":"09:45"}]"#
    private let incomingTimes = #"[{"node":1,"start":"15:00","end":"15:45"},{"node":3,"start":"13:00","end":"13:45"}]"#

    override func setUp() { super.setUp(); Sleepy.UndoManager.shared.clear() }
    override func tearDown() { Sleepy.UndoManager.shared.clear(); super.tearDown() }

    private func course(node: Int = 3, day: Int = 2, ownTime: Bool = false) -> CourseEntity {
        .init(groupId: "incoming-\(node)-\(day)", tableId: 0, courseName: "Incoming",
              day: day, startNode: node, step: 1, startWeek: 1, endWeek: 16, color: "#FF6750A4",
              ownTime: ownTime, startTime: ownTime ? "13:00" : "", endTime: ownTime ? "13:45" : "")
    }

    private func fixture() throws -> (AppDatabase, ScheduleRepository, Int64, Int64, Int64) {
        let database = try AppDatabase.inMemory()
        let period = try database.periodTableDao.insert(.init(name: "Shared", nodesPerDay: 2, timeJson: sharedTimes))
        let selected = try database.timeTableDao.insert(.init(name: "Selected", startDate: "2026-11-02",
            nodesPerDay: 2, timeJson: sharedTimes, isDefault: true, periodTableId: period))
        let target = try database.timeTableDao.insert(.init(name: "Target", startDate: "2026-11-02",
            nodesPerDay: 1, timeJson: "[]", periodTableId: period))
        return (database, ScheduleRepository(database), selected, target, period)
    }

    private func append(_ repository: ScheduleRepository, target: Int64, courses: [CourseEntity],
                        backup: Bool = true) throws -> Int {
        try repository.appendImportedCoursesWithBackup(target, courses: courses, incomingTimeJson: incomingTimes,
            requiredNodeCount: 3, keepGroups: true, backupOriginal: backup)
    }

    private func tableSnapshot(_ repository: ScheduleRepository) throws -> [MigrationDatabaseCodec.TimeTableRow] {
        try repository.getAllTables().map(MigrationDatabaseCodec.toRow)
    }

    func testBoundPreviewUsesTheSharedScheduleWithoutImportingExtraPeriods() throws {
        let (_, repository, _, target, _) = try fixture()
        let result = ScheduleParser.ParseResult(tableName: "Source", startDate: "2026-11-02",
            courses: [course()], timeJson: incomingTimes, nodesPerDay: 3)
        let preview = try XCTUnwrap(ImportSheet.buildImportPreview(result, targetTableId: target, repository: repository))
        XCTAssertEqual(preview.effectiveTimeJson, sharedTimes)
    }

    func testMissingBoundPeriodRejectsAppendBeforeBackupAndPreservesEveryBoundTable() throws {
        let (_, repository, selected, target, period) = try fixture()
        let beforeTables = try tableSnapshot(repository)
        let beforePeriod = try repository.getPeriodTable(period)
        var changes = 0
        repository.onDataChangedHook = { changes += 1 }
        XCTAssertThrowsError(try append(repository, target: target, courses: [course()]))
        XCTAssertEqual(try tableSnapshot(repository), beforeTables)
        XCTAssertEqual(try repository.getPeriodTable(period), beforePeriod)
        XCTAssertTrue(try repository.getCourses(target).isEmpty)
        XCTAssertEqual(try repository.getDefaultTable()?.id, selected)
        XCTAssertEqual(changes, 0)
        XCTAssertFalse(Sleepy.UndoManager.shared.hasSnapshot)
    }

    func testAcceptedLowPeriodDoesNotCopyUnusedIncomingPeriodsIntoSharedSchedule() throws {
        let (_, repository, _, target, period) = try fixture()
        let before = try repository.getPeriodTable(period)
        XCTAssertEqual(try append(repository, target: target, courses: [course(node: 2)]), 1)
        XCTAssertEqual(try repository.getPeriodTable(period), before)
        XCTAssertEqual(try repository.getCourses(target).map(\.startNode), [2])
    }

    func testCoverageChecksOnlyCoursesSurvivingConflictFiltering() throws {
        let (database, repository, _, target, period) = try fixture()
        var legacy = course()
        legacy.tableId = target
        legacy.courseName = "Legacy high-period course"
        try database.courseDao.insert(legacy)
        let before = try repository.getPeriodTable(period)
        XCTAssertEqual(try append(repository, target: target, courses: [course(), course(node: 2, day: 3)]), 1)
        XCTAssertEqual(try repository.getPeriodTable(period), before)
        XCTAssertEqual(try repository.getCourses(target).count, 2)
    }

    func testActualClockCourseNeedsNoSharedPeriodAndDoesNotExtendIt() throws {
        let (_, repository, _, target, period) = try fixture()
        let before = try repository.getPeriodTable(period)
        XCTAssertEqual(try append(repository, target: target, courses: [course(node: 30, ownTime: true)]), 1)
        XCTAssertEqual(try repository.getPeriodTable(period), before)
        XCTAssertEqual(try repository.getCourses(target).first?.startTime, "13:00")
    }

    func testUnboundScheduleCanFillMissingPeriodsFromTheImport() throws {
        let database = try AppDatabase.inMemory()
        let target = try database.timeTableDao.insert(.init(name: "Private", startDate: "2026-11-02",
            nodesPerDay: 2, timeJson: sharedTimes, isDefault: true))
        let repository = ScheduleRepository(database)
        XCTAssertEqual(try append(repository, target: target, courses: [course()], backup: false), 1)
        let effective = try XCTUnwrap(repository.getTable(target))
        XCTAssertEqual(TimeTableUtils.parseTimeSlotRows(effective.timeJson).first { $0.node == 1 }?.start, "08:00")
        XCTAssertEqual(TimeTableUtils.parseTimeSlotRows(effective.timeJson).first { $0.node == 3 }?.start, "13:00")
        XCTAssertEqual(try repository.getCourses(target).map(\.startNode), [3])
    }

    func testNewImportRechecksTheLiveBoundScheduleBeforeAnyWrite() throws {
        let (_, repository, selected, _, period) = try fixture()
        let before = try tableSnapshot(repository)
        XCTAssertThrowsError(try repository.importNewTable(table: .init(name: "New", startDate: "2026-11-02",
            nodesPerDay: 3, timeJson: incomingTimes), courses: [course()], periodTable: nil, bindPeriodTableId: period))
        XCTAssertEqual(try tableSnapshot(repository), before)
        XCTAssertEqual(try repository.getPeriodTable(period)?.timeJson, sharedTimes)
        XCTAssertEqual(try repository.getDefaultTable()?.id, selected)
        XCTAssertFalse(Sleepy.UndoManager.shared.hasSnapshot)
    }
}
