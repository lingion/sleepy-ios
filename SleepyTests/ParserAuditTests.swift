// ParserAuditTests.swift — v1.0.37 对齐补齐的功能回归:
// AI 标记提取 / 全角归一 / dropped 行 / ICS 作息收割 / tableInfo 时间表收割 / 学期状态
import XCTest
@testable import Sleepy

final class ParserAuditTests: XCTestCase {

    // MARK: - extractMarkedBody

    func testExtractMarkedBodyStandard() {
        let text = "好的，以下是转换结果：\n<<<SLEEPY-BEGIN>>>\n高数\t张三\tA101\t1\t1-2\t1-16\t0\n<<<SLEEPY-END>>>\n希望对你有帮助"
        let body = ScheduleParser.extractMarkedBody(text)
        XCTAssertTrue(body.contains("高数"))
        XCTAssertFalse(body.contains("BEGIN"))
        XCTAssertFalse(body.contains("希望"))
    }

    func testExtractMarkedBodyTolerantMarkers() {
        // 少横线 + 大小写 + 花括号
        let text = "{{SLEEPY begin}}\n英语\t李四\tB202\t3\t3-4\t1-16\t1\n{{sleepy end}}"
        let body = ScheduleParser.extractMarkedBody(text)
        XCTAssertTrue(body.contains("英语"))
    }

    func testExtractMarkedBodyBeginOnly() {
        let body = ScheduleParser.extractMarkedBody("废话\n<<SLEEPY-BEGIN>>\n体育\t-\t-\t5\t3\t1-16\t2")
        XCTAssertTrue(body.contains("体育"))
        XCTAssertFalse(body.contains("废话"))
    }

    func testExtractMarkedBodyNoMarkers() {
        XCTAssertEqual(ScheduleParser.extractMarkedBody("普通文本"), "普通文本")
    }

    // MARK: - normalizeFullWidth

    func testNormalizeFullWidthDigitsAndDash() {
        XCTAssertEqual(ScheduleParser.normalizeFullWidth("１－２"), "1-2")
        XCTAssertEqual(ScheduleParser.normalizeFullWidth("１～１６"), "1~16")
    }

    func testParseFullWidthCourseLineEndToEnd() {
        // 全角 １－２ 不归一就会静默丢行 — 归一后应解析成功
        let text = "高等数学\t张三\tA101\t1\t１－２\t1-16\t0"
        guard case .success(let r) = ScheduleParser.parse(text, defaultTableId: 1) else {
            return XCTFail("全角节次应能解析")
        }
        XCTAssertEqual(r.courses.count, 1)
        XCTAssertEqual(r.courses[0].startNode, 1)
        XCTAssertEqual(r.courses[0].step, 2)
    }

    // MARK: - droppedLines

    func testDroppedLinesCollected() {
        let text = "高等数学\t张三\tA101\t1\t1-2\t1-16\t0\n这行是废话\n另一行也是废话xxxx"
        guard case .success(let r) = ScheduleParser.parse(text, defaultTableId: 1) else {
            return XCTFail("应解析成功")
        }
        XCTAssertEqual(r.courses.count, 1)
        XCTAssertEqual(r.droppedLines.count, 2)
        XCTAssertTrue(r.droppedLines[0].contains("废话"))
    }

    func testMarkdownTableStripped() {
        let text = "| 课程 | 老师 | 教室 | 星期 | 节次 | 周次 |\n|---|---|---|---|---|---|\n| 高等数学 | 张三 | A101 | 1 | 1-2 | 1-16 |"
        guard case .success(let r) = ScheduleParser.parse(text, defaultTableId: 1) else {
            return XCTFail("Markdown 表格行应能解析")
        }
        XCTAssertEqual(r.courses.count, 1)
        // 表头行"星期"列 parseDay 失败 → 与 Android 同语义进 dropped(非静默丢)
        XCTAssertEqual(r.droppedLines.count, 1)
    }

