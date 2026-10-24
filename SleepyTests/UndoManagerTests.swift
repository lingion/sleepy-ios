// UndoManagerTests.swift — ← UndoManagerTest.kt (对齐安卓 12 用例语义, GPL-3.0)

import XCTest
@testable import Sleepy

final class UndoManagerTests: XCTestCase {

    private func course(_ id: Int64) -> CourseEntity {
        var c = CourseEntity(groupId: "g\(id)", tableId: 1, courseName: "C\(id)",
                             day: 1, startNode: 1, step: 2, startWeek: 1, endWeek: 16, color: "")
        c.id = id
        return c
    }

    private func table(_ id: Int64, isDefault: Bool = false) -> TimeTableEntity {
        var t = TimeTableEntity(name: "T\(id)", startDate: "2026-09-01")
        t.id = id
        t.isDefault = isDefault
        return t
    }

    // 默认参数不能引用前序参数(Swift 规则), 兜底名在函数体内做
    private func periodTable(_ id: Int64, name: String? = nil) -> PeriodTableEntity {
        var p = PeriodTableEntity(name: name ?? "P\(id)")
        p.id = id
        return p
    }

    override func setUp() {
        super.setUp()
        UndoManager.shared.clear()
        UndoManager.shared.restoring = false
    }

    func testCaptureAndPollReturnsSnapshot() {
        let tables = [table(1, isDefault: true)]
        let courses = [course(1), course(2)]
        UndoManager.shared.capture(tables: tables, courses: courses, defaultTableId: 1)
        XCTAssertTrue(RunLoop.spin(until: { UndoManager.shared.hasSnapshot }))
        let snap = UndoManager.shared.poll()
        XCTAssertNotNil(snap)
        XCTAssertEqual(snap?.tables.map { $0.id }, [1])
        XCTAssertEqual(snap?.courses.map { $0.id }, [1, 2])
        XCTAssertEqual(snap?.defaultTableId, 1)
        // poll 取走即清空
        XCTAssertFalse(UndoManager.shared.hasSnapshot)
        XCTAssertNil(UndoManager.shared.poll())
    }

    func testCaptureOverwritesSlotSingleWriteSemantics() {
        UndoManager.shared.capture(tables: [table(1)], courses: [course(1)], defaultTableId: 1)
        UndoManager.shared.capture(tables: [table(2)], courses: [course(2)], defaultTableId: 2)
        // capture 现已同步落槽 — 直接断言槽被第二次覆盖(单写动作语义),无需泵循环
        let snap = UndoManager.shared.poll()
        XCTAssertEqual(snap?.tables.first?.id, 2)
        XCTAssertEqual(snap?.courses.first?.id, 2)
    }

    func testBatchKeepsFirstCaptureOnly() {
        UndoManager.shared.beginBatch()
        UndoManager.shared.capture(tables: [table(1)], courses: [], defaultTableId: 1)
        UndoManager.shared.capture(tables: [table(2)], courses: [], defaultTableId: 2)
        UndoManager.shared.endBatch()
        _ = RunLoop.spin(until: { UndoManager.shared.hasSnapshot })
        // 批内多次 capture 只保第一次 = 复合动作回退到动作前时点
        XCTAssertEqual(UndoManager.shared.poll()?.tables.first?.id, 1)
    }

    func testRestoringSuppressesCapture() {
        UndoManager.shared.restoring = true
        UndoManager.shared.capture(tables: [table(1)], courses: [], defaultTableId: 1)
        // restoring 期间 capture 被抑制
        RunLoop.spin(until: { false }, limit: 0.1)
        XCTAssertFalse(UndoManager.shared.hasSnapshot)
        UndoManager.shared.restoring = false
    }

    func testPollWhenEmptyReturnsNil() {
        XCTAssertNil(UndoManager.shared.poll())
        XCTAssertFalse(UndoManager.shared.hasSnapshot)
    }

