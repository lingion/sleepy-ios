import XCTest
import Combine
@testable import Sleepy

final class CourseEditorTargetTests: XCTestCase {
    private let selectedJSON = #"[{"node":1,"start":"08:00","end":"08:45"}]"#
    private let targetJSON = #"[{"node":1,"start":"10:00","end":"10:45"},{"node":2,"start":"11:00","end":"11:45"}]"#
    private var previousDepth = 5

    override func setUp() {
        super.setUp()
        let history = Sleepy.UndoManager.shared
        previousDepth = history.maxDepth
        history.clear()
        history.applyMaxDepth(0)
    }

    override func tearDown() {
        let history = Sleepy.UndoManager.shared
        history.clear()
        history.applyMaxDepth(previousDepth)
        super.tearDown()
    }

    private struct Fixture {
        let repository: ScheduleRepository
        let selectedId: Int64
        let targetId: Int64
        let selectedPeriodId: Int64
        let targetPeriodId: Int64
        let selectedCourses: [CourseEntity]
        let targetCourses: [CourseEntity]
    }

    private func fixture() throws -> Fixture {
        let repo = ScheduleRepository(try AppDatabase.inMemory())
        let a = try repo.insertTable(TimeTableEntity(name: "Selected", startDate: "2026-09-07", isDefault: true))
        let b = try repo.insertTable(TimeTableEntity(name: "Editing target", startDate: "2026-10-05"))
        let pa = try repo.insertPeriodTable(PeriodTableEntity(name: "Morning", nodesPerDay: 1, timeJson: selectedJSON))
        let pb = try repo.insertPeriodTable(PeriodTableEntity(name: "Late morning", nodesPerDay: 2, timeJson: targetJSON))
        try repo.bindPeriodTable(timeTableId: a, periodTableId: pa)
        try repo.bindPeriodTable(timeTableId: b, periodTableId: pb)
        // The same group string in both tables makes an incorrectly scoped query observable.
        for (table, day, name) in [(a, 1, "Keep selected"), (b, 2, "Edit target"), (b, 4, "Edit target")] {
            try repo.insertCourse(CourseEntity(groupId: "same-group", tableId: table, courseName: name,
                day: day, startNode: 1, step: 1, startWeek: 1, endWeek: 16, color: "#FF123456"))
        }
        return Fixture(repository: repo, selectedId: a, targetId: b, selectedPeriodId: pa,
                       targetPeriodId: pb, selectedCourses: try repo.getCourses(a), targetCourses: try repo.getCourses(b))
    }

    @MainActor
    func testEditingAnotherTableLoadsAndSavesItsWholeGroupAndRealTimeOwner() async throws {
        let f = try fixture()
        let vm = ScheduleViewModel(repo: f.repository)
        let ready = expectation(description: "Selected table loaded")
        let observation = vm.$state.filter { $0.selectedTableId == f.selectedId && $0.effectivePeriodTable?.id == f.selectedPeriodId }
            .prefix(1).sink { _ in ready.fulfill() }
        defer { observation.cancel() }
        await fulfillment(of: [ready], timeout: 3)
        let source = try XCTUnwrap(f.targetCourses.first)
        let context = try XCTUnwrap(CourseEditorContext.load(editingCourse: source,
            targetTableId: f.selectedId, selectedTableId: vm.state.selectedTableId, repository: f.repository))
        XCTAssertEqual(context.table.id, f.targetId)
        XCTAssertEqual(context.table.startDate, "2026-10-05")
        XCTAssertEqual(context.table.timeJson, targetJSON)
        XCTAssertEqual(context.table.periodTableId, f.targetPeriodId)
        XCTAssertEqual(context.groupCourses, f.targetCourses)
        let rawBefore = try XCTUnwrap(f.repository.getTable(f.targetId))
        let stagedJSON = TimeTableUtils.insertEdgeNode(timeJson: targetJSON, edgeClass: .before, start: "09:00", end: "09:45")
        let drafts = context.groupCourses.map { row -> CourseEntity in
            var copy = row
            copy.tableId = f.selectedId // Context must still retain its captured owner.
            copy.alias = "Saved target"
            copy.startNode = 0
            return copy
        }
        try context.save(drafts: drafts, timeChange: .init(expectedPeriodTableId: f.targetPeriodId,
            originalTimeJson: targetJSON, updatedTimeJson: stagedJSON), repository: f.repository)
        let saved = try f.repository.getCourses(f.targetId)
        XCTAssertEqual(saved.count, 2)
        XCTAssertTrue(saved.allSatisfy { $0.alias == "Saved target" && $0.startNode == 0 && $0.tableId == f.targetId })
        XCTAssertEqual(try f.repository.getCourses(f.selectedId), f.selectedCourses)
        XCTAssertEqual(try f.repository.getPeriodTable(f.selectedPeriodId)?.timeJson, selectedJSON)
        XCTAssertEqual(try f.repository.getPeriodTable(f.targetPeriodId)?.timeJson, stagedJSON)
        XCTAssertEqual(try f.repository.getTable(f.targetId)?.timeJson, rawBefore.timeJson)
        XCTAssertEqual(vm.state.selectedTableId, f.selectedId)
        XCTAssertEqual(try f.repository.getDefaultTable()?.id, f.selectedId)
    }