    func testOutOfRangeDayClamped() {
        let text = "高等数学\t张三\tA101\t8\t1-2\t1-16\t0"
        guard case .success(let r) = ScheduleParser.parse(text, defaultTableId: 1) else {
            return XCTFail("越界星期应钳到 1..7")
        }
        XCTAssertEqual(r.courses[0].day, 7)
    }

    func testReversedRangeSorted() {
        let text = "高等数学\t张三\tA101\t1\t1-2\t16-1\t0"
        guard case .success(let r) = ScheduleParser.parse(text, defaultTableId: 1) else {
            return XCTFail("反写区间应自动排序")
        }
        XCTAssertEqual(r.courses[0].startWeek, 1)
        XCTAssertEqual(r.courses[0].endWeek, 16)
    }

    func testDayNameParsed() {
        let text = "高等数学\t张三\tA101\t周一\t1-2\t1-16\t0"
        guard case .success(let r) = ScheduleParser.parse(text, defaultTableId: 1) else {
            return XCTFail("星期列写周一应能解析")
        }
        XCTAssertEqual(r.courses[0].day, 1)
    }

    // MARK: - plain 时间表行收割

    func testPlainTimeTableHarvest() {
        let text = "第1节 08:00-09:35\n时间表 2 09:55 11:30\n高等数学\t张三\tA101\t1\t1-2\t1-16\t0"
        guard case .success(let r) = ScheduleParser.parse(text, defaultTableId: 1) else {
            return XCTFail("应解析成功")
        }
        XCTAssertEqual(r.courses.count, 1)
        XCTAssertEqual(r.droppedLines.count, 0)   // 时间行不应进 dropped
        XCTAssertEqual(r.nodesPerDay, 2)
        XCTAssertTrue(r.timeJson.contains("\"node\":1"))
        XCTAssertTrue(r.timeJson.contains("\"start\":\"08:00\""))
        XCTAssertTrue(r.timeJson.contains("\"end\":\"11:30\""))
    }

    // MARK: - tableInfo 收割

    func testHarvestSleepyTimeJson() {
        // Sleepy 导出: tableInfo.time = timeJson 原文(courses 在顶层, tableInfo 供收割)
        let timeJson = "[{\"node\":1,\"start\":\"08:00\",\"end\":\"09:35\"},{\"node\":2,\"start\":\"09:55\",\"end\":\"11:30\"}]"
        var root: [String: Any] = ["name": "我的课表"]
        root["tableInfo"] = ["startDate": "2026-09-07", "time": timeJson] as [String: Any]
        root["courses"] = [[String: Any]]()
        let data = try! JSONSerialization.data(withJSONObject: root)
        let json = String(data: data, encoding: .utf8)!
        guard case .success(let r) = ScheduleParser.parse(json, defaultTableId: 1) else {
            return XCTFail("JSON 应解析成功: \(json)")
        }
        XCTAssertEqual(r.nodesPerDay, 2)
        XCTAssertEqual(r.timeJson, timeJson)
    }

    func testHarvestWakeupTimeList() {
        let json = """
        {"name":"WakeUp表","courses":[],"tableInfo":{"timeList":[{"node":1,"startTime":"08:00","endTime":"09:35"},{"node":3,"startTime":"10:00","endTime":"11:35"}]}}
        """
        guard case .success(let r) = ScheduleParser.parse(json, defaultTableId: 1) else {
            return XCTFail("WakeUp timeList 应收割")
        }
        XCTAssertEqual(r.nodesPerDay, 3)
        XCTAssertTrue(r.timeJson.contains("\"node\":3"))
    }

    // MARK: - ICS (← IcsWakeUpImportTest.kt 全套移植)

