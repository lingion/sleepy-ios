import XCTest
import GRDB
@testable import Sleepy

final class ParityInterfaceCompatibilityTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    private var prefs: AppPrefs!

    override func setUp() {
        suite = "parity-interface-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        prefs = AppPrefs(defaults: defaults)
        prefs.setCourseColorMode(AppPrefs.COURSE_COLOR_MODE_CUSTOM)
        prefs.setCourseColorSeedHue(120)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    private func course(_ gid: String) -> CourseEntity {
        CourseEntity(groupId: gid, tableId: 1, courseName: gid, day: 1,
                     startNode: 1, step: 1, startWeek: 1, endWeek: 16, color: "")
    }

    func testBannerCanBeDisabledAndReenabledWithoutSelectingUnsupportedMode() {
        prefs.setBeforeClassMode(AppPrefs.BEFORE_CLASS_MODE_BANNER)
        prefs.setBeforeClassBannerEnabled(false)
        XCTAssertFalse(prefs.isBeforeClassBannerEnabled())
        XCTAssertEqual("banner", prefs.getBeforeClassMode())
        XCTAssertFalse(prefs.isBeforeClassFluidEnabled())
        // 手表旧快照按 banner → fluid 的顺序恢复，不得把关闭状态冲掉。
        prefs.setBeforeClassFluidEnabled(false)
        XCTAssertFalse(prefs.isBeforeClassBannerEnabled())
        prefs.setBeforeClassBannerEnabled(true)
        XCTAssertTrue(prefs.isBeforeClassBannerEnabled())
    }

    func testLegacyBannerOffAndExplicitModeSurviveReconstruction() {
        defaults.set(false, forKey: AppPrefs.KEY_BEFORE_CLASS_BANNER)
        XCTAssertFalse(prefs.isBeforeClassBannerEnabled())
        defaults.set(true, forKey: AppPrefs.KEY_BEFORE_CLASS_FLUID)
        XCTAssertEqual("fluid", prefs.getBeforeClassMode())
        prefs.setBeforeClassBannerEnabled(true)
        let reloaded = AppPrefs(defaults: defaults)
        XCTAssertEqual("banner", reloaded.getBeforeClassMode())
        XCTAssertFalse(reloaded.isBeforeClassFluidEnabled())
        XCTAssertTrue(reloaded.isBeforeClassBannerEnabled())
    }

    func testSyncWriteReturnsPersistedRowsAndUsesInjectedSeed() throws {
        let db = try AppDatabase.inMemory()
        let result = CourseColorWriteGlue.persistNewGroupHues(
            dao: db.courseColorDao, entities: [course("g1"), course("g1"), course(" \n")], prefs: prefs)
        XCTAssertEqual(result, try db.courseColorDao.getHueMap(CourseColorEntity.globalTableKey))
        XCTAssertEqual(result, CourseColorUtil.planHuesForGroups(anchor: 120, existingHues: [], gids: ["g1"]))
        XCTAssertEqual(result.count, 1)
    }

    func testInDbSeesUncommittedRowsAndOuterRollbackRemovesOnlyNewWrites() throws {
        let db = try AppDatabase.inMemory()
        try db.courseColorDao.upsert(CourseColorEntity(groupId: "old", hue: 42))
        enum Abort: Error { case rollback }
        XCTAssertThrowsError(try db.dbQueue.write { dbw in
            var pending = CourseColorEntity(groupId: "pending", hue: 77)
            try pending.insert(dbw)
            let result = CourseColorWriteGlue.persistNewGroupHuesInDb(
                dbw: dbw, dao: db.courseColorDao,
                entities: [course("old"), course("pending"), course("new")], prefs: prefs)
            XCTAssertEqual(Set(result.keys), ["new"])
            XCTAssertEqual(try Float.fetchOne(dbw, sql: "SELECT hue FROM course_colors WHERE groupId = 'pending'"), 77)
            XCTAssertEqual(try Int.fetchOne(dbw, sql: "SELECT COUNT(*) FROM course_colors"), 3)
            throw Abort.rollback
        })
        XCTAssertEqual(try db.courseColorDao.getHueMap(CourseColorEntity.globalTableKey), ["old": 42])
    }

    func testColorWriteFailureRollsBackBatchButKeepsOuterImport() throws {
        let db = try AppDatabase.inMemory()
        try db.dbQueue.write { dbw in
            try dbw.execute(sql: "CREATE TABLE imported_marker (value TEXT)")
            // 第二行失败，确保第一行也被 savepoint 撤回（不依赖 Dictionary 顺序）。
            try dbw.execute(sql: """
                CREATE TRIGGER fail_second_color BEFORE INSERT ON course_colors
                WHEN (SELECT COUNT(*) FROM course_colors) > 0
                BEGIN SELECT RAISE(ABORT, 'color failure'); END
                """)
        }
        try db.dbQueue.write { dbw in
            try dbw.execute(sql: "INSERT INTO imported_marker VALUES ('course import')")
            let result = CourseColorWriteGlue.persistNewGroupHuesInDb(
                dbw: dbw, dao: db.courseColorDao, entities: [course("a"), course("b")], prefs: prefs)
            XCTAssertTrue(result.isEmpty, "失败不得返回未持久化的规划")
            XCTAssertEqual(try Int.fetchOne(dbw, sql: "SELECT COUNT(*) FROM course_colors"), 0)
        }
        XCTAssertEqual(try db.dbQueue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM imported_marker") }, 1)
    }

    func testReadFailureDoesNotOverwriteExistingColor() throws {
        let db = try AppDatabase.inMemory()
        try db.courseColorDao.upsert(CourseColorEntity(groupId: "existing", hue: 42))
        try db.dbQueue.write { dbw in
            try dbw.execute(sql: "ALTER TABLE course_colors RENAME TO saved_colors")
            try dbw.execute(sql: "CREATE VIEW course_colors AS SELECT * FROM missing_source")
        }
        let result = CourseColorWriteGlue.persistNewGroupHues(
            dao: db.courseColorDao, entities: [course("existing")], prefs: prefs)
        XCTAssertTrue(result.isEmpty)
        XCTAssertEqual(try db.dbQueue.read { try Float.fetchOne($0, sql: "SELECT hue FROM saved_colors") }, 42)
    }

    func testSyncRecalcFailureReturnsEmptyAndLeavesExistingRows() throws {
        let db = try AppDatabase.inMemory()
        try db.courseColorDao.upsert(CourseColorEntity(groupId: "old", hue: 42))
        try db.dbQueue.write { dbw in
            try dbw.execute(sql: """
                CREATE TRIGGER fail_color BEFORE INSERT ON course_colors
                BEGIN SELECT RAISE(ABORT, 'color failure'); END
                """)
        }
        let result = CourseColorWriteGlue.recalcWithAnchor(anchor: 120, dao: db.courseColorDao, gids: ["old", "new"])
        XCTAssertTrue(result.isEmpty)
        XCTAssertEqual(try db.courseColorDao.getHueMap(CourseColorEntity.globalTableKey), ["old": 42])
    }

    func testAsyncCompatibilityWritesBeforeReturning() async throws {
        let db = try AppDatabase.inMemory()
        let result = await CourseColorWriteGlue.persistNewGroupHues(
            mode: AppPrefs.COURSE_COLOR_MODE_CUSTOM, anchor: 120,
            dao: db.courseColorDao, entities: [course("async")])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result, try db.courseColorDao.getHueMap(CourseColorEntity.globalTableKey))
        let count = await CourseColorWriteGlue.recalcAll(
            mode: AppPrefs.COURSE_COLOR_MODE_FOLLOW_THEME, dao: db.courseColorDao, gids: ["async"])
        XCTAssertEqual(count, 1)
    }
}
