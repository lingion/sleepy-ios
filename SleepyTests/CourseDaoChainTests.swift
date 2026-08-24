// CourseDaoChainTests.swift — G4 链①前半: 数据层全链(内存栈,起真 DAO/建表/事务)
// database-testing parity: 建表→插入→查询→更新→组替换→整表替换→级联删除
// + schema parity(与 Room 注解声明的列集一致)

import XCTest
import GRDB
@testable import Sleepy

final class CourseDaoChainTests: XCTestCase {

    var db: AppDatabase!

    override func setUp() {
        super.setUp()
        db = try! AppDatabase.inMemory()
    }

    private func makeTable(name: String = "主课表") -> Int64 {
        var t = TimeTableEntity(name: name, startDate: "2026-03-02")
        let id = try! db.timeTableDao.insert(t)
        t.id = id
        return id
    }

    private func course(tableId: Int64, groupId: String, day: Int = 1, startNode: Int = 1,
                        startWeek: Int = 1, endWeek: Int = 16, type: Int = 0) -> CourseEntity {
        CourseEntity(groupId: groupId, tableId: tableId, courseName: "高数-\(groupId)",
                     day: day, startNode: startNode, step: 2, startWeek: startWeek,
                     endWeek: endWeek, type: type, color: "#FF6750A4")
    }

    func testTableCRUDAndDefault() throws {
        XCTAssertEqual(0, try db.timeTableDao.count())
        let id = try makeTable()
        XCTAssertEqual(1, try db.timeTableDao.count())
        XCTAssertNotNil(try db.timeTableDao.getById(id))

        // setDefault: UPDATE ... SET isDefault = (id = :id)
        try db.timeTableDao.setDefault(id)
        let def = try db.timeTableDao.getDefault()
        XCTAssertEqual(id, def?.id)

        // update
        var t = try XCTUnwrap(try db.timeTableDao.getById(id))
        t.name = "改名"
        try db.timeTableDao.update(t)
        XCTAssertEqual("改名", try db.timeTableDao.getById(id)?.name)

        // getAll 按 createdAt DESC
        _ = try makeTable(name: "第二表")
        let all = try db.timeTableDao.getAll()
        XCTAssertEqual(2, all.count)

        try db.timeTableDao.deleteById(id)
        XCTAssertEqual(1, try db.timeTableDao.count())
    }

    func testCourseCrudAndQueries() throws {
        let tid = try makeTable()
        var c = course(tableId: tid, groupId: "g1", day: 2, startNode: 3)
        let cid = try db.courseDao.insert(c)
        XCTAssertGreaterThan(cid, 0)
        c.id = cid

        // update
        c.room = "A101"
        try db.courseDao.update(c)
        XCTAssertEqual("A101", try db.courseDao.getById(cid)?.room)

        // getByTable 排序: day, startNode, startWeek
        _ = try db.courseDao.insert(course(tableId: tid, groupId: "g2", day: 1, startNode: 1))
        _ = try db.courseDao.insert(course(tableId: tid, groupId: "g3", day: 2, startNode: 1))
        let byTable = try db.courseDao.getByTable(tid)
        XCTAssertEqual(3, byTable.count)
        // ORDER BY day, startNode, startWeek → day 序列 [1,2,2]
        XCTAssertEqual([1, 2, 2], byTable.map { $0.day }, "ORDER BY day: got \(byTable.map { ($0.groupId, $0.day, $0.startNode) })")
        // day==2 的两条按 startNode 升序
        let d2 = byTable.filter { $0.day == 2 }
        XCTAssertEqual([1, 3], d2.map { $0.startNode },
                       "day2 rows: \(d2.map { ($0.groupId, $0.day, $0.startNode, $0.id) }); all: \(byTable.map { ($0.groupId, $0.day, $0.startNode, $0.id) })")

        // byDay 排序 startNode
        let byDay = try db.courseDao.getByTableAndDay(tid, day: 2)
        XCTAssertEqual(2, byDay.count)
        XCTAssertEqual([1, 3], byDay.map { $0.startNode })

        // groupId 查询(组=同一门课多节次)
        _ = try db.courseDao.insert(course(tableId: tid, groupId: "g1", day: 4))
        XCTAssertEqual(2, try db.courseDao.getByGroupId(tid, "g1").count)

        // count
        XCTAssertEqual(4, try db.courseDao.countByTable(tid))
        XCTAssertEqual(4, try db.courseDao.totalCount())
    }

