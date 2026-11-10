import XCTest
@testable import Sleepy

/// Android v1.0.64 synthetic vectors; expected occurrences are independently enumerated.
final class JwPostgradSchoolParityTests: XCTestCase {
    private func parse(_ type: String, _ source: String) throws -> [JwCourse] {
        try JwPostgradSchoolParser(source, protocolType: type).generateCourseList()
    }

    private func course(_ name: String, _ room: String, _ teacher: String, _ day: Int,
                        _ start: Int, _ end: Int, _ first: Int, _ last: Int, _ parity: Int = 0,
                        credit: Float = 0, note: String = "", startTime: String = "", endTime: String = "") -> JwCourse {
        JwCourse(name: name, room: room, teacher: teacher, day: day, startNode: start, endNode: end,
                 startWeek: first, endWeek: last, type: parity, startTime: startTime, endTime: endTime, credit: credit, note: note)
    }

    private func occurrences(_ courses: [JwCourse]) -> [String] {
        courses.flatMap { course in (course.startWeek...course.endWeek).filter { course.type == 0 || $0 % 2 == course.type % 2 }.flatMap { week in
            (course.startNode...course.endNode).map { "\(course.name)|\(course.teacher)|\(course.room)|\(course.day)|\($0)|\(week)" }
        } }.sorted()
    }

    func testXjtuSparseWeeksAndNodesKeepFields() throws {
        let html = #"<table id="tbl"><tr><td id="abc3">课程：数学分析2<br>班级：A班<br>教师：王<br>教室：东楼<br>节次：1,3-4<br>周次：第1-3单周，第7周</td></tr></table>"#
        XCTAssertEqual(try parse("xjtu_post", html), [course("数学分析2A班", "东楼", "王", 3, 1, 1, 1, 3, 1), course("数学分析2A班", "东楼", "王", 3, 3, 4, 1, 3, 1), course("数学分析2A班", "东楼", "王", 3, 1, 1, 7, 7), course("数学分析2A班", "东楼", "王", 3, 3, 4, 7, 7)])
        XCTAssertTrue(try parse("xjtu_post", html.replacingOccurrences(of: "abc3", with: "abc0")).isEmpty)
    }

    func testUestcSeparateSlashMeetingsSkipMalformedWeeks() throws {
        let html = #"<table id="tbl"><tr><th>表头</th></tr><tr><td>节次</td><td>代码/光学/属性/院系/李/2-6双周,9周/(5~6)/A101， 代码/专题/属性/院系//5周/(9)/， 代码/坏课/属性/院系/王/待定/(1-2)/B</td></tr></table>"#
        XCTAssertEqual(try parse("uestc_post", html), [course("光学", "A101", "李", 1, 5, 6, 2, 6, 2), course("光学", "A101", "李", 1, 5, 6, 9, 9), course("专题", "", "", 1, 9, 9, 5, 5)])
    }

    func testBfaEmptyWeekdayCellStillOccupiesColumn() throws {
        let html = #"<div id="table"><table class="pages-sec-student-scheme-pages-student-timetable-query-timetable-index-tableContent"><tr><td _nk=""></td><td _nk="2"><div><p>序号</p><p>影像2</p><p>限选</p><p>周</p><p>摄影棚[1-8]</p></div><div>1-2节</div></td></tr></table></div>"#
        XCTAssertEqual(try parse("bfa_post", html), [course("影像2", "摄影棚", "周", 2, 1, 2, 1, 8, credit: 1, note: "限选")])
    }

    func testGdbyxyUsesLastNestedTableAndGlobalParity() throws {
        let html = #"<div id="pageRpt"><table><tr><td>[X1]伪课程<br>伪教师<br>[1-20周]一[1-2节]<br>伪教室<br></td></tr></table><table><tr><td>[A123]法理<br>陈<br>[1,3-5周]日[7-8节]单<br>主楼_201_多余<br></td></tr></table></div>"#
        XCTAssertEqual(try parse("gdbyxy", html), [course("法理", "主楼-201", "陈", 7, 7, 8, 1, 1, 1), course("法理", "主楼-201", "陈", 7, 7, 8, 3, 5, 1)])
    }

