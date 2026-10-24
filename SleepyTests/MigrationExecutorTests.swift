// MigrationExecutorTests.swift — ← app/src/test/java/com/lingion/sleepy/data/migration/MigrationExecutorTest.kt (逐用例)
//
// 平台适配说明:
// - Android FakeCourseDao 等内存 DAO → iOS DAO 是持有 DatabaseWriter 的具体 struct,
//   无法注入替身 → 用 AppDatabase.inMemory() 起真 GRDB 内存库(等价隔离, 不落盘)。
// - Android FakePrefsStore(vararg fileNames) → iOS FakeMigrationPrefsStore:
//   open(fileName:) 按 suiteName 懒建 UserDefaults; 每个测试用唯一 prefix(UUID)
//   隔离 suite, 避免测试间/跨运行污染, tearDown 清空全部键。
// - 依赖注: test 3 的 OVERWRITE 整文件替换依赖 MigrationPrefsCodec.apply(merge:false)
//   的 clear 语义(F047 修复项); 语义正确时本用例与 Android 行为一致。

import XCTest
import GRDB
@testable import Sleepy

/// 文件名→UserDefaults(suiteName) 的注入版 prefs store; 未预置文件名按需创建空 prefs,
/// 与 Android FakePrefsStore 的 getOrPut 语义一致。
final class FakeMigrationPrefsStore: MigrationPrefsStoreProtocol {
    private let prefix: String
    private var opened: [String: UserDefaults] = [:]

    init(prefix: String = UUID().uuidString) {
        self.prefix = prefix
    }

    func open(fileName: String) -> UserDefaults {
        if let d = opened[fileName] { return d }
        let d = UserDefaults(suiteName: "\(prefix).\(fileName)")!
        opened[fileName] = d
        return d
    }

    /// 清空本 store 打开过的所有 suite(测试收尾用)。
    func reset() {
        for d in opened.values {
            for key in d.dictionaryRepresentation().keys {
                d.removeObject(forKey: key)
            }
        }
    }
}

final class MigrationExecutorTests: XCTestCase {

    private var stores: [FakeMigrationPrefsStore] = []

    private func makeStore(_ fileNames: String...) -> FakeMigrationPrefsStore {
        let store = FakeMigrationPrefsStore()
        for f in fileNames { _ = store.open(fileName: f) }
        stores.append(store)
        return store
    }

    override func tearDown() {
        stores.forEach { $0.reset() }
        stores.removeAll()
        super.tearDown()
    }

    private func newDb() throws -> AppDatabase {
        return try AppDatabase.inMemory()
    }

    // ← export with database pulls persisted_state dependency into package
    func testExportWithDatabasePullsPersistedStateDependency() throws {
        let db = try newDb()
        let store = makeStore("sleepy_prefs", "custom_themes", "widget_bindings")

        let result = try MigrationExecutor.export(
            selected: [.DATABASE],
            prefsStore: store,
            courseDao: db.courseDao, timeTableDao: db.timeTableDao,
            periodTableDao: db.periodTableDao, importDraftDao: db.importDraftDao,
            dbQueue: db.dbQueue,
            createdAt: 1234
        )

        XCTAssertEqual(["database", "persisted_state"], result.manifest.modules)
        // persisted_state 当前为空集, 仍是合法空快照
        let content = try MigrationPackageCodec.read(result.bytes)
        let persisted = try MigrationPrefsCodec.decode(
            XCTUnwrap(content.modules[.PERSISTED_STATE]))
        XCTAssertTrue(persisted.files.isEmpty)
        // prefs 文件未被选择 → widgets/preferences 不在包内
        XCTAssertNil(content.modules[.PREFERENCES])
        XCTAssertNil(content.modules[.WIDGETS])
    }

    // ← export without database keeps selected modules only
    func testExportWithoutDatabaseKeepsSelectedModulesOnly() throws {
        let db = try newDb()
        let store = makeStore("sleepy_prefs", "widget_bindings", "widget_scroll_prefs")
        store.open(fileName: "widget_scroll_prefs").set("v", forKey: "marker")

        let result = try MigrationExecutor.export(
            selected: [.WIDGETS],
            prefsStore: store,
            courseDao: db.courseDao, timeTableDao: db.timeTableDao,
            periodTableDao: db.periodTableDao, importDraftDao: db.importDraftDao,
            dbQueue: db.dbQueue
        )

        let content = try MigrationPackageCodec.read(result.bytes)
        XCTAssertEqual([MigrationModule.WIDGETS], content.modules.keys.sorted())
        let widgetFiles = try MigrationPrefsCodec.decode(
            XCTUnwrap(content.modules[.WIDGETS])).files
        // 非空文件进包; preferences 文件不混入 widgets 模块
        XCTAssertTrue(widgetFiles.keys.contains("widget_scroll_prefs"))
        XCTAssertFalse(widgetFiles.keys.contains("sleepy_prefs"))
        XCTAssertEqual("v", widgetFiles["widget_scroll_prefs"]?.entries["marker"]?.string)
    }

