// 合成 fixtures 对照 Android v1.0.63 JwKingoSuperSourceShapeTest.kt 与 PR35 Kingo 三链。
import XCTest
@testable import Sleepy

final class JwKingoHTMLRegressionTests: XCTestCase {
    private func block(_ timing: String, name: String = "课程") -> String {
        "<div>\(name)<br>教师<br>\(timing)<br>A101</div>"
    }

    private func grid(_ blocks: String) -> String {
        "<table id='mytable'><tr><td></td><td>\(blocks)</td></tr></table>"
    }

    func testSectionSuffixAndRangeSeparators() throws {
        for (text, start, end) in [("3-4节", 3, 4), ("2节", 2, 2), ("5~6节", 5, 6), ("29至30节", 29, 30), ("1", 1, 1)] {
            let courses = try JwKingoParser(grid(block("1-60周[\(text)]"))).generateCourseList()
            XCTAssertEqual(courses, [JwCourse(name: "课程", room: "A101", teacher: "教师", day: 2,
                startNode: start, endNode: end, startWeek: 1, endWeek: 60)], text)
        }
    }

    func testInvalidSectionsDoNotInventCoursesOrHideFollowingBlock() throws {
        for text in ["1,3,5节", "0节", "31节", "5-3节", "1-31节", "-1节", "1-2-3节", "999999999999999999节", "３节", "3节junk"] {
            let courses = try JwKingoParser(grid(block("1-8周[\(text)]", name: "坏课") + block("1-8周[2节]", name: "好课"))).generateCourseList()
            XCTAssertEqual(courses, [JwCourse(name: "好课", room: "A101", teacher: "教师", day: 2,
                startNode: 2, endNode: 2, startWeek: 1, endWeek: 8)], text)
        }
    }

    func testInvalidWeeksDoNotHideFollowingCourse() throws {
        for text in ["-1-8周", "1-2-3周", "999999999999999999周", "0周", "61周", "8-1周", "1-61周", "１-８周", "junk1-8周", "1-8周junk"] {
            let courses = try JwKingoParser(grid(block("\(text)[1-2节]", name: "坏课") + block("1-8周(单),10-12周（双）[3-4节]", name: "好课"))).generateCourseList()
            XCTAssertEqual(courses, [
                JwCourse(name: "好课", room: "A101", teacher: "教师", day: 2, startNode: 3, endNode: 4, startWeek: 1, endWeek: 8, type: 1),
                JwCourse(name: "好课", room: "A101", teacher: "教师", day: 2, startNode: 3, endNode: 4, startWeek: 10, endWeek: 12, type: 2)
            ], text)
        }
    }

    func testParityAndSparseTokensWithBothParenthesisWidths() throws {
        for (suffix, type) in [("(单)", 1), ("（单）", 1), ("(双)", 2), ("（双）", 2), ("单周", 1), ("双", 2), ("", 0)] {
            let courses = try JwKingoParser(grid(block("1-8周\(suffix)；10周，12~14周[3-4节]"))).generateCourseList()
            XCTAssertEqual(courses.map(\.startWeek), [1, 10, 12], suffix)
            XCTAssertEqual(courses.map(\.endWeek), [8, 10, 14], suffix)
            XCTAssertEqual(courses.map(\.type), [type, 0, 0], suffix)
        }
    }

    func testCompactXkinfoAndDynamicTimingWithoutRoom() throws {
        let source = """
        <table id='mytable'><tr><td><div class='div1'><span class='xkinfo'>&nbsp;</span></div>
        <div>物理<br>李四&nbsp;1-8周[5-6节]<br>实验楼201</div></td></tr></table>
        """
        XCTAssertEqual(try JwKingoParser(source).generateCourseList(), [
            JwCourse(name: "物理", room: "实验楼201", teacher: "李四", day: 1, startNode: 5, endNode: 6, startWeek: 1, endWeek: 8)
        ])
        let dynamic = grid("<div>课程<br>主讲<br>助教<br>2-4周(双)[3-4节]</div>")
        XCTAssertEqual(try JwKingoParser(dynamic).generateCourseList(), [
            JwCourse(name: "课程", teacher: "主讲 助教", day: 2, startNode: 3, endNode: 4, startWeek: 2, endWeek: 4, type: 2)
        ])
    }

