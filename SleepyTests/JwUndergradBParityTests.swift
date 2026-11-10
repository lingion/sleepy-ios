import XCTest
@testable import Sleepy

/// Independently enumerated Android v1.0.64 school occurrences, including metadata.
final class JwUndergradBParityTests: XCTestCase {
    private struct Occurrence: Hashable {
        let name: String; let room: String; let teacher: String
        let week: Int; let day: Int; let node: Int; let credit: Float; let note: String
    }
    private func actual(_ courses: [JwCourse]) -> Set<Occurrence> {
        Set(courses.flatMap { course in (course.startWeek...course.endWeek).filter { course.type == 0 || $0 % 2 == course.type % 2 }.flatMap { week in
            (course.startNode...course.endNode).map { Occurrence(name: course.name, room: course.room, teacher: course.teacher, week: week, day: course.day, node: $0, credit: course.credit, note: course.note) }
        } })
    }
    private func expected(_ name: String, _ room: String, _ teacher: String, _ weeks: [Int], _ day: Int, _ nodes: [Int], credit: Float = 0, note: String = "") -> Set<Occurrence> {
        Set(weeks.flatMap { week in nodes.map { Occurrence(name: name, room: room, teacher: teacher, week: week, day: day, node: $0, credit: credit, note: note) } })
    }
    private func parse(_ source: String, _ type: String, file: StaticString = #filePath, line: UInt = #line) throws -> [JwCourse] {
        let direct = ["sicnu", "nuist", "sit", "sysu"].contains(type)
            ? JwUndergradBGridParser(source, protocolType: type).generateCourseList()
            : JwUndergradBHtmlParser(source, protocolType: type).generateCourseList()
        let declared = try JwParserRegistry.parserFor(type, source).generateCourseList()
        XCTAssertEqual(declared, direct, file: file, line: line)
        XCTAssertEqual(JwParserRegistry.selectBest(source, declaredType: type).0, direct, file: file, line: line)
        XCTAssertEqual(try JwImportViewModel.parseHtmlStatic(source, type).courses, direct, file: file, line: line)
        return direct
    }

    func testHuatFifthRowHasThreeNodesAndKeepsHyphenatedNames() throws {
        let rows = (0...4).map { row in
            "<tr valign='middle'><td align='center'>标签</td>" + (row == 4 ? "<td><table><tbody><tr><td>设计-实验 王师 H 1201 1-3周</td></tr></tbody></table></td>" : "<td></td>") + "<td><table><tbody><tr><td>英语 王师 H 1301 2-4周</td></tr></tbody></table></td></tr>"
        }.joined()
        let courses = try parse("<table id='ctl00_ContentPlaceHolder1_CourseTable'>\(rows)</table>", "huat")
        var want = expected("设计-实验", "1201", "王师", [1, 2, 3], 1, [9, 10, 11])
        for row in 0...4 { want.formUnion(expected("英语", "1301", "王师", [2, 3, 4], 2, row == 4 ? [9, 10, 11] : [row * 2 + 1, row * 2 + 2])) }
        XCTAssertEqual(actual(courses), want)
        let bad = "<table id='ctl00_ContentPlaceHolder1_CourseTable'><tr valign='middle'><td><table><tr><td>数学 王师 H 1201 9-2周</td></tr></table></td></tr></table>"
        XCTAssertTrue(try parse(bad, "huat").isEmpty)
    }

    func testSeu2017JoinsTeacherCreditAndSeparateWeeks() throws {
        let source = "<table class='tableline'><tr><th>头</th></tr><tr><td>1</td><td>数学</td><td>陈师</td><td>2.5</td></tr></table><table class='tableline'><tr><th>头</th></tr><tr><td>上午</td><td>1-2节</td><td>数学<br>[1-5周]3-4节<br>A(单)<br>英语<br>[8周]5节<br>B</td></tr></table>"
        let want = expected("数学", "A", "陈师", [1, 3, 5], 1, [3, 4], credit: 2.5).union(expected("英语", "B", "", [8], 1, [5]))
        XCTAssertEqual(actual(try parse(source, "seu_2017")), want)
        XCTAssertTrue(try parse(source.replacingOccurrences(of: "3-4节", with: "4-3节").replacingOccurrences(of: "[8周]5节", with: "[8周]0节"), "seu_2017").isEmpty)
    }

