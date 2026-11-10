// JwScauParserTests.swift — ← 原版本 v1.0.62 JwScauParserTest.kt (逐用例移植)
//
// 华南农业大学 (SCAU, jwxt.scau.edu.cn) 解析器契约锁。
// 覆盖 原版本 侧的 13 个 regex_invariants (INV-12 跳过: 该选择器为
// AIScheduleSCAU 独有, WakeUp 主备路径均不命中) + 端到端用例。
//
// fixture: SleepyTests/resources/scau_sample.html
//   (与 原版本 app/src/test/resources/jw/scau_sample.html 逐字节一致:
//    3 行 × 7 单元格主路径 + 7 列降级路径)

import XCTest
@testable import Sleepy

final class JwScauParserTests: XCTestCase {

    // MARK: - 载入工具

    /// ← 原 `javaClass.classLoader.getResourceAsStream("jw/scau_sample.html")`
    private func sample() throws -> String {
        let bundle = Bundle(for: JwScauParserTests.self)
        guard let url = bundle.url(forResource: "scau_sample", withExtension: "html")
                ?? bundle.url(forResource: "scau_sample", withExtension: "html", subdirectory: "resources") else {
            XCTFail("测试资源 scau_sample.html 应存在")
            throw NSError(domain: "test", code: 1)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// ← 原 `JwImportViewModel.parseHtmlStatic(html, type)`
    private func parseStatic(_ html: String, _ type: String) throws -> [JwCourse] {
        try JwImportViewModel.parseHtmlStatic(html, type).courses
    }

    /// 三元组数组 → 可比较的二维整型数组(Swift 元组不满足 Equatable)。
    private func runs(_ value: [(Int, Int, Int)]) -> [[Int]] {
        value.map { [$0.0, $0.1, $0.2] }
    }

    // MARK: - 目录条目形态

    func testPinnedGreyovoElementUiShapeParsesSparseSchedule() throws {
        // ← 原 `pinned greyovo Element UI shape parses sparse schedule`
        let course = "<div style='position: relative'><div></div><div></div><div style='display:none'>课程</div>"
            + "<div>* 编译原理(理论)</div><div>方凤美</div><div>班级</div>"
            + "<div>(2-3,5-14周)</div><div>3212</div></div>"
        let html = "<div class='el-table__body-wrapper'><table class='el-table__body'>"
            + "<tbody><tr><td>1-2节</td><td>\(course)</td>" + String(repeating: "<td></td>", count: 6)
            + "</tr></tbody></table></div>"

        // 目录里 "华南农业大学" 登记的 type 是 qz(不是 scau) —— 与 原版本 同源资产。
        let catalogueType = "qz"
        let courses = try parseStatic(html, catalogueType)

        // URL 检测出的协议也要得到同一批课程。
        let detectedType = try XCTUnwrap(JwImportViewModel.detectProtocolFromUrl("http://jwxtxs.scau.edu.cn/default2.aspx"))
        let detected = try parseStatic(html, detectedType)
        XCTAssertEqual(courses, detected)

        XCTAssertEqual(2, courses.count)
        XCTAssertEqual(2, courses[0].startWeek)
        XCTAssertEqual(3, courses[0].endWeek)
        XCTAssertEqual(5, courses[1].startWeek)
        XCTAssertEqual(14, courses[1].endWeek)
        XCTAssertEqual(1, courses[0].day)
        XCTAssertEqual(1, courses[0].startNode)
        XCTAssertEqual(2, courses[0].endNode)
    }

    func testSparseWeeksPreserveGapsAndInvalidWeeksCreateNoCourse() throws {
        // ← 原 `sparse weeks preserve gaps and invalid weeks create no course`
        let parser = JwScauParser(try sample())
        XCTAssertEqual([[1, 4, 0], [6, 8, 0]], runs(parser.parseWeekRuns("1-4,6-8周")))
        XCTAssertEqual([], runs(parser.parseWeekRuns("待定")))
        let (rs, re) = parser.parseWeekRange(["", "", "待定"], weeksLineIndex: 2)
        XCTAssertEqual(0, rs)
        XCTAssertEqual(0, re)
        XCTAssertEqual([[1, 7, 1], [10, 16, 2]], runs(parser.parseWeekRuns("1-8单周,10-16双周")))
    }

    func testExplicitMalformedElementUiSectionsDoNotInventRowDefaults() throws {
        // ← 原 `explicit malformed Element UI sections do not invent row defaults`
        let base = "<div style='position:relative'><div></div><div></div><div></div>"
            + "<div>课</div><div></div><div>班</div><div>366-367节(1-8周)</div><div>室</div></div>"
        let html = "<div class='el-table__body-wrapper'><table class='el-table__body'><tbody>"
            + "<tr><td>1-2节</td><td>\(base)</td>" + String(repeating: "<td></td>", count: 6) + "</tr>"
            + "</tbody></table></div>"
        XCTAssertTrue(try JwScauParser(html).generateCourseList().isEmpty)
        // Explicit high physical nodes remain valid inside the v1.0.64 resource bound.
        let valid = try JwScauParser(html.replacingOccurrences(of: "366-367节", with: "99-100节")).generateCourseList()
        XCTAssertEqual(valid.map(\.startNode), [99])
        XCTAssertEqual(valid.map(\.endNode), [100])
    }

    func testSeventhElementUiRowAcceptsExplicitSection() throws {
        // ← 原 `seventh Element UI row accepts explicit section`
        let course = "<div style='position: relative'><div></div><div></div><div></div>"
            + "<div>夜课</div><div></div><div>班</div><div>16-17节(1-8周)</div><div>室</div></div>"
        let blank = "<tr><td>1-2节</td>" + String(repeating: "<td></td>", count: 7) + "</tr>"
        let html = "<div class='el-table__body-wrapper'><table class='el-table__body'><tbody>"
            + String(repeating: blank, count: 6) + "<tr><td>16-17节</td><td>\(course)</td>"
            + String(repeating: "<td></td>", count: 6) + "</tr></tbody></table></div>"
        let parsed = try JwScauParser(html).generateCourseList()
        XCTAssertEqual(1, parsed.count)
        XCTAssertEqual(16, parsed[0].startNode)
        XCTAssertEqual(17, parsed[0].endNode)
    }

    func testHeadersAndEmptyCellsPreserveWeekdayAndNode() throws {
        // ← 原 `headers and empty cells preserve weekday and node`
        let html = "<table border=1><tr><th>节次</th><th>周一</th></tr>"
            + "<tr><td></td><td valign=top>单片机<br>老师<br>1-4,6-8周<br>实验室<br>1节)</td>"
            + "<td></td><td valign=top>物理<br>老师<br>2-4周<br>实验室<br>1节)</td></tr></table>"
        let courses = try JwScauParser(html).generateCourseList()
        XCTAssertEqual(3, courses.count)
        XCTAssertEqual(0, courses[0].type)
        XCTAssertEqual(1, courses[0].startNode)
        XCTAssertEqual(1, courses[0].day)
        XCTAssertEqual(3, courses[courses.count - 1].day)
    }

    func testOldBordercolorTableUsesFallbackFieldOrder() throws {
        // ← 原 `old bordercolor table uses fallback field order`
        let html = "<table border=1 bordercolor=\"#000000\"><tr><td valign=top>1节)</td></tr>"
            + "<tr><td valign=top>数学：李老师<br>1-3,5周<br>A101</td></tr></table>"
        let courses = try JwScauParser(html).generateCourseList()
        XCTAssertEqual(2, courses.count)
        XCTAssertEqual("数学", courses[0].name)
        XCTAssertEqual("李老师", courses[0].teacher)
        XCTAssertEqual(5, courses[courses.count - 1].startWeek)
    }

    // MARK: - INV-1: 节次 regex (\d+节)

    func testInv1SectionRegexMatchesSectionMarkersInPrimaryPath() throws {
        // ← 原 `INV-1 节次regex matches 节次 markers in primary path`
        let src = try sample()
        XCTAssertNotNil(JwScauParser.reSectionProbe.firstMatch(
            in: src, range: NSRange(src.startIndex..., in: src)))
        let probe = "高等数学\n张三\n1-8周\n六教6A201\n1节)"
        let m = try XCTUnwrap(JwScauParser.reSectionProbe.firstMatch(
            in: probe, range: NSRange(probe.startIndex..., in: probe)))
        XCTAssertEqual("1", JwScauParser.groupValue(1, m, in: probe))
    }

    func testInv1SectionRegexMatchesMultipleSections() throws {
        // ← 原 `INV-1 节次regex matches multiple sections`
        let parser = JwScauParser(try sample())
        let courses = try parser.generateCourseList()
        XCTAssertEqual(12, courses.count)
        let nodeSet = Set(courses.map { $0.startNode })
        XCTAssertTrue(nodeSet.contains(1), "startNode 1 must be present")
        XCTAssertTrue(nodeSet.contains(3), "startNode 3 must be present")
        XCTAssertTrue(nodeSet.contains(5), "startNode 5 must be present")
    }

    // MARK: - INV-2: 周次片段过滤 [\d,\-]+

    func testInv2WeekSegmentFilterHandlesCommaAndDashSegments() throws {
        // ← 原 `INV-2 周次片段过滤 handles comma and dash segments`
        let parser = JwScauParser(try sample())
        let (s1, e1) = parser.parseWeekRange(["", "", "1-8周"], weeksLineIndex: 2)
        XCTAssertEqual(1, s1)
        XCTAssertEqual(8, e1)

        let (s2, e2) = parser.parseWeekRange(["", "", "3-15周"], weeksLineIndex: 2)
        XCTAssertEqual(3, s2)
        XCTAssertEqual(15, e2)
    }

    func testInv2WeekSegmentFilterMultiSegmentBoundaries() throws {
        // ← 原 `INV-2 周次片段过滤 multi-segment boundaries`
        let parser = JwScauParser(try sample())
        let (s, e) = parser.parseWeekRange(["", "", "1-4,6-8周"], weeksLineIndex: 2)
        XCTAssertEqual(1, s)
        XCTAssertEqual(8, e)
    }

    // MARK: - INV-3: table[border=1] 主路径选择器

    func testInv3PrimarySelectorMatchesFixture() throws {
        // ← 原 `INV-3 主路径选择器 table border 1 matches fixture`
        let parser = JwScauParser(try sample())
        let features = parser.matchedFeatureList
        XCTAssertTrue(features.contains("scau:border-primary"),
                      "expected scau:border-primary in features, got=\(features)")
    }

    func testInv3PrimarySelectsCoursesFromBorder1Table() throws {
        // ← 原 `INV-3 主路径 selects courses from border 1 table`
        let parser = JwScauParser(try sample())
        XCTAssertEqual(12, try parser.generateCourseList().count)
    }

    // MARK: - INV-4: table[border=1][bordercolor=#000000] 降级选择器

    func testInv4FallbackSelectorBordercolor000000MatchesFallback() throws {
        // ← 原 `INV-4 降级选择器 bordercolor 000000 matches fallback`
        let parser = JwScauParser(try sample())
        let features = parser.matchedFeatureList
        XCTAssertTrue(features.contains("scau:bordercolor-fallback"),
                      "expected scau:bordercolor-fallback in features, got=\(features)")
    }

    // MARK: - INV-5: td[valign=top]

    func testInv5TdValignTopSelectorHitInFixture() throws {
        // ← 原 `INV-5 td valign top selector hit in fixture`
        let parser = JwScauParser(try sample())
        let features = parser.matchedFeatureList
        XCTAssertTrue(features.contains("scau:valign-top-td"),
                      "expected scau:valign-top-td in features, got=\(features)")
    }

    // MARK: - INV-6: <head>/</head> 切片

    func testInv6HeadSliceDetectedInSource() throws {
        // ← 原 `INV-6 head-slice detected in source`
        let parser = JwScauParser(try sample())
        let features = parser.matchedFeatureList
        XCTAssertTrue(features.contains("scau:head-slice"),
                      "expected scau:head-slice in features, got=\(features)")
    }

    func testInv6HeadSliceRawMarkersPresent() throws {
        // ← 原 `INV-6 head-slice raw markers present`
        let src = try sample()
        XCTAssertTrue(src.contains("<head>"), "source must contain <head>")
        XCTAssertTrue(src.contains("</head>"), "source must contain </head>")
    }

    // MARK: - INV-7: <br> split 字段分隔

    func testInv7BrSplitParsesFourLinePrimaryCell() throws {
        // ← 原 `INV-7 br split parses 4-line primary cell`
        let parser = JwScauParser(try sample())
        let courses = try parser.generateCourseList()
        let math = try XCTUnwrap(courses.first { $0.name == "高等数学" })
        XCTAssertEqual("张三", math.teacher)
        XCTAssertEqual("六教6A201", math.room)
        XCTAssertEqual(1, math.day)
    }

    // MARK: - INV-8: 全角冒号 split

    func testInv8FullwidthColonSplitSeparatesNameAndTeacherInFallback() throws {
        // ← 原 `INV-8 全角冒号 split separates name and teacher in fallback`
        let src = try sample()
        XCTAssertTrue(src.contains("："), "source must contain ：")
        let parser = JwScauParser(src)
        let courses = try parser.generateCourseList()
        XCTAssertEqual(12, courses.count)
        let math = try XCTUnwrap(courses.first { $0.name == "高等数学" })
        XCTAssertEqual("张三", math.teacher)
    }

    // MARK: - INV-9: 半角 (单)/(双) parity

    func testInv9HalfwidthParenthesisDetectedAsType1Or2() throws {
        // ← 原 `INV-9 半角 parenthesis parity detected as type 1 or 2`
        let src = try sample()
        XCTAssertTrue(src.contains("(单)") || src.contains("(双)"))
        let parser = JwScauParser(src)
        let courses = try parser.generateCourseList()
        let ds = try XCTUnwrap(courses.first { $0.name == "数据结构" }, "数据结构 course should exist")
        XCTAssertEqual(1, ds.type)
        let eng = try XCTUnwrap(courses.first { $0.name == "英语" }, "英语 course should exist")
        XCTAssertEqual(2, eng.type)
    }

    // MARK: - INV-10: 全角 (单)/(双) parity

    func testInv10FullwidthParenthesisDetectedAsType1Or2() throws {
        // ← 原 `INV-10 全角 parenthesis parity detected as type 1 or 2`
        let src = try sample()
        XCTAssertTrue(src.contains("（单）") || src.contains("（双）"))
        let parser = JwScauParser(src)
        let courses = try parser.generateCourseList()
        let se = try XCTUnwrap(courses.first { $0.name == "软件工程" }, "软件工程 course should exist")
        XCTAssertEqual(2, se.type)
    }

    // MARK: - INV-11: substring 单/双 → type 1/2

    func testInv11SubstringParityParsingViaJwParityAdjustedRange() throws {
        // ← 原 `INV-11 substring parity parsing via JwParity adjustedRange`
        let (s2, e2) = JwParity.adjustedRange(5, 16, parity: 2)
        XCTAssertEqual(6, s2)
        XCTAssertEqual(16, e2)

        let (s1, e1) = JwParity.adjustedRange(3, 15, parity: 1)
        XCTAssertEqual(3, s1)
        XCTAssertEqual(15, e1)

        let (s0, e0) = JwParity.adjustedRange(1, 16, parity: 0)
        XCTAssertEqual(1, s0)
        XCTAssertEqual(16, e0)
    }

    // MARK: - INV-13: 全角冒号 UTF-16

    func testInv13FullwidthColonIsUPlusFF1AInUtf16() throws {
        // ← 原 `INV-13 全角冒号 is U+FF1A in UTF-16`
        let fullwidthColon: Character = "："
        XCTAssertEqual(0xFF1A, fullwidthColon.unicodeScalars.first!.value)
        XCTAssertEqual(1, String(fullwidthColon).count)

        let parser = JwScauParser(try sample())
        let features = parser.matchedFeatureList
        XCTAssertTrue(features.contains("scau:fullwidth-colon"),
                      "expected scau:fullwidth-colon in features, got=\(features)")
    }

    // MARK: - 端到端综合

    func testEndToEndPrimaryPathYieldsTwelveCoursesWithCorrectDayAndNodeMapping() throws {
        // ← 原 `end-to-end primary path yields 12 courses with correct day and node mapping`
        let parser = JwScauParser(try sample())
        let courses = try parser.generateCourseList()
        XCTAssertEqual(12, courses.count)

        let math = try XCTUnwrap(courses.first { $0.name == "高等数学" && $0.day == 1 })
        XCTAssertEqual(1, math.startNode)
        XCTAssertEqual(2, math.endNode)

        let pe = try XCTUnwrap(courses.first { $0.name == "体育" && $0.day == 1 })
        XCTAssertEqual(3, pe.startNode)
        XCTAssertEqual(4, pe.endNode)

        let cn = try XCTUnwrap(courses.first { $0.name == "计算机网络" })
        XCTAssertEqual(3, cn.day)
        XCTAssertEqual(5, cn.startNode)
        XCTAssertEqual(6, cn.endNode)
    }

    func testConfidenceScoresHighWhenAllAnchorsPresent() throws {
        // ← 原 `confidence scores high when all anchors present`
        let parser = JwScauParser(try sample())
        XCTAssertGreaterThanOrEqual(parser.confidenceValue, 80)
    }

    func testUnrelatedHtmlYieldsLowConfidence() throws {
        // ← 原 `unrelated HTML yields low confidence`
        let unrelated = "<html><body><table border=\"0\"><tr><td>no courses</td></tr></table></body></html>"
        let parser = JwScauParser(unrelated)
        XCTAssertLessThan(parser.confidenceValue, 50)
        XCTAssertTrue(try parser.generateCourseList().isEmpty)
    }

    // MARK: - 关键分隔符常量

    func testSelectorsMatchFindingsProtocolMatrixExactly() {
        // ← 原 `selectors match findings protocol matrix exactly`
        XCTAssertEqual("table[border=1]", JwScauParser.selectPrimaryTable)
        XCTAssertEqual("table[border=1][bordercolor=#000000]", JwScauParser.selectFallbackTable)
        XCTAssertEqual("td[valign=top]", JwScauParser.selectTdValignTop)
    }

    func testRegistrationWithJwParserRegistryFactory() {
        // ← 原 `REGISTRATION with JwParserRegistry FACTORY (uncommented)`
        XCTAssertTrue(JwParserRegistry.isRoutable(JwProtocol.TYPE_SCAU),
                      "TYPE_SCAU must be registered in the factory table")
    }

    func testNoCollisionWithJwQzParserSelectorStrategy() throws {
        // ← 原 `no collision with JwQzParser selector strategy`
        let qzHtml = "<html><body><div id='kbtable'><table><tr><td><font title='老师'>test</font></td></tr></table></div></body></html>"
        let scauParser = JwScauParser(qzHtml)
        XCTAssertLessThan(scauParser.confidenceValue, 80)
        XCTAssertFalse(JwScauParser.selectPrimaryTable.contains("kbtable")
                       || JwScauParser.selectFallbackTable.contains("kbtable")
                       || JwScauParser.selectTdValignTop.contains("kbtable"))
    }
}
