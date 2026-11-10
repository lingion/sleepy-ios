import XCTest
import GRDB
@testable import Sleepy

final class PurePeriodImportFailureTests: XCTestCase {
    func testFailedInsertKeepsImportedDraftAndDoesNotPublishSuccessThenRetryCommits() throws {
        let history = Sleepy.UndoManager.shared
        let previousDepth = history.maxDepth
        history.clear()
        history.restoring = false
        history.applyMaxDepth(5)
        defer {
            history.clear()
            history.restoring = false
            history.applyMaxDepth(previousDepth)
        }
        let db = try AppDatabase.inMemory()
        let repo = ScheduleRepository(db)
        let json = #"[{"node":1,"start":"08:00","end":"08:45"},{"node":2,"start":"09:00","end":"09:45"}]"#
        let parsed = ScheduleParser.ParsedPeriodTable(sourceId: 0, name: "导入作息",
                                                      nodesPerDay: 2, timeJson: json)
        let result = ScheduleParser.ParseResult(tableName: parsed.name, startDate: "", courses: [],
                                                timeJson: json, nodesPerDay: 2, periodTable: parsed)
        let draft = ImportPreview(targetTableId: 0, targetTableName: "", parseResult: result,
                                  existingCourses: [], conflicts: [])
        var session = ImportPreviewSession()
        session.replacePreview(draft)
        var imported = 0
        var failure: String?
        try db.dbQueue.write {
            try $0.execute(sql: "CREATE TRIGGER reject_period_import BEFORE INSERT ON period_tables BEGIN SELECT RAISE(ABORT, 'injected period import failure'); END;")
        }

        let failed = session.completeImportIfSaved {
            ImportSheet.applyPurePeriodImport(name: "用户修改的作息名称", parsed: parsed, repository: repo,
                                               onImported: { imported += 1 }, onError: { failure = $0 })
        }
        XCTAssertFalse(failed)
        XCTAssertNotNil(failure)
        XCTAssertEqual(imported, 0, "A failed insert must not invoke the root import success callback")
        XCTAssertEqual(session.preview?.id, draft.id, "Keep the same dialog instance and its edited name available for retry")
        XCTAssertEqual(session.preview?.parseResult.periodTable?.timeJson, json)
        XCTAssertEqual(session.preview?.parseResult.periodTable?.nodesPerDay, 2)
        XCTAssertTrue(try repo.getAllPeriodTables().isEmpty)
        XCTAssertTrue(try repo.getAllTables().isEmpty)
        XCTAssertFalse(history.hasSnapshot)

        try db.dbQueue.write { try $0.execute(sql: "DROP TRIGGER reject_period_import") }
        let succeeded = session.completeImportIfSaved {
            ImportSheet.applyPurePeriodImport(name: "用户修改的作息名称", parsed: parsed, repository: repo,
                                               onImported: { imported += 1 }, onError: { failure = $0 })
        }
        XCTAssertTrue(succeeded)
        XCTAssertNil(session.preview)
        XCTAssertEqual(imported, 1)
        let saved = try XCTUnwrap(repo.getAllPeriodTables().first)
        XCTAssertEqual(saved.name, "用户修改的作息名称")
        XCTAssertEqual(saved.timeJson, json)
        XCTAssertEqual(saved.nodesPerDay, 2)
        XCTAssertTrue(try repo.getAllTables().isEmpty, "Pure period import must not create a course table")
        XCTAssertTrue(try repo.restoreLastSnapshot())
        XCTAssertTrue(try repo.getAllPeriodTables().isEmpty)
        XCTAssertFalse(history.hasSnapshot)
    }
}
