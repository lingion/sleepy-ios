import XCTest
import Combine
import GRDB
@testable import Sleepy

final class DuplicateTableAtomicTests: XCTestCase {
    private let history = Sleepy.UndoManager.shared
    private var previousDepth = 5
    private let compatibilityJSON = #"[{"node":1,"start":"08:00","end":"08:45"}]"#
    private let sharedJSON = #"[{"node":1,"start":"10:00","end":"10:45"}]"#

    override func setUp() {
        super.setUp()
        previousDepth = history.maxDepth
        history.clear()
        history.restoring = false
        history.applyMaxDepth(5)
    }

    override func tearDown() {
        history.clear()
        history.restoring = false
        history.applyMaxDepth(previousDepth)
        super.tearDown()
    }

    private struct Contents: Encodable {
        let tables: [TimeTableEntity]
        let periods: [PeriodTableEntity]
        let courses: [CourseEntity]
    }

    private func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(value)
    }

    private func contents(_ repo: ScheduleRepository) throws -> Data {
        try encoded(Contents(tables: repo.getAllTables().sorted { $0.id < $1.id },
                             periods: repo.getAllPeriodTables().sorted { $0.id < $1.id },
                             courses: repo.getAllCourses().sorted { $0.id < $1.id }))
    }

    private func source(_ repo: ScheduleRepository) throws -> Int64 {
        let periodID = try repo.insertPeriodTable(PeriodTableEntity(name: "共享作息", timeJson: sharedJSON))
        let tableID = try repo.insertTable(TimeTableEntity(
            name: "秋季课表", startDate: "2026-09-07", maxWeek: 18, nodesPerDay: 9,
            timeJson: compatibilityJSON, color: "#FF123456", isDefault: true,
            smartConfigJson: "private-config", createdAt: 1234, periodTableId: periodID,
            preBindSnapshotJson: #"{"t":"private-time","n":9,"s":"private-config"}"#,
            reminderEnabled: false))
        // The third row deliberately has the same name but a distinct group.
        // Duplication must preserve source grouping instead of applying import name matching.
        for node in 1...3 {
            try repo.insertCourse(CourseEntity(
                groupId: node == 3 ? "separate-math" : "math", tableId: tableID,
                courseName: "高等数学", teacher: "教师\(node)", room: "教室\(node)", note: "备注\(node)",
                day: node, startNode: node, step: 1, startWeek: node, endWeek: 18,
                type: node == 3 ? 3 : 0, color: "#FF123456", colorMode: CourseColorMode.CUSTOM,
                ownTime: node == 3, startTime: "10:00", endTime: "10:45", alias: "别名\(node)",
                credit: 2.5, level: node, fixedDate: node == 3 ? "2026-11-09" : nil))
        }
        return tableID
    }

    @MainActor
    func testCourseInsertFailureRollsBackTableAndEarlierRowsAndPreservesBothHistoryStacks() throws {
        let db = try AppDatabase.inMemory()
        let repo = ScheduleRepository(db)
        let sourceID = try source(repo)
        history.clear()
        let original = try contents(repo)
        try repo.insertTable(TimeTableEntity(name: "先前操作", startDate: "2026-09-07"))
        let before = try contents(repo)
        try repo.insertTable(TimeTableEntity(name: "待重做操作", startDate: "2026-09-07"))
        let redo = try contents(repo)
        XCTAssertTrue(try repo.restoreLastSnapshot())
        XCTAssertEqual(try contents(repo), before)
        XCTAssertTrue(history.hasSnapshot)
        XCTAssertTrue(history.hasRedoSnapshot)
        try db.dbQueue.write {
            try $0.execute(sql: """
                CREATE TRIGGER reject_duplicate BEFORE INSERT ON courses
                WHEN NEW.tableId != \(sourceID) AND NEW.startNode = 2
                BEGIN SELECT RAISE(ABORT, 'injected copy failure'); END;
                """)
        }
        var changes = 0
        repo.onDataChangedHook = { changes += 1 }
        XCTAssertThrowsError(try repo.duplicateTable(sourceID))
        let vm = ScheduleViewModel(repo: repo)
        var failure: String?
        XCTAssertFalse(vm.duplicateTable(sourceID, onFailure: { failure = $0 }))
        XCTAssertEqual(failure, L10n.format("table_reminder_save_failed"))
        XCTAssertEqual(vm.state.error, failure)
        XCTAssertEqual(try contents(repo), before, "Neither the empty copy nor its first inserted course may survive")
        XCTAssertEqual(changes, 0)
        XCTAssertTrue(history.hasSnapshot)
        XCTAssertTrue(history.hasRedoSnapshot)

        try db.dbQueue.write { try $0.execute(sql: "DROP TRIGGER reject_duplicate") }
        XCTAssertTrue(try repo.restoreLastSnapshot())
        XCTAssertEqual(try contents(repo), original, "Failure must preserve the previous undo snapshot")
        XCTAssertFalse(history.hasSnapshot)
        XCTAssertTrue(try repo.redoLastUndo())
        XCTAssertEqual(try contents(repo), before)
        XCTAssertTrue(try repo.redoLastUndo())
        XCTAssertEqual(try contents(repo), redo, "Failure must preserve the pre-existing redo snapshot")
        XCTAssertFalse(history.hasRedoSnapshot)
    }

    @MainActor
    func testSuccessfulCopyPreservesSettingsAndGroupingWithoutChangingSelectionAndIsOneUndoStep() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ScheduleRepository(db)
        let sourceID = try source(repo)
        for suffix in 2...3 {
            try repo.insertTable(TimeTableEntity(name: "秋季课表\(suffix)", startDate: "2026-09-07"))
        }
        let originalTable = try XCTUnwrap(repo.getTable(sourceID))
        let originalCourses = try repo.getCourses(sourceID).sorted { $0.id < $1.id }
        let vm = ScheduleViewModel(repo: repo)
        let loaded = expectation(description: "Existing default table and its courses loaded")
        var fulfilled = false
        let observation = vm.$state.sink { state in
            if !fulfilled, state.selectedTableId == sourceID, state.courses.count == originalCourses.count {
                fulfilled = true
                loaded.fulfill()
            }
        }
        await fulfillment(of: [loaded], timeout: 3)
        withExtendedLifetime(observation) {}
        let selectedID = vm.state.selectedTableId
        history.clear()
        let before = try contents(repo)
        var changes = 0
        repo.onDataChangedHook = { changes += 1 }

        XCTAssertTrue(vm.duplicateTable(sourceID))
        let copy = try XCTUnwrap(repo.getAllTables().first { $0.name == "秋季课表4" })
        var expected = originalTable
        expected.id = copy.id
        expected.name = copy.name
        expected.isDefault = false
        expected.createdAt = copy.createdAt
        XCTAssertEqual(try encoded(copy), try encoded(expected))
        XCTAssertNotEqual(copy.createdAt, originalTable.createdAt)
        XCTAssertEqual(try repo.getDefaultTable()?.id, sourceID)
        XCTAssertEqual(vm.state.selectedTableId, selectedID)
        XCTAssertNil(vm.state.error)
        let copiedCourses = try repo.getCourses(copy.id).sorted { $0.id < $1.id }
        XCTAssertEqual(copiedCourses.count, originalCourses.count)
        XCTAssertEqual(Set(copiedCourses.map(\.groupId)).count, 2)
        XCTAssertEqual(copiedCourses[0].groupId, copiedCourses[1].groupId)
        XCTAssertNotEqual(copiedCourses[0].groupId, copiedCourses[2].groupId)
        XCTAssertTrue(Set(copiedCourses.map(\.groupId)).isDisjoint(with: Set(originalCourses.map(\.groupId))))
        for (old, copied) in zip(originalCourses, copiedCourses) {
            var expectedCourse = old
            expectedCourse.id = copied.id
            expectedCourse.tableId = copy.id
            expectedCourse.groupId = copied.groupId
            XCTAssertEqual(copied, expectedCourse)
        }
        XCTAssertEqual(changes, 1)
        let after = try contents(repo)
        XCTAssertTrue(try repo.restoreLastSnapshot())
        XCTAssertEqual(try contents(repo), before)
        XCTAssertFalse(history.hasSnapshot, "A single undo must remove both the table and all copied rows")
        XCTAssertTrue(try repo.redoLastUndo())
        XCTAssertEqual(try contents(repo), after)
    }

    func testEmptyTableCanBeCopiedWithoutTakingDefaultAndUndoRemovesIt() throws {
        let db = try AppDatabase.inMemory()
        let repo = ScheduleRepository(db)
        let sourceID = try repo.insertTable(TimeTableEntity(name: "空课表", startDate: "2026-09-07"))
        history.clear()
        let before = try contents(repo)
        let copyID = try repo.duplicateTable(sourceID)
        XCTAssertEqual(try repo.getTable(copyID)?.name, "空课表2")
        XCTAssertEqual(try repo.getTable(copyID)?.isDefault, false)
        XCTAssertEqual(try repo.getDefaultTable()?.id, sourceID)
        XCTAssertTrue(try repo.getCourses(copyID).isEmpty)
        XCTAssertTrue(try repo.restoreLastSnapshot())
        XCTAssertEqual(try contents(repo), before)
        XCTAssertFalse(history.hasSnapshot)
    }

    @MainActor
    func testMissingSourceReportsFailureWithoutWritingOrPublishingUndo() throws {
        let db = try AppDatabase.inMemory()
        let repo = ScheduleRepository(db)
        let vm = ScheduleViewModel(repo: repo)
        var changes = 0
        repo.onDataChangedHook = { changes += 1 }
        XCTAssertThrowsError(try repo.duplicateTable(98765))
        XCTAssertFalse(vm.duplicateTable(98765))
        XCTAssertNotNil(vm.state.error)
        XCTAssertTrue(try repo.getAllTables().isEmpty)
        XCTAssertFalse(history.hasSnapshot)
        XCTAssertEqual(changes, 0)
    }
}
