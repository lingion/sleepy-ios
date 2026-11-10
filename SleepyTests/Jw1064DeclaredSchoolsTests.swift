import XCTest
@testable import Sleepy

final class Jw1064DeclaredSchoolsTests: XCTestCase {
    private func json(_ value: Any) throws -> String {
        String(data: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), encoding: .utf8)!
    }

    private func occurrences(_ courses: [JwCourse]) -> [String] {
        courses.flatMap { course in
            (course.startWeek...course.endWeek).filter { course.type == 0 || $0 % 2 == course.type % 2 }.flatMap { week in
                (course.startNode...course.endNode).map { node in
                    "\(course.name)|\(course.teacher)|\(course.room)|\(course.day)|\(node)|\(week)"
                }
            }
        }.sorted()
    }

    func testAhmuLengthAndHighSectionsArePreserved() throws {
        func row(_ name: String, _ first: Any, _ length: Any) -> [String: Any] {
            ["kcmc": name, "xqj": 3, "sjd": first, "skcd": length, "qsz": 2, "jsz": 3, "jsmc": "实训楼", "xm": "张"]
        }
        let source = try json([row("高节次", 31, 2), row("长课", 1, 31), row("末节", 366, 1),
                               row("越界", 366, 2), row("小数", 1.5, 2), row("溢出", "2147483648", 1), row("空格", " 1", 2), row("布尔", true, 1)])
        let courses = try JwAhmuParser(source).generateCourseList()
        XCTAssertEqual(courses.map(\.name), ["高节次", "长课", "末节"])
        XCTAssertEqual(courses.map(\.endNode), [32, 31, 366])
        XCTAssertEqual(courses.map(\.endWeek), [3, 3, 3])
    }

    private func aicTable(_ node: Int, marker: String = "getScheduleNew.do") -> String {
        var rows = "<tr><td>节次</td><td>星期一</td></tr>"
        for index in 1...node {
            let item = index == node ? "<div class='courseInfo'><b>实验</b><span class='weekDetail'>第2-3周</span><span class='teacher'>张</span><span class='place'>A</span></div>" : ""
            rows += "<tr><td>\(index)</td><td>\(item)</td></tr>"
        }
        return "<table id='table'>\(rows)</table><script>\(marker)</script>"
    }

    func testAicBlankRowsReservePeriodsAndBound366() throws {
        for node in [31, 366] {
            XCTAssertEqual(try JwAicParser(aicTable(node)).generateCourseList(), [JwCourse(name: "实验", room: "A", teacher: "张", day: 1, startNode: node, endNode: node, startWeek: 2, endWeek: 3)])
        }
        XCTAssertTrue(try JwAicParser(aicTable(367)).generateCourseList().isEmpty)
    }

    func testAicMarkerIsScopedToItsOwnTable() throws {
        let weekly = aicTable(1, marker: "weekly.do")
        let semester = aicTable(3)
        XCTAssertEqual(try JwAicParser(weekly + semester).generateCourseList().map(\.startNode), [3])
        XCTAssertThrowsError(try JwAicParser(weekly).generateCourseList())
        XCTAssertThrowsError(try JwAicParser(aicTable(1).replacingOccurrences(of: "class='weekDetail'", with: "class='weekly'")).generateCourseList())
    }

    func testBfaSixFieldsPreserveSparsePeriodsAndParity() throws {
        let source = "<table id='studentRecordTable'><tbody><tr><td>摄影</td><td>张</td><td>2-6(双)</td><td>7</td><td>1,3-4,31</td><td>-</td></tr><tr><td>错误</td><td>张</td><td>1-3</td><td>1.5</td><td>1-2</td><td>A</td></tr></tbody></table>"
        let result = try JwBfaParser(source).generateCourseList()
        XCTAssertEqual(occurrences(result), [2, 4, 6].flatMap { week in [1, 3, 4, 31].map { "摄影|张||7|\($0)|\(week)" } }.sorted())
        XCTAssertEqual(result.map(\.startNode), [1, 3, 31])
    }

    private func ccibeEnvelope() -> [String: Any] {
        let calendar: [String: Any] = ["id": "term-a", "allWeek": 3, "startTime": "2026-09-02"]
        let course: [String: Any] = ["kcmc": "逐周课程", "xqj": "三", "jc": "1,3", "qsz": 1, "jsz": 20, "jxdd": "A", "jsxm": "张"]
        return ["calendar": calendar, "weeks": (1...3).map { week -> [String: Any] in
            ["week": week, "data": ["calendar": calendar, "wdkb": week == 2 ? [] : [course]]]
        }]
    }

    func testCcibeRequestWeekOwnsOccurrencesIncludingEmptyWeeks() throws {
        let result = try JwCcibeParser(json(ccibeEnvelope())).generateCourseList()
        XCTAssertEqual(occurrences(result), [1, 3].flatMap { week in [1, 3].map { "逐周课程|张|A|3|\($0)|\(week)" } }.sorted())
        XCTAssertTrue(try JwCcibeParser(json(["wdkb": [["kcmc": "缺周", "xqj": "一", "jc": "1"]]])).generateCourseList().isEmpty)
    }

    func testCcibeRejectsIncompleteRepeatedAndMixedTermPages() throws {
        let source = ccibeEnvelope()
        let pages = source["weeks"] as! [[String: Any]]
        var incomplete = source; incomplete["weeks"] = Array(pages.dropLast())
        var repeatedPages = pages; repeatedPages[2]["week"] = 1
        var repeated = source; repeated["weeks"] = repeatedPages
        var missingPages = pages; missingPages[2]["data"] = ["calendar": ["id": "term-a"]]
        var missing = source; missing["weeks"] = missingPages
        var mixedPages = pages
        var mixedData = mixedPages[2]["data"] as! [String: Any]; mixedData["calendar"] = ["id": "term-b"]; mixedPages[2]["data"] = mixedData
        var mixed = source; mixed["weeks"] = mixedPages
        for invalid in [incomplete, repeated, missing, mixed] { XCTAssertThrowsError(try JwCcibeParser(json(invalid)).generateCourseList()) }
    }

    private func cnuCourse(_ name: String, _ timing: String, teacher: String = "张", room: String = "A") -> String {
        "<div class='curriculum-item'><div><span>\(name)</span><span>查看更多</span></div><div>\(teacher)</div><div>\(timing)</div><div>\(room)</div></div>"
    }

    private func cnuRow(_ gutters: Int, _ day: Int, _ items: String) -> String {
        "<tr>" + String(repeating: "<td>标签</td>", count: gutters) + (1...7).map { "<td>\($0 == day ? items : "")</td>" }.joined() + "</tr>"
    }

    func testCnuGuttersAndMultipleItemsKeepFieldsIsolated() throws {
        let source = "<table><tbody><tr><td>菜单</td></tr></tbody></table><table><tbody>" + cnuRow(1, 3, cnuCourse("数据库", "2-4周[3-4节]") + cnuCourse("编译", "6-7周[3-4节]", teacher: "王", room: "B")) + cnuRow(2, 7, cnuCourse("晚课", "1-2周[31节]")) + "</tbody></table>"
        XCTAssertEqual(try JwCnuParser(source).generateCourseList(), [
            JwCourse(name: "数据库", room: "A", teacher: "张", day: 3, startNode: 3, endNode: 4, startWeek: 2, endWeek: 4),
            JwCourse(name: "编译", room: "B", teacher: "王", day: 3, startNode: 3, endNode: 4, startWeek: 6, endWeek: 7),
            JwCourse(name: "晚课", room: "A", teacher: "张", day: 7, startNode: 31, endNode: 31, startWeek: 1, endWeek: 2)])
    }

    func testCnuSparsePeriodsRetainParityAndMalformedArrangementFailsClosed() throws {
        let valid = "<table><tbody>" + cnuRow(1, 2, cnuCourse("实验", "1-7单周[1,3-4节]")) + "</tbody></table>"
        XCTAssertEqual(occurrences(try JwCnuParser(valid).generateCourseList()), [1, 3, 5, 7].flatMap { week in [1, 3, 4].map { "实验|张|A|2|\($0)|\(week)" } }.sorted())
        for timing in ["周[1-2节]", "0-8周[1-2节]", "1-8周[0-2节]", "1-8周[5-3节]", "-1-8周[1-2节]", "1-8周[1.5节]", "1-8周[2147483648节]", "1-8,待定周[1-2节]"] {
            XCTAssertTrue(try JwCnuParser("<table><tbody>" + cnuRow(1, 1, cnuCourse("错误", timing)) + "</tbody></table>").generateCourseList().isEmpty, timing)
        }
    }

    private func cppuRow(_ name: String, _ date: Any, _ node: Any) -> [String: Any] {
        ["KCMC": name, "SKRQ": date, "JC": node, "JS": "李", "DDMC": "实验楼", "XF": 2.5]
    }

    func testCppuActualDatesResolveAcrossWednesdayTermStart() throws {
        let source = try json(["startDate": "2026-09-02", "rows": [cppuRow("第一周", "2026-09-02", "2@上午"), cppuRow("周日", "2026-09-06", "3@下午"), cppuRow("第二周", "2026-09-07", "4@晚上")]])
        let result = try JwCppuParser(source).generateCourseList()
        XCTAssertEqual(result.map(\.day), [3, 7, 1])
        XCTAssertEqual(result.map(\.startWeek), [1, 1, 2])
        XCTAssertEqual(result.map(\.startNode), [3, 5, 7])
        XCTAssertEqual(result.map(\.credit), [2.5, 2.5, 2.5])
    }

    func testCppuMissingDatesThrowAndUnknownBlocksDoNotDefault() throws {
        XCTAssertThrowsError(try JwCppuParser(json(["rows": [cppuRow("缺学期", "2026-09-02", "1")]])).generateCourseList())
        XCTAssertThrowsError(try JwCppuParser(json(["startDate": "2026-09-02", "rows": [cppuRow("缺日期", NSNull(), "1")]])).generateCourseList())
        let invalid = [cppuRow("缺节", "2026-09-02", NSNull()), cppuRow("之前", "2026-08-23", "1"), cppuRow("坏节", "2026-09-02", "-1@上午")]
        XCTAssertTrue(try JwCppuParser(json(["startDate": "2026-09-02", "rows": invalid])).generateCourseList().isEmpty)
    }

    private func ecjtu(_ rows: String) -> String {
        "<table class='table_border'><tr><td>节次</td>" + (1...7).map { "<td>星期\($0)</td>" }.joined() + "</tr>" + rows + "</table>"
    }

    func testEcjtuSemanticLinesSparseNodesAndFinalLine() throws {
        let source = ecjtu("<tr><td>上午</td>" + String(repeating: "<td></td>", count: 6) + "<td><b>设计&amp;艺术</b><br/><span>张&amp;李@A&amp;B</span><br/>2 1,3,11-12</td></tr>")
        XCTAssertEqual(occurrences(try JwEcjtuParser(source).generateCourseList()), [1, 3, 11, 12].map { "设计&艺术|张&李|A&B|7|\($0)|2" }.sorted())
    }

    func testEcjtuMergedCellsRetainLogicalWeekdays() throws {
        let source = ecjtu("<tr><td>一</td><td rowspan='2'>跨行<br>陈@C<br>3 1,2<br></td><td colspan='2'></td><td>中课<br>刘@D<br>4 3,4<br></td>" + String(repeating: "<td></td>", count: 3) + "</tr><tr><td>二</td><td>续课<br>王@E<br>7 5,6<br></td>" + String(repeating: "<td></td>", count: 5) + "</tr>")
        XCTAssertEqual(occurrences(try JwEcjtuParser(source).generateCourseList()), ["跨行|陈|C|1|1|3", "跨行|陈|C|1|2|3", "中课|刘|D|4|3|4", "中课|刘|D|4|4|4", "续课|王|E|2|5|7", "续课|王|E|2|6|7"].sorted())
    }

    func testEcjtuInvalidBlocksEndLocallyAndOverlappingWeeksMerge() throws {
        let bad = ["-1-4 1,2", "1.5 1,2", "4-1 1,2", "2 0,2", "3 1.5,2", "2 1,0"].enumerated().map { "错误\($0.offset)<br>坏@坏<br>\($0.element)<br>" }.joined()
        let contents = bad + "材料<br>张@A<br>1-3 1,3<br>材料<br>张@A<br>3-5 1,3<br>材料<br>李@B<br>3 1,3"
        let source = ecjtu("<tr><td>上午</td><td>\(contents)</td>" + String(repeating: "<td></td>", count: 6) + "</tr>")
        XCTAssertEqual(occurrences(try JwEcjtuParser(source).generateCourseList()), ((1...5).flatMap { week in [1, 3].map { "材料|张|A|1|\($0)|\(week)" } } + [1, 3].map { "材料|李|B|1|\($0)|3" }).sorted())
    }

    func testFstvcSerializedFieldsOwnPeriodsAndNotes() throws {
        func row(_ name: String, _ week: Any, _ day: Any, _ nodes: String) -> [String: Any] {
            ["kcmc": name, "zc": week, "xqs": day, "jcshow": nodes, "skjsxm": "李", "skcdmc": "实训楼", "sknl": "实验内容", "_nodesLi": [11, 12]]
        }
        let result = try JwFstvcParser(json([row("有效课", 7, 2, "3-4"), row("坏周", 0, 1, "1-2"), row("小数", 7.5, 1, "1-2"), row("倒序", 1, 1, "4-2")])).generateCourseList()
        XCTAssertEqual(occurrences(result), [3, 4].map { "有效课|李|实训楼|2|\($0)|7" })
        XCTAssertEqual(result.map(\.note), ["实验内容"])
    }
}
