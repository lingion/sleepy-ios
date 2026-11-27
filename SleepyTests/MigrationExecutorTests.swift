// MigrationExecutorTests.swift — ← app/src/test/java/com/lingion/sleepy/data/migration/MigrationExecutorTest.kt (逐用例)
//
// 平台适配说明:
// - 原版本 FakeCourseDao 等内存 DAO → iOS DAO 是持有 DatabaseWriter 的具体 struct,
//   无法注入替身 → 用 AppDatabase.inMemory() 起真 GRDB 内存库(等价隔离, 不落盘)。
// - 原版本 FakePrefsStore(vararg fileNames) → iOS FakeMigrationPrefsStore:
//   open(fileName:) 按 suiteName 懒建 UserDefaults; 每个测试用唯一 prefix(UUID)
//   隔离 suite, 避免测试间/跨运行污染, tearDown 清空全部键。
// - 依赖注: test 3 的 OVERWRITE 整文件替换依赖 MigrationPrefsCodec.apply(merge:false)
//   的 clear 语义(F047 修复项); 语义正确时本用例与 原版本 行为一致。

import XCTest
import GRDB
@testable import Sleepy

/// 文件名→UserDefaults(suiteName) 的注入版 prefs store; 未预置文件名按需创建空 prefs,
/// 与 原版本 FakePrefsStore 的 getOrPut 语义一致。
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

    func testAndroidSchoolSourceSurvivesBothArchiveRestoreModes() throws {
        let identity = #"{"schemaVersion":1,"sourceType":"jw","school":{"name":"Ａ校🍂","sortKey":"A","type":"qz","url":"https://jw.example.edu/"}}"#
        let rows: [String: Any] = ["timeTables": [
            ["id": 7, "name": "Imported", "startDate": "2026-09-07", "createdAt": 123, "timeJson": "[]",
             "jwSchoolSourceJson": identity, "jwSchoolSourceVerified": true]
        ]]
        let module = String(decoding: try JSONSerialization.data(withJSONObject: rows), as: UTF8.self)
        let raw = try MigrationPackageCodec.write(modules: [.DATABASE: module], createdAt: 1)
        for mode: MigrationExecutor.ImportMode in [.MERGE, .OVERWRITE] {
            let database = try AppDatabase.inMemory()
            let store = makeStore()
            _ = try MigrationExecutor.import(bytes: raw, mode: mode, prefsStore: store,
                courseDao: database.courseDao, timeTableDao: database.timeTableDao, periodTableDao: database.periodTableDao,
                importDraftDao: database.importDraftDao, dbQueue: database.dbQueue)
            XCTAssertEqual(try database.timeTableDao.getAll().first?.jwSchoolSourceJson, identity)
            XCTAssertEqual(try database.timeTableDao.getAll().first?.jwSchoolSourceVerified, false)
            let exported = try MigrationExecutor.export(selected: [.DATABASE], prefsStore: store,
                courseDao: database.courseDao, timeTableDao: database.timeTableDao, periodTableDao: database.periodTableDao,
                importDraftDao: database.importDraftDao, dbQueue: database.dbQueue).bytes
            let db = try XCTUnwrap(MigrationPackageCodec.read(exported).modules[.DATABASE])
            let roundTrip = try MigrationDatabaseCodec.decode(db)
            XCTAssertEqual(roundTrip.timeTables.first?.jwSchoolSourceJson, identity)
            XCTAssertFalse(db.contains("jwSchoolSourceVerified"))
        }
    }

    func testAndroidCombinedPeriodArchiveRoundTripsBothRestoreModes() throws {
        let combo = """
        { "name":"Seasonal","publicSchedules":[{"name":"Summer","startDate":"2026-09-14","endDate":"2026-09-30","timeSlots":[{"number":1,"startTime":"09:00","endTime":"09:45"}]}] }
        """
        let staticTimes = #"[{"node":1,"start":"08:00","end":"08:45"}]"#
        // Use the Android wire keys, not the iOS encoder, to supply the archive input.
        let androidDB: [String: Any] = [
            "periodTables": [
                ["id": 9, "name": "Dated", "timeJson": staticTimes, "nodesPerDay": 1,
                 "createdAt": 1, "updatedAt": 2, "comboScheduleJson": combo],
                ["id": 10, "name": "Legacy", "timeJson": staticTimes, "createdAt": 1, "updatedAt": 2]
            ],
            "timeTables": [
                ["id": 20, "name": "Term", "startDate": "2026-09-07",
                 "periodTableId": 9, "timeJson": staticTimes, "createdAt": 1]
            ],
            "courses": [
                ["id": 21, "groupId": "lab", "tableId": 20, "courseName": "Lab", "day": 1,
                 "startNode": 1, "step": 1, "startWeek": 1, "endWeek": 16, "color": "#FF6750A4"]
            ]
        ]
        let input = String(decoding: try JSONSerialization.data(withJSONObject: androidDB), as: UTF8.self)
        let bytes = try MigrationPackageCodec.write(modules: [.DATABASE: input], createdAt: 1)
        let store = makeStore()
        for mode: MigrationExecutor.ImportMode in [.MERGE, .OVERWRITE] {
            let db = try newDb()
            try db.periodTableDao.insert(.init(name: "Keep this local", id: 9))
            try db.timeTableDao.insert(.init(name: "Local", startDate: "2026-01-05", periodTableId: 9, id: 20))
            _ = try MigrationExecutor.import(bytes: bytes, mode: mode, prefsStore: store,
                courseDao: db.courseDao, timeTableDao: db.timeTableDao, periodTableDao: db.periodTableDao,
                importDraftDao: db.importDraftDao, dbQueue: db.dbQueue)
            let encoded = try MigrationExecutor.export(selected: [.DATABASE], prefsStore: store,
                courseDao: db.courseDao, timeTableDao: db.timeTableDao, periodTableDao: db.periodTableDao,
                importDraftDao: db.importDraftDao, dbQueue: db.dbQueue).bytes
            let payload = try XCTUnwrap(MigrationPackageCodec.read(encoded).modules[.DATABASE])
            let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any])
            let periods = try XCTUnwrap(root["periodTables"] as? [[String: Any]])
            let dated = try XCTUnwrap(periods.first(where: { $0["name"] as? String == "Dated" }))
            let legacy = try XCTUnwrap(periods.first(where: { $0["name"] as? String == "Legacy" }))
            let tables = try XCTUnwrap(root["timeTables"] as? [[String: Any]])
            let term = try XCTUnwrap(tables.first(where: { $0["name"] as? String == "Term" }))
            let courses = try XCTUnwrap(root["courses"] as? [[String: Any]])
            XCTAssertEqual(dated["comboScheduleJson"] as? String, combo)
            XCTAssertEqual(dated["timeJson"] as? String, staticTimes)
            XCTAssertEqual(legacy["comboScheduleJson"] as? String, "")
            XCTAssertEqual(term["periodTableId"] as? Int, dated["id"] as? Int)
            XCTAssertEqual(courses.first?["tableId"] as? Int, term["id"] as? Int)
            XCTAssertEqual(courses.first?["courseName"] as? String, "Lab")
            XCTAssertEqual(dated["id"] as? Int == 9, mode == .OVERWRITE)
            XCTAssertEqual(term["id"] as? Int == 20, mode == .OVERWRITE)
            if mode == .MERGE {
                XCTAssertEqual(try db.periodTableDao.getById(9)?.name, "Keep this local")
                XCTAssertEqual(try db.timeTableDao.getById(20)?.periodTableId, 9)
            }
        }
    }

    func testUpgradeAddsAnEmptyComboColumnWithoutChangingExistingRows() throws {
        let template = try newDb()
        let queue = try DatabaseQueue()
        try template.migrator.migrate(queue, upTo: "v15.addImportSource")
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO period_tables (id,name,nodesPerDay,timeJson,smartConfigJson,createdAt,updatedAt)
                VALUES (42,'Original',1,'[]','',123,456)
                """)
        }
        let upgraded = try AppDatabase(queue: queue)
        let period = try XCTUnwrap(upgraded.periodTableDao.getById(42))
        XCTAssertEqual(period.name, "Original")
        XCTAssertEqual(period.timeJson, "[]")
        XCTAssertEqual(period.createdAt, 123)
        XCTAssertEqual(period.updatedAt, 456)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(period)) as? [String: Any])
        XCTAssertEqual(json["comboScheduleJson"] as? String, "")
    }

    func testOlderWatchPeriodPayloadStillDecodes() throws {
        let legacy = #"{"id":42,"name":"Old phone","nodesPerDay":1,"timeJson":"[]","smartConfigJson":"","createdAt":123,"updatedAt":456}"#
        let period = try JSONDecoder().decode(PeriodTableEntity.self, from: Data(legacy.utf8))
        XCTAssertEqual(period.id, 42)
        XCTAssertEqual(period.name, "Old phone")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(period)) as? [String: Any])
        XCTAssertEqual(json["comboScheduleJson"] as? String, "")
    }

    func testRemoteArchiveIsReadOnlyBeforeSharedMergeOrOverwrite() throws {
        let source = try newDb()
        let tableId = try source.timeTableDao.insert(.init(name: "Remote term", startDate: "2026-09-07"))
        _ = try source.courseDao.insert(.init(groupId: "lab", tableId: tableId, courseName: "Lab",
                                               day: 1, startNode: 1, step: 2, startWeek: 1, endWeek: 2,
                                               color: "#FF6750A4"))
        let store = makeStore()
        let data = try MigrationExecutor.export(selected: [.DATABASE], prefsStore: store,
            courseDao: source.courseDao, timeTableDao: source.timeTableDao, periodTableDao: source.periodTableDao,
            importDraftDao: source.importDraftDao, dbQueue: source.dbQueue).bytes

        for mode: MigrationExecutor.ImportMode in [.MERGE, .OVERWRITE] {
            let target = try newDb()
            _ = try target.timeTableDao.insert(.init(name: "Local term", startDate: "2026-08-31"))
            let ready = try MigrationPreparedArchive.decodeRemote(data)
            // Choosing Cancel would stop here. Decoding has not opened or touched the target.
            XCTAssertEqual(try target.timeTableDao.getAll().map(\.name), ["Local term"])
            XCTAssertTrue(try target.courseDao.getAllCourses().isEmpty)

            let report = try MigrationExecutor.apply(ready, mode: mode, prefsStore: store,
                courseDao: target.courseDao, timeTableDao: target.timeTableDao, periodTableDao: target.periodTableDao,
                importDraftDao: target.importDraftDao, dbQueue: target.dbQueue)
            let tables = try target.timeTableDao.getAll()
            let remote = try XCTUnwrap(tables.first { $0.name == "Remote term" })
            XCTAssertEqual(try target.courseDao.getByTable(remote.id).map(\.courseName), ["Lab"])
            XCTAssertEqual(tables.contains { $0.name == "Local term" }, mode == .MERGE)
            XCTAssertEqual(report.counts.courses, 1)
        }
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
        // FK: 本机课引用 tableId=1, 先补 time_tables id=1(原版本 Fake DAO 无 FK 约束)
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
    // (原版本 LinkedHashMap 插入序 = ordinal 序; iOS payloads 是无序 Dictionary,
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
                       "manifest.modules 必须按 原 ordinal 序确定性输出")
    }
}
