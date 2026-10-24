// JwImportViewModelTests.swift — F018 对齐回归测试
// ← JwProtocolDetectionUnitTest.kt / JwImportViewModel 相关的纯逻辑断言(检测链新锚点 +
//   parseZfNewBridgeResult 默认值 + normalizeStartDate 归一周四), iOS 侧无对应 Android
//   单测文件直接镜像, 按本项目 drift-fix 规则补齐行为断言。

import XCTest
@testable import Sleepy

final class JwImportViewModelTests: XCTestCase {

    // MARK: - URL 判型新锚点(← JwImportViewModel.kt:350-351, 374-375, 383, 389-390, 407, 411, 457-458)

    func testDetectUrlNuitAndKustAtChainHead() {
        XCTAssertEqual(JwImportViewModel.detectProtocolFromUrl("https://jw.nuit.edu.cn/jwapp/sys/x"),
                       JwProtocol.TYPE_NUIT)
        XCTAssertEqual(JwImportViewModel.detectProtocolFromUrl("https://i.kust.edu.cn/jwapp/sys/x"),
                       JwProtocol.TYPE_KUST)
        XCTAssertEqual(JwImportViewModel.detectProtocolFromUrl("https://www.kmust.edu.cn/jwapp/sys/x"),
                       JwProtocol.TYPE_KUST)
    }

    func testDetectUrlNuitAndKustInsideWebVpnSubChain() {
        XCTAssertEqual(JwImportViewModel.detectProtocolFromUrl(
            "https://vpn.nuit.edu.cn/webvpn/https://jw.nuit.edu.cn/jwapp/sys/x"),
            JwProtocol.TYPE_NUIT)
        XCTAssertEqual(JwImportViewModel.detectProtocolFromUrl(
            "https://proxy/webvpn/https://i.kust.edu.cn/jwapp/sys/x"),
            JwProtocol.TYPE_KUST)
    }

    func testDetectUrlBuaaByxtRoutesToNeuBeforeJwapp() {
        // 必须先于通用 /jwapp/ — 否则被吸进 TYPE_WISEDU(必空课表, kt:376-382)
        XCTAssertEqual(JwImportViewModel.detectProtocolFromUrl(
            "https://byxt.buaa.edu.cn/jwapp/sys/homeapp/api/home/student/getMyScheduleDetail.do"),
            JwProtocol.TYPE_NEU)
        // 旧 jwxt.buaa 强智 iEAS 分支不受影响
        XCTAssertEqual(JwImportViewModel.detectProtocolFromUrl("https://jwxt.buaa.edu.cn/ieas2.1/x"),
                       JwProtocol.TYPE_QZ_IEAS)
    }

    func testDetectUrlClassicEams() {
        XCTAssertEqual(JwImportViewModel.detectProtocolFromUrl("https://x/CourseTableForStd"),
                       JwProtocol.TYPE_CLASSIC_EAMS)
        XCTAssertEqual(JwImportViewModel.detectProtocolFromUrl("https://x/edu/lesson/std/timetable"),
                       JwProtocol.TYPE_CLASSIC_EAMS)
    }

    func testDetectUrlYethanHost() {
        XCTAssertEqual(JwImportViewModel.detectProtocolFromUrl("https://yhxt.swjtu.edu.cn/"),
                       JwProtocol.TYPE_YETHAN)
        XCTAssertEqual(JwImportViewModel.detectProtocolFromUrl("http://yhxt.swjtu.edu.cn/a/b"),
                       JwProtocol.TYPE_YETHAN)
        XCTAssertNil(JwImportViewModel.detectProtocolFromUrl("https://yhxt.swjtu.edu.cnx/"))
    }

    func testDetectUrlXjuPostHost() {
        XCTAssertEqual(JwImportViewModel.detectProtocolFromUrl("https://yjspy.xju.edu.cn/"),
                       JwProtocol.TYPE_XJU_POST)
        // 本科教务等其余子域不误判
        XCTAssertNil(JwImportViewModel.detectProtocolFromUrl("https://jwgl.xju.edu.cn/"))
    }

    func testDetectUrlCfNewBeforeCf() {
        XCTAssertEqual(JwImportViewModel.detectProtocolFromUrl("https://x/new/student/xsgrkb"),
                       JwProtocol.TYPE_CF_NEW)
    }

    // MARK: - HTML 判型新指纹(← kt:525-526, 540-542)

    func testDetectHtmlNuitKustFingerprints() {
        XCTAssertEqual(JwImportViewModel.detectProtocolFromHtml("<html>classDateAndPlace()</html>"),
                       JwProtocol.TYPE_NUIT)
        XCTAssertEqual(JwImportViewModel.detectProtocolFromHtml("<html>queryAWeekSchedule</html>"),
                       JwProtocol.TYPE_KUST)
        XCTAssertEqual(JwImportViewModel.detectProtocolFromHtml("<html>resultsJsonArr</html>"),
                       JwProtocol.TYPE_KUST)
    }