    func testCuplSundayHeaderAndRowspanRetainCoordinates() throws {
        let html = #"<table id="tabCT"><tr><th>节次</th><th>星期日</th><th>星期一</th></tr><tr><td>第1节</td><td rowspan="2"><b>法史</b><br>周次：第1-3周<br>校区：海淀<br>教室：研101<br>教师：陈</td><td><b>专题</b><br>第5周<br>教室：昌平<br>教师：赵</td></tr><tr><td>第2节</td><td><b>周一后课</b><br>第7周<br>教室：A<br>教师：李</td></tr></table>"#
        XCTAssertEqual(try parse("cupl_post", html), [course("法史", "研101", "陈", 7, 1, 2, 1, 3), course("专题", "昌平", "赵", 1, 1, 1, 5, 5), course("周一后课", "A", "李", 1, 2, 2, 7, 7)])
        XCTAssertTrue(try parse("cupl_post", html.replacingOccurrences(of: "rowspan=\"2\"", with: "rowspan=\"0\"")).isEmpty)
    }

    func testYsuAlternateAnchorKeepsSeparateGroups() throws {
        let html = #"<table id="MainWork_DataGrid1"><tr align="center"><th>节次</th><th>星期一</th><th>星期二</th></tr><tr><td align="center">1</td><td rowspan="2">机械<br>[第1-5单周,第8周](教师：吴)(教室:B)<br><br>方法<br>[第6周](教师：王)(教室:C)</td><td>设计<br>[第2-4双周](教师：李)(教室:D)</td></tr><tr><td align="center">2</td><td>后续<br>[第9周](教师：陈)(教室:E)</td></tr></table>"#
        XCTAssertEqual(try parse("ysu_post", html), [course("机械", "B", "吴", 1, 1, 2, 1, 5, 1), course("机械", "B", "吴", 1, 1, 2, 8, 8), course("方法", "C", "王", 1, 1, 2, 6, 6), course("设计", "D", "李", 2, 1, 1, 2, 4, 2), course("后续", "E", "陈", 2, 2, 2, 9, 9)])
    }

    func testWhuPreservesNumericCourseNamesAndOptionalFields() throws {
        let html = #"<div class="table_con"><table><tr><td rowspan="2">上午</td><td>1</td><td>数学分析2 1-3单周1-2节 A，B 张<br>123 5周3节 李</td></tr><tr><td>2</td><td>数学分析1 4周5节</td><td>实验 7周7-8节 王</td></tr></table></div>"#
        XCTAssertEqual(try parse("whu_post", html), [course("数学分析2", "A,B", "张", 1, 1, 2, 1, 3, 1), course("123", "", "李", 1, 3, 3, 5, 5), course("数学分析1", "", "", 1, 5, 5, 4, 4), course("实验", "", "王", 2, 7, 8, 7, 7)])
    }

    func testHrbeuTeacherWeekEnumerationKeepsNotes() throws {
        let html = #"<div id="StuCul_TimetableQry_TimeTable"><table class="WtbodyZlistS"><tr><td>节次</td><td field="Wednesday">课程:数学分析2<br>教师:一班多师 2班<br>节次:1,3-4<br>周次:1,3周(甲);4-6双周(乙)<br>教室:研楼<br>备注:限选</td></tr></table></div>"#
        let expected = [1, 3].flatMap { week in [1, 3, 4].map { "数学分析2(2班)|甲|研楼|3|\($0)|\(week)" } } + [4, 6].flatMap { week in [1, 3, 4].map { "数学分析2(2班)|乙|研楼|3|\($0)|\(week)" } }
        let result = try parse("hrbeu_post", html)
        XCTAssertEqual(occurrences(result), expected.sorted())
        XCTAssertEqual(Set(result.map(\.note)), ["备注:限选"])
    }

    func testShtuExclusionsDoNotMergeDifferentNodeWeeks() throws {
        let html = #"<table id="div-table"><tr><td>节次</td><td>周一</td></tr><tr><td>1</td><td>统计2班<br>王<br>A<br>第1-5周(除第2,4周)</td></tr><tr><td>2</td><td>统计2班<br>王<br>A<br>第1-5周(除第3周)</td></tr><tr><td>3</td><td>代数1班<br>李<br>B<br>第5周</td></tr></table>"#
        let expected = [1, 3, 5].map { course("统计2班", "A", "王", 1, 1, 1, $0, $0) } + [1, 2, 4, 5].map { course("统计2班", "A", "王", 1, 2, 2, $0, $0) } + [course("代数1班", "B", "李", 1, 3, 3, 5, 5)]
        XCTAssertEqual(try parse("shtu_post", html), expected)
    }

