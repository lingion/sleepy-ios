import XCTest
@testable import Sleepy

final class PeriodTableEdgeMigrationParityTests: XCTestCase {
    private typealias Row = TimeTableUtils.TimeSlotRow
    private var oldJSON: String { json([
        Row(node: 1, start: "08:00", end: "08:45"), Row(node: 2, start: "09:00", end: "09:45"),
        Row(node: 3, start: "12:00", end: "12:45", edgeClass: .after),
        Row(node: 0, start: "06:00", end: "06:45", edgeClass: .before)]) }
    private var newJSON: String { json([
        Row(node: 0, start: "05:00", end: "05:45", edgeClass: .before),
        Row(node: 1, start: "07:00", end: "07:45"), Row(node: 2, start: "08:00", end: "08:45"),
        Row(node: 3, start: "09:00", end: "09:45"),
        Row(node: 4, start: "13:00", end: "13:45", edgeClass: .after)]) }
    private func json(_ rows: [Row]) -> String { TimeTableUtils.buildTimeJsonFromRows(rows) }
    private func course(_ node: Int, tableId: Int64 = 1, edge: Bool = true, step: Int = 1) -> CourseEntity {
        CourseEntity(groupId: "edge-\(node)", tableId: tableId, courseName: "课程", teacher: "教师",
            room: "教室", note: "保留", day: 1, startNode: node, step: step, startWeek: 1,
            endWeek: 16, color: "#FF6750A4", isIrregularNode: edge)
    }

    func testEqualEdgeCountsTrackIdentityEvenWhenClocksChangeAndPreserveEveryOtherField() {
        let original = [course(3), course(0), course(2, edge: false)]
        let migrated = remapRenumberedEdgeCourses(original, oldTimeJson: oldJSON, newTimeJson: newJSON)
        var expected = original
        expected[0].startNode = 4
        XCTAssertEqual(migrated, expected)
    }

    func testDeletedEdgesOnlyMigrateUniqueSurvivorsAndNeverTheirNeighbour() {
        let old = json([Row(node: 3, start: "12:00", end: "12:45", edgeClass: .after),
                        Row(node: 4, start: "13:00", end: "13:45", edgeClass: .after)])
        let next = json([Row(node: 5, start: "13:00", end: "13:45", edgeClass: .after)])
        XCTAssertEqual(remapRenumberedEdgeCourses([course(3), course(4)], oldTimeJson: old, newTimeJson: next).map(\.startNode), [3, 5])
        XCTAssertEqual(remapRenumberedEdgeCourses([course(3, step: 2)], oldTimeJson: old, newTimeJson: next).map(\.startNode), [3])
        let ambiguous = json([Row(node: 5, start: "13:00", end: "13:45", edgeClass: .after),
                              Row(node: 6, start: "13:00", end: "13:45", edgeClass: .after),
                              Row(node: 7, start: "14:00", end: "14:45", edgeClass: .after)])
        XCTAssertEqual(remapRenumberedEdgeCourses([course(4)], oldTimeJson: old, newTimeJson: ambiguous).map(\.startNode), [4])
    }

    func testManualEdgeDeletionFreezesOldClockAndAvoidsTheSurvivorsReusedNode() {
        let rows = [Row(node: 1, start: "08:00", end: "08:45"),
                    Row(node: 2, start: "09:00", end: "09:45"),
                    Row(node: 3, start: "12:00", end: "12:45", edgeClass: .after),
                    Row(node: 4, start: "13:00", end: "13:45", edgeClass: .after)]
        let nextRows = TimeTableUtils.removeAndRenumber(rows, node: 3)
        XCTAssertEqual(nextRows.map(\.node), [1, 2, 3])
        var privateCourse = course(3)
        privateCourse.ownTime = true
        privateCourse.startTime = "12:15"
        privateCourse.endTime = "12:35"
        let original = [course(3), course(4), privateCourse]
        let migrated = remapRenumberedEdgeCourses(original, oldTimeJson: json(rows), newTimeJson: json(nextRows))
        var frozen = original[0]
        frozen.startNode = 5
        frozen.ownTime = true
        frozen.isIrregularTime = true
        frozen.startTime = "12:00"
        frozen.endTime = "12:45"
        var survivor = original[1]
        survivor.startNode = 3
        privateCourse.startNode = 5
        XCTAssertEqual(migrated, [frozen, survivor, privateCourse])
        XCTAssertFalse(nextRows.contains { $0.node == migrated[0].startNode })
    }

