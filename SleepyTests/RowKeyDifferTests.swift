// RowKeyDifferTests.swift — ← RowKeyDifferTest.kt 全量 9 用例 (a00007f7 别名 3 契约 + issue#22 核心 6, GPL-3.0)
// 用户报障 2026-09-11: 编辑课程别名无法保存 — fieldsDiffer 漏比 alias。
// 对齐 1.0.61: 补齐 RowKeyDifferTest.kt 的 issue#22 行级 diff 核心 6 用例。

import XCTest
@testable import Sleepy

final class RowKeyDifferTests: XCTestCase {

    /// ← RowKeyDifferTest.kt 的 course() fixture, 默认值与 Kotlin 侧一致
    private func course(_ id: Int64 = 0, gid: String = "g1", table: Int64 = 1,
                        name: String = "高数", teacher: String = "", room: String = "",
                        day: Int = 1, startNode: Int = 1, step: Int = 1,
                        startWeek: Int = 1, endWeek: Int = 16, type: Int = 0,
                        colorMode: Int = CourseColorMode.GROUP, color: String = "#FF6750A4",
                        note: String = "", alias: String = "") -> CourseEntity {
        var c = CourseEntity(groupId: gid, tableId: table, courseName: name,
                             day: day, startNode: startNode, step: step,
                             startWeek: startWeek, endWeek: endWeek, color: color)
        c.id = id
        c.teacher = teacher
        c.room = room
        c.note = note
        c.type = type
        c.colorMode = colorMode
        c.alias = alias
        return c
    }

    // ── issue#22 行级 diff/patch 核心 6 用例 (← RowKeyDifferTest.kt) ──────────

    /// 同名 3 个不同地点,server 3 行与 draft 一致 → diff 空
    func testSameNameThreeLocationsIdenticalDraftProducesEmptyDiff() {
        let server = [course(1, room: "A"), course(2, room: "B"), course(3, room: "C")]
        let draft = server // struct 值类型: 与 Kotlin it.copy() 等价
        let diff = RowKeyDiffer.diff(draft, server)
        XCTAssertTrue(diff.toInsert.isEmpty)
        XCTAssertTrue(diff.toUpdate.isEmpty)
        XCTAssertTrue(diff.toDelete.isEmpty)
    }

    /// 同名 3 行 server,草稿改 A 楼地点 → A 行 delete + A2 行 insert,其他 2 行不动
    /// (RowKey 含 room → 改地点等于换新行, 旧行删 + 新行插)
    func testChangingOneRoomDeletesOldRowAndInsertsNew() {
        let server = [course(1, room: "A"), course(2, room: "B"), course(3, room: "C")]
        let draft = [
            course(0, room: "A2"),  // 新地点 A2(新 RowKey)
            course(2, room: "B"),   // 保持
            course(3, room: "C")
        ]
        let diff = RowKeyDiffer.diff(draft, server)
        XCTAssertEqual(diff.toInsert.count, 1)
        XCTAssertEqual(diff.toInsert.first?.room, "A2")
        XCTAssertEqual(diff.toInsert.first?.id, 0)
        XCTAssertTrue(diff.toUpdate.isEmpty)
        XCTAssertEqual(diff.toDelete, [1])
    }

    /// 删 1 行 → 其他 2 行不动, 删的行 id 进 toDelete
    func testDeletingOneRowOnlyTouchesThatId() {
        let server = [course(1, room: "A"), course(2, room: "B"), course(3, room: "C")]
        let draft = [
            course(1, room: "A"),
            course(3, room: "C")
            // id=2 被删
        ]
        let diff = RowKeyDiffer.diff(draft, server)
        XCTAssertTrue(diff.toInsert.isEmpty)
        XCTAssertTrue(diff.toUpdate.isEmpty)
        XCTAssertEqual(diff.toDelete, [2])
    }

