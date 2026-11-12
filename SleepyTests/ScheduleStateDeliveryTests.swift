import XCTest
import Combine
@testable import Sleepy

@MainActor
final class ScheduleStateDeliveryTests: XCTestCase {
    private func wait(_ viewModel: ScheduleViewModel, _ condition: @escaping (ScheduleState) -> Bool) async {
        let ready = expectation(description: "Schedule state reflects the committed input")
        let observation = viewModel.$state.filter(condition).prefix(1).sink { _ in ready.fulfill() }
        await fulfillment(of: [ready], timeout: 3)
        observation.cancel()
        // Drain the GRDB/Combine delivery queue before counting the next operation.
        try? await Task.sleep(nanoseconds: 50_000_000)
    }

    func testPagingDeliveryAndSameIDEditsStayConsistent() async throws {
        let history = Sleepy.UndoManager.shared
        let originalDepth = history.maxDepth
        history.clear(); history.applyMaxDepth(0)
        defer { history.clear(); history.applyMaxDepth(originalDepth) }
        let db = try AppDatabase.inMemory()
        let repo = ScheduleRepository(db)
        let tableID = try repo.insertTable(TimeTableEntity(name: "Original", startDate: "2026-11-09", isDefault: true))
        let courseID = try repo.insertCourse(CourseEntity(groupId: "g", tableId: tableID,
            courseName: "Lesson", day: 1, startNode: 1, step: 2,
            startWeek: 1, endWeek: 20, color: "#FF6750A4"))
        let viewModel = ScheduleViewModel(repo: repo)
        var deliveries = 0
        let observation = viewModel.$state.dropFirst().sink { _ in deliveries += 1 }
        defer { observation.cancel() }
        await wait(viewModel) { $0.initialWeekSettled && $0.courses.first?.id == courseID }
        print("SCHEDULE_DELIVERY initial=\(deliveries)")
        deliveries = 0
        viewModel.changeWeek(4)
        XCTAssertEqual(viewModel.state.selectedWeek, 4)
        XCTAssertTrue(viewModel.state.weekSelectionManual)
        print("SCHEDULE_DELIVERY change_week=\(deliveries)")
        XCTAssertEqual(deliveries, 1, "A week change publishes one coherent snapshot")
        viewModel.changeWeek(4)
        XCTAssertEqual(deliveries, 1, "Selecting the already selected manual week is a no-op")

        deliveries = 0
        var table = try XCTUnwrap(repo.getTable(tableID))
        table.name = "Renamed"
        table.startDate = "2026-11-02"
        table.nodesPerDay = 9
        try repo.updateTable(table)
        await wait(viewModel) { $0.currentTable?.name == "Renamed" && $0.nodesPerDay == 9 }
        XCTAssertEqual(viewModel.state.currentTable?.startDate, "2026-11-02")
        XCTAssertEqual(viewModel.state.selectedWeek, 4)
        XCTAssertEqual(viewModel.state.courses.map(\.id), [courseID])
        print("SCHEDULE_DELIVERY same_table_edit=\(deliveries)")

        let periodID = try repo.insertPeriodTable(PeriodTableEntity(name: "Bound", nodesPerDay: 2,
            timeJson: #"[{"node":1,"start":"10:00","end":"10:45"},{"node":2,"start":"11:00","end":"11:45"}]"#))
        try repo.bindPeriodTable(timeTableId: tableID, periodTableId: periodID)
        await wait(viewModel) { $0.effectivePeriodTable?.id == periodID && $0.nodesPerDay == 2 }
        var period = try XCTUnwrap(repo.getPeriodTable(periodID))
        period.nodesPerDay = 3
        try repo.updatePeriodTable(period)
        await wait(viewModel) { $0.nodesPerDay == 3 }
        XCTAssertEqual(viewModel.state.selectedWeek, 4)
        XCTAssertEqual(viewModel.state.effectiveCurrentTable?.nodesPerDay, 3)

        var course = try XCTUnwrap(repo.getCourse(courseID))
        course.room = "Updated room"
        try repo.updateCourse(course)
        await wait(viewModel) { $0.courses.first?.room == "Updated room" }
        XCTAssertEqual(viewModel.state.selectedWeek, 4)
        try repo.deleteTable(tableID)
        await wait(viewModel) { $0.tables.isEmpty && $0.selectedTableId == nil }
        XCTAssertNil(viewModel.state.weekDisplayContext)
        XCTAssertTrue(viewModel.state.courses.isEmpty)
        XCTAssertTrue(viewModel.state.transfers.isEmpty)
        XCTAssertNil(viewModel.state.effectivePeriodTable)
    }

    func testShorterSemesterAndRemovedTransferClampManualWeekAndAutomaticTableSwitchResetsIt() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ScheduleRepository(db)
        let firstID = try repo.insertTable(TimeTableEntity(name: "Long", startDate: "2026-11-09", isDefault: true))
        let viewModel = ScheduleViewModel(repo: repo)
        await wait(viewModel) { $0.initialWeekSettled && $0.selectedTableId == firstID }
        viewModel.changeWeek(20)
        var first = try XCTUnwrap(repo.getTable(firstID))
        first.maxWeek = 2
        try repo.updateTable(first)
        await wait(viewModel) { $0.currentTable?.maxWeek == 2 && $0.selectedWeek == 2 }
        XCTAssertTrue(viewModel.state.weekSelectionManual)

        let store = AppPrefs.shared.sharedBackedStore
        let key = "holiday_transfer_\(firstID)"
        let original = store.object(forKey: key)
        defer {
            if let original { store.set(original, forKey: key) } else { store.removeObject(forKey: key) }
        }
        let transfer = HolidayTransferEntry(sourceDate: try XCTUnwrap(DateUtils.parseDate("2026-11-09")),
            targetDate: try XCTUnwrap(DateUtils.parseDate("2026-12-07")), segmentId: "extended")
        AppPrefs.shared.setHolidayTransfers(firstID, [transfer])
        viewModel.refreshTransfer()
        XCTAssertEqual(viewModel.state.displayMaxWeek, 5)
        viewModel.changeWeek(5)
        AppPrefs.shared.setHolidayTransfers(firstID, [])
        viewModel.refreshTransfer()
        XCTAssertEqual(viewModel.state.selectedWeek, 2)

        let shortID = try repo.insertTable(TimeTableEntity(name: "Short", startDate: "2026-11-09", maxWeek: 1))
        try repo.setDefault(shortID)
        await wait(viewModel) { $0.selectedTableId == shortID && $0.initialWeekSettled }
        XCTAssertEqual(viewModel.state.selectedWeek, 1)
        XCTAssertFalse(viewModel.state.weekSelectionManual)
    }
}
