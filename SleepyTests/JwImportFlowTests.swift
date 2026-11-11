import XCTest
@testable import Sleepy

/// F080 (JwImportFlow v1.0.61 对齐) 纯逻辑回归锁。
///
/// 锁 DiagMapper 的 UNKNOWN_EMPTY 网络提示尾(F080 issue #15):
/// 原 mapImpl 对 UNKNOWN_EMPTY 返回 "$base（features）$hintPart" —
/// 校园网限制主机(v1.0.46+ 24 校)与强智系协议在 unknownEmpty 分类下也必须
/// 保留 jw_diag_campus_vpn_hint / jw_diag_qz_vpn_hint 尾; iOS 旧实现提前
/// `return base` 把尾丢了。JwImportActivityDiagnosticsTest(原版本) 同源语义。
final class JwImportFlowTests: XCTestCase {

    private let linyi = JwSchoolInfo(sortKey: "L", name: "临沂大学",
                                     url: "http://jwgl.lyu.edu.cn/jwglxt",
                                     type: JwProtocol.TYPE_ZF_NEW, sortKeyFull: "linyi")
    private let sdust = JwSchoolInfo(sortKey: "S", name: "山东科技",
                                     url: "http://jwgl.sdust.edu.cn",
                                     type: JwProtocol.TYPE_QZ, sortKeyFull: "shandongkeji")
    private let pku = JwSchoolInfo(sortKey: "B", name: "北京大学",
                                   url: "https://elective.pku.edu.cn",
                                   type: JwProtocol.TYPE_PKU, sortKeyFull: "beida")

    private func diag(_ cat: JwParseDiagnostics.Category,
                      features: [String] = ["kbtable", "img_in_table", "vpn"]) -> JwParseDiagnostics.Result {
        JwParseDiagnostics.Result(category: cat, attempts: [], matchedFeatures: features,
                                  courseCount: 0, userMessage: "")
    }

    /// UNKNOWN_EMPTY + 校园网限制主机 → 特征回显 + 校园网/VPN 提示尾都在。
    func testUnknownEmptyKeepsCampusVpnHint() {
        let msg = DiagMapper.map(diag(.unknownEmpty), linyi)
        XCTAssertTrue(msg.contains("kbtable") || msg.contains("img_in_table"),
                      "UNKNOWN_EMPTY 应回显诊断特征: \(msg)")
        XCTAssertTrue(msg.contains("校园网") || msg.contains("VPN"),
                      "UNKNOWN_EMPTY 不得吞掉校园网提示尾(issue#15 回归): \(msg)")
    }

    /// UNKNOWN_EMPTY + 强智系协议 → 强智专属提示尾在。
    func testUnknownEmptyKeepsQzHint() {
        let msg = DiagMapper.map(diag(.unknownEmpty), sdust)
        XCTAssertTrue(msg.contains("强智") || msg.contains("重新登录"),
                      "强智校 UNKNOWN_EMPTY 应含强智提示尾: \(msg)")
    }

    /// UNKNOWN_EMPTY + 普通校 → 只有 base, 无提示尾。
    func testUnknownEmptyGenericSchoolHasNoHintTail() {
        let msg = DiagMapper.map(diag(.unknownEmpty), pku)
        XCTAssertTrue(msg.contains("kbtable"), "特征仍应回显: \(msg)")
        XCTAssertFalse(msg.contains("校园网"), "北大不应触发校园网提示: \(msg)")
        XCTAssertFalse(msg.contains("强智"), "北大不应触发强智提示: \(msg)")
    }

    /// 提示尾格式与原实现一致: base + "\n\n" + hint(双换行分隔, 非拼接同段)。
    func testHintTailSeparatedByDoubleNewline() {
        let msg = DiagMapper.map(diag(.unknownEmpty), linyi)
        XCTAssertTrue(msg.contains("\n\n"), "提示尾应以空行分隔(hintPart = \"\\n\\n$schoolHint\"): \(msg)")
    }

    /// v1.0.61 新收录的受限主机(矿大北京/石河子/广州医科)在 unknownEmpty 与
    /// 其他分类下同样获得校园网提示 — 锁清单不因分类分叉。
    func testNewCampusHostsCoveredInUnknownEmpty() {
        for host in ["jwxt.cumtb.edu.cn", "jwgl.shzu.edu.cn", "jwgl.gzhmu.edu.cn"] {
            let school = JwSchoolInfo(sortKey: "T", name: "测试校", url: "http://\(host)/x",
                                      type: JwProtocol.TYPE_ZF_NEW, sortKeyFull: "test")
            let msg = DiagMapper.map(diag(.unknownEmpty), school)
            XCTAssertTrue(msg.contains("校园网") || msg.contains("VPN"),
                          "\(host) UNKNOWN_EMPTY 应含校园网提示尾: \(msg)")
        }
    }
}

