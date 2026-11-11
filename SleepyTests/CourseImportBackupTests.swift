import XCTest
import GRDB
@testable import Sleepy

final class CourseImportBackupTests: XCTestCase {
    private let oldTimes = #"[{"node":1,"start":"10:00","end":"10:45"},{"node":2,"start":"11:00","end":"11:45"}]"#
    private let incomingTimes = #"[{"node":1,"start":"15:00","end":"15:45"},{"node":3,"start":"13:00","end":"13:45"}]"#
    private var previousDepth = 5

    override func setUp() {
        super.setUp()
        previousDepth = Sleepy.UndoManager.shared.maxDepth
        Sleepy.UndoManager.shared.clear()
        Sleepy.UndoManager.shared.applyMaxDepth(5)
    }

    override func tearDown() {
        Sleepy.UndoManager.shared.clear()
        Sleepy.UndoManager.shared.applyMaxDepth(previousDepth)
        super.tearDown()
    }

    private struct Fixture {
        let database: AppDatabase
        let repository: ScheduleRepository
        let selected: Int64
        let target: Int64
        let period: Int64
    }

    private func fixture() throws -> Fixture {
        let database = try AppDatabase.inMemory()
        let repository = ScheduleRepository(database)
        let selected = try repository.insertTable(TimeTableEntity(name: "Selected", startDate: "2026-09-07", isDefault: true))
        let target = try repository.insertTable(TimeTableEntity(name: "Target", startDate: "2026-09-14", maxWeek: 16,
            nodesPerDay: 1, timeJson: #"[{"node":1,"start":"08:00","end":"08:45"}]"#, smartConfigJson: "private"))
        let period = try repository.insertPeriodTable(PeriodTableEntity(name: "Shared bell", nodesPerDay: 2,
            timeJson: oldTimes, smartConfigJson: "shared"))
        try repository.bindPeriodTable(timeTableId: target, periodTableId: period)
        _ = try repository.insertCourse(course(target, name: "Original", day: 1, node: 1, endWeek: 16))
        _ = try repository.insertCourse(course(selected, name: "Keep selected", day: 4, node: 1, endWeek: 16))
        Sleepy.UndoManager.shared.clear()
        return Fixture(database: database, repository: repository, selected: selected, target: target, period: period)
    }

    private func course(_ table: Int64, name: String = "Incoming", day: Int = 2,
                        node: Int = 2, endWeek: Int = 24) -> CourseEntity {
        CourseEntity(groupId: "original-group", tableId: table, courseName: name,
            day: day, startNode: node, step: 1, startWeek: 1, endWeek: endWeek, color: "#FF123456")
    }

    private func append(_ f: Fixture, courses: [CourseEntity]? = nil,
                        backup: Bool = true, conflicts: Bool = false) throws -> Int {
        try f.repository.appendImportedCoursesWithBackup(f.target, courses: courses ?? [course(999)],
            incomingTimeJson: incomingTimes, requiredNodeCount: 3, keepGroups: true,
            backupOriginal: backup, appendConflicts: conflicts)
    }

    func testBackupFreezesEffectiveScheduleAndImportKeepsOriginalCompatibilityColumns() throws {
        let f = try fixture()
        let original = try XCTUnwrap(f.repository.getTable(f.target))
        let originalPeriod = try XCTUnwrap(f.repository.getPeriodTable(f.period))
        let selectedCourses = try f.repository.getCourses(f.selected)
        let backupBase = L10n.format("import_backup_name", original.name)
        _ = try f.repository.insertPeriodTable(PeriodTableEntity(name: backupBase, timeJson: oldTimes))
        _ = try f.repository.insertTable(TimeTableEntity(name: backupBase + "2", startDate: "2026-09-07"))
        var first = course(999)
        first.id = 999
        let second = course(999, day: 3)
        var changed = 0
        f.repository.onDataChangedHook = { changed += 1 }
        Sleepy.UndoManager.shared.clear()
        XCTAssertEqual(try append(f, courses: [first, second]), 2)
        XCTAssertEqual(changed, 1)
        let target = try XCTUnwrap(f.repository.getTable(f.target))
        let backup = try XCTUnwrap(f.repository.getAllTables().first { $0.name == backupBase + "3" })
        XCTAssertEqual(backup.timeJson, oldTimes)
        XCTAssertEqual(backup.nodesPerDay, 2)
        XCTAssertEqual(backup.smartConfigJson, "shared")
        XCTAssertEqual(backup.maxWeek, 16)
        XCTAssertNil(backup.periodTableId)
        XCTAssertEqual(backup.preBindSnapshotJson, "")
        XCTAssertFalse(backup.isDefault)
        XCTAssertFalse(backup.reminderEnabled)
        XCTAssertEqual(try f.repository.getCourses(backup.id).map(\.courseName), ["Original"])
        XCTAssertEqual(try f.repository.getCourses(backup.id).map(\.groupId), ["original-group"])
        XCTAssertEqual(target.timeJson, original.timeJson)
        XCTAssertEqual(target.nodesPerDay, original.nodesPerDay)
        XCTAssertEqual(target.smartConfigJson, original.smartConfigJson)
        XCTAssertEqual(target.preBindSnapshotJson, original.preBindSnapshotJson)
        XCTAssertEqual(target.periodTableId, f.period)
        XCTAssertEqual(target.maxWeek, 24)
        let extended = try XCTUnwrap(f.repository.getPeriodTable(f.period))
        XCTAssertEqual(TimeTableUtils.parseTimeSlotRows(extended.timeJson).first?.start, "10:00")
        XCTAssertEqual(extended.nodesPerDay, 2)
        XCTAssertEqual(extended, originalPeriod, "Appending courses must not alter the shared bell schedule")
        let imported = try f.repository.getCourses(f.target).filter { $0.courseName == "Incoming" }
        XCTAssertEqual(imported.count, 2)
        XCTAssertEqual(Set(imported.map(\.groupId)).count, 1)
        XCTAssertNotEqual(imported.first?.groupId, "original-group")
        XCTAssertTrue(imported.allSatisfy { $0.tableId == f.target && $0.id != 999 })
        XCTAssertEqual(try f.repository.getCourses(f.selected), selectedCourses)
        XCTAssertEqual(try f.repository.getDefaultTable()?.id, f.target)
    }

    func testBackupAppendAndDefaultSwitchAreOneUndoRedoAction() throws {
        let f = try fixture()
        let before = try f.repository.getCourses(f.target)
        XCTAssertEqual(try append(f), 1)
        let after = try f.repository.getCourses(f.target)
        let backupId = try XCTUnwrap(f.repository.getAllTables().first { $0.id != f.selected && $0.id != f.target }?.id)
        XCTAssertTrue(try f.repository.restoreLastSnapshot())
        XCTAssertEqual(try f.repository.getAllTables().count, 2)
        XCTAssertNil(try f.repository.getTable(backupId))
        XCTAssertEqual(try f.repository.getCourses(f.target), before)
        XCTAssertEqual(try f.repository.getPeriodTable(f.period)?.timeJson, oldTimes)
        XCTAssertEqual(try f.repository.getDefaultTable()?.id, f.selected)
        XCTAssertFalse(Sleepy.UndoManager.shared.hasSnapshot)
        XCTAssertTrue(try f.repository.redoLastUndo())
        XCTAssertEqual(try f.repository.getCourses(f.target), after)
        XCTAssertNotNil(try f.repository.getTable(backupId))
        XCTAssertEqual(try f.repository.getDefaultTable()?.id, f.target)
    }

    func testFailureAfterBackupAndCourseInsertRollsBackEverythingAndKeepsRedo() throws {
        let f = try fixture()
        let beforeTables = try f.repository.getAllTables()
        let beforeCourses = try f.repository.getCourses(f.target)
        let colors = try f.database.dbQueue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM course_colors") }
        Sleepy.UndoManager.shared.recordRedo(UndoSnapshot(tables: beforeTables, courses: beforeCourses, defaultTableId: f.selected))
        try f.database.dbQueue.write {
            try $0.execute(sql: "CREATE TRIGGER reject_import_schedule BEFORE UPDATE ON time_tables BEGIN SELECT RAISE(ABORT, 'injected timetable failure'); END")
        }
        var changed = 0
        f.repository.onDataChangedHook = { changed += 1 }
        XCTAssertThrowsError(try append(f))
        XCTAssertEqual(try f.repository.getAllTables().map(\.id), beforeTables.map(\.id))
        XCTAssertEqual(try f.repository.getCourses(f.target), beforeCourses)
        XCTAssertEqual(try f.repository.getPeriodTable(f.period)?.timeJson, oldTimes)
        XCTAssertEqual(try f.repository.getDefaultTable()?.id, f.selected)
        XCTAssertEqual(try f.database.dbQueue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM course_colors") }, colors)
        XCTAssertFalse(Sleepy.UndoManager.shared.hasSnapshot)
        XCTAssertTrue(Sleepy.UndoManager.shared.hasRedoSnapshot)
        XCTAssertEqual(changed, 0)
    }

    func testLiveConflictsReturnZeroWithoutBackupMutationOrHistory() throws {
        let f = try fixture()
        let before = try f.repository.getCourses(f.target)
        var conflicting = course(999, day: 1, node: 8)
        conflicting.ownTime = true
        conflicting.startTime = "10:15"
        conflicting.endTime = "10:30"
        var changed = 0
        f.repository.onDataChangedHook = { changed += 1 }
        XCTAssertEqual(try append(f, courses: [conflicting]), 0)
        XCTAssertEqual(try f.repository.getAllTables().count, 2)
        XCTAssertEqual(try f.repository.getCourses(f.target), before)
        XCTAssertEqual(try f.repository.getPeriodTable(f.period)?.timeJson, oldTimes)
        XCTAssertEqual(try f.repository.getDefaultTable()?.id, f.selected)
        XCTAssertFalse(Sleepy.UndoManager.shared.hasSnapshot)
        XCTAssertEqual(changed, 0)
    }

    func testAppendConflictsWithoutBackupRemapsDistinctAuthoritativeGroups() throws {
        let f = try fixture()
        let first = course(999, day: 1, node: 1)
        var second = first
        second.groupId = "separate-authoritative-group"
        XCTAssertEqual(try append(f, courses: [first, second], backup: false, conflicts: true), 2)
        XCTAssertEqual(try f.repository.getAllTables().count, 2)
        let imported = try f.repository.getCourses(f.target).filter { $0.courseName == "Incoming" }
        XCTAssertEqual(Set(imported.map(\.groupId)).count, 2)
        XCTAssertFalse(imported.contains { $0.groupId == "original-group" || $0.groupId == second.groupId })
        XCTAssertEqual(try f.repository.getCourses(f.target).count, 3)
    }

    func testNonAuthoritativeAppendKeepsSameNameDifferentTeachersSeparate() throws {
        let f = try fixture()
        var first = course(999)
        first.groupId = ""
        first.teacher = "Teacher A"
        var second = course(999, day: 3)
        second.groupId = ""
        second.teacher = "Teacher B"
        second.color = "#FF654321"

        XCTAssertEqual(try f.repository.appendImportedCoursesWithBackup(f.target, courses: [first, second],
            incomingTimeJson: incomingTimes, requiredNodeCount: 3, keepGroups: false,
            backupOriginal: false), 2)

        let imported = try f.repository.getCourses(f.target).filter { $0.courseName == "Incoming" }
        XCTAssertEqual(imported.count, 2)
        XCTAssertEqual(Set(imported.map(\.groupId)).count, 2)
        XCTAssertTrue(imported.allSatisfy { !$0.groupId.isBlank && $0.groupId != "original-group" })
        XCTAssertEqual(imported.first { $0.teacher == "Teacher A" }?.color, first.color)
        XCTAssertEqual(imported.first { $0.teacher == "Teacher B" }?.color, second.color)
    }

    func testAuthoritativeBlankGroupsKeepMeetingsTogetherAndTeachersSeparate() throws {
        let f = try fixture()
        var first = course(999, name: " Incoming ")
        first.groupId = "  "
        first.teacher = " Teacher A "
        var second = course(999, day: 3)
        second.groupId = ""
        second.teacher = "Teacher A"
        var third = course(999, day: 4)
        third.groupId = "\n"
        third.teacher = "Teacher B"

        XCTAssertEqual(try append(f, courses: [first, second, third], backup: false), 3)

        let imported = try f.repository.getCourses(f.target).filter {
            $0.courseName.trimmingCharacters(in: .whitespacesAndNewlines) == "Incoming"
        }
        XCTAssertEqual(imported.count, 3)
        let teacherA = imported.filter { $0.teacher.trimmingCharacters(in: .whitespacesAndNewlines) == "Teacher A" }
        let teacherB = try XCTUnwrap(imported.first { $0.teacher == "Teacher B" })
        XCTAssertEqual(teacherA.count, 2)
        XCTAssertEqual(Set(teacherA.map(\.groupId)).count, 1)
        XCTAssertNotEqual(teacherA.first?.groupId, teacherB.groupId)
        XCTAssertEqual(Set(imported.map(\.groupId)).count, 2)
        XCTAssertTrue(imported.allSatisfy { !$0.groupId.isBlank && $0.groupId != "original-group" })
    }

    func testMissingTargetOrOverflowDraftCannotCreateBackupOrHistory() throws {
        let f = try fixture()
        XCTAssertThrowsError(try f.repository.appendImportedCoursesWithBackup(Int64.max, courses: [course(999)],
            incomingTimeJson: incomingTimes, requiredNodeCount: 3, keepGroups: true, backupOriginal: true))
        var overflow = course(999, node: Int.max)
        overflow.step = 2
        XCTAssertThrowsError(try append(f, courses: [overflow]))
        XCTAssertEqual(try f.repository.getAllTables().count, 2)
        XCTAssertEqual(try f.repository.getCourses(f.target).count, 1)
        XCTAssertFalse(Sleepy.UndoManager.shared.hasSnapshot)
    }
}
