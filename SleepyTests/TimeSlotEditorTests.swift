// TimeSlotEditorTests.swift — ← ui/component/ResolveAutoPeriodConfigContractTest.kt
// issue#23 Task 4 进自动模式配置同步契约 + v1.0.56 decodeSmartPeriodConfig。
// Android assertSame(引用恒等) 在 Swift 值语义下以 XCTAssertEqual(值恒等, 含 label) 表达
// "stored 句柄原样保留" — 分组标签仍在即证未重推断。

import XCTest
@testable import Sleepy

final class TimeSlotEditorTests: XCTestCase {

    private func row(_ node: Int, _ start: String, _ end: String,
                     edge: TimeTableUtils.EdgeClass? = nil) -> TimeTableUtils.TimeSlotRow {
        TimeTableUtils.TimeSlotRow(node: node, start: start, end: end, edgeClass: edge)
    }

    // 元组数组不满足 XCTAssertEqual 的 Equatable 约束(Swift 无 Tuple:Equatable) — 用字符串化三元组
    private func pairs(_ rows: [TimeTableUtils.TimeSlotRow]) -> [String] {
        rows.map { "\($0.node)|\($0.start)|\($0.end)" }
    }

    // 1) 手动 45/30 行 → 进自动后派生配置 primary=45, 30 组落在第 3 节, derive 回原行
    func testManualRowsBecomePrimaryWithShortGroupAtNode3() {
        let rows = [row(1, "08:00", "08:45"), row(2, "08:55", "09:40"), row(3, "10:10", "10:40")]

        let resolved = resolveAutoPeriodConfig(rows: rows, stored: nil)

        XCTAssertNotNil(resolved)
        XCTAssertEqual(45, resolved!.periodMinutes)
        XCTAssertEqual(3, resolved!.totalPeriods)
        XCTAssertEqual([DurationOption(minutes: 30)], resolved!.durations)
        XCTAssertEqual([nil, nil, 0], resolved!.periodAssignments)
        XCTAssertEqual(pairs([row(1, "08:00", "08:45"), row(2, "08:55", "09:40"), row(3, "10:10", "10:40")]),
                       pairs(resolved!.derive()))
    }

    // 2) stored 配置仍能 derive 出当前标准行 → 原样保留(含 durations 标签)
    func testStoredConfigPreservedWhenItStillDerivesCurrentRows() {
        let rows = [row(1, "08:00", "08:45"), row(2, "08:55", "09:40"), row(3, "10:10", "10:40")]
        let stored = resolveAutoPeriodConfig(rows: rows, stored: nil)!
        var labelled = stored
        labelled.durations = [DurationOption(minutes: 30, isLong: true, label: "短课")]

        let resolved = resolveAutoPeriodConfig(rows: rows, stored: labelled)

        XCTAssertEqual(labelled, resolved)
        XCTAssertEqual("短课", resolved!.durations.first!.label)
    }

    // 3) stored 配置对不上当前行 → 从当前行重推断
    func testStoredConfigReinferredWhenItNoLongerMatchesRows() {
        let originalRows = [row(1, "08:00", "08:45"), row(2, "08:55", "09:40"), row(3, "10:10", "10:40")]
        let stored = resolveAutoPeriodConfig(rows: originalRows, stored: nil)!
        // 用户改了第 3 节起止 — stored 的 derive 对不上新行
        let mutated = [row(1, "08:00", "08:45"), row(2, "08:55", "09:40"), row(3, "10:00", "10:30")]

        let resolved = resolveAutoPeriodConfig(rows: mutated, stored: stored)

        XCTAssertNotNil(resolved)
        XCTAssertEqual(45, resolved!.periodMinutes)
        XCTAssertEqual(3, resolved!.totalPeriods)
        XCTAssertEqual(pairs(mutated), pairs(resolved!.derive()))
    }

    // 4) 任何有效标准起止对 → resolve → stored 再 resolve → derive 回到原行(不动点)
    func testRoundTripPreservesEveryValidStandardPair() {
        let rows = [
            row(1, "08:00", "08:45"),
            row(2, "08:55", "09:25"),
            row(3, "10:25", "11:10"),
            row(4, "11:20", "12:05"),
            row(5, "13:30", "14:15"),
            row(6, "14:25", "14:55"),
        ]

        let firstPass = resolveAutoPeriodConfig(rows: rows, stored: nil)
        XCTAssertNotNil(firstPass)

        let secondPass = resolveAutoPeriodConfig(rows: rows, stored: firstPass)
        XCTAssertEqual(firstPass, secondPass)
        XCTAssertEqual(pairs(rows), pairs(secondPass!.derive()))
    }

    // 5) 手动→自动同步保留 edge 行, 标准行替换为派生输出
    func testMergeAutoRowsPreservesEdgeRows() {
        let before = row(0, "07:00", "07:30", edge: .before)
        let first = row(1, "08:00", "08:45")
        let after = row(4, "22:00", "23:00", edge: .after)
        let existing = [before, first, after]
        let derived = [row(1, "08:10", "08:55"), row(2, "09:05", "09:50")]

        let synced = mergeAutoRows(existingRows: existing, derivedStandardRows: derived)

        XCTAssertEqual([before, derived[0], after, derived[1]], synced)
        let edgeClasses: [TimeTableUtils.EdgeClass?] = [.some(.before), nil, .some(.after), nil]
        XCTAssertEqual(edgeClasses, synced.map { $0.edgeClass })
    }