    /// 用户 2026-09-10 报: 复制课表(动作A留旧快照) → 追加导入(动作B开批) → 撤回 → 副本被撤没。
    /// 语义: 每个新动作的快照必须锚定本动作开始前, 旧快照不得复用。
    func testStaleSnapshotNotReusedByNewBatch() {
        UndoManager.shared.clear()
        // 动作A: 复制课表(非批) — 留下指向"复制前"的快照
        UndoManager.shared.capture(tables: [table(1)], courses: [], defaultTableId: 1)
        _ = RunLoop.spin(until: { UndoManager.shared.hasSnapshot })
        // 动作B: 追加导入 — beginBatch 开批, 首个 capture 必须落到"动作B开始前"的库态
        UndoManager.shared.beginBatch()
        UndoManager.shared.capture(tables: [table(1), table(2)], courses: [], defaultTableId: 1)
        let snap = UndoManager.shared.poll()
        UndoManager.shared.endBatch()
        // 旧实现: 槽里已有快照 → 跳过, poll 出来的是动作A的快照(无 id=2 副本) — 错
        // 正确: 动作B首拍生效, 快照含副本表 — 撤回只回退动作B, 副本保留
        XCTAssertNotNil(snap?.tables.first { $0.id == 2 })
    }

    /// 同族: 动作A留快照 → 动作B非批单写 → B 的 capture 也必须生效。单写语义 = 总是覆盖。
    func testSingleWriteAfterAnotherActionRecapturesFresh() {
        UndoManager.shared.clear()
        UndoManager.shared.capture(tables: [table(1)], courses: [], defaultTableId: 1)
        UndoManager.shared.capture(tables: [table(1), table(3)], courses: [], defaultTableId: 1)
        let snap = UndoManager.shared.poll()
        XCTAssertNotNil(snap?.tables.first { $0.id == 3 })
    }

    // ────────────────────────────────────────────────────────────────────
    // issue#40 — 快照须携带独立时间节次表
    // ────────────────────────────────────────────────────────────────────

    /// issue#40: 撤回快照必须含独立时间节次表, 否则撤回建时间表类动作后
    /// period_tables 残留/绑定丢失。
    func testSnapshotCarriesPeriodTablesForIssue40Undo() {
        UndoManager.shared.clear()
        let p1 = periodTable(5, name: "春季作息")
        UndoManager.shared.capture(tables: [], courses: [], defaultTableId: nil, periodTables: [p1])
        let snap = UndoManager.shared.poll()
        XCTAssertEqual(snap?.periodTables.count, 1)
        XCTAssertEqual(snap?.periodTables.first?.id, 5)
        XCTAssertEqual(snap?.periodTables.first?.name, "春季作息")
    }

    /// 兼容: 旧三参数调用不得因新参数破坏(默认空 periodTables)。
    func testLegacyThreeArgCaptureCompilesWithEmptyPeriodTables() {
        UndoManager.shared.clear()
        UndoManager.shared.capture(tables: [table(1)], courses: [], defaultTableId: 1)
        let snap = UndoManager.shared.poll()
        XCTAssertEqual(snap?.periodTables.isEmpty, true)
        XCTAssertEqual(snap?.defaultTableId, 1)
    }

    // ────────────────────────────────────────────────────────────────────
    // 2026-09-21 redo 套件 — 单级 redo 槽, 与 undo 互不抢占, 新写清 redo
    // ────────────────────────────────────────────────────────────────────

    /// redo 与 undo 是两条独立槽; recordRedo 不动 undo 槽, pollRedo 不动 undo 槽。
    func testRecordRedoAndPollRedoMutuallyExclusiveWithUndo() {
        UndoManager.shared.clear()
        let t = table(1)
        UndoManager.shared.capture(tables: [t], courses: [], defaultTableId: 1)
        var modified = t
        modified.name = "modified"
        UndoManager.shared.recordRedo(UndoSnapshot(tables: [modified], courses: [], defaultTableId: 1))
        XCTAssertTrue(UndoManager.shared.hasSnapshot)       // undo 槽仍存在
        XCTAssertTrue(UndoManager.shared.hasRedoSnapshot)   // redo 槽也存在
        let undo = UndoManager.shared.poll()
        XCTAssertEqual(undo?.tables.first?.name, "T1")
        XCTAssertFalse(UndoManager.shared.hasSnapshot)      // undo 排空
        XCTAssertTrue(UndoManager.shared.hasRedoSnapshot)   // redo 仍在(互不抢)
        let redo = UndoManager.shared.pollRedo()
        XCTAssertEqual(redo?.tables.first?.name, "modified")
        XCTAssertFalse(UndoManager.shared.hasRedoSnapshot)
    }