    /// 真实文件的最小切片: 单周理论课(1-12) + 双周毛概(2-8) + 散周创业基础 + 实训 17 周
    private static let wakeUpIcs = """
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//YZune//WakeUpSchedule//EN
        BEGIN:VEVENT
        SUMMARY:算法设计与分析（理论）
        DTSTART;TZID=Asia/Shanghai:20260831T082000
        DTEND;TZID=Asia/Shanghai:20260931T100000
        RRULE:FREQ=WEEKLY;UNTIL=20261122T160000Z;INTERVAL=1
        LOCATION:三教337 王锐
        DESCRIPTION:第1 - 2节\\n三教337\\n王锐
        END:VEVENT
        BEGIN:VEVENT
        SUMMARY:毛泽东思想和中国特色社会主义理论体系概论（理论）
        DTSTART;TZID=Asia/Shanghai:20260910T132000
        DTEND;TZID=Asia/Shanghai:20260910T150000
        RRULE:FREQ=WEEKLY;UNTIL=20260916T160000Z;INTERVAL=1
        LOCATION:二教B121 赵丽娜
        DESCRIPTION:第5 - 6节\\n二教B121\\n赵丽娜
        END:VEVENT
        BEGIN:VEVENT
        SUMMARY:毛泽东思想和中国特色社会主义理论体系概论（理论）
        DTSTART;TZID=Asia/Shanghai:20260924T132000
        DTEND;TZID=Asia/Shanghai:20260924T150000
        RRULE:FREQ=WEEKLY;UNTIL=20260930T160000Z;INTERVAL=1
        LOCATION:二教B121 赵丽娜
        DESCRIPTION:第5 - 6节\\n二教B121\\n赵丽娜
        END:VEVENT
        BEGIN:VEVENT
        SUMMARY:毛泽东思想和中国特色社会主义理论体系概论（理论）
        DTSTART;TZID=Asia/Shanghai:20261008T132000
        DTEND;TZID=Asia/Shanghai:20261008T150000
        RRULE:FREQ=WEEKLY;UNTIL=20261014T160000Z;INTERVAL=1
        LOCATION:二教B121 赵丽娜
        DESCRIPTION:第5 - 6节\\n二教B121\\n赵丽娜
        END:VEVENT
        BEGIN:VEVENT
        SUMMARY:毛泽东思想和中国特色社会主义理论体系概论（理论）
        DTSTART;TZID=Asia/Shanghai:20261022T132000
        DTEND;TZID=Asia/Shanghai:20261022T150000
        RRULE:FREQ=WEEKLY;UNTIL=20261028T160000Z;INTERVAL=1
        LOCATION:二教B121 赵丽娜
        DESCRIPTION:第5 - 6节\\n二教B121\\n赵丽娜
        END:VEVENT
        BEGIN:VEVENT
        SUMMARY:创业基础（理论）
        DTSTART;TZID=Asia/Shanghai:20260908T180000
        DTEND;TZID=Asia/Shanghai:20260908T193000
        RRULE:FREQ=WEEKLY;UNTIL=20260914T160000Z;INTERVAL=1
        LOCATION:二教B203 李力
        DESCRIPTION:第9 - 10节\\n二教B203\\n李力
        END:VEVENT
        BEGIN:VEVENT
        SUMMARY:创业基础（理论）
        DTSTART;TZID=Asia/Shanghai:20261013T180000
        DTEND;TZID=Asia/Shanghai:20261013T193000
        RRULE:FREQ=WEEKLY;UNTIL=20261019T160000Z;INTERVAL=1
        LOCATION:二教B203 李力
        DESCRIPTION:第9 - 10节\\n二教B203\\n李力
        END:VEVENT
        BEGIN:VEVENT
        SUMMARY:Linux操作系统课程实训（环节）
        DTSTART;TZID=Asia/Shanghai:20261221T082000
        DTEND;TZID=Asia/Shanghai:20261221T120000
        RRULE:FREQ=WEEKLY;UNTIL=20261227T160000Z;INTERVAL=1
        LOCATION:三教337 辛钢
        DESCRIPTION:第1 - 4节\\n三教337\\n辛钢
        END:VEVENT
        END:VCALENDAR
        """