    func testExplicitAddTargetWinsOverMainSelection() throws {
        let f = try fixture()
        let context = try XCTUnwrap(CourseEditorContext.load(editingCourse: nil, targetTableId: f.targetId,
            selectedTableId: f.selectedId, repository: f.repository))
        XCTAssertNil(context.editingCourse)
        XCTAssertTrue(context.groupCourses.isEmpty)
        XCTAssertEqual(context.table.timeJson, targetJSON)
        let draft = CourseEntity(groupId: "new-add", tableId: f.selectedId, courseName: "Added to target",
            day: 6, startNode: 2, step: 1, startWeek: 3, endWeek: 3, color: "")
        try context.save(drafts: [draft], repository: f.repository)
        XCTAssertEqual(try f.repository.getCourses(f.selectedId), f.selectedCourses)
        XCTAssertEqual(try f.repository.getCourses(f.targetId).filter { $0.courseName == draft.courseName }.map(\.tableId), [f.targetId])
        XCTAssertEqual(try f.repository.getDefaultTable()?.id, f.selectedId)
    }

    func testQuickAddUsesItsCapturedTableAfterMainSelectionChanges() throws {
        let f = try fixture()
        let slot = CourseAddSlot(tableId: f.targetId, week: 3, day: 6, node: 2, step: 1)
        let context = try XCTUnwrap(CourseEditorContext.load(editingCourse: nil, initialSlot: slot,
            selectedTableId: f.selectedId, repository: f.repository))
        let block = try XCTUnwrap(AddCourseScreen.quickAddMeetingBlock(slot, table: context.table))
        let draft = AddCourseScreen.buildCourseEntity(tableId: context.table.id, groupId: "quick-add",
            courseName: "Quick target", day: 6, block: block, timeJson: context.table.timeJson,
            tableStartDate: context.table.startDate)
        try context.save(drafts: [draft], repository: f.repository)
        let saved = try XCTUnwrap(f.repository.getCourses(f.targetId).first { $0.courseName == "Quick target" })
        XCTAssertEqual(saved.startNode, 2)
        XCTAssertEqual(saved.startWeek, 3)
        XCTAssertEqual(saved.endWeek, 3)
        XCTAssertEqual(try f.repository.getCourses(f.selectedId), f.selectedCourses)
        XCTAssertThrowsError(try CourseEditorContext.load(editingCourse: nil, targetTableId: f.selectedId,
            initialSlot: slot, selectedTableId: f.selectedId, repository: f.repository))
    }

    func testMissingExplicitTargetsAndMissingEditedCourseNeverFallBackToSelectedTable() throws {
        let f = try fixture()
        XCTAssertThrowsError(try CourseEditorContext.load(editingCourse: nil, targetTableId: Int64.max,
            selectedTableId: f.selectedId, repository: f.repository))
        let missingSlot = CourseAddSlot(tableId: Int64.max, week: 1, day: 1, node: 1, step: 1)
        XCTAssertThrowsError(try CourseEditorContext.load(editingCourse: nil, initialSlot: missingSlot,
            selectedTableId: f.selectedId, repository: f.repository))
        var missingCourse = try XCTUnwrap(f.targetCourses.first)
        missingCourse.id = Int64.max
        XCTAssertThrowsError(try CourseEditorContext.load(editingCourse: missingCourse,
            selectedTableId: f.selectedId, repository: f.repository))
        XCTAssertEqual(try f.repository.getCourses(f.selectedId), f.selectedCourses)
        XCTAssertEqual(try f.repository.getCourses(f.targetId), f.targetCourses)
    }

    func testDeletedEditingSourceCannotBeRecreatedBySavingAStaleDraft() throws {
        let f = try fixture()
        let context = try XCTUnwrap(CourseEditorContext.load(editingCourse: f.targetCourses.first,
            selectedTableId: f.selectedId, repository: f.repository))
        try f.repository.deleteCourseGroup(f.targetId, "same-group")
        XCTAssertThrowsError(try context.save(drafts: f.targetCourses, repository: f.repository))
        XCTAssertTrue(try f.repository.getCourses(f.targetId).isEmpty)
        XCTAssertEqual(try f.repository.getCourses(f.selectedId), f.selectedCourses)
    }

