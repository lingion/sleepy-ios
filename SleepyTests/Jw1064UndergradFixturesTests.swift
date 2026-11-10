import XCTest
@testable import Sleepy

/// Constant source/expected vectors from Android tag v1.0.64 (77b878fd).
/// Expected records are retained independently of the Swift parser implementation.
final class Jw1064UndergradFixturesTests: XCTestCase {
    struct Fixture {
        let name: String
        let type: String
        let source: String
        let expected: [JwCourse]
    }
    static let fixtures: [Fixture] = [
        // JwUndergradRoundTwoBatchOneTest.kt
        Fixture(name: "hniuReadsItsOwnTableAndDiscontinuousWeeks", type: "hniu", source: "<table bordercolordark=\"#FFFFFF\"><tbody><tr><td align=\"center\">时间</td><td valign=\"top\">离散数学<br>王老师 [1-4,6周][3-4节]<br>理科楼201</td></tr></tbody></table>", expected: [
            JwCourse(name: "离散数学", room: "理科楼201", teacher: "王老师", day: 1, startNode: 3, endNode: 4, startWeek: 1, endWeek: 4),
            JwCourse(name: "离散数学", room: "理科楼201", teacher: "王老师", day: 1, startNode: 3, endNode: 4, startWeek: 6, endWeek: 6)
        ]),
        // JwUndergradRoundTwoBatchOneTest.kt
        Fixture(name: "sustechUsesSectionBracketAndKeepsWeekSegments", type: "sustech", source: "[{\"KCWZSM\":null,\"RWH\":null,\"FILEURL\":null,\"SKSJ\":\"离散数学[王老师][教学班-01][1-8单周,10周][理科楼201][第3-4节]\",\"XB\":null,\"SKSJ_EN\":null,\"KEY\":\"xq7_jc1\"},{\"KCWZSM\":null,\"RWH\":null,\"FILEURL\":null,\"SKSJ\":\"备注\",\"XB\":null,\"SKSJ_EN\":null,\"KEY\":\"bz\"}]", expected: [
            JwCourse(name: "离散数学", room: "理科楼201", teacher: "王老师", day: 7, startNode: 3, endNode: 4, startWeek: 1, endWeek: 8, type: 1, note: "01"),
            JwCourse(name: "离散数学", room: "理科楼201", teacher: "王老师", day: 7, startNode: 3, endNode: 4, startWeek: 10, endWeek: 10, note: "01")
        ]),
        // JwUndergradRoundTwoBatchOneTest.kt
        Fixture(name: "uicKeepsAdjacentSinglePeriodsAndTeacherLookup", type: "uic", source: "<table class=\"tablestyle-2\"><tbody><tr><td>1</td><td>x</td><td>离散数学</td><td>王老师</td></tr></tbody></table><table id=\"mytimetable\"><tr><th>星期一</th></tr><tr><td>离散数学<br>理科楼201</td></tr><tr><td>离散数学<br>理科楼201</td></tr></table>", expected: [
            JwCourse(name: "离散数学", room: "理科楼201", teacher: "王老师", day: 1, startNode: 1, endNode: 1, startWeek: 1, endWeek: 20),
            JwCourse(name: "离散数学", room: "理科楼201", teacher: "王老师", day: 1, startNode: 2, endNode: 2, startWeek: 1, endWeek: 20)
        ]),
        // JwUndergradRoundTwoBatchOneTest.kt
        Fixture(name: "cityuRecoversWeekdayAfterRowSpans", type: "cityu", source: "<table class=\"ctt-matrix\"><tr><th>课表</th></tr><tr><td class=\"ctt-matrix-td-time\">08:00</td><td rowspan=\"2\">代码<br>离散数学<br>理科楼201</td><td rowspan=\"2\">代码<br>英语<br>文科楼101</td><td></td></tr><tr><td class=\"ctt-matrix-td-time\">09:00</td><td>代码<br>物理<br>实验楼301</td></tr></table>", expected: [
            JwCourse(name: "离散数学", room: "理科楼201", teacher: "", day: 1, startNode: 1, endNode: 2, startWeek: 1, endWeek: 20),
            JwCourse(name: "英语", room: "文科楼101", teacher: "", day: 2, startNode: 1, endNode: 2, startWeek: 1, endWeek: 20),
            JwCourse(name: "物理", room: "实验楼301", teacher: "", day: 3, startNode: 2, endNode: 2, startWeek: 1, endWeek: 20)
        ]),
        // JwUndergradRoundTwoBatchOneTest.kt
        Fixture(name: "stuDecodesSundayLettersCreditAndParity", type: "stu", source: "<table id=\"DataGrid1\"><tr class=\"DGHeaderStyle\"><td>表头</td></tr><tr><td>1</td><td>[CS101]离散数学</td><td>2.5</td><td>王老师</td><td>理科楼201</td><td>2-16</td><td>AB双</td><td></td><td></td><td></td><td></td><td></td><td></td></tr><tr class=\"DGFooterStyle\"><td>页脚</td></tr></table>", expected: [
            JwCourse(name: "离散数学", room: "理科楼201", teacher: "王老师", day: 7, startNode: 11, endNode: 12, startWeek: 2, endWeek: 16, type: 2, credit: 2.5)
        ]),
        // JwUndergradRoundTwoBatchOneTest.kt
        Fixture(name: "nfuKeepsMultipleSundayOccurrencesAndOptionalRoom", type: "nfu", source: "<table><tr class=\"ui-widget-content\"><td><span>离散数学</span><span></span><span></span><span></span><span></span><span></span><span></span><span></span><span></span><span>第1-8周 第3-4节 王老师 理科楼201 单周/第10周 第5节 王老师</span></td></tr></table>", expected: [
            JwCourse(name: "离散数学", room: "理科楼201", teacher: "王老师", day: 7, startNode: 3, endNode: 4, startWeek: 1, endWeek: 8, type: 1),
            JwCourse(name: "离散数学", room: "", teacher: "王老师", day: 7, startNode: 5, endNode: 5, startWeek: 10, endWeek: 10)
        ]),
        // JwUndergradRoundTwoBatchOneTest.kt
        Fixture(name: "cityuRestoresColumnsAfterEmptyAndExpiredRowSpans", type: "cityu", source: "<table class=\"ctt-matrix\"><tr><th>课表</th></tr><tr><td class=\"ctt-matrix-td-time\">08:00</td><td rowspan=\"2\">代码<br>离散数学<br>A</td><td></td></tr><tr><td class=\"ctt-matrix-td-time\">09:00</td><td></td></tr><tr><td class=\"ctt-matrix-td-time\">10:00</td><td rowspan=\"2\">代码<br>英语<br>B</td><td></td></tr><tr><td class=\"ctt-matrix-td-time\">11:00</td><td>代码<br>物理<br>C</td></tr></table>", expected: [
            JwCourse(name: "离散数学", room: "A", teacher: "", day: 1, startNode: 1, endNode: 2, startWeek: 1, endWeek: 20),
            JwCourse(name: "英语", room: "B", teacher: "", day: 1, startNode: 3, endNode: 4, startWeek: 1, endWeek: 20),
            JwCourse(name: "物理", room: "C", teacher: "", day: 2, startNode: 4, endNode: 4, startWeek: 1, endWeek: 20)
        ]),
        // JwUndergradRoundTwoBatchOneTest.kt
        Fixture(name: "sustechHighSectionsSurviveDeclaredSelectionImportAndDraft", type: "sustech", source: "[{\"KEY\":\"xq7_jc1\",\"SKSJ\":\"离散数学[王老师][教学班-01][2-8双周][A][第30-31节]\"}]", expected: [
            JwCourse(name: "离散数学", room: "A", teacher: "王老师", day: 7, startNode: 30, endNode: 31, startWeek: 2, endWeek: 8, type: 2, note: "01")
        ]),
        // JwUndergradRoundTwoBatchTwoTest.kt
        Fixture(name: "bjtuReadsPinnedLegacyTextWithoutRequiringModernDayHeaders", type: "bjtu", source: "<table class=\"table table-bordered\"><tr><th>课表</th></tr><tr><td>第一节</td><td>ABCDEFG [01] 离散数学 [1] 第01-08周 王老师 AB123</td><td></td><td></td><td></td><td></td><td></td><td></td></tr></table>", expected: [
            JwCourse(name: "离散数学", room: "AB123", teacher: "王老师", day: 1, startNode: 1, endNode: 1, startWeek: 1, endWeek: 8)
        ]),
        // JwUndergradRoundTwoBatchTwoTest.kt
        Fixture(name: "swustUsesLastSevenColumnsAndOneBasedPeriods", type: "swust", source: "<table class=\"UICourseTable\"><tbody><tr><td>时段</td><td></td><td></td><td></td><td></td><td></td><td></td><td><div class=\"lecture\"><span class=\"course\">离散数学</span><span class=\"place\">理科楼201</span><span class=\"week\">1-8(周)</span></div></td></tr></tbody></table>", expected: [
            JwCourse(name: "离散数学", room: "理科楼201", teacher: "", day: 7, startNode: 1, endNode: 1, startWeek: 1, endWeek: 8)
        ]),
        // JwUndergradRoundTwoBatchTwoTest.kt
        Fixture(name: "scauReadsExplicitPackedSectionAndWeeksAtTheirActualOffsets", type: "scau", source: "<table border=\"1\"><tr><th>课表</th></tr><tr><td valign=\"top\">离散数学<br>(910节)(双)<br>王老师<br>理科楼201<br>2-10周</td></tr></table>", expected: [
            JwCourse(name: "离散数学", room: "理科楼201", teacher: "王老师", day: 1, startNode: 9, endNode: 10, startWeek: 2, endWeek: 10, type: 2)
        ]),
        // JwUndergradRoundTwoBatchTwoTest.kt
        Fixture(name: "scauDoesNotReuseASectionFromThePreviousCell", type: "scau", source: "<table border=\"1\"><tr><th>课表</th></tr><tr><td valign=\"top\">离散数学<br>(12节)<br>王老师<br>A<br>1-8周</td><td valign=\"top\">英语<br>(1112节)<br>李老师<br>B<br>2-10周</td></tr></table>", expected: [
            JwCourse(name: "离散数学", room: "A", teacher: "王老师", day: 1, startNode: 1, endNode: 2, startWeek: 1, endWeek: 8),
            JwCourse(name: "英语", room: "B", teacher: "李老师", day: 2, startNode: 11, endNode: 12, startWeek: 2, endWeek: 10)
        ]),
        // JwUndergradRoundTwoBatchThreeTest.kt
        Fixture(name: "jmucyKeepsStarSeparatedCoursesAndSparseWeeks", type: "jmucy", source: "<table id=\"ctl00_ContentPlaceHolder3_ScheduleTable\"><tr><th>课表</th></tr><tr><td>第一二节</td><td>离散数学 A 王老师 第1-4周,6周★英语 李老师 第2-8双周</td></tr></table>", expected: [
            JwCourse(name: "离散数学", room: "A", teacher: "王老师", day: 1, startNode: 1, endNode: 2, startWeek: 1, endWeek: 4),
            JwCourse(name: "离散数学", room: "A", teacher: "王老师", day: 1, startNode: 1, endNode: 2, startWeek: 6, endWeek: 6),
            JwCourse(name: "英语", room: "", teacher: "李老师", day: 1, startNode: 1, endNode: 2, startWeek: 2, endWeek: 8, type: 2)
        ]),
        // JwUndergradRoundTwoBatchThreeTest.kt
        Fixture(name: "nuaajcFindsColumnsByTheirServerHeaders", type: "nuaajc", source: "<table id=\"GrwCourseTablePrint\"><tr><th>weekly</th><th>unit</th><th>kcm</th><th>week</th><th>roomid</th><th>lsjs</th><th>jsm</th></tr><tr><td>1-4,6</td><td>9</td><td>离散数学</td><td>7</td><td>A</td><td>3</td><td>王老师</td></tr></table>", expected: [
            JwCourse(name: "离散数学", room: "A", teacher: "王老师", day: 7, startNode: 9, endNode: 11, startWeek: 1, endWeek: 4),
            JwCourse(name: "离散数学", room: "A", teacher: "王老师", day: 7, startNode: 9, endNode: 11, startWeek: 6, endWeek: 6)
        ]),
        // JwUndergradRoundTwoBatchThreeTest.kt
        Fixture(name: "qmuUsesOnlyRowsWithCourseCellsAndDotSeparatedWeeks", type: "qmu", source: "<table frame=\"box\"><tr><th>表头</th></tr><tr><td valign=\"top\">离散数学<br>王老师<br>A<br>1-4.6周 单周 2节</td></tr><tr><th>中午</th></tr><tr><td valign=\"top\">英语<br>李老师<br>B<br>2-8周 双周 1节</td></tr></table>", expected: [
            JwCourse(name: "离散数学", room: "A", teacher: "王老师", day: 1, startNode: 1, endNode: 2, startWeek: 1, endWeek: 4, type: 1),
            JwCourse(name: "离散数学", room: "A", teacher: "王老师", day: 1, startNode: 1, endNode: 2, startWeek: 6, endWeek: 6, type: 1),
            JwCourse(name: "英语", room: "B", teacher: "李老师", day: 1, startNode: 3, endNode: 3, startWeek: 2, endWeek: 8, type: 2)
        ]),
        // JwUndergradRoundTwoBatchThreeTest.kt
        Fixture(name: "hitszKeepsLabAndTheoryCardFields", type: "hitsz", source: "<table><tbody class=\"ivu-table-tbody\"><tr><td>节次</td><td><div class=\"ivu-card-body\">离散数学 [王老师] [第1-8单周,10周][A] 第3-4节</div><div class=\"ivu-card-body\">【实验】物理 [第5-6节][第2-8双周] [实验楼]</div></td></tr></tbody></table>", expected: [
            JwCourse(name: "离散数学", room: "A", teacher: "王老师", day: 1, startNode: 3, endNode: 4, startWeek: 1, endWeek: 8, type: 1),
            JwCourse(name: "离散数学", room: "A", teacher: "王老师", day: 1, startNode: 3, endNode: 4, startWeek: 10, endWeek: 10),
            JwCourse(name: "【实验】物理", room: "实验楼", teacher: "", day: 1, startNode: 5, endNode: 6, startWeek: 2, endWeek: 8, type: 2)
        ]),
        // JwUndergradRoundTwoBatchFourTest.kt
        Fixture(name: "shsmuUsesPinnedMondayBaselineAndBothActualTimes", type: "shsmu", source: "{\"list\":[\n          {\"Curriculum\":\"医学基础\",\"Teacher\":\"王老师\",\"ClassroomAcademy\":\"A\",\"Start\":\"2025-09-21 08:00:00\",\"End\":\"2025-09-21 09:30:00\"},\n          {\"Curriculum\":\"护理学\",\"Teacher\":null,\"ClassroomAcademy\":null,\"Start\":\"2025-09-22T13:30:00\",\"End\":\"2025-09-22T15:00:00\"}\n        ]}", expected: [
            JwCourse(name: "医学基础", room: "A", teacher: "王老师", day: 7, startNode: 1, endNode: 2, startWeek: 1, endWeek: 1, startTime: "08:00", endTime: "09:30"),
            JwCourse(name: "护理学", room: "", teacher: "", day: 1, startNode: 6, endNode: 7, startWeek: 2, endWeek: 2, startTime: "13:30", endTime: "15:00")
        ]),
        // JwUndergradRoundTwoBatchFourTest.kt
        Fixture(name: "shsmuKeepsCompleteIntervalWhenOnlyOneEndpointMatchesSchoolClock", type: "shsmu", source: "{\"list\":[\n          {\"Curriculum\":\"实验一\",\"Start\":\"2025-09-23 08:00:00\",\"End\":\"2025-09-23 09:25:00\"},\n          {\"Curriculum\":\"实验二\",\"Start\":\"2025-09-23 08:05:00\",\"End\":\"2025-09-23 09:30:00\"},\n          {\"Curriculum\":\"实验三\",\"Start\":\"2025-09-23 08:05:00\",\"End\":\"2025-09-23 09:25:00\"}\n        ]}", expected: [
            JwCourse(name: "实验一", day: 2, startNode: 1, endNode: 2, startWeek: 2, endWeek: 2, startTime: "08:00", endTime: "09:25"),
            JwCourse(name: "实验二", day: 2, startNode: 1, endNode: 2, startWeek: 2, endWeek: 2, startTime: "08:05", endTime: "09:30"),
            JwCourse(name: "实验三", day: 2, startNode: 1, endNode: 2, startWeek: 2, endWeek: 2, startTime: "08:05", endTime: "09:25")
        ]),
        Fixture(name: "cRouting_xhtd", type: "xhtd", source: "<div id='kbtable'><div id='1-1'><nobr>课程2</nobr><br>类别<br>王<br>第5周<br>A</div></div>", expected: [JwCourse(name: "课程2", room: "A", teacher: "王", day: 1, startNode: 1, endNode: 2, startWeek: 5, endWeek: 5, credit: 0, note: "")]),
        Fixture(name: "cRouting_xytc", type: "xytc", source: "<table id='report_tSxsgrkbcx'><tr><td>课程2&nbsp;5周&nbsp;星期1&nbsp;1节&nbsp;A&nbsp;王</td></tr></table>", expected: [JwCourse(name: "课程2", room: "A", teacher: "王", day: 1, startNode: 1, endNode: 1, startWeek: 5, endWeek: 5, credit: 0, note: "")]),
        Fixture(name: "cRouting_cidp", type: "cidp", source: "<div id='scheduleTable'><div class='Content' data-week='1' data-class='1'><div class='divOneClass'><span class='spLUName'>课程2</span><span class='spTeacherName'>王</span><span class='spWeekInfo'>5周</span><span class='spClassroom'>A</span></div></div></div>", expected: [JwCourse(name: "课程2", room: "A", teacher: "王", day: 1, startNode: 1, endNode: 2, startWeek: 5, endWeek: 5, credit: 0, note: "")]),
        Fixture(name: "cRouting_sdpei", type: "sdpei", source: "<table id='tableMain'><tr><th>第一节</th><td><div class='divOneClass'><span class='spLUName'>课程2</span><span class='spTeacherName'>王</span><span class='spWeekInfo'>5周</span><span class='spClassroom'>A</span></div></td></tr></table>", expected: [JwCourse(name: "课程2", room: "A", teacher: "王", day: 1, startNode: 1, endNode: 1, startWeek: 5, endWeek: 5, credit: 0, note: "")]),
        Fixture(name: "cRouting_shu", type: "shu", source: "<table><tr name='rowclass'><td>编号</td><td>类别</td><td>课程2</td><td>2.5</td><td>其他</td><td>王</td><td>一1-1(5周)</td><td>A</td></tr></table>", expected: [JwCourse(name: "课程2", room: "A", teacher: "王", day: 1, startNode: 1, endNode: 1, startWeek: 5, endWeek: 5, credit: 2.5, note: "")]),
        Fixture(name: "cRouting_cqu", type: "cqu", source: "<div class='print-schedule-table'><div class='item-box'><div class='item-name'>课程2[代码]</div><div class='item-location'>A</div><div class='item-instr'>王-主讲</div><div class='item-time'>5周 1节 星期一</div></div></div>", expected: [JwCourse(name: "课程2", room: "A", teacher: "王", day: 1, startNode: 1, endNode: 1, startWeek: 5, endWeek: 5, credit: 0, note: "")]),
        Fixture(name: "cRouting_jmpt", type: "jmpt", source: "<table class='admintable'></table><table class='admintable'><tr><td rowspan='1'>星期一</td><td>第5周</td><td>1</td><td>1</td><td>课程2</td><td>其他</td><td>王</td><td>A</td><td>限选</td><td>每周</td><td>其他</td><td>其他</td></tr></table>", expected: [JwCourse(name: "课程2", room: "A", teacher: "王", day: 1, startNode: 1, endNode: 1, startWeek: 5, endWeek: 5, credit: 0, note: "限选")]),
        Fixture(name: "cRouting_lngd", type: "lngd", source: "<div id='root'><div class='kbappTimetableDayColumnRoot___1DlDV'><div class='kbappTimetableCourseRenderCourseItem___MgPtp'><div class='title___3o2RH'>课程2 2.5学分</div><div class='kbappTimetableCourseRenderCourseItemInfoText___2Zmwu'>5周王 第1节-第1节 A</div></div></div></div>", expected: [JwCourse(name: "课程2", room: "A", teacher: "王", day: 1, startNode: 1, endNode: 1, startWeek: 5, endWeek: 5, credit: 2.5, note: "")]),
        Fixture(name: "cRouting_vatuu", type: "vatuu", source: "<table class='table_border'><tr><td>节</td><td>星期一</td></tr><tr><td>1</td><td>课程2(王)<br>5周<br>A<br></td></tr></table>", expected: [JwCourse(name: "课程2", room: "A", teacher: "王", day: 1, startNode: 1, endNode: 1, startWeek: 5, endWeek: 5, credit: 0, note: "")]),
        Fixture(name: "cRouting_yzzy", type: "yzzy", source: "<table id='timetable'><tr><td>标题</td></tr><tr><td><div class='kbcontent'><font onmouseover='kbtc(this);'>课程2</font><font title='周次(节次)'>5(周)</font><font title='教室'>A</font><font title='教师'>王</font></div></td></tr></table>", expected: [JwCourse(name: "课程2", room: "A", teacher: "王", day: 1, startNode: 1, endNode: 1, startWeek: 5, endWeek: 5, credit: 0, note: "")]),
    ]
    func testFixedAndroidVectorsThroughDeclaredSelectionAndDraft() throws {
        for fixture in Self.fixtures {
            let direct = try JwParserRegistry.parserFor(fixture.type, fixture.source).generateCourseList()
            XCTAssertEqual(direct, fixture.expected, fixture.name)
            XCTAssertEqual(JwParserRegistry.selectBest(fixture.source, declaredType: fixture.type).0, fixture.expected, fixture.name)
            let draft = JwImportDraftSnapshot(school: JwSchoolInfo(sortKey: "T", name: "fixture", type: fixture.type), courses: direct, periods: [])
            XCTAssertEqual(JwImportDraftCodec.fromJson(JwImportDraftCodec.toJson(draft))?.courses, fixture.expected, fixture.name)
        }
    }
    func testShuTermNameComesFromSemesterControl() {
        let source = #"<title>错误标题</title><a class="gologin-btn"><span class="el-link--inner">2026-2027学年秋季学期</span></a>"#
        XCTAssertEqual(JwUndergradBHtmlParser(source, protocolType: "shu2024").tableName(), "26-27秋")
    }
    private func assertDeclared(_ type: String, _ source: String, _ expected: [JwCourse],
                                file: StaticString = #filePath, line: UInt = #line) throws {
        let direct = try JwParserRegistry.parserFor(type, source).generateCourseList()
        XCTAssertEqual(direct, expected, file: file, line: line)
        XCTAssertEqual(JwParserRegistry.selectBest(source, declaredType: type).0, expected, file: file, line: line)
    }

