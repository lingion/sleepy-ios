import XCTest
@testable import Sleepy

final class ImportPresentationTests: XCTestCase {
    @MainActor
    func testImportRequestFromScheduleDoesNotCreateAnEmptyTable() throws {
        let db = try AppDatabase.inMemory()
        let repository = ScheduleRepository(db)
        let root = AppRootViewModel(repository: repository)
        root.requestImport()
        XCTAssertEqual(root.currentTab, .manage)
        XCTAssertTrue(root.importRequested)
        XCTAssertNil(root.overlayScreen)
        XCTAssertNil(root.pendingNewTableId)
        XCTAssertTrue(try repository.getAllTables().isEmpty)
    }

    @MainActor
    func testImportCanBeRequestedAgainWhileManageIsAlreadyVisible() throws {
        let db = try AppDatabase.inMemory()
        let repository = ScheduleRepository(db)
        let root = AppRootViewModel(repository: repository)
        root.currentTab = .manage
        root.requestImport()
        XCTAssertTrue(root.importRequested)
        root.importRequested = false // presentation consumed the first request
        root.requestImport()
        XCTAssertTrue(root.importRequested)
        XCTAssertEqual(root.currentTab, .manage)
        XCTAssertNil(root.pendingNewTableId)
        XCTAssertTrue(try repository.getAllTables().isEmpty)
    }

    @MainActor
    func testSuccessfulNewPeriodSaveClearsDiscardRouteAndKeepsPersistedTable() throws {
        let database = try AppDatabase.inMemory()
        let repository = ScheduleRepository(database)
        let root = AppRootViewModel(repository: repository)
        root.createPeriodTableThenEdit()
        let id = try XCTUnwrap(root.pendingNewPeriodTableId)
        var saved = try XCTUnwrap(repository.getPeriodTable(id))
        saved.name = "Saved bell schedule"
        XCTAssertTrue(root.scheduleViewModel.updatePeriodTableContent(saved, onFinish: {
            root.finishPeriodTableSave()
        }))
        XCTAssertNil(root.pendingNewPeriodTableId)
        XCTAssertNil(root.periodEditId)
        XCTAssertNil(root.overlayScreen)
        root.handleBack()
        XCTAssertEqual(try repository.getPeriodTable(id)?.name, saved.name)
    }
}
