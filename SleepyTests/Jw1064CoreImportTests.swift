import XCTest
@testable import Sleepy

final class Jw1064CoreImportTests: XCTestCase {
    private func json(_ object: Any) throws -> String { String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self) }
    private func occurrences(_ courses: [JwCourse]) -> Set<String> {
        Set(courses.flatMap { c in (c.startWeek...c.endWeek).filter { c.type == 0 || $0 % 2 == c.type % 2 }.flatMap { week in
            (c.startNode...c.endNode).map { "\(c.name)|\(c.room)|\(c.day)|\($0)|\(week)" }
        } })
    }
    private func detail(_ room: String = "A", _ weeks: String = "1、3", _ nodes: String = "1、3") -> String {
        "<div class='mc-body'><p>课程名称：实验 &amp; 讨论</p><table><tr><th>上课时间</th><td>星期一：第\(nodes)节。</td></tr><tr><th>上课地点</th><td>\(room)</td></tr><tr><th>上课周次</th><td>\(weeks)</td></tr></table></div>"
    }
    private func grid() -> String { "<table><thead><tr><th>节次/星期</th></tr></thead><tbody>" + [1, 3].map { "<tr><th>\($0)</th><td><a href='/course/coursetime/10'>实验 &amp; 讨论</a></td></tr>" }.joined() + "</tbody></table>" }
    func testUcasSparseJsonPeriodsAndTopLevelArrayAfterComment() throws {
        let row: [String: Any] = ["courseName":"实验", "coursePlace":"A", "courseWeek":21, "courseTime":8197]
        let source = "<!--[2:] {bad}-->" + (try json([row]))
        let result = try JwUcasParser(source).generateCourseList()
        XCTAssertEqual(occurrences(result), Set([1,3,5].flatMap { w in [1,3].map { "实验|A|1|\($0)|\(w)" } }))
        XCTAssertEqual(result.count, 2)
    }
    func testUcasDetailPanelsKeepSparseNodesAndExactWeeks() throws {
        let source = detail() + detail("B", "2、6", "4-5")
        let parser = JwUcasParser(source), courses = try parser.generateCourseList()
        XCTAssertEqual(courses.count, 4)
        XCTAssertEqual(parser.confidenceValue, 100)
        XCTAssertTrue(parser.matchedFeatureList.contains("ucas:explicit-detail"))
        XCTAssertEqual(occurrences(courses).count, 8)
        for invalid in ["1、oops3", "0", "367", "2-1", "2147483648"] { XCTAssertTrue(JwUcasParser.parseNumberList(invalid).isEmpty) }
    }
    func testUcasGridRequiresDetailIdAndKeepsAllMatchingArrangements() throws {
        XCTAssertTrue(try JwUcasParser(grid()).generateCourseList().isEmpty)
        let source = grid() + "<!--sleepy-ucas-detail:/course/coursetime/10-->" + detail() + detail("B", "2、6") + "<!--/sleepy-ucas-detail-->" + "<!--sleepy-ucas-detail:/course/coursetime/11-->" + detail("WRONG") + "<!--/sleepy-ucas-detail-->"
        let courses = try JwUcasParser(source).generateCourseList()
        XCTAssertEqual(Set(courses.map(\.room)), ["A","B"])
        XCTAssertEqual(occurrences(courses).count, 8)
    }
    func testScauExplicitPackedSectionsAndGlobalParity() throws {
        let source = "<table border='1'><tr><td valign='top'>实验<br>(3132节)(单)<br>王老师<br>A101<br>1-5,9-13周</td></tr></table>"
        let courses = try JwScauParser(source).generateCourseList()
        XCTAssertEqual(courses.count, 2)
        XCTAssertTrue(courses.allSatisfy { $0.startNode == 31 && $0.endNode == 32 && $0.type == 1 && $0.teacher == "王老师" })
        XCTAssertTrue(JwScauParser("").parseWeekRuns("1-5,9-13(双)", parity: 1, globalParity: true).isEmpty)
        XCTAssertTrue(JwScauParser("").parseWeekRuns("1-5,bad").isEmpty)
        XCTAssertEqual(JwScauParser("").parseWeekRuns("365-366").count, 1)
    }
    func testScauIndexedFallbackUsesItsOwnFieldOrder() throws {
        let source = "<table border='1' bordercolor='#000000'><tr><td>标题</td></tr><tr><td>星期</td></tr><tr><td valign='top'>实 验 1-3,9-11：张老师<br>A101<br>第1-11周(单)</td></tr></table>"
        let courses = try JwScauParser(source).generateCourseList()
        XCTAssertEqual(courses.count, 2)
        XCTAssertTrue(courses.allSatisfy { $0.name == "实验" && $0.room == "A101" && $0.teacher == "张老师" && $0.type == 1 && $0.startNode == 1 && $0.endNode == 2 })
    }
    private func thu() -> String {
        #"<html><input name='p_xnxq' value='2026-2027-1'><script>function setInitValue() { strHTML = ""; strHTML += "<a class='mainHref' href='/syxk;12345678'>"; strHTML += "<b>实验</b>"; strHTML1 = ""; strHTML1 += "；张老师"; strHTML1 += "；必修"; strHTML1 += "；全周"; strHTML1 += "；A101"; getElementById('a1_1').innerHTML += strHTML; } Event.observe(window,'load',setInitValue);</script></html>"#
    }
    func testThuCapturedCalendarMovesCancelsAndDeduplicates() throws {
        let calendar = #"{"weekCount":4,"reschedule":[[1,1,2,2],[3,1],[1,1,2,2]]}"#
        let courses = try JwThuScriptParser(thu(), calendar).generateCourseList()
        XCTAssertEqual(occurrences(courses), Set(["实验|A101|2|1|2","实验|A101|2|2|2","实验|A101|1|1|2","实验|A101|1|2|2","实验|A101|1|1|4","实验|A101|1|2|4"]))
        XCTAssertFalse(JwThuScriptParser.validSemesterData(#"{"weekCount":"4"}"#))
        XCTAssertFalse(JwThuScriptParser.validSemesterData(#"{"reschedule":[[1,1,2,2],[1,1,3,3]]}"#))
        let payload = try JwThuCapturePayload.wrap(thu(), calendar)
        XCTAssertEqual(try JwThuparser(payload).generateCourseList(), courses)
    }
    func testQzExplicitSparsePeriodsNeverFallBackFromInvalidProvidedNodes() throws {
        func source(_ nodes: String) -> String { "<table id='kbtable'><tr><td><div class='kbcontent'>实验<br><font title='教师'>张老师</font><br><font title='上课地点'>A</font><br><font title='周次(节次)'>1-5(单),8-10(双)[\(nodes)节]</font></div></td></tr></table>" }
        let courses = try JwQzParser(source("1,3-4")).generateCourseList()
        XCTAssertEqual(courses.count, 4)
        XCTAssertEqual(occurrences(courses).count, 15)
        for invalid in ["0", "4-3", "367", "2147483648", "1,bad"] { XCTAssertTrue(try JwQzParser(source(invalid)).generateCourseList().isEmpty) }
    }
    func testQzModernTooltipUsesSiblingDayAndExplicitFields() throws {
        let source = "<table><tr><td>节次</td><td name='kbDataTd'><ul><li class='qz-toolitiplists'><b class='qz-tooltipContent-title'>实验 &amp; 讨论</b><div class='qz-tooltipContent-detailitem'>老师：张老师</div><div class='qz-tooltipContent-detailitem'>地点：A</div><div class='qz-tooltipContent-detailitem'>时间：2,6周[3,5节]</div></li></ul></td></tr></table>"
        let courses = try JwQzParser(source).generateCourseList()
        XCTAssertEqual(courses.count, 4)
        XCTAssertTrue(courses.allSatisfy { $0.name == "实验 & 讨论" && $0.day == 1 && $0.room == "A" && $0.teacher == "张老师" })
    }
    func testNewZfStrictWeeksDayAndHighPhysicalNodes() throws {
        func source(_ day: Any, _ nodes: String, _ weeks: String) throws -> String { try json(["kbList":[["kcmc":"实验","xqj":day,"xqjmc":"星期一","jcs":nodes,"zcd":weeks]]]) }
        let courses = try JwNewZfParser(source(7, "31-32,366", "1-5(单),8-10(双)")).generateCourseList()
        XCTAssertEqual(courses.count, 4)
        XCTAssertTrue(courses.allSatisfy { $0.day == 7 })
        for (day,nodes,weeks): (Any,String,String) in [(0,"1-2","1-2"), (1,"2147483648","1"), (1,"2-1","1"), (1,"1","bad"), (1,"1","{1-2") ,(1,"1","367")] { XCTAssertTrue(try JwNewZfParser(source(day,nodes,weeks)).generateCourseList().isEmpty) }
    }
    func testUstcRetainsActualClockSparseWeeksAndSourceMetadata() throws {
        let source = #"{"studentTableVm":{"activities":[{"courseName":"实验","weekday":3,"startDate":"08:15","endDate":"09:40","weeksStr":"1,5,9","teachers":["张","李"],"credits":2.5,"lessonCode":"CODE","lessonRemark":"备注"}]}}"#
        let courses = try JwUstcParser(source).generateCourseList()
        XCTAssertEqual(courses.map(\.startWeek), [1,5,9])
        XCTAssertTrue(courses.allSatisfy { $0.startNode == 1 && $0.endNode == 1 && $0.hasActualTime && $0.teacher == "张 李" && $0.credit == 2.5 && $0.note == "CODE备注" })
        XCTAssertTrue(try JwUstcParser(source.replacingOccurrences(of: "\"weeksStr\"", with: "\"startUnit\":0,\"endUnit\":2,\"weeksStr\"")).generateCourseList().isEmpty)
    }
    func testUrpRowspansPreserveMetadataWithoutFillingSparseWeeks() throws {
        let source = "<table class='displayTag'><thead><tr><th>课程名</th><th>教师</th><th>学分</th><th>周次</th><th>星期</th><th>节次</th><th>教学楼</th><th>教室</th></tr></thead><tbody><tr><td rowspan='2'>实验</td><td rowspan='2'>张</td><td rowspan='2'>2.5</td><td>1,5</td><td>一</td><td>31-32</td><td>A</td><td>101</td></tr><tr><td>2,6</td><td>三</td><td>4</td><td>B</td><td>202</td></tr></tbody></table>"
        let courses = try JwUrpParser(source).generateCourseList()
        XCTAssertEqual(occurrences(courses).count, 6)
        XCTAssertTrue(courses.allSatisfy { $0.name == "实验" && $0.teacher == "张" && $0.credit == 2.5 })
        XCTAssertTrue(try JwUrpParser(source.replacingOccurrences(of: "rowspan='2'", with: "rowspan='3'")).generateCourseList().isEmpty)
    }
    func testNwpuKeepsEveryLineCreditAndNote() throws {
        let source = "<table id='sample-table-1'><thead><tr><th>院系</th><th>课程编号</th><th>课程名称</th><th>主讲教师</th><th>学分</th><th>班级说明</th><th>上课时间</th></tr></thead><tbody><tr><td>学院</td><td>C01</td><td>实验</td><td>张</td><td>2.5</td><td>分组</td><td>A101(第2-12周 星期三上1-2节)<br>B202(第3-9周 星期四晚1-2节)</td></tr></tbody></table>"
        let courses = try JwNwpuPostParser(source).generateCourseList()
        XCTAssertEqual(courses.count, 2)
        XCTAssertEqual(Set(courses.map(\.room)), ["A101","B202"])
        XCTAssertTrue(courses.allSatisfy { $0.credit == 2.5 && $0.note == "学院 C01 分组" })
    }
    func testWhutDynamicSectionMapAndLegacyPhysicalNodes() throws {
        let source = #"{"sleepyWhutSectionMap":{"8":31,"9":32},"datas":{"cxxszhxqkb":{"rows":[{"KCM":"实验","SKXQ":2,"KSJC":8,"JSJC":9,"SKZC":"10101","JASMC":"A","SKJS":"张"}]}}}"#
        XCTAssertEqual(try JwWhutParser(source).generateCourseList().first?.startNode, 31)
        let html = "<div id='xqkb'><table class='table-class-even'><tr><td>标题</td><td style='x'><a>实验<span>@A</span><span>1-3周(31-32节)</span></a></td></tr></table></div>"
        XCTAssertEqual(try JwWhutParser(html).generateCourseList(), [JwCourse(name:"实验",room:"A",day:1,startNode:31,endNode:32,startWeek:1,endWeek:3)])
    }
    func testSchoolGridRoutesKeepDeclaredMappingsAndSparseArrangements() throws {
        let gxic = "<table width='98%'><tr><th>节次</th><th>星期日</th><th>星期一</th></tr><tr><td>第0102节</td><td><a title='上课周次：1,5\n开课地点：A\n授课教师：张'>实验<br>extra</a></td></tr></table>"
        let gx = try JwSchoolGridParser(gxic,"gxic").generateCourseList()
        XCTAssertEqual(gx.count,2); XCTAssertTrue(gx.allSatisfy { $0.day == 7 && $0.startTime == "08:40" && $0.endTime == "10:10" && $0.name == "实验" })
        let gxnu = "<table id='xkjbgzszGridIdGrid'><tbody><tr><td aria-describedby='xkjbgzszGridIdGrid_kcmc'>实验</td><td aria-describedby='xkjbgzszGridIdGrid_rkjs'>张</td><td aria-describedby='xkjbgzszGridIdGrid_xf'>2.5</td><td aria-describedby='xkjbgzszGridIdGrid_sksjdd'>1,5周 星期二 31,33节【A】；2周 星期日 4节【B】</td></tr></tbody></table>"
        XCTAssertEqual(try JwSchoolGridParser(gxnu,"gxnu").generateCourseList().count,5)
        let jxnu = "<table id='_ctl1_dgStudentLesson'><tr><td></td><td>实验</td><td></td><td>张</td></tr></table><table id='_ctl1_NewKcb'><tr></tr><tr><td bgcolor='#cccccc'>节次</td><td><div>实验<br>(A)</div></td></tr></table>"
        XCTAssertEqual(try JwSchoolGridParser(jxnu,"jxnu").generateCourseList(),[JwCourse(name:"实验",room:"A",teacher:"张",day:1,startNode:1,endNode:2,startWeek:1,endWeek:20)])
        let nnutc = "<table><tbody><tr><td>节次</td><td><div class='card'><svg data-icon='calculator'></svg><label>实验</label><svg data-icon='user'></svg><label>张</label><svg data-icon='environment'></svg><label>A[1-5,9-13(单)]</label><svg></svg><label>第31,33节</label></div></td></tr></tbody></table>"
        let nn = try JwSchoolGridParser(nnutc,"nnutc").generateCourseList()
        XCTAssertEqual(nn.count,4); XCTAssertTrue(nn.allSatisfy { $0.day == 1 && $0.type == 1 })
    }
    func testSchoolTableRoutesKeepSourcePeriodsAndLocations() throws {
        let hbut = "<table id='weekSchedule'><tr><td>实验,C01</td><td>1,5</td><td>周一~周二</td><td>第31,33节</td><td>地点:A</td></tr></table>"
        XCTAssertEqual(try JwSchoolTableParser(hbut,"hbut").generateCourseList().count,8)
        let hnjm = "<div class='Sub-kcbt'>星期二</div><table><tr><td>1-2节</td><td>实验1-3周(图101)</td><td>张</td></tr></table>"
        let hn = try JwSchoolTableParser(hnjm,"hnjm").generateCourseList()
        XCTAssertEqual(hn.first?.startTime,"08:10"); XCTAssertEqual(hn.first?.endTime,"09:50")
        let lz = "<table id='TableLCRoomOccupy'><tr><td class='PuTongCell' id='jieci31day1'><div>实验<br>张<br>教室:A(教室人数20)<br>x<br>周次:1-5[单]</div></td></tr></table>"
        XCTAssertEqual(try JwSchoolTableParser(lz,"lz").generateCourseList().first?.startNode,31)
        let nau = "<table id='content'><tr><th>课程名称</th><th>上课时间及地点</th><th>学分</th><th>任课教师</th><th>x</th><th>x</th><th>x</th><th>x</th></tr><tr><td>实验</td><td>上课地点：A上课时间：1-5之单周 星期 2 第 31,33节</td><td>2.5</td><td>张</td><td></td><td></td><td></td><td></td></tr></table>"
        XCTAssertEqual(try JwSchoolTableParser(nau,"nau").generateCourseList().count,2)
        let nju = "<div id='kcb_container'><table class='wut_table'><tbody><tr></tr><tr><td class='mtt_bgcolor_grey' data-unit='31'>(08:15~09:40)</td><td data-role='item'><div class='mtt_arrange_item'><b class='mtt_item_kcmc'>C01 实验 2班</b><div class='mtt_item_sksj'>周二1,5周第31节</div><i class='mtt_item_room'>A</i><i class='mtt_item_jxbmc'>张</i></div></td></tr></tbody></table></div>"
        let nj = try JwSchoolTableParser(nju,"nju").generateCourseList()
        XCTAssertEqual(nj.count,2); XCTAssertTrue(nj.allSatisfy { $0.name == "实验" && $0.hasActualTime })
        let cqupt = "<table id='stuPanel'><tr style='text-align:center'><td>节次</td><td><div zc='10101'>C01-实验<br>地点：A<br>3节连上<br>张 2.5学分</div></td></tr></table>"
        let cq = try JwSchoolTableParser(cqupt,"cqupt").generateCourseList()
        XCTAssertEqual(cq.count,3); XCTAssertTrue(cq.allSatisfy { $0.startNode == 1 && $0.endNode == 3 && $0.teacher == "张" && $0.credit == 2.5 })
    }
}