    func testDeletedBeforeEdgeRetainsFreeAnchorAndExistingPrivateTimeFlags() {
        let rows = [Row(node: -1, start: "05:00", end: "05:45", edgeClass: .before),
                    Row(node: 0, start: "06:00", end: "06:45", edgeClass: .before),
                    Row(node: 1, start: "08:00", end: "08:45")]
        let next = json(TimeTableUtils.removeAndRenumber(rows, node: -1))
        var privateCourse = course(-1)
        privateCourse.ownTime = true
        privateCourse.startTime = "05:10"
        privateCourse.endTime = "05:30"
        let migrated = remapRenumberedEdgeCourses([course(-1), privateCourse], oldTimeJson: json(rows), newTimeJson: next)
        XCTAssertEqual(migrated[0].startNode, -1)
        XCTAssertTrue(migrated[0].isIrregularNode)
        XCTAssertTrue(migrated[0].ownTime)
        XCTAssertTrue(migrated[0].isIrregularTime)
        XCTAssertEqual(migrated[0].startTime, "05:00")
        XCTAssertEqual(migrated[0].endTime, "05:45")
        XCTAssertEqual(migrated[1], privateCourse)
    }

    func testManualEdgeDeletionPersistsFrozenClockAcrossSharedAndPrivateSavesWithUndo() throws {
        let rows = [Row(node: 1, start: "08:00", end: "08:45"),
                    Row(node: 2, start: "09:00", end: "09:45"),
                    Row(node: 3, start: "12:00", end: "12:45", edgeClass: .after),
                    Row(node: 4, start: "13:00", end: "13:45", edgeClass: .after)]
        let old = json(rows)
        let next = json(TimeTableUtils.removeAndRenumber(rows, node: 3))
        for entry in ["update", "save", "metadata", "bind", "sync", "independent", "detachCopy", "createNew"] {
            let history = Sleepy.UndoManager.shared
            let previousDepth = history.maxDepth
            history.clear()
            history.applyMaxDepth(5)
            defer { history.clear(); history.applyMaxDepth(previousDepth) }
            let repo = ScheduleRepository(try AppDatabase.inMemory())
            let periodId = try repo.insertPeriodTable(PeriodTableEntity(name: "共享", nodesPerDay: 2, timeJson: old))
            let tid = try repo.insertTable(TimeTableEntity(name: "课表", startDate: "2026-09-07",
                nodesPerDay: 2, timeJson: old, periodTableId: entry == "independent" ? nil : periodId))
            let removedId = try repo.insertCourse(course(3, tableId: tid))
            let survivorId = try repo.insertCourse(course(4, tableId: tid))
            let other = try repo.insertTable(TimeTableEntity(name: "其他绑定", startDate: "2026-09-07", periodTableId: periodId))
            let otherId = try repo.insertCourse(course(3, tableId: other))
            let original = try XCTUnwrap(repo.getCourse(removedId))
            let otherOriginal = try XCTUnwrap(repo.getCourse(otherId))
            var edited = try XCTUnwrap(repo.getTable(tid))
            edited.timeJson = next
            var period = try XCTUnwrap(repo.getPeriodTable(periodId))
            period.timeJson = next
            history.clear()
            switch entry {
            case "update": try repo.updatePeriodTable(period)
            case "save": _ = try repo.savePeriodTable(period)
            case "metadata": try repo.updateTableMetadataWithPeriodTable(table: edited, periodTable: period)
            case "bind": try repo.updateTableMetadataAndBind(table: edited, periodTableId: periodId, periodContent: period)
            case "sync": try repo.executeScheduleEditPolicy(editedTable: edited, draft: period, policy: .sync)
            case "independent": try repo.updateTableRemappingCourses(edited)
            default: try repo.executeScheduleEditPolicy(editedTable: edited, draft: period,
                policy: entry == "detachCopy" ? .detachCopy : .createNew)
            }
            var expected = original
            expected.startNode = 5
            expected.ownTime = true
            expected.isIrregularTime = true
            expected.startTime = "12:00"
            expected.endTime = "12:45"
            XCTAssertEqual(try repo.getCourse(removedId), expected, entry)
            XCTAssertEqual(try repo.getCourse(survivorId)?.startNode, 3, entry)
            let shared = ["update", "save", "metadata", "bind", "sync"].contains(entry)
            if shared {
                var otherExpected = expected
                otherExpected.id = otherOriginal.id
                otherExpected.tableId = otherOriginal.tableId
                XCTAssertEqual(try repo.getCourse(otherId), otherExpected, entry)
            } else {
                XCTAssertEqual(try repo.getCourse(otherId), otherOriginal, entry)
                XCTAssertEqual(try repo.getPeriodTable(periodId)?.timeJson, old, entry)
            }
            XCTAssertTrue(try repo.restoreLastSnapshot(), entry)
            XCTAssertEqual(try repo.getCourse(removedId), original, entry)
            XCTAssertEqual(try repo.getCourse(otherId), otherOriginal, entry)
            XCTAssertTrue(try repo.redoLastUndo(), entry)
            XCTAssertEqual(try repo.getCourse(removedId), expected, entry)
        }
    }

