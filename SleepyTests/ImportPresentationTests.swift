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

final class OverlayParentNavigationTests: XCTestCase {
    @MainActor
    private func makeRoot() throws -> (AppRootViewModel, ScheduleRepository) {
        let repository = ScheduleRepository(try AppDatabase.inMemory())
        return (AppRootViewModel(repository: repository), repository)
    }

    @MainActor
    func testNewTableSaveKeepsCurrentTableAndReturnsToItsParentList() async throws {
        let repository = ScheduleRepository(try AppDatabase.inMemory())
        let sourceID = try repository.insertTable(TimeTableEntity(
            name: "Current source", startDate: "2026-09-07", isDefault: true))
        let root = AppRootViewModel(repository: repository)
        let deadline = Date().addingTimeInterval(3)
        while root.scheduleViewModel.state.currentTable?.id != sourceID, Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(root.scheduleViewModel.state.currentTable?.id, sourceID)
        root.navigator.openAllTables()
        root.createNewTableThenEdit()
        let newID = try XCTUnwrap(root.pendingNewTableId)
        XCTAssertNotEqual(newID, sourceID)
        XCTAssertEqual(root.scheduleViewModel.state.selectedTableId, sourceID,
                       "Opening an unsaved table must not replace the current schedule")
        var saved = try XCTUnwrap(repository.getTable(newID))
        saved.name = "Saved draft"
        XCTAssertTrue(root.scheduleViewModel.updateTableRemappingCourses(saved, onFinish: {
            root.finishTableSave()
        }))
        XCTAssertEqual(root.overlayScreen, .allTables)
        XCTAssertNil(root.pendingNewTableId)
        XCTAssertNil(root.editTableId)
        XCTAssertEqual(root.scheduleViewModel.state.selectedTableId, sourceID)
        XCTAssertEqual(Set(try repository.getAllTables().map(\.id)), [sourceID, newID])
        XCTAssertEqual(try repository.getTable(newID)?.name, "Saved draft")
        XCTAssertEqual(try repository.getAllTables().filter(\.isDefault).map(\.id), [sourceID])
    }

    @MainActor
    func testTableEditorBackRestoresAllTablesBeforeReturningToMain() throws {
        let (root, _) = try makeRoot()
        root.navigator.openAllTables()
        root.navigator.openEditTable(tableId: 42)
        root.handleBack()
        XCTAssertEqual(root.overlayScreen, .allTables)
        XCTAssertNil(root.editTableId)
        root.handleBack()
        XCTAssertNil(root.overlayScreen)
    }

    @MainActor
    func testPeriodEditorBackRestoresPeriodTables() throws {
        let (root, _) = try makeRoot()
        root.navigator.openPeriodTables()
        root.navigator.openPeriodEdit(periodId: 42)
        root.handleBack()
        XCTAssertEqual(root.overlayScreen, .periodTables)
        XCTAssertNil(root.periodEditId)
        root.handleBack()
        XCTAssertNil(root.overlayScreen)
    }

    @MainActor
    func testCancelNewPeriodDiscardsItsRowAndRestoresPeriodTables() throws {
        let (root, repository) = try makeRoot()
        root.navigator.openPeriodTables()
        root.createPeriodTableThenEdit()
        let id = try XCTUnwrap(root.pendingNewPeriodTableId)
        XCTAssertNotNil(try repository.getPeriodTable(id))
        root.handleBack()
        XCTAssertEqual(root.overlayScreen, .periodTables)
        XCTAssertNil(root.pendingNewPeriodTableId)
        XCTAssertNil(root.periodEditId)
        XCTAssertNil(try repository.getPeriodTable(id))
    }

    @MainActor
    func testSaveNewPeriodKeepsItsRowAndRestoresPeriodTables() throws {
        let (root, repository) = try makeRoot()
        root.navigator.openPeriodTables()
        root.createPeriodTableThenEdit()
        let id = try XCTUnwrap(root.pendingNewPeriodTableId)
        let saved = try XCTUnwrap(repository.getPeriodTable(id))
        XCTAssertTrue(root.scheduleViewModel.updatePeriodTableContent(saved, onFinish: {
            root.finishPeriodTableSave()
        }))
        XCTAssertEqual(root.overlayScreen, .periodTables)
        XCTAssertNil(root.pendingNewPeriodTableId)
        XCTAssertNil(root.periodEditId)
        XCTAssertNotNil(try repository.getPeriodTable(id))
    }

    @MainActor
    func testNewTableCancelRestoresAllTablesAndDiscardsDraft() async throws {
        let (root, repository) = try makeRoot()
        root.navigator.openAllTables()
        root.createNewTableThenEdit()
        let id = try XCTUnwrap(root.pendingNewTableId)
        try await Task.sleep(nanoseconds: 600_000_000)
        XCTAssertEqual(root.overlayScreen, .editTable)
        root.handleBack()
        XCTAssertEqual(root.overlayScreen, .allTables)
        XCTAssertNil(root.pendingNewTableId)
        XCTAssertNil(root.editTableId)
        let deadline = Date().addingTimeInterval(3)
        while try repository.getAllTables().contains(where: { $0.id == id }), Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertFalse(try repository.getAllTables().contains { $0.id == id })
    }

    @MainActor
    func testLicenseBackRestoresAbout() throws {
        let (root, _) = try makeRoot()
        root.navigator.openAbout()
        root.navigator.openLicense()
        root.handleBack()
        XCTAssertEqual(root.overlayScreen, .about)
    }

    @MainActor
    func testPeriodHeaderBackRestoresAppearance() throws {
        let (root, _) = try makeRoot()
        root.navigator.openAppearance()
        root.navigator.openPeriodHeaderSettings()
        root.handleBack()
        XCTAssertEqual(root.overlayScreen, .theme)
    }

    @MainActor
    func testPopToMainClearsParentBeforeAnotherDirectEditor() throws {
        let (root, _) = try makeRoot()
        root.navigator.openAllTables()
        root.navigator.openEditTable(tableId: 42)
        root.navigator.popToMain()
        XCTAssertNil(root.overlayScreen)
        root.navigator.openPeriodEdit(periodId: 43)
        root.handleBack()
        XCTAssertNil(root.overlayScreen)
    }
}
