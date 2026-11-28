import XCTest
@testable import Sleepy

final class LiteSQLiteTests: XCTestCase {
    private func makeTempDBURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sleepy-litesqlite-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("sleepy.db")
    }

    func testLiteDatabaseInitializesWalAndForeignKeysOutsideTransaction() throws {
        let dbURL = makeTempDBURL()
        defer { try? FileManager.default.removeItem(at: dbURL.deletingLastPathComponent()) }

        // Previously LiteDatabase ran `PRAGMA journal_mode = WAL;` inside `BEGIN IMMEDIATE`,
        // which failed on SQLite / device extension startup with a fatal error.
        let lite = try LiteDatabase(path: dbURL.path)
        let (journalMode, foreignKeys, tables) = try lite.read { conn -> (String, Int, Set<String>) in
            let mode = try conn.fetchOne("PRAGMA journal_mode;") { $0.colString(0).lowercased() } ?? ""
            let fk = try conn.fetchOne("PRAGMA foreign_keys;") { $0.colInt(0) } ?? 0
            let tbls = Set(try conn.fetchAll(
                "SELECT name FROM sqlite_master WHERE type = 'table';"
            ) { $0.colString(0) })
            return (mode, fk, tbls)
        }

        XCTAssertEqual(journalMode, "wal")
        XCTAssertEqual(foreignKeys, 1)
        XCTAssertTrue(Set(["time_tables", "courses", "period_tables", "course_colors"]).isSubset(of: tables))

        // Re-opening an already-WAL database should also succeed cleanly.
        let reopened = try LiteDatabase(path: dbURL.path)
        let reopenedMode = try reopened.read { conn in
            try conn.fetchOne("PRAGMA journal_mode;") { $0.colString(0).lowercased() } ?? ""
        }
        XCTAssertEqual(reopenedMode, "wal")
    }

    func testWidgetOpenedFirstLeavesSchemaToMainAppMigrator() throws {
        let dbURL = makeTempDBURL()
        defer { try? FileManager.default.removeItem(at: dbURL.deletingLastPathComponent()) }

        // Regression: the widget used to create the shared tables itself, and the main app's GRDB
        // migrator then failed on its first launch with "table time_tables already exists".
        let widgetView = try LiteDatabase(path: dbURL.path, createSchema: false)
        let tablesSeenByWidget = try widgetView.read { conn in
            Set(try conn.fetchAll("SELECT name FROM sqlite_master WHERE type = 'table';") { $0.colString(0) })
        }
        XCTAssertFalse(tablesSeenByWidget.contains("time_tables"))

        let appDb = try AppDatabase(persistentURL: dbURL)
        let hasTimeTables = try appDb.dbQueue.read { db in try db.tableExists("time_tables") }
        XCTAssertTrue(hasTimeTables)
    }

    func testLiteDatabaseReadsDataWrittenByGRDBAppDatabase() throws {
        let dbURL = makeTempDBURL()
        defer { try? FileManager.default.removeItem(at: dbURL.deletingLastPathComponent()) }

        let appDb = try AppDatabase(persistentURL: dbURL)
        let repo = ScheduleRepository(appDb)

        let ptId = try repo.insertPeriodTable(PeriodTableEntity(
            name: "测试作息",
            nodesPerDay: 12,
            timeJson: "[]",
            smartConfigJson: "",
            comboScheduleJson: "{}",
            createdAt: 1000,
            updatedAt: 1000
        ))
        let tableId = try repo.insertTable(TimeTableEntity(
            name: "主课表",
            startDate: "2026-09-01",
            maxWeek: 20,
            nodesPerDay: 12,
            timeJson: "[]",
            color: "#FF6750A4",
            isDefault: true,
            createdAt: 1000,
            periodTableId: ptId,
            jwSchoolSourceVerified: true
        ))
        try repo.insertCourse(CourseEntity(
            groupId: "g1",
            tableId: tableId,
            courseName: "高等数学",
            day: 1,
            startNode: 1,
            step: 2,
            startWeek: 1,
            endWeek: 16,
            color: "#FF6750A4"
        ))

        let lite = try LiteDatabase(path: dbURL.path)
        let (tableName, verified, courseName, combo) = try lite.read { conn -> (String, Bool, String, String) in
            let tbl = try conn.fetchOne(
                "SELECT name, jwSchoolSourceVerified FROM time_tables WHERE id = ?;",
                arguments: [.int64(tableId)]
            ) { ($0.colString(0), $0.colBool(1)) }
            let crs = try conn.fetchOne(
                "SELECT courseName FROM courses WHERE tableId = ?;",
                arguments: [.int64(tableId)]
            ) { $0.colString(0) }
            let pt = try conn.fetchOne(
                "SELECT comboScheduleJson FROM period_tables WHERE id = ?;",
                arguments: [.int64(ptId)]
            ) { $0.colString(0) }
            return (tbl?.0 ?? "", tbl?.1 ?? false, crs ?? "", pt ?? "")
        }

        XCTAssertEqual(tableName, "主课表")
        XCTAssertTrue(verified)
        XCTAssertEqual(courseName, "高等数学")
        XCTAssertEqual(combo, "{}")
    }
}
