import XCTest
@testable import Sleepy

final class Jw1064LegacyOccurrenceTests: XCTestCase {
    private func json(_ object: Any) throws -> String { String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self) }
    private func occurrences(_ courses: [JwCourse]) -> [String] {
        courses.flatMap { course in (course.startWeek...course.endWeek).filter { course.type == 0 || $0 % 2 == course.type % 2 }.flatMap { week in
            (course.startNode...course.endNode).map { "\(course.name)|\(course.teacher)|\(course.room)|\(course.day)|\($0)|\(week)" }
        } }.sorted()
    }

    private func ecupl(_ date: String = "2026-09-07", _ bitmap: Int = 42, metadata: String = "") -> String {
        """
        \(metadata)<script language="JavaScript">
        new CourseTable('2026-09-07',[[800,845],[900,945],[1900,1945],[1955,2040]]);
        var activity=newActivity("T1","甲老师","C01","法学(实验)(C01)","R1","A101","\(date)",\(bitmap));
        addActivityByTime(activity,2,1900,2040); addActivityByTime(activity,5,800,945);
        </script>
        """
    }

    func testEcuplHHmmDecimalWeeksAndObjectMethodScript() throws {
        let expected = [JwCourse(name: "法学(实验)", room: "A101", teacher: "甲老师", day: 2, startNode: 3, endNode: 4, startWeek: 1, endWeek: 5, type: 1, startTime: "19:00", endTime: "20:40"), JwCourse(name: "法学(实验)", room: "A101", teacher: "甲老师", day: 5, startNode: 1, endNode: 2, startWeek: 1, endWeek: 5, type: 1, startTime: "08:00", endTime: "09:45")]
        let objectMethods = ecupl().replacingOccurrences(of: " language=\"JavaScript\"", with: "").replacingOccurrences(of: "var activity=newActivity", with: "var activity=table0.newActivity").replacingOccurrences(of: "addActivityByTime(", with: "table0.addActivityByTime(")
        for source in [ecupl(), objectMethods] {
            XCTAssertEqual(try JwEcuplScriptParser(source).generateCourseList(), expected)
            XCTAssertEqual(try JwClassicEamsParser(source).generateCourseList(), expected)
        }
        XCTAssertEqual(try JwEcuplScriptParser(ecupl("2026-09-06", 20)).generateCourseList().map(\.endWeek), [3, 3])
        XCTAssertTrue(try JwEcuplScriptParser(ecupl().replacingOccurrences(of: "845", with: "899")).generateCourseList().isEmpty)
    }

    func testEcuplReorderedDetailsKeepCreditAndLocation() throws {
        let metadata = #"<table class="listTable"><tr><td>学分</td><td>备注</td><td>课程序号</td><td>教师</td><td>课程名称</td></tr><tr><td>2.5</td><td>地点调整为B楼</td><td>C01</td><td>乙老师</td><td>法学实训</td></tr></table>"#
        let result = try JwEcuplScriptParser(ecupl(metadata: metadata)).generateCourseList()
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(Set(result.map(\.name)), ["法学实训"])
        XCTAssertEqual(Set(result.map(\.room)), ["A101 (地点调整为B楼)"])
        XCTAssertEqual(Set(result.map(\.teacher)), ["甲老师 (乙老师)"])
        XCTAssertEqual(Set(result.map(\.credit)), [2.5])
        XCTAssertEqual(Set(result.map(\.note)), [""])
    }

    func testEcuplAnnualOriginWrapAndMetadata() throws {
        func page(_ year: Int, _ origin: Int, _ indices: Set<Int>) -> String {
            let bitmap = (0...53).map { indices.contains($0) ? "1" : "0" }.joined()
            return """
            <script>var table0=new CourseTable(\(year),84);var unitCount=12;
            activity=new TaskActivity("T1","甲","C1","法学(一)(C1)","R1","A101","\(bitmap)");
            index=2*unitCount+4;index=2*unitCount+5;table0.marshalTable(\(origin),1,20);</script>
            <table class="listTable"><tr><td>课程序号</td><td>课程名称</td><td>教师</td><td>学分</td><td>备注</td></tr><tr><td>C1</td><td>法学(一)</td><td>乙</td><td>2.5</td><td>分组教学</td></tr></table>
            """
        }
        for (source, weeks) in [(page(2024, 36, [35, 37]), [1, 3]), (page(2024, 50, [3, 5]), [7, 9]), (page(2022, 50, [3, 5]), [8, 10])] {
            let expected = weeks.map { JwCourse(name: "法学(一)", room: "A101", teacher: "乙", day: 3, startNode: 5, endNode: 6, startWeek: $0, endWeek: $0, credit: 2.5, note: "分组教学") }
            XCTAssertEqual(try JwEcuplParser(source).generateCourseList(), expected)
            XCTAssertEqual(try JwEcuplSuperParser(source + ecupl()).generateCourseList(), expected)
        }
    }

    func testBnuzModernMixedParityAndLegacyEntities() throws {
        let modern = #"<table id="schedule"><tbody><tr></tr><tr><td><div ng-repeat="c in s.info"><h4>材料 &amp; 实验</h4><ul><li><p ng-repeat="t in c.times">第1-7单,10双周第3-4节[A &amp; B]<span>张老师</span></p><p ng-repeat="t in c.times">第2,6周第8节[C303]<span>李老师</span></p></li></ul></div></td></tr></tbody></table>"#
        XCTAssertEqual(try JwBnuzParser(modern).generateCourseList(), [JwCourse(name: "材料 & 实验", room: "A & B", teacher: "张老师", day: 2, startNode: 3, endNode: 4, startWeek: 1, endWeek: 7, type: 1), JwCourse(name: "材料 & 实验", room: "A & B", teacher: "张老师", day: 2, startNode: 3, endNode: 4, startWeek: 10, endWeek: 10, type: 2), JwCourse(name: "材料 & 实验", room: "C303", teacher: "李老师", day: 2, startNode: 8, endNode: 8, startWeek: 2, endWeek: 2), JwCourse(name: "材料 & 实验", room: "C303", teacher: "李老师", day: 2, startNode: 8, endNode: 8, startWeek: 6, endWeek: 6)])
        let legacy = "<table id='table1'><tr><td>3</td><td><span></span>材料 &amp; 实验<br>张&amp;李{1-3周}<br>A &amp; B(2节)<br></td></tr></table>"
        XCTAssertEqual(try JwBnuzParser(legacy).generateCourseList(), [JwCourse(name: "材料 & 实验", room: "A & B", teacher: "张&李", day: 1, startNode: 3, endNode: 4, startWeek: 1, endWeek: 3)])
    }

    func testChaoxingDoesNotFormCartesianProductAcrossWeeksNodesOrTeachers() throws {
        func row(_ node: Int, _ weeks: [Int], _ teacher: String, _ room: String) -> [String: Any] { ["kcmc": "实验", "xingqi": 2, "xjc": node, "zc": weeks, "tmc": teacher, "croommc": room] }
        let source = try json(["rows": [row(1, [1, 3], "张", "A"), row(2, [3, 5], "张", "A"), row(4, [2], "张", "B"), row(4, [2], "李", "C"), row(1, [1, 3], "张", "A")]])
        XCTAssertEqual(occurrences(try JwChaoxingParser(source).generateCourseList()), ["实验|张|A|2|1|1", "实验|张|A|2|1|3", "实验|张|A|2|2|3", "实验|张|A|2|2|5", "实验|张|B|2|4|2", "实验|李|C|2|4|2"].sorted())
    }

    private func cfEnvelope() -> [String: Any] {
        let row: [String: Any] = ["kcmc": "实验", "teaxms": "张", "jxcdmc": "A", "xq": "3", "ps": "1", "pe": "2", "zc": "1"]
        return ["sleepyCfNtss": true, "requestedWeeks": [1, 25], "weeks": [["week": 1, "rows": [row]], ["week": 25, "rows": []]]]
    }

    func testCfNewRequiresEveryDeclaredBucketIncludingEmptyWeeks() throws {
        let complete = cfEnvelope()
        XCTAssertEqual(try JwCfNewParser(json(complete)).generateCourseList(), [JwCourse(name: "实验", room: "A", teacher: "张", day: 3, startNode: 1, endNode: 2, startWeek: 1, endWeek: 1)])
        for malformed in [["week": 1, "rows": []], ["week": 24, "rows": []], ["week": 25.5, "rows": []], ["week": 25], ["week": 25, "rows": [:]]] as [[String: Any]] {
            var source = complete; var weeks = source["weeks"] as! [[String: Any]]; weeks[1] = malformed; source["weeks"] = weeks
            XCTAssertThrowsError(try JwCfNewParser(json(source)).generateCourseList())
        }
        var missing = complete; missing["weeks"] = Array((complete["weeks"] as! [[String: Any]]).prefix(1))
        XCTAssertThrowsError(try JwCfNewParser(json(missing)).generateCourseList())
        for requested in [[1, 1, 25], [1, 367]] { var source = complete; source["requestedWeeks"] = requested; XCTAssertThrowsError(try JwCfNewParser(json(source)).generateCourseList()) }
    }

    func testEams5ReadsPluralAndSingularTablesAndRetainsClocks() throws {
        let source = #"{"studentTableVms":[{"activities":[{"courseName":"课程甲","weekday":1,"startUnit":1,"endUnit":2,"room":"A101","teachers":["王老师","李老师"],"weekIndexes":[1,5,9]}]},{"activities":[{"courseName":"课程乙","weekday":2,"startUnit":3,"endUnit":4,"room":"B202","teachers":["张老师"],"weekIndexes":[2,6]}]}],"studentTableVm":{"activities":[{"courseName":"课程丙","weekday":7,"startUnit":9,"endUnit":10,"room":"C303","teachers":[],"weekIndexes":[8]}]}}"#
        let expected = [1, 5, 9].map { JwCourse(name: "课程甲", room: "A101", teacher: "王老师/李老师", day: 1, startNode: 1, endNode: 2, startWeek: $0, endWeek: $0) } + [2, 6].map { JwCourse(name: "课程乙", room: "B202", teacher: "张老师", day: 2, startNode: 3, endNode: 4, startWeek: $0, endWeek: $0) } + [JwCourse(name: "课程丙", room: "C303", teacher: "", day: 7, startNode: 9, endNode: 10, startWeek: 8, endWeek: 8)]
        XCTAssertEqual(try JwEams5Parser(source).generateCourseList(), expected)
        for weeks in ["[]", "null", "\"\"", "\"invalid\""] {
            XCTAssertTrue(try JwEams5Parser("{\"studentTableVms\":[{\"activities\":[{\"courseName\":\"课程\",\"weekday\":2,\"startUnit\":3,\"endUnit\":4,\"weekIndexes\":\(weeks)}]}]}").generateCourseList().isEmpty)
        }
        let clockSource = #"{"result":{"lessonList":[{"id":7,"courseName":"课程"}],"scheduleList":[{"lessonId":7,"weekday":2,"weekIndex":3,"startTime":805,"endTime":940,"periods":2}]}}"#
        let clockCourse = try XCTUnwrap(JwEams5Parser(clockSource).generateCourseList().first)
        XCTAssertEqual(clockCourse.startTime, "08:05"); XCTAssertEqual(clockCourse.endTime, "09:40")
    }

    func testNewUrpReadsEveryGroupAndStrictCoordinates() throws {
        func nested(_ name: String, _ day: Any = 2, _ node: Any = 3, _ count: Any = 2, _ bitmap: String = "10101") -> [String: Any] {
            ["courseName": name, "attendClassTeacher": "张/李", "timeAndPlaceList": [["classDay": day, "classSessions": node, "continuingSession": count, "classWeek": bitmap, "campusName": "东校区", "teachingBuildingName": "A楼", "classroomName": "301"]]]
        }
        let source = try json(["dateList": [NSNull(), [:], ["selectCourseList": [nested("实验")]], ["selectCourseList": [nested("周日讨论", 7, 7, 3, "01010")]]]])
        XCTAssertEqual(try JwNewUrpParser(source).generateCourseList(), [JwCourse(name: "实验", room: "东校区A楼301", teacher: "张/李", day: 2, startNode: 3, endNode: 4, startWeek: 1, endWeek: 5, type: 1), JwCourse(name: "周日讨论", room: "东校区A楼301", teacher: "张/李", day: 7, startNode: 7, endNode: 9, startWeek: 2, endWeek: 4, type: 2)])
        for invalid: Any in [NSNull(), "bad", "0", "-1", "2147483647", "1.5"] {
            for row in [nested("错误", invalid), nested("错误", 2, invalid), nested("错误", 2, 3, invalid)] {
                XCTAssertTrue(try JwNewUrpParser(json(["dateList": [["selectCourseList": [row]]]])).generateCourseList().isEmpty)
            }
        }
    }

    func testKingoReportPlainTeachersCreditAndLocalVersusGlobalParity() throws {
        func report(_ id: String, _ timing: String, _ credit: String = "2.5") -> String {
            var cells = [String](repeating: "<td></td>", count: id == "reportArea" ? 13 : 11)
            cells[1] = "<td>[EX01]实验</td>"; cells[2] = "<td>\(credit)</td>"; cells[4] = "<td>张老师[T01]</td>"; cells[cells.count - 1] = "<td><font>\(timing)</font></td>"
            return "<div id='\(id)'><table><tr style='height:20px'>\(cells.joined())</tr></table><span>选定</span></div>"
        }
        for id in ["pageRpt", "reportArea"] {
            let result = try JwKingoZxParser(report(id, "[1-5单周,8-12周]星期三[3-4节]/A101")).generateCourseList()
            XCTAssertEqual(Set(result.map(\.teacher)), ["张老师"]); XCTAssertEqual(Set(result.map(\.credit)), [2.5])
            XCTAssertEqual(Set(occurrences(result)), Set([1, 3, 5, 9, 11].flatMap { week in [3, 4].map { "实验|张老师|A101|3|\($0)|\(week)" } }))
        }
        let mixed = try JwKingoZxParser(report("pageRpt", "[1-5单周,8-12双周]星期三[3-4节]/A101")).generateCourseList()
        XCTAssertEqual(Set(occurrences(mixed)), Set([1, 3, 5, 8, 10, 12].flatMap { week in [3, 4].map { "实验|张老师|A101|3|\($0)|\(week)" } }))
        XCTAssertEqual(try JwKingoZxParser(report("pageRpt", "六 1-2节 双 [2-8周]/C303", "NaN")).generateCourseList(), [JwCourse(name: "实验", room: "C303", teacher: "张老师", day: 6, startNode: 1, endNode: 2, startWeek: 2, endWeek: 8, type: 2)])
    }
}