    func testSevenDayGuttersAndRowspanStayAligned() throws {
        let source = """
        <table id='mytable'><tr class='H'><th>时段</th><th>节次</th><th>星期一</th><th>星期二</th><th>星期三</th><th>星期四</th><th>星期五</th><th>星期六</th><th>星期日</th></tr>
        <tr><td rowspan='2'>上午</td><td>第1-2节</td><td>\(block("1-2周[1-2节]", name: "周一"))</td><td></td><td></td><td></td><td></td><td></td><td><div>周日<br>教师<br>1-4周[1-2节]</div></td></tr>
        <tr><td>第3-4节</td><td>\(block("2-4周(双)[3-4节]", name: "英语"))</td><td><div>体育<br>教师<br>1-5周[3-4节]</div></td><td></td><td></td><td></td><td></td><td></td></tr></table>
        """
        let courses = try JwKingoParser(source).generateCourseList()
        XCTAssertEqual(courses.map(\.day), [1, 7, 1, 2])
        XCTAssertEqual(courses.map(\.endNode), [2, 2, 4, 4])
        XCTAssertEqual(courses.map(\.room), ["A101", "", "A101", ""])
        XCTAssertEqual(courses.map(\.type), [0, 0, 2, 0])
    }

    func testFiveDayGridAndDirectCellTiming() throws {
        let source = """
        <table id='mytable'><tr><th>节次</th><th>周一</th><th>周二</th><th>周三</th><th>周四</th><th>周五</th></tr>
        <tr><td>第2节</td><td></td><td></td><td></td><td></td><td>周五课<br>教师<br>60周[30节]</td></tr></table>
        """
        XCTAssertEqual(try JwKingoParser(source).generateCourseList(), [
            JwCourse(name: "周五课", teacher: "教师", day: 5, startNode: 30, endNode: 30, startWeek: 60, endWeek: 60)
        ])
    }

    private func formatTwo(_ weeks: String = "1-8", nodes: String = "3-4节", parity: String = "单") -> String {
        """
        <table><thead><tr><th>课程</th><th>教师</th><th>地点</th><th>周次</th><th>节次</th><th>单双周</th></tr></thead>
        <tbody><tr><td>[001]算法</td><td>[002]王五</td><td>教二</td><td>\(weeks)</td><td>周三[\(nodes)]</td><td>\(parity)</td></tr></tbody></table>
        """
    }

    private var kbDiv: String {
        "<table id='kbDiv'><tbody><tr><td>节次1</td><td></td><td></td><td>数据结构(1-16周（双） 教工301)</td><td></td><td></td><td></td><td></td></tr></tbody></table>"
    }

    func testFormatTwoAndFallbackAfterInvalidMytable() throws {
        let expected = [JwCourse(name: "算法", room: "教二", teacher: "王五", day: 3, startNode: 3, endNode: 4, startWeek: 1, endWeek: 8, type: 1)]
        XCTAssertEqual(try JwKingoParser(formatTwo()).generateCourseList(), expected)
        XCTAssertEqual(try JwKingoParser(grid(block("-1-8周[1-2节]")) + formatTwo()).generateCourseList(), expected)
    }

    func testKbDivAndFallbackAfterMalformedFormatTwo() throws {
        let expected = [JwCourse(name: "数据结构", room: "教工301", day: 3, startNode: 1, endNode: 1, startWeek: 1, endWeek: 16, type: 2)]
        XCTAssertEqual(try JwKingoParser(kbDiv).generateCourseList(), expected)
        for badTable in [formatTwo("-1-8周"), formatTwo("1-2-3周"), formatTwo("999999999999999999周"), formatTwo(nodes: "1,3,5节")] {
            XCTAssertEqual(try JwKingoParser(badTable + kbDiv).generateCourseList(), expected)
        }
    }

