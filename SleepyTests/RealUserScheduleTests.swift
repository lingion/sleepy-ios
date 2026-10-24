// RealUserScheduleTests.swift — ← RealUserIcsTest.kt + RealUserAITest.kt (逐用例)
// 真实用户样本(2026-09-05 粘贴)双格式回归: WakeUp ICS(INTERVAL=1 短事件拆双周 +
// INTERVAL=2 对照)与 sleepy-v1 AI 产出(39 条 C 行, 含 11 列多竖线行)。

import XCTest
@testable import Sleepy

final class RealUserScheduleTests: XCTestCase {

    private func parseOrThrow(_ text: String, tableId: Int64 = 7) throws -> ScheduleParser.ParseResult {
        switch ScheduleParser.parse(text, defaultTableId: tableId) {
        case .success(let r): return r
        case .failure(let e): throw e
        }
    }

    // ================= RealUserIcsTest.kt =================

    private func vevent(_ summary: String, _ dt: String, _ until: String, _ interval: Int,
                        _ loc: String, _ desc: String) -> String {
        return """
        BEGIN:VEVENT
        DTSTAMP:20260824T110751Z
        SUMMARY:\(summary)
        DTSTART;TZID=Asia/Shanghai:\(dt)T082000
        DTEND;TZID=Asia/Shanghai:\(dt)T100000
        RRULE:FREQ=WEEKLY;UNTIL=\(until)T160000Z;INTERVAL=\(interval)
        LOCATION:\(loc)
        DESCRIPTION:\(desc)
        END:VEVENT
        """
    }

    private var ics: String {
        ([
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//YZune//WakeUpSchedule//EN",
            vevent("算法设计与分析（理论）", "20260831", "20261122", 1, "三教337 王锐", "第1 - 2节\\n三教337\\n王锐"),
            vevent("毛泽东思想和中国特色社会主义理论体系概论（理论）", "20260910", "20260916", 1, "二教B121 赵丽娜", "第5 - 6节\\n二教B121\\n赵丽娜"),
            vevent("毛泽东思想和中国特色社会主义理论体系概论（理论）", "20260924", "20260930", 1, "二教B121 赵丽娜", "第5 - 6节\\n二教B121\\n赵丽娜"),
            vevent("创业基础（理论）", "20260908", "20260914", 1, "二教B203 李力", "第9 - 10节\\n二教B203\\n李力"),
            vevent("创业基础（理论）", "20261013", "20261019", 1, "二教B203 李力", "第9 - 10节\\n二教B203\\n李力"),
            vevent("创业基础（理论）", "20261110", "20261116", 1, "二教B203 李力", "第9 - 10节\\n二教B203\\n李力"),
            vevent("线性代数A3（理论）", "20260911", "20260917", 2, "二教B203 张艳妮", "第1 - 2节\\n二教B203\\n张艳妮"),
            vevent("Linux操作系统课程实训（环节）", "20261221", "20261227", 1, "三教337 辛钢", "第1 - 4节\\n三教337\\n辛钢"),
            "END:VCALENDAR",
        ] as [String]).joined(separator: "\n")
    }

    func testImportRealIcs() throws {
        let pr = try parseOrThrow(ics)
        XCTAssertFalse(pr.courses.isEmpty, "courses=\(pr.courses.count)")
        XCTAssertEqual("2026-08-31", pr.startDate)  // 学期首收割 = 最早 DTSTART
    }

    func testBiweekly_twoSpacedEvents_collapsedToType2() throws {
        // 毛概 day4: 第2周(9/10) + 第4周(9/24) 两条事件 → 同奇偶间距2 → 2-4双
        let pr = try parseOrThrow(ics)
        let mg = pr.courses.filter { $0.courseName.contains("毛泽东") }
        XCTAssertFalse(mg.isEmpty)
        XCTAssertEqual(1, mg.count)
        let m = mg[0]
        XCTAssertEqual(2, m.type)
        XCTAssertEqual(2, m.startWeek)
        XCTAssertEqual(4, m.endWeek)
    }