    func testWakeUpIcsParsesWeeksNodesTeacherAnchor() {
        guard case .success(let r) = ScheduleParser.parse(Self.wakeUpIcs, defaultTableId: 999) else {
            return XCTFail("ICS 应解析成功")
        }
        // 学期锚点 = 最早 DTSTART 所在周(2026-08-31 周一)
        XCTAssertEqual(r.startDate, "2026-08-31")
        // 算法(1-12周) + 毛概双周合并1条 + 创业基础散周2条 + 实训(17周) = 5 行
        XCTAssertEqual(r.courses.count, 5)

        let algo = r.courses.first { $0.courseName.hasPrefix("算法设计") }!
        XCTAssertEqual(algo.teacher, "王锐")
        XCTAssertEqual(algo.room, "三教337")
        XCTAssertEqual(algo.day, 1)
        XCTAssertEqual(algo.startNode, 1)
        XCTAssertEqual(algo.step, 2)
        XCTAssertEqual(algo.startWeek, 1)
        XCTAssertEqual(algo.endWeek, 12)
        XCTAssertEqual(algo.type, 0)

        let mao = r.courses.first { $0.courseName.hasPrefix("毛泽东") }!
        XCTAssertEqual(mao.startWeek, 2)
        XCTAssertEqual(mao.endWeek, 8)
        XCTAssertEqual(mao.type, 2)
        XCTAssertEqual(mao.day, 4)
        XCTAssertEqual(mao.startNode, 5)
        XCTAssertEqual(mao.step, 2)

        // 创业基础: 散周 2,7 不构成双周序列 → 保持独立两行
        let chuangs = r.courses.filter { $0.courseName.hasPrefix("创业") }
        XCTAssertEqual(chuangs.count, 2)
        XCTAssertEqual(Set(chuangs.map { $0.startWeek }), [2, 7])
        chuangs.forEach {
            XCTAssertEqual($0.type, 0); XCTAssertEqual($0.day, 2)
            XCTAssertEqual($0.startNode, 9); XCTAssertEqual($0.step, 2)
        }

        let practice = r.courses.first { $0.courseName.hasPrefix("Linux") }!
        XCTAssertEqual(practice.startWeek, 17)
        XCTAssertEqual(practice.endWeek, 17)
        XCTAssertEqual(practice.startNode, 1)
        XCTAssertEqual(practice.step, 4)
    }

    func testWakeUpIcsHarvestsTimeTableFromEvents() {
        guard case .success(let r) = ScheduleParser.parse(Self.wakeUpIcs, defaultTableId: 999) else {
            return XCTFail("ICS 应解析成功")
        }
        XCTAssertFalse(r.timeJson.isEmpty, "作息应被收割")
        // 事件直接给出: 1-2节@08:20-10:00, 1-4节@08:20-12:00, 5-6节@13:20-15:00, 9-10节@18:00-19:30
        // → 块锚点 1@08:20, 4@12:00, 5@13:20, 6@15:00, 9@18:00, 10@19:30
        let hmCal = Calendar(identifier: .gregorian)
        func hm(_ d: Date) -> String {
            let c = hmCal.dateComponents([.hour, .minute], from: d)
            return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
        }
        let nodes = TimeTableUtils.parseNodes(r.timeJson)
            .reduce(into: [Int: (String, String)]()) { $0[$1.node] = (hm($1.start), hm($1.end)) }
        XCTAssertEqual(nodes[1]?.0, "08:20")
        XCTAssertEqual(nodes[4]?.1, "12:00")
        XCTAssertEqual(nodes[5]?.0, "13:20")
        XCTAssertEqual(nodes[6]?.1, "15:00")
        XCTAssertEqual(nodes[9]?.0, "18:00")
        XCTAssertEqual(nodes[10]?.1, "19:30")
        XCTAssertEqual(r.nodesPerDay, 10)
    }