    private func jnuDocument(_ text: String) -> String {
        "<div id='oReportCell'><table class='a8'>" + String(repeating: "<tr><td>表头</td></tr>", count: 3)
        + "<tr><td>星期一</td><td><div>" + text + "</div></td></tr>"
        + String(repeating: "<tr><td></td></tr>", count: 6) + "</table></div>"
    }

    func testJnuDocumentChoiceAndMalformedWeekBoundsMatchFixedAndroid() throws {
        let fragment = jnuDocument("课程：离散数学(理论) 从第2至10 双周 A")
        let expected = [JwCourse(name: "离散数学", room: "A", day: 1, startNode: 1, endNode: 1,
                                 startWeek: 2, endWeek: 10, type: 2)]
        for source in [fragment, "<html><body>" + fragment + "</body></html>"] {
            try assertDeclared("jnu", source, expected)
        }
        let page = "<html><body>" + fragment + "</body></html>"
        try assertDeclared("jnu", page + "<html><body>请重新登录</body></html>", [])
        try assertDeclared("jnu", page + page + page, [])
        for text in ["课程：数学(理论) 从第10至2 A 尾注", "课程：数学(理论) 从第0至8 A 尾注",
                     "课程：数学(理论) 从第1至367 A 尾注", "课程：数学(理论) 从第999999999999999999至8 A 尾注",
                     "课程：数学(理论) 从第未知至8 A 尾注", "教室开放时间(理论) A 尾注"] {
            try assertDeclared("jnu", jnuDocument(text), [])
        }
        try assertDeclared("jnu", jnuDocument("课程：数学(理论) 从第2至10 A101 尾注"),
            [JwCourse(name: "数学", room: "A101", day: 1, startNode: 1, endNode: 1, startWeek: 2, endWeek: 10)])
    }

