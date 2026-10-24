// SleepyPeriodTableParserTests.swift — ← PeriodTableRoundTripTest.kt + PeriodTableOnlyExportTest.kt
// (parser 侧断言, GPL-3.0) — issue#40 §6: sleepy-v1 P 区块 (P 头 / Pd 预设 / Pn 逐节) 的
// 解析 + 导出↔解析往返契约。
//
// 覆盖 F052 全部修复点:
// - P 分支解析(旧 iOS 把 P 系行当垃圾 dropped)
// - ParseResult.periodTable 产物(sourceId/name/nodesPerDay/timeJson 无损)
// - Pd 展开 ND_PRESET 12 节 / 纯作息零课程路径 / 二次 P 头 dropped+warning
// - isMagicLine v0 语义(本地判定 = detectVersion >= 1)
// - javaInt/javaLong 数字宽度对齐(32 位溢出 → 视为未声明, 与 Android toIntOrNull 一致)
//
// ⚠ 编译依赖 ScheduleParser.ParsedPeriodTable / ParseResult.periodTable 落地
// (见 needs_shared_wiring — F049 同步在改 ScheduleParser.swift)。

import XCTest
@testable import Sleepy

final class SleepyPeriodTableParserTests: XCTestCase {

    private func parse(_ text: String, tableId: Int64 = 999) throws -> ScheduleParser.ParseResult {
        switch ScheduleParser.parse(text, defaultTableId: tableId, defaultColor: "#FF6750A4") {
        case .success(let r): return r
        case .failure(let e): throw e
        }
    }

    // ---- ← PeriodTableRoundTripTest.kt ----

    private let twoNodeJson = "[{\"node\":1,\"start\":\"08:20\",\"end\":\"09:05\"},{\"node\":2,\"start\":\"09:15\",\"end\":\"10:00\"}]"

    private func exported(withPeriodTable: Bool) -> String {
        let pt: SleepyNativeExporter.PeriodTableExport? = withPeriodTable
            ? .init(id: 5, name: "春季作息", nodesPerDay: 2, timeJson: twoNodeJson)
            : nil
        return SleepyNativeExporter.exportFile(
            tableName: "2026 春季课表", startDate: "2026-02-23", maxWeek: 18,
            nodesPerDay: 2, timeJson: twoNodeJson, courses: [], periodTable: pt)
    }

    func testExportWithPeriodTableParsesBackLosslessly() throws {
        let parsed = try parse(exported(withPeriodTable: true))
        guard let pt = parsed.periodTable else {
            XCTFail("P 区块必须解析出来"); return
        }
        XCTAssertEqual(5, pt.sourceId)
        XCTAssertEqual("春季作息", pt.name)
        XCTAssertEqual(2, pt.nodesPerDay)
        // timeJson 往返无损(逐节时间一致)
        let rows = TimeTableUtils.parseTimeSlotRows(pt.timeJson)
        XCTAssertEqual(2, rows.count)
        XCTAssertEqual("08:20", rows[0].start)
        XCTAssertEqual("09:05", rows[0].end)
        XCTAssertEqual("09:15", rows[1].start)
        XCTAssertEqual("10:00", rows[1].end)
    }

    func testCompatTimeJsonAlwaysPresentForOldVersions() throws {
        // §6: 旧版本打开新导出文件, 至少读到每张课表内的兼容 timeJson —
        // 导出端 P 区块之外必须照常输出 N 行
        let parsed = try parse(exported(withPeriodTable: true))
        let rows = TimeTableUtils.parseTimeSlotRows(parsed.timeJson)
        XCTAssertEqual(2, rows.count, "兼容列 N 行不得因 P 区块缺失")
        XCTAssertEqual("08:20", rows[0].start)
    }

    func testExportWithoutPeriodTableYieldsNullPeriodTable() throws {
        // 旧格式(每张课表各自 timeJson): 导入端 periodTable=null → 各建一张, 不误共享
        let parsed = try parse(exported(withPeriodTable: false))
        XCTAssertNil(parsed.periodTable)
    }

    func testCrcCheckPassesWithPeriodTableBlock() throws {
        let parsed = try parse(exported(withPeriodTable: true))
        XCTAssertFalse(parsed.warnings.contains { $0.contains("校验") },
                       "P 区块不得破坏 crc 校验: warnings=\(parsed.warnings)")
    }

