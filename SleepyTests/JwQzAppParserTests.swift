import XCTest
@testable import Sleepy

/// 强智移动教务 SPA 课表解析器 (type=qz_app) 单元测试 —— 移植 Android JwQzAppParserTest。
///
/// 数据：resources/qz_app/curriculum.sample.json — 河北资源环境职业技术学院 2026-09-09
/// 学生回传采集包 (去敏后 fixture, PII 已清)。10 行 → 展开 20 个 JwCourse。
///
/// 重点锁逐周合并语义: 端点一次只回一周, 抓取侧合并成 `{"weeks":[<单次响应>, …]}`
/// 组合源, parser 必须遍历全部周元素且整行去重 —— 只取当前周会让仅在后续周
/// 出现的课整门丢失。
final class JwQzAppParserTests: XCTestCase {

    private func fixture(_ name: String) throws -> String {
        let bundle = Bundle(for: Self.self)
        guard let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "resources/qz_app")
            ?? bundle.url(forResource: name, withExtension: "json", subdirectory: "qz_app") else {
            XCTFail("fixture qz_app/\(name).json 应打进测试 bundle")
            throw NSError(domain: "test", code: 1)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func ct(_ v: String) -> [String] {
        JwQzAppParser.parseClassTime(v).map { "\($0.day)-\($0.start)-\($0.end)" }
    }

    private func runs(_ weeks: [Int]) -> [String] {
        JwQzAppParser.weekRuns(weeks).map { "\($0.0)-\($0.1)/\($0.2)" }
    }

    // MARK: - hebzyhj fixture

    func testFixtureTenRowsExpandToTwentyCourses() throws {
        let courses = try JwQzAppParser(try fixture("curriculum.sample")).generateCourseList()
        XCTAssertEqual(courses.count, 20, "10 行 → 20 JwCourse (全部两段拆, type=0)")
        var byDay: [Int: Int] = [:]
        for c in courses { byDay[c.day, default: 0] += 1 }
        XCTAssertEqual(byDay[1], 2, "周一 2")
        XCTAssertEqual(byDay[2], 2, "周二 2")
        XCTAssertEqual(byDay[3], 4, "周三 4")
        XCTAssertEqual(byDay[4], 4, "周四 4")
        XCTAssertEqual(byDay[5], 8, "周五 8")
        XCTAssertNil(byDay[6])
        XCTAssertNil(byDay[7], "无周末课程")
    }

    func testClassWeekGapSplit() throws {
        let courses = try JwQzAppParser(try fixture("curriculum.sample")).generateCourseList()
        let ads = courses.filter { $0.name == "广告策划与创意" }
        XCTAssertEqual(ads.count, 2, "两段")
        let ranges = Set(ads.map { "\($0.startWeek)-\($0.endWeek)" })
        XCTAssertTrue(ranges.contains("1-4"), "含 1-4")
        XCTAssertTrue(ranges.contains("6-19"), "含 6-19")
        XCTAssertTrue(ads.allSatisfy { $0.type == 0 }, "非步 2 → type=0")
    }

    func testMultiSegmentSplit() throws {
        let courses = try JwQzAppParser(try fixture("curriculum.sample")).generateCourseList()
        // 商务数据分析: 周五 1-2 节 (1-4,6-14) → 2 段; 周五 3-4 节 (1-4,6-15) → 2 段 = 共 4 行
        let biz = courses.filter { $0.name == "商务数据分析" }
        XCTAssertEqual(biz.count, 4, "双时段各两段 = 4 行")
        let nodes = Set(biz.map { "\($0.startNode)-\($0.endNode)" })
        XCTAssertTrue(nodes.contains("1-2"), "1-2 节")
        XCTAssertTrue(nodes.contains("3-4"), "3-4 节")
        XCTAssertTrue(biz.allSatisfy { $0.room.contains("微机室") }, "非数字房号保留")
        let ranges1to2 = Set(biz.filter { $0.startNode == 1 && $0.endNode == 2 }
            .map { "\($0.startWeek)-\($0.endWeek)" })
        XCTAssertTrue(ranges1to2.contains("1-4"), "1-2 节含 1-4")
        XCTAssertTrue(ranges1to2.contains("6-14"), "1-2 节含 6-14")
    }

    func testFieldMappingUsesClassroomNubAsRoom() throws {
        let courses = try JwQzAppParser(try fixture("curriculum.sample")).generateCourseList()
        guard let xfxw = courses.first(where: { $0.name == "消费行为分析" }) else {
            return XCTFail("fixture 应有 消费行为分析")
        }
        XCTAssertEqual(xfxw.room, "Z5-117", "完整楼栋+房号")
        XCTAssertEqual(xfxw.day, 4, "周四")
        XCTAssertEqual(xfxw.startNode, 1)
        XCTAssertEqual(xfxw.endNode, 2, "1-2 节")
        XCTAssertEqual(xfxw.teacher, "胡美娜")
    }

    // MARK: - classTime 解码 invariant

    func testClassTimeDecode() {
        // "10304" → 周一 3-4 节
        XCTAssertEqual(ct("10304"), ["1-3-4"])
        XCTAssertEqual(ct("701"), ["7-1-1"], "单节 (长度 3)")
        XCTAssertEqual(ct("21112"), ["2-11-12"])
        // 9 位连堂两段 (2026-09-11 学生采集包: ITMC 周三 1-2 + 3-4)
        XCTAssertEqual(ct("301020304"), ["3-1-2", "3-3-4"], "连堂多段展开")
        // 非法形态: 长度 4 半对 / 非数字 / day 越界 / end<start / 空串
        XCTAssertEqual(ct("1034"), [], "长度 4 拒 (01+34 半对)")
        XCTAssertEqual(ct("1030a"), [], "非数字拒")
        XCTAssertEqual(ct("0304"), [], "day=0 拒")
        XCTAssertEqual(ct("8304"), [], "day=8 拒")
        XCTAssertEqual(ct("14213"), [], "end<start 拒")
        XCTAssertEqual(ct(""), [], "空串拒")
        XCTAssertEqual(ct("-10304"), [], "负号拒")
    }

    // MARK: - 空 / 对抗输入

    func testEmptyAndAdversarialInputGraceful() throws {
        XCTAssertEqual(try JwQzAppParser("").generateCourseList().count, 0)
        XCTAssertEqual(try JwQzAppParser("not json at all").generateCourseList().count, 0)
        // 未登录 401 形态 → data 非数组 → empty (Registry 按 0 课空学期处理)
        XCTAssertEqual(try JwQzAppParser(#"{"code":"401","Msg":"非法访问：/student/curriculum","data":null}"#)
                       .generateCourseList().count, 0)
        XCTAssertEqual(try JwQzAppParser(#"{"code":"1","Msg":"success~","data":[]}"#)
                       .generateCourseList().count, 0)
        XCTAssertEqual(try JwQzAppParser(#"{"code":"1","data":[{"date":[]}]}"#)
                       .generateCourseList().count, 0)

        // courseName 空白 → 跳过, 不崩
        let blankName = """
        {"code":"1","data":[{"courses":[\
        {"classTime":"10304","classWeek":"1-4,6-19","courseName":"   "},\
        {"classTime":"10304","classWeek":"1-4,6-19","courseName":"正常课"}]}]}
        """
        let mixed = try JwQzAppParser(blankName).generateCourseList()
        XCTAssertEqual(mixed.count, 2, "空白名行跳过, 仅正常课 2 行")
        XCTAssertTrue(mixed.allSatisfy { $0.name == "正常课" })

        // classTime 非法 → 跳过该行, 不影响其它行
        let badTime = """
        {"code":"1","data":[{"courses":[\
        {"classTime":"X0304","classWeek":"1-4,6-19","courseName":"坏时间"},\
        {"classTime":"10304","classWeek":"1-4,6-19","courseName":"好时间"}]}]}
        """
        let skipBad = try JwQzAppParser(badTime).generateCourseList()
        XCTAssertEqual(skipBad.count, 2)
        XCTAssertTrue(skipBad.allSatisfy { $0.name == "好时间" })
    }

    // MARK: - weeks 信封 (逐周合并)

    /// 单次课表响应载荷 (与 QZ_APP_FETCH_JS 逐周 fetch 的返回结构一致)。
    private func weekPayload(week: Int, coursesJson: String) -> String {
        #"{"code":"1","Msg":"success~","data":[{"date":[],"course":null,"needClassName":false,"needClassRoomNub":false,"week":\#(week),"courses":[\#(coursesJson)]}]}"#
    }

    private func mergedSource(_ payloads: [String]) -> String {
        "{\"weeks\":[" + payloads.joined(separator: ",") + "]}"
    }

    /// 20 次逐周抓取合并源: 同两门课在每周响应里字节级重复 → 必须只展开一次。
    func testMergedMultiWeekDedupesIdenticalRows() throws {
        let one = """
        {"courseName":"高等数学","teacherName":"张","classTime":"10304","classWeek":"1-4,6-19","classroomNub":"Z5-101"},\
        {"courseName":"大学英语","teacherName":"李","classTime":"10506","classWeek":"1-4,6-19","classroomNub":"Z5-202"}
        """
        let courses = try JwQzAppParser(
            mergedSource((1...20).map { weekPayload(week: $0, coursesJson: one) })
        ).generateCourseList()
        // 每门课 classWeek "1-4,6-19" 拆 2 段 → 2 门 × 2 段 = 4 行, 与周数无关
        XCTAssertEqual(courses.count, 4, "20 周重复行去重 = 2 门课 × 2 周段")
        XCTAssertEqual(Set(courses.map(\.name)), ["高等数学", "大学英语"])
        XCTAssertEqual(Set(courses.map { "\($0.startWeek)-\($0.endWeek)" }), ["1-4", "6-19"])
    }

    /// 只在后续周出现的课必须保留 (旧实现只取响应数组首元素 → 整门丢失)。
    func testMergedMultiWeekKeepsCourseOnlyInLaterWeek() throws {
        let later = #"{"courseName":"大学物理实验","teacherName":"王","classTime":"30708","classWeek":"8-10","classroomNub":"物实-3"}"#
        let merged = mergedSource([
            weekPayload(week: 1, coursesJson: ""),
            weekPayload(week: 9, coursesJson: later),
        ])
        let courses = try JwQzAppParser(merged).generateCourseList()
        XCTAssertEqual(courses.count, 1, "仅后续周的课必须保留")
        XCTAssertEqual(courses.first?.name, "大学物理实验")
        XCTAssertEqual(courses.first?.startWeek, 8)
        XCTAssertEqual(courses.first?.endWeek, 10)
    }

    /// 内容不同 (换教室) 的两行必须都保留 —— 去重只吃整行字节相同者。
    func testMergedMultiWeekKeepsDifferingRows() throws {
        let a = #"{"courseName":"体育","teacherName":"赵","classTime":"20102","classWeek":"1-8","classroomNub":"操场"}"#
        let b = #"{"courseName":"体育","teacherName":"赵","classTime":"20102","classWeek":"1-8","classroomNub":"体育馆"}"#
        let merged = mergedSource([
            weekPayload(week: 1, coursesJson: a),
            weekPayload(week: 2, coursesJson: b),
        ])
        let courses = try JwQzAppParser(merged).generateCourseList()
        XCTAssertEqual(courses.count, 2, "换教室的两行都保留")
        XCTAssertEqual(Set(courses.map(\.room)), ["操场", "体育馆"])
    }

    /// 旧形态 (顶层 data 数组, 无 weeks 信封) 仍然可解 —— 向后兼容。
    func testLegacySinglePayloadStillParses() throws {
        let legacy = try fixture("curriculum.sample")
        XCTAssertTrue(!legacy.contains("\"weeks\""), "fixture 应是旧形态")
        let courses = try JwQzAppParser(legacy).generateCourseList()
        XCTAssertEqual(courses.count, 20, "旧形态解析结果不变")
    }

    func testEmptyWeeksAndNonObjectElementsSkipped() throws {
        XCTAssertEqual(try JwQzAppParser(#"{"weeks":[]}"#).generateCourseList().count, 0)
        XCTAssertEqual(try JwQzAppParser(#"{"weeks":[null,"x",3,{"data":{"courses":[]}}]}"#)
                       .generateCourseList().count, 0)
    }

    /// courses 数组混入 null/字符串坏行 → 只跳过坏行 (← Android `if (el !is JsonObject) continue`),
    /// 不得像整体 `as? [[String: Any]]` 强转那样丢掉整个 grid。
    func testCoursesArrayWithJunkElementsKeepsGoodRows() throws {
        let src = #"{"code":"1","data":[{"courses":[null,"x",42,{"classTime":"10304","classWeek":"1-4","courseName":"好课"}]}]}"#
        let courses = try JwQzAppParser(src).generateCourseList()
        XCTAssertEqual(courses.count, 1, "坏元素只跳过自身, 好课保留")
        XCTAssertEqual(courses.first?.name, "好课")
    }

    // MARK: - confidence / matchedFeatures (← Android JwQzAppParserTest 锚点案)

    func testConfidenceAnchors() {
        let strong = """
        {"code":"1","data":[{"courses":[\
        {"classWeekDetails":",1,2,3,4,","classTime":"10304","courseName":"x"}]}]}
        """
        XCTAssertEqual(JwQzAppParser(strong).confidenceValue, 90, "classWeekDetails+classTime → 90")
        let ok = """
        {"code":"1","data":[{"courses":[\
        {"classWeek":"1-4,6-19","classTime":"10304","courseName":"x"}]}]}
        """
        XCTAssertEqual(JwQzAppParser(ok).confidenceValue, 85, "classWeek+classTime → 85")
        XCTAssertEqual(JwQzAppParser(#"{"code":"1"}"#).confidenceValue, 0)
        XCTAssertEqual(JwQzAppParser(#"{"classTime":"10304"}"#).confidenceValue, 0, "缺 classWeek 系")
        XCTAssertEqual(JwQzAppParser(#"{"classWeek":"1-4"}"#).confidenceValue, 0, "缺 classTime")
    }

    func testMatchedFeaturesListReturnsOnlyPresentMarkers() {
        let full = #"{"classWeekDetails":",1,","classTime":"10304","courses":[],"code":"1","Msg":"x"}"#
        let feats = JwQzAppParser(full).matchedFeatureList
        XCTAssertTrue(feats.contains("classWeekDetails"))
        XCTAssertTrue(feats.contains("classTime"))
        XCTAssertTrue(feats.contains("courses[]"))
        XCTAssertTrue(feats.contains("code/Msg envelope"))
    }

    // MARK: - 多周合并 + 连堂多段 classTime (2026-09-11 学生三周采集包实锤)

    /// 9 门课 29 行零丢失 —— ITMC 曾因 9 位 classTime 被整行丢弃 (旧 parseClassTime 只认 3/5 位)。
    func testMultiweekRealCapturesNoLoss() throws {
        let courses = try JwQzAppParser(try fixture("curriculum.multiweek.sample")).generateCourseList()
        XCTAssertEqual(courses.count, 29)
        XCTAssertEqual(
            Set(courses.map(\.name)),
            [
                "ITMC市场营销沙盘模拟（二）",
                "商务数据分析",
                "客户关系管理",
                "广告策划与创意",
                "数字营销",
                "消费行为分析",
                "短视频策划与制作",
                "管理学",
                "财务管理（市场营销专业）",
            ],
            "9 门课全保留 (ITMC 曾因 9 位 classTime 被丢)")
    }

    func testMultiweekITMCTwoBackToBackSegments() throws {
        let courses = try JwQzAppParser(try fixture("curriculum.multiweek.sample")).generateCourseList()
        let itmc = courses.filter { $0.name == "ITMC市场营销沙盘模拟（二）" }
        // classTime "301020304" = 周三 1-2 + 3-4 两段; classWeek 11-19 → 1 段周次 × 2 时段 = 2 JwCourse
        XCTAssertEqual(Set(itmc.map { "\($0.day)-\($0.startNode)-\($0.endNode)" }),
                       ["3-1-2", "3-3-4"], "周三 1-2 与 3-4 两段都在")
        XCTAssertTrue(itmc.allSatisfy { $0.startWeek == 11 && $0.endWeek == 19 }, "周次 11-19")
    }

    func testMultiweekCrossWeekDuplicateRowsCollapsedDistinctRoomsKept() throws {
        let courses = try JwQzAppParser(try fixture("curriculum.multiweek.sample")).generateCourseList()
        // 广告策划与创意: 周一3-4 (Z5-117) + 周二5-6 (Z5-103, 7-15) — 两行不同教室都保留
        let ad117 = courses.filter { $0.name == "广告策划与创意" && $0.room == "Z5-117" }
        let ad103 = courses.filter { $0.name == "广告策划与创意" && $0.room == "Z5-103" }
        XCTAssertFalse(ad117.isEmpty, "Z5-117 行保留")
        XCTAssertFalse(ad103.isEmpty, "Z5-103 行保留 (只在 7-15 周响应出现)")
        XCTAssertEqual(ad103.first?.startWeek, 7)
        XCTAssertEqual(ad103.first?.endWeek, 15)
    }

    // MARK: - 辅助函数

    func testParseWeekSpecHandlesRangeSingleAndMixedTokens() {
        XCTAssertEqual(JwQzAppParser.parseWeekSpec("1-4"), [1, 2, 3, 4])
        XCTAssertEqual(JwQzAppParser.parseWeekSpec("6"), [6])
        XCTAssertEqual(JwQzAppParser.parseWeekSpec("1-4,6-19"), [1, 2, 3, 4] + Array(6...19))
        XCTAssertEqual(JwQzAppParser.parseWeekSpec(""), [])
        XCTAssertEqual(JwQzAppParser.parseWeekSpec("abc"), [])
        XCTAssertEqual(JwQzAppParser.parseWeekSpec("9-3"), [], "end<start 拒")
        XCTAssertEqual(JwQzAppParser.parseWeekSpec("0,31"), [], "域外拒")
        // ← Android `parseWeekSpec handles range single and mixed tokens` 域外/倒序案
        XCTAssertEqual(JwQzAppParser.parseWeekSpec("1,30,31,0,-1,abc,1-"), [1, 30], "域外/非法 token 忽略")
        XCTAssertEqual(JwQzAppParser.parseWeekSpec("1-3,5-2"), [1, 2, 3], "倒序区间忽略, 合法段保留")
        // ← Android 锚定正则: 多段 token "1-2-3" 整串不匹配 ^(\d+)-(\d+)$ → 忽略
        XCTAssertEqual(JwQzAppParser.parseWeekSpec("1-2-3"), [], "三段 token 整串拒")
    }

    func testWeekRunsContiguousStep2AndMultiSplit() {
        XCTAssertEqual(runs([1, 2, 3, 4]), ["1-4/0"], "单一连续段")
        XCTAssertEqual(runs([1, 2, 3, 4, 6, 7, 8]), ["1-4/0", "6-8/0"], "有洞 → 逐段")
        XCTAssertEqual(runs([2, 4, 6, 8]), ["2-8/2"], "整体等差 2 起于偶数 → 双周")
        XCTAssertEqual(runs([1, 3, 5]), ["1-5/1"], "整体等差 2 起于奇数 → 单周")
        XCTAssertEqual(runs([]), [])
    }

    func testExtractGridsSkipsNonObjects() throws {
        let data = Data(#"{"weeks":[{"data":[{"courses":[]}]},null,"x",3]}"#.utf8)
        let root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(JwQzAppParser.extractGrids(root).count, 1)
    }
}