    private func shuCard(_ timing: String) -> String {
        let fields = [("#", "001"), ("课程名", "数学"), ("学分", "3.5"), ("上课教师", "陈师"), ("上课时间", timing), ("上课地点", "A101")]
        return "<div class='arranged-content'><div class='el-card arranged-course-card'>" + fields.map { "<div class='card-item cv-clearfix'><div class='label cv-pull-left'>\($0.0):</div><div class='value cv-pull-left'>\($0.1)</div></div>" }.joined() + "</div></div>"
    }

    func testShu2024SparseOddWeeksAndSecondArrangement() throws {
        let want = expected("数学", "A101", "陈师", [1, 3, 9], 1, [3, 4], credit: 3.5).union(expected("数学", "A101", "陈师", [2, 6], 7, [11, 12], credit: 3.5))
        XCTAssertEqual(actual(try parse(shuCard("一3-4单(1-3周,9周) 日11-12(2周,6周)"), "shu2024")), want)
        XCTAssertTrue(try parse(shuCard("一3-4单(2周)"), "shu2024").isEmpty)
    }

    func testShu2024DesktopDefaultTermNameAndPeriods() throws {
        let cells = ["1", "物理", "代码", "2", "班级", "周师", "二1-2", "B", "x", "x", "x"]
        let source = "<div class='arranged-content'><table class='el-table__body'><tbody><tr class='el-table__row'>" + cells.map { "<td>\($0)</td>" }.joined() + "</tr></tbody></table></div>"
        XCTAssertEqual(actual(try parse(source, "shu2024")), expected("物理", "B", "周师", Array(1...10), 2, [1, 2], credit: 2))
        XCTAssertEqual(JwUndergradBHtmlParser("<a class='gologin-btn'><span class='el-link--inner'>2026-2027学年秋季学期</span></a>", protocolType: "shu2024").tableName(), "26-27秋")
        XCTAssertEqual(JwUndergradBHtmlParser.shuPeriods.last?.0, 12)
        XCTAssertEqual(JwUndergradBHtmlParser.shuPeriods.last?.1, "20:55")
        XCTAssertEqual(JwUndergradBHtmlParser.shuPeriods.last?.2, "21:40")
    }

    func testShu2024RejectsEntireMalformedArrangement() throws {
        for timing in ["一3-4(abc5)", "一3-4(第2-坏5)", "一3-4(1周,abc5)", "前缀一3-4(2周)", "一3-4后缀(2周)", "一3-4(2周)后缀", "一3-4(3-2周)", "一3-4(2147483648周)", "一3-4单(2周)双"] {
            XCTAssertTrue(try parse(shuCard(timing), "shu2024").isEmpty, timing)
        }
    }

    func testShu2024LargeRangesStayCompactWithoutInventedLimits() throws {
        XCTAssertEqual(actual(try parse(shuCard("一31-32(400-401周)"), "shu2024")), expected("数学", "A101", "陈师", [400, 401], 1, [31, 32], credit: 3.5))
        XCTAssertEqual(try parse(shuCard("一31-32单(1-2147483647周)"), "shu2024"), [JwCourse(name: "数学", room: "A101", teacher: "陈师", day: 1, startNode: 31, endNode: 32, startWeek: 1, endWeek: Int(Int32.max), type: 1, credit: 3.5)])
    }

    private func tju(_ timing: String) -> String {
        let labels = ["备注", "上课地点", "教师", "课程名称", "学分", "上课时间"]
        let fields = ["实验", "B210", "陈师(主讲)王师(助教)", "数据库", "2.5", timing]
        return "<table class='el-table__header'><tr>" + labels.map { "<th>\($0)</th>" }.joined() + "</tr></table><table class='el-table__body'><tr>" + fields.map { "<td>\($0)</td>" }.joined() + "</tr></table>"
    }

    func testTjuHeaderMappingTeacherRolesAndIndependentWeekFragments() throws {
        let want = expected("数据库", "B210", "陈师,王师", [1, 3, 5, 8], 1, [3, 4], credit: 2.5, note: "实验").union(expected("数据库", "B210", "陈师,王师", [2, 4], 3, [7], credit: 2.5, note: "实验"))
        XCTAssertEqual(actual(try parse(tju("星期一 3-4节[1-5单,8],星期三 7节[2-4双]"), "tju")), want)
        for weeks in ["1-2,bad", "1-2,0", "1-2,9-3", "1-2,2147483648"] { XCTAssertTrue(try parse(tju("星期一 1-2节[\(weeks)]"), "tju").isEmpty, weeks) }
        let embedded = "<table class='el-table__header'><tr><th>课程名称</th><th>教师</th><th>教学安排</th></tr></table><table class='el-table__body'><tr><td>物理</td><td>李师</td><td>星期日 9-10节[6]D</td></tr></table>"
        XCTAssertEqual(actual(try parse(embedded, "tju")), expected("物理", "D", "李师", [6], 7, [9, 10]))
    }

