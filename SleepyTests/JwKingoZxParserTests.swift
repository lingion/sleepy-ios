// SleepyTests/JwKingoZxParserTests.swift
//
// 移植自 Android app/src/test/java/com/lingion/sleepy/data/jw/JwKingoZxParserTest.kt
// (v1.0.62 parity 收口)。9 用例逐一对应，断言语义不放宽。
// fixture: SleepyTests/resources/kingo_zx_sample.html (与 Android 逐字节一致)。

import XCTest
@testable import Sleepy

final class JwKingoZxParserTests: XCTestCase {

    private func res(_ name: String) throws -> String {
        let bundle = Bundle(for: JwKingoZxParserTests.self)
        guard let url = bundle.url(forResource: name, withExtension: "html")
                ?? bundle.url(forResource: name, withExtension: "html", subdirectory: "resources") else {
            XCTFail("测试资源 \(name).html 应存在")
            throw NSError(domain: "test", code: 1)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func confidence(_ p: JwParser) -> Int {
        (p as? JwParserConfidenceReporting)?.confidenceValue ?? 0
    }

    // ← Android reportRowsFollowUpstreamFields
    func test_reportRowsFollowUpstreamFields() throws {
        let html = try res("kingo_zx_sample")
        let parser = JwKingoZxParser(html)
        let courses = try parser.generateCourseList()
        XCTAssertEqual(2, courses.count)
        XCTAssertEqual("线性代数", courses[0].name)
        XCTAssertEqual("赵老师", courses[0].teacher)
        XCTAssertEqual("XB309", courses[0].room)
        XCTAssertEqual(1, courses[0].day)
        XCTAssertEqual(5, courses[0].startNode)
        XCTAssertEqual(6, courses[0].endNode)
        XCTAssertEqual(1, courses[0].startWeek)
        XCTAssertEqual(16, courses[0].endWeek)
        XCTAssertEqual(3, courses[1].day)
        XCTAssertEqual(90, confidence(parser))
    }

    // ← Android gridKeepsSparseWeeksAndSectionRange
    func test_gridKeepsSparseWeeksAndSectionRange() throws {
        let html = """
            <table id='mytable'><tr><td>节次</td>
            <td class='td'><div>数据结构<br>钱老师<br>5,7,9,13-16,1-18 单[5-6]<br>教2-301</div></td>
            <td class='td'><div>大学英语<br>孙老师<br>2-8 双[1-2]<br>教1-102</div></td>
            </tr></table>
            """
        let courses = try JwKingoZxParser(html).generateCourseList()
        XCTAssertTrue(courses.contains { $0.name == "数据结构" && $0.room == "教2-301"
            && $0.day == 1 && $0.startNode == 5 && $0.endNode == 6 })
        XCTAssertTrue(courses.contains { $0.name == "大学英语" && $0.day == 2 && $0.type == 2
            && $0.startWeek == 2 && $0.endWeek == 8 })
        XCTAssertFalse(courses.contains { $0.name == "数据结构"
            && $0.startWeek <= 10 && $0.endWeek >= 10 && $0.type == 0 })
    }

    // ← Android reportAcceptsEveryWeekdaySpelling
    func test_reportAcceptsEveryWeekdaySpelling() throws {
        let days = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
        for (index, label) in days.enumerated() {
            var cells = Array(repeating: "<td></td>", count: 11)
            cells[1] = "<td>[A01]数学</td>"
            cells[10] = "<td>1-16周 \(label) 5-6节/教室</td>"
            let html = "<table id='pageRpt'><tr><td><table></table><table><tr>"
                + cells.joined() + "</tr></table></td></tr></table>"
            let courses = try JwKingoZxParser(html).generateCourseList()
            XCTAssertEqual(1, courses.count, label)
            XCTAssertEqual(index + 1, courses.first?.day, label)
        }
    }

    // ← Android reportAcceptsDaySectionWeeksOrderFromUpstreamCode
    func test_reportAcceptsDaySectionWeeksOrderFromUpstreamCode() throws {
        var cells = Array(repeating: "<td></td>", count: 11)
        cells[1] = "<td>[A02]物理</td>"
        cells[10] = "<td>星期四 3-4节 1-16周/教室A<br>周日 5-6节 2-14周 双/教室B</td>"
        let html = "<table id='pageRpt'><tr><td><table></table><table><tr>"
            + cells.joined() + "</tr></table></td></tr></table>"
        let courses = try JwKingoZxParser(html).generateCourseList()
        XCTAssertEqual(2, courses.count)
        XCTAssertEqual(4, courses[0].day)
        XCTAssertEqual(1, courses[0].startWeek)
        XCTAssertEqual(16, courses[0].endWeek)
        XCTAssertEqual(7, courses[1].day)
        XCTAssertEqual(2, courses[1].startWeek)
        XCTAssertEqual(14, courses[1].endWeek)
        XCTAssertEqual(2, courses[1].type)
    }

    // ← Android emptyWeekdayColumnDoesNotShiftLaterGridCourses
    func test_emptyWeekdayColumnDoesNotShiftLaterGridCourses() throws {
        let html = """
            <table id='mytable'><tr><td>节次</td><td>空星期一</td>
            <td class='td'><div>体育<br>李老师<br>1-8[傍晚]<br>操场</div></td></tr></table>
            """
        let courses = try JwKingoZxParser(html).generateCourseList()
        XCTAssertEqual(1, courses.count)
        let course = courses[0]
        XCTAssertEqual(2, course.day)
        XCTAssertEqual(9, course.startNode)
        XCTAssertEqual(9, course.endNode)
        XCTAssertEqual("操场", course.room)
    }

    // ← Android noHeaderGridKeepsMondayAndBlankTuesdayPositions
    func test_noHeaderGridKeepsMondayAndBlankTuesdayPositions() throws {
        let html = """
            <table id='mytable'><tr>
            <td class='td'><div>周一课<br>甲老师<br>1-8[1-2]<br>A101</div></td>
            <td></td><td class='td'><div>周三课<br>乙老师<br>1-8[3-4]<br>C303</div></td>
            <td></td><td></td><td></td><td></td></tr></table>
            """
        let courses = try JwKingoZxParser(html).generateCourseList()
        XCTAssertTrue(courses.contains { $0.name == "周一课" && $0.day == 1 && $0.startNode == 1 })
        XCTAssertTrue(courses.contains { $0.name == "周三课" && $0.day == 3 && $0.startNode == 3 })
    }

    // ← Android unsupportedFixtureAndExpiredLoginYieldNoCourses
    func test_unsupportedFixtureAndExpiredLoginYieldNoCourses() throws {
        let unsupported = "<div id='pageRpt'><table><tr><td>高等数学</td><td>张三</td><td>1-8周</td><td>六教</td></tr></table></div>"
        XCTAssertTrue(try JwKingoZxParser(unsupported).generateCourseList().isEmpty)
        let expired = "<html><form action='/login'><input type='password'/></form></html>"
        XCTAssertTrue(try JwKingoZxParser(expired).generateCourseList().isEmpty)
        XCTAssertEqual(0, confidence(JwKingoZxParser(expired)))
    }

    // ← Android captureRecognizesKingoFrameAnchors
    func test_captureRecognizesKingoFrameAnchors() {
        XCTAssertTrue(FrameTraversalTree.findAnchors("<table id='pageRpt'></table>").contains("pageRpt"))
        XCTAssertTrue(FrameTraversalTree.findAnchors("<table id='mytable'></table>").contains("mytable"))
    }

    // ← Android genericSelectionRoutesCapturedKingoReport
    func test_genericSelectionRoutesCapturedKingoReport() throws {
        let html = try res("kingo_zx_sample")
        XCTAssertTrue(FrameTraversalTree.findAnchors(html).contains("pageRpt"))
        let (courses, attempts) = JwParserRegistry.selectBest(html)
        XCTAssertEqual(2, courses.count)
        XCTAssertEqual("线性代数", courses.first?.name)
        XCTAssertTrue(attempts.contains { $0.type == JwProtocol.TYPE_KINGO_ZX && $0.courseCount == 2 })
    }
}
