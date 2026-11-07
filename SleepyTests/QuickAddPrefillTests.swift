import XCTest
import Combine
@testable import Sleepy

final class QuickAddPrefillTests: XCTestCase {
    private func table(id: Int64 = 1) -> TimeTableEntity {
        TimeTableEntity(name: "快速加课", startDate: "2026-09-07", maxWeek: 20, nodesPerDay: 4,
            timeJson: """
            [{"node":0,"start":"07:00","end":"07:30","edge":"before"},
             {"node":1,"start":"08:00","end":"08:45"},
             {"node":2,"start":"09:00","end":"09:45"},
             {"node":3,"start":"10:00","end":"10:45"},
             {"node":4,"start":"11:00","end":"11:45"},
             {"node":5,"start":"12:00","end":"12:30","edge":"after"}]
            """, isDefault: true, id: id)
    }

    func testPrefillInitializesExactDaySpanAndSingleWeek() throws {
        let slot = CourseAddSlot(tableId: 1, week: 3, day: 6, node: 2, step: 3)
        let block = try XCTUnwrap(AddCourseScreen.quickAddMeetingBlock(slot, table: table()))
        XCTAssertEqual(block.days, [6])
        XCTAssertEqual(block.startNode, 2)
        XCTAssertEqual(block.step, 3)
        XCTAssertEqual(block.startWeek, 3)
        XCTAssertEqual(block.endWeek, 3)
        XCTAssertEqual(block.weekType, 0)
        XCTAssertFalse(block.isIrregularNode)
        XCTAssertFalse(block.isIrregularTime)
        XCTAssertTrue(AddCourseScreen.validateCourseDraft(courseName: "课", blocks: [block],
            startWeek: 3, endWeek: 3, timeJson: table().timeJson).isEmpty)
        XCTAssertFalse(AddCourseScreen.validateCourseDraft(courseName: "", blocks: [block],
            startWeek: 3, endWeek: 3, timeJson: table().timeJson).isEmpty)
    }

    func testBothEdgeSlotsKeepNodeIdentityAndSinglePeriod() throws {
        for node in [0, 5] {
            let slot = CourseAddSlot(tableId: 1, week: 4, day: 7, node: node, step: 1)
            let block = try XCTUnwrap(AddCourseScreen.quickAddMeetingBlock(slot, table: table()))
            XCTAssertTrue(block.isIrregularNode)
            XCTAssertEqual(block.selectedEdgeNode, node)
            XCTAssertEqual(block.step, 1)
            XCTAssertTrue(AddCourseScreen.validateCourseDraft(courseName: "边缘课", blocks: [block],
                startWeek: 4, endWeek: 4, timeJson: table().timeJson).isEmpty)
            let entity = AddCourseScreen.buildCourseEntity(tableId: 1, groupId: "edge", courseName: "边缘课",
                day: 7, block: block, timeJson: table().timeJson)
            XCTAssertEqual(entity.startNode, node)
            XCTAssertEqual(entity.step, 1)
            XCTAssertTrue(entity.isIrregularNode)
        }
    }

    func testInvalidOrStaleSlotDoesNotFallBackToDefaultMonday() {
        for slot in [
            CourseAddSlot(tableId: 2, week: 3, day: 6, node: 2, step: 1),
            CourseAddSlot(tableId: 1, week: 0, day: 6, node: 2, step: 1),
            CourseAddSlot(tableId: 1, week: 3, day: 8, node: 2, step: 1),
            CourseAddSlot(tableId: 1, week: 3, day: 6, node: -1, step: 1),
            CourseAddSlot(tableId: 1, week: 3, day: 6, node: 0, step: 2),
            CourseAddSlot(tableId: 1, week: 3, day: 6, node: 4, step: 2),
            CourseAddSlot(tableId: 1, week: 3, day: 6, node: 2, step: Int.max)
        ] {
            XCTAssertNil(AddCourseScreen.quickAddMeetingBlock(slot, table: table()))
        }
    }