    /// 增 1 行 → 新行进 toInsert(带原 tableId 与 groupId, id=0 让 GRDB 自增)
    func testAddingOneRowKeepsGroupAndTableId() {
        let server = [course(1, room: "A"), course(2, room: "B")]
        let draft = server + [course(0, room: "D")]
        let diff = RowKeyDiffer.diff(draft, server)
        XCTAssertEqual(diff.toInsert.count, 1)
        XCTAssertEqual(diff.toInsert.first?.id, 0)
        XCTAssertEqual(diff.toInsert.first?.room, "D")
        XCTAssertEqual(diff.toInsert.first?.groupId, "g1")
        XCTAssertEqual(diff.toInsert.first?.tableId, 1)
        XCTAssertTrue(diff.toUpdate.isEmpty)
        XCTAssertTrue(diff.toDelete.isEmpty)
    }

    /// 跨 groupId 不互相影响 — g1 加行不动 g2
    func testGroupsDoNotAffectEachOther() {
        let server = [course(1, gid: "g1", room: "A"), course(2, gid: "g2", room: "B")]
        let draft = [
            course(1, gid: "g1", room: "A"),
            course(2, gid: "g2", room: "B"),
            course(0, gid: "g1", room: "A2")  // 新加到 g1
        ]
        let diff = RowKeyDiffer.diff(draft, server)
        XCTAssertEqual(diff.toInsert.count, 1)
        XCTAssertEqual(diff.toInsert.first?.groupId, "g1")
        XCTAssertTrue(diff.toDelete.isEmpty)
    }

    /// RowKey 比较不含 colorMode/note(改字段不视为新行) → 走 update 保留 id
    func testColorModeColorNoteChangesGoThroughUpdateNotDeleteInsert() {
        let server = [course(1, room: "A", colorMode: 0, color: "#FF111111", note: "旧")]
        let draft = [course(1, room: "A", colorMode: 1, color: "", note: "新")]
        let diff = RowKeyDiffer.diff(draft, server)
        XCTAssertTrue(diff.toInsert.isEmpty)
        XCTAssertTrue(diff.toDelete.isEmpty)
        XCTAssertEqual(diff.toUpdate.count, 1)
        XCTAssertEqual(diff.toUpdate.first?.id, 1)
        XCTAssertEqual(diff.toUpdate.first?.colorMode, 1)
        XCTAssertEqual(diff.toUpdate.first?.color, "")
        XCTAssertEqual(diff.toUpdate.first?.note, "新")
    }

    // ── 别名契约 3 用例 (用户报障 2026-09-11) ────────────────────────────────

    /// 只改别名 → 该行走 update 保留 id, 不删不插
    func testAliasOnlyChangeProducesUpdateKeepingId() {
        let server = [course(1)]
        let draft = [course(1, alias: "高数(强化)")]
        let diff = RowKeyDiffer.diff(draft, server)
        XCTAssertTrue(diff.toInsert.isEmpty)
        XCTAssertTrue(diff.toDelete.isEmpty)
        XCTAssertEqual(diff.toUpdate.count, 1)
        XCTAssertEqual(diff.toUpdate.first?.id, 1)
        XCTAssertEqual(diff.toUpdate.first?.alias, "高数(强化)")
    }

    /// 别名清空也是变更 — 存量行必须同步清掉
    func testAliasClearedProducesUpdateWithEmptyString() {
        let server = [course(1, alias: "高数(强化)")]
        let draft = [course(1, alias: "")]
        let diff = RowKeyDiffer.diff(draft, server)
        XCTAssertTrue(diff.toDelete.isEmpty)
        XCTAssertEqual(diff.toUpdate.count, 1)
        XCTAssertEqual(diff.toUpdate.first?.alias, "")
    }

    /// 相同别名不动 — diff 空(别让修补把跳过路径打穿成全量 update)
    func testSameAliasProducesEmptyDiff() {
        let server = [course(1, alias: "高数(强化)")]
        let draft = [course(1, alias: "高数(强化)")]
        let diff = RowKeyDiffer.diff(draft, server)
        XCTAssertTrue(diff.toInsert.isEmpty)
        XCTAssertTrue(diff.toUpdate.isEmpty)
        XCTAssertTrue(diff.toDelete.isEmpty)
    }
}