    // ← overwrite import replaces prefs files present in package and leaves absent files untouched
    func testOverwriteImportReplacesPackageFilesAndLeavesAbsentFilesUntouched() throws {
        let db = try newDb()
        let store = makeStore("sleepy_prefs", "custom_themes", "widget_bindings")
        // 本机: sleepy_prefs 有包内没有的 stale 键; widget_bindings 本机有、包内没有 → 应保持不动
        store.open(fileName: "sleepy_prefs").set("old", forKey: "stale")
        store.open(fileName: "widget_bindings").set("keep-me", forKey: "localBinding")

        let source = makeStore("sleepy_prefs", "widget_scroll_prefs")
        source.open(fileName: "sleepy_prefs").set("20", forKey: "weekCount")
        source.open(fileName: "widget_scroll_prefs").set(true, forKey: "scrollOn")

        let exported = try MigrationExecutor.export(
            selected: [.PREFERENCES, .WIDGETS],
            prefsStore: source,
            courseDao: db.courseDao, timeTableDao: db.timeTableDao,
            periodTableDao: db.periodTableDao, importDraftDao: db.importDraftDao,
            dbQueue: db.dbQueue
        )

        let report = try MigrationExecutor.import(
            bytes: exported.bytes, mode: .OVERWRITE,
            prefsStore: store,
            courseDao: db.courseDao, timeTableDao: db.timeTableDao,
            periodTableDao: db.periodTableDao, importDraftDao: db.importDraftDao,
            dbQueue: db.dbQueue
        )

        // 包内文件全量替换: stale 键消失
        let sleepy = store.open(fileName: "sleepy_prefs")
        XCTAssertEqual("20", sleepy.string(forKey: "weekCount"))
        XCTAssertNil(sleepy.string(forKey: "stale"))
        // 包内缺失文件不动本机
        XCTAssertEqual("keep-me", store.open(fileName: "widget_bindings").string(forKey: "localBinding"))
        // 包内出现的新文件落库
        XCTAssertEqual(true, store.open(fileName: "widget_scroll_prefs").bool(forKey: "scrollOn"))
        XCTAssertEqual([MigrationModule.PREFERENCES, MigrationModule.WIDGETS], report.appliedModules)
        XCTAssertEqual(2, report.counts.prefFiles)
        XCTAssertEqual(2, report.counts.prefKeys)
    }

    // ← overwrite import restores database rows with original ids
    func testOverwriteImportRestoresDatabaseRowsWithOriginalIds() throws {
        let db = try newDb()
        var period = PeriodTableEntity(name: "p", timeJson: "[]", createdAt: 1, updatedAt: 1)
        period.id = 9
        _ = try db.periodTableDao.insert(period)
        var table = TimeTableEntity(name: "t", startDate: "", timeJson: "[]", createdAt: 1)
        table.id = 5
        table.periodTableId = 9
        _ = try db.timeTableDao.insert(table)
        var course = CourseEntity(groupId: "g", tableId: 5, courseName: "课",
                                  day: 1, startNode: 1, step: 1, startWeek: 1, endWeek: 1,
                                  color: "#FF6750A4")
        course.id = 101
        _ = try db.courseDao.insert(course)

        let store = makeStore("sleepy_prefs")
        let exported = try MigrationExecutor.export(
            selected: [.DATABASE],
            prefsStore: store,
            courseDao: db.courseDao, timeTableDao: db.timeTableDao,
            periodTableDao: db.periodTableDao, importDraftDao: db.importDraftDao,
            dbQueue: db.dbQueue
        )

        let target = try newDb()
        // iOS 真库启用 FK 约束(Room Fake DAO 不约束): 脏课引用 tableId=1, 先补一条
        // time_tables id=1 满足 courses.tableId 外键; OVERWRITE 导入会整表清掉它。
        var seedTable = TimeTableEntity(name: "seed", startDate: "", timeJson: "[]", createdAt: 1)
        seedTable.id = 1
        _ = try target.timeTableDao.insert(seedTable)
        var dirty = CourseEntity(groupId: "x", tableId: 1, courseName: "脏数据",
                                 day: 1, startNode: 1, step: 1, startWeek: 1, endWeek: 1,
                                 color: "#FF0000")
        dirty.id = 999
        _ = try target.courseDao.insert(dirty)

        let report = try MigrationExecutor.import(
            bytes: exported.bytes, mode: .OVERWRITE,
            prefsStore: store,
            courseDao: target.courseDao, timeTableDao: target.timeTableDao,
            periodTableDao: target.periodTableDao, importDraftDao: target.importDraftDao,
            dbQueue: target.dbQueue
        )

        XCTAssertEqual([9], try target.periodTableDao.getAll().map { $0.id })
        XCTAssertEqual([5], try target.timeTableDao.getAll().map { $0.id })
        XCTAssertEqual([101], try target.courseDao.getAllCourses().map { $0.id })
        XCTAssertEqual(1, report.counts.courses)
    }