    @MainActor
    func testPrefilledDraftRoundTripsThroughRepositoryWithoutChangingOtherCourses() throws {
        let db = try AppDatabase.inMemory()
        let table = table(id: 1_700_000_123)
        _ = try db.timeTableDao.insert(table)
        let repo = ScheduleRepository(db)
        defer { Sleepy.UndoManager.shared.clear() }
        let slot = CourseAddSlot(tableId: table.id, week: 3, day: 6, node: 2, step: 3)
        let block = try XCTUnwrap(AddCourseScreen.quickAddMeetingBlock(slot, table: table))
        let draft = AddCourseScreen.buildCourseEntity(tableId: table.id, groupId: "quick", courseName: "新课程",
            day: 6, block: block, timeJson: table.timeJson, tableStartDate: table.startDate)
        let untouched = CourseEntity(groupId: "old", tableId: table.id, courseName: "已有课程",
            day: 1, startNode: 1, step: 1, startWeek: 1, endWeek: 20, color: "#FF6750A4")
        _ = try repo.insertCourses([untouched])
        let original = try repo.getCourses(table.id)
        _ = try repo.insertCourses([draft])
        let rows = try repo.getCourses(table.id)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.filter { $0.groupId == "old" }, original)
        let saved = try XCTUnwrap(rows.first { $0.groupId == "quick" })
        XCTAssertEqual(saved.tableId, table.id)
        XCTAssertEqual(saved.day, 6)
        XCTAssertEqual(saved.startNode, 2)
        XCTAssertEqual(saved.step, 3)
        XCTAssertEqual(saved.startWeek, 3)
        XCTAssertEqual(saved.endWeek, 3)
        XCTAssertEqual(saved.type, 0)
        XCTAssertTrue(saved.inWeek(3))
        XCTAssertFalse(saved.inWeek(2))
        XCTAssertFalse(saved.inWeek(4))
    }

    @MainActor
    func testNavigatorPrefillClearsOnBackOrdinaryAddEditingAndOtherOverlay() async throws {
        let db = try AppDatabase.inMemory()
        let table = table(id: 1_700_000_124)
        _ = try db.timeTableDao.insert(table)
        let root = AppRootViewModel(repository: ScheduleRepository(db))
        let ready = expectation(description: "水合表已发布")
        let token = root.scheduleViewModel.$state
            .filter { $0.selectedTableId == table.id && $0.effectiveCurrentTable != nil }
            .prefix(1).sink { _ in ready.fulfill() }
        defer { token.cancel() }
        await fulfillment(of: [ready], timeout: 3)

        func open() {
            XCTAssertTrue(root.navigator.openAddCourseAt(tableId: table.id, week: 3, day: 6, node: 2, step: 3))
            XCTAssertEqual(root.overlayScreen, .addCourse)
            XCTAssertNil(root.editingCourse)
            XCTAssertEqual(root.initialCourseSlot,
                CourseAddSlot(tableId: table.id, week: 3, day: 6, node: 2, step: 3))
        }
        open()
        root.handleBack()
        XCTAssertNil(root.initialCourseSlot)
        XCTAssertNil(root.overlayScreen)
        open()
        root.overlayScreen = nil // 保存成功/关闭 overlay 的生产出口。
        XCTAssertNil(root.initialCourseSlot)
        open()
        root.navigator.openAddCourse()
        XCTAssertNil(root.initialCourseSlot)
        open()
        let fixed = CourseEntity(groupId: "fixed", tableId: table.id, courseName: "定日课", day: 1,
            startNode: 1, step: 1, startWeek: 1, endWeek: 1, color: "#FF6750A4", id: 42, fixedDate: "2026-09-07")
        root.navigator.session.beginEditCourse(fixed)
        XCTAssertNil(root.initialCourseSlot)
        root.navigator.openAddCourse(courseId: fixed.id, editing: true)
        XCTAssertEqual(root.editingCourse?.fixedDate, "2026-09-07")
        open()
        root.overlayScreen = .allTables
        XCTAssertNil(root.initialCourseSlot)
        XCTAssertFalse(root.navigator.openAddCourseAt(tableId: table.id + 1, week: 3, day: 6, node: 2, step: 3))
        XCTAssertEqual(root.overlayScreen, .allTables)
    }

    func testOrdinaryDraftDefaultsAndFixedDateEditRemainIndependentOfPrefill() throws {
        let slot = CourseAddSlot(tableId: 1, week: 3, day: 6, node: 2, step: 3)
        _ = try XCTUnwrap(AddCourseScreen.quickAddMeetingBlock(slot, table: table()))
        let plain = AddCourseScreen.initialMeetingBlock(nil)
        XCTAssertEqual(plain.days, [1])
        XCTAssertEqual(plain.startNode, 1)
        XCTAssertEqual(plain.step, 2)
        XCTAssertEqual(plain.startWeek, 1)
        XCTAssertEqual(plain.endWeek, 16)
        XCTAssertNil(plain.fixedDate)
        let fixed = CourseEntity(groupId: "fixed", tableId: 1, courseName: "定日课", day: 1,
            startNode: 1, step: 1, startWeek: 1, endWeek: 1, color: "#FF6750A4", id: 42, fixedDate: "2026-09-07")
        let block = AddCourseScreen.initialMeetingBlock(fixed)
        let saved = AddCourseScreen.buildCourseEntity(tableId: 1, groupId: "fixed", courseName: fixed.courseName,
            day: 1, block: block, timeJson: table().timeJson, tableStartDate: table().startDate)
        XCTAssertEqual(saved.fixedDate, fixed.fixedDate)
        XCTAssertEqual(saved.day, fixed.day)
        XCTAssertEqual(saved.startWeek, fixed.startWeek)
        XCTAssertEqual(saved.endWeek, fixed.endWeek)
    }
}