    func testDeletedEdgeClockPersistsEvenWhenItsOrphanAnchorDoesNotChange() throws {
        let history = Sleepy.UndoManager.shared
        let previousDepth = history.maxDepth
        history.clear()
        history.applyMaxDepth(5)
        defer { history.clear(); history.applyMaxDepth(previousDepth) }
        let rows = [Row(node: -1, start: "05:00", end: "05:45", edgeClass: .before),
                    Row(node: 0, start: "06:00", end: "06:45", edgeClass: .before),
                    Row(node: 1, start: "08:00", end: "08:45")]
        let old = json(rows)
        let next = json(TimeTableUtils.removeAndRenumber(rows, node: -1))
        for shared in [false, true] {
            let repo = ScheduleRepository(try AppDatabase.inMemory())
            let periodId = try repo.insertPeriodTable(PeriodTableEntity(name: "共享", timeJson: old))
            let tid = try repo.insertTable(TimeTableEntity(name: "课表", startDate: "2026-09-07",
                timeJson: old, periodTableId: shared ? periodId : nil))
            let id = try repo.insertCourse(course(-1, tableId: tid))
            if shared {
                var period = try XCTUnwrap(repo.getPeriodTable(periodId))
                period.timeJson = next
                try repo.updatePeriodTable(period)
            } else {
                var table = try XCTUnwrap(repo.getTable(tid))
                table.timeJson = next
                try repo.updateTableRemappingCourses(table)
            }
            let saved = try XCTUnwrap(repo.getCourse(id))
            XCTAssertEqual(saved.startNode, -1)
            XCTAssertTrue(saved.ownTime)
            XCTAssertTrue(saved.isIrregularTime)
            XCTAssertEqual(saved.startTime, "05:00")
            XCTAssertEqual(saved.endTime, "05:45")
        }
    }

