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

    func testJwNewUrpParserParsesHEUMockHTML() throws {  // ← `JwNewUrpParser parses HEU mock HTML`
        let parser = JwNewUrpParser(mockHeuHtml)

        let courses = try parser.generateCourseList()

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

    func testJwUrpParserHandlesEmptyHTMLGracefully() throws {  // ← `JwUrpParser handles empty HTML gracefully`
        let result = try JwUrpParser("<html><body>空</body></html>").generateCourseList()
        XCTAssertEqual(0, result.count)
    }

    func testJwNewUrpParserHandlesEmptyHTMLGracefully() throws {  // ← `JwNewUrpParser handles empty HTML gracefully`
        let result = try JwNewUrpParser("<html><body>空</body></html>").generateCourseList()
        XCTAssertEqual(0, result.count)
    }

    func testJwNewUrpParserHandlesMalformedJSONGracefully() throws {  // ← `JwNewUrpParser handles malformed JSON gracefully`
        let result = try JwNewUrpParser("not json").generateCourseList()
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

    func testJwQzParserParsesQZMockHTML() throws {  // ← `JwQzParser parses QZ mock HTML`
        let courses = try JwQzParser(mockQzHtml).generateCourseList()
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

    func testMultiSegmentWeeksPreserved() throws {  // ← `multi-segment weeks preserved`
        let courses = try JwNewZfParser(jsonSource).generateCourseList()
        let gao = courses.filter { $0.name == "高等数学" }
        XCTAssertEqual(2, gao.count, "高等数学应展开成 2 段周次")
        let ranges = Set(gao.map { "\($0.startWeek)-\($0.endWeek)" })
        XCTAssertTrue(ranges.contains("1-11"), "应含 1-11 段")
        XCTAssertTrue(ranges.contains("13-16"), "应含 13-16 段(之前会被 ranges.first() 丢弃)")
    }

    func testMissingEndNodeDefaultsToSingleSection() throws {  // ← `missing end node defaults to single section`
        let courses = try JwNewZfParser(jsonSource).generateCourseList()
        let single = courses.first { $0.name == "单节缺结束" }!
        // 无 jsjc → 之前默认 startNode+1=4(2节),修复后按单节 startNode=endNode=3
        XCTAssertEqual(3, single.startNode, "缺结束节次应按单节:startNode=endNode")
        XCTAssertEqual(3, single.endNode, "缺结束节次应按单节:endNode")
    }

    func testBitmapWeekStringParsed() throws {  // ← `bitmap week string parsed`
        // 正方 bitmap 周次:11111111111100000(1-12 周)
        let src = #"{"kbxx":[{"kcmc":"位图课","kcxq":3,"ksjc":5,"jsjc":6,"zcd":"11111111111100000"}]}"#
        let courses = try JwNewZfParser(src).generateCourseList()
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
        let courses = try JwWiseduParser(try loadRealJson()).generateCourseList()
        XCTAssertEqual(46, courses.count, "34 行展开后应为 46 个 JwCourse")
    }

    func testSingleWeekCompressionXingshiYuZhengce() throws {  // ← `single-week compression - 形势与政策`
        let courses = try JwWiseduParser(try loadRealJson()).generateCourseList()
        let type1 = courses.filter { $0.type == 1 }
        XCTAssertEqual(1, type1.count, "应恰好 1 个单周课段")
        let xs = type1[0]
        XCTAssertEqual("形势与政策", xs.name)
        XCTAssertEqual(11, xs.startWeek)
        XCTAssertEqual(17, xs.endWeek)
        XCTAssertEqual(1, xs.type)
    }

    func testFieldMappingPE2() throws {  // ← `field mapping - 体育（二）`
        let courses = try JwWiseduParser(try loadRealJson()).generateCourseList()
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
        let courses = try JwWiseduParser(try loadRealJson()).generateCourseList()
        // 电路与电子I 周一段 SKZC 含 3 个连续段 (2-5, 7-9, 11-14)
        let circuit = courses.filter { $0.name == "电路与电子I" && $0.day == 1 }
        let ranges = Set(circuit.map { "\($0.startWeek)-\($0.endWeek)" })
        XCTAssertTrue(ranges.contains("2-5"), "应含 2-5 周段")
        XCTAssertTrue(ranges.contains("7-9"), "应含 7-9 周段")
        XCTAssertTrue(ranges.contains("11-14"), "应含 11-14 周段")
    }

    func testEmptyAndMalformedInputGraceful() throws {  // ← `empty and malformed input - graceful`
        XCTAssertEqual(0, try JwWiseduParser("").generateCourseList().count)
        XCTAssertEqual(0, try JwWiseduParser("not json").generateCourseList().count)
        XCTAssertEqual(0, try JwWiseduParser(#"{"code":"0","datas":{}}"#).generateCourseList().count)
    }

    // MARK: - ← JwParserFixtureTest.kt wisedu 三例 (数字型 SKXQ/KSJC/JSJC 契约)

    /// 载入 SleepyTests/resources/wisedu-json/<name>.json
    /// (测试 target resources 以 folder 形式挂载, 加载方式参照 JwChaoxingParserTests)
    private func loadWiseduFixture(_ name: String) throws -> String {
        let bundle = Bundle(for: JwWiseduParserTests.self)
        guard let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "resources/wisedu-json")
            ?? bundle.url(forResource: name, withExtension: "json", subdirectory: "wisedu-json") else {
            XCTFail("测试资源 wisedu-json/\(name).json 应存在")
            throw NSError(domain: "test", code: 2)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// ← JwParserFixtureTest.expectedCourses: 读 expected.json 的 courses 数组,
    /// 九字段 (name/day/startNode/endNode/startWeek/endWeek/type/teacher/room), 顺序敏感。
    /// JwCourse: Equatable 恰含这九字段 → 整struct比较等价逐字段比较。
    private func expectedCourses(_ jsonText: String) throws -> [JwCourse] {
        guard let root = try JSONSerialization.jsonObject(with: Data(jsonText.utf8)) as? [String: Any],
              let arr = root["courses"] as? [[String: Any]] else {
            throw NSError(domain: "test", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "expected.json 缺 courses 数组"])
        }
        return arr.map { o in
            JwCourse(
                name: (o["name"] as? String) ?? "",
                room: (o["room"] as? String) ?? "",
                teacher: (o["teacher"] as? String) ?? "",
                day: (o["day"] as? Int) ?? -1,
                startNode: (o["startNode"] as? Int) ?? -1,
                endNode: (o["endNode"] as? Int) ?? -1,
                startWeek: (o["startWeek"] as? Int) ?? -1,
                endWeek: (o["endWeek"] as? Int) ?? -1,
                type: (o["type"] as? Int) ?? -1
            )
        }
    }

    func testWiseduFixtureContracts() throws {
        // ← caseTable 三行: wisedu-normal=5 / wisedu-missing=3 / wisedu-empty=0
        //   + `every fixture matches its nine-field expected contract` +
        //     `expectedCount annotation matches expected json` 两道闸
        let cases: [(id: String, fixture: String, count: Int)] = [
            ("wisedu-normal", "xskcb_normal", 5),
            ("wisedu-missing", "xskcb_missing_fields", 3),
            ("wisedu-empty", "xskcb_empty_rows", 0),
        ]
        for c in cases {
            let expected = try expectedCourses(try loadWiseduFixture(c.fixture + ".json.expected"))
            let actual = try JwWiseduParser(try loadWiseduFixture(c.fixture)).generateCourseList()
            XCTAssertEqual(c.count, expected.count, "\(c.id): expectedCount 注记与 expected.json 不符")
            XCTAssertEqual(expected.count, actual.count,
                           "\(c.id): 课程数 expected=\(expected.count) actual=\(actual.count)")
            XCTAssertEqual(expected, actual, "\(c.id): 九字段契约不符(顺序敏感)")
        }
    }

    func testNumericJsonPrimitivesProduceCourses() throws {
        // ← v1.0.61 对齐修复回归: kotlinx jsonPrimitive.contentOrNull 对 JSON 数字取
        // "1" 字面文本; iOS 若只认 `as? String` 则 int("SKXQ")=nil 整行丢失(修复前 0 课)。
        let json = #"""
        {"code":"0","datas":{"xskcb":{"rows":[{"KCM":"高等数学","SKJS":"张老师","JASMC":"教学楼A101",
        "SKXQ":1,"KSJC":1,"JSJC":2,
        "SKZC":"1111100000000000000000000000000000000000000000000000000000","KBID":"kb-t1"}]}}}
        """#
        let courses = try JwWiseduParser(json).generateCourseList()
        XCTAssertEqual(1, courses.count, "数字型 SKXQ/KSJC/JSJC 行不应被丢弃")
        XCTAssertEqual(JwCourse(name: "高等数学", room: "教学楼A101", teacher: "张老师",
                                day: 1, startNode: 1, endNode: 2,
                                startWeek: 1, endWeek: 5, type: 0), courses[0])
    }

    func testNullModuleThrowsNotSilentEmpty() throws {
        // ← 模块键存在但值为 JSON null: Kotlin `datas[it]?.jsonObject` 抛
        // IllegalArgumentException; iOS 同形抛 JwParseError, 不再静默吞掉(问题3修复)。
        XCTAssertThrowsError(try JwWiseduParser(#"{"datas":{"xskcb":null}}"#).generateCourseList())
        // 模块键缺失仍走 firstNotNullOfOrNull 短路 → 空表 (Kotlin 不抛)
        XCTAssertEqual(0, try JwWiseduParser(#"{"datas":{}}"#).generateCourseList().count)
    }
}

// MARK: - JwImportViewModel 静态纯函数(iOS 新增,等价 Kotlin 侧可单测部分)

final class JwImportViewModelLogicTests: XCTestCase {

    func testDetectProtocolFromUrl() {
        // ← detectProtocolFromUrlImpl 判型链(Android JwOldZfParserTest.kt:519 + JwProtocolDetectionUnitTest 为准)
        XCTAssertEqual(JwProtocol.TYPE_WISEDU, JwImportViewModel.detectProtocolFromUrl("https://jwgl.hrbeu.edu.cn/jwapp/sys/"))
        XCTAssertEqual(JwProtocol.TYPE_ZF_NEW, JwImportViewModel.detectProtocolFromUrl("http://x/jwglxt/kbcx"))
        XCTAssertEqual(JwProtocol.TYPE_ZF_NEW, JwImportViewModel.detectProtocolFromUrl("http://x/xtgl/login"))
        // ahut /jsxsd/ → QZ(Android 实测: assertEquals("qz", detectProtocolFromUrl("http://jwxt.ahut.edu.cn/jsxsd/")))
        XCTAssertEqual(JwProtocol.TYPE_QZ, JwImportViewModel.detectProtocolFromUrl("http://jwxt.ahut.edu.cn/jsxsd/"))
        // B3: 裸 urp 不再钉死 URP_NEW → nil 走 HTML/tryAllParsers 兜底
        XCTAssertNil(JwImportViewModel.detectProtocolFromUrl("http://x/urp/main"))
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

        // 不支持协议 → 抛(Android dispatch_未知协议仍抛暂不支持 同语义,type 用无工厂的假值)
        XCTAssertThrowsError(try JwImportViewModel.parseHtml("<html/>", protocolType: "nope"))
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

    // MARK: schools.json 载入工具

    /// ← parseSchoolsJson 走 app bundle 的 schools.json
    private func loadSchools() throws -> [JwSchoolInfo] {
        let bundle = Bundle(for: JwImportViewModel.self) // @testable → 用 app 类型
        let url = Bundle.main.url(forResource: "schools", withExtension: "json")
            ?? bundle.url(forResource: "schools", withExtension: "json")
        let raw = try String(contentsOf: url!, encoding: .utf8)
        return JwImportViewModel.parseSchoolsJson(raw)
    }

    private func entryOf(_ list: [JwSchoolInfo], _ name: String) -> JwSchoolInfo? {
        list.first { $0.name == name }
    }

    func testSchoolsJsonLoadsAndParses() throws {
        // 校数闸门随安卓 schools.json 联动
        // 2026-09-10 安卓 185 → v1.0.60 全量交叉验证收录 348 (15 agent 分桶, 60 修/3 删/3 更名)
        // 2026-10-10 收录湖北商贸学院(zf_new, PR #156/#157) → 349
        //   (安卓 v1.0.61 tag XjuPostgraduateAdmissionTest `main assets schools json count gate 349`;
        //    iOS resources/schools.json 与安卓 v1.0.61 assets 逐条 diff = 0)
        let list = try loadSchools()
        XCTAssertEqual(349, list.count)
        let first = list[0]
        XCTAssertFalse(first.name.isEmpty)
    }

    // ← Schools179CrossValidationTest.kt `ysu entry pinned to collector and replay evidence`
    func testYsuEntryPinnedToCollectorAndReplayEvidence() throws {
        // 采集包 sleepy-adapt (2026-09-06) + token 重放实采: yjsxt.ysu.edu.cn/pp 研究生平台
        // (博雅研究生 V6.0, fid=41571), 逐周 byStudent 390 行, termBeginTime=2026-08-31。
        // 入口 = 燕大统一身份认证 CAS, service 回调 yjsxt /api/casLogin/ysu (实测 302 链路)。
        // 研究生入口, status=grad_supported; 首个 boya_pp 协议校。
        let list = try loadSchools()
        let e = try XCTUnwrap(entryOf(list, "燕山大学"), "燕山大学 条目缺失")
        XCTAssertTrue(e.url.contains("cer.ysu.edu.cn/authserver/login"),
                      "入口应为 cer.ysu.edu.cn 统一身份认证")
        XCTAssertTrue(e.url.contains("yjsxt.ysu.edu.cn%2Fapi%2FcasLogin%2Fysu"),
                      "service 应回调 yjsxt casLogin")
        XCTAssertEqual("boya_pp", e.type, "应为 boya_pp (博雅研究生平台实锤)")
        XCTAssertEqual(JwSchoolInfo.STATUS_GRAD_SUPPORTED, e.status,
                       "应为 grad_supported (研究生入口)")
        XCTAssertTrue(e.isGrad)
    }
}
