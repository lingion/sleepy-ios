// Issue55CsvHtmlTextOwnTimeTests.swift — ← Issue55CsvHtmlTextOwnTimeTest.kt (逐用例)
// issue#55 第四/五/六通路: CSV / HTML / 文本 三路导入恢复非标准时间课程 ownTime。
// 「自定义时间/是/true/1」标记列 → ownTime; 不带则当标准作息行。

import XCTest
@testable import Sleepy

final class Issue55CsvHtmlTextOwnTimeTests: XCTestCase {

    private func parseOrThrow(_ text: String) throws -> ScheduleParser.ParseResult {
        switch ScheduleParser.parse(text, defaultTableId: 999) {
        case .success(let r): return r
        case .failure(let e): throw e
        }
    }

    private func assertOwnTime(_ course: CourseEntity, _ expectedStart: String, _ expectedEnd: String,
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(course.ownTime,
                      "ownTime 必须恢复; got ownTime=\(course.ownTime) startTime=\(course.startTime) endTime=\(course.endTime)",
                      file: file, line: line)
        XCTAssertEqual(expectedStart, course.startTime, "startTime", file: file, line: line)
        XCTAssertEqual(expectedEnd, course.endTime, "endTime", file: file, line: line)
        // 节次定位仍保留(网格布局兜底用)
        XCTAssertGreaterThanOrEqual(course.startNode, 1, file: file, line: line)
        XCTAssertGreaterThanOrEqual(course.step, 1, file: file, line: line)
    }

    // ---- CSV: 自定义时间标记 + 起止时间 ----

    func testCsv_markerYes_restoresOwnTime_andPrivateTimesExcludedFromNodeTimes() throws {
        let csv = """
            课程名,教师,教室,星期,节次,周次,类型,开始时间,结束时间,自定义时间
            晚课,李四,C301,3,11-12,1-16,每周,20:50,22:00,是
            高数,张三,A101,1,1-2,1-16,每周,08:00,08:45,否
            """
        let parsed = try parseOrThrow(csv)
        XCTAssertEqual(2, parsed.courses.count)

        let own = parsed.courses[0]
        assertOwnTime(own, "20:50", "22:00")
        XCTAssertEqual("晚课", own.courseName)
        XCTAssertEqual(3, own.day)
        XCTAssertEqual(11, own.startNode)
        XCTAssertEqual(2, own.step)

        let normal = parsed.courses[1]
        XCTAssertFalse(normal.ownTime, "普通行 ownTime 必须 false")
        XCTAssertEqual("", normal.startTime)
        XCTAssertEqual("", normal.endTime)

        // 关键契约: ownTime 行的 20:50-22:00 不应被收割进公共 timeJson
        // (晚课的真实时间由 ownTime 字段承载, 不与作息表的 08:00 系起止冲突)
        let ownStartIn = parsed.timeJson.contains("20:50")
        let ownEndIn = parsed.timeJson.contains("22:00")
        XCTAssertFalse(ownStartIn && ownEndIn,
                       "ownTime 行的时间不应进公共作息 timeJson; got: \(parsed.timeJson)")
        // 而普通行的 08:00-08:45 应正常进作息收割
        XCTAssertTrue(parsed.timeJson.contains("08:00"),
                      "非 ownTime 行的时间应正常进作息; got: \(parsed.timeJson)")
    }

    func testCsv_markerTrue_caseInsensitive_restoresOwnTime() throws {
        let csv = """
            课程名,教师,教室,星期,节次,周次,开始时间,结束时间,owntime
            夜自习,王五,D404,5,11,1-8,19:00,20:30,True
            """
        let c = try parseOrThrow(csv).courses[0]
        assertOwnTime(c, "19:00", "20:30")
    }

    func testCsv_markerOne_restoresOwnTime() throws {
        let csv = """
            课程名,教师,教室,星期,节次,周次,类型,开始时间,结束时间,自定义时间
            选修,赵六,E505,7,9-10,2-12,双,14:00,15:30,1
            """
        let c = try parseOrThrow(csv).courses[0]
        assertOwnTime(c, "14:00", "15:30")
    }

    func testCsv_noMarkerColumn_stillHarvestsTimes_andOwnTimeFalse() throws {
        // 普通 CSV: 无标记列 → 当作标准作息行, 不应锁 ownTime
        let csv = """
            课程名,教师,教室,星期,节次,周次,类型,开始时间,结束时间
            高数,张三,A101,1,1-2,1-16,每周,08:00,08:45
            晚课,李四,C301,3,11-12,1-16,每周,20:50,22:00
            """
        let parsed = try parseOrThrow(csv)
        XCTAssertEqual(2, parsed.courses.count)
        for c in parsed.courses {
            XCTAssertFalse(c.ownTime, "无标记列 → ownTime 必须 false")
        }
        // 普通行的两端时间都应收割
        XCTAssertTrue(parsed.timeJson.contains("08:00"))
        XCTAssertTrue(parsed.timeJson.contains("22:00"))
    }

