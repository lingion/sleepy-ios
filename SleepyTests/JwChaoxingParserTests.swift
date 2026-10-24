// JwChaoxingParserTests.swift — ← JwChaoxingParserTest.kt + JwChaoxingFzmjtcParserTest.kt (逐用例)
//
// 超星学习通/ChaoXing 综合教务解析器测试。
//
// 数据源:
//  - 吉林工商学院采集包 (sleepy-adapt-0905-215140, 2026-09-05)
//    → resources/chaoxing/jlbtc-grdb.json, queryKbForGrdb 个人课表 22 行单节粒度。
//  - 闽江师范高等专科学校采集包 (sleepy-adapt-20260930-153532, 2026-09-30)
//    → resources/chaoxing/fzmjtc-grdb.json, Syswin 变体 42 行单节粒度,
//      同一节因按周次换教室返回多行 — 锁死"按(课名,星期,教师)分组 + 周次并集
//      + 多教室 / 连接"的合并行为, 防止重叠课程卡回归。

import XCTest
@testable import Sleepy

final class JwChaoxingParserTests: XCTestCase {

    private func fixture(_ name: String) throws -> String {
        let bundle = Bundle(for: Self.self)
        guard let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "resources/chaoxing")
            ?? bundle.url(forResource: name, withExtension: "json", subdirectory: "chaoxing") else {
            XCTFail("fixture chaoxing/\(name).json 应打进测试 bundle")
            throw NSError(domain: "test", code: 1)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func parseJlbtc() throws -> [JwCourse] {
        try JwChaoxingParser(fixture("jlbtc-grdb")).generateCourseList()
    }

    private func parseFzmjtc() throws -> [JwCourse] {
        try JwChaoxingParser(fixture("fzmjtc-grdb")).generateCourseList()
    }

    private func single(_ src: String) throws -> [JwCourse] {
        try JwChaoxingParser(src).generateCourseList()
    }

    // MARK: - ← JwChaoxingParserTest.kt (jlbtc-grdb fixture)

    func testParses22SinglePeriodRowsInto11MergedCourses() throws { // ← `parses 22 single-period rows into 11 merged continuous-block courses`
        XCTAssertEqual(11, try parseJlbtc().count)
    }

    func testMondayAlgorithmCourseMergesPeriods12WithWeeks112() throws { // ← `monday algorithm course merges periods 1-2 with weeks 1-12`
        guard let c = try parseJlbtc().first(where: { $0.name == "算法设计与分析" && $0.day == 1 && $0.startNode == 1 }) else {
            return XCTFail("算法设计与分析 周一 1 节 应存在")
        }
        XCTAssertEqual(2, c.endNode)
        XCTAssertEqual(1, c.startWeek)
        XCTAssertEqual(12, c.endWeek)
        XCTAssertEqual(0, c.type) // 1..12 连续 → 每周
        XCTAssertEqual("王锐", c.teacher)
        XCTAssertEqual("三教337", c.room)
    }

    func testStripsAnchorTagsJlbtc() throws { // ← `strips anchor tags from course teacher and room`
        for c in try parseJlbtc() {
            XCTAssertFalse(c.name.contains("<") || c.name.contains("javascript:"), "\(c.name) 含HTML")
            XCTAssertFalse(c.teacher.contains("<"), "\(c.teacher) 含HTML")
            XCTAssertFalse(c.room.contains("<"), "\(c.room) 含HTML")
        }
    }

    func testPeCourseWithEmptyRoomKeepsBlankRoom() throws { // ← `pe course with empty room keeps blank room`
        guard let pe = try parseJlbtc().first(where: { $0.name == "体育3" }) else {
            return XCTFail("体育3 应存在")
        }
        XCTAssertEqual("", pe.room)
        XCTAssertEqual("徐义山", pe.teacher)
        XCTAssertEqual(2, pe.day)
        XCTAssertEqual(16, pe.endWeek)
    }

    func testThursdayLinuxCourseSpansPeriods910() throws { // ← `thursday linux course spans periods 9-10`
        guard let c = try parseJlbtc().first(where: { $0.name == "Linux操作系统" && $0.day == 4 }) else {
            return XCTFail("Linux操作系统 周四 应存在")
        }
        XCTAssertEqual(9, c.startNode)
        XCTAssertEqual(10, c.endNode)
        XCTAssertEqual(14, c.endWeek)
    }

    func testOddWeekOnlyCourseYieldsType1() throws { // ← `odd-week-only course yields type 1 single week`
        let src = #"{"xnxq":"2026-2027-1","rows":[ {"kcmc":"测试单周课","xjc":"3","xingqi":3,"zcstr":"1,3,5,7,9","tmc":"师","croommc":"室"} ]}"#
        let cs = try single(src)
        XCTAssertEqual(1, cs.count)
        XCTAssertEqual(1, cs[0].type)
        XCTAssertEqual(1, cs[0].startWeek)
        XCTAssertEqual(9, cs[0].endWeek)
    }

    func testEvenWeekOnlyCourseYieldsType2() throws { // ← `even-week-only course yields type 2 double week`
        let src = #"{"xnxq":"2026-2027-1","rows":[ {"kcmc":"测试双周课","xjc":"5","xingqi":5,"zcstr":"2,4,6,8,10,12","tmc":"","croommc":""} ]}"#
        let cs = try single(src)
        XCTAssertEqual(1, cs.count)
        XCTAssertEqual(2, cs[0].type)
        XCTAssertEqual(2, cs[0].startWeek)
        XCTAssertEqual(12, cs[0].endWeek)
    }

    func testGappedWeekListSplitsIntoSegments() throws { // ← `gapped week list splits into segments with same type`
        // 1,2,3,8,9 → 两段 [1-3] [8-9], 每周
        let src = #"{"xnxq":"2026-2027-1","rows":[ {"kcmc":"分段课","xjc":"1","xingqi":1,"zcstr":"1,2,3,8,9","tmc":"","croommc":""} ]}"#
        let cs = try single(src)
        XCTAssertEqual(2, cs.count)
        XCTAssert((1, 3) == (cs[0].startWeek, cs[0].endWeek))
        XCTAssert((8, 9) == (cs[1].startWeek, cs[1].endWeek))
    }

    func testMissingXjcFallsBackToRqxlRemainder() throws { // ← `missing xjc falls back to rqxl remainder`
        // xjc 缺位 → rqxl=403 → 周四第3节
        let src = #"{"xnxq":"2026-2027-1","rows":[ {"kcmc":"节次回退课","rqxl":"403","zcstr":"1-16","tmc":"","croommc":""} ]}"#
        let cs = try single(src)
        XCTAssertEqual(1, cs.count)
        XCTAssertEqual(4, cs[0].day)
        XCTAssertEqual(3, cs[0].startNode)
        XCTAssertEqual(3, cs[0].endNode)
    }

    func testZcstrDashRangeExpandsLikeCommaForm() throws { // ← `zcstr dash range form expands like comma form`
        let src = #"{"xnxq":"2026-2027-1","rows":[ {"kcmc":"区间周次课","xjc":"2","xingqi":2,"zcstr":"1-16","tmc":"","croommc":""} ]}"#
        let cs = try single(src)
        XCTAssertEqual(1, cs.count)
        XCTAssertEqual(1, cs[0].startWeek)
        XCTAssertEqual(16, cs[0].endWeek)
    }

    func testRowsWithoutWeekdayAreSkippedWithoutCrashing() throws { // ← `rows without weekday are skipped without crashing`
        let src = #"{"xnxq":"2026-2027-1","rows":[ {"kcmc":"无星期课","zcstr":"1,2"}, {"kcmc":"正常课","xjc":"1","xingqi":1,"zcstr":"1,2","tmc":"","croommc":""} ]}"#
        let cs = try single(src)
        XCTAssertEqual(1, cs.count)
        XCTAssertEqual("正常课", cs[0].name)
    }

    func testNonJsonGarbageYieldsEmptyListNotCrashJlbtc() throws { // ← `non-json garbage yields empty list not crash`
        XCTAssertTrue(try single("<html>404</html>").isEmpty)
        XCTAssertTrue(try single("").isEmpty)
    }

    // MARK: - ← JwChaoxingFzmjtcParserTest.kt (fzmjtc-grdb fixture)

    func testFzmjtcParsesRowsWithoutDuplicateOverlappingCards() throws { // ← `parses rows without duplicate overlapping cards`
        let courses = try parseFzmjtc()
        // 同(课名,星期,教师)分组: 连堂拉通 + 周次并集; 换教室多行合并后 40 条
        XCTAssertEqual(40, courses.count)
        // 关键回归: 同一(课名,星期,节次段,周次段)只允许一条 (重叠课程卡 bug)
        let keys = courses.map { "\($0.name)|\($0.day)|\($0.startNode)|\($0.endNode)|\($0.startWeek)|\($0.endWeek)" }
        XCTAssertEqual(Set(keys).count, keys.count, "存在重叠课程卡")
    }

    func testFzmjtcEnglishCourseMergesPeriodsAndSplitsWeekGap() throws { // ← `english course merges periods 1-2 and splits week gap on wednesday`
        // 大学英语 周三 1-2 节: 周次并集 3,4,5,7..19 → 间隙拆 [3-5][7-19] 两段
        let cs = try parseFzmjtc().filter { $0.name == "大学英语(一)" && $0.day == 3 }
        XCTAssertEqual(2, cs.count)
        for c in cs {
            XCTAssertEqual(1, c.startNode)
            XCTAssertEqual(2, c.endNode)
            XCTAssertEqual("叶月英", c.teacher)
            XCTAssertEqual("仓-3-501", c.room)
        }
        XCTAssertTrue(cs.contains(where: { $0.startWeek == 3 && $0.endWeek == 5 }))
        XCTAssertTrue(cs.contains(where: { $0.startWeek == 7 && $0.endWeek == 19 }))
    }

    func testFzmjtcRoomSwapCourseUnionsWeeksIntoSingleCard() throws { // ← `room swap course unions weeks into single card with both rooms`
        // 安全与急救处理 周一 3-4 节: 5-15 奇数周 A 室 + 17,19 周 B 室 → 合并到同一节块
        let cs = try parseFzmjtc().filter { $0.name == "安全与急救处理" && $0.day == 1 && $0.startNode == 3 }
        // 周次并集 5,7,9,11,13,15,17,19 全奇数 → 单周 type=1, 一段 [5,19]
        XCTAssertEqual(1, cs.count)
        let c = cs[0]
        XCTAssertEqual(4, c.endNode)
        XCTAssertEqual(1, c.type)
        XCTAssertEqual(5, c.startWeek)
        XCTAssertEqual(19, c.endWeek)
        XCTAssertTrue(c.room.contains("仓-1-703-急危重症实训室") && c.room.contains("仓-3-703"),
                      "合并卡应同时含两间教室")
    }

    func testFzmjtcThreePeriodCourseSpans57OnDay4() throws { // ← `three-period course spans periods 5-7 on day 4`
        let cs = try parseFzmjtc().filter { $0.name == "思想道德与法治" && $0.day == 4 }
        // 周次并集 3,6..19 → 间隙拆 [3-3][6-19] 两段, 都拉通 5-7 节
        XCTAssertEqual(2, cs.count)
        for c in cs {
            XCTAssertEqual(5, c.startNode)
            XCTAssertEqual(7, c.endNode)
            XCTAssertEqual("刘姝辰", c.teacher)
        }
    }

    func testStripsAnchorTagsFzmjtc() throws { // ← `strips anchor tags from course teacher and room`
        for c in try parseFzmjtc() {
            XCTAssertFalse(c.name.contains("<") || c.name.contains("javascript:"), "\(c.name) 含HTML")
            XCTAssertFalse(c.teacher.contains("<"), "\(c.teacher) 含HTML")
            XCTAssertFalse(c.room.contains("<"), "\(c.room) 含HTML")
        }
    }

    func testFzmjtcOddWeekOnlyCourseYieldsType1() throws { // ← `odd-week-only course yields type 1 single week`
        // 书写训练与工程素养 day2: zcstr=3,5,...,17 → 单周
        guard let c = try parseFzmjtc().first(where: { $0.name == "书写训练与工程素养" && $0.day == 2 }) else {
            return XCTFail("书写训练与工程素养 day2 应存在")
        }
        XCTAssertEqual(1, c.type)
        XCTAssertEqual(3, c.startWeek)
        XCTAssertEqual(17, c.endWeek)
    }

    func testFzmjtcEvenWeekOnlyCourseYieldsType2() throws { // ← `even-week-only course yields type 2 double week`
        // 大学生心理健康与促进 day5: zcstr=10,12,14 → 双周
        guard let c = try parseFzmjtc().first(where: { $0.name.hasPrefix("大学生心理健康") && $0.day == 5 }) else {
            return XCTFail("大学生心理健康 day5 应存在")
        }
        XCTAssertEqual(2, c.type)
        XCTAssertEqual(10, c.startWeek)
        XCTAssertEqual(14, c.endWeek)
    }

    func testNonJsonGarbageYieldsEmptyListNotCrashFzmjtc() throws { // ← `non-json garbage yields empty list not crash`
        XCTAssertTrue(try single("<html>404</html>").isEmpty)
        XCTAssertTrue(try single("").isEmpty)
    }

    // MARK: - 对齐 Android 行元素容错 (el.jsonObject runCatching ?: continue)

    func testMalformedRowElementSkipsOnlyThatRow() throws {
        // rows 混入非对象元素 → 只跳过该行, 其余行照常解析 (禁整数组丢弃)
        let src = #"{"xnxq":"2026-2027-1","rows":[ "garbage", {"kcmc":"有效课","xjc":"1","xingqi":1,"zcstr":"1-4","tmc":"","croommc":""} ]}"#
        let cs = try single(src)
        XCTAssertEqual(1, cs.count)
        XCTAssertEqual("有效课", cs[0].name)
    }
}