    func testDetectHtmlCfNewBeforeCfKeywords() {
        // NTSS 页脚同含"乘方"字样时, CF_NEW 路径锚点必须赢(kt 分支顺序)
        let html = "<html>getCalendarWeekDatas 乘方教务</html>"
        XCTAssertEqual(JwImportViewModel.detectProtocolFromHtml(html), JwProtocol.TYPE_CF_NEW)
        XCTAssertEqual(JwImportViewModel.detectProtocolFromHtml("<html>ntsscalendar</html>"),
                       JwProtocol.TYPE_CF_NEW)
    }

    func testDetectProtocolHitFeaturesIncludesCfNewLabels() {
        let hits = JwImportViewModel.detectProtocolHitFeatures(
            "<html>/new/student/xsgrkb getCalendarWeekDatas ntsscalendar</html>")
        XCTAssertTrue(hits.contains("/new/student/xsgrkb"))
        XCTAssertTrue(hits.contains("getCalendarWeekDatas"))
        XCTAssertTrue(hits.contains("ntsscalendar"))
    }

    // MARK: - parseZfNewBridgeResult 默认值(← kt:245 optString("format",""))

    func testParseZfNewBridgeResultMissingFormatKeyIsOther() {
        // {ok:true, data:...} 无 format 键 → Android 判 OTHER; iOS 曾默认 "zf_new" 误判成功
        let r = JwImportViewModel.parseZfNewBridgeResult(#"{"ok":true,"data":"[1,2]"}"#)
        XCTAssertFalse(r.ok)
        XCTAssertEqual(r.kind, "OTHER")
        XCTAssertEqual(r.payload, "")
    }

    func testParseZfNewBridgeResultFormatZfNewBlankData() {
        let ok = JwImportViewModel.parseZfNewBridgeResult(#"{"ok":true,"format":"zf_new","data":"[]"}"#)
        XCTAssertTrue(ok.ok)
        let blank = JwImportViewModel.parseZfNewBridgeResult(#"{"ok":true,"format":"zf_new","data":"   "}"#)
        XCTAssertFalse(blank.ok)
        XCTAssertEqual(blank.kind, "FORMAT_ERROR")
    }

    // MARK: - normalizeStartDate(← DateUtils.kt:60-65)

    func testNormalizeStartDateSnapsToMonday() {
        XCTAssertEqual(JwImportViewModel.normalizeStartDate("2026-09-01"), "2026-08-31")  // 周二→上周一
        XCTAssertEqual(JwImportViewModel.normalizeStartDate("2026-09-06"), "2026-08-31")  // 周日→同周周一
        XCTAssertEqual(JwImportViewModel.normalizeStartDate("2026-09-07"), "2026-09-07")  // 周一不动
    }

    func testNormalizeStartDatePassthroughOnParseFailure() {
        // "解析失败原样返回"(kt catch → 原文), 含非法日期/欠宽格式
        XCTAssertEqual(JwImportViewModel.normalizeStartDate("2026-13-45"), "2026-13-45")
        XCTAssertEqual(JwImportViewModel.normalizeStartDate("2026-9-1"), "2026-9-1")
        XCTAssertEqual(JwImportViewModel.normalizeStartDate("not-a-date"), "not-a-date")
    }

    // MARK: - 文案/空白检查(← kt:672/643/681/687/106/144/159)

    func testImportAsNewTableEmptyCoursesFullWidthComma() throws {
        // 测试库走 inMemory(G4 链条测试同款), 绝不碰 getShared 的真实 App Group 库
        let db = try AppDatabase.inMemory()
        XCTAssertThrowsError(try JwImportViewModel.importAsNewTable(
            db, courses: [], tableName: "x")) { error in
            let msg = (error as NSError).userInfo[NSLocalizedDescriptionKey] as? String ?? ""
            XCTAssertEqual(msg, "课程列表为空，请确认已到达课表页面")  // 全角逗号
        }
    }

    func testToCourseEntitiesBlankNameDefaultsUnnamed() {
        // ← kt ifBlank: 纯空白课程名也回退"未命名"
        let jw = JwCourse(name: "   ", room: "", teacher: "", day: 1,
                          startNode: 1, endNode: 2, startWeek: 1, endWeek: 16)
        let entities = JwImportViewModel.toCourseEntities([jw], tableId: 1, defaultColor: "#FF000000")
        XCTAssertEqual(entities.first?.courseName, "未命名")
    }
}
