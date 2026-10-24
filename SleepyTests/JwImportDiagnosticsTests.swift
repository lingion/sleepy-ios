import XCTest
@testable import Sleepy

/// T9 诊断接线测试 —— 移植 Android JwImportActivityDiagnosticsTest。
///
/// iOS 侧 JwParseDiagnostics.classify 长期零调用方 (0 课一律吐 jw_parse_empty),
/// 本组测试锁住两件事: ①DiagMapper 分类→文案映射与 Android 同义;
/// ②0 课路径真的走 classify (会话过期页不再被误报成"本学期无课")。
final class JwImportDiagnosticsTests: XCTestCase {

    private let linyi = JwSchoolInfo(sortKey: "L", name: "临沂大学",
                                     url: "http://jwgl.lyu.edu.cn/jwglxt",
                                     type: JwProtocol.TYPE_ZF_NEW, sortKeyFull: "linyi")
    private let pku = JwSchoolInfo(sortKey: "B", name: "北京大学",
                                   url: "https://elective.pku.edu.cn",
                                   type: JwProtocol.TYPE_PKU, sortKeyFull: "beida")
    private let sdust = JwSchoolInfo(sortKey: "S", name: "山东科技",
                                     url: "http://jwgl.sdust.edu.cn",
                                     type: JwProtocol.TYPE_QZ, sortKeyFull: "shandongkeji")

    private func diag(_ cat: JwParseDiagnostics.Category,
                      features: [String] = ["test"]) -> JwParseDiagnostics.Result {
        JwParseDiagnostics.Result(category: cat, attempts: [], matchedFeatures: features,
                                  courseCount: 0, userMessage: "")
    }

    // MARK: - 分类 → 文案映射

    func testLinyiSessionExpiredIncludesCampusVpnHint() {
        let msg = DiagMapper.map(diag(.sessionExpired), linyi)
        XCTAssertTrue(msg.contains("校园网") || msg.contains("VPN"), "临沂大学错误应含 VPN 提示: \(msg)")
        XCTAssertTrue(msg.contains("会话") || msg.contains("登录"), "应含会话语义: \(msg)")
    }

    func testQzSessionExpiredIncludesQzHint() {
        let msg = DiagMapper.map(diag(.sessionExpired), sdust)
        XCTAssertTrue(msg.contains("强智") || msg.contains("重新登录"), "强智错误应含强智专属提示: \(msg)")
    }

    func testGenericSchoolGetsNoVpnHint() {
        let msg = DiagMapper.map(diag(.noTableContainer), pku)
        XCTAssertFalse(msg.contains("临沂"), "北大不应触发临沂 VPN 提示: \(msg)")
        XCTAssertFalse(msg.contains("强智"), "北大不应触发强智提示: \(msg)")
    }

    func testUnknownEmptyEchoesDiagnosticFeatures() {
        let msg = DiagMapper.map(diag(.unknownEmpty, features: ["kbtable", "img_in_table", "vpn"]), linyi)
        XCTAssertTrue(msg.contains("kbtable") || msg.contains("img_in_table"),
                      "UNKNOWN_EMPTY 应回显诊断特征: \(msg)")
    }