    func testWakeUpIcsRoomAlternatingNotFakeBiweekly() {
        let ics = """
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//YZune//WakeUpSchedule//EN
        BEGIN:VEVENT
        SUMMARY:管理心理学★
        DTSTART;TZID=Asia/Shanghai:20240507T190000
        DTEND;TZID=Asia/Shanghai:20240507T203500
        RRULE:FREQ=WEEKLY;UNTIL=20240507T160000Z;INTERVAL=1
        LOCATION:博1-A102 段鑫星
        DESCRIPTION:第9 - 10节\\n博1-A102\\n段鑫星
        END:VEVENT
        BEGIN:VEVENT
        SUMMARY:管理心理学★
        DTSTART;TZID=Asia/Shanghai:20240514T190000
        DTEND;TZID=Asia/Shanghai:20240514T203500
        RRULE:FREQ=WEEKLY;UNTIL=20240514T160000Z;INTERVAL=1
        LOCATION:博5-BC区线上教室 段鑫星
        DESCRIPTION:第9 - 10节\\n博5-BC区线上教室\\n段鑫星
        END:VEVENT
        BEGIN:VEVENT
        SUMMARY:管理心理学★
        DTSTART;TZID=Asia/Shanghai:20240521T190000
        DTEND;TZID=Asia/Shanghai:20240521T203500
        RRULE:FREQ=WEEKLY;UNTIL=20240521T160000Z;INTERVAL=1
        LOCATION:博1-A102 段鑫星
        DESCRIPTION:第9 - 10节\\n博1-A102\\n段鑫星
        END:VEVENT
        END:VCALENDAR
        """
        guard case .success(let r) = ScheduleParser.parse(ics, defaultTableId: 999) else {
            return XCTFail("ICS 应解析成功")
        }
        // 3 个逐周连续事件 → 合并为 1 行 [1,3] type=0(取首教室), 不拆成假单双周
        XCTAssertEqual(r.courses.count, 1)
        XCTAssertEqual(r.courses[0].type, 0)
        XCTAssertEqual(r.courses[0].startWeek, 1)
        XCTAssertEqual(r.courses[0].endWeek, 3)
        XCTAssertEqual(r.courses[0].day, 2)
        XCTAssertEqual(r.courses[0].startNode, 9)
        XCTAssertEqual(r.courses[0].step, 2)
        XCTAssertEqual(r.courses[0].teacher, "段鑫星")
        XCTAssertEqual(r.courses[0].room, "博1-A102")
    }

    func testWakeUpIcsTrueBiweeklyStillDetected() {
        var sb = "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//YZune//WakeUpSchedule//EN\n"
        for w in [2, 4, 6, 8] {
            let date = Calendar.isoAddDays(Calendar.isoMondayOfWeek(DateUtils.parseDate("2026-08-31")!),
                                           (w - 1) * 7 + 1)
            let d = Calendar.isoString(date).replacingOccurrences(of: "-", with: "")
            sb += """
            BEGIN:VEVENT
            SUMMARY:真双周课
            DTSTART;TZID=Asia/Shanghai:\(d)T102000
            DTEND;TZID=Asia/Shanghai:\(d)T120000
            RRULE:FREQ=WEEKLY;UNTIL=\(d)T160000Z;INTERVAL=1
            LOCATION:A101 李老师
            DESCRIPTION:第5 - 6节\\nA101\\n李老师
            END:VEVENT

            """
        }
        sb += "END:VCALENDAR"
        guard case .success(let r) = ScheduleParser.parse(sb, defaultTableId: 999) else {
            return XCTFail("ICS 应解析成功")
        }
        XCTAssertEqual(r.courses.count, 1)
        // 锚点 = 最早事件所在周(首事件在第 2 周 → 相对周号 1,3,5,7)
        XCTAssertEqual(r.courses[0].startWeek, 1)
        XCTAssertEqual(r.courses[0].endWeek, 7)
        XCTAssertEqual(r.courses[0].type, 1, "起始周相对奇数 → 单周序列")
        XCTAssertEqual(r.courses[0].room, "A101")
    }

    func testWakeUpIcsNoTimeHarvestWhenSparse() {
        let sparse = """
        BEGIN:VCALENDAR
        VERSION:2.0
        BEGIN:VEVENT
        SUMMARY:裸课
        DTSTART;TZID=Asia/Shanghai:20260831T082000
        RRULE:FREQ=WEEKLY;INTERVAL=1
        END:VEVENT
        END:VCALENDAR
        """
        guard case .success(let r) = ScheduleParser.parse(sparse, defaultTableId: 999) else {
            return XCTFail("稀疏 ICS 应能解析")
        }
        XCTAssertTrue(r.timeJson.isEmpty)
    }