    func testShareTextFormRoundTripsPeriodTable() throws {
        let exported = SleepyNativeExporter.exportShareText(
            tableName: "分享课表", startDate: "2026-02-23", maxWeek: 16,
            nodesPerDay: 2, timeJson: twoNodeJson, courses: [],
            periodTable: .init(id: 9, name: "考试周作息", nodesPerDay: 2, timeJson: twoNodeJson))
        let parsed = try parse(exported)
        let pt = try XCTUnwrap(parsed.periodTable)
        XCTAssertEqual(9, pt.sourceId)
        XCTAssertEqual("考试周作息", pt.name)
    }

    func testNdPresetPeriodTableExportsAsPdAndExpandsBack() throws {
        // P 区块时间等于冻结预设时写 Pd(紧凑形), 导入端展开回 12 节
        let exported = SleepyNativeExporter.exportFile(
            tableName: "ND表", startDate: "2026-02-23", maxWeek: 16,
            nodesPerDay: 12, timeJson: TimeTableUtils.DEFAULT_TIME_JSON, courses: [],
            periodTable: .init(id: 3, name: "默认作息", nodesPerDay: 12,
                               timeJson: TimeTableUtils.DEFAULT_TIME_JSON))
        XCTAssertTrue(exported.contains("Pd"), "Pd 行必须出现")
        let parsed = try parse(exported)
        let pt = try XCTUnwrap(parsed.periodTable)
        let rows = TimeTableUtils.parseTimeSlotRows(pt.timeJson)
        XCTAssertEqual(12, rows.count)
        XCTAssertEqual("08:00", rows[0].start)
        XCTAssertEqual("22:30", rows[11].end)
    }

    // ---- ← PeriodTableOnlyExportTest.kt (parser 侧) ----

    private let threeNodeJson = "[{\"node\":1,\"start\":\"08:20\",\"end\":\"09:05\"},{\"node\":2,\"start\":\"09:15\",\"end\":\"10:00\"},{\"node\":3,\"start\":\"10:20\",\"end\":\"11:05\"}]"

    private func periodEntity(id: Int64 = 7, name: String = "春季作息",
                              nodesPerDay: Int = 3, timeJson: String? = nil) -> PeriodTableEntity {
        var e = PeriodTableEntity(name: name)
        e.id = id
        e.nodesPerDay = nodesPerDay
        e.timeJson = timeJson ?? threeNodeJson
        return e
    }

    func testPeriodOnlyShareTextParsesBackToPurePeriodResult() throws {
        // T9 纯作息导入路径: 0 课程 + periodTable 非空
        let text = SleepyNativeExporter.exportPeriodTableShareText(periodEntity())
        let r = try parse(text, tableId: 1)
        XCTAssertEqual(0, r.courses.count)
        let pt = try XCTUnwrap(r.periodTable)
        XCTAssertEqual("春季作息", pt.name)
        XCTAssertEqual(3, pt.nodesPerDay)
        let nodes = TimeTableUtils.parseNodes(pt.timeJson)
        XCTAssertEqual(3, nodes.count)
        XCTAssertEqual("08:20", hm(nodes[0].start))
        XCTAssertEqual("11:05", hm(nodes[2].end))
    }

    func testMixedExportStillCarriesCourses() throws {
        // 兜底: P 区块(带 C 行)不受影响
        let doc = "#sleepy-v1\nT表|2026-03-02|20|3\nP春季作息|7|3\nPn1|08:20|09:05\nPn2|09:15|10:00\nPn3|10:20|11:05\nC高数|2|1-2|1-16"
        let r = try parse(doc, tableId: 1)
        XCTAssertEqual(1, r.courses.count)
        XCTAssertNotNil(r.periodTable)
    }

    func testPurePeriodWithoutTimeRowsStillYieldsNullPeriodTable() throws {
        // P 头存在但零 Pn/Pd → 无法构成时间表 → periodTable=null(诚实) — T9 分支不触发
        let r = try parse("#sleepy-v1\nP春季作息|7|3\n", tableId: 1)
        XCTAssertNil(r.periodTable)
    }

    private func hm(_ date: Date) -> String {
        let cal = Calendar(identifier: .gregorian)
        return String(format: "%02d:%02d", cal.component(.hour, from: date), cal.component(.minute, from: date))
    }

    // ---- P 区块行级容错 (← SleepyNativeParser.kt parsePeriodHeader / parsePeriodNodeLine) ----

    func testMalformedPeriodHeaderDropsWithFallbackWarning() throws {
        // 非法 P 头(无 id): dropped + 表级退回 warning, 兼容列照常入库
        let r = try parse("#sleepy-v1\nC高数|2|1-2\nP|abc\n", tableId: 1)
        XCTAssertTrue(r.droppedLines.contains { $0.hasPrefix("P") }, "dropped=\(r.droppedLines)")
        XCTAssertTrue(r.warnings.contains("时间节次表区块无法解析，已退回课程表内作息"),
                      "warnings=\(r.warnings)")
        XCTAssertNil(r.periodTable)
    }

