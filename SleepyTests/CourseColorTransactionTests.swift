import XCTest
import GRDB
@testable import Sleepy

final class CourseColorTransactionTests: XCTestCase {
    private func prefs() -> AppPrefs {
        let prefs = AppPrefs(defaults: UserDefaults(suiteName: "hue-transaction-\(UUID())")!)
        prefs.setCourseColorMode(AppPrefs.COURSE_COLOR_MODE_CUSTOM)
        prefs.setCourseColorSeedHue(120)
        return prefs
    }

    private func course(_ gid: String) -> CourseEntity {
        CourseEntity(groupId: gid, tableId: 1, courseName: gid,
                     day: 1, startNode: 1, step: 1, startWeek: 1, endWeek: 16, color: "")
    }

    func testTransactionSeesUncommittedHuesAndRollbackRemovesNewHues() throws {
        enum Rollback: Error { case requested }
        let db = try AppDatabase.inMemory()
        let prefs = prefs()
        XCTAssertThrowsError(try db.dbQueue.write { dbw in
            var old = CourseColorEntity(groupId: "old", hue: 42)
            try old.insert(dbw)
            let plan = CourseColorWriteGlue.persistNewGroupHuesInDb(
                dbw: dbw, dao: db.courseColorDao,
                entities: [course("old"), course("new"), course("new"), course("  ")], prefs: prefs)
            XCTAssertEqual(Set(plan.keys), ["new"])
            XCTAssertEqual(try Float.fetchOne(dbw, sql: "SELECT hue FROM course_colors WHERE groupId = 'old'"), 42)
            XCTAssertEqual(try Int.fetchOne(dbw, sql: "SELECT COUNT(*) FROM course_colors"), 2)
            throw Rollback.requested
        })
        XCTAssertTrue(try db.courseColorDao.getHueMap(CourseColorEntity.GLOBAL_TABLE_KEY).isEmpty)
    }

    func testColorWriteFailureRollsBackOnlyColorsAndAllowsMainTransactionToCommit() throws {
        let db = try AppDatabase.inMemory()
        let prefs = prefs()
        try db.dbQueue.write { dbw in
            try dbw.execute(sql: "CREATE TABLE import_marker (value INTEGER)")
            try dbw.execute(sql: "INSERT INTO import_marker VALUES (1)")
            // 第二条配色插入失败，验证第一条也撤销且导入主事务可继续提交。
            try dbw.execute(sql: """
                CREATE TRIGGER reject_second_hue BEFORE INSERT ON course_colors
                WHEN (SELECT COUNT(*) FROM course_colors) > 0
                BEGIN SELECT RAISE(ABORT, 'color write failure'); END
                """)
            let plan = CourseColorWriteGlue.persistNewGroupHuesInDb(
                dbw: dbw, dao: db.courseColorDao, entities: [course("a"), course("b")], prefs: prefs)
            XCTAssertTrue(plan.isEmpty)
        }
        XCTAssertTrue(try db.courseColorDao.getHueMap(CourseColorEntity.GLOBAL_TABLE_KEY).isEmpty)
        XCTAssertEqual(try db.dbQueue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM import_marker") }, 1)
    }
}
