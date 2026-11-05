import XCTest
import Combine
import GRDB
@testable import Sleepy

final class CourseDragViewModelTests: XCTestCase {
    private func utcCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)
        cal.firstWeekday = 2
        return cal
    }
    
    /// 用数据库结果作判据；不在测试里重写逆映射或课程拆分算法。
    private struct DatabaseState: Encodable {
        let tables: [TimeTableEntity]
        let periods: [PeriodTableEntity]
        let courses: [CourseEntity]
    }

    @MainActor
    private final class Fixture {
        let db: AppDatabase
        let repo: ScheduleRepository
        let tableId: Int64
        var vm: ScheduleViewModel!
        var writes = 0
        private var savedTransfers: [Int64: [HolidayTransferEntry]] = [:]

        init() throws {
            db = try AppDatabase.inMemory()
            repo = ScheduleRepository(db)
            // 避免内存库自增 ID=1 借用宿主真实课表的偏好键。
            tableId = Int64.random(in: 1_000_000_000...2_000_000_000)
            _ = try db.timeTableDao.insert(TimeTableEntity(
                name: "拖动集成测试", startDate: "2026-09-07", maxWeek: 20,
                nodesPerDay: 4, timeJson: """
                [{"node":1,"start":"08:00","end":"08:45"},
                 {"node":2,"start":"09:00","end":"09:45"},
                 {"node":3,"start":"10:00","end":"10:45"},
                 {"node":4,"start":"11:00","end":"11:45"}]
                """, isDefault: true, id: tableId))
            setTransfers([], tableId: tableId)
            repo.onDataChangedHook = { [weak self] in self?.writes += 1 }
            Sleepy.UndoManager.shared.clear()
        }

        func close() {
            vm = nil
            repo.onDataChangedHook = nil
            for (id, transfers) in savedTransfers {
                AppPrefs.shared.setHolidayTransfers(id, transfers)
            }
            Sleepy.UndoManager.shared.clear()
        }

        func setTransfers(_ transfers: [HolidayTransferEntry], tableId: Int64) {
            if savedTransfers[tableId] == nil {
                savedTransfers[tableId] = AppPrefs.shared.getHolidayTransfers(tableId)
            }
            AppPrefs.shared.setHolidayTransfers(tableId, transfers)
        }

        func seed(ownTime: Bool = false, tableId: Int64? = nil) throws -> CourseEntity {
            var course = CourseEntity(
                groupId: UUID().uuidString, tableId: tableId ?? self.tableId,
                courseName: "数据库系统", teacher: "陈老师", room: "A203", note: "保留原始备注",
                day: 2, startNode: ownTime ? 4 : 1, step: 2,
                startWeek: 1, endWeek: 9, color: "#FF123456", colorMode: CourseColorMode.CUSTOM,
                ownTime: ownTime, startTime: ownTime ? "08:35" : "",
                endTime: ownTime ? "08:40" : "", alias: "DB", credit: 3.5, level: 2)
            course.id = try db.courseDao.insert(course)
            return course
        }

        func rows() throws -> [CourseEntity] {
            try db.dbQueue.read { try CourseEntity.order(Column("id")).fetchAll($0) }
        }

        func snapshot() throws -> Data {
            let state = try db.dbQueue.read { db in
                DatabaseState(
                    tables: try TimeTableEntity.order(Column("id")).fetchAll(db),
                    periods: try PeriodTableEntity.order(Column("id")).fetchAll(db),
                    courses: try CourseEntity.order(Column("id")).fetchAll(db))
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            return try encoder.encode(state)
        }

        func source(_ course: CourseEntity, week: Int, day: Int? = nil) throws -> CourseDragContext.Source {
            let table = try XCTUnwrap(vm.state.effectiveCurrentTable)
            let cal = Calendar(identifier: .gregorian)
            var utcCal = cal
            utcCal.timeZone = TimeZone(secondsFromGMT: 0)
            utcCal.firstWeekday = 2
            let rendered = renderCoursesForWeek(table, week: week, courses: [course],
                transfers: vm.state.transfers, timeJson: table.timeJson, calendar: utcCal)
            let projection = try XCTUnwrap(rendered.first { day == nil || $0.day == day })
            let occurrence = try XCTUnwrap(CourseOccurrenceIdentity.resolve(startDate: table.startDate,
                maxWeek: table.maxWeek, displayWeek: week, displayDay: projection.day, transfers: vm.state.transfers))
            return CourseDragContext.Source(course: course, renderedCourse: projection,
                displayWeek: week, displayDay: projection.day, occurrence: occurrence,
                origin: .zero, grabOffsetY: 12, snapOffsetY: 18)
        }
    }

    @MainActor
    private func waitForState(_ vm: ScheduleViewModel,
                              matching predicate: @escaping (ScheduleState) -> Bool) async {
        let ready = expectation(description: "真实 GRDB 观察已发布所需 VM 状态")
        let token = vm.$state.filter(predicate).prefix(1).sink { _ in ready.fulfill() }
        defer { token.cancel() }
        await fulfillment(of: [ready], timeout: 3)
    }

    @MainActor
    private func load(_ fixture: Fixture, course: CourseEntity) async {
        fixture.vm = ScheduleViewModel(repo: fixture.repo)
        await waitForState(fixture.vm) {
            $0.selectedTableId == fixture.tableId && $0.initialWeekSettled
                && $0.courses.contains { $0.id == course.id }
        }
    }

    private func transfer(week: Int, from: Int, to: Int) throws -> HolidayTransferEntry {
        HolidayTransferEntry(
            sourceDate: try XCTUnwrap(DateUtils.dateOfWeek(
                startDate: "2026-09-07", week: week, dayOfWeek: from)),
            targetDate: try XCTUnwrap(DateUtils.dateOfWeek(
                startDate: "2026-09-07", week: week, dayOfWeek: to)),
            segmentId: "drag-test")
    }

    @MainActor
    func testTransferRenderCopyMovesOriginalIDAndCapturedWeekRatherThanVisibleWeek() async throws {
        let f = try Fixture()
        defer { f.close() }
        let original = try f.seed(ownTime: true)
        let unrelated = try f.seed()
        f.setTransfers([HolidayTransferEntry(
            sourceDate: try XCTUnwrap(DateUtils.dateOfWeek(startDate: "2026-09-07", week: 3, dayOfWeek: 2)),
            targetDate: try XCTUnwrap(DateUtils.dateOfWeek(startDate: "2026-09-07", week: 4, dayOfWeek: 7)),
            segmentId: "cross-week")], tableId: f.tableId)
        await load(f, course: original)
        let source = try f.source(original, week: 4, day: 7)
        XCTAssertEqual(source.course.id, original.id)
        XCTAssertEqual(source.renderedCourse.day, 7)
        XCTAssertEqual(source.renderedCourse.startNode, 1)
        XCTAssertEqual(source.renderedCourse.step, 1)
        XCTAssertEqual(source.course.day, 2)
        XCTAssertEqual(source.occurrence, .init(week: 3, day: 2))
        XCTAssertEqual(source.displayWeek, 4)
        XCTAssertEqual(original.day, 2)
        XCTAssertEqual(original.startNode, 4)
        f.setTransfers([], tableId: f.tableId)
        f.vm.refreshTransfer() // 捕获后映射变化，也不能重算源周成第四周。
        f.vm.changeWeek(8) // 拖动已翻页；不能用 VM 当前展示周或 lift 展示周代替 occurrence。
        let before = try f.snapshot()

        XCTAssertTrue(f.vm.moveDraggedOccurrence(source: source, targetWeek: 8,
                                                  displayDay: 4, targetNode: 3))

        let rows = try f.rows()
        let moved = try XCTUnwrap(rows.first { $0.groupId == original.groupId && $0.day == 4 })
        XCTAssertNotEqual(moved.id, original.id)
        XCTAssertEqual(moved.startWeek, 8)
        XCTAssertEqual(moved.endWeek, 8)
        XCTAssertEqual(moved.startNode, 3)
        XCTAssertEqual(moved.step, 2, "不能把归一化渲染副本的 step=1 写回库")
        XCTAssertEqual(moved.startTime, "10:00")
        XCTAssertEqual(moved.endTime, "10:05")
        XCTAssertEqual(moved.note, original.note)
        XCTAssertEqual(moved.room, original.room)
        XCTAssertEqual(moved.alias, original.alias)
        XCTAssertEqual(moved.credit, original.credit)
        XCTAssertEqual(moved.colorMode, original.colorMode)
        let remaining = rows.filter { $0.groupId == original.groupId && $0.day == 2 }
        XCTAssertEqual(remaining.map(\.startWeek).sorted(), [1, 4])
        XCTAssertEqual(remaining.map(\.endWeek).sorted(), [2, 9])
        XCTAssertTrue(remaining.allSatisfy { $0.startNode == 4 && $0.step == 2 && $0.startTime == "08:35" })
        XCTAssertEqual(rows.filter { $0.id == unrelated.id }.count, 1)
        XCTAssertEqual(rows.count, 4)
        XCTAssertEqual(f.writes, 1)
        let after = try f.snapshot()
        XCTAssertTrue(f.vm.undoLastChange())
        XCTAssertEqual(try f.snapshot(), before, "撤回恢复包括原 ID、其它课程和表配置的全库快照")
        XCTAssertFalse(f.vm.undoLastChange(), "一次拖动仅产生一个撤回单元")
        XCTAssertTrue(f.vm.redoLastUndo())
        XCTAssertEqual(try f.snapshot(), after)
    }

    @MainActor
    func testDestinationDateResolvesTrueWeekAndDayInsteadOfDisplayCoordinates() async throws {
        let f = try Fixture()
        defer { f.close() }
        let original = try f.seed()
        // 第七周周四投影到第八周周日；只需单条映射，不再要求旧逆映射双向交换。
        f.setTransfers([HolidayTransferEntry(
            sourceDate: try XCTUnwrap(DateUtils.dateOfWeek(startDate: "2026-09-07", week: 7, dayOfWeek: 4)),
            targetDate: try XCTUnwrap(DateUtils.dateOfWeek(startDate: "2026-09-07", week: 8, dayOfWeek: 7)),
            segmentId: "target-cross-week")], tableId: f.tableId)
        await load(f, course: original)
        let source = try f.source(original, week: 3)
        f.vm.changeWeek(3)
        let before = try f.snapshot()

        XCTAssertTrue(f.vm.moveDraggedOccurrence(source: source, targetWeek: 8,
                                                  displayDay: 7, targetNode: 3))

        let rows = try f.rows()
        let moved = try XCTUnwrap(rows.first { $0.startWeek == 7 && $0.endWeek == 7 })
        XCTAssertEqual(moved.day, 4, "存真实第七周周四，不能存展示第八周周日")
        XCTAssertEqual(moved.startNode, 3)
        XCTAssertEqual(rows.filter { $0.day == 7 }.count, 0)
        let rendered = renderCoursesForWeek(try XCTUnwrap(f.vm.state.currentTable), week: 8,
            courses: [moved], transfers: f.vm.state.transfers, timeJson: f.vm.state.effectiveCurrentTable?.timeJson,
            calendar: utcCalendar())
        XCTAssertEqual(rendered.first?.day, 7, "重新渲染后仍落在用户释放的星期日列")
        XCTAssertTrue(f.vm.undoLastChange())
        XCTAssertEqual(try f.snapshot(), before)
    }

    @MainActor
    func testHolidayEmptyColumnRejectsWithoutWritingOrReplacingExistingUndo() async throws {
        let f = try Fixture()
        defer { f.close() }
        let original = try f.seed()
        f.setTransfers([try transfer(week: 8, from: 4, to: 7)], tableId: f.tableId)
        await load(f, course: original)
        let beforeEdit = try f.snapshot()
        var edited = original
        edited.note = "先前可撤回的编辑"
        try f.repo.updateCourse(edited)
        let beforeDrop = try f.snapshot()
        f.writes = 0

        XCTAssertFalse(f.vm.moveDraggedOccurrence(source: try f.source(original, week: 3),
                                                   targetWeek: 8, displayDay: 4, targetNode: 3),
                        "新模型周日唯一映射源日；拒绝对象是已挪空的周四列")

        XCTAssertEqual(try f.snapshot(), beforeDrop)
        XCTAssertEqual(f.writes, 0)
        XCTAssertTrue(f.repo.canUndo)
        XCTAssertFalse(f.repo.canRedo)
        XCTAssertTrue(f.vm.undoLastChange())
        XCTAssertEqual(try f.snapshot(), beforeEdit, "拒绝拖动不能覆盖先前编辑的快照")
    }

    @MainActor
    func testHolidayEmptyColumnRejectsWithoutCreatingUndo() async throws {
        let f = try Fixture()
        defer { f.close() }
        let original = try f.seed()
        f.setTransfers([try transfer(week: 8, from: 4, to: 7)], tableId: f.tableId)
        await load(f, course: original)
        let before = try f.snapshot()

        XCTAssertFalse(f.vm.moveDraggedOccurrence(source: try f.source(original, week: 3),
                                                   targetWeek: 8, displayDay: 4, targetNode: 3))

        XCTAssertEqual(try f.snapshot(), before)
        XCTAssertEqual(f.writes, 0)
        XCTAssertFalse(f.repo.canUndo)
        XCTAssertFalse(f.repo.canRedo)
    }

    @MainActor
    func testTableSwitchRejectsCapturedSourceEvenForSamePositionDrop() async throws {
        let f = try Fixture()
        defer { f.close() }
        let original = try f.seed()
        let otherId = f.tableId + 1
        _ = try f.db.timeTableDao.insert(TimeTableEntity(name: "切换后的课表", startDate: "2026-09-07", id: otherId))
        f.setTransfers([], tableId: otherId)
        let other = try f.seed(tableId: otherId)
        await load(f, course: original)
        let source = try f.source(original, week: 3)
        f.vm.selectTable(otherId)
        // selectTable 的 setDefault 是异步 Task；先等它完成，才记录拒绝拖动的基线。
        await waitForState(f.vm) {
            $0.selectedTableId == otherId && $0.currentTable?.isDefault == true
                && $0.courses.contains { $0.id == other.id }
        }
        let before = try f.snapshot()
        f.writes = 0
        Sleepy.UndoManager.shared.clear()

        XCTAssertFalse(f.vm.moveDraggedOccurrence(source: source, targetWeek: 3,
                                                   displayDay: 2, targetNode: 1))
        XCTAssertFalse(f.vm.moveDraggedOccurrence(source: source, targetWeek: 8,
                                                   displayDay: 4, targetNode: 3))

        XCTAssertEqual(try f.snapshot(), before, "旧表源与新表课程均不写")
        XCTAssertEqual(f.writes, 0)
        XCTAssertFalse(f.repo.canUndo)
        XCTAssertFalse(f.repo.canRedo)
    }

    @MainActor
    func testRenderedSamePositionNoOpPreservesExistingUndoAndRedoOnMakeupDay() async throws {
        let f = try Fixture()
        defer { f.close() }
        let original = try f.seed(ownTime: true)
        f.setTransfers([try transfer(week: 3, from: 2, to: 7)], tableId: f.tableId)
        await load(f, course: original)
        let source = try f.source(original, week: 3)
        XCTAssertEqual(source.renderedCourse.day, 7)
        XCTAssertEqual(source.renderedCourse.startNode, 1)
        let beforeEdit = try f.snapshot()
        var edited = original
        edited.note = "先前编辑"
        try f.repo.updateCourse(edited)
        let afterEdit = try f.snapshot()
        f.writes = 0

        XCTAssertTrue(f.vm.moveDraggedOccurrence(source: source, targetWeek: 3,
                                                  displayDay: 7, targetNode: 1, targetStartTime: "08:35"))
        XCTAssertEqual(try f.snapshot(), afterEdit)
        XCTAssertEqual(f.writes, 0)
        XCTAssertTrue(f.vm.undoLastChange())
        XCTAssertEqual(try f.snapshot(), beforeEdit)
        f.writes = 0

        XCTAssertTrue(f.vm.moveDraggedOccurrence(source: source, targetWeek: 3,
                                                  displayDay: 7, targetNode: 1, targetStartTime: "08:35"))
        XCTAssertEqual(try f.snapshot(), beforeEdit)
        XCTAssertEqual(f.writes, 0)
        XCTAssertFalse(f.repo.canUndo)
        XCTAssertTrue(f.repo.canRedo)
        XCTAssertTrue(f.vm.redoLastUndo())
        XCTAssertEqual(try f.snapshot(), afterEdit, "原位释放不能清空 redo 或产生自己的 undo")
    }

    @MainActor
    func testSameWeekDayAndNodeWithDifferentExplicitStartIsNotNoOp() async throws {
        let f = try Fixture()
        defer { f.close() }
        let original = try f.seed(ownTime: true)
        await load(f, course: original)
        let source = try f.source(original, week: 3)
        XCTAssertEqual(source.displayWeek, 3)
        XCTAssertEqual(source.course.day, 2)
        XCTAssertEqual(source.renderedCourse.startNode, 1)
        XCTAssertEqual(source.course.startTime, "08:35")
        let before = try f.snapshot()

        XCTAssertTrue(f.vm.moveDraggedOccurrence(source: source, targetWeek: 3,
                                                  displayDay: 2, targetNode: 1, targetStartTime: "08:30"))

        let rows = try f.rows()
        let selectedWeek = rows.filter { $0.inWeek(3) }
        XCTAssertEqual(selectedWeek.count, 1)
        let moved = try XCTUnwrap(selectedWeek.first)
        XCTAssertEqual(moved.startWeek, 3)
        XCTAssertEqual(moved.endWeek, 3)
        XCTAssertEqual(moved.day, 2)
        XCTAssertEqual(moved.startNode, 1)
        XCTAssertEqual(moved.startTime, "08:30", "同一网格位置的显式改时刻必须写库")
        XCTAssertEqual(moved.endTime, "08:35", "仍保持五分钟时长")
        XCTAssertEqual(moved.step, original.step)
        XCTAssertTrue(moved.ownTime)
        let remaining = rows.filter { !$0.inWeek(3) }
        XCTAssertEqual(remaining.map(\.startWeek).sorted(), [1, 4])
        XCTAssertEqual(remaining.map(\.endWeek).sorted(), [2, 9])
        XCTAssertTrue(remaining.allSatisfy {
            $0.day == 2 && $0.startTime == "08:35" && $0.endTime == "08:40"
        })
        XCTAssertEqual(f.writes, 1)
        let after = try f.snapshot()
        XCTAssertNotEqual(after, before)
        XCTAssertTrue(f.vm.undoLastChange())
        XCTAssertEqual(try f.snapshot(), before)
        XCTAssertFalse(f.vm.undoLastChange(), "改时刻只产生一个撤回单元")
        XCTAssertTrue(f.vm.redoLastUndo())
        XCTAssertEqual(try f.snapshot(), after)
    }

    @MainActor
    func testDeletedSourceRejectsSamePositionWithoutReplacingPriorUndo() async throws {
        let f = try Fixture()
        defer { f.close() }
        let original = try f.seed()
        await load(f, course: original)
        let source = try f.source(original, week: 3)
        let before = try f.snapshot()
        try f.repo.deleteCourse(original.id)
        let afterDelete = try f.snapshot()
        f.writes = 0
        XCTAssertFalse(f.vm.moveDraggedOccurrence(source: source, targetWeek: 3,
            displayDay: 2, targetNode: 1))
        XCTAssertEqual(try f.snapshot(), afterDelete)
        XCTAssertEqual(f.writes, 0)
        XCTAssertTrue(f.vm.undoLastChange())
        XCTAssertEqual(try f.snapshot(), before)
    }

    @MainActor
    func testHorizontalOwnTimeMoveForwardsExactStartAndPreservesDuration() async throws {
        let f = try Fixture()
        defer { f.close() }
        let original = try f.seed(ownTime: true)
        await load(f, course: original)
        let source = try f.source(original, week: 3)
        XCTAssertEqual(source.renderedCourse.startNode, 1)
        let before = try f.snapshot()

        XCTAssertTrue(f.vm.moveDraggedOccurrence(source: source, targetWeek: 3,
                                                  displayDay: 4, targetNode: 1, targetStartTime: "08:35"))

        let rows = try f.rows()
        let moved = try XCTUnwrap(rows.first { $0.day == 4 })
        XCTAssertEqual(moved.startWeek, 3)
        XCTAssertEqual(moved.endWeek, 3)
        XCTAssertEqual(moved.startNode, 1)
        XCTAssertEqual(moved.startTime, "08:35", "丢失参数会错误吸附到 08:00")
        XCTAssertEqual(moved.endTime, "08:40")
        XCTAssertEqual(moved.step, 2)
        XCTAssertTrue(moved.ownTime)
        XCTAssertEqual(rows.filter { $0.day == 2 && $0.inWeek(3) }.count, 0)
        XCTAssertEqual(f.writes, 1)
        let after = try f.snapshot()
        XCTAssertTrue(f.vm.undoLastChange())
        XCTAssertEqual(try f.snapshot(), before)
        XCTAssertTrue(f.vm.redoLastUndo())
        XCTAssertEqual(try f.snapshot(), after)
    }
}