    func testJavtcPreservesTitleNewlinesAndSparseWeeks() throws {
        let title = "编号\n代码\n课程名称：离散数学\n授课教师：王老师\n班级\n上课周次：1-4,6\n开课地点：A\n备注"
        let source = "<table border='1' width='98%'><tr><th>课表</th></tr><tr><td>第三四节</td><td><a title='" + title
            + "'>课程</a></td>" + String(repeating: "<td></td>", count: 6) + "</tr></table>"
        try assertDeclared("javtc", source, [
            JwCourse(name: "离散数学", room: "A", teacher: "王老师", day: 1, startNode: 3, endNode: 4, startWeek: 1, endWeek: 4),
            JwCourse(name: "离散数学", room: "A", teacher: "王老师", day: 1, startNode: 3, endNode: 4, startWeek: 6, endWeek: 6)])
    }

    private func ygu(_ nodes: String, _ weeks: String, parity: String = "", room: String = "文科楼201",
                     day: Int = 7, name: String = "医学", mixed: Bool = false) throws -> String {
        let records: [Any] = (mixed ? [NSNull(), 5] : []) + [["xq": day, "jcs": nodes, "zcs": weeks,
            "dsz": parity, "kcmc": name, "rkls": "王老师", "jsmc": room]]
        let weeks: [Any] = (mixed ? [NSNull()] : []) + [["kcbVoList": records]]
        let data: [Any] = (mixed ? [NSNull()] : []) + [["weekList": weeks]]
        return String(data: try JSONSerialization.data(withJSONObject: ["data": data]), encoding: .utf8)!
    }