    func testEarlierValidChainWins() throws {
        let source = grid(block("1-8周[3-4节]")) + formatTwo() + kbDiv
        XCTAssertEqual(try JwKingoParser(source).generateCourseList().map(\.name), ["课程"])
    }

    func testKbDivRejectsInvalidWeeksButKeepsFollowingCell() throws {
        for invalid in ["-1-8周", "1-2-3周", "999999999999999999周", "0周", "61周", "8-1周"] {
            let source = """
            <table id='kbDiv'><tbody><tr><td>节次1</td><td>坏课(\(invalid) A101)</td><td>好课(60周(单) A102)</td>
            <td></td><td></td><td></td><td></td><td></td></tr></tbody></table>
            """
            XCTAssertEqual(try JwKingoParser(source).generateCourseList(), [
                JwCourse(name: "好课", room: "A102", day: 2, startNode: 1, endNode: 1, startWeek: 60, endWeek: 60, type: 1)
            ], invalid)
        }
    }

    func testKbDivEnforcesNodeThirtyUpperBound() throws {
        let emptyRow = "<tr>" + String(repeating: "<td></td>", count: 7) + "</tr>"
        let courseRow = "<tr><td>边界课(1-8周 A101)</td>" + String(repeating: "<td></td>", count: 6) + "</tr>"
        let source = "<table id='kbDiv'><tbody>" + String(repeating: emptyRow, count: 29) + courseRow + courseRow + "</tbody></table>"
        XCTAssertEqual(try JwKingoParser(source).generateCourseList(), [
            JwCourse(name: "边界课", room: "A101", day: 1, startNode: 30, endNode: 30, startWeek: 1, endWeek: 8)
        ])
    }

    func testRegistryUsesKingoForAllThreeHtmlShapes() throws {
        for source in [grid(block("1-8周[3-4节]")), formatTwo(), kbDiv] {
            let direct = try JwKingoParser(source).generateCourseList()
            let (courses, attempts) = JwParserRegistry.selectBest(source)
            XCTAssertEqual(courses, direct)
            XCTAssertTrue(attempts.contains { $0.type == JwProtocol.TYPE_KINGO_NEW && $0.courseCount == direct.count && $0.confidence >= 90 })
        }
    }

    func testMalformedTimingInFirstLineDoesNotCrashOrHideFollowingBlock() throws {
        let source = grid("<div>1-8周[1-2节]<br>教师</div>" + block("1-8周[2节]", name: "好课"))
        XCTAssertEqual(try JwKingoParser(source).generateCourseList().map(\.name), ["好课"])
    }

    func testLegacyZxGutterSparseWeeksAndDuplicates() throws {
        let legacy = "<div>数据结构<br>钱老师<br>5,7,9,13-16,1-18 单[5-6]<br>教2-301</div>"
        let source = """
        <table id='mytable'><tr><td>节次</td><td class='td'>\(legacy)\(legacy)</td>
        <td class='td'><div>大学英语<br>孙老师<br>2-8 双[1-2]<br>教1-102</div></td></tr></table>
        """
        XCTAssertEqual(JwParserRegistry.selectBest(source).0, try JwKingoParser(source).generateCourseList())
        XCTAssertEqual(try JwKingoParser(source).generateCourseList(), [
            JwCourse(name: "数据结构", room: "教2-301", teacher: "钱老师", day: 1, startNode: 5, endNode: 6, startWeek: 1, endWeek: 13, type: 1),
            JwCourse(name: "数据结构", room: "教2-301", teacher: "钱老师", day: 1, startNode: 5, endNode: 6, startWeek: 14, endWeek: 17),
            JwCourse(name: "大学英语", room: "教1-102", teacher: "孙老师", day: 2, startNode: 1, endNode: 2, startWeek: 2, endWeek: 8, type: 2)
        ])
    }

    func testMissingLayoutReportsAllThreeChains() {
        XCTAssertThrowsError(try JwKingoParser("<html><body></body></html>").generateCourseList()) { error in
            let message = (error as? JwParseError)?.message ?? ""
            for chain in ["chain1", "chain2", "chain3"] { XCTAssertTrue(message.contains(chain), message) }
        }
    }
}
