import XCTest
@testable import Sleepy

/// 强智 qz 变体 (QzBr / QzWithNode) 单元测试 —— 移植 Android
/// JwQzBrParserTest.kt (4 案) + JwQzWithNodeParserTest.kt (3 案)。
///
/// fixture 与 Android 端 jw/fixtures/{qz_br,qz_with_node}/ 字节级一致
/// (md5 核对过), 期望值逐条对齐 Android 测试。
final class JwQzVariantsTests: XCTestCase {

    private func fixture(_ dir: String, _ name: String) throws -> String {
        let bundle = Bundle(for: Self.self)
        guard let url = bundle.url(forResource: name, withExtension: "html", subdirectory: "resources/\(dir)")
            ?? bundle.url(forResource: name, withExtension: "html", subdirectory: dir)
            ?? bundle.url(forResource: name, withExtension: "html") else {
            XCTFail("fixture \(dir)/\(name).html 应打进测试 bundle")
            throw NSError(domain: "test", code: 1)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - JwQzBrParserTest.kt

    func testQzBrNormalFixtureEightCoursesWithMultiSegment() throws {
        let courses = try JwQzBrParser(try fixture("qz_br", "timetable_qzbr_normal")).generateCourseList()
        XCTAssertEqual(courses.count, 8, "含同格双课与逗号多段")

        // 高等数学 / 周一第1-2节 / 1-16周
        let highMath = courses[0]
        XCTAssertEqual(highMath.name, "高等数学")
        XCTAssertEqual(highMath.teacher, "张老师")
        XCTAssertEqual(highMath.room, "教一101")
        XCTAssertEqual(highMath.day, 1)
        XCTAssertEqual(highMath.startNode, 1)
        XCTAssertEqual(highMath.endNode, 2)
        XCTAssertEqual(highMath.startWeek, 1)
        XCTAssertEqual(highMath.endWeek, 16)
        XCTAssertEqual(highMath.type, 0)

        // 计算机网络 5-15,17 逗号多段应拆两条
        let networking = courses.filter { $0.name == "计算机网络" }
        XCTAssertEqual(networking.count, 2)
        XCTAssertEqual(networking[0].startWeek, 5)
        XCTAssertEqual(networking[0].endWeek, 15)
        XCTAssertEqual(networking[1].startWeek, 17)
        XCTAssertEqual(networking[1].endWeek, 17)
    }

    func testQzBrEmptyKbtableNoException() throws {
        let courses = try JwQzBrParser(try fixture("qz_br", "timetable_kbtable_empty")).generateCourseList()
        XCTAssertEqual(courses.count, 0)
    }

    func testQzBrLoginPageThrowsNoTableMarker() throws {
        // T8 契约: QzBr 继承 JwQzParser, 缺 #kbtable 抛 JwParseError
        let html = try fixture("qz_br", "login_page")
        do {
            _ = try JwQzBrParser(html).generateCourseList()
            XCTFail("应抛 JwParseError")
        } catch let e as JwParseError {
            XCTAssertEqual(e.attempts.first?.exception, JwParseError.NO_TABLE_CONTAINER_MARKER)
        }
    }

    func testQzBrCourseNameCleanWithSpanStructure() throws {
        // 区别于基础 JwQzParser.parseCourseName 的 substringBefore("<font"):
        // span 结构上得整段污染, qz_br 用 substringBefore("<br>").trim() 得干净课名。
        // .trim() 漂移锁: "测试课程 " (br 前带尾空格) 必须产出 "测试课程"。
        let html = """
        <html><body>
        <table id="kbtable">
          <tr>
            <td>第一节</td>
            <td>
              <div class="kbcontent">测试课程 <br>
                <span title="老师">王老师</span><br>
                <span title="教室">C301</span><br>
                <span title="周次(节次)">1-16(周)</span>
              </div>
            </td>
          </tr>
        </table>
        </body></html>
        """
        let courses = try JwQzBrParser(html).generateCourseList()
        XCTAssertEqual(courses.count, 1)
        XCTAssertEqual(courses[0].name, "测试课程", "不是 \"测试课程 王老师 C301 1-16(周)\"")
        XCTAssertEqual(courses[0].teacher, "王老师")
        XCTAssertEqual(courses[0].room, "C301")
    }

    // MARK: - JwQzWithNodeParserTest.kt

    func testWithNodeSpaceBranch() throws {
        let courses = try JwQzWithNodeParser(
            try fixture("qz_with_node", "timetable_qzbr_withnode_space")).generateCourseList()
        XCTAssertEqual(courses.count, 6)

        // 高等数学 周三 1-2节 (单周) — 节次来自 title 文本, type=1 来自 (单周) 后缀
        let highMath = courses.first { $0.name == "高等数学" }
        XCTAssertNotNil(highMath)
        XCTAssertEqual(highMath?.day, 3)
        XCTAssertEqual(highMath?.startNode, 1)
        XCTAssertEqual(highMath?.endNode, 2)
        XCTAssertEqual(highMath?.startWeek, 3)
        XCTAssertEqual(highMath?.endWeek, 15)
        XCTAssertEqual(highMath?.type, 1)
    }

    func testWithNodeSplitTitleBranch() throws {
        let courses = try JwQzWithNodeParser(
            try fixture("qz_with_node", "timetable_qzbr_withnode_split_title")).generateCourseList()
        XCTAssertEqual(courses.count, 5, "含 5-15,17 拆 2 条")

        // 周三 1-2节 高等数学 (单周)
        let highMath = courses.first { $0.name == "高等数学" }
        XCTAssertNotNil(highMath)
        XCTAssertEqual(highMath?.day, 3)
        XCTAssertEqual(highMath?.startNode, 1)
        XCTAssertEqual(highMath?.type, 1)

        // 大学物理 周一 5-6节 5-15,17 多段
        let physics = courses.filter { $0.name == "大学物理" }
        XCTAssertEqual(physics.count, 2)
        XCTAssertEqual(physics[0].startNode, 5)
        XCTAssertEqual(physics[0].endNode, 6)
        XCTAssertEqual(physics[0].startWeek, 5)
        XCTAssertEqual(physics[0].endWeek, 15)
        XCTAssertEqual(physics[1].startWeek, 17)
        XCTAssertEqual(physics[1].endWeek, 17)

        // ← Kotlin substringAfter(')') 缺省语义漂移锁 (Android 同结果, 旧 iOS 缺 ')' 时得 1-1):
        // 数据结构 title=节次 为裸形态 "3-4节" (无 ')'), 必须解析成 3-4 节而非默认 1-1。
        let dataStruct = courses.first { $0.name == "数据结构" }
        XCTAssertNotNil(dataStruct)
        XCTAssertEqual(dataStruct?.startNode, 3, "substringAfter(')') 缺 ')' 时 Kotlin 返回原串")
        XCTAssertEqual(dataStruct?.endNode, 4)
    }

    func testWithNodeEmptyKbtableNoException() throws {
        let courses = try JwQzWithNodeParser(
            try fixture("qz_with_node", "timetable_kbtable_empty")).generateCourseList()
        XCTAssertEqual(courses.count, 0)
    }

    /// ← Android `toInt()` 对坏数字段抛 NumberFormatException 中断整次解析
    /// (旧 iOS 静默吞成默认值)。现在 iOS 解析完统一抛 JwParseError, 整份课表
    /// 丢弃, Registry 记 0 课 + exception, 最终状态与 Android 一致。
    func testWithNodeMalformedWeekThrowsInsteadOfSilentDefault() throws {
        let html = """
        <html><body>
        <table id="kbtable">
          <tr>
            <th>第1-2节</th>
            <td>
              <div class="kbcontent">坏周次课<br>
                <font title="老师">x</font><br>
                <font title="教室">y</font><br>
                <font title="周次(节次)">a-b(周) 1-2节</font>
              </div>
            </td>
          </tr>
        </table>
        </body></html>
        """
        do {
            let courses = try JwQzWithNodeParser(html).generateCourseList()
            XCTFail("应抛 JwParseError, 实际返回 \(courses.count) 课(静默默认值)")
        } catch let e as JwParseError {
            XCTAssertEqual(e.attempts.first?.courseCount, 0)
            XCTAssertTrue(e.attempts.first?.exception?.contains("NumberFormatException") ?? false,
                          "attempt 应带数值格式异常描述, 实际 \(e.attempts.first?.exception ?? "nil")")
        }
    }

    /// else 分支 (format-3) 周次文本无 ')' 时 substringAfter 返回原串、
    /// weekStr substringBefore(')') 不补回 ')' —— 两个缺省语义锁。
    func testWithNodeElseBranchSubstringSemantics() throws {
        // "1-16(周)[1-2节]": weekStr=substringBefore(')')="1-16(周", 无空格/非空 → else 分支
        // nodeList=substringAfter(')')="[1-2节]" → removeSurrounding → ["1","2节"] → 1-2
        let html = """
        <html><body>
        <table id="kbtable">
          <tr>
            <th>第1-2节</th>
            <td>
              <div class="kbcontent">格式三课<br>
                <font title="老师">t</font><br>
                <font title="教室">r</font><br>
                <font title="周次(节次)">1-16(周)[1-2节]</font>
              </div>
            </td>
          </tr>
        </table>
        </body></html>
        """
        let courses = try JwQzWithNodeParser(html).generateCourseList()
        XCTAssertEqual(courses.count, 1)
        let c = courses[0]
        XCTAssertEqual(c.name, "格式三课")
        XCTAssertEqual(c.startNode, 1)
        XCTAssertEqual(c.endNode, 2)
        // weekStr "1-16(周" → split(',') → "1-16(周" 含 '-' → weeks ["1","16(周"]
        // endWeek = "16(周".substringBefore('(') = "16" (Android 同值; 旧 iOS 补回 ')' 也是 16,
        // 差异在 weekStr 本身 — 这里锁解析链路末端结果不回归)
        XCTAssertEqual(c.startWeek, 1)
        XCTAssertEqual(c.endWeek, 16)
        XCTAssertEqual(c.type, 0)
    }

    // MARK: - parseCourseName 单元级 trim 锁 (← Android JwQzBrParserTest 精确 "测试课程")

    func testQzBrParseCourseNameTrimsTrailingSpace() throws {
        // "高等数学 <br>..." 尾空格 → Android substringBefore("<br>").trim() 得 "高等数学",
        // 旧 iOS 未 trim 得 "高等数学 "。JwCourse 双端均原样存 name, 该差异直达展示层。
        XCTAssertEqual(JwQzBrParser("").parseCourseName("高等数学 <br><span>x</span>"), "高等数学")
        XCTAssertEqual(JwQzBrParser("").parseCourseName("  高等数学<br>x"), "高等数学")
        XCTAssertEqual(JwQzBrParser("").parseCourseName("高等数学"), "高等数学", "无 <br> 兜底原串去首尾空白")
    }
}
