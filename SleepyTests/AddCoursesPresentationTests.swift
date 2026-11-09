import XCTest
@testable import Sleepy

final class AddCoursesPresentationTests: XCTestCase {
    @MainActor
    func testAddCoursesCapturesAnExplicitTargetWithoutCreatingATable() throws {
        let repository = ScheduleRepository(try AppDatabase.inMemory())
        let root = AppRootViewModel(repository: repository)
        root.requestAddCourses(targetTableId: 42)
        XCTAssertEqual(root.currentTab, .manage)
        XCTAssertTrue(root.importRequested)
        XCTAssertEqual(root.requestedImportTargetTableId, 42)
        XCTAssertNil(root.overlayScreen)
        XCTAssertTrue(try repository.getAllTables().isEmpty)

        root.importRequested = false
        root.requestImport()
        XCTAssertTrue(root.importRequested)
        XCTAssertNil(root.requestedImportTargetTableId)
    }

    @MainActor
    func testExplicitManualTargetClearsForOrdinaryAddAndOtherRoutes() throws {
        let root = AppRootViewModel(repository: ScheduleRepository(try AppDatabase.inMemory()))
        let selectedTableID = root.scheduleViewModel.state.selectedTableId
        root.openManualAddCourse(targetTableId: 42)
        XCTAssertEqual(root.overlayScreen, .addCourse)
        XCTAssertEqual(root.addCourseTargetTableId, 42)
        XCTAssertEqual(root.scheduleViewModel.state.selectedTableId, selectedTableID)
        XCTAssertNil(root.editingCourse)

        root.navigator.openAddCourse()
        XCTAssertNil(root.addCourseTargetTableId)
        root.openManualAddCourse(targetTableId: 42)
        root.overlayScreen = .general
        XCTAssertNil(root.addCourseTargetTableId)
    }

    @MainActor
    func testMissingTargetCannotOpenTheNewTableImportFlow() throws {
        let root = AppRootViewModel(repository: ScheduleRepository(try AppDatabase.inMemory()))
        root.requestAddCourses(targetTableId: 0)
        XCTAssertFalse(root.importRequested)
        XCTAssertNil(root.requestedImportTargetTableId)
        XCTAssertEqual(root.currentTab, .schedule)
        root.openManualAddCourse(targetTableId: 0)
        XCTAssertNil(root.overlayScreen)
    }

    func testChangingAnExplicitTargetChangesTheCourseEditorIdentity() {
        XCTAssertNotEqual(CourseEditorIdentity(courseId: nil, initialSlot: nil, targetTableId: 41),
                          CourseEditorIdentity(courseId: nil, initialSlot: nil, targetTableId: 42))
        XCTAssertNotEqual(CourseEditorIdentity(courseId: nil, initialSlot: nil),
                          CourseEditorIdentity(courseId: nil, initialSlot: nil, targetTableId: 42))
    }
}