    func testSleepyIcsRoundTrip() {
        var table = TimeTableEntity(name: "T", startDate: "2026-02-23", maxWeek: 18, nodesPerDay: 13,
                                    timeJson: "[{\"node\":1,\"start\":\"08:00\",\"end\":\"08:45\"},{\"node\":2,\"start\":\"08:50\",\"end\":\"09:35\"},{\"node\":3,\"start\":\"10:00\",\"end\":\"10:45\"}]")
        table.id = 1
        table.isDefault = true
        let courses = [
            CourseEntity(groupId: "", tableId: 1, courseName: "高数", teacher: "张三", room: "A101",
                         day: 2, startNode: 1, step: 2, startWeek: 1, endWeek: 16, type: 0,
                         color: "#FF6750A4", id: 0)
        ]
        let exported = ScheduleExporter.exportIcs(table, courses)
        guard case .success(let r) = ScheduleParser.parse(exported, defaultTableId: 999) else {
            return XCTFail("自家 ICS 应能回读: \(exported)")
        }
        XCTAssertEqual(r.courses.count, 1)
        XCTAssertEqual(r.courses[0].courseName, "高数")
        XCTAssertEqual(r.courses[0].teacher, "张三")
        XCTAssertEqual(r.courses[0].room, "A101")
        XCTAssertEqual(r.courses[0].day, 2)
        XCTAssertEqual(r.courses[0].startNode, 1)
        XCTAssertEqual(r.courses[0].step, 2)
        XCTAssertEqual(r.courses[0].startWeek, 1)
        XCTAssertEqual(r.courses[0].endWeek, 16)
        XCTAssertEqual(r.courses[0].type, 0)
        XCTAssertEqual(r.startDate, "2026-02-23")
    }

    // MARK: - 学期状态

    func testSemesterStatusBeforeStart() {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        let future = f.string(from: Date().addingTimeInterval(30 * 86400))
        XCTAssertEqual(DateUtils.semesterStatus(startDate: future, maxWeek: 20), .beforeStart)
    }

    func testSemesterStatusAfterEnd() {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        let past = f.string(from: Date().addingTimeInterval(-30 * 86400))
        XCTAssertEqual(DateUtils.semesterStatus(startDate: past, maxWeek: 2), .afterEnd)
    }

    func testSemesterStatusInRange() {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        let past = f.string(from: Date().addingTimeInterval(-7 * 86400))
        XCTAssertEqual(DateUtils.semesterStatus(startDate: past, maxWeek: 20), .inRange)
    }

    // MARK: - helpers

    private func escapeForJson(_ s: String) -> String {
        s.replacingOccurrences(of: "\"", with: "\\\"")
    }
}

// MARK: - L10n 五语言键注入(v1.0.37 对齐)
final class L10nAuditTests: XCTestCase {
    func testV1037KeysPresentInBundle() {
        // 本测试随系统语言跑;键存在性(Bundle)与语言无关 — 缺键时 NSLocalizedString 返回 key 本身
        for key in ["ai_prompt_title", "ai_prompt_hint", "ai_prompt_text", "copy_prompt", "copied",
                    "format_help_spec", "format_help_example", "format_help_close",
                    "format_detail_content_desc",
                    "import_dropped_title", "import_dropped_hint",
                    "semester_not_started", "semester_ended", "today_semester_out_hint",
                    "schedule_week_prefix"] {
            XCTAssertTrue(L10n.has(key), "缺键: \(key)")
        }
        // 扁平化 spec 数组: 每格式至少 3 条
        for fmt in ["wakeup_share", "wakeup_json", "ics", "csv", "html", "plain"] {
            XCTAssertTrue(L10n.has("format_\(fmt)_spec_0"), "缺 format_\(fmt)_spec_0")
            XCTAssertTrue(L10n.has("format_\(fmt)_spec_2"), "缺 format_\(fmt)_spec_2 (每格式应≥3条)")
            XCTAssertTrue(L10n.has("format_\(fmt)_when"), "缺 format_\(fmt)_when")
            XCTAssertTrue(L10n.has("format_\(fmt)_example"), "缺 format_\(fmt)_example")
        }
    }
}
