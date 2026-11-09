import XCTest
@testable import Sleepy

final class AddCoursesImportTests: XCTestCase {
    override func setUp() { super.setUp(); Sleepy.UndoManager.shared.clear() }
    override func tearDown() { Sleepy.UndoManager.shared.clear(); super.tearDown() }

    private let oldTimes = #"[{"node":1,"start":"08:00","end":"08:45"}]"#
    private let boundTimes = #"[{"node":1,"start":"09:00","end":"09:45"},{"node":2,"start":"10:00","end":"10:45"}]"#

    private func course(_ table: Int64 = 0, group: String, name: String = "Math", teacher: String = "Ada", day: Int = 1, room: String = "") -> CourseEntity {
        CourseEntity(groupId: group, tableId: table, courseName: name, teacher: teacher, room: room,
                     day: day, startNode: 1, step: 1, startWeek: 1, endWeek: 16, color: "#FF6750A4")
    }

    func testGroupIdentityKeepsAuthoritativePartitionsAndTrimsFallback() {
        let rows = [course(group: "a"), course(group: "a", day: 2, room: " B "),
                    course(group: "b"), course(group: " ", name: " Math ", teacher: " Ada "),
                    course(group: "", room: "A")]
        let groups = AddCoursesImport.groups(rows)
        XCTAssertEqual(groups.count, 3)
        XCTAssertEqual(groups.first { $0.id == "a" }?.rows.count, 2)
        XCTAssertEqual(groups.first { $0.id == "a" }?.rooms, ["B"])
        XCTAssertEqual(AddCoursesImport.groupKey(rows[3]), AddCoursesImport.groupKey(rows[4]))
        XCTAssertNotEqual(AddCoursesImport.groupKey(rows[0]), AddCoursesImport.groupKey(rows[2]))
    }

    func testFilteringKeepsWholeGroupsAndParserMetadata() throws {
        let rows = [course(group: "a"), course(group: "a", day: 2), course(group: "b")]
        let result = ScheduleParser.ParseResult(tableName: "Source", startDate: "2026-11-02", courses: rows,
                                               timeJson: boundTimes, nodesPerDay: 2, droppedLines: ["bad"],
                                               warnings: ["warning"], maxWeek: 16, groupIdsAuthoritative: true,
                                               periodTable: .init(sourceId: 3, name: "Bell", nodesPerDay: 2, timeJson: boundTimes))
        let filtered = try AddCoursesImport.filtered(result, selectedKeys: ["a"])
        XCTAssertEqual(filtered.courses.map(\.day), [1, 2])
        XCTAssertEqual(filtered.tableName, result.tableName)
        XCTAssertEqual(filtered.timeJson, boundTimes)
        XCTAssertEqual(filtered.nodesPerDay, 2)
        XCTAssertEqual(filtered.maxWeek, 16)
        XCTAssertEqual(filtered.droppedLines, ["bad"])
        XCTAssertEqual(filtered.warnings, ["warning"])
        XCTAssertTrue(filtered.groupIdsAuthoritative)
        XCTAssertEqual(filtered.periodTable?.sourceId, 3)
        XCTAssertThrowsError(try AddCoursesImport.filtered(result, selectedKeys: []))
        XCTAssertThrowsError(try AddCoursesImport.filtered(result, selectedKeys: ["unknown"]))
    }

    func testCourseImportDecisionDefaultsToBackupAndExcludesConflicts() {
        let decision = CourseImportDecision()
        XCTAssertTrue(decision.backupOriginal)
        XCTAssertFalse(decision.appendConflicts)
    }

    func testEmptyAndPeriodOnlyDataAreRejected() {
        let result = ScheduleParser.ParseResult(tableName: "Bell", startDate: "", courses: [], timeJson: boundTimes,
                                               periodTable: .init(sourceId: 0, name: "Bell", nodesPerDay: 2, timeJson: boundTimes))
        XCTAssertThrowsError(try AddCoursesImport.validate(result))
    }