    func testHquUsesLongestUniquePlanNameAndExplicitRoomLength() throws {
        let plans = "<table id='CoursePlanTable'><tr><td>数学</td><td>短名教师</td><td>1</td></tr><tr><td>高等数学</td><td>长名教师</td><td>4</td></tr></table>"
        let cells = "<td>星期一</td>" + String(repeating: "<td></td>", count: 5) + "<td><div>代码 高等数学</div><div>C(2节)</div><div>1-5周</div><div>单周</div></td>"
        let source = plans + "<table id='ArrangeTable'><tr><th>头</th></tr><tr>\(cells)</tr></table>"
        XCTAssertEqual(actual(try parse(source, "hqu")), expected("高等数学", "C", "长名教师", [1, 3, 5], 1, [11, 12], credit: 4))
        XCTAssertEqual(actual(try parse(source.replacingOccurrences(of: "(2节)", with: ""), "hqu")), expected("高等数学", "C", "长名教师", [1, 3, 5], 1, [11, 12, 13], credit: 4))
        let unknown = "<table id='ArrangeTable'><tr><th>头</th></tr><tr><td>周一</td></tr><tr><td>周二</td><td><div>未知课</div><div>A</div><div>4周</div></td></tr></table>"
        XCTAssertEqual(actual(try parse(unknown, "hqu")), expected("未知课", "A", "", [4], 2, [1, 2]))
    }

    func testChangzhouSlashNamesSparseWeeksAndExactParityTokens() throws {
        let source = "<table id='GVxkall'><tr class='dg1-item'><td>x</td><td>数学</td><td>x</td><td>x</td><td>x</td><td>李师</td></tr></table><table id='GVxkkb'><tr class='dg1-item'><td>第一节</td><td>数学 A 单 1-5,8</td><td>实验/物理 B 全 2,6</td></tr><tr class='dg1-item'><td>第二节</td><td>数学 C 双 2-4</td></tr></table>"
        let want = expected("数学", "A", "李师", [1, 3, 5], 1, [1]).union(expected("实验/物理", "B", "", [2, 6], 2, [1])).union(expected("数学", "C", "李师", [2, 4], 1, [2]))
        XCTAssertEqual(actual(try parse(source, "changzhou")), want)
        let textToken = "<table id='GVxkkb'><tr class='dg1-item'><td>1</td><td>数学 A 未知单双 1-2</td></tr></table>"
        XCTAssertEqual(actual(try parse(textToken, "changzhou")), expected("数学", "A", "", [1, 2], 1, [1]))
        for weeks in ["9-2", "0-8", "1-2147483648"] {
            XCTAssertTrue(try parse("<table id='GVxkkb'><tr class='dg1-item'><td>1</td><td>数学 A 全 \(weeks)</td></tr></table>", "changzhou").isEmpty)
        }
        XCTAssertEqual(actual(try parse("<table id='GVxkkb'><tr class='dg1-item'><td>1</td><td>数学 A 全 400-401</td></tr></table>", "changzhou")), expected("数学", "A", "", [400, 401], 1, [1]))
    }

    private func cell(_ value: String = "", _ span: Int = 1) -> String { "<td rowspan='\(span)'>\(value)</td>" }

    func testSicnuThreeTwoAndOneLineMeetingsInheritName() throws {
        let content = "数学**<br>王师<br>A(2-6周);英语*<br>李师[B(1-5周);赵师[C(7周)"
        let source = "<table class='PintTableStyle'><tr><td width='10'>1</td>" + cell("<span>\(content)</span>", 2) + "</tr></table>"
        let want = expected("数学", "A", "王师", [2, 4, 6], 1, [1, 2]).union(expected("英语", "B", "李师", [1, 3, 5], 1, [1, 2])).union(expected("英语", "C", "赵师", [7], 1, [1, 2]))
        XCTAssertEqual(actual(try parse(source, "sicnu")), want)
        let bad = "<table class='PintTableStyle'><tr>" + cell("王师[A(1-8周);数学<br>李师<br>B(9-2周)") + "</tr></table>"
        XCTAssertTrue(try parse(bad, "sicnu").isEmpty)
    }

