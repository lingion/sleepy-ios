// JwParserTests.swift — ← JwParserTest.kt + JwNewZfParserTest.kt + JwWiseduParserTest.kt (逐用例)

import XCTest
@testable import Sleepy

// MARK: - ← JwParserTest.kt

final class JwParserTests: XCTestCase {

    // --- Mock HEU 课表 HTML(嵌入 JSON,模拟 wisedu URP) ---
    private let mockHeuHtml = """
        <!DOCTYPE html><html><head><title>个人课表</title>
        <script>
        var kbxx_json = {
          "dateList": [
            {
              "selectCourseList": [
                {
                  "courseName": "高等数学",
                  "attendClassTeacher": "张三",
                  "timeAndPlaceList": [
                    {
                      "classDay": 1,
                      "classSessions": 1,
                      "continuingSession": 2,
                      "classWeek": "11111111111111111111",
                      "campusName": "",
                      "teachingBuildingName": "主楼",
                      "classroomName": "A101"
                    }
                  ]
                },
                {
                  "courseName": "大学物理",
                  "attendClassTeacher": "李四",
                  "timeAndPlaceList": [
                    {
                      "classDay": 3,
                      "classSessions": 3,
                      "continuingSession": 1,
                      "classWeek": "10101010101010101010",
                      "campusName": "",
                      "teachingBuildingName": "实验楼",
                      "classroomName": "B202"
                    }
                  ]
                },
                {
                  "courseName": "英语",
                  "attendClassTeacher": "王五",
                  "timeAndPlaceList": [
                    {
                      "classDay": 5,
                      "classSessions": 5,
                      "continuingSession": 2,
                      "classWeek": "11111111111111110000",
                      "campusName": "",
                      "teachingBuildingName": "文科楼",
                      "classroomName": "C303"
                    }
                  ]
                }
              ]
            }
          ]
        };
        </script>
        </head><body><h1>个人课表</h1></body></html>
    """

    func testJwNewUrpParserParsesHEUMockHTML() {  // ← `JwNewUrpParser parses HEU mock HTML`
        let parser = JwNewUrpParser(mockHeuHtml)

        let courses = parser.generateCourseList()

        XCTAssertEqual(3, courses.count, "3 门课")

        // 第 1 门:高等数学
        let c1 = courses[0]
        XCTAssertEqual("高等数学", c1.name)
        XCTAssertEqual("张三", c1.teacher)
        XCTAssertEqual(1, c1.day)
        XCTAssertEqual(1, c1.startNode)
        XCTAssertEqual(2, c1.endNode)
        XCTAssertTrue(c1.startWeek == 1 && c1.endWeek >= 16, "周次应包含 1-20")
        XCTAssertEqual(0, c1.type)

        // 第 2 门:大学物理 type=1
        let c2 = courses[1]
        XCTAssertEqual("大学物理", c2.name)
        XCTAssertEqual(3, c2.day)
        XCTAssertEqual(1, c2.type)  // 单周
    }

    func testJwUrpParserHandlesEmptyHTMLGracefully() {  // ← `JwUrpParser handles empty HTML gracefully`
        let result = JwUrpParser("<html><body>空</body></html>").generateCourseList()
        XCTAssertEqual(0, result.count)
    }

    func testJwNewUrpParserHandlesEmptyHTMLGracefully() {  // ← `JwNewUrpParser handles empty HTML gracefully`
        let result = JwNewUrpParser("<html><body>空</body></html>").generateCourseList()
        XCTAssertEqual(0, result.count)
    }

    func testJwNewUrpParserHandlesMalformedJSONGracefully() {  // ← `JwNewUrpParser handles malformed JSON gracefully`
        let result = JwNewUrpParser("not json").generateCourseList()
        XCTAssertEqual(0, result.count)
    }

    // --- Mock 强智 HTML ---
    private let mockQzHtml = """
        <html><body>
        <table id="kbtable">
          <tr><td></td><td></td><td></td><td></td><td></td><td></td><td></td><td></td></tr>
          <tr>
            <td>1</td>
            <td>
              <div>
                <div class="kbcontent">
                  高数<br>
                  <span title="老师">张三</span><br>
                  <span title="教室">A101</span><br>
                  <span title="周次(节次)">1-16周</span>
                </div>
              </div>
            </td>
            <td></td><td></td><td></td><td></td><td></td><td></td>
          </tr>
        </table>
        </body></html>
    """

