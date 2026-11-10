import XCTest
@testable import Sleepy

/// Synthetic fixtures mirror the pinned Android v1.0.64 occurrence contracts.
final class Jw1064NativeContractTests: XCTestCase {
    private func occurrences(_ courses: [JwCourse]) -> [String] {
        courses.flatMap { c in
            (c.startWeek...c.endWeek).filter { c.type == 0 || $0 % 2 == c.type % 2 }.flatMap { week in
                (c.startNode...c.endNode).map { node in "\(c.name)|\(c.teacher)|\(c.room)|\(c.day)|\(node)|\(week)" }
            }
        }.sorted()
    }
    private func task(_ bitmap: String, _ indices: [(Int, Int)], teacher: String = "张老师") -> String {
        "activity=new TaskActivity(\"t\",\"\(teacher)\",\"c\",\"机电(1001)(A班)\",\"r\",\"实训楼301\",\"\(bitmap)\");" + indices.map { "index=\($0.0)*unitCount+\($0.1); table.activities[index].push(activity);" }.joined()
    }
    func testSingleSchoolDiagnosticsKeepExactEmptyContainerAnchors() throws {
        let cases: [(String, String, Int, [String])] = [
            ("gdbh", #"{"cname":null,"seq":null}"#, 100, ["GDBH/data/seq"]),
            ("jlu_post", #"{"xsjxrwcx":null,"PKSJDD":null}"#, 100, ["datas/xsjxrwcx/rows/PKSJDD"]),
            ("kingosoft", #"[{"week7":[],"jcxx":null}]"#, 100, ["kingosoft-week-array", "jcxx"]),
            ("stum", " \n[{\"week\":1}]", 90, ["declared-stum-week-pages"]),
            ("fdu", #"{"studentTableVms":[{"activities":[]}]}"#, 100, ["fdu-undergraduate-print-data"]),
            ("fdu", #"{"results":[{"KCMC":"","ZCBH":"","XQ":0,"KSJCDM":0}]}"#, 100, ["fdu-postgraduate-results"]),
            ("fdu", "<table class='table table-hover'></table>", 100, ["declared-fdu-list"]),
            ("shcc", "var ypData=invalid", 100, ["ypData"]),
            ("ruc", "{schoolHours:[],course:[]}", 100, ["ruc-course", "schoolHours"]),
            ("hbmzu", "<div class='list_table tac'></div>", 100, ["list_table/tac"]),
            ("hust", "<div class=main-page-block></div>", 100, ["main-page-block/search-details-body"]),
            ("sdu", "<div id=ysjddDataTableId></div>", 100, ["ysjddDataTableId"]),
            ("nua", "<table></table>", 80, ["declared-nua-last-table"]),
            ("gdei", "<table><tbody></tbody></table>", 80, ["declared-gdei-tbody"]),
            ("gliet", "<table role=presentation><tr><td>第1、2节</td></tr></table>", 100, ["GLIET/presentation-grid"]),
            ("nyist", "<div class=course-content><div class=course-item-list></div></div>", 100, ["NYIST/course-content"]),
            ("jxau", "<div id=KebiaoTable1></div>", 100, ["JXAU/KebiaoTable1"]),
            ("seig", "<table><tr><td>星期一 星期二 星期三</td></tr></table>", 100, ["declared-seig-grid"]),
            ("ztvtit", "<table class=scheduleTable></table>", 100, ["scheduleTable", "week-lesson"]),
            ("zptc", "<div id=kb><div class=pbtd></div></div>", 100, ["ZPTC/kb-pbtd-header"]),
            ("cdut", "<div class=tab1></div>", 100, ["CDUT/weekly-tab1"]),
            ("ctgu", "<div id=ctl00_MainContentPlaceHolder_GridScore></div>", 100, ["CTGU/GridScore"]),
            ("dhu", "<table><tr><td> 二十 节 </td></tr></table>", 80, ["DHU/chinese-period-grid"]),
            ("gzhuyjs", "<table class=tab_0></table>", 100, ["GZHU-post/tab_0"]),
        ]
        for (kind, source, confidence, features) in cases {
            let parser = Jw1064SchoolParser(source, kind: kind)
            XCTAssertEqual(parser.confidenceValue, confidence, kind)
            XCTAssertEqual(parser.matchedFeatureList, features, kind)
            XCTAssertEqual(try parser.generateCourseList(), [], kind)
            let missing = Jw1064SchoolParser("<p>unrelated</p>", kind: kind)
            XCTAssertEqual(missing.confidenceValue, 0, kind)
            XCTAssertEqual(missing.matchedFeatureList, [], kind)
        }
    }
    func testSingleSchoolInheritedDiagnosticsStayZeroWithCourses() throws {
        let sources: [(String, String)] = [
            ("buaa", #"{"datas":{"arrangedList":[{"courseName":"课程","dayOfWeek":1,"beginSection":1,"endSection":1,"cellDetail":[{"text":"张[1周]"}]}]}}"#),
            ("chaoxing_share", #"[{"name":"课程","dayOfWeek":1,"beginNumber":1,"length":1,"weeks":"1"}]"#),
            ("sues", #"{"studentTableVm":{"activities":[{"courseName":"课程","weekday":1,"startUnit":1,"endUnit":1,"weekIndexes":[1]}]}}"#),
            ("login_xbellsoft", #"[{"kcmc":"课程","xqj":1,"djj":1,"dsz":2,"qmz":"1"}]"#),
            ("hit", "<table class=xfyq_con><tr><td>第1节</td><td>课程<br>张[1周]A</td>" + String(repeating:"<td></td>",count:6) + "</tr></table>"),
        ]
        for (kind, source) in sources {
            let parser = Jw1064SchoolParser(source, kind: kind)
            XCTAssertFalse(try parser.generateCourseList().isEmpty, kind)
            XCTAssertEqual(parser.confidenceValue, 0, kind)
            XCTAssertEqual(parser.matchedFeatureList, [], kind)
        }
    }
    func testSingleSchoolDiagnosticsRespectSourceAndContainerBoundaries() {
        let cases: [(String, String)] = [
            ("gdbh", "cname seq"),
            ("jlu_post", #"{"xsjxrwcx":{}}"#),
            ("kingosoft", #"[{"week8":[],"jcxx":"1"}]"#),
            ("stum", #"{"week":1}"#),
            ("ruc", "<div>var data={schoolHours:[],course:[]}</div>"),
            ("ruc", "<script>var data={schoolHours:[],course:null}</script>"),
            ("shcc", "var notypData=[]"),
            ("hbmzu", "<div class=list_table></div><div class=tac></div>"),
            ("gliet", "<table role=presentation><tr><td>第3、4节</td></tr></table>"),
            ("nyist", "<div class=course-content></div><div class=course-item-list></div>"),
            ("seig", "<table><tr><td>星期一 星期二</td></tr></table><table><tr><td>星期三</td></tr></table>"),
            ("ztvtit", "<div class=scheduleTable></div>"),
            ("zptc", "<div id=kb></div><div class=pbtd></div>"),
            ("dhu", "<table><tr><td>说明</td><td><table><tr><td>一节</td></tr></table></td></tr></table>"),
            ("dhu", "<table><tr><td>说明</td></tr></table><table><tr><td>一节</td></tr></table>"),
            ("gzhuyjs", "<div class=tab_0></div>"),
        ]
        for (kind, source) in cases {
            let parser = Jw1064SchoolParser(source, kind: kind)
            XCTAssertEqual(parser.confidenceValue, 0, kind)
            XCTAssertEqual(parser.matchedFeatureList, [], kind)
        }
    }
    func testSingleSchoolIntegerTransportKeepsProtocolWhitespaceRules() throws {
        let fixtures: [(String, String, Bool, Bool)] = [
            ("buaa", #"{"datas":{"arrangedList":[{"courseName":"课程","dayOfWeek":VALUE,"beginSection":1,"endSection":1,"cellDetail":[{"text":"张[1周]"}]}]}}"#, true, true),
            ("chaoxing_share", #"[{"name":"课程","dayOfWeek":VALUE,"beginNumber":1,"length":1,"weeks":"1"}]"#, false, true),
            ("gdbh", #"{"data":[{"cname":"课程","week":VALUE,"seq":1,"startweek":1,"endweek":1}]}"#, false, true),
            ("stum", #"[{"data":{"week":VALUE,"data":[{"name":"1","monday":"[{\"f2\":\"课程\"}]"}]}}]"#, false, true),
            ("sues", #"{"studentTableVm":{"activities":[{"courseName":"课程","weekday":VALUE,"startUnit":1,"endUnit":1,"weekIndexes":[1]}]}}"#, false, true),
            ("login_xbellsoft", #"[{"kcmc":"课程","xqj":VALUE,"djj":1,"dsz":2,"qmz":"1"}]"#, true, false),
            ("shcc", #"var ypData=[{"kcS":"课程","xqj":VALUE,"djj":1,"skcd":1,"js":"张(1周)"}];"#, false, true),
            ("ruc", #"{"schoolHours":["08:00~08:45"],"course":[{"title":"课程","week":VALUE,"start":1,"quittingTime":1,"weekly":"1周"}]}"#, true, true),
            ("kingosoft", #"[{"week1":[{"kcmc":"课程","jcxx":VALUE}]}]"#, true, false),
        ]
        for (kind, template, allowsWhitespace, allowsPlus) in fixtures {
            for raw in ["1", "\"1\""] {
                XCTAssertEqual(try Jw1064SchoolParser(template.replacingOccurrences(of:"VALUE",with:raw),kind:kind).generateCourseList().count, 1, kind + raw)
            }
            for raw in ["true", "false", "1.0", "1e0", "\"1.0\"", "2147483648", "\"2147483648\"", "null"] {
                XCTAssertEqual(try Jw1064SchoolParser(template.replacingOccurrences(of:"VALUE",with:raw),kind:kind).generateCourseList(), [], kind + raw)
            }
            for (raw, accepted) in [("\" 1 \"",allowsWhitespace),("\"+1\"",allowsPlus)] {
                XCTAssertEqual(try Jw1064SchoolParser(template.replacingOccurrences(of:"VALUE",with:raw),kind:kind).generateCourseList().count, accepted ? 1 : 0, kind + raw)
            }
        }
        for raw in ["true", "1.0", "1e0", "\" 1 \""] {
            let source = #"{"studentTableVm":{"activities":[{"courseName":"课程","weekday":1,"startUnit":1,"endUnit":1,"weekIndexes":[VALUE]}]}}"#.replacingOccurrences(of:"VALUE",with:raw)
            XCTAssertEqual(try JwSuesParser(source).generateCourseList(), [], raw)
        }
    }
    func testSingleSchoolStringOnlyFieldsDoNotCoerceContainersOrScalars() throws {
        let fixtures: [(String, (Any) throws -> String, Bool)] = [
            ("gdbh", { try self.json(["data":[["cname":$0,"name":42,"croomno":true,"week":1,"seq":1,"startweek":1,"endweek":1]]]) }, true),
            ("jlu_post", { try self.json(["datas":["xsjxrwcx":["rows":[["KCMC":$0,"RKJS":42,"PKSJDD":"1周 星期一[1节]A"]]]]]) }, true),
            ("stum", { value in let items = try self.json([["f2":value,"f3":42,"f4":true]]); return try self.json([["data":["week":1,"data":[["name":"1","monday":items]]]]]) }, true),
            ("login_xbellsoft", { try self.json([["kcmc":$0,"jsxm":42,"skdd":true,"xqj":1,"djj":1,"dsz":2,"qmz":"1"]]) }, false),
            ("shcc", { "var ypData=" + (try self.json([["kcS":$0,"js":"张(1周)","jsmc":true,"xqj":1,"djj":1,"skcd":1]])) }, true),
        ]
        for (kind, makeSource, trimsName) in fixtures {
            for value: Any in [42, true, NSNull(), ["x":"y"], ["x"]] {
                XCTAssertEqual(try Jw1064SchoolParser(makeSource(value),kind:kind).generateCourseList(), [], kind)
            }
            let courses = try Jw1064SchoolParser(makeSource(" 课程 "),kind:kind).generateCourseList()
            XCTAssertEqual(courses.count, 1, kind)
            XCTAssertEqual(courses.first?.name, trimsName ? "课程" : " 课程 ", kind)
            if kind != "shcc" { XCTAssertEqual(courses.first?.teacher, "", kind) }
            if kind != "jlu_post" { XCTAssertEqual(courses.first?.room, "", kind) }
        }
    }
    func testSingleSchoolRawScalarFieldsPreserveWhitespaceAndBooleanText() throws {
        let share = #"[{"name":" 课程 ","dayOfWeek":1,"beginNumber":1,"length":1,"weeks":"1","location":" A ","onlineLocation":" B ","teacherName":" 张 "}]"#
        XCTAssertEqual(try JwChaoxingShareParser(share).generateCourseList(), [JwCourse(name:" 课程 ",room:" A  B ",teacher:" 张 ",day:1,startNode:1,endNode:1,startWeek:1,endWeek:1)])
        let shareScalar = #"[{"name":true,"dayOfWeek":1,"beginNumber":1,"length":1,"weeks":"1","location":false,"onlineLocation":3,"teacherName":true}]"#
        XCTAssertEqual(try JwChaoxingShareParser(shareScalar).generateCourseList().first?.name, "true")
        XCTAssertEqual(try JwChaoxingShareParser(shareScalar).generateCourseList().first?.room, "false3")
        for raw in ["{}", "[]"] {
            XCTAssertEqual(try JwChaoxingShareParser(shareScalar.replacingOccurrences(of:"\"name\":true",with:"\"name\":\(raw)")).generateCourseList(), [])
        }
        let sues = #"{"studentTableVm":{"activities":[{"courseName":" 课程 ","room":" A ","teachers":[" 张 "],"lessonCode":" C ","lessonRemark":" 备注 ","weekday":1,"startUnit":1,"endUnit":1,"weekIndexes":[1],"credits":true}]}}"#
        let course = try JwSuesParser(sues).generateCourseList().first
        XCTAssertEqual(course?.name, " 课程 "); XCTAssertEqual(course?.room, "A")
        XCTAssertEqual(course?.teacher, " 张 "); XCTAssertEqual(course?.note, " C  备注 "); XCTAssertEqual(course?.credit, 0)
        let xbell = #"[{"kcmc":" 课程 ","jsxm":" 张 ","skdd":" A ","xqj":1,"djj":1,"dsz":2,"qmz":"1"}]"#
        XCTAssertEqual(try JwXbellsoftParser(xbell).generateCourseList(), [JwCourse(name:" 课程 ",room:" A ",teacher:" 张 ",day:1,startNode:1,endNode:1,startWeek:1,endWeek:1)])
        let buaa = #"{"datas":{"arrangedList":[{"courseName":true,"dayOfWeek":1,"beginSection":1,"endSection":1,"credit":true,"titleDetail":[null,null,null,null,null,null,null,null,2.5],"cellDetail":[{"text":"张[1周]"}]}]}}"#
        let buaaCourse = try JwBuaaParser(buaa).generateCourseList().first
        XCTAssertEqual(buaaCourse?.name, "true"); XCTAssertEqual(buaaCourse?.credit, 0); XCTAssertEqual(buaaCourse?.note, "2.5")
    }
    func testRucRejectsReversedCombinedClockAndUsesFirstMetadataPrefix() throws {
        let source = #"{"schoolHours":["10:00~11:00","08:00~09:00"],"course":[{"title":"课程","week":1,"start":1,"quittingTime":2,"weekly":"1周","place":"地点： A地点：B ","teacher":"教师： 张教师：李 "}]}"#
        let course = try JwRucParser(source).generateCourseList().first
        XCTAssertEqual(course?.startTime, ""); XCTAssertEqual(course?.endTime, "")
        XCTAssertEqual(course?.room, "A地点：B"); XCTAssertEqual(course?.teacher, "张教师：李")
        let normal = source.replacingOccurrences(of:"08:00~09:00",with:"11:10~12:00")
        let valid = try JwRucParser(normal).generateCourseList().first
        XCTAssertEqual(valid?.startTime, "10:00"); XCTAssertEqual(valid?.endTime, "12:00")
    }
    private func simc(_ tasks: String, _ marshal: String = "table.marshalTable(5,2,8);", unitCount: Bool = true) -> String {
        "<div class=grid><table><tr><th>代码</th><th>类别</th><th>课程</th><th>学分</th></tr><tr><td>1001</td><td>必修</td><td>机电</td><td>2.5</td></tr></table></div><script>" + (unitCount ? "var unitCount=14;" : "") + tasks + marshal + "</script>"
    }
    func testSimcRepeatedBitmapAndLunchBoundary() throws {
        let courses = try JwSimcParser(simc(task("010101", [(0,0),(0,1),(0,3),(0,4),(0,8),(0,13),(2,6)]))).generateCourseList()
        XCTAssertEqual(courses.count, 20)
        XCTAssertEqual(Set(courses.map(\.startWeek)), Set([2,4,6,8]))
        XCTAssertEqual(Set(courses.map(\.credit)), Set([2.5]))
        for c in courses {
            XCTAssertEqual(c.name, "机电")
            let expected = c.day == 3 ? "7-7 14:45-15:30" : [1:"1-2 08:30-10:00",4:"4-4 11:00-11:45",5:"5-5 13:00-13:45",9:"9-10 16:15-17:45"][c.startNode]!
            XCTAssertEqual("\(c.startNode)-\(c.endNode) \(c.startTime)-\(c.endTime)", expected)
        }
    }
    func testSimcExtendedSlotsAndMalformedMarshal() throws {
        for (raw, pairs, start, end) in [(9, [(1,4),(5,5)], "07:00", "13:30"),(10,[(6,10)],"14:00","20:30"),(11,[(1,4),(5,8)],"08:15","15:30"),(12,[(9,10)],"16:00","22:00")] {
            let courses = try JwSimcParser(simc(task("10", [(6,raw)]), "table.marshalTable(1,1,2);", unitCount: false)).generateCourseList()
            XCTAssertEqual(courses.map { "\($0.startNode)-\($0.endNode)" }, pairs.map { "\($0.0)-\($0.1)" })
            XCTAssertTrue(courses.allSatisfy { $0.day == 7 && $0.startWeek == 1 && $0.startTime == start && $0.endTime == end })
        }
        for (bitmap, marshal) in [("010101",""),("010101","table.marshalTable(0,1,6);"),("010101","table.marshalTable(1,9,3);"),("01x101","table.marshalTable(5,2,8);"),("010101","table.marshalTable(12,2,8);")] {
            XCTAssertEqual(try JwSimcParser(simc(task(bitmap,[(0,0)]),marshal)).generateCourseList(), [])
        }
        let mixed = try JwSimcParser(simc(task("10", [(0,13),(0,9)]),"table.marshalTable(1,1,2);")).generateCourseList()
        XCTAssertEqual(mixed.map { "\($0.startNode)-\($0.endNode)|\($0.startTime)|\($0.endTime)" }, ["10-11||"])
    }
    func testShtuExplicitGraduateClockAndResourceBoundary() throws {
        func source(_ first: Int) -> String { "<table id=jsTbl_1><tr><td xq=5 jc=\(first) rowspan=3><div class=arrage><p>研</p><p>第2-6双周(张老师)</p><p>研讨(一班)</p><p>C303</p><p>面授讲课</p></div></td></tr></table>" }
        let courses = try JwShtu2024Parser(source(11)).generateCourseList()
        XCTAssertEqual(courses, [JwCourse(name:"研讨",room:"C303",teacher:"张老师",day:5,startNode:11,endNode:13,startWeek:2,endWeek:6,type:2,startTime:"18:55",endTime:"21:30")])
        XCTAssertEqual(try JwShtu2024Parser(source(14)).generateCourseList(), [])
        XCTAssertTrue(try JwJzParser(source(11)).generateCourseList().allSatisfy { $0.startTime.isEmpty && $0.endTime.isEmpty })
        XCTAssertEqual(JwJzParser(source(11)).confidenceValue, 95)
    }
    func testUmoocSetExclusionsAndMalformedExpressions() throws {
        XCTAssertEqual(umoocWeeks("1-10周（除3,5,8周）"), [1,2,4,6,7,9,10])
        XCTAssertEqual(umoocWeeks("1-11单周(除3-7周)"), [1,9,11])
        XCTAssertEqual(umoocWeeks("全周(除2,4周)"), (1...18).filter { ![2,4].contains($0) })
        XCTAssertEqual(umoocWeeks("单周"), Array(stride(from:1, through:17, by:2)))
        for raw in ["1-8周(除x)","1-8周(除0)","1-8周(除5-3)","-1-8周","1-8,错误","0","1-367周","待定"] { XCTAssertEqual(umoocWeeks(raw), [], raw) }
        let html = "<table id=timetable><tr class=infolist_hr_common><th>下午</th><td id='3-5'>&lt;&lt;离散数学&gt;&gt;<br>A301<br>陈老师<br>32学时<br>1-10周（除3,5,8周）<br></td></tr></table>"
        let courses = try JwUmoocParser(html).generateCourseList()
        XCTAssertEqual(Set(courses.flatMap { c in (c.startWeek...c.endWeek).filter { c.type == 0 || $0 % 2 == c.type % 2 } }), Set([1,2,4,6,7,9,10]))
        XCTAssertTrue(courses.allSatisfy { $0.name == "离散数学" && $0.teacher == "陈老师" && $0.room == "A301" && $0.day == 3 && $0.startNode == 5 })
    }
    func testKingoMergedGuttersAndSundayFirstHeader() throws {
        let html = """
        <table id=mytable><tr class=H><th>时段</th><th>节次</th><th>星期一</th><th>星期二</th><th>星期三</th><th>星期四</th><th>星期五</th><th>星期六</th><th>星期日</th></tr>
        <tr><td rowspan=2>上午</td><td rowspan=2>1-4节</td><td rowspan=2><div>周一实验<br>教师甲<br>1-8周[1-4节]<br>实验室甲</div></td><td></td><td></td><td></td><td></td><td></td><td></td></tr>
        <tr><td><div>周二实验<br>教师乙<br>2-10周(双)[3-4节]<br>实验室乙</div></td><td></td><td></td><td></td><td></td><td></td></tr></table>
        """
        XCTAssertEqual(Set(try JwKingoParser(html).generateCourseList()), Set([JwCourse(name:"周一实验",room:"实验室甲",teacher:"教师甲",day:1,startNode:1,endNode:4,startWeek:1,endWeek:8),JwCourse(name:"周二实验",room:"实验室乙",teacher:"教师乙",day:2,startNode:3,endNode:4,startWeek:2,endWeek:10,type:2)]))
        let sunday = "<table id=mytable><tr class=H><th colspan=2>时段</th><th>星期日</th><th>星期一</th><th>星期二</th><th>星期三</th><th>星期四</th><th>星期五</th><th>星期六</th></tr><tr><td>下午</td><td>第5节</td><td><div>周日实验<br>教师<br>3-9周[5节]<br>实验室</div></td><td></td><td></td><td></td><td></td><td></td><td></td></tr></table>"
        XCTAssertEqual(try JwKingoParser(sunday).generateCourseList().first?.day, 7)
        let kbdiv = "<table id=kbDiv><tbody><tr><td>数学(1-8周 中间字段 A101)</td><td></td><td></td><td></td><td></td><td></td><td></td></tr></tbody></table>"
        XCTAssertEqual(try JwKingoParser(kbdiv).generateCourseList().first?.room, "A101")
    }
    func testXbellsoftSparseWeeksParityAndMixedRows() throws {
        func source(_ weeks: String, code: String = "2") -> String { "[null,42,{\"kcmc\":\"操作系统\",\"xqj\":7,\"djj\":5,\"dsz\":\(code),\"qmz\":\"\(weeks)\",\"jsxm\":null,\"skdd\":null}]" }
        let sparse = try JwXbellsoftParser(source("1;4;10-12;")).generateCourseList()
        XCTAssertEqual(Set(sparse.flatMap { Array($0.startWeek...$0.endWeek) }), Set([1,4,10,11,12]))
        XCTAssertEqual(occurrences(sparse), occurrences(try JwJzParser(source("1;4;10-12;")).generateCourseList()))
        for code in ["0","1","2","6"] {
            let rows = try JwXbellsoftParser(source("1-8;10-12",code:code)).generateCourseList()
            XCTAssertTrue(rows.allSatisfy { $0.type == (code == "1" ? 1 : code == "2" ? 0 : 2) })
        }
        for raw in ["-1-8","1.5-8","1-3;bad;7-9","0-8","8-1","1-367","1-3-5",""] { XCTAssertEqual(try JwXbellsoftParser(source(raw)).generateCourseList(), [], raw) }
    }
    func testChaoxingShareSparseWeeksAndOverlap() throws {
        let source = #"[null,{"name":"实验","dayOfWeek":7,"beginNumber":3,"length":3,"location":"A301","onlineLocation":"线上会议123","teacherName":"张老师","weeks":"7, 1,3,3,5"},{"name":"同名课","dayOfWeek":1,"beginNumber":8,"length":2,"location":null,"onlineLocation":"线上B","teacherName":null,"weeks":"2,4,10"}]"#
        let courses = try JwChaoxingShareParser(source).generateCourseList()
        XCTAssertEqual(Set(courses.filter { $0.name == "实验" }.flatMap { c in (c.startWeek...c.endWeek).filter { c.type == 0 || $0 % 2 == c.type % 2 } }), Set([1,3,5,7]))
        XCTAssertTrue(courses.filter { $0.name == "实验" }.allSatisfy { $0.startNode == 3 && $0.endNode == 5 && $0.room == "A301线上会议123" })
        XCTAssertTrue(courses.filter { $0.name == "同名课" }.allSatisfy { $0.room == "线上B" && $0.teacher.isEmpty })
        for raw in ["1,x","0,1","1-3","1,367"] {
            let json = "[{\"name\":\"坏\",\"dayOfWeek\":1,\"beginNumber\":1,\"length\":1,\"weeks\":\"\(raw)\"}]"
            XCTAssertEqual(try JwChaoxingShareParser(json).generateCourseList(), [])
        }
    }
    func testFduStrictIntegersSundayAndIndependentGoodRows() throws {
        let good = #"{"courseName":"课程","weekday":7,"startUnit":3,"endUnit":4,"weekIndexes":[1,2,4],"teachers":[" 张老师 ","李老师"],"room":"A301"}"#
        func ug(_ rows: String) -> String { "{\"studentTableVms\":[{\"activities\":[\(rows)]}]}" }
        let expected = [JwCourse(name:"课程",room:"A301",teacher:"张老师/李老师",day:7,startNode:3,endNode:4,startWeek:1,endWeek:1),JwCourse(name:"课程",room:"A301",teacher:"张老师/李老师",day:7,startNode:3,endNode:4,startWeek:3,endWeek:3)]
        XCTAssertEqual(try JwFduParser(ug("null,42,\"invalid\"," + good)).generateCourseList(), expected)
        XCTAssertEqual(JwFduParser(ug(good)).matchedFeatureList, ["fdu-undergraduate-print-data"])
        for value in ["\"3\"","3.0","3.5","true","367","2147483648"] {
            let bad = good.replacingOccurrences(of:"\"startUnit\":3",with:"\"startUnit\":\(value)")
            XCTAssertEqual(try JwFduParser(ug(bad + "," + good)).generateCourseList(), expected, value)
        }
        let pg = #"{"results":[null,42,{"KCMC":"研究生课程","XQ":7,"KSJCDM":5,"ZCBH":"10101","JSJCDM":9,"JSXM":null,"JASMC":null}]}"#
        let pgCourses = try JwFduParser(pg).generateCourseList()
        XCTAssertEqual(pgCourses.map(\.startWeek), [1,3,5])
        XCTAssertTrue(pgCourses.allSatisfy { $0.day == 7 && $0.startNode == 5 && $0.endNode == 5 })
        XCTAssertEqual(JwFduParser(pg).matchedFeatureList, ["fdu-postgraduate-results"])
        for source in ["{\"studentTableVms\":[null,{\"activities\":[\(good)]}]}","{\"studentTableVms\":[{\"activities\":[]},{\"activities\":[\(good)]}]}",ug(good) + " trailing"] { XCTAssertEqual(try JwFduParser(source).generateCourseList(), []) }
    }
    func testCumtbShortDurationAndChaoxingArrayEnvelope() throws {
        let source = #"{"result":{"lessonList":[],"scheduleList":[{"lessonId":9,"weekday":1,"weekIndex":2,"startTime":800,"endTime":830,"personName":null,"room":null}]}}"#
        let course = try JwCumtbParser(source).generateCourseList().first
        XCTAssertEqual(course?.name, "未知")
        XCTAssertEqual(course?.startNode, 1)
        XCTAssertEqual(course?.endNode, 2)
        XCTAssertEqual(course?.startTime, "08:00")
        let chaoxing = #"[null,{"kcmc":"课程","xq":3,"djc":5,"zctype":2,"zc":"2-8(备注9)","croommc":"A","tmc":"张"}]"#
        XCTAssertEqual(WakeUpCompat.parseChaoxing(chaoxing), [JwCourse(name:"课程",room:"A",teacher:"张",day:3,startNode:5,endNode:5,startWeek:2,endWeek:8,type:2)])
    }
    func testClassicEamsRequiresUnitCountAndPreservesDisjointNodes() throws {
        let js = "var unitCount=14;" + task("0101",[(0,0),(0,2),(2,3)])
        let courses = try JwClassicEamsParser(js).generateCourseList()
        XCTAssertEqual(Set(courses.map(\.startWeek)), Set([1,3]))
        XCTAssertEqual(courses.count, 6)
        XCTAssertTrue(courses.allSatisfy { $0.startNode == $0.endNode })
        XCTAssertEqual(try JwClassicEamsParser(task("0101",[(0,0)])).generateCourseList(), [])
        XCTAssertEqual(try JwClassicEamsParser("var unitCount=14;" + task("01x1",[(0,0)])).generateCourseList(), [])
    }
    private func json(_ value: Any) throws -> String { String(data: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), encoding:.utf8)! }
    private func verify(_ parser: JwParser, _ expected: [String]) throws { XCTAssertEqual(occurrences(try parser.generateCourseList()), expected.sorted()) }
    private func expected(_ name:String,_ teacher:String,_ room:String,_ day:Int,_ nodes:[Int],_ weeks:[Int])->[String] { weeks.flatMap { w in nodes.map { "\(name)|\(teacher)|\(room)|\(day)|\($0)|\(w)" } } }
    func testBuaaTeacherWeekSegmentsKeepClockCreditAndNote() throws {
        let source = try json(["datas":["arrangedList":[NSNull(),["courseName":"课程","dayOfWeek":7,"beginSection":3,"endSection":4,"beginTime":"10:00","endTime":"11:40","placeName":"默认楼","credit":2.5,"titleDetail":["","","","","","","","","教学班"],"cellDetail":[NSNull(),["text":"张老师[1-5周(单)]李老师[8-10周(双)]"]]]]]])
        let courses = try JwBuaaParser(source).generateCourseList()
        XCTAssertEqual(occurrences(courses), (expected("课程","张老师","默认楼",7,[3,4],[1,3,5])+expected("课程","李老师","默认楼",7,[3,4],[8,10])).sorted())
        XCTAssertTrue(courses.allSatisfy { $0.credit == 2.5 && $0.note == "教学班" && $0.startTime == "10:00" && $0.endTime == "11:40" })
    }
    func testGdbhPeriodPairAndJluIndependentBracketLists() throws {
        let source = try json(["data":[NSNull(),["cname":"电子技术","name":"张","croomno":"海教楼","week":7,"seq":6,"startweek":9,"endweek":10,"xf":"2.5"]]])
        try verify(JwGdbhParser(source),expected("电子技术","张","海教楼",7,[11,12],[9,10]))
        let schedule = "[1-5单周,8-10双周 星期一 1-2节]A楼;[12周 星期日 9节]B楼"
        let jlu = try json(["datas":["xsjxrwcx":["rows":[NSNull(),["KCMC":"课程甲","RKJS":"张","PKSJDD":schedule]]]]])
        try verify(JwJluPostParser(jlu),expected("课程甲","张","A楼",1,[1,2],[1,3,5,8,10])+expected("课程甲","张","B楼",7,[9],[12]))
        for text in ["1-3周 星期一[1,3节]A","[1-3周] 星期一 [1,3节]A"] {
            let html = try json(["datas":["xsjxrwcx":["rows":[["KCMC":"课程","RKJS":"张","PKSJDD":text]]]]])
            try verify(JwJluPostParser(html),expected("课程","张","A",1,[1,3],[1,2,3]))
        }
    }
    func testGdeiCourseLocalNodeOverridesAndRoomSuffix() throws {
        func course(_ name:String,_ week:String,_ nodes:String?,_ room:String,_ teacher:String)->String { "<div><div>\(name)</div><div><span>\(week)</span>"+(nodes.map { "<span>\($0)</span>" } ?? "")+"</div><div>未用</div><div>\(room)</div><div>\(teacher)</div></div>" }
        let html = "<table><tbody><tr><td>第1-2节(上午)</td><td>"+course("课甲","第1-5单周;第8-10双周","第5,7节","实验楼(A座)(40人)","张")+course("课乙","第12周",nil,"主楼(30人)","李")+"</td><td>"+course("课丙","第6周",nil,"工坊","王")+"</td></tr></tbody></table>"
        try verify(JwGdeiParser(html),expected("课甲","张","实验楼(A座)",1,[5,7],[1,3,5,8,10])+expected("课乙","李","主楼",1,[1,2],[12])+expected("课丙","王","工坊",2,[1,2],[6]))
    }
    func testHbmzuRowCoordinatesAndNuaMiddayInsertion() throws {
        let hbmzu = "<table class='list_table tac'><tr><td><p><span>课程</span><span>第1-5单周,第8-10双周</span><span>A</span><span>张</span></p></td></tr><tr><td></td></tr><tr><td><p><span>后课</span><span>第6周</span><span>D</span><span>赵</span></p></td></tr></table>"
        try verify(JwHbmzuParser(hbmzu),expected("课程","张","A",1,[1,2],[1,3,5,8,10])+expected("后课","赵","D",1,[5,6],[6]))
        let nua = "<table><tr><td>装饰</td></tr></table><table><tr><th>表头</th></tr><tr><td>绘画</td><td>张</td><td>未用</td><td>1-3周 周一4,中午,5 周三1,3</td><td>画室</td></tr><tr><td>绘画</td><td>李</td><td>未用</td><td>6周 周日中午</td><td>工坊</td></tr></table>"
        try verify(JwNuaParser(nua),expected("绘画","张","画室",1,[4,5,6],[1,2,3])+expected("绘画","张","画室",3,[1,3],[1,2,3])+expected("绘画","李","工坊",7,[5],[6]))
    }
    func testStumStringifiedDayBucketsAndKingosoftNullWeekPositions() throws {
        let item = try json([NSNull(),["f2":"课甲","f3":"张","f4":"A"]])
        let stum = try json([NSNull(),["data":["week":3,"data":[["name":"A","monday":item,"start_time":"18:30","end_time":"19:15"],["name":"C","sunday":item,"start_time":"bad","end_time":"19:15"]]]]])
        let courses = try JwStumParser(stum).generateCourseList()
        try verify(JwStumParser(stum),expected("课甲","张","A",1,[11],[3])+expected("课甲","张","A",7,[13],[3]))
        XCTAssertEqual(courses.first?.startTime,"18:30");XCTAssertEqual(courses.last?.startTime,"")
        let lesson:[String:Any] = ["kcmc":"实验","skdd":"A","rkjs":"张/李","jcxx":"3-4","xf":"2.5"]
        let kingo = try json([NSNull(),"",["week7":[NSNull(),lesson,lesson]],NSNull(),["week7":[lesson]]])
        try verify(JwKingosoftParser(kingo),expected("实验","张/李","A",7,[3,4],[3,5]))
    }
    func testNyistClockAndJxauEmptyCellsAndSeparators() throws {
        let nyist = "<div class=course-content><div class=name>网络</div><div class=course-item-list><div class=teacher><p class=content>张</p></div><div class=address><p class=content>A</p></div><div class=time><p class=content>第[1-5]周(单) 第[6-8]周(双) 周日 5-6节 14:30~16:00</p></div></div></div>"
        let rows = try JwNyistParser(nyist).generateCourseList()
        try verify(JwNyistParser(nyist),expected("网络","张","A",7,[5,6],[1,3,5,6,8]))
        XCTAssertTrue(rows.allSatisfy { $0.startTime == "14:30" && $0.endTime == "16:00" })
        func lesson(_ name:String="农业",_ weeks:String="1,3-4(周)")->String { "<dl><a>\(name)</a><dd>李</dd><dd>\(weeks)</dd><b>B</b></dl>" }
        let cells = ["",lesson(),"","",lesson("分隔假课"),lesson("晚课","8"),lesson("第二分隔假课"),lesson("末课","9")]
        let jxau = "<table id=KebiaoTable1><tr><td>说明</td></tr><tr><td>表头</td></tr><tr><td class=left1>星期三</td>"+cells.map { "<td>\($0)</td>" }.joined()+"</tr>"+String(repeating:"<tr><td class=left1>星期一</td></tr>",count:6)+"</table>"
        try verify(JwJxauParser(jxau),expected("农业","李","B",3,[3,4],[1,3,4])+expected("晚课","李","B",3,[9,10],[8])+expected("末课","李","B",3,[11,12],[9]))
    }
    func testGlietsMultipleBlocksAndLateSinglePeriods() throws {
        let html = "<table role=presentation><tr><td>第1、2节</td><td><div>课号:101张老师<br>电路<br>(1-2)A<br>(7-8)B<br>课号:102李老师<br>信号<br>(4)C</div></td><td><div>课号:103王老师<br>数学<br>(3-5)D</div></td></tr></table>"
        try verify(JwGlietParser(html),expected("电路","张老师","A",1,[1,2],[1,2])+expected("电路","张老师","B",1,[1,2],[7,8])+expected("信号","李老师","C",1,[1,2],[4])+expected("数学","王老师","D",2,[1,2],[3,4,5]))
    }
    func testSduFixedColumnsAndHustDetailLocalMetadata() throws {
        let fields = ["序号","代码","课程甲","无关","无关","无关","无关","李老师","1-5单,8-10双,14周","2","7","无关","中心楼A"]
        let sdu = "<table id=ysjddDataTableId><tr><th>排课</th></tr><tr>"+fields.map { "<td>\($0)</td>" }.joined()+"</tr></table>"
        try verify(JwSduParser(sdu),expected("课程甲","李老师","中心楼A",2,[7],[1,3,5,8,10,14]))
        func detail(_ time:String,_ teacher:String,_ room:String)->String { "<div><span class=text-box>时间:\(time)</span><span class=text-box>教师:\(teacher)</span><span class=text-box>教室:\(room)</span></div>" }
        let hust = "<div class=main-page-block><section><p>计算机&amp;基础</p><p>其他信息</p><p>一班</p><div class=search-details-body>"+detail("1-3周 星期一 1-2节","张老师","A101")+detail("6-8周 星期日 9-10节","李老师","B202")+"</div></section></div>"
        let courses = try JwHustParser(hust).generateCourseList()
        try verify(JwHustParser(hust),expected("计算机&基础","张老师","A101",1,[1,2],[1,2,3])+expected("计算机&基础","李老师","B202",7,[9,10],[6,7,8]))
        XCTAssertTrue(courses.allSatisfy { $0.note == "开课对象：一班" })
    }
    func testRucSparseClockBucketsAndShccEmbeddedSemicolons() throws {
        let row:[String:Any] = ["title":"研讨{甲}","place":"地点：明德楼301","teacher":"教师：王老师","week":"5","start":"3","quittingTime":"1","weekly":"1-7,11-15单周"]
        let source = "<script>var unrelated='var morning =';var data=" + (try json(["schoolHours":["8:00~8:45",NSNull(),"10:00~10:45"],"course":[NSNull(),row]])) + "; var morning=4;</script>"
        let courses = try JwRucParser(source).generateCourseList()
        try verify(JwRucParser(source),expected("研讨{甲}","王老师","明德楼301",5,[3],[1,3,5,7,11,13,15]))
        XCTAssertTrue(courses.allSatisfy { $0.startTime == "10:00" && $0.endTime == "10:45" })
        let shcc = "<script>var ypData=" + (try json([NSNull(),["kcS":"课程;甲","js":"张老师(1-5(单),8-10(双))","jsmc":"A101","xqj":"3","djj":"3","skcd":"2"]])) + ";$(document).ready(function(){});</script>"
        try verify(JwShccParser(shcc),expected("课程;甲","张老师","A101",3,[3,4],[1,3,5,8,10]))
    }
    func testEmbeddedObjectLiteralsKeepQuotesCommentsAndScriptScope() throws {
        let object = #"{schoolHours:['8:00~8:45'], course:[{title:'研讨;甲',week:1,start:1,quittingTime:1,weekly:'1,5周',teacher:'教师：张',place:'地点：A'}]}"#
        let source = "<div>var data=" + object + ";</div><script>var data={unrelated:1};var data=/* { ] ignored } */" + object + ";var trailing=1;</script>"
        try verify(JwRucParser(source), expected("研讨;甲","张","A",1,[1],[1,5]))
        try verify(JwRucParser(object + ";after()"), expected("研讨;甲","张","A",1,[1],[1,5]))
        XCTAssertEqual(try JwRucParser("<div>var data=" + object + ";</div>").generateCourseList(), [])
        let shcc = #"<script>var ypData=/* } ] */[{kcS:'课程;甲',js:'张(1,5周)',jsmc:'A',xqj:3,djj:2,skcd:2}];next();</script>"#
        try verify(JwShccParser(shcc), expected("课程;甲","张","A",3,[2,3],[1,5]))
    }
    func testSuesRoomClockMatrixAndMixedTeacherRows() throws {
        func source(_ room: String, _ first: Int, _ last: Int) -> String {
            "{\"studentTableVm\":{\"activities\":[null,{\"courseName\":\"实验\",\"weekday\":7,\"startUnit\":\(first),\"endUnit\":\(last),\"weekIndexes\":[5,1,5],\"room\":\"\(room)\",\"teachers\":[\"张\",null,42,\"李\"],\"startTime\":\"8:15\",\"endTime\":\"9:35\",\"credits\":2.5,\"lessonCode\":\"C\",\"lessonRemark\":\"备注\"}]}}"
        }
        for (room, first, last, start, end) in [("A101多",4,4,"10:40","11:20"),("J301多",3,5,"09:55","12:00"),("D101多",3,5,"10:15","12:20"),("J303(中外教室）",4,5,"10:55","12:20"),("普通教室",1,2,"08:15","09:35")] {
            let courses = try JwSuesParser(source(room,first,last)).generateCourseList()
            XCTAssertEqual(courses.map(\.startWeek), [1,5])
            XCTAssertTrue(courses.allSatisfy { $0.teacher == "张,李" && $0.startTime == start && $0.endTime == end && $0.credit == 2.5 && $0.note == "C备注" })
        }
    }
    func testSeigLastParenthesisAndZtvtitOwnerCoordinates() throws {
        let seig = "<table><tr><td>节次</td>"+["一","二","三","四","五","六","日"].map { "<td>星期\($0)</td>" }.joined()+"</tr><tr><td>标签</td><td>程序设计(实验)(A 王老师 1周 3周 7周 [B201])</td>"+String(repeating:"<td></td>",count:5)+"<td>体育(B 李老师 2周 6周 [操场])</td></tr></table>"
        try verify(JwSeigParser(seig),expected("程序设计(实验)","王老师","B201",1,[1,2],[1,3,7])+expected("体育","李老师","操场",7,[1,2],[2,6]))
        let ztvtit = "<table class=scheduleTable><tr><td week=sun lesson=11><div class=courseInfo><span>课程</span><span class=teacher>张</span><span class=place>A</span><span class=WeekDetail>1-5单周,8-10双周</span></div></td></tr></table>"
        try verify(JwZtvtitParser(ztvtit),expected("课程","张","A",7,[11],[1,3,5,8,10]))
    }
    func testZptcHeaderMappingAndDhuOccupiedColumns() throws {
        let zptc = "<table id=kb><tr><th>时间</th><th>周日</th><th>周二</th><th>周一</th></tr><tr><td>说明</td><td><div class=pbtd id=x1_1>奇数课/单周/第3-4节[教学班][1-7]【张老师】【A101】</div><div class=pbtd id=x2_1>每周课/每周/第5-6节【李老师】【B202】[教学班][2-4]</div></td></tr></table>"
        try verify(JwZptcParser(zptc),expected("奇数课","张老师","A101",7,[3,4],[1,3,5,7])+expected("每周课","李老师","B202",2,[5,6],[2,3,4]))
        let dhu = "<table><tr><td>节次</td>"+(1...7).map { "<td>星期\($0)</td>" }.joined()+"</tr><tr><td>三节</td><td rowspan=2></td><td colspan=2></td><td rowspan=2>设计 2周 陈 D</td>"+String(repeating:"<td></td>",count:3)+"</tr><tr><td>四节</td><td>材料 7周 刘 E</td><td></td>"+String(repeating:"<td></td>",count:3)+"</tr></table>"
        try verify(JwDhuParser(dhu),expected("设计","陈","D",4,[3,4],[2])+expected("材料","刘","E",2,[4],[7]))
    }
    func testGzhuyjsMergedEmptyColumnsAndCdutWeekRows() throws {
        func block(_ name:String,_ time:String)->String { "<div>\(name)<br>课程代码<br>培养环节<br>王<br>\(time)<br>研教楼</div>" }
        let gzhuyjs = "<table class=tab_0><tbody>"+String(repeating:"<tr><td colspan=8>表头</td></tr>",count:4)+"<tr><td rowspan=2>白天</td><td colspan=2></td><td>"+block("周三课","2-2周 3到4小节")+"</td></tr><tr><td>"+block("周一课","3-3周 7到8小节")+"</td></tr></tbody></table>"
        try verify(JwGzhuyjsParser(gzhuyjs),expected("周三课","王","研教楼",3,[3,4],[2])+expected("周一课","王","研教楼",1,[7,8],[3]))
        let legend = "<table class=tab2><tr><td><b>(G1)地质学(ID77) 学分[2.5]</b><br>班次-A01(一班) 教师[王]<br>班次-B02(二班) 教师[李]</td></tr></table>"
        let cdut = legend+"<table class=tab1><tr><td class=td1>01周</td><td colspan=2>G1A1<span class=roomcss>A101</span></td><td colspan=4></td><td colspan=2>G1B2<span class=roomcss>B201</span></td><td colspan=64></td><td>G1A1<span class=roomcss>A101</span></td></tr></table>"
        let courses = try JwCdutParser(cdut).generateCourseList()
        try verify(JwCdutParser(cdut),expected("地质学","王","A101",1,[1,2],[1])+expected("地质学","李","B201",1,[6,7],[1])+expected("地质学","王","A101",7,[1],[1]))
        XCTAssertTrue(courses.allSatisfy { $0.credit == 2.5 })
    }
    func testHitEmptyTeacherAndCtguFlatRecordsMetadata() throws {
        let hit = "<table class=xfyq_con><tr><td>上午</td><td>第1-2节</td><td>数学<br>[1-8]周A，李老师[9-16]周B</td>"+String(repeating:"<td></td>",count:6)+"</tr></table>"
        try verify(JwHitParser(hit),expected("数学","","A",1,[1,2],Array(1...8))+expected("数学","李老师","B",1,[1,2],Array(9...16)))
        let ctgu = "<table id=ctl00_MainContentPlaceHolder_GridScore><tr><th>节次</th><th>周一</th><th>周二</th><th>周三</th><th>周四</th><th>周五</th><th>周六</th><th>周日</th></tr><tr><td>第一二节</td><td>课程甲(班级)<br>A101<br>第2-4周<br>双周<br>必修课说明<br>张老师<br>课程乙<br>B<br>第6周<br>双周<br>乙的说明<br>李老师</td></tr></table>"
        try verify(JwCtguParser(ctgu),expected("课程甲","张老师","A101",1,[1,2],[2,4])+expected("课程乙","李老师","B",1,[1,2],[6]))
    }

}