    func testCsv_markerYesButInvalidTimeRange_demotesToOwnTimeFalse() throws {
        // 标记是,但时间非法(开始 ≥ 结束) → 视为非法行, ownTime 不锁,
        // 但行本身仍按节点落位(不静默丢), 时间列忽略
        let csv = """
            课程名,教师,教室,星期,节次,周次,开始时间,结束时间,自定义时间
            夜课,钱七,F606,4,8,1-4,22:00,20:00,是
            """
        let c = try parseOrThrow(csv).courses[0]
        XCTAssertFalse(c.ownTime, "非法时间范围 → ownTime 必须 false")
        XCTAssertEqual(4, c.day)
    }

    // ---- HTML ----

    func testHtml_markerYes_restoresOwnTime() throws {
        let html = """
            <table>
            <tr><td>课程</td><td>教师</td><td>教室</td><td>星期</td><td>节次</td><td>周次</td><td>开始时间</td><td>结束时间</td><td>自定义时间</td></tr>
            <tr><td>晚课</td><td>李四</td><td>C301</td><td>3</td><td>11-12</td><td>1-16</td><td>20:50</td><td>22:00</td><td>是</td></tr>
            <tr><td>高数</td><td>张三</td><td>A101</td><td>1</td><td>1-2</td><td>1-16</td><td>08:00</td><td>08:45</td><td></td></tr>
            </table>
            """
        let parsed = try parseOrThrow(html)
        XCTAssertEqual(2, parsed.courses.count)

        let own = parsed.courses[0]
        assertOwnTime(own, "20:50", "22:00")
        XCTAssertEqual("晚课", own.courseName)

        let normal = parsed.courses[1]
        XCTAssertFalse(normal.ownTime, "普通行 ownTime 必须 false")
    }

    func testHtml_noMarkerColumn_ignoresOwnTime() throws {
        let html = """
            <table>
            <tr><td>课程</td><td>教师</td><td>教室</td><td>星期</td><td>节次</td><td>周次</td></tr>
            <tr><td>高数</td><td>张三</td><td>A101</td><td>1</td><td>1-2</td><td>1-16</td></tr>
            </table>
            """
        let parsed = try parseOrThrow(html)
        XCTAssertEqual(1, parsed.courses.count)
        XCTAssertFalse(parsed.courses[0].ownTime)
    }

    // ---- 文本: 类型后跟钟点列 ----

    func testText_trailingTwoTimeFields_restoresOwnTime() throws {
        // 列序: 名称 老师 教室 星期 节次 周次 类型 上课开始 上课结束
        let text = "晚课\t李四\tC301\t3\t11-12\t1-16\t0\t20:50\t22:00"
        let c = try parseOrThrow(text).courses[0]
        assertOwnTime(c, "20:50", "22:00")
        XCTAssertEqual("晚课", c.courseName)
    }

    func testText_trailingSingleTimeRange_restoresOwnTime() throws {
        let text = "夜自习\t王五\tD404\t5\t11\t1-8\t0\t19:00-20:30"
        let c = try parseOrThrow(text).courses[0]
        assertOwnTime(c, "19:00", "20:30")
    }

    func testText_noTrailingTime_ownTimeFalse() throws {
        // 旧制表符格式: 7 列 = 标准课, 不应被误标 ownTime
        let text = "高数\t张三\tA101\t1\t1-2\t1-16\t0"
        let c = try parseOrThrow(text).courses[0]
        XCTAssertFalse(c.ownTime, "7 列无钟点 → ownTime 必须 false")
        XCTAssertEqual("", c.startTime)
        XCTAssertEqual("", c.endTime)
    }

    func testText_trailingInvalidTime_demotesToOwnTimeFalse() throws {
        // 类型后跟一个非法钟点(开始≥结束) → ownTime 不锁, 课按节点落位
        let text = "夜课\t钱七\tF606\t4\t8\t1-4\t0\t25:00-26:00"
        let c = try parseOrThrow(text).courses[0]
        XCTAssertFalse(c.ownTime, "非法时间 → ownTime 必须 false")
    }

    // ---- 两位补零归一(与 sleepy-v1 一致) ----

    func testCsv_singleDigitHour_normalizedToTwoDigits() throws {
        let csv = """
            课程名,教师,教室,星期,节次,周次,开始时间,结束时间,自定义时间
            早八,孙八,G707,2,1,1-16,8:00,8:45,是
            """
        let c = try parseOrThrow(csv).courses[0]
        XCTAssertEqual("08:00", c.startTime)
        XCTAssertEqual("08:45", c.endTime)
    }

    // ---- 审计防回归: isLikelyCsv 教师列不再硬性要求 (教务导出常无教师列) ----

    func testCsvWithoutTeacherColumn_nowDetected() throws {
        let csv = "课程,教室,星期,节次,周次\n高等数学,A101,1,1-2,1-16\n大学英语,B202,3,3-4,1-16"
        let r = try parseOrThrow(csv)
        XCTAssertEqual(2, r.courses.count)
        XCTAssertEqual("", r.courses[0].teacher)
    }
}