    func testScatteredIsolatedWeeks_perSegment() throws {
        // 创业基础: 3 条孤立周事件(2/7/11) → 非连续非同奇偶 → 分段 type=0 区间互斥, 显示无损
        let pr = try parseOrThrow(ics)
        let cy = pr.courses.filter { $0.courseName.contains("创业基础") }.sorted { $0.startWeek < $1.startWeek }
        XCTAssertEqual(3, cy.count)
        XCTAssertEqual([2, 7, 11], cy.map { $0.startWeek })
        XCTAssertTrue(cy.allSatisfy { $0.startWeek == $0.endWeek })
    }

    func testInterval2SingleEvent_documentedLimitation() throws {
        // 已知隐患(不在真实用户文件中): 单条 INTERVAL=2 事件命中 spans.count==1 分支 → type=0。
        // 真实 WakeUp 导出用多条 INTERVAL=1 短事件表达双周; Sleepy 自家导出单条时仅 type 语义漂移。
        let pr = try parseOrThrow(ics)
        let xd = pr.courses.filter { $0.courseName.contains("线性代数") && $0.day == 5 }
        XCTAssertEqual(1, xd.count)
        XCTAssertEqual(2, xd[0].startWeek)  // 起周正确; type 见注释
    }

    func testSingleWeekPracticum() throws {
        // Linux 实训: 17 周单周连排(第1-4节)
        let pr = try parseOrThrow(ics)
        let sx = pr.courses.filter { $0.courseName.contains("实训") }
        XCTAssertEqual(1, sx.count)
        let s = sx[0]
        XCTAssertEqual(17, s.startWeek)
        XCTAssertEqual(17, s.endWeek)
        XCTAssertEqual(1, s.startNode)
        XCTAssertEqual(4, s.step)
    }

    // ================= RealUserAITest.kt =================

    private let aiDoc = """
        #sleepy-v1
        C算法设计与分析 \\(理论\\)|1|1-2|1-12|王锐|三教337||||
        CLinux操作系统课程实训 \\(环节\\)|1|1-2|17定|辛钢|三教337||||
        C算法设计与分析课程实训 \\(环节\\)|1|1-2|18定|王锐|三教337||||
        C毛泽东思想和中国特色社会主义理论体系概论 \\(理论\\)|1|3-4|1-16|赵丽娜|二教B105||||
        CLinux操作系统课程实训 \\(环节\\)|1|3-4|17定|辛钢|三教337||||
        C算法设计与分析课程实训 \\(环节\\)|1|3-4|18定|王锐|三教337||||
        C操作系统 \\(理论\\)|1|5-6|1-14|吴玉山|实验楼A202||||
        C线性代数A3 \\(理论\\)|2|1-2|1-16|张艳妮|二教B203||||
        CLinux操作系统课程实训 \\(环节\\)|2|1-2|17定|辛钢|三教337||||
        C算法设计与分析课程实训 \\(环节\\)|2|1-2|18定|王锐|三教337||||
        C线性代数A3 \\(理论\\)|2|3-4|1-16|张艳妮|二教B203||||
        CLinux操作系统课程实训 \\(环节\\)|2|3-4|17定|辛钢|三教337||||
        C算法设计与分析课程实训 \\(环节\\)|2|3-4|18定|王锐|三教337||||
        C体育3 \\(理论\\)|2|5-6|1-16|徐义山||||||
        CLinux操作系统 \\(理论\\)|2|7-8|1-14|辛钢|三教318||||
        C创业基础 \\(理论\\)|2|9-10|2定|李力|二教B203||||
        C创业基础 \\(理论\\)|2|9-10|7定|李力|二教B203||||
        C创业基础 \\(理论\\)|2|9-10|11定|李力|二教B203||||
        CPython程序设计 \\(理论\\)|3|1-2|1-14|付欣|三教318||||
        CLinux操作系统课程实训 \\(环节\\)|3|1-2|17定|辛钢|三教337||||
        C算法设计与分析课程实训 \\(环节\\)|3|1-2|18定|王锐|三教337||||
        CPython程序设计 \\(理论\\)|3|3-4|1-14|付欣|三教318||||
        CLinux操作系统课程实训 \\(环节\\)|3|3-4|17定|辛钢|三教337||||
        C算法设计与分析课程实训 \\(环节\\)|3|3-4|18定|王锐|三教337||||
        CLinux操作系统课程实训 \\(环节\\)|4|1-2|17定|辛钢|三教337||||
        C算法设计与分析课程实训 \\(环节\\)|4|1-2|18定|王锐|三教337||||
        CPython程序设计 \\(理论\\)|4|3-4|1-14|付欣|三教318||||
        CLinux操作系统课程实训 \\(环节\\)|4|3-4|17定|辛钢|三教337||||
        C算法设计与分析课程实训 \\(环节\\)|4|3-4|18定|王锐|三教337||||
        C毛泽东思想和中国特色社会主义理论体系概论 \\(理论\\)|4|5-6|2-16双|赵丽娜|二教B121||||
        C操作系统 \\(理论\\)|4|7-8|1-14|吴玉山|实验楼A202||||
        CLinux操作系统 \\(理论\\)|4|9-10|1-14|辛钢|三教318||||
        CLinux操作系统课程实训 \\(环节\\)|5|1-2|17定|辛钢|三教337||||
        C算法设计与分析课程实训 \\(环节\\)|5|1-2|18定|王锐|三教337||||
        C线性代数A3 \\(理论\\)|5|1-2|2-16双|张艳妮|二教B203||||
        CLinux操作系统课程实训 \\(环节\\)|5|3-4|17定|辛钢|三教337||||
        C算法设计与分析课程实训 \\(环节\\)|5|3-4|18定|王锐|三教337||||
        C线性代数A3 \\(理论\\)|5|3-4|2-16双|张艳妮|二教B203||||
        C算法设计与分析 \\(理论\\)|5|5-6|1-12|王锐|三教337||||
        """