    func testAllSharedSaveEntrypointsMigrateEveryOwnerAndUndoAsOneAction() throws {
        for entry in ["update", "save", "metadata", "bind", "sync"] {
            let history = Sleepy.UndoManager.shared
            let previousDepth = history.maxDepth
            history.clear()
            history.applyMaxDepth(5)
            defer { history.clear(); history.applyMaxDepth(previousDepth) }
            let db = try AppDatabase.inMemory()
            let repo = ScheduleRepository(db)
            let periodId = try repo.insertPeriodTable(PeriodTableEntity(name: "共享", nodesPerDay: 2, timeJson: oldJSON))
            var tableIds: [Int64] = []
            var edgeIds: [Int64] = []
            var standardIds: [Int64] = []
            for name in ["一", "二"] {
                let tid = try repo.insertTable(TimeTableEntity(name: name, startDate: "2026-09-07", periodTableId: periodId))
                tableIds.append(tid)
                edgeIds.append(try repo.insertCourse(course(3, tableId: tid)))
                standardIds.append(try repo.insertCourse(course(2, tableId: tid, edge: false)))
            }
            var period = try XCTUnwrap(repo.getPeriodTable(periodId))
            period.timeJson = newJSON
            period.nodesPerDay = 3
            let edited = try XCTUnwrap(repo.getTable(tableIds[0]))
            history.clear()
            switch entry {
            case "update": try repo.updatePeriodTable(period)
            case "save": XCTAssertEqual(try repo.savePeriodTable(period), 2)
            case "metadata": try repo.updateTableMetadataWithPeriodTable(table: edited, periodTable: period)
            case "bind": try repo.updateTableMetadataAndBind(table: edited, periodTableId: periodId, periodContent: period)
            default: try repo.executeScheduleEditPolicy(editedTable: edited, draft: period, policy: .sync)
            }
            let reopened = ScheduleRepository(db)
            XCTAssertEqual(try reopened.getPeriodTable(periodId)?.timeJson, newJSON, entry)
            for id in edgeIds { XCTAssertEqual(try reopened.getCourse(id)?.startNode, 4, entry) }
            for id in standardIds { XCTAssertEqual(try reopened.getCourse(id)?.startNode, 2, entry) }
            XCTAssertTrue(try repo.restoreLastSnapshot(), entry)
            XCTAssertEqual(try repo.getPeriodTable(periodId)?.timeJson, oldJSON, entry)
            for id in edgeIds { XCTAssertEqual(try repo.getCourse(id)?.startNode, 3, entry) }
            XCTAssertFalse(try repo.restoreLastSnapshot(), entry)
            XCTAssertTrue(try repo.redoLastUndo(), entry)
            for id in edgeIds { XCTAssertEqual(try repo.getCourse(id)?.startNode, 4, entry) }
        }
    }

    func testIndependentDetachAndCreateNewKeepAbsoluteStandardPolicyAndEdgeIdentity() throws {
        for entry in ["independent", "detachCopy", "createNew"] {
            let history = Sleepy.UndoManager.shared
            let previousDepth = history.maxDepth
            history.clear()
            history.applyMaxDepth(5)
            defer { history.clear(); history.applyMaxDepth(previousDepth) }
            let db = try AppDatabase.inMemory()
            let repo = ScheduleRepository(db)
            let periodId = try repo.insertPeriodTable(PeriodTableEntity(name: "共享", nodesPerDay: 2, timeJson: oldJSON))
            let tid = try repo.insertTable(TimeTableEntity(name: "课表", startDate: "2026-09-07", nodesPerDay: 2,
                timeJson: entry == "independent" ? oldJSON : "[]", periodTableId: entry == "independent" ? nil : periodId))
            let edgeId = try repo.insertCourse(course(3, tableId: tid))
            let standardId = try repo.insertCourse(course(2, tableId: tid, edge: false))
            var edited = try XCTUnwrap(repo.getTable(tid))
            edited.timeJson = newJSON
            edited.nodesPerDay = 3
            let draft = PeriodTableEntity(name: "新作息", nodesPerDay: 3, timeJson: newJSON)
            history.clear()
            if entry == "independent" { try repo.updateTableRemappingCourses(edited) }
            else { try repo.executeScheduleEditPolicy(editedTable: edited, draft: draft,
                policy: entry == "detachCopy" ? .detachCopy : .createNew) }
            XCTAssertEqual(try ScheduleRepository(db).getCourse(edgeId)?.startNode, 4, entry)
            XCTAssertEqual(try repo.getCourse(standardId)?.startNode, 3, entry)
            XCTAssertEqual(try repo.getPeriodTable(periodId)?.timeJson, oldJSON, entry)
            XCTAssertTrue(try repo.restoreLastSnapshot(), entry)
            XCTAssertEqual(try repo.getCourse(edgeId)?.startNode, 3, entry)
            XCTAssertEqual(try repo.getCourse(standardId)?.startNode, 2, entry)
            XCTAssertTrue(try repo.redoLastUndo(), entry)
            XCTAssertEqual(try repo.getCourse(edgeId)?.startNode, 4, entry)
        }
    }
}