final class JwImportParserWarningTests: XCTestCase {
    private func thuFixture() throws -> String {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(bundle.url(forResource: "thu_courses.sample", withExtension: "html")
            ?? bundle.url(forResource: "thu_courses.sample", withExtension: "html", subdirectory: "resources"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testPartialThuImportSurfacesTheExistingSkippedDiagnostic() throws {
        let html = try thuFixture().replacingOccurrences(of: "；前八周", with: "；待定周次")
        let result = JwParseDispatch.parse(html, JwProtocol.TYPE_THU)
        XCTAssertNil(result.error)
        XCTAssertEqual(result.courses.count, 4)
        XCTAssertEqual(JwImportParserWarnings.messages(protocolType: JwProtocol.TYPE_THU, attempts: result.attempts),
                       [L10n.format("jw_thu_skipped_courses", 1)])
    }

    func testCompleteThuImportDoesNotShowASkippedWarning() throws {
        let result = JwParseDispatch.parse(try thuFixture(), JwProtocol.TYPE_THU)
        XCTAssertEqual(result.courses.count, 5)
        XCTAssertTrue(JwImportParserWarnings.messages(protocolType: JwProtocol.TYPE_THU, attempts: result.attempts).isEmpty)
    }

    func testAllUnsupportedThuEntriesShowTheSkippedCountInsteadOfGenericEmptyDiagnosis() throws {
        var html = try thuFixture()
        for weeks in ["；前八周", "；全周", "；单周", "；双周", "；第3-15周（单）"] {
            html = html.replacingOccurrences(of: weeks, with: "；待定周次")
        }
        let result = JwParseDispatch.parse(html, JwProtocol.TYPE_THU)
        XCTAssertNil(result.error)
        XCTAssertTrue(result.courses.isEmpty)
        let school = JwSchoolInfo(sortKey: "Q", name: "清华大学",
                                 url: "https://zhjwxk.cic.tsinghua.edu.cn",
                                 type: JwProtocol.TYPE_THU, sortKeyFull: "qinghua")
        XCTAssertEqual(JwImportParserWarnings.emptyResultMessage(
            html: html, school: school, protocolType: JwProtocol.TYPE_THU, attempts: result.attempts),
            L10n.format("jw_thu_skipped_courses", 5))
        XCTAssertEqual(JwImportParserWarnings.emptyResultMessage(
            html: html, school: school, protocolType: JwProtocol.TYPE_THU, attempts: []),
            DiagMapper.diagnosis(html: html, school: school, attempts: []))
    }

    func testWarningRequiresTheThuProtocolAndAPositiveDiagnosticCount() {
        func attempt(type: String? = JwProtocol.TYPE_THU, count: String) -> ParserAttemptSnapshot {
            ParserAttemptSnapshot(parserName: "THU", type: type, courseCount: 1, confidence: 100,
                                  matchedFeatures: ["thu:skipped-unsupported=\(count)"], exception: nil)
        }
        for count in ["0", "-1", "unknown"] {
            XCTAssertTrue(JwImportParserWarnings.messages(protocolType: JwProtocol.TYPE_THU,
                attempts: [attempt(count: count)]).isEmpty)
        }
        XCTAssertTrue(JwImportParserWarnings.messages(protocolType: JwProtocol.TYPE_UCAS,
            attempts: [attempt(count: "2")]).isEmpty)
        XCTAssertTrue(JwImportParserWarnings.messages(protocolType: JwProtocol.TYPE_THU,
            attempts: [attempt(type: JwProtocol.TYPE_UCAS, count: "2")]).isEmpty)
    }

    func testAllFiveSkippedWarningTranslationsMatchAndroid1064() throws {
        let expected = [
            "zh-Hans": "有 %1$d 条清华课程安排因信息不完整或周次、时段格式不受支持而跳过。请核对教务课表并手动补录。",
            "zh-Hant": "有 %1$d 條清華課程安排因資訊不完整或週次、時段格式不支援而略過。請核對教務課表並手動補錄。",
            "en": "%1$d THU course entries were skipped because details were incomplete or the weeks or times are unsupported. Check the official timetable and add them manually.",
            "ja": "THUの授業予定%1$d件は情報不足、または週・時間帯の形式に対応できず除外されました。教務システムの時間割を確認し、手動で追加してください。",
            "es": "Se omitieron %1$d entradas de cursos de THU por datos incompletos o semanas u horarios no compatibles. Compruebe el horario oficial y añádalas manualmente."
        ]
        for (language, text) in expected {
            let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"))
            let bundle = try XCTUnwrap(Bundle(path: path))
            XCTAssertEqual(NSLocalizedString("jw_thu_skipped_courses", bundle: bundle, comment: ""), text)
        }
    }
}