    func testSixCategoriesProduceDistinctMessages() {
        let cats: [JwParseDiagnostics.Category] = [
            .sessionExpired, .noTableContainer, .headerNoNode,
            .imageOrEmptyCells, .emptySemester, .wrongProtocol,
        ]
        var seen = Set<String>()
        for cat in cats {
            let msg = DiagMapper.map(diag(cat), linyi)
            XCTAssertFalse(msg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(cat) 文案非空")
            XCTAssertTrue(seen.insert(msg).inserted, "\(cat) 文案互异")
        }
    }

    // MARK: - 0 课路径接线

    /// 会话过期页 (老正方 logout.aspx 硬指纹) 解析出 0 课时, 必须报"会话已过期",
    /// 而不是笼统的"本学期无课" —— 这正是 classify 接线前的错误指向。
    func testLoginPageHtmlDiagnosedAsSessionExpired() {
        let html = """
        <html><head><script>window.parent.location.href='logout.aspx'</script></head>\
        <body><form action="/jsxsd/xk/LoginToXk"><input name="verifycode"></form>\
        <div>用户登录</div></body></html>
        """
        let msg = DiagMapper.diagnosis(html: html, school: pku, attempts: [])
        XCTAssertTrue(msg.contains("会话") || msg.contains("登录"),
                      "登录页应诊断为会话过期: \(msg)")
        XCTAssertFalse(msg.contains("本学期暂无课程"), "不应误报空学期: \(msg)")
    }

    /// 空 HTML 不能喂给 classify (Swift 侧是非可捕获的 precondition)。
    func testBlankHtmlFallsBackWithoutCrashing() {
        let msg = DiagMapper.diagnosis(html: "   \n ", school: pku, attempts: [])
        XCTAssertEqual(msg, L10n.format("jw_err_empty_semester"))
    }

    /// attempt 快照要能进诊断结果 (parserName/异常名不丢, 供 UNKNOWN_EMPTY 回显)。
    func testAttemptsAreMappedIntoDiagResult() {
        let html = "<html><body><div id=\"kbtable\"></div></body></html>"
        let snapshot = ParserAttemptSnapshot(parserName: "JwQzParser(type=qz)", type: JwProtocol.TYPE_QZ,
                                             courseCount: 0, confidence: 0, matchedFeatures: [],
                                             exception: "JwParseError")
        let diag = JwParseDiagnostics.classify(html, "", pku, [snapshot.asDiag])
        XCTAssertEqual(diag.attempts.count, 1)
        XCTAssertEqual(diag.attempts.first?.parserName, "JwQzParser(type=qz)")
        XCTAssertEqual(diag.attempts.first?.exception, "JwParseError")
    }

    // MARK: - 解析分派 (JwParseDispatch) —— 0 课诊断的前置数据来源

    private let wiseduJson = #"{"datas":{"xskcb":{"rows":[{"KCM":"测试课","SKJS":"T","JASMC":"R","SKXQ":"2","KSJC":"1","JSJC":"2","SKZC":"11111111111111110000"}]}}}"#

    /// 空协议类型必须仍走"全候选裁决"兜底 —— 接线诊断时若误走工厂表会 0 课。
    func testEmptyProtocolStillFallsBackToAllCandidates() {
        let out = JwParseDispatch.parse(wiseduJson, "")
        XCTAssertNil(out.error)
        XCTAssertEqual(1, out.courses.count)
        XCTAssertEqual("测试课", out.courses.first?.name)
        XCTAssertFalse(out.attempts.isEmpty, "兜底路径也要产出 attempts 供诊断")
    }

    /// 声明协议解析失败 (parser 抛 JwParseError): error 文案 + attempts 快照都要交回调用方。
    /// ← Android 真值两面对照: JwQzParserNoTableTest 锁 qz 缺 #kbtable 抛
    ///   JwParseException 且 attempts[0].exception=NO_TABLE_CONTAINER_MARKER;
    ///   zf_new 缺表**不抛** (JwNewZfParser.parseHtmlTableFromQt 吸收为 0 课,
    ///   JwNewZfParser.kt:737-742) — zf_new 没有"错误带 attempts"路径可测,
    ///   原稿用 zf_new 断言 error 非空是对 Android 契约的误译, 改用 qz 协议触发真错误。
    func testDeclaredProtocolReportsAttemptsOnError() {
        let out = JwParseDispatch.parse("<html><body>无课表</body></html>", JwProtocol.TYPE_QZ)
        XCTAssertTrue(out.courses.isEmpty)
        XCTAssertFalse(out.attempts.isEmpty)
        XCTAssertNotNil(out.error)
        XCTAssertNotNil(out.attempts.first?.exception, "失败 attempt 要带异常名供诊断分类")
    }

    /// 协议不在工厂表: 不抛异常, 错误文案 + attempts 交回调用方。
    func testUnknownProtocolTypeYieldsErrorNotCrash() {
        let out = JwParseDispatch.parse(wiseduJson, "no_such_protocol")
        XCTAssertTrue(out.courses.isEmpty)
        XCTAssertNotNil(out.error)
        XCTAssertEqual(1, out.attempts.count)
        XCTAssertEqual("JwParseError", out.attempts.first?.exception)
    }

    /// 分派结果能直接喂给诊断 (端到端: 0 课 → 分类文案, 不再是裸 jw_parse_empty)。
    func testDispatchOutcomeFeedsDiagnosis() {
        let out = JwParseDispatch.parse("<html><body>无课表</body></html>", JwProtocol.TYPE_ZF_NEW)
        let msg = DiagMapper.diagnosis(html: "<html><body>无课表</body></html>",
                                       school: linyi, attempts: out.attempts)
        XCTAssertFalse(msg.isEmpty)
        XCTAssertFalse(msg.contains("jw_parse_empty"), "不应再吐裸 key: \(msg)")
    }
}