    /// 标准编辑器语义: undo → 改 → redo 路径废。新用户动作 = 历史分叉, redo 立即作废。
    func testCaptureClearsRedoSlotForkPrevention() {
        UndoManager.shared.clear()
        UndoManager.shared.recordRedo(UndoSnapshot(tables: [], courses: [], defaultTableId: nil))
        XCTAssertTrue(UndoManager.shared.hasRedoSnapshot)
        UndoManager.shared.capture(tables: [], courses: [], defaultTableId: nil)
        XCTAssertFalse(UndoManager.shared.hasRedoSnapshot) // capture 必清 redo
    }

    /// redo 应用快照后必须把 redo 前态成 undo(对称 — 用户再次点撤回回退 redo)。
    /// 实现把 redo 前态直接灌进 undo 槽, 不走 capture(批/抑制逻辑绕过)。
    func testReinsertForRedoSymmetryRestoresUndoSlot() {
        UndoManager.shared.clear()
        let before = UndoSnapshot(tables: [], courses: [], defaultTableId: nil)
        UndoManager.shared.reinsertForRedoSymmetry(before)
        XCTAssertTrue(UndoManager.shared.hasSnapshot)
        let snap = UndoManager.shared.poll()
        XCTAssertNotNil(snap)
        XCTAssertFalse(UndoManager.shared.hasSnapshot) // poll 即清空, 与槽内即传入值同语义
    }

    /// clear 同时清空 undo 与 redo 两槽。
    func testClearEmptiesBothUndoAndRedoSlots() {
        UndoManager.shared.clear()
        UndoManager.shared.capture(tables: [], courses: [], defaultTableId: nil)
        UndoManager.shared.recordRedo(UndoSnapshot(tables: [], courses: [], defaultTableId: nil))
        UndoManager.shared.clear()
        XCTAssertFalse(UndoManager.shared.hasSnapshot)
        XCTAssertFalse(UndoManager.shared.hasRedoSnapshot)
    }

    /// 用户原动作: A→B→C 三态演进。仓库层语义模拟:
    /// undo() 把当前态录 redo + 恢复 undo 快照; redo() 反向搬运;
    /// 关键: 用户新写动作(capture)必须清 redo, 否则历史分叉(从中间态直跳新态)。
    func testFullUndoThenRedoThenNewWriteCycle() {
        UndoManager.shared.clear()
        let a = UndoSnapshot(tables: [], courses: [], defaultTableId: nil)
        let b = UndoSnapshot(tables: [table(1)], courses: [], defaultTableId: 1)
        // 用户在 B 状态点击"撤回" → 仓库把当前态录 redo, 恢复 a
        UndoManager.shared.recordRedo(b)
        UndoManager.shared.reinsertForRedoSymmetry(a)
        XCTAssertTrue(UndoManager.shared.hasSnapshot)
        XCTAssertTrue(UndoManager.shared.hasRedoSnapshot)
        // 用户点"取消撤回" → 仓库把当前态录 undo, 恢复 b
        UndoManager.shared.reinsertForRedoSymmetry(b)
        UndoManager.shared.recordRedo(a)
        // 关键: 用户做了新动作(capture) → redo 必清
        UndoManager.shared.capture(tables: [], courses: [], defaultTableId: 2)
        XCTAssertFalse(UndoManager.shared.hasRedoSnapshot) // 关键断言: 新写清 redo
    }
}

/// RunLoop 等待辅助: UndoManager.capture 走 DispatchQueue.main.async,测试需泵主循环
private func RunLoopSpin(until condition: () -> Bool, limit: TimeInterval = 1.0) -> Bool {
    let deadline = Date().addingTimeInterval(limit)
    while !condition() && Date() < deadline {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
    }
    return condition()
}

private extension RunLoop {
    static func spin(until condition: () -> Bool, limit: TimeInterval = 1.0) -> Bool {
        RunLoopSpin(until: condition, limit: limit)
    }
}
