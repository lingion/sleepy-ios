// CourseColorMigrationTests.swift — ← data/CourseColorMigrationTest.kt 逐用例移植 (v1.0.62, GPL-3.0)
//
// v11 → v12 迁移契约 (spec §6 测试 5/6):
//   1. 建表 course_colors 且不触碰既有表/既有行;
//   2. 复合主键 (tableKey, groupId) 去重语义 — 同键 upsert 幂等, 异键同 groupId 是不同行,
//      同键裸 INSERT 必被拒(防「误用旧式双列主键」);
//   3. 迁移链尾必须到 v12。
//
// 平台差异: Android 用 Room Migration 单一事实来源 MIGRATION_11_12_STATEMENTS;
// iOS 用 GRDB DatabaseMigrator, DDL 逐字与 Android 11_12 一致(见 AppDatabase.migrator)。

import XCTest
import GRDB
@testable import Sleepy

final class CourseColorMigrationTests: XCTestCase {

    /// 与 AppDatabase.migrator 的 v12 DDL 逐字一致(单一事实来源在生产代码,此处复制用于断言)。
    private static let courseColorsDDL = """
        CREATE TABLE IF NOT EXISTS course_colors (
            tableKey TEXT NOT NULL,
            groupId TEXT NOT NULL,
            hue REAL NOT NULL,
            PRIMARY KEY (tableKey, groupId)
        )
        """

    private func makeDbWithDDL() throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try queue.write { db in
            try db.execute(sql: Self.courseColorsDDL)
        }
        return queue
    }

    // ───────── 1. 建表不动既有数据 ─────────

    func testMigrationCreatesCourseColorsWithoutTouchingExistingRows() throws {
        let queue = try DatabaseQueue()
        try queue.write { db in
            try db.execute(sql: "CREATE TABLE time_tables (id INTEGER PRIMARY KEY, name TEXT NOT NULL)")
            try db.execute(sql: "INSERT INTO time_tables VALUES (1, 'existing')")
            try db.execute(sql: Self.courseColorsDDL)
        }

        try queue.read { db in
            var columns: [String: (String, Int)] = [:]
            for row in try Row.fetchAll(db, sql: "PRAGMA table_info(course_colors)") {
                let name: String = row["name"]
                let type: String = row["type"]
                let notNull: Int = row["notnull"]
                columns[name] = (type, notNull)
            }
            XCTAssertEqual("TEXT", columns["tableKey"]?.0)
            XCTAssertEqual(1, columns["tableKey"]?.1)
            XCTAssertEqual("TEXT", columns["groupId"]?.0)
            XCTAssertEqual(1, columns["groupId"]?.1)
            XCTAssertEqual("REAL", columns["hue"]?.0)
            XCTAssertEqual(1, columns["hue"]?.1)

            // 旧数据无损
            let name = try String.fetchOne(db, sql: "SELECT name FROM time_tables WHERE id = 1")
            XCTAssertEqual("existing", name, "旧数据必须无损")
        }
    }

    // ───────── 2. 复合主键语义 ─────────

    func testCompositePrimaryKeyRejectsDifferentTableKeySameGroupIdAndUpsertIsIdempotent() throws {
        let queue = try makeDbWithDDL()
        try queue.write { db in
            try db.execute(sql: "INSERT INTO course_colors VALUES ('__global__', 'g1', 123.5)")
            // 同 (tableKey, groupId) 二次写 = REPLACE 语义 → 更新非新增
            try db.execute(sql: "INSERT OR REPLACE INTO course_colors VALUES ('__global__', 'g1', 200.0)")
            let row = try Row.fetchOne(db, sql: "SELECT COUNT(*) AS c, MAX(hue) AS h FROM course_colors")
            XCTAssertEqual(1, row?["c"] as Int? ?? 0, "upsert 幂等: 同键只余一行")
            XCTAssertEqual(200.0, (row?["h"] as Double? ?? -1), accuracy: 0.001)

            // 不同 tableKey 同 groupId 是不同行(主键含 tableKey 的几何证明)
            try db.execute(sql: "INSERT INTO course_colors VALUES ('t2', 'g1', 5.0)")
            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM course_colors")
            XCTAssertEqual(2, count)

            // 旧式双列主键的误用防线: 同键裸 INSERT 必被拒
            var rejected = false
            do {
                try db.execute(sql: "INSERT INTO course_colors VALUES ('__global__', 'g1', 9.0)")
            } catch {
                rejected = true
            }
            XCTAssertTrue(rejected, "复合主键必须拒绝同键重复")
        }
    }

    // ───────── 3. 迁移链尾到 v12 ─────────

    func testMigrationChainReachesV12() throws {
        let appdb = try AppDatabase.inMemory()
        try appdb.dbQueue.read { db in
            let identifiers = try String.fetchAll(
                db, sql: "SELECT identifier FROM grdb_migrations ORDER BY identifier")
            XCTAssertTrue(identifiers.contains("v12.createCourseColors"),
                          "迁移链必须含 v12.createCourseColors, 实际: \(identifiers)")
            // v11 → v12 之间不得有断链: 前序迁移也应全部落地
            for expected in ["v11.addReminderEnabled", "v10.createCalendarImportRecords",
                             "v9.addPreBindSnapshot", "v8.createPeriodTables"] {
                XCTAssertTrue(identifiers.contains(expected), "缺失迁移: \(expected)")
            }
            // 迁移后 course_colors 真实存在且列形状正确
            let cols = try Row.fetchAll(db, sql: "PRAGMA table_info(course_colors)")
                .map { (row: Row) -> String in row["name"] }
            XCTAssertEqual(["tableKey", "groupId", "hue"], cols)
        }
    }

    /// 端到端: 迁移链落库后, CourseColorDao 能真实写入并读回(复合主键在 DAO 路径同样生效)。
    func testCourseColorDaoRoundTripAfterMigration() throws {
        let appdb = try AppDatabase.inMemory()
        let dao = appdb.courseColorDao
        let g = CourseColorEntity(tableKey: CourseColorEntity.globalTableKey, groupId: "g1", hue: 123.5)
        try dao.upsert(g)
        try dao.upsert(CourseColorEntity(tableKey: CourseColorEntity.globalTableKey,
                                         groupId: "g1", hue: 200.0))
        var map = try dao.getHueMap(CourseColorEntity.globalTableKey)
        XCTAssertEqual(1, map.count, "同键 upsert 幂等")
        XCTAssertEqual(200.0, map["g1"] ?? -1, accuracy: 0.001)

        try dao.upsert(CourseColorEntity(tableKey: "t2", groupId: "g1", hue: 5.0))
        map = try dao.getHueMap(CourseColorEntity.globalTableKey)
        XCTAssertEqual(1, map.count, "异 tableKey 不污染全局表")
    }
}