    func testRepositoryRejectsDeletedSourceBeforeChangingCourseGroupOrSchedule() throws {
        let f = try fixture()
        let source = try XCTUnwrap(f.targetCourses.first)
        try f.repository.deleteCourse(source.id)
        let remaining = try f.repository.getCourses(f.targetId)
        let stagedJSON = TimeTableUtils.insertEdgeNode(timeJson: targetJSON, edgeClass: .before,
                                                      start: "09:00", end: "09:45")
        let drafts = f.targetCourses.map { row -> CourseEntity in
            var copy = row
            copy.alias = "Must not be saved"
            copy.startNode = 0
            return copy
        }
        XCTAssertThrowsError(try f.repository.saveCourseDrafts(tableId: f.targetId,
            editingGroupId: source.groupId, drafts: drafts,
            timeChange: .init(expectedPeriodTableId: f.targetPeriodId, originalTimeJson: targetJSON,
                              updatedTimeJson: stagedJSON), editingCourseId: source.id))
        XCTAssertNil(try f.repository.getCourse(source.id))
        XCTAssertEqual(try f.repository.getCourses(f.targetId), remaining)
        XCTAssertEqual(try f.repository.getPeriodTable(f.targetPeriodId)?.timeJson, targetJSON)
        XCTAssertEqual(try f.repository.getCourses(f.selectedId), f.selectedCourses)
    }

    func testRepositoryRejectsSourceFromAnotherTableOrGroupBeforeChangingRowsOrSchedule() throws {
        let f = try fixture()
        let source = try XCTUnwrap(f.targetCourses.first)
        let anotherTableSource = try XCTUnwrap(f.selectedCourses.first)
        let stagedJSON = TimeTableUtils.insertEdgeNode(timeJson: targetJSON, edgeClass: .before,
                                                      start: "09:00", end: "09:45")
        for (sourceId, groupId) in [(anotherTableSource.id, source.groupId), (source.id, "wrong-group")] {
            let drafts = f.targetCourses.map { row -> CourseEntity in
                var copy = row
                copy.groupId = groupId
                copy.alias = "Must not be saved"
                copy.startNode = 0
                return copy
            }
            XCTAssertThrowsError(try f.repository.saveCourseDrafts(tableId: f.targetId,
                editingGroupId: groupId, drafts: drafts,
                timeChange: .init(expectedPeriodTableId: f.targetPeriodId, originalTimeJson: targetJSON,
                                  updatedTimeJson: stagedJSON), editingCourseId: sourceId))
            XCTAssertEqual(try f.repository.getCourses(f.targetId), f.targetCourses)
            XCTAssertEqual(try f.repository.getPeriodTable(f.targetPeriodId)?.timeJson, targetJSON)
            XCTAssertEqual(try f.repository.getCourses(f.selectedId), f.selectedCourses)
            XCTAssertEqual(try f.repository.getPeriodTable(f.selectedPeriodId)?.timeJson, selectedJSON)
        }
    }

    func testGroupColorAndDeleteRemainScopedToTheEditingTable() throws {
        let f = try fixture()
        let context = try XCTUnwrap(CourseEditorContext.load(editingCourse: f.targetCourses.first,
            selectedTableId: f.selectedId, repository: f.repository))
        _ = try context.setGroupColor("#FFABCDEF", repository: f.repository)
        XCTAssertTrue(try f.repository.getCourses(f.targetId).allSatisfy { $0.color == "#FFABCDEF" })
        XCTAssertEqual(try f.repository.getCourses(f.selectedId), f.selectedCourses)
        try context.deleteGroup(repository: f.repository)
        XCTAssertTrue(try f.repository.getCourses(f.targetId).isEmpty)
        XCTAssertEqual(try f.repository.getCourses(f.selectedId), f.selectedCourses)
    }

    func testFirstManualDraftMayHaveNoTableButExplicitMissingTargetMayNot() throws {
        let repo = ScheduleRepository(try AppDatabase.inMemory())
        XCTAssertNil(try CourseEditorContext.load(editingCourse: nil, selectedTableId: nil, repository: repo))
        XCTAssertThrowsError(try CourseEditorContext.load(editingCourse: nil, targetTableId: 0,
            selectedTableId: nil, repository: repo))
        XCTAssertTrue(try repo.getAllTables().isEmpty)
    }

    func testGroupReadFailureDoesNotBecomeAnEmptyEditableGroup() throws {
        let f = try fixture()
        try f.repository.database.dbQueue.write { try $0.execute(sql: "DROP TABLE courses") }
        XCTAssertThrowsError(try CourseEditorContext.load(editingCourse: f.targetCourses.first,
            selectedTableId: f.selectedId, repository: f.repository))
        XCTAssertEqual(try f.repository.getAllTables().count, 2)
        XCTAssertEqual(try f.repository.getDefaultTable()?.id, f.selectedId)
    }
}
