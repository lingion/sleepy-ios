import Combine
import XCTest
@testable import Sleepy

final class CourseDeepLinkNavigationTests: XCTestCase {
    @MainActor
    private func makeRoot() async throws -> (AppRootViewModel, ScheduleRepository, CourseEntity, Int64) {
        let database = try AppDatabase.inMemory()
        let repository = ScheduleRepository(database)
        let currentTable = TimeTableEntity(name: "Visible table A", startDate: "2026-09-07",
                                           isDefault: true, id: 1_700_010_001)
        let ownerTable = TimeTableEntity(name: "Course owner B", startDate: "2026-09-07",
                                         isDefault: false, id: 1_700_010_002)
        _ = try database.timeTableDao.insert(currentTable)
        _ = try database.timeTableDao.insert(ownerTable)
        _ = try repository.insertCourses([
            CourseEntity(groupId: "deep-link", tableId: ownerTable.id, courseName: "Stored course",
                         day: 2, startNode: 3, step: 2, startWeek: 1, endWeek: 20, color: "#FF6750A4")
        ])
        let course = try XCTUnwrap(repository.getCourses(ownerTable.id).first)
        let root = AppRootViewModel(repository: repository)
        let ready = expectation(description: "The stored table is loaded")
        let token = root.scheduleViewModel.$state
            .filter { $0.selectedTableId == currentTable.id && $0.effectiveCurrentTable != nil }
            .prefix(1).sink { _ in ready.fulfill() }
        defer { token.cancel() }
        await fulfillment(of: [ready], timeout: 3)
        return (root, repository, course, currentTable.id)
    }

    @MainActor
    func testValidCourseReplacesNormalOverlayAndInvalidIDLeavesItAlone() async throws {
        let (root, _, course, currentTableID) = try await makeRoot()
        root.overlayScreen = .general
        XCTAssertFalse(root.handleDeepLinkCourse(-1))
        XCTAssertEqual(root.overlayScreen, .general)
        XCTAssertNil(root.editingCourse)

        XCTAssertTrue(root.handleDeepLinkCourse(course.id))
        XCTAssertEqual(root.overlayScreen, .addCourse)
        XCTAssertEqual(root.navigator.session.editingCourse, course)
        XCTAssertNotEqual(course.tableId, currentTableID)
        XCTAssertEqual(root.scheduleViewModel.state.selectedTableId, currentTableID)
        XCTAssertNil(root.initialCourseSlot)
    }

    @MainActor
    func testCourseDeepLinkInvalidatesThePreviousDismissalCompletion() async throws {
        let (root, _, course, currentTableID) = try await makeRoot()
        root.overlayScreen = .general
        let ticket = root.beginOverlayDismissal()

        XCTAssertTrue(root.handleDeepLinkCourse(course.id))
        var staleBackCalls = 0
        root.completeOverlayDismissal(ticket) {
            staleBackCalls += 1
            root.handleBack()
        }
        XCTAssertEqual(staleBackCalls, 0)
        XCTAssertEqual(root.overlayScreen, .addCourse)
        XCTAssertEqual(root.editingCourse, course)
        XCTAssertEqual(root.editingCourse?.tableId, course.tableId)
        XCTAssertEqual(root.scheduleViewModel.state.selectedTableId, currentTableID)
    }

    @MainActor
    func testCourseDeepLinkDiscardsPendingDraftsAndBackKeepsTheStoredCourse() async throws {
        let (root, repository, course, currentTableID) = try await makeRoot()
        root.createNewTableThenEdit()
        let newTableID = try XCTUnwrap(root.pendingNewTableId)
        root.createPeriodTableThenEdit()
        let newPeriodID = try XCTUnwrap(root.pendingNewPeriodTableId)
        let discarded = expectation(description: "The abandoned new table is removed")
        let token = root.scheduleViewModel.$state
            .filter { !$0.tables.contains { $0.id == newTableID } && $0.selectedTableId == currentTableID }
            .prefix(1).sink { _ in discarded.fulfill() }
        defer { token.cancel() }

        XCTAssertTrue(root.handleDeepLinkCourse(course.id))
        XCTAssertNil(root.pendingNewTableId)
        XCTAssertNil(root.previousDefaultTableId)
        XCTAssertNil(root.editTableId)
        XCTAssertNil(root.pendingNewPeriodTableId)
        XCTAssertNil(root.periodEditId)
        XCTAssertEqual(root.overlayScreen, .addCourse)
        XCTAssertEqual(root.editingCourse, course)
        await fulfillment(of: [discarded], timeout: 3)
        XCTAssertFalse(try repository.getAllTables().contains { $0.id == newTableID })
        XCTAssertNil(try repository.getPeriodTable(newPeriodID))
        XCTAssertEqual(root.scheduleViewModel.state.selectedTableId, currentTableID)
        XCTAssertEqual(root.editingCourse?.tableId, course.tableId)

        root.handleBack()
        XCTAssertNil(root.overlayScreen)
        XCTAssertNil(root.editingCourse)
        XCTAssertEqual(try repository.getCourse(course.id), course)
        XCTAssertTrue(try repository.getAllTables().contains { $0.id == course.tableId })
    }
}