    func testSicnuRowspansAndEmptyRowsRetainWeekday() throws {
        let source = "<table class='PintTableStyle'><tr><td colspan='8'>上午</td></tr><tr><td width='10'>1</td>" + cell("数学<br>王师<br>A(1-2周)", 2) + cell() + "</tr><tr><td width='10'>2</td>" + cell() + "</tr><tr><td width='10'>3</td>" + cell("物理<br>李师<br>B(4周)", 3) + cell() + "</tr><tr><td width='10'>4</td>" + cell("化学<br>赵师<br>C(6周)") + "</tr></table>"
        let want = expected("数学", "A", "王师", [1, 2], 1, [1, 2]).union(expected("物理", "B", "李师", [4], 1, [3, 4, 5])).union(expected("化学", "C", "赵师", [6], 2, [4]))
        XCTAssertEqual(actual(try parse(source, "sicnu")), want)
    }

    private func nuist(_ content: String, label: String = "1～2", extra: String = "") -> String {
        "<table id='TABLE1'><tr><td>时间</td><td>星期一</td><td>星期二</td></tr><tr><td>\(label)</td><td>\(content)</td><td></td></tr>\(extra)</table>"
    }

    func testNuistPackedNodesMetadataAndRoomFallback() throws {
        let source = nuist("数学◇王师(2-6)◇}A◇x◇}B◇2-6{1112节}双◆物理◇李师(1-3)◇}C◇x◇}◇1-3{910节}单")
        let want = expected("数学", "B", "王师", [2, 4, 6], 1, [11, 12]).union(expected("物理", "C", "李师", [1, 3], 1, [9, 10]))
        XCTAssertEqual(actual(try parse(source, "nuist")), want)
    }

    func testNuistAbsentPackedNodesUsesPhysicalRowsAndDoesNotDefaultBadWeeks() throws {
        let source = nuist("英语◇周师(备注)◇}A◇周次(4-6)◇}◇4-6{节}", extra: "<tr><td>3～4</td><td></td><td>化学◇赵师()◇}D◇()◇}◇8-10{节}双</td></tr>")
        XCTAssertEqual(actual(try parse(source, "nuist")), expected("英语", "A", "周师", [4, 5, 6], 1, [1, 2]).union(expected("化学", "D", "赵师", [8, 10], 2, [3, 4])))
        let single = nuist("数学◇王师(8-2)◇}A◇x◇}◇8-2{12节}◆英语◇李师(6-6)◇}B◇x◇}◇6-6{节}", label: "1")
        XCTAssertEqual(actual(try parse(single, "nuist")), expected("英语", "B", "李师", [6], 1, [1]))
    }

    private func sitTable(_ rows: String) -> String { "<form><table><tr><th>头</th></tr><tr><th>头二</th></tr>\(rows)</table></form>" }
    private func sitEntry(_ name: String, _ weeks: String, _ room: String = "A", _ teacher: String = "王师") -> String { "<div name='d1'>\(name) \(weeks) \(room) x \(teacher)</div>" }

    func testSitStarParityAndThreeRowOccupancy() throws {
        let source = sitTable("<tr><td>1</td>" + cell(sitEntry("数学", "(1-2周"), 3) + cell() + "</tr><tr><td>2</td>" + cell() + "</tr><tr><td>3</td>" + cell(sitEntry("物理", "(4周", "B", "李师")) + "</tr><tr><td>4</td>" + cell(sitEntry("化学", "(6周", "C", "赵师")) + "</tr>")
        let want = expected("数学", "A", "王师", [1, 2], 1, [1, 2, 3]).union(expected("物理", "B", "李师", [4], 2, [3])).union(expected("化学", "C", "赵师", [6], 1, [4]))
        XCTAssertEqual(actual(try parse(source, "sit")), want)
        let parity = sitTable("<tr><td>1</td>" + cell(sitEntry("数学", "(2-6周**"), 2) + cell(sitEntry("英语", "(5周*", "B", "李师")) + "</tr>")
        XCTAssertEqual(actual(try parse(parity, "sit")), expected("数学", "A", "王师", [2, 4, 6], 1, [1, 2]).union(expected("英语", "B", "李师", [5], 2, [1])))
    }