    func testYguBuildingClocksSparseWeekNodesAndNullSiblings() throws {
        for building in ["文科楼", "商学楼", "音艺楼", "行政楼", "操场", "理科楼"] {
            try assertDeclared("ygu", ygu("3,4", "1-8", room: building + " 201", mixed: true), [
                JwCourse(name: "医学", room: building + "201", teacher: "王老师", day: 7,
                    startNode: 3, endNode: 4, startWeek: 1, endWeek: 8,
                    startTime: building == "理科楼" ? "10:20" : "10:05", endTime: building == "理科楼" ? "12:00" : "11:40")])
        }
        var expected: [JwCourse] = []
        for node in [3, 5] { for week in [1, 3, 7] {
            expected.append(JwCourse(name: "医学", room: "文科楼201", teacher: "王老师", day: 7,
                startNode: node, endNode: node, startWeek: week, endWeek: week, type: 1,
                startTime: node == 3 ? "10:05" : "14:00", endTime: node == 3 ? "10:50" : "14:45"))
        } }
        try assertDeclared("ygu", ygu("3,5", "1,3,7", parity: "单"), expected)
        for source in [try ygu("12", "1-8"), try ygu("0", "1-8"), try ygu("4-3", "1-8"),
                       try ygu("3", "8-1"), try ygu("3", "0,8"), try ygu("3", "367"),
                       try ygu("3", "1-8", day: 8), try ygu("3", "1-8", parity: "未知"),
                       try ygu("3", "1-8", name: ""), try ygu("3", ""), "{}", "not json"] {
            try assertDeclared("ygu", source, [])
        }
    }

}
