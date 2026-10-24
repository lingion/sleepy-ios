// ScheduleParserLosslessTests.swift — ← ParseNodesLosslessTest.kt + WakeUpShareNodesLosslessTest.kt
// v7.10.16k 无损收尾: 全格式路径 nodesPerDay = max(作息声明, 课程到达)。
// 用户 2026-09-03 实测: 没时间 ≠ 没有节次 — 课程到达 13 节, 解析结果必须承认 13 节。
// 另含 v1.0.56 T11 纯作息 JSON(timeList-only)路径 ← PeriodTableOnlyExportTest.kt JSON 两案。

import XCTest
@testable import Sleepy

final class ScheduleParserLosslessTests: XCTestCase {

    private func parseOrThrow(_ text: String) throws -> ScheduleParser.ParseResult {
        switch ScheduleParser.parse(text, defaultTableId: 999) {
        case .success(let r): return r
        case .failure(let e): throw e
        }
    }

    // ---- ← ParseNodesLosslessTest.kt ----

    func testSimpleTextWithoutTimeBlock_StillReportsMaxCourseNode() throws {
        let text = """
            高数 张三 A101 1 1-2 1-16
            体育 李四 操场 3 12-13 1-16
            大物 王五 B202 2 13 1-16
            """
        let parsed = try parseOrThrow(text)
        XCTAssertEqual(13, parsed.nodesPerDay, "课程到达 13 节, nodesPerDay 必须是 13")
        XCTAssertTrue(parsed.timeJson.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      "没时间块就不该伪造时间(timeJson 留空由合并层铺底)")
    }

    func testTimeBlockNodes_DoNotShrinkBelowCourseReach() throws {
        // TIME 块只声明到 10 节, 但课程到达 13 节 → 仍取 13
        let text = """
            <<<SLEEPY-TIME-BEGIN>>>
            第1节 08:00-08:45
            第10节 19:50-20:35
            <<<SLEEPY-TIME-END>>>
            高数 张三 A101 1 12-13 1-16
            """
        let parsed = try parseOrThrow(text)
        XCTAssertEqual(13, parsed.nodesPerDay, "max(作息声明, 课程到达) = 13")
    }

    // ---- ← WakeUpShareNodesLosslessTest.kt ----