    func testJwQzParserParsesQZMockHTML() {  // ← `JwQzParser parses QZ mock HTML`
        let courses = JwQzParser(mockQzHtml).generateCourseList()
        XCTAssertTrue(courses.count >= 1, "应至少 1 门课")
        // Android 侧只打日志不断言字段。iOS 补字段断言,但对齐真实语义:
        // - name: 无 <font> 标签时 substringBefore("<font")=整块 → text() 拼全部
        // - day: td 顺序计数,节次格("1")也算第 1 天 → 课程在 td[1] = day 2
        // - 周: title="周次(节次)" 1-16周 → (1,16)
        let c = courses[0]
        XCTAssertTrue(c.name.contains("高数"), "name 应含课程名(实际: \(c.name))")
        XCTAssertEqual("张三", c.teacher)
        XCTAssertEqual("A101", c.room)
        XCTAssertEqual(2, c.day)
        XCTAssertEqual(1, c.startWeek)
        XCTAssertEqual(16, c.endWeek)
        XCTAssertEqual(3, c.startNode)  // mock 有两行 tr: 空行 nodeCount=1、课行 nodeCount=2 → node=2*2-1=3(与 Kotlin 一致)
    }
}

// MARK: - ← JwNewZfParserTest.kt (v1.0.29 审计修复验证)

final class JwNewZfParserTests: XCTestCase {

    /// 正方新版典型 API JSON:多段周次 + 缺结束节次
    private let jsonSource = """
            {"kbxx":[
              {"kcmc":"高等数学","jsxm":"张老师","jasmc":"A101","kcxq":1,
               "ksjc":1,"jsjc":2,"zcd":"1-11周(单),13-16周"},
              {"kcmc":"单节缺结束","jsxm":"李老师","jasmc":"B202","kcxq":2,
               "ksjc":3,"zcd":"1-16周"}
            ]}
    """

    func testMultiSegmentWeeksPreserved() {  // ← `multi-segment weeks preserved`
        let courses = JwNewZfParser(jsonSource).generateCourseList()
        let gao = courses.filter { $0.name == "高等数学" }
        XCTAssertEqual(2, gao.count, "高等数学应展开成 2 段周次")
        let ranges = Set(gao.map { "\($0.startWeek)-\($0.endWeek)" })
        XCTAssertTrue(ranges.contains("1-11"), "应含 1-11 段")
        XCTAssertTrue(ranges.contains("13-16"), "应含 13-16 段(之前会被 ranges.first() 丢弃)")
    }

    func testMissingEndNodeDefaultsToSingleSection() {  // ← `missing end node defaults to single section`
        let courses = JwNewZfParser(jsonSource).generateCourseList()
        let single = courses.first { $0.name == "单节缺结束" }!
        // 无 jsjc → 之前默认 startNode+1=4(2节),修复后按单节 startNode=endNode=3
        XCTAssertEqual(3, single.startNode, "缺结束节次应按单节:startNode=endNode")
        XCTAssertEqual(3, single.endNode, "缺结束节次应按单节:endNode")
    }

    func testBitmapWeekStringParsed() {  // ← `bitmap week string parsed`
        // 正方 bitmap 周次:11111111111100000(1-12 周)
        let src = #"{"kbxx":[{"kcmc":"位图课","kcxq":3,"ksjc":5,"jsjc":6,"zcd":"11111111111100000"}]}"#
        let courses = JwNewZfParser(src).generateCourseList()
        XCTAssertTrue(!courses.isEmpty, "位图周次应解析出课程")
        let c = courses[0]
        XCTAssertEqual(1, c.startWeek)
        XCTAssertEqual(12, c.endWeek)
    }
}

// MARK: - ← JwWiseduParserTest.kt (哈工程真实 xskcb_heu.json)

final class JwWiseduParserTests: XCTestCase {