    // edge 行永不参与推断/比对
    func testEdgeRowsExcludedFromInferenceAndMatch() {
        let standard = [row(1, "08:00", "08:45"), row(2, "08:55", "09:40"), row(3, "09:50", "10:35")]
        let rowsWithEdges = [
            row(0, "07:00", "07:59", edge: .before),
            standard[0], standard[1], standard[2],
            row(4, "22:00", "23:00", edge: .after),
        ]

        let resolved = resolveAutoPeriodConfig(rows: rowsWithEdges, stored: nil)

        XCTAssertNotNil(resolved)
        XCTAssertEqual(3, resolved!.totalPeriods)
        XCTAssertEqual(pairs(standard), pairs(resolved!.derive()))
        // 同批含 edge 行回喂: stored derive(3 标准行)与传入标准行逐行相等 → 原样保留
        XCTAssertEqual(resolved, resolveAutoPeriodConfig(rows: rowsWithEdges, stored: resolved))
    }

    // 6) 已进自动后编辑配置 → derive 仍精确同步, resolve 不静默重推断
    func testEditedAutoConfigStillSyncsDerivedRows() {
        let rows = [row(1, "08:00", "08:45"), row(2, "08:55", "09:40")]
        let resolved = resolveAutoPeriodConfig(rows: rows, stored: nil)!

        var edited = resolved
        edited.periodMinutes = 50
        XCTAssertEqual(pairs([row(1, "08:00", "08:50"), row(2, "09:00", "09:50")]),
                       pairs(edited.derive()))
        let rowsForEdited = edited.derive().map { row($0.node, $0.start, $0.end) }
        XCTAssertEqual(edited, resolveAutoPeriodConfig(rows: rowsForEdited, stored: edited))
    }

    // 重复标准节点 → nil 不抛异常
    func testDuplicateStandardNodesReturnNil() {
        let rows = [row(1, "08:00", "08:45"), row(1, "08:55", "09:40")]
        XCTAssertNil(resolveAutoPeriodConfig(rows: rows, stored: SmartPeriodConfig(totalPeriods: 2)))
    }

    // 行不可推断(空/畸形/倒序/断号) → nil, 由调用方决定兜底
    func testUninferableRowsReturnNil() {
        XCTAssertNil(resolveAutoPeriodConfig(rows: [], stored: nil))
        XCTAssertNil(resolveAutoPeriodConfig(rows: [row(1, "bad", "08:45")], stored: nil))
        XCTAssertNil(resolveAutoPeriodConfig(rows: [row(1, "09:00", "08:45")], stored: nil))
        XCTAssertNil(resolveAutoPeriodConfig(rows: [row(1, "08:00", "08:45"), row(3, "08:55", "09:40")],
                                             stored: nil))
    }

    // stored 仍能 derive 标准行时, 即使 rows 混入 edge 行也原样保留
    func testStoredPreservedWhenEdgeRowsIgnored() {
        let standard = [row(1, "08:00", "08:45"), row(2, "08:55", "09:40"), row(3, "10:10", "10:40")]
        let stored = resolveAutoPeriodConfig(rows: standard, stored: nil)!
        var labelled = stored
        labelled.durations = [DurationOption(minutes: 30, isLong: false, label: "短课")]

        let rowsWithEdges = [
            row(0, "07:00", "07:59", edge: .before),
            standard[0], standard[1], standard[2],
            row(4, "22:00", "23:00", edge: .after),
        ]

        let resolved = resolveAutoPeriodConfig(rows: rowsWithEdges, stored: labelled)

        XCTAssertEqual(labelled, resolved)
        XCTAssertEqual("短课", resolved!.durations.first!.label)
    }

    // resolve(unstored) 委托 inferSmartPeriodConfig(等价冒烟)
    func testResolveDelegatesToInferForUnstoredPath() {
        let rows = [row(1, "08:00", "08:45"), row(2, "08:55", "09:40"), row(3, "09:50", "10:35")]
        let resolved = resolveAutoPeriodConfig(rows: rows, stored: nil)
        let expected = TimeTableUtils.inferSmartPeriodConfig(rows, previous: nil)
        XCTAssertNotNil(resolved)
        XCTAssertNotNil(expected)
        XCTAssertEqual(expected!.periodMinutes, resolved!.periodMinutes)
        XCTAssertEqual(expected!.totalPeriods, resolved!.totalPeriods)
        XCTAssertEqual(expected!.durations, resolved!.durations)
        XCTAssertEqual(expected!.breaks, resolved!.breaks)
        XCTAssertEqual(expected!.periodAssignments, resolved!.periodAssignments)
        XCTAssertEqual(expected!.transitionAssignments, resolved!.transitionAssignments)
    }

    // MARK: - decodeSmartPeriodConfig ← Kotlin 顶层 helper

    func testDecodeSmartPeriodConfigNilEmptyBlankAndCorrupt() {
        XCTAssertNil(decodeSmartPeriodConfig(nil))
        XCTAssertNil(decodeSmartPeriodConfig(""))
        XCTAssertNil(decodeSmartPeriodConfig("   "))
        XCTAssertNil(decodeSmartPeriodConfig("not json"))
    }

    func testDecodeSmartPeriodConfigValidJson() {
        let json = "{\"startTime\":\"08:20\",\"periodMinutes\":40,\"totalPeriods\":6}"
        let cfg = decodeSmartPeriodConfig(json)
        XCTAssertNotNil(cfg)
        XCTAssertEqual("08:20", cfg!.startTime)
        XCTAssertEqual(40, cfg!.periodMinutes)
        XCTAssertEqual(6, cfg!.totalPeriods)
    }
}