    /// 用户提供的真实分享文本(课程节选, 保留 startNode/step 结构) — 与 Kotlin 同源逐字节一致
    private func shareText() -> String {
        return """
【来自Sleepy】
课程分享：

{
    "name": "补实验",
    "startDate": "2026-08-31",
    "courseDetailJson": "%5B%0A++++%7B%0A++++++++%22name%22%3A+%22%E8%BF%88%E5%85%8B%E5%B0%94%E9%80%8A-11%232003-3%22%2C%0A++++++++%22teacher%22%3A+%22%E6%9D%8E%E5%B9%B3%22%2C%0A++++++++%22position%22%3A+%2211%232003%22%2C%0A++++++++%22day%22%3A+4%2C%0A++++++++%22startNode%22%3A+11%2C%0A++++++++%22step%22%3A+3%2C%0A++++++++%22startWeek%22%3A+6%2C%0A++++++++%22endWeek%22%3A+6%2C%0A++++++++%22type%22%3A+0%2C%0A++++++++%22color%22%3A+%22%23FF6750A4%22%0A++++%7D%2C%0A++++%7B%0A++++++++%22name%22%3A+%22%E8%87%AA%E7%BB%84%E6%9C%9B%E8%BF%9C%E9%95%9C%E5%92%8C%E6%98%BE%E5%BE%AE%E9%95%9C-11%232005-3%22%2C%0A++++++++%22teacher%22%3A+%22%E7%8E%8B%E5%BE%B7%E5%85%B4%22%2C%0A++++++++%22position%22%3A+%2211%232005%22%2C%0A++++++++%22day%22%3A+4%2C%0A++++++++%22startNode%22%3A+11%2C%0A++++++++%22step%22%3A+3%2C%0A++++++++%22startWeek%22%3A+7%2C%0A++++++++%22endWeek%22%3A+7%2C%0A++++++++%22type%22%3A+0%2C%0A++++++++%22color%22%3A+%22%23FF6750A4%22%0A++++%7D%2C%0A++++%7B%0A++++++++%22name%22%3A+%22%E5%88%86%E5%85%89%E8%AE%A1-11%232008-3%22%2C%0A++++++++%22teacher%22%3A+%22%E9%99%88%E6%B7%91%E5%A6%8D%22%2C%0A++++++++%22position%22%3A+%2211%232008%22%2C%0A++++++++%22day%22%3A+4%2C%0A++++++++%22startNode%22%3A+11%2C%0A++++++++%22step%22%3A+3%2C%0A++++++++%22startWeek%22%3A+9%2C%0A++++++++%22endWeek%22%3A+9%2C%0A++++++++%22type%22%3A+0%2C%0A++++++++%22color%22%3A+%22%23FF6750A4%22%0A++++%7D%2C%0A++++%7B%0A++++++++%22name%22%3A+%22%E5%85%89%E7%BA%A4%E4%BC%A0%E6%84%9F%E3%80%81%E5%85%89%E7%BA%A4%E9%80%9A%E4%BF%A1-11%232007%2F3006%22%2C%0A++++++++%22teacher%22%3A+%22%E6%88%B4%E5%BC%BA%22%2C%0A++++++++%22position%22%3A+%2211%232007%2F3006%22%2C%0A++++++++%22day%22%3A+7%2C%0A++++++++%22startNode%22%3A+3%2C%0A++++++++%22step%22%3A+3%2C%0A++++++++%22startWeek%22%3A+6%2C%0A++++++++%22endWeek%22%3A+6%2C%0A++++++++%22type%22%3A+0%2C%0A++++++++%22color%22%3A+%22%23FF6750A4%22%0A++++%7D%2C%0A++++%7B%0A++++++++%22name%22%3A+%22%E5%AF%86%E7%AB%8B%E6%A0%B9%E6%B2%B9%E6%BB%B4-11%232006-3%22%2C%0A++++++++%22teacher%22%3A+%22%E7%8E%8B%E5%BE%B7%E5%85%B4%22%2C%0A++++++++%22position%22%3A+%2211%232006%22%2C%0A++++++++%22day%22%3A+7%2C%0A++++++++%22startNode%22%3A+3%2C%0A++++++++%22step%22%3A+3%2C%0A++++++++%22startWeek%22%3A+7%2C%0A++++++++%22endWeek%22%3A+7%2C%0A++++++++%22type%22%3A+0%2C%0A++++++++%22color%22%3A+%22%23FF6750A4%22%0A++++%7D%2C%0A++++%7B%0A++++++++%22name%22%3A+%22%E5%85%89%E7%94%B5%E6%95%88%E5%BA%94%EF%BC%8811%233001%EF%BC%89%22%2C%0A++++++++%22teacher%22%3A+%22%E5%BC%A0%E6%99%93%E5%B3%BB%22%2C%0A++++++++%22position%22%3A+%2211%233001%22%2C%0A++++++++%22day%22%3A+7%2C%0A++++++++%22startNode%22%3A+6%2C%0A++++++++%22step%22%3A+3%2C%0A++++++++%22startWeek%22%3A+9%2C%0A++++++++%22endWeek%22%3A+9%2C%0A++++++++%22type%22%3A+0%2C%0A++++++++%22color%22%3A+%22%23FF6750A4%22%0A++++%7D%2C%0A++++%7B%0A++++++++%22name%22%3A+%22%E5%85%89%E7%BA%A4%E4%BC%A0%E6%84%9F%E3%80%81%E5%85%89%E7%BA%A4%E9%80%9A%E4%BF%A1-11%232007%2F3006%22%2C%0A++++++++%22teacher%22%3A+%22%E6%88%B4%E5%BC%BA%22%2C%0A++++++++%22position%22%3A+%2211%232007%2F3006%22%2C%0A++++++++%22day%22%3A+7%2C%0A++++++++%22startNode%22%3A+6%2C%0A++++++++%22step%22%3A+3%2C%0A++++++++%22startWeek%22%3A+6%2C%0A++++++++%22endWeek%22%3A+6%2C%0A++++++++%22type%22%3A+0%2C%0A++++++++%22color%22%3A+%22%23FF6750A4%22%0A++++%7D%2C%0A++++%7B%0A++++++++%22name%22%3A+%22%E6%BC%94%E7%A4%BA%E5%AE%9E%E9%AA%8C%EF%BC%88%E9%80%B8%E5%A4%AB%E6%A5%BC110%EF%BC%89%22%2C%0A++++++++%22teacher%22%3A+%22%E7%8E%8B%E7%AB%8B%E5%AA%9B%22%2C%0A++++++++%22position%22%3A+%22%E9%80%B8%E5%A4%AB%E6%A5%BC110%22%2C%0A++++++++%22day%22%3A+7%2C%0A++++++++%22startNode%22%3A+6%2C%0A++++++++%22step%22%3A+3%2C%0A++++++++%22startWeek%22%3A+9%2C%0A++++++++%22endWeek%22%3A+9%2C%0A++++++++%22type%22%3A+0%2C%0A++++++++%22color%22%3A+%22%23FF6750A4%22%0A++++%7D%0A%5D"
}
"""
    }