    func testUstcSemicolonAppointmentsRetainSparsePeriodsAndClocks() throws {
        let fields = ["序号", "限选", "代码", "院系", "类别", "量子2", "1~3(单周);4~6(双周)", "周", "A101: 1(1,3);B201: 2(8:40~10:20)"]
        let html = "<table id='tablexskbcx-index-table'><tr>" + fields.map { "<td><span>\($0)</span></td>" }.joined() + "</tr></table>"
        XCTAssertEqual(try parse("ustc_post", html), [course("量子2", "A101", "周", 1, 1, 1, 1, 3, 1, note: "限选"), course("量子2", "A101", "周", 1, 3, 3, 1, 3, 1, note: "限选"), course("量子2", "B201", "周", 2, 2, 3, 4, 6, 2, note: "限选", startTime: "08:40", endTime: "10:20")])
    }

    func testXauatIgnoresCommentedAssignments() throws {
        let html = #"""
        <script>var td = document.getElementById('td_3_47');
        td.innerHTML += "课程:结构2<br>编号:A1<br>教师：陈（主讲）<br>地点-主楼(第2-6周 双周)";
        // var td = document.getElementById('td_1_41'); td.innerHTML += "课程:伪课<br>x<br>教师：伪<br>地点-伪(第1-20周 单周)";
        var td = document.getElementById('td_7_49');
        td.innerHTML += "课程:专题<br>编号:B1<br>主讲教师：李<br>地点-副楼(第5周 每周)";</script>
        """#
        XCTAssertEqual(try parse("xauat_post", html), [course("结构2", "主楼", "陈", 3, 7, 7, 2, 6, 2), course("专题", "副楼", "李", 7, 9, 9, 5, 5)])
    }

    func testZjuJsonPagesAndChineseWeeks() throws {
        let page = #"<div><form id='kcbForm'></form><table><tr><th>头</th></tr><tr><td rowspan='2'><a><strong>研究2</strong><br><br>类别<br>时间||(前四,八周)<br>王<br>A</a></td><td><a><strong>专题</strong><br><br>类别<br>时间||(五周)<br>李<br>B</a></td></tr><tr><td><a><strong>后课</strong><br><br>类别<br>时间||(九周)<br>陈<br>C</a></td></tr></table></div>"#
        let source = String(decoding: try JSONSerialization.data(withJSONObject: [page]), as: UTF8.self)
        XCTAssertEqual(try parse("zju_post", source), [course("研究2", "A", "王", 1, 1, 2, 1, 4), course("研究2", "A", "王", 1, 1, 2, 8, 8), course("专题", "B", "李", 2, 1, 1, 5, 5), course("后课", "C", "陈", 2, 2, 2, 9, 9)])
    }

    func testCsvQuotedFieldsCRLFAndSemicolon() throws {
        let header = "课程名称,星期,开始节数,结束节数,教师,教室,周数"
        let source = header + "\r\n\"R,\"\"D\"\"\",三,1,2,\"王\r\n李\",A,\"1-5单周,8周\"\r\n"
        XCTAssertEqual(try parse("csv", source), [course("R,\"D\"", "A", "王\r\n李", 3, 1, 2, 1, 5, 1), course("R,\"D\"", "A", "王\r\n李", 3, 1, 2, 8, 8)])
        XCTAssertEqual(try parse("csv", header.replacingOccurrences(of: ",", with: ";") + "\n分号;7;59;60;李;B;5\n"), [course("分号", "B", "李", 7, 59, 60, 5, 5)])
        XCTAssertTrue(try parse("csv", header + "\n\"未闭合,1,1,2,王,B,5").isEmpty)
        XCTAssertTrue(try parse("csv", header + "\n坏星期,8,1,2,王,B,5\n倒置,1,4,2,王,B,5").isEmpty)
    }

    func testShuweiLegacyCarriesActivityCoordinates() throws {
        let html = #"""
        <script>var activity = null;
        var actTeachers = [{"name":"王"},{"name":"李"}];
        activity = new TaskActivity("id","计算2(旧名)","roomId","A101","010100","extra","甲组");
        index = 0 * unitCount + 0; index = 2 * unitCount + 2;
        var courseName = "专题"; courseName += "2";
        var actTeachers = [{"name":"陈"}];
        activity = new TaskActivity("id","被声明名覆盖","roomId","B201","000010","extra","乙组");
        index = 6 * unitCount + 4; table0.marshalTable();</script>
        """#
        XCTAssertEqual(try parse("shuwei_old", html), [course("计算2(甲组)", "A101", "王, 李", 1, 1, 1, 1, 1), course("计算2(甲组)", "A101", "王, 李", 1, 1, 1, 3, 3), course("计算2(甲组)", "A101", "王, 李", 3, 3, 3, 1, 1), course("计算2(甲组)", "A101", "王, 李", 3, 3, 3, 3, 3), course("专题2", "B201", "陈", 7, 5, 5, 4, 4)])
    }
}