    func testSitLastBodyExplicitPrefixAndIntegerBounds() throws {
        let schedule = sitTable("<tr><td>1</td>" + cell(sitEntry("物理", "第2-6周**", "B", "李师")) + "</tr>")
        let old = sitTable("<tr><td>1</td>" + cell(sitEntry("旧数据", "(1周")) + "</tr>")
        XCTAssertEqual(actual(try parse(old + "<body>" + schedule, "sit")), expected("物理", "B", "李师", [2, 4, 6], 1, [1]))
        let high = sitTable("<tr><td>31</td>" + cell(sitEntry("物理", "第400-401周", "B", "李师"), 2) + "</tr>")
        XCTAssertEqual(actual(try parse(high, "sit")), expected("物理", "B", "李师", [400, 401], 1, [31, 32]))
        let overflow = sitTable("<tr><td>2147483647</td>" + cell(sitEntry("物理", "第1周"), 2) + "</tr>")
        XCTAssertTrue(try parse(overflow, "sit").isEmpty)
        let last = sitTable("<tr><td>2147483647</td>" + cell(sitEntry("物理", "第1周")) + "</tr>")
        XCTAssertEqual(try parse(last, "sit"), [JwCourse(name: "物理", room: "A", teacher: "王师", day: 1, startNode: Int(Int32.max), endNode: Int(Int32.max), startWeek: 1, endWeek: 1)])
        XCTAssertTrue(try parse("<form><input name='password'></form>", "sit").isEmpty)
    }

    private func sysuTable(_ first: String, _ second: String, _ rows: String) -> String {
        "<table class='com-table class-schedule-table2'><tr><th class='th2'>节次</th><th colspan='2'>\(first)</th><th colspan='3'>\(second)</th></tr></table><table class='com-table class-schedule-table2'><tbody>\(rows)</tbody></table>"
    }
    private func sysuEntry(_ name: String, _ weeks: String = "1-1每周") -> String { "<span>\(weeks)</span><span>(001)\(name)</span><span>王/师</span><span>A/B</span>" }
    private func sysuCell(_ name: String, _ width: Int, _ height: Int = 1) -> String { "<td colspan='\(width)' rowspan='\(height)'>\(sysuEntry(name))</td>" }

    func testSysuSundayFirstAndEmptyCellsPreserveColumnWidths() throws {
        let rows = "<tr><td class='td2-1'>1</td><td class='11111' colspan='1'></td><td colspan='1' rowspan='2'>" + sysuEntry("数学", "1-5单周") + "</td><td colspan='3' rowspan='1'>" + sysuEntry("英语", "8-8每周") + "</td></tr>"
        XCTAssertEqual(actual(try parse(sysuTable("星期日", "星期一", rows), "sysu")), expected("数学", "AB", "王师", [1, 3, 5], 7, [1, 2]).union(expected("英语", "AB", "王师", [8], 1, [1])))
        let crossing = "<tr><td colspan='3' rowspan='1'>" + sysuEntry("错误") + "</td></tr>"
        XCTAssertTrue(try parse(sysuTable("星期一", "星期日", crossing), "sysu").isEmpty)
    }

    func testSysuDifferentColumnWidthsKeepMultiplePhysicalRowspans() throws {
        let rows = "<tr>" + sysuCell("数学", 2, 3) + sysuCell("物理", 1, 2) + sysuCell("英语", 2) + "</tr><tr>" + sysuCell("化学", 2) + "</tr><tr>" + sysuCell("地理", 1, 2) + sysuCell("历史", 2) + "</tr><tr>" + sysuCell("艺术", 2) + sysuCell("体育", 2) + "</tr>"
        var want = expected("数学", "AB", "王师", [1], 1, [1, 2, 3])
        for (name, day, nodes) in [("物理", 2, [1, 2]), ("英语", 2, [1]), ("化学", 2, [2]), ("地理", 2, [3, 4]), ("历史", 2, [3]), ("艺术", 1, [4]), ("体育", 2, [4])] { want.formUnion(expected(name, "AB", "王师", [1], day, nodes)) }
        XCTAssertEqual(actual(try parse(sysuTable("星期一", "星期二", rows), "sysu")), want)
        let empty = "<tr><td class='11111' colspan='2' rowspan='2'></td>" + sysuCell("英语", 3) + "</tr><tr>" + sysuCell("物理", 3) + "</tr><tr>" + sysuCell("数学", 2) + sysuCell("化学", 3) + "</tr>"
        let emptyWant = expected("英语", "AB", "王师", [1], 2, [1]).union(expected("物理", "AB", "王师", [1], 2, [2])).union(expected("数学", "AB", "王师", [1], 1, [3])).union(expected("化学", "AB", "王师", [1], 2, [3]))
        XCTAssertEqual(actual(try parse(sysuTable("星期一", "星期二", empty), "sysu")), emptyWant)
    }
}
