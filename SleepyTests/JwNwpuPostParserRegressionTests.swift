import XCTest
@testable import Sleepy

final class JwNwpuPostParserRegressionTests: XCTestCase {
    private func html(_ timing: String) -> String {
        """
        <table id="sample-table-1"><thead><tr>
        <th>课程编号</th><th>课程名称</th><th>班级名称</th><th>主讲教师</th><th>上课时间</th>
        </tr></thead><tbody><tr>
        <td>001</td><td>数值分析</td><td>研一</td><td>张老师</td><td>A101(\(timing))</td>
        </tr></tbody></table>
        """
    }

    private func assertNodes(_ timing: String, start: Int, end: Int,
                             file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(try JwNwpuPostParser(html(timing)).generateCourseList(), [
            JwCourse(name: "数值分析(研一)", room: "A101", teacher: "张老师", day: 3,
                     startNode: start, endNode: end, startWeek: 2, endWeek: 12, note: "001")
        ], file: file, line: line)
    }

    func testMorningHasZeroOffset() throws {
        try assertNodes("第2-12周 星期三上1-2节", start: 1, end: 2)
    }

    func testNoonHasFourNodeOffset() throws {
        try assertNodes("第2-12周 星期三中1-2节", start: 5, end: 6)
    }

    func testAfternoonHasSixNodeOffset() throws {
        try assertNodes("第2-12周 星期三下1-2节", start: 7, end: 8)
    }

    func testEveningHasTenNodeOffset() throws {
        try assertNodes("第2-12周 星期三晚1-3节", start: 11, end: 13)
    }

    func testAbsentPeriodUsesAbsoluteNodes() throws {
        try assertNodes("第2-12周 星期三5-6节", start: 5, end: 6)
    }

    func testAbsentPeriodDoesNotTurnWeeksIntoNodes() throws {
        XCTAssertEqual(try JwNwpuPostParser(html("星期三 第2-12周")).generateCourseList(), [])
        try assertNodes("星期三5-6节 第2-12周", start: 5, end: 6)
    }

    func testOffsetCannotExceedNodeThirteen() throws {
        XCTAssertEqual(try JwNwpuPostParser(html("第2-12周 星期三晚4节")).generateCourseList(), [])
    }
}