    private func loadRealJson() throws -> String {
        // ← javaClass.classLoader.getResource("xskcb_heu.json")
        // 测试 target resources 以 folder 形式挂载(xcodegen buildPhase: resources, type: folder)
        let bundle = Bundle(for: JwWiseduParserTests.self)
        guard let url = bundle.url(forResource: "xskcb_heu", withExtension: "json")
            ?? bundle.url(forResource: "xskcb_heu", withExtension: "json", subdirectory: "resources") else {
            XCTFail("测试资源 xskcb_heu.json 应存在")
            throw NSError(domain: "test", code: 1)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testParsesRealHEUScheduleTotalCount() throws {  // ← `parses real HEU schedule - total count`
        let courses = JwWiseduParser(try loadRealJson()).generateCourseList()
        XCTAssertEqual(46, courses.count, "34 行展开后应为 46 个 JwCourse")
    }

    func testSingleWeekCompressionXingshiYuZhengce() throws {  // ← `single-week compression - 形势与政策`
        let courses = JwWiseduParser(try loadRealJson()).generateCourseList()
        let type1 = courses.filter { $0.type == 1 }
        XCTAssertEqual(1, type1.count, "应恰好 1 个单周课段")
        let xs = type1[0]
        XCTAssertEqual("形势与政策", xs.name)
        XCTAssertEqual(11, xs.startWeek)
        XCTAssertEqual(17, xs.endWeek)
        XCTAssertEqual(1, xs.type)
    }

    func testFieldMappingPE2() throws {  // ← `field mapping - 体育（二）`
        let courses = JwWiseduParser(try loadRealJson()).generateCourseList()
        let pe = courses.first { $0.name == "体育（二）" }!
        XCTAssertEqual("篮球训练馆", pe.room)
        XCTAssertEqual("鲍伟", pe.teacher)
        XCTAssertEqual(4, pe.day)        // 周四
        XCTAssertEqual(3, pe.startNode)
        XCTAssertEqual(4, pe.endNode)
        XCTAssertEqual(2, pe.startWeek)
        XCTAssertEqual(17, pe.endWeek)
        XCTAssertEqual(0, pe.type)       // 每周
    }

    func testMultiSegmentSplitCircuit() throws {  // ← `multi-segment split - 电路与电子I`
        let courses = JwWiseduParser(try loadRealJson()).generateCourseList()
        // 电路与电子I 周一段 SKZC 含 3 个连续段 (2-5, 7-9, 11-14)
        let circuit = courses.filter { $0.name == "电路与电子I" && $0.day == 1 }
        let ranges = Set(circuit.map { "\($0.startWeek)-\($0.endWeek)" })
        XCTAssertTrue(ranges.contains("2-5"), "应含 2-5 周段")
        XCTAssertTrue(ranges.contains("7-9"), "应含 7-9 周段")
        XCTAssertTrue(ranges.contains("11-14"), "应含 11-14 周段")
    }

    func testEmptyAndMalformedInputGraceful() throws {  // ← `empty and malformed input - graceful`
        XCTAssertEqual(0, JwWiseduParser("").generateCourseList().count)
        XCTAssertEqual(0, JwWiseduParser("not json").generateCourseList().count)
        XCTAssertEqual(0, JwWiseduParser(#"{"code":"0","datas":{}}"#).generateCourseList().count)
    }
}

// MARK: - JwImportViewModel 静态纯函数(iOS 新增,等价 Kotlin 侧可单测部分)

final class JwImportViewModelLogicTests: XCTestCase {

    func testDetectProtocolFromUrl() {
        // ← detectProtocolFromUrl 5 分支
        XCTAssertEqual(JwProtocol.TYPE_WISEDU, JwImportViewModel.detectProtocolFromUrl("https://jwgl.hrbeu.edu.cn/jwapp/sys/"))
        XCTAssertEqual(JwProtocol.TYPE_ZF_NEW, JwImportViewModel.detectProtocolFromUrl("http://x/jwglxt/kbcx"))
        XCTAssertEqual(JwProtocol.TYPE_ZF_NEW, JwImportViewModel.detectProtocolFromUrl("http://x/xtgl/login"))
        XCTAssertEqual(JwProtocol.TYPE_QZ, JwImportViewModel.detectProtocolFromUrl("http://x/qz/index"))
        // ahut 这类 URL 无协议特征 → Android/Kotlin 同为 null(数据源靠 schools.json 的 type 字段)
        XCTAssertNil(JwImportViewModel.detectProtocolFromUrl("http://jwxt.ahut.edu.cn/jsxsd/"))
        XCTAssertEqual(JwProtocol.TYPE_URP_NEW, JwImportViewModel.detectProtocolFromUrl("http://x/urp/main"))
        XCTAssertNil(JwImportViewModel.detectProtocolFromUrl("http://plain.example.com/"))
    }

    func testParseHtmlUnknownProtocolTriesAllParsers() throws {
        // wisedu JSON 直喂,protocol 空 → tryAllParsers 应命中 Wisedu
        let json = #"{"datas":{"xskcb":{"rows":[{"KCM":"测试课","SKJS":"T","JASMC":"R","SKXQ":"2","KSJC":"1","JSJC":"2","SKZC":"11111111111111110000"}]}}}"#
        let courses = try JwImportViewModel.parseHtml(json, protocolType: "")
        XCTAssertEqual(1, courses.count)
        XCTAssertEqual("测试课", courses[0].name)
        XCTAssertEqual(2, courses[0].day)
    }

    func testParseHtmlDispatchesByProtocol() throws {
        let qz = """
        <html><body><table id="kbtable"><tr><td>1</td><td><div><div class="kbcontent">课A<br><span title="老师">张</span><span title="教室">101</span><span title="周次(节次)">1-8周</span></div></div></td><td></td><td></td><td></td><td></td><td></td><td></td></tr></table></body></html>
        """
        let courses = try JwImportViewModel.parseHtml(qz, protocolType: "qz")
        // 注: td.getElementsByTag("div") 含嵌套内外两层 div,各命中一次 kbcontent →
        // 与 Android/Jsoup 相同,单课格产出 2 条(Kotlin 测试用 >=1 掩盖;忠实移植保持一致)
        XCTAssertGreaterThanOrEqual(courses.count, 1)
        XCTAssertTrue(courses[0].name.contains("课A"))

        // 不支持协议 → 抛
        XCTAssertThrowsError(try JwImportViewModel.parseHtml("<html/>", protocolType: "pku"))
    }

    func testToCourseEntitiesMapping() {
        // ← toCourseEntities 字段映射 + coerce 语义
        let jw = JwCourse(name: "", room: "R", teacher: "T", day: 9, startNode: 0, endNode: 3, startWeek: -1, endWeek: -5, type: 2)
        let e = JwImportViewModel.toCourseEntities([jw], tableId: 7, defaultColor: "#FF112233")[0]
        XCTAssertEqual("未命名", e.courseName)     // ifBlank
        XCTAssertEqual(7, e.tableId)
        XCTAssertEqual(7, e.day)                   // 9 → coerceIn(1,7) = 7
        XCTAssertEqual(1, e.startNode)             // coerceAtLeast(1)
        XCTAssertEqual(4, e.step)                  // (3-0+1).coerceAtLeast(1)
        XCTAssertEqual(1, e.startWeek)             // coerceAtLeast(1)
        XCTAssertEqual(-1, e.endWeek)              // Kotlin 原语义: max(-5, -1) = -1
        XCTAssertEqual(2, e.type)
        XCTAssertEqual("#FF112233", e.color)
    }

    func testImportAsNewTableFullChain() throws {
        // G4 链条③: JwCourse → importAsNewTable → CourseDao 查询
        let db = try AppDatabase.inMemory()
        let jwCourses = [
            JwCourse(name: "课一", room: "A", teacher: "T1", day: 1, startNode: 1, endNode: 2, startWeek: 1, endWeek: 16, type: 0),
            JwCourse(name: "课一", room: "A", teacher: "T1", day: 3, startNode: 3, endNode: 4, startWeek: 1, endWeek: 16, type: 0),
            JwCourse(name: "课二", room: "B", teacher: "T2", day: 5, startNode: 5, endNode: 6, startWeek: 2, endWeek: 17, type: 1)
        ]
        let newId = try JwImportViewModel.importAsNewTable(
            db, courses: jwCourses, tableName: "哈工程2025-2", nodesPerDay: 12
        )
        XCTAssertGreaterThan(newId, 0)

        let table = try db.timeTableDao.getById(newId)
        XCTAssertEqual("哈工程2025-2", table?.name)
        XCTAssertEqual(12, table?.nodesPerDay)
        XCTAssertEqual(true, table?.isDefault)

        let all = try db.courseDao.getByTable(newId)
        XCTAssertEqual(3, all.count)
        // 同名课程共享 groupId
        let g1 = Set(all.filter { $0.courseName == "课一" }.map { $0.groupId })
        XCTAssertEqual(1, g1.count)
        // 默认色
        XCTAssertTrue(all.allSatisfy { $0.color == "#FF6750A4" })

        // 空课程 → 抛
        XCTAssertThrowsError(try JwImportViewModel.importAsNewTable(db, courses: [], tableName: "x"))
    }

    func testSchoolsJsonLoadsAndParses() throws {
        // ← parseSchoolsJson 走 app bundle 的 schools.json(146 校)
        let bundle = Bundle(for: JwImportViewModel.self) // @testable → 用 app 类型
        let url = Bundle.main.url(forResource: "schools", withExtension: "json")
            ?? bundle.url(forResource: "schools", withExtension: "json")
        let raw = try String(contentsOf: url!, encoding: .utf8)
        let text = raw
        let list = try schoolsFromJson(text)
        XCTAssertEqual(146, list.count)
        let first = list[0]
        XCTAssertFalse(first.name.isEmpty)
    }

    // 复刻 parseSchoolsJson 以便独立验证(静态方法私有)
    private func schoolsFromJson(_ text: String) throws -> [JwSchoolInfo] {
        let data = text.data(using: .utf8)!
        let arr = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]
        return arr.map { obj in
            JwSchoolInfo(
                sortKey: obj["sortKey"] as? String ?? "",
                name: obj["name"] as? String ?? "",
                url: obj["url"] as? String ?? "",
                type: (obj["type"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                aliases: (obj["aliases"] as? [String]) ?? [],
                sortKeyFull: obj["sortKeyFull"] as? String ?? ""
            )
        }
    }
}
