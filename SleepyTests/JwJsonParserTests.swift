// JwJsonParserTests.swift — ← JwSeuParserTest.kt / JwZjuParserTest.kt / JwUstcParserTest.kt /
// JwScuParserTest.kt / JwNeuParserTest.kt / JwCquParserTest.kt (985 批次 JSON 协议解析器测试)
// fixtures 与安卓同源: seu/zju/ustc/scu/neu courses.sample.json + my_table_cqu.json

import XCTest
@testable import Sleepy

final class JwJsonParserTests: XCTestCase {

    private func loadFixture(_ name: String) throws -> String {
        // 测试 target resources 以 folder 形式挂载(xcodegen buildPhase: resources, type: folder)
        let bundle = Bundle(for: JwJsonParserTests.self)
        guard let url = bundle.url(forResource: name, withExtension: "json")
            ?? bundle.url(forResource: name, withExtension: "json", subdirectory: "resources") else {
            XCTFail("测试资源 \(name).json 应存在")
            throw NSError(domain: "test", code: 1)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - SEU(东南大学)

    func testSeuTotalCount() throws {  // ← parses SEU courses - total count is correct
        let courses = try JwSeuParser(try loadFixture("seu_courses")).generateCourseList()
        // 4 示例课程: 1-16周 1 + 2-15单 1 + 2,4,6周 3 + 1-16双 1 = 6
        XCTAssertEqual(courses.count, 6)
    }

    func testSeuMathFields() throws {  // ← 高等数学 maps to correct fields
        let courses = try JwSeuParser(try loadFixture("seu_courses")).generateCourseList()
        let c = try XCTUnwrap(courses.first { $0.name == "高等数学" })
        XCTAssertEqual(c.day, 1)
        XCTAssertEqual(c.startNode, 1)
        XCTAssertEqual(c.endNode, 2)
        XCTAssertEqual(c.startWeek, 1)
        XCTAssertEqual(c.endWeek, 16)
        XCTAssertEqual(c.type, 0)
        XCTAssertEqual(c.teacher, "张老师")
        XCTAssertEqual(c.room, "九龙湖A楼301")
    }

    func testSeuPhysicsOddWeekStartCorrection() throws {  // ← 大学物理 weekday 3 nodes 5-6
        let courses = try JwSeuParser(try loadFixture("seu_courses")).generateCourseList()
        let c = try XCTUnwrap(courses.first { $0.name == "大学物理" })
        XCTAssertEqual(c.day, 3)
        XCTAssertEqual(c.startNode, 5)
        XCTAssertEqual(c.endNode, 6)
        XCTAssertEqual(c.startWeek, 3)  // 2 偶 → 单周首校正为 3
        XCTAssertEqual(c.endWeek, 15)
        XCTAssertEqual(c.type, 1)
    }

    func testSeuDiscreteWeeksExpand() throws {  // ← 离散周 2,4,6 expands to three entries
        let courses = try JwSeuParser(try loadFixture("seu_courses")).generateCourseList()
        let lab = courses.filter { $0.name == "数据结构实验" }
        XCTAssertEqual(lab.count, 3)
        XCTAssertEqual(lab[0].startWeek, 2)
        XCTAssertEqual(lab[1].startWeek, 4)
        XCTAssertEqual(lab[2].startWeek, 6)
        for c in lab {
            XCTAssertEqual(c.day, 5)
            XCTAssertEqual(c.startNode, 7)
            XCTAssertEqual(c.endNode, 8)
        }
    }

    func testSeuEvenWeekType2() throws {  // ← 双周课 type 2
        let courses = try JwSeuParser(try loadFixture("seu_courses")).generateCourseList()
        let c = try XCTUnwrap(courses.first { $0.name == "英语口语" })
        XCTAssertEqual(c.type, 2)
        XCTAssertEqual(c.startWeek, 2)  // 1 奇 → 双周首校正为 2
        XCTAssertEqual(c.endWeek, 16)
    }

    func testSeuNullFieldsTolerated() throws {  // ← null or missing fields tolerate
        let parser = JwSeuParser("""
        [
          {"KCM": "测试课", "SKXQ": 4, "KSJC": 3, "JSJC": 4, "ZCMC": "1-8周", "SKJS": null, "JASMC": "null"}
        ]
        """)
        let courses = try parser.generateCourseList()
        XCTAssertEqual(courses.count, 1)
        XCTAssertEqual(courses.first?.teacher, "")
        XCTAssertEqual(courses.first?.room, "")
    }

    func testSeuConfidence() {
        XCTAssertTrue(JwSeuParser("{\"KCM\":\"x\",\"ZCMC\":\"1周\"}").confidenceValue >= 80)
        XCTAssertEqual(JwSeuParser("no json").confidenceValue, 0)
    }

    func testSeuMatchedFeatures() throws {
        let features = JwSeuParser(try loadFixture("seu_courses")).matchedFeatureList
        XCTAssertTrue(features.contains { $0.contains("KCM") })
    }

    func testSeuMixedParityPerSegment() {  // ← mixed parity string applies marker per segment
        // "1-8周(单),9-16周(双)": 整串 first-match 会把后半段标成单周,
        // 偶周 10,12,14,16 全丢且多出 4 个假周。按段检测后两段各自正确。
        let ranges = JwSeuParser("{}").parseWeekRanges("1-8(单),9-16(双)")
        XCTAssertEqual(ranges.count, 2)
        XCTAssert((1, 8, 1) == ranges[0])    // 单周段: start 已奇不动; end 不做奇偶收缩
        XCTAssert((10, 16, 2) == ranges[1])  // 双周段: 9→10 抬起点
    }

    func testSeuSingleWeekSegmentEqualEndpointsNotInverted() {  // ← single week segment equal endpoints does not invert
        // "6-6(单)" 旧实现产出 (7,6) 倒挂; 共享 helper 把 end 抬回 start
        let ranges = JwSeuParser("{}").parseWeekRanges("6-6(单)")
        XCTAssertEqual(ranges.count, 1)
        XCTAssert((7, 7, 1) == ranges[0])
    }

    func testSeuFullWidthParenNormalized() {
        // "1-16周（单）" 全角形态: 先归一括号再按段检测 (对齐 Android v1.0.61)
        let ranges = JwSeuParser("{}").parseWeekRanges("1-16周（单）")
        XCTAssertEqual(ranges.count, 1)
        XCTAssert((1, 16, 1) == ranges[0])
    }

    func testSeuScalarRootReturnsEmpty() {  // ← scalar root json returns empty list not exception
        // root 是标量 (用户误粘 "42") 不得抛错, 走 0 课路径
        XCTAssertTrue(try JwSeuParser("42").generateCourseList().isEmpty)
    }

    func testSeuDataObjectShapeReturnsEmpty() {  // ← data object shape returns empty list not exception
        XCTAssertTrue(try JwSeuParser("{\"data\":{\"nested\":1}}").generateCourseList().isEmpty)
    }

    // MARK: - ZJU(浙江大学)

    func testZjuTotalCount() throws {  // ← total count is correct
        let courses = try JwZjuParser(try loadFixture("zju_courses")).generateCourseList()
        // 4 rows: 1-16周(全)1 + 2-15周(单)1 + 离散8 + 1-16周(双)1 = 11
        XCTAssertEqual(courses.count, 11)
    }

    func testZjuMathFields() throws {
        let courses = try JwZjuParser(try loadFixture("zju_courses")).generateCourseList()
        let math = try XCTUnwrap(courses.first { $0.name == "高等数学" })
        XCTAssertEqual(math.teacher, "王教授")
        XCTAssertEqual(math.room, "紫金港东1A-301")
        XCTAssertEqual(math.day, 1)
        XCTAssertEqual(math.startNode, 1)
        XCTAssertEqual(math.endNode, 2)
        XCTAssertEqual(math.startWeek, 1)
        XCTAssertEqual(math.endWeek, 16)
        XCTAssertEqual(math.type, 0)  // dsz=2 → type 0 (每周)
    }

    func testZjuPhysicsOddWeek() throws {
        let courses = try JwZjuParser(try loadFixture("zju_courses")).generateCourseList()
        let phys = try XCTUnwrap(courses.first { $0.name == "大学物理" })
        XCTAssertEqual(phys.day, 3)
        XCTAssertEqual(phys.startNode, 5)
        XCTAssertEqual(phys.endNode, 6)
        // 单周=奇数, 2-15(单) → 起点 3, 终点 15
        XCTAssertEqual(phys.startWeek, 3)
        XCTAssertEqual(phys.endWeek, 15)
        XCTAssertEqual(phys.type, 1)  // dsz=0 → type 1 (单周)
    }

    func testZjuDiscreteWeeksExpand() throws {
        let courses = try JwZjuParser(try loadFixture("zju_courses")).generateCourseList()
        let lab = courses.filter { $0.name == "数据结构实验" }
        XCTAssertEqual(lab.count, 8)
        XCTAssertEqual(lab.first?.day, 5)
        XCTAssertEqual(lab.first?.startNode, 7)
        XCTAssertEqual(lab.first?.endNode, 8)
        // 离散周每周为一段
        let weeks = lab.map { $0.startWeek }.sorted()
        XCTAssertEqual(weeks, [2, 4, 6, 8, 10, 12, 14, 16])
    }

    func testZjuEvenWeekType2() throws {
        let courses = try JwZjuParser(try loadFixture("zju_courses")).generateCourseList()
        let eng = try XCTUnwrap(courses.first { $0.name == "英语口语" })
        XCTAssertEqual(eng.day, 2)
        XCTAssertEqual(eng.startNode, 9)
        XCTAssertEqual(eng.endNode, 10)
        // 双周=偶数, 1-16(双) → 起点 2, 终点 16
        XCTAssertEqual(eng.startWeek, 2)
        XCTAssertEqual(eng.endWeek, 16)
        XCTAssertEqual(eng.type, 2)  // dsz=1 → type 2 (双周)
    }

    func testZjuDegenerateOddWeekNoInversion() throws {
        // "6-6周" dsz=0(单): 起点抬到 7, 端点相等时 end 抬回 start → (7,7) 不倒挂
        // (对齐 Android JwParity.adjustedRange; 旧内联实现产 (7,6))
        let json = """
        {"kbList": [{"xkkh": "TEST0000000000000002", "xqj": "1", "dsz": "0", "djj": "1",
                     "skcd": "1", "kcb": "倒挂测试<br>6-6周<br>老师<br>教室", "xxq": "秋冬"}]}
        """
        let courses = try JwZjuParser(json).generateCourseList()
        XCTAssertEqual(courses.count, 1)
        XCTAssertEqual(courses.first?.startWeek, 7)
        XCTAssertEqual(courses.first?.endWeek, 7)
        XCTAssertEqual(courses.first?.type, 1)
    }

    func testZjuShortKcbTolerated() throws {  // ← teacher falls back when missing in kcb
        // kcb 长度不足 4 段时不应崩; teacher 段空 → 兜底空字符串
        let json = """
        {"kbList": [{"xkkh": "TEST0000000000000001", "xqj": "4", "dsz": "2", "djj": "1",
                     "skcd": "2", "kcb": "微积分<br>1-8周<br> ", "xxq": "秋冬"}]}
        """
        let courses = try try JwZjuParser(json).generateCourseList()
        XCTAssertEqual(courses.count, 1)
        XCTAssertEqual(courses.first?.name, "微积分")
        XCTAssertEqual(courses.first?.teacher, "")
    }

    func testZjuConfidence() throws {
        XCTAssertTrue(JwZjuParser(try loadFixture("zju_courses")).confidenceValue >= 80)
        XCTAssertEqual(JwZjuParser("{\"other\":[]}").confidenceValue, 0)
    }

    func testZjuMatchedFeatures() throws {
        let features = JwZjuParser(try loadFixture("zju_courses")).matchedFeatureList
        XCTAssertTrue(features.contains { $0.lowercased().contains("kblist") })
    }

    // MARK: - USTC(中国科学技术大学)

    func testUstcTotalCount() throws {
        let courses = try JwUstcParser(try loadFixture("ustc_courses")).generateCourseList()
        // 4 activities: 1-16 全周 1 + 2-15单 1 + 离散 8 + 1-16双 1 = 11
        XCTAssertEqual(courses.count, 11)
    }

    func testUstcMathFields() throws {
        let courses = try JwUstcParser(try loadFixture("ustc_courses")).generateCourseList()
        let math = try XCTUnwrap(courses.first { $0.name == "高等数学A" })
        XCTAssertEqual(math.teacher, "王教授")
        XCTAssertEqual(math.room, "教二楼301")
        XCTAssertEqual(math.day, 1)
        // lessonCode "0102" → start=1, end=2
        XCTAssertEqual(math.startNode, 1)
        XCTAssertEqual(math.endNode, 2)
        XCTAssertEqual(math.startWeek, 1)
        XCTAssertEqual(math.endWeek, 16)
        XCTAssertEqual(math.type, 0)  // weeksStr "1-16" 无单双 → type 0
    }

    func testUstcPhysicsOddWeek() throws {
        let courses = try JwUstcParser(try loadFixture("ustc_courses")).generateCourseList()
        let phys = try XCTUnwrap(courses.first { $0.name == "大学物理B" })
        XCTAssertEqual(phys.day, 3)
        XCTAssertEqual(phys.startNode, 5)
        XCTAssertEqual(phys.endNode, 6)
        // 2-15单: 单周=奇数, 2 偶 → 校正为 3, 终点 15
        XCTAssertEqual(phys.startWeek, 3)
        XCTAssertEqual(phys.endWeek, 15)
        XCTAssertEqual(phys.type, 1)  // weeksStr 含 "单" → type 1
    }

    func testUstcDiscreteWeeksExpand() throws {
        let courses = try JwUstcParser(try loadFixture("ustc_courses")).generateCourseList()
        let lab = courses.filter { $0.name == "数据结构实验" }
        XCTAssertEqual(lab.count, 8)
        XCTAssertEqual(lab.first?.day, 5)
        XCTAssertEqual(lab.first?.startNode, 7)
        XCTAssertEqual(lab.first?.endNode, 8)
        let weeks = lab.map { $0.startWeek }.sorted()
        XCTAssertEqual(weeks, [2, 4, 6, 8, 10, 12, 14, 16])
    }

    func testUstcEvenWeekType2() throws {
        let courses = try JwUstcParser(try loadFixture("ustc_courses")).generateCourseList()
        let eng = try XCTUnwrap(courses.first { $0.name == "英语口语" })
        XCTAssertEqual(eng.day, 2)
        XCTAssertEqual(eng.startNode, 9)
        XCTAssertEqual(eng.endNode, 10)
        // 1-16双: 双周=偶数, 1 奇 → 校正为 2, 终点 16
        XCTAssertEqual(eng.startWeek, 2)
        XCTAssertEqual(eng.endWeek, 16)
        XCTAssertEqual(eng.type, 2)  // weeksStr 含 "双" → type 2
    }

    func testUstcRoomFallbackToCustomPlace() throws {
        // 英语口语 room=null, customPlace="在线" → 兜底为 customPlace
        let courses = try JwUstcParser(try loadFixture("ustc_courses")).generateCourseList()
        let eng = try XCTUnwrap(courses.first { $0.name == "英语口语" })
        XCTAssertEqual(eng.room, "在线")
    }

    func testUstcTeachersJoinWithSpace() throws {
        let json = """
        {"studentTableVm": {"activities": [
          {"courseName": "组合数学", "teachers": ["李四", "王五"], "room": "教室1",
           "weeksStr": "1-10", "weekday": "2", "lessonCode": "0304"}
        ]}}
        """
        let courses = try try JwUstcParser(json).generateCourseList()
        XCTAssertEqual(courses.first?.teacher, "李四 王五")
    }

    func testUstcMalformedLessonCodeFallsBackToTimeInference() throws {  // ← malformed lessonCode falls back to start end time inference
        // lessonCode 并非协议契约 (上游 json_version.py 只把它拼进 description,
        // 节次实际从 startDate/endDate HH:mm 推) — 不合式时不得整行丢弃。
        // 08:00 → node 1 (slot ±10min 吸附); 09:40 不吸附任何 slot → startNode+1=2
        let json = """
        {"studentTableVm": {"activities": [
          {"courseName": "机器学习", "campus": "高新园区", "customPlace": null,
           "room": "电三楼201", "teachers": ["周老师"], "weeksStr": "1-16",
           "weekday": 2, "startDate": "08:00", "endDate": "09:40", "lessonCode": "X-77"}
        ]}}
        """
        let courses = try try JwUstcParser(json).generateCourseList()
        XCTAssertEqual(courses.count, 1)
        XCTAssertEqual(courses.first?.startNode, 1)
        XCTAssertEqual(courses.first?.endNode, 2)
    }

    func testUstcLessonCodeAbsentStillParsesViaTimeInference() throws {  // ← lessonCode absent entirely still parses via time inference
        let json = """
        {"studentTableVm": {"activities": [
          {"courseName": "学术道德", "campus": null, "customPlace": "线上",
           "room": null, "teachers": ["吴老师"], "weeksStr": "6-9",
           "weekday": 5, "startDate": "19:00", "endDate": "20:50"}
        ]}}
        """
        let courses = try try JwUstcParser(json).generateCourseList()
        XCTAssertEqual(courses.count, 1)
        XCTAssertEqual(courses.first?.startNode, 9)   // 19:00 → slot 9
        XCTAssertEqual(courses.first?.endNode, 10)    // 20:50 = 19:00+110, 不吸附 → 9+1
        XCTAssertEqual(courses.first?.room, "线上")
    }

    func testUstcConfidence() throws {
        XCTAssertTrue(JwUstcParser(try loadFixture("ustc_courses")).confidenceValue >= 80)
        XCTAssertEqual(JwUstcParser("{\"other\":{}}").confidenceValue, 0)
    }

    func testUstcMatchedFeatures() throws {
        let features = JwUstcParser(try loadFixture("ustc_courses")).matchedFeatureList
        XCTAssertTrue(features.contains { $0.lowercased().contains("studenttablevm") })
    }

    // MARK: - SCU(四川大学)

    func testScuTotalCount() throws {
        let courses = try JwScuParser(try loadFixture("scu_courses")).generateCourseList()
        // 1-16周 1 + 2-15周 1 + 离散 8 + 1-16周 1 = 11
        XCTAssertEqual(courses.count, 11)
    }

    func testScuMathFields() throws {
        let courses = try JwScuParser(try loadFixture("scu_courses")).generateCourseList()
        let math = try XCTUnwrap(courses.first { $0.name == "高等数学" })
        XCTAssertEqual(math.day, 1)  // raw classDay=0 → day=1
        XCTAssertEqual(math.startNode, 1)
        XCTAssertEqual(math.endNode, 2)  // start=1, continuing=2 → 1+2-1
        XCTAssertEqual(math.teacher, "王教授")
        XCTAssertEqual(math.room, "江安校区一教A楼301")
    }

    func testScuPhysicsDayMapping() throws {
        let courses = try JwScuParser(try loadFixture("scu_courses")).generateCourseList()
        let phys = try XCTUnwrap(courses.first { $0.name == "大学物理" })
        XCTAssertEqual(phys.day, 3)
        XCTAssertEqual(phys.startNode, 5)
        XCTAssertEqual(phys.endNode, 6)
        XCTAssertEqual(phys.startWeek, 2)
        XCTAssertEqual(phys.endWeek, 15)
    }

    func testScuDiscreteWeeksExpand() throws {
        let courses = try JwScuParser(try loadFixture("scu_courses")).generateCourseList()
        let lab = courses.filter { $0.name == "数据结构实验" }
        XCTAssertEqual(lab.count, 8)
        let weeks = lab.map { $0.startWeek }.sorted()
        XCTAssertEqual(weeks, [2, 4, 6, 8, 10, 12, 14, 16])
        for c in lab { XCTAssertEqual(c.startWeek, c.endWeek) }
    }

    func testScuEnglishFields() throws {
        let courses = try JwScuParser(try loadFixture("scu_courses")).generateCourseList()
        let eng = try XCTUnwrap(courses.first { $0.name == "英语口语" })
        XCTAssertEqual(eng.day, 2)  // raw 1 → 2
        XCTAssertEqual(eng.startNode, 9)
        XCTAssertEqual(eng.endNode, 10)
        XCTAssertEqual(eng.room, "望江校区外语楼501")
    }

    func testScuWeekDescriptionStripsNonDigit() throws {
        // "1-15周(单)" 对齐 Android v1.0.61 extractParity: "(单)" 剥除后按
        // [^\d\-,] 展开, 单周信息保留 (type=1); 起点 1 已奇 → 不抬 (同 Android)
        let json = """
        {"dateList": [{"selectCourseList": [{
            "attendClassTeacher": "X", "courseName": "单周测试", "examTypeName": "",
            "timeAndPlaceList": [{"weekDescription": "1-15周(单)", "classSessions": "1",
                                  "continuingSession": "2", "classDay": "0",
                                  "teachingBuildingName": "", "classroomName": "A"}]
        }]}]}
        """
        let courses = try try JwScuParser(json).generateCourseList()
        XCTAssertEqual(courses.count, 1)
        XCTAssertEqual(courses.first?.startWeek, 1)
        XCTAssertEqual(courses.first?.endWeek, 15)
        XCTAssertEqual(courses.first?.type, 1)
    }

    func testScuSingleWeekMarkerKeptAsType1() throws {  // ← single week marker kept as type 1
        // weekDescription 真实含裸"单"后缀形态 (上游 timetable.json 资产实证);
        // 单/双信息在线协议不丢失 — 保留 type 并做端点修正 (2 偶 → 3)
        let json = """
        {"dateList": [{"selectCourseList": [{
            "attendClassTeacher": "X", "courseName": "单周测试", "examTypeName": "",
            "timeAndPlaceList": [{"weekDescription": "2-15周单", "classSessions": "1",
                                  "continuingSession": "2", "classDay": "0",
                                  "teachingBuildingName": "一教", "classroomName": "A101"}]
        }]}]}
        """
        let courses = try try JwScuParser(json).generateCourseList()
        XCTAssertEqual(courses.count, 1)
        XCTAssertEqual(courses.first?.startWeek, 3)
        XCTAssertEqual(courses.first?.endWeek, 15)
        XCTAssertEqual(courses.first?.type, 1)
    }

    func testScuDoubleWeekParenFormKeptAsType2() throws {  // ← double week paren form kept as type 2
        // 全角括号形态 "1-16周（双）": 先归一 (）→ () 再剥 "(双)" 限定词
        let json = """
        {"dateList": [{"selectCourseList": [{
            "attendClassTeacher": "X", "courseName": "双周测试", "examTypeName": "",
            "timeAndPlaceList": [{"weekDescription": "1-16周（双）", "classSessions": "1",
                                  "continuingSession": "2", "classDay": "1",
                                  "teachingBuildingName": "二教", "classroomName": "B202"}]
        }]}]}
        """
        let courses = try try JwScuParser(json).generateCourseList()
        XCTAssertEqual(courses.count, 1)
        XCTAssertEqual(courses.first?.startWeek, 2)  // 起点 1 奇 → 双周校正为 2
        XCTAssertEqual(courses.first?.endWeek, 16)
        XCTAssertEqual(courses.first?.type, 2)
    }

    func testScuConfidence() throws {
        XCTAssertTrue(JwScuParser(try loadFixture("scu_courses")).confidenceValue >= 80)
        XCTAssertEqual(JwScuParser("{\"other\":[]}").confidenceValue, 0)
    }

    func testScuMatchedFeatures() throws {
        let features = JwScuParser(try loadFixture("scu_courses")).matchedFeatureList
        XCTAssertTrue(features.contains { $0.contains("selectCourseList") })
    }

    // MARK: - NEU(东北大学)

    func testNeuTotalCount() throws {
        let courses = try JwNeuParser(try loadFixture("neu_courses")).generateCourseList()
        // 1-16周 1 + 2-15周 1 + 离散 8 + 1-16双周 1(type=0) = 11
        XCTAssertEqual(courses.count, 11)
    }

    func testNeuMathFields() throws {
        let courses = try JwNeuParser(try loadFixture("neu_courses")).generateCourseList()
        let math = try XCTUnwrap(courses.first { $0.name == "高等数学" })
        XCTAssertEqual(math.day, 1)
        XCTAssertEqual(math.startNode, 1)
        XCTAssertEqual(math.endNode, 2)
        XCTAssertEqual(math.teacher, "王教授")
        XCTAssertEqual(math.room, "浑南校区一教A楼301")
        XCTAssertEqual(math.startWeek, 1)
        XCTAssertEqual(math.endWeek, 16)
    }

    func testNeuPhysicsFields() throws {
        let courses = try JwNeuParser(try loadFixture("neu_courses")).generateCourseList()
        let phys = try XCTUnwrap(courses.first { $0.name == "大学物理" })
        XCTAssertEqual(phys.day, 3)
        XCTAssertEqual(phys.startNode, 5)
        XCTAssertEqual(phys.endNode, 6)
        XCTAssertEqual(phys.startWeek, 2)
        XCTAssertEqual(phys.endWeek, 15)
    }

    func testNeuDiscreteWeeksExpand() throws {
        let courses = try JwNeuParser(try loadFixture("neu_courses")).generateCourseList()
        let lab = courses.filter { $0.name == "数据结构实验" }
        XCTAssertEqual(lab.count, 8)
        let weeks = lab.map { $0.startWeek }.sorted()
        XCTAssertEqual(weeks, [2, 4, 6, 8, 10, 12, 14, 16])
        for c in lab { XCTAssertEqual(c.startWeek, c.endWeek) }
    }

    func testNeuEvenWeekType0() throws {
        // 1-16双周: 线协议单/双信息仍存在, Sleepy 保留 type=2 并做端点修正
        // (双周起点须偶数 → startWeek 1→2) — 对齐 Android v1.0.60
        // JwNeuParserTest "双周课 carries parity type 2 with even endpoint correction"
        let courses = try JwNeuParser(try loadFixture("neu_courses")).generateCourseList()
        let eng = try XCTUnwrap(courses.first { $0.name == "英语口语" })
        XCTAssertEqual(eng.day, 2)
        XCTAssertEqual(eng.startNode, 9)
        XCTAssertEqual(eng.endNode, 10)
        XCTAssertEqual(eng.startWeek, 2)  // 端点修正: 双周起点须偶数
        XCTAssertEqual(eng.endWeek, 16)
        XCTAssertEqual(eng.type, 2)
    }

    func testNeuTeacherExtraction() throws {
        // teacher 从 "1-16周/王教授[主讲]" 末段 "/" 后取, 剥 [主讲]
        let courses = try JwNeuParser(try loadFixture("neu_courses")).generateCourseList()
        let math = try XCTUnwrap(courses.first { $0.name == "高等数学" })
        XCTAssertEqual(math.teacher, "王教授")
    }

    func testNeuTitleDetailFallbackWhenOnlySummary() throws {
        // titleDetail 只有 summary → 回退 weeksAndTeachers "/" 前段取 week, room 空串
        let json = """
        {"datas": {"arrangedList": [{
            "courseName": "无地点课程", "dayOfWeek": 4, "beginSection": 1, "endSection": 2,
            "weeksAndTeachers": "1-16周/测试教师[主讲]", "titleDetail": ["汇总信息"]
        }]}}
        """
        let courses = try try JwNeuParser(json).generateCourseList()
        XCTAssertEqual(courses.count, 1)
        XCTAssertEqual(courses.first?.room, "")
        XCTAssertEqual(courses.first?.startWeek, 1)
        XCTAssertEqual(courses.first?.endWeek, 16)
    }

    func testNeuConfidence() throws {
        XCTAssertTrue(JwNeuParser(try loadFixture("neu_courses")).confidenceValue >= 80)
        XCTAssertEqual(JwNeuParser("{\"other\":{}}").confidenceValue, 0)
    }

    func testNeuMatchedFeatures() throws {
        let features = JwNeuParser(try loadFixture("neu_courses")).matchedFeatureList
        XCTAssertTrue(features.contains { $0.contains("arrangedList") })
    }

    // MARK: - CQU(重庆大学)

    private func parseCqu() throws -> [JwCourse] {
        try JwCquParser(try loadFixture("my_table_cqu")).generateCourseList()
    }

    func testCquTotalCount() throws {
        // 6 行压缩后应为 6 个 JwCourse
        XCTAssertEqual(try parseCqu().count, 6)
    }

    func testCquMathFields() throws {
        let math = try XCTUnwrap(try parseCqu().first { $0.name == "高等数学Ⅰ-1" })
        XCTAssertEqual(math.teacher, "张三")  // instructorName 首个 '-' 前段
        XCTAssertEqual(math.room, "A区第一教学楼101")
        XCTAssertEqual(math.day, 1)
        XCTAssertEqual(math.startNode, 1)
        XCTAssertEqual(math.endNode, 2)
        XCTAssertEqual(math.startWeek, 1)
        XCTAssertEqual(math.endWeek, 17)
    }

    func testCquEvenWeekCompression() throws {
        let physics = try parseCqu().filter { $0.name == "大学物理" }
        // 双周 bitmap 压缩成 1 个 type=2 段
        XCTAssertEqual(physics.count, 1)
        let p = try XCTUnwrap(physics.first)
        XCTAssertEqual(p.startWeek, 2)
        XCTAssertEqual(p.endWeek, 16)
        XCTAssertEqual(p.type, 2)
        XCTAssertEqual(p.day, 3)
    }

    func testCquLateWeekCourse() throws {
        let pe = try XCTUnwrap(try parseCqu().first { $0.name == "体育（三）" })
        XCTAssertEqual(pe.day, 5)
        XCTAssertEqual(pe.startNode, 6)
        XCTAssertEqual(pe.endNode, 7)
        XCTAssertEqual(pe.startWeek, 7)
        XCTAssertEqual(pe.endWeek, 24)
    }

    func testCquMultiDashTeacher() throws {
        let cct = try XCTUnwrap(try parseCqu().first { $0.name == "电路与电子Ⅱ" })
        XCTAssertEqual(cct.teacher, "赵六")  // 多 '-' 只取第一段
        XCTAssertEqual(cct.day, 4)
        XCTAssertEqual(cct.startNode, 3)
        XCTAssertEqual(cct.endNode, 4)
    }

    func testCquWholeWeekCourse() throws {
        let gx = try XCTUnwrap(try parseCqu().first { $0.name == "金工实习" })
        XCTAssertEqual(gx.startWeek, 17)
        XCTAssertEqual(gx.endWeek, 20)
        XCTAssertEqual(gx.startNode, 1)
        XCTAssertEqual(gx.endNode, 1)
        XCTAssertEqual(gx.room, "工程培训中心")
    }

    func testCquNullInstructorFallback() throws {
        let mil = try XCTUnwrap(try parseCqu().first { $0.name == "军事理论" })
        XCTAssertEqual(mil.teacher, "")
        XCTAssertEqual(mil.room, "")
        XCTAssertEqual(mil.startNode, 10)
        XCTAssertEqual(mil.endNode, 11)
    }

    func testCquConfidenceAnchors() throws {
        let p = JwCquParser(try loadFixture("my_table_cqu"))
        XCTAssertTrue(p.confidenceValue >= 80)
        XCTAssertTrue(!p.matchedFeatureList.isEmpty)
        XCTAssertEqual(JwCquParser("random text").confidenceValue, 0)
    }

    func testCquMalformedInputGraceful() throws {
        XCTAssertEqual(try try JwCquParser("").generateCourseList().count, 0)
        XCTAssertEqual(try try JwCquParser("not json").generateCourseList().count, 0)
        XCTAssertEqual(try try JwCquParser("{\"classTimetableVOList\":null}").generateCourseList().count, 0)
    }

    func testCquUrlDetection() {  // ← detectProtocolFromUrl routes my.cqu.edu.cn
        XCTAssertEqual(JwImportViewModel.detectProtocolFromUrl("https://my.cqu.edu.cn/"), JwProtocol.TYPE_CQU)
        XCTAssertEqual(JwImportViewModel.detectProtocolFromUrl("https://my.cqu.edu.cn/enroll/Home"), JwProtocol.TYPE_CQU)
        // URL 含 cqu.edu.cn 子域但非门户 host 不得误判
        XCTAssertNil(JwImportViewModel.detectProtocolFromUrl("https://jw.cqu.edu.cn/"))
    }

    func testCquRegistryDispatch() throws {  // ← registry dispatches CQU json to JwCquParser
        let (courses, attempts) = JwParserRegistry.selectBest(try loadFixture("my_table_cqu"),
                                                              declaredType: JwProtocol.TYPE_CQU)
        XCTAssertEqual(6, courses.count)
        let cqu = try XCTUnwrap(attempts.first { $0.type == JwProtocol.TYPE_CQU }, "cqu 行必须被尝试")
        XCTAssertEqual(JwProtocol.TYPE_CQU, cqu.type)
        XCTAssertGreaterThanOrEqual(cqu.confidence, 80, "CQU parser 置信度应 >= 80")
    }

    func testCquSchoolEntryRegisteredAndSupported() throws {  // ← CQU entry in schools json is registered and supported
        // ← JwParserTests.loadSchools: app bundle 的 schools.json
        let bundle = Bundle(for: JwImportViewModel.self) // @testable → 用 app 类型
        let url = Bundle.main.url(forResource: "schools", withExtension: "json")
            ?? bundle.url(forResource: "schools", withExtension: "json")
        let raw = try String(contentsOf: XCTUnwrap(url, "测试资源 schools.json 应存在"), encoding: .utf8)
        let cqu = try XCTUnwrap(JwImportViewModel.parseSchoolsJson(raw).first { $0.name == "重庆大学" },
                                "重庆大学 条目缺失")
        XCTAssertEqual("cqu", cqu.type)
        XCTAssertEqual(JwProtocol.TYPE_CQU, cqu.type)
        XCTAssertEqual("https://my.cqu.edu.cn/", cqu.url)
        XCTAssertTrue(cqu.isSupported)
        XCTAssertTrue(cqu.aliases.contains("cqu"))
        XCTAssertEqual("chongqingdaxue", cqu.sortKeyFull)
    }
}