    func testExistingSourceUsesEffectiveBoundPeriodsAndPreservesGroups() throws {
        let repo = ScheduleRepository(try AppDatabase.inMemory())
        let source = try repo.insertTable(.init(name: "Source", startDate: "2026-11-02", maxWeek: 18, nodesPerDay: 1, timeJson: oldTimes))
        let target = try repo.insertTable(.init(name: "Target", startDate: "2026-11-02"))
        let period = try repo.insertPeriodTable(.init(name: "Bound", nodesPerDay: 2, timeJson: boundTimes))
        try repo.bindPeriodTable(timeTableId: source, periodTableId: period)
        _ = try repo.insertCoursesKeepingGroups([course(source, group: "partition-a"), course(source, group: "partition-b")])
        let result = try AddCoursesImport.source(repository: repo, sourceTableId: source, targetTableId: target)
        XCTAssertEqual(result.timeJson, boundTimes)
        XCTAssertEqual(result.nodesPerDay, 2)
        XCTAssertEqual(result.maxWeek, 18)
        XCTAssertEqual(result.courses.map(\.groupId).sorted(), ["partition-a", "partition-b"])
        XCTAssertTrue(result.groupIdsAuthoritative)
        XCTAssertThrowsError(try AddCoursesImport.source(repository: repo, sourceTableId: target, targetTableId: target))
        XCTAssertThrowsError(try AddCoursesImport.source(repository: repo, sourceTableId: source, targetTableId: 999))
    }

    func testSelectionAndAppendKeepCapturedTargetWhenSelectedTableChanges() throws {
        let repo = ScheduleRepository(try AppDatabase.inMemory())
        let target = try repo.insertTable(.init(name: "Captured", startDate: "2026-11-02", nodesPerDay: 1, timeJson: oldTimes))
        let other = try repo.insertTable(.init(name: "Now selected", startDate: "2026-10-05", nodesPerDay: 1, timeJson: oldTimes))
        let source = try repo.insertTable(.init(name: "Source", startDate: "2026-11-02", nodesPerDay: 2, timeJson: boundTimes))
        _ = try repo.insertCoursesKeepingGroups([course(source, group: "chosen"), course(source, group: "excluded", day: 2)])
        let parsed = try AddCoursesImport.source(repository: repo, sourceTableId: source, targetTableId: target)
        let filtered = try AddCoursesImport.filtered(parsed, selectedKeys: ["chosen"])
        let preview = try XCTUnwrap(ImportSheet.buildImportPreview(filtered, targetTableId: target, repository: repo))
        XCTAssertEqual(preview.targetTableId, target)
        XCTAssertEqual(preview.targetTableName, "Captured")
        var imported = false
        let saved = ImportSheet.applyCourseImport(preview: preview,
                                                  decision: .init(backupOriginal: false, appendConflicts: true),
                                                  onImported: { imported = true }, onError: { XCTFail($0) }, repository: repo)
        XCTAssertEqual(saved, target)
        XCTAssertTrue(imported)
        XCTAssertEqual(try repo.getCourses(target).map(\.day), [1])
        XCTAssertNotEqual(try repo.getCourses(target).first?.groupId, "chosen", "Copies form a new course group in the target")
        XCTAssertTrue(try repo.getCourses(other).isEmpty)
        XCTAssertEqual(try repo.getCourses(source).count, 2)
        XCTAssertEqual(try repo.getTable(other)?.startDate, "2026-10-05")
        XCTAssertEqual(try repo.getAllTables().count, 3)
    }

    func testTextPreviewUsesExplicitTargetInsteadOfMutableSelection() throws {
        let repo = ScheduleRepository(try AppDatabase.inMemory())
        let target = try repo.insertTable(.init(name: "Captured", startDate: "2026-11-02"))
        let other = try repo.insertTable(.init(name: "Other", startDate: "2026-11-02"))
        var state = ScheduleState()
        state.selectedTableId = other
        let preview = try XCTUnwrap(ImportSheet.buildImportPreview("#sleepy-v1\nTSource|2026-11-02|16|12\nCMath|1|1-2|1-16", state,
                                                                   targetTableId: target, repository: repo,
                                                                   onError: { XCTFail($0) }))
        XCTAssertEqual(preview.targetTableId, target)
        XCTAssertEqual(preview.targetTableName, "Captured")
        XCTAssertTrue(preview.parseResult.courses.allSatisfy { $0.tableId == target })
    }
}
