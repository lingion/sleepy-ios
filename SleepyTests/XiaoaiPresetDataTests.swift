// XiaoaiPresetDataTests.swift — ← app/src/test/java/com/lingion/sleepy/data/parser/XiaoaiPresetDataTest.kt (v1.0.62 B6)
// 小爱课程表 presetData 契约 — 按官方 H5 (umi.js) 验证器逐条锁死, 期望值照抄 原版本 测试:
//
// - courseInfos[].weeks / sections 必须是 int 数组 (验证器 d(): Array.isArray,
//   字符串 errCode 4 直接拒收; 预览渲染 sections.filter 亦要求数组)
// - weeks 值域 [1,30] 过滤 · day [1,7] · name ≤50 字节
// - timerRes: totalWeek [1,30] · startSemester 13 位字符串 · forenoon [1,10] ·
//   afternoon/night [0,10] · 三段之和 === sections.length (P 验证器)
// - 时段边界: startTime <13:00 上午 · <18:00 下午 · 其余晚间 (f 验证器)
// - 深链: voiceassist://aiweb/?source=&flag=268468224&url=<enc>&presetData=<enc>

import XCTest
@testable import Sleepy

final class XiaoaiPresetDataTests: XCTestCase {

    // ← 原版本 DEFAULT_TIME_JSON (10 节, 与 TimeTableUtils.DEFAULT_TIME_JSON 无关)
    private let defaultTimeJson = """
        [{"node":1,"start":"08:00","end":"08:45"},
         {"node":2,"start":"08:55","end":"09:40"},
         {"node":3,"start":"10:00","end":"10:45"},
         {"node":4,"start":"10:55","end":"11:40"},
         {"node":5,"start":"12:40","end":"13:25"},
         {"node":6,"start":"13:35","end":"14:20"},
         {"node":7,"start":"14:40","end":"15:25"},
         {"node":8,"start":"15:35","end":"16:20"},
         {"node":9,"start":"18:30","end":"19:15"},
         {"node":10,"start":"19:25","end":"20:10"}]
        """

    private func table(maxWeek: Int = 18, startDate: String = "2026-09-07",
                       timeJson: String? = nil) -> TimeTableEntity {
        var t = TimeTableEntity(name: "TestUni", startDate: startDate, maxWeek: maxWeek,
                                nodesPerDay: 12, timeJson: timeJson ?? defaultTimeJson)
        t.id = 1
        return t
    }

    private func course(name: String = "高等数学", day: Int = 1, startNode: Int = 1, step: Int = 2,
                        startWeek: Int = 1, endWeek: Int = 16, type: Int = 0) -> CourseEntity {
        CourseEntity(groupId: "", tableId: 1, courseName: name, teacher: "张三", room: "A101",
                     day: day, startNode: startNode, step: step,
                     startWeek: startWeek, endWeek: endWeek, type: type, color: "#FF6750A4")
    }

