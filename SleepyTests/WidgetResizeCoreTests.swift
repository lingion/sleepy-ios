// WidgetResizeCoreTests.swift — ← WidgetResizeCoreTest.kt
// 纯逻辑测试: WidgetResizeCore — 今日系小组件 resize/导航推送世代号核心。
//
// 背景 (resize 稳定性): resize 拖拽期间系统连发 OPTIONS_CHANGED, 每次触发一次
// "后台渲染 → awm.updateAppWidget"。旧尺寸的任务若后完成, 会把新尺寸的推送覆盖回旧内容
// 且不再有后续更新来纠正 (永久 stale)。世代号 = 每个 widgetId 独立单调计数,
// commit 前校验: 变了 = 渲染期间落了更新的触发 → 本结果作废。

import XCTest
@testable import Sleepy

final class WidgetResizeCoreTests: XCTestCase {

    // ---- bump / current 基本语义 ----

    func testCurrentReturnsZeroForUnknownWidgetId() {
        XCTAssertEqual(WidgetResizeCore.current(990_001), 0)
    }

    func testBumpIncrementsMonotonicallyPerWidget() {
        let id = 990_002
        let g1 = WidgetResizeCore.bump(id)
        let g2 = WidgetResizeCore.bump(id)
        XCTAssertGreaterThan(g2, g1, "bump 必须单调递增")
        XCTAssertEqual(g2, WidgetResizeCore.current(id))
    }

    func testDifferentWidgetIdsHaveIndependentGenerations() {
        let a = 990_003
        let b = 990_004
        let ga = WidgetResizeCore.bump(a)
        _ = WidgetResizeCore.bump(b)
        _ = WidgetResizeCore.bump(b)
        XCTAssertEqual(ga, WidgetResizeCore.current(a), "别的 id 连续 bump 不得影响本 id 世代")
    }

    // ---- isStale 判定 ----

    func testIsStaleFalseRightAfterBumpWithSameSnapshot() {
        let id = 990_005
        let gen = WidgetResizeCore.bump(id)
        XCTAssertFalse(WidgetResizeCore.isStale(id, expectedGen: gen), "刚 bump 的世代未被超越 → 不 stale")
    }

    func testIsStaleTrueAfterNewerBumpSupersedesSnapshot() {
        let id = 990_006
        let gen = WidgetResizeCore.bump(id)
        _ = WidgetResizeCore.bump(id) // 模拟渲染期间落了新的 resize 触发
        XCTAssertTrue(WidgetResizeCore.isStale(id, expectedGen: gen), "被更新的触发超越 → 旧渲染结果必须作废")
    }

    func testIsStaleForUnknownIdAndGenZeroIsNotStale() {
        // gen=0 是"无世代把关"哨兵之外的合法历史值; 未知 id current=0 → gen=0 不 stale
        XCTAssertFalse(WidgetResizeCore.isStale(990_007, expectedGen: 0))
    }

    // ---- remove: 实例删除后 id 复用不误判 ----

    func testRemoveClearsGenerationSoReusedWidgetIdStartsFresh() {
        let id = 990_008
        _ = WidgetResizeCore.bump(id)
        _ = WidgetResizeCore.bump(id)
        WidgetResizeCore.remove(id)
        XCTAssertEqual(WidgetResizeCore.current(id), 0, "remove 后世代归零 (widget id 会被系统复用)")
    }

    // ---- 并发冒烟: 多线程 bump 不丢计数 ----

    func testConcurrentBumpsNeverLoseIncrements() {
        let id = 990_009
        let threads = 8
        let perThread = 50
        DispatchQueue.concurrentPerform(iterations: threads) { _ in
            for _ in 0..<perThread {
                _ = WidgetResizeCore.bump(id)
            }
        }
        XCTAssertEqual(WidgetResizeCore.current(id), Int64(threads * perThread))
        WidgetResizeCore.remove(id)
    }
}