    // ← merge import keeps local prefs keys not present in package
    func testMergeImportKeepsLocalPrefsKeysNotPresentInPackage() throws {
        let source = makeStore("sleepy_prefs")
        source.open(fileName: "sleepy_prefs").set("from-package", forKey: "shared")
        let db = try newDb()
        let exported = try MigrationExecutor.export(
            selected: [.PREFERENCES],
            prefsStore: source,
            courseDao: db.courseDao, timeTableDao: db.timeTableDao,
            periodTableDao: db.periodTableDao, importDraftDao: db.importDraftDao,
            dbQueue: db.dbQueue
        )

        let store = makeStore("sleepy_prefs")
        let local = store.open(fileName: "sleepy_prefs")
        local.set("local", forKey: "shared")
        local.set("mine", forKey: "localOnly")

        let target = try newDb()
        let report = try MigrationExecutor.import(
            bytes: exported.bytes, mode: .MERGE,
            prefsStore: store,
            courseDao: target.courseDao, timeTableDao: target.timeTableDao,
            periodTableDao: target.periodTableDao, importDraftDao: target.importDraftDao,
            dbQueue: target.dbQueue
        )

        let prefs = store.open(fileName: "sleepy_prefs")
        XCTAssertEqual("from-package", prefs.string(forKey: "shared"))
        XCTAssertEqual("mine", prefs.string(forKey: "localOnly"))
        XCTAssertEqual(MigrationExecutor.ImportMode.MERGE, report.mode)
    }

    // ← corrupt package is rejected before touching local data
    func testCorruptPackageIsRejectedBeforeTouchingLocalData() throws {
        let store = makeStore("sleepy_prefs")
        store.open(fileName: "sleepy_prefs").set("untouched", forKey: "safe")
        let db = try newDb()
        // FK: 本机课引用 tableId=1, 先补 time_tables id=1(Android Fake DAO 无 FK 约束)
        var seedTable = TimeTableEntity(name: "seed", startDate: "", timeJson: "[]", createdAt: 1)
        seedTable.id = 1
        _ = try db.timeTableDao.insert(seedTable)
        _ = try db.courseDao.insert(CourseEntity(groupId: "g", tableId: 1, courseName: "本机课",
                                                 day: 1, startNode: 1, step: 1,
                                                 startWeek: 1, endWeek: 1, color: "#FF0000"))

        XCTAssertThrowsError(try MigrationExecutor.import(
            bytes: Data("not a zip".utf8), mode: .OVERWRITE,
            prefsStore: store,
            courseDao: db.courseDao, timeTableDao: db.timeTableDao,
            periodTableDao: db.periodTableDao, importDraftDao: db.importDraftDao,
            dbQueue: db.dbQueue
        )) { error in
            XCTAssertTrue(error is MigrationPackageException,
                          "应抛 MigrationPackageException, 实得 \(type(of: error))")
        }
        XCTAssertEqual("untouched", store.open(fileName: "sleepy_prefs").string(forKey: "safe"))
        let all = try db.courseDao.getAllCourses()
        XCTAssertEqual(1, all.count)
    }

    // iOS 补充: manifest.modules 确定性 — 覆盖 F045 issue#1
    // (Android LinkedHashMap 插入序 = ordinal 序; iOS payloads 是无序 Dictionary,
    //  修复后 manifest.modules 必须按 ordinal 输出, 多次导出结果一致)
    func testManifestModulesOrderIsDeterministicOrdinal() throws {
        let db = try newDb()
        let store = makeStore("sleepy_prefs")
        store.open(fileName: "sleepy_prefs").set("v", forKey: "x")
        let result = try MigrationExecutor.export(
            selected: [.DATABASE, .WIDGETS, .PREFERENCES],
            prefsStore: store,
            courseDao: db.courseDao, timeTableDao: db.timeTableDao,
            periodTableDao: db.periodTableDao, importDraftDao: db.importDraftDao,
            dbQueue: db.dbQueue,
            createdAt: 7
        )
        XCTAssertEqual(["database", "preferences", "widgets", "persisted_state"],
                       result.manifest.modules,
                       "manifest.modules 必须按 Android ordinal 序确定性输出")
    }
}