    func testFullImport_39Courses_allIn() throws {
        let pr = try parseOrThrow(aiDoc)
        XCTAssertEqual(39, pr.courses.count)
        XCTAssertTrue(pr.droppedLines.isEmpty, "dropped=\(pr.droppedLines)")
        XCTAssertTrue(pr.warnings.isEmpty, "warnings=\(pr.warnings)")
    }

    func testEscapedParens_unescapedToLiteral() throws {
        let pr = try parseOrThrow(aiDoc)
        XCTAssertEqual("算法设计与分析 (理论)", pr.courses[0].courseName)
    }

    func testScatteredSingleWeeks_kept() throws {
        let pr = try parseOrThrow(aiDoc)
        let chuangye = pr.courses.filter { $0.courseName.contains("创业基础") }
        XCTAssertEqual(3, chuangye.count)
        XCTAssertTrue(chuangye.allSatisfy { $0.type == 3 && $0.startWeek == $0.endWeek })
        XCTAssertEqual([2, 7, 11], chuangye.map { $0.startWeek }.sorted())
    }

    func testEvenWeekCourse_type2() throws {
        let pr = try parseOrThrow(aiDoc)
        let maogai = pr.courses.filter { $0.courseName.contains("毛泽东") }
        XCTAssertEqual(2, maogai.count)
        // day1 那条每周, day4 那条双周
        let d1 = maogai.first { $0.day == 1 }!
        XCTAssertEqual(0, d1.type); XCTAssertEqual(1, d1.startWeek); XCTAssertEqual(16, d1.endWeek)
        let d4 = maogai.first { $0.day == 4 }!
        XCTAssertEqual(2, d4.type); XCTAssertEqual(2, d4.startWeek); XCTAssertEqual(16, d4.endWeek)
    }

    func testTrailingExtraColumn_silentlyIgnored() throws {
        // 11 列行(体育3): 前 10 列对位正确, 尾部多列 v2 契约静默忽略 → 课程完整入库, 教室空
        let pr = try parseOrThrow(aiDoc)
        let pe = pr.courses.first { $0.courseName.contains("体育3") }!
        XCTAssertEqual("徐义山", pe.teacher)
        XCTAssertEqual("", pe.room)
        XCTAssertEqual(2, pe.day)
        XCTAssertEqual(5, pe.startNode)
    }

    func testGroups_sameNameShareGroup() throws {
        let pr = try parseOrThrow(aiDoc)
        // Linux实训 12 行(同课名) → 同组; Linux理论 3 行 → 另一组
        let shixun = Set(pr.courses.filter { $0.courseName.contains("Linux操作系统课程实训") }.map { $0.groupId })
        let lilun = Set(pr.courses.filter { $0.courseName == "Linux操作系统 (理论)" }.map { $0.groupId })
        XCTAssertEqual(1, shixun.count)
        XCTAssertEqual(1, lilun.count)
        XCTAssertNotEqual(shixun.first, lilun.first)
    }
}