    /// ← 原版本 parseImportData: 外层 {importData:"<json>"} 两段解析
    private func parseImportData(_ presetData: String) throws -> [String: Any] {
        let outer = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(presetData.utf8)) as? [String: Any])
        let inner = try XCTUnwrap(outer["importData"] as? String)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(inner.utf8)) as? [String: Any])
    }

    // ---- courseInfos ----

    func testWeeks_isIntArray_notCommaString() throws {
        let infos = XiaoaiPresetData.buildCourseInfos(courses: [course()], timeJson: defaultTimeJson)
        let weeks = try XCTUnwrap(infos[0]["weeks"] as? [Int], "weeks 必须是数组(官方 d() 验证器 Array.isArray)")
        XCTAssertEqual(Array(1...16), weeks)
    }

    func testSections_isIntArray_andExpandsStep() throws {
        let infos = XiaoaiPresetData.buildCourseInfos(courses: [course(startNode: 3, step: 3)], timeJson: defaultTimeJson)
        let sections = try XCTUnwrap(infos[0]["sections"] as? [Int], "sections 必须是数组")
        XCTAssertEqual([3, 4, 5], sections)
    }

    func testOddWeeks_type1_expandsToOddNumbersOnly() {
        XCTAssertEqual([1, 3, 5, 7, 9, 11, 13, 15], XiaoaiPresetData.expandWeeks(course(type: 1)))
    }

    func testEvenWeeks_type2_expandsToEvenNumbersOnly() {
        XCTAssertEqual([2, 4, 6, 8, 10, 12, 14, 16], XiaoaiPresetData.expandWeeks(course(type: 2)))
    }

    func testEmptyCourses_produceEmptyArray() {
        XCTAssertEqual(0, XiaoaiPresetData.buildCourseInfos(courses: [], timeJson: defaultTimeJson).count)
    }

    // ---- presetData 顶层形状 ----

    func testPresetData_shape_isV2_parserRes_timerRes() throws {
        let importData = try parseImportData(try XiaoaiPresetData.build(
            table: table(), courses: [course()], nowMillis: 1_700_000_000_000))
        XCTAssertEqual(true, try XCTUnwrap(importData["isV2"] as? Bool))
        XCTAssertEqual(0, try XCTUnwrap(importData["errorCode"] as? Int))
        XCTAssertEqual("TestUni", try XCTUnwrap(importData["schoolName"] as? String))
        XCTAssertNotNil(importData["parserRes"] as? [String: Any])
        XCTAssertNotNil(importData["timerRes"] as? [String: Any])
        XCTAssertEqual("1700000000000", try XCTUnwrap(importData["t"] as? String))
    }

    // ---- timerRes ----

    func testTimerRes_totalWeekAndStartSemester13Digits() throws {
        let importData = try parseImportData(try XiaoaiPresetData.build(table: table(), courses: [course()]))
        let timer = try XCTUnwrap(importData["timerRes"] as? [String: Any])
        XCTAssertEqual(18, try XCTUnwrap(timer["totalWeek"] as? Int))
        let startSemester = try XCTUnwrap(timer["startSemester"] as? String)
        XCTAssertEqual(13, startSemester.count, "startSemester 必须是 13 位毫秒时间戳")
        // 2026-09-07 00:00 UTC+8 = 1788710400000
        XCTAssertEqual("1788710400000", startSemester)
    }

    func testTimerRes_sectionSum_equalsForenoonAfternoonNight() throws {
        let importData = try parseImportData(try XiaoaiPresetData.build(table: table(), courses: [course()]))
        let timer = try XCTUnwrap(importData["timerRes"] as? [String: Any])
        let forenoon = try XCTUnwrap(timer["forenoon"] as? Int)
        let afternoon = try XCTUnwrap(timer["afternoon"] as? Int)
        let night = try XCTUnwrap(timer["night"] as? Int)
        let sections = try XCTUnwrap(timer["sections"] as? [[String: Any]])
        XCTAssertEqual(sections.count, forenoon + afternoon + night,
                       "官方 P 验证器: forenoon+afternoon+night 必须 === sections.length")
        // DEFAULT_TIME_JSON: <13:00 上午 5 节(1-5), <18:00 下午 3 节(6-8), 晚间 2 节(9-10)
        XCTAssertEqual(5, forenoon)
        XCTAssertEqual(3, afternoon)
        XCTAssertEqual(2, night)
    }

    func testTimerRes_sections_areSectionStartTimeEndTime() throws {
        let importData = try parseImportData(try XiaoaiPresetData.build(table: table(), courses: [course()]))
        let sections = try XCTUnwrap((try XCTUnwrap(importData["timerRes"] as? [String: Any]))["sections"] as? [[String: Any]])
        let first = try XCTUnwrap(sections.first)
        XCTAssertEqual(1, try XCTUnwrap(first["section"] as? Int))
        XCTAssertEqual("08:00", try XCTUnwrap(first["startTime"] as? String))
        XCTAssertEqual("08:45", try XCTUnwrap(first["endTime"] as? String))
    }

    // ---- 深链 ----

    func testDeepLink_schemeAndParams() throws {
        let presetData = try XiaoaiPresetData.build(table: table(), courses: [course()])
        let link = XiaoaiPresetData.deepLink(presetData)
        XCTAssertTrue(link.hasPrefix("voiceassist://aiweb/?"), "scheme 必须是 voiceassist://aiweb")
        XCTAssertTrue(link.contains("flag=268468224"), "flag 必须是 268468224")
        XCTAssertTrue(link.contains("url=https%3A%2F%2Fi.ai.mi.com"), "url 参数必须是 encode 过的 H5 地址")
        XCTAssertTrue(link.contains("presetData=%7B%22importData%22"), "presetData 参数必须存在")
        // presetData 参数可解码回原文 (← java.net.URLDecoder: '+' 还原空格)
        let enc = try XCTUnwrap(presetDataParam(in: link))
        let decoded = enc.replacingOccurrences(of: "+", with: " ").removingPercentEncoding
        XCTAssertEqual(presetData, decoded)
    }

    // ---- ownTime 归一化 ----

    func testOwnTimeCourse_isNormalizedIntoSections() throws {
        // timeToNode: 起点吸附到 start<=20:50 的最后一节 = 第10节(19:25), 无更晚节 → 单节 [10]
        var ownTime = course(name: "晚课", startNode: 9, step: 2)
        ownTime.ownTime = true
        ownTime.startTime = "20:50"
        ownTime.endTime = "22:00"
        let infos = XiaoaiPresetData.buildCourseInfos(courses: [ownTime], timeJson: defaultTimeJson)
        let sections = try XCTUnwrap(infos[0]["sections"] as? [Int])
        XCTAssertEqual([10], sections)
    }

    func testLegacyOwnTime_usesActualClockInsteadOfStaleNode() throws {
        // 真实 DB 并存的历史键形 {nodeStart,startTime,endTime} — 按实际钟点归一, 不信过期 startNode
        let legacy = defaultTimeJson
            .replacingOccurrences(of: "node", with: "nodeStart")
            .replacingOccurrences(of: "start", with: "startTime")
            .replacingOccurrences(of: "end", with: "endTime")
        var custom = course(startNode: 1)
        custom.ownTime = true
        custom.startTime = "18:30"
        custom.endTime = "20:10"
        let importData = try parseImportData(try XiaoaiPresetData.build(
            table: table(timeJson: legacy), courses: [custom]))
        let parserRes = try XCTUnwrap(importData["parserRes"] as? [String: Any])
        let courseInfos = try XCTUnwrap(parserRes["courseInfos"] as? [[String: Any]])
        let sections = try XCTUnwrap(courseInfos[0]["sections"] as? [Int])
        XCTAssertEqual([9, 10], sections)
    }

    // ---- parseTimerSections 键形兼容 ----

    func testTimerSections_acceptsLegacyNodeStartKeyShape() {
        // 真实 DB 并存的历史键形 {nodeStart,startTime,endTime} — 模拟器实测抓到
        let legacy = """
            [{"nodeStart":1,"startTime":"08:00","endTime":"08:45"},
             {"nodeStart":2,"startTime":"08:50","endTime":"09:35"}]
            """
        let sections = XiaoaiPresetData.parseTimerSections(legacy)
        XCTAssertEqual(2, sections.count)
        XCTAssertEqual(1, sections[0].node)
        XCTAssertEqual("08:00", sections[0].start)
        XCTAssertEqual("08:45", sections[0].end)
        XCTAssertEqual(2, sections[1].node)
        XCTAssertEqual("08:50", sections[1].start)
        XCTAssertEqual("09:35", sections[1].end)
    }

    func testTimerSections_acceptsImplicitSequentialNodes() {
        let sections = XiaoaiPresetData.parseTimerSections(#"[{"start":"08:00","end":"08:45"}]"#)
        XCTAssertEqual(1, sections.count)
        XCTAssertEqual(1, sections[0].node)
        XCTAssertEqual("08:00", sections[0].start)
        XCTAssertEqual("08:45", sections[0].end)
    }

    // ---- 越界拒绝 ----

    func testUnsupportedWeeks_areRejectedInsteadOfSilentlyDropped() {
        XCTAssertThrowsError(try XiaoaiPresetData.build(table: table(maxWeek: 31), courses: [course()]))
        XCTAssertThrowsError(try XiaoaiPresetData.build(table: table(), courses: [course(endWeek: 31)]))
        XCTAssertThrowsError(try XiaoaiPresetData.build(
            table: table(), courses: [course(startWeek: 2, endWeek: 2, type: 1)]))
    }

    func testInvalidPeriods_areRejectedBeforeReceiverRenumbersOrIgnoresThem() {
        let invalid = [
            #"[{"node":1,"start":"08:00","end":"08:45"},{"node":1,"start":"09:00","end":"09:45"}]"#,
            #"[{"node":2,"start":"08:00","end":"08:45"}]"#,
            #"[{"node":1,"start":"08:00","end":"09:45"},{"node":2,"start":"09:00","end":"10:00"}]"#,
            #"[{"node":1,"start":"13:00","end":"13:45"}]"#,
            #"[{"node":1,"start":"08:00","end":"28:45"}]"#,
            #"[{"node":1,"start":"08:00","end":"08:45"},{}]"#,
        ]
        for times in invalid {
            XCTAssertThrowsError(try XiaoaiPresetData.build(table: table(timeJson: times),
                                                            courses: [course(step: 1)]),
                                 "应拒绝非法节次表: \(times)")
        }
    }

    func testInvalidDate_isRejectedInsteadOfChangingSemesterToToday() {
        XCTAssertThrowsError(try XiaoaiPresetData.build(table: table(startDate: "bad-date"), courses: [course()]))
    }

    func testSessionCounts_matchReceiverBoundaryAtThirteenAndEighteen() {
        let counts = XiaoaiPresetData.inferSessionCounts([
            (node: 1, start: "12:59", end: "13:00"),
            (node: 2, start: "13:00", end: "13:45"),
            (node: 3, start: "18:00", end: "18:45"),
        ])
        XCTAssertEqual(1, counts.morning)
        XCTAssertEqual(1, counts.afternoon)
        XCTAssertEqual(1, counts.night)
    }

    /// presetData=([^&]+) 捕获组提取
    private func presetDataParam(in link: String) -> String? {
        let ns = link as NSString
        guard let regex = try? NSRegularExpression(pattern: "presetData=([^&]+)"),
              let m = regex.firstMatch(in: link, options: [],
                                       range: NSRange(location: 0, length: ns.length)),
              m.range(at: 1).location != NSNotFound else { return nil }
        return ns.substring(with: m.range(at: 1))
    }
}