    func testDuplicatePeriodHeaderSecondDroppedNoWarning() throws {
        // 二次 P 头 = 形状异常 → dropped(不硬拒, 不再发退回 warning), 首条生效
        let r = try parse("#sleepy-v1\nP春季作息|7|3\nP秋季作息|8|4\nPn1|08:20|09:05\nC高数|2|1-2\n", tableId: 1)
        let pt = try XCTUnwrap(r.periodTable)
        XCTAssertEqual("春季作息", pt.name)
        XCTAssertEqual(7, pt.sourceId)
        XCTAssertTrue(r.droppedLines.contains { $0.hasPrefix("P秋季作息") }, "dropped=\(r.droppedLines)")
    }

    func testDuplicatePeriodNodeFirstWins() throws {
        // Pn 重复节号: 首行生效, 次行入 dropped(同 N 行语义)
        let r = try parse("#sleepy-v1\nP春季作息|7|2\nPn1|08:20|09:05\nPn1|10:00|10:45\nC高数|2|1-2\n", tableId: 1)
        let pt = try XCTUnwrap(r.periodTable)
        let rows = TimeTableUtils.parseTimeSlotRows(pt.timeJson)
        XCTAssertEqual(1, rows.count)
        XCTAssertEqual("08:20", rows[0].start)
        XCTAssertTrue(r.droppedLines.contains { $0.hasPrefix("Pn1|10:00") }, "dropped=\(r.droppedLines)")
    }

    func testBarePDroppedAndDVariantFoldsIntoPdSeen() throws {
        // 裸 "P"(无 | 无节号)→ dropped 上报不硬拒; "PDx" 走 pdSeen(kt:137), 不入 dropped
        let r = try parse("#sleepy-v1\nP\nPDx\nC高数|2|1-2\n", tableId: 1)
        XCTAssertEqual(1, r.courses.count)
        XCTAssertNil(r.periodTable)  // pdSeen 但零 P 头 → 诚实 null (kt:181)
        XCTAssertEqual(["P"], r.droppedLines, "dropped=\(r.droppedLines)")
    }

    func testPeriodHeaderMissingNodesPerDayDefaults12() throws {
        // P 头第三列缺失 → npd ?: 12 (kt:357)
        let r = try parse("#sleepy-v1\nP春季作息|7\nPn1|08:20|09:05\nC高数|2|1-2\n", tableId: 1)
        let pt = try XCTUnwrap(r.periodTable)
        XCTAssertEqual(12, pt.nodesPerDay)
    }

    // ---- isMagicLine v0 语义 (issue#6: kt:266-267 detectVersion >= 1) ----

    func testV0MagicLineIsNotMagicForParser() {
        // "#sleepy-v0" 在 Android parser 内层不算 magic: parse 直调必须抛"无 magic 文本"
        XCTAssertThrowsError(
            try SleepyNativeParser.parse("#sleepy-v0\nC高数|2|1-2", defaultTableId: 1, defaultColor: "#FF6750A4"))
        // v1 正常
        XCTAssertNoThrow(
            try SleepyNativeParser.parse("#sleepy-v1\nC高数|2|1-2", defaultTableId: 1, defaultColor: "#FF6750A4"))
    }

    // ---- 数字 token 宽度对齐 (issue#7: Java toIntOrNull = 32 位) ----

    func testSignedIntTokensAcceptedLikeJava() throws {
        // Java parseInt 接受 "+18"; maxWeek 与 P 头 id 同步验证
        let r = try parse("#sleepy-v1\nT表|2026-03-02|+18|12\nC高数|2|1-2\n", tableId: 1)
        XCTAssertEqual(18, r.maxWeek)
    }

    func testInt32OverflowTreatedAsAbsentLikeJava() throws {
        // "99999999999" 超 32 位 → Android toIntOrNull()=null(视为未声明, 走默认 20 且不报钳制);
        // 旧 iOS Int()(64 位)直接吃下 → 钳 60 + 假 warning。对齐后不得出现钳制 warning。
        let r = try parse("#sleepy-v1\nT表|2026-03-02|99999999999|12\nC高数|2|1-2\n", tableId: 1)
        XCTAssertEqual(20, r.maxWeek)
        XCTAssertFalse(r.warnings.contains { $0.contains("总周数") }, "warnings=\(r.warnings)")
    }
}