    func testReplaceGroupAtomic() throws {
        let tid = try makeTable()
        try db.courseDao.insertAll([
            course(tableId: tid, groupId: "g1", day: 1),
            course(tableId: tid, groupId: "g1", day: 3),
            course(tableId: tid, groupId: "g2", day: 5),
        ])
        // replaceGroup: 删 g1 两节,插三节新记录
        try db.courseDao.replaceGroup(tableId: tid, groupId: "g1", newCourses: [
            course(tableId: tid, groupId: "g1", day: 1),
            course(tableId: tid, groupId: "g1", day: 3),
            course(tableId: tid, groupId: "g1", day: 5),
        ])
        XCTAssertEqual(4, try db.courseDao.countByTable(tid)) // 3 新 + g2 1
        XCTAssertEqual(3, try db.courseDao.getByGroupId(tid, "g1").count)
    }

    func testReplaceAllAtomic() throws {
        let tid = try makeTable()
        try db.courseDao.insertAll((1...5).map { course(tableId: tid, groupId: "g\($0)") })
        try db.courseDao.replaceAll(tableId: tid, courses: [
            course(tableId: tid, groupId: "n1"), course(tableId: tid, groupId: "n2"),
        ])
        XCTAssertEqual(2, try db.courseDao.countByTable(tid))
        XCTAssertEqual(["n1", "n2"], try db.courseDao.getByTable(tid).map { $0.groupId })
    }

    func testForeignKeyCascadeDelete() throws {
        let tid = try makeTable()
        try db.courseDao.insertAll([
            course(tableId: tid, groupId: "g1"), course(tableId: tid, groupId: "g2"),
        ])
        XCTAssertEqual(2, try db.courseDao.totalCount())
        // Room: ForeignKey(onDelete = CASCADE) — 删表级联删课
        try db.timeTableDao.deleteById(tid)
        XCTAssertEqual(0, try db.courseDao.totalCount())
    }

    func testInsertConflictReplace() throws {
        let tid = try makeTable()
        var c = course(tableId: tid, groupId: "g1")
        try db.courseDao.insert(c)
        let first = try XCTUnwrap(try db.courseDao.getByTable(tid).first)
        // OnConflictStrategy.REPLACE: 同主键再插 → 覆盖
        var c2 = first
        c2.room = "B202"
        try db.courseDao.insert(c2)
        XCTAssertEqual(1, try db.courseDao.countByTable(tid))
        XCTAssertEqual("B202", try db.courseDao.getByTable(tid).first?.room)
    }

    // ---- schema parity: 列集与 Room @Entity 注解一致 ----

    func testSchemaParity() throws {
        // PRAGMA 走 Row 读取 name 列,别手解析分隔字符串
        let courseCols = try Set(db.dbQueue.read { try Row.fetchAll($0, sql: "PRAGMA table_info(courses)").map { (r: Row) -> String in r["name"] } })
        XCTAssertEqual(["id","groupId","tableId","courseName","teacher","room","note","day",
                        "startNode","step","startWeek","endWeek","type","color","ownTime",
                        "startTime","endTime","credit","level"], courseCols)
        let tableCols = try Set(db.dbQueue.read { try Row.fetchAll($0, sql: "PRAGMA table_info(time_tables)").map { (r: Row) -> String in r["name"] } })
        XCTAssertEqual(["id","name","startDate","maxWeek","nodesPerDay","timeJson","color",
                        "isDefault","smartConfigJson","createdAt"], tableCols)
        // FK 声明存在且 ON DELETE CASCADE (PRAGMA 行 = Row,列: id/seq/table/from/to/on_update/on_delete)
        let fk = try db.dbQueue.read { try Row.fetchAll($0, sql: "PRAGMA foreign_key_list(courses)") }
        let fkInfo = fk.map { (r: Row) -> (String, String) in (r["table"], r["on_delete"]) }
        XCTAssertTrue(fkInfo.contains { $0.0 == "time_tables" }, "FK 指向 time_tables, got \(fkInfo)")
        XCTAssertTrue(fkInfo.contains { $0.0 == "time_tables" && $0.1 == "CASCADE" }, "FK 级联删除, got \(fkInfo)")
        // 索引 parity
        let idx = try db.dbQueue.read { try String.fetchAll($0, sql: "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='courses' AND name NOT LIKE 'sqlite_autoindex%'") }
        XCTAssertEqual(3, idx.count, "Room 声明 3 索引: tableId / day / (startWeek,endWeek)")
    }
}