    func testWakeUpShare_CoursesReach13Nodes_Reported() throws {
        let r = try parseOrThrow(shareText())
        XCTAssertEqual(8, r.courses.count, "8 门课全收")
        XCTAssertEqual(13, r.nodesPerDay, "startNode=11 step=3 → 13 节, nodesPerDay 必须是 13")
        XCTAssertTrue(r.timeJson.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      "无作息源时 timeJson 留空(不伪造时间)")
        XCTAssertEqual(11, r.courses[0].startNode, "迈克尔逊 startNode=11")
    }

    func testCsv_CoursesReachBeyondTimeTable_Reported() throws {
        // CSV: 作息列只声明 1..2 节, 但有课程在 12-13 节
        let csv = """
            课程,教师,教室,星期,节次,周次,开始时间,结束时间
            高数,张三,A101,1,12-13,1-16,,
            体育,李四,操场,2,1-2,1-16,08:00,09:40
            """
        let r = try parseOrThrow(csv)
        XCTAssertEqual(2, r.courses.count)
        XCTAssertEqual(13, r.nodesPerDay, "max(作息声明 2, 课程到达 13) = 13")
    }

    func testHtml_CoursesReachBeyond_Reported() throws {
        let html = """
            <html><body><table>
            <tr><th>课程</th><th>教师</th><th>教室</th><th>星期</th><th>节次</th><th>周次</th></tr>
            <tr><td>高数</td><td>张三</td><td>A101</td><td>1</td><td>11-13</td><td>1-16</td></tr>
            </table></body></html>
            """
        let r = try parseOrThrow(html)
        XCTAssertEqual(1, r.courses.count)
        XCTAssertEqual(13, r.nodesPerDay, "HTML 路径同样无损")
    }

    // ---- v1.0.56 T11: 纯作息 JSON(timeList-only, 无 courses)是合法形态 ----
    // ← PeriodTableOnlyExportTest.kt::json_contains_name_nodes_time /
    //   json_parses_back_to_pure_period_result

    private func periodEntity(id: Int64 = 7, name: String = "春季作息",
                              nodesPerDay: Int = 3, timeJson: String? = nil) -> PeriodTableEntity {
        var e = PeriodTableEntity(name: name)
        e.id = id
        e.nodesPerDay = nodesPerDay
        e.timeJson = timeJson ??
            "[{\"node\":1,\"start\":\"08:20\",\"end\":\"09:05\"},{\"node\":2,\"start\":\"09:15\",\"end\":\"10:00\"},{\"node\":3,\"start\":\"10:20\",\"end\":\"11:05\"}]"
        return e
    }

    func testJson_ContainsNameNodesTime() throws {
        let json = SleepyNativeExporter.exportPeriodTableJson(periodEntity())
        XCTAssertTrue(json.contains("\"name\""))
        XCTAssertTrue(json.contains("春季作息"))
        XCTAssertTrue(json.contains("\"nodesPerDay\""))
        XCTAssertTrue(json.contains("\"node\""))
        // timeList 用 WakeUp 原生字段名 — 解析端 harvest 按此收割
        XCTAssertTrue(json.contains("\"startTime\""))
        XCTAssertTrue(json.contains("\"endTime\""))
    }

    func testJson_ParsesBackToPurePeriodResult() throws {
        // 无 courses 的纯作息 JSON 不得报「找不到 courses 数组」— T9 纯作息路径
        let json = SleepyNativeExporter.exportPeriodTableJson(periodEntity())
        let r = try parseOrThrow(json)
        XCTAssertEqual(0, r.courses.count)
        let pt = try XCTUnwrap(r.periodTable, "timeList-only JSON 必须产出 periodTable")
        XCTAssertEqual("春季作息", pt.name)
        XCTAssertEqual(3, pt.nodesPerDay)
        XCTAssertEqual(3, TimeTableUtils.parseNodes(pt.timeJson).count)
        // 声明 nodesPerDay 不被压掉(v7.10.16k 无损闭环)
        XCTAssertEqual(3, r.nodesPerDay)
    }

    func testWakeUpJson_SparseTimeList_DeclaredNodesPerDayPreserved() throws {
        // tableInfo.nodesPerDay=13 但 time 只 2 行(稀疏 timeJson) → 导入不得把声明压成 2
        let json = """
            {"name":"稀疏","startDate":"2026-09-07","tableInfo":{"nodesPerDay":13,"time":"[{\\"node\\":1,\\"start\\":\\"08:00\\",\\"end\\":\\"08:45\\"},{\\"node\\":2,\\"start\\":\\"08:55\\",\\"end\\":\\"09:40\\"}]"},"courses":[{"name":"高数","day":1,"startNode":1,"step":2,"startWeek":1,"endWeek":16,"type":0}]}
            """
        let r = try parseOrThrow(json)
        XCTAssertEqual(13, r.nodesPerDay, "声明 13 > 作息行 2 → 取声明")
        XCTAssertNotNil(r.periodTable)
    }
}
