// JwParseDiagnosticsTests.swift — ← JwParseDiagnosticsTest.kt (v1.0.61)
//
// T9 诊断分类单测 — 九个用例逐一对应 Android 侧 JwParseDiagnosticsTest:
//   1. zf_new 会话过期页            → SESSION_EXPIRED (+登录提示文案/隐私断言)
//   2. 强智 Logon.do 登录页          → SESSION_EXPIRED + "logon" 特征
//   3. 空白页无课表容器              → NO_TABLE_CONTAINER + "no_container"
//   4. 老正方图片课表                → IMAGE_OR_EMPTY_CELLS + "img_in_table"
//   5. "尚未产生课表数据" 声明页      → EMPTY_SEMESTER
//   6. 容器在但无逐节行头(内联 HTML)  → HEADER_NO_NODE
//   7. 北大 datagrid 选课页          → 命中 datagrid 且 category != WRONG_PROTOCOL
//   8. qz 学校看到 zf Table1 容器    → WRONG_PROTOCOL (文案含"不一致/切换")
//   9. 全 fixture userMessage 敏感数据横扫(隐私硬约束)
//
// Fixture 源: app/src/test/resources/jw_fixtures/ 已整树复制到本 target 的
// SleepyTests/resources/jw_fixtures/, 由 project.yml 以 buildPhase: resources
// 打包。加载器对"保留 resources/ 前缀 / 去前缀 / 拍平"三种 bundle 布局都兜底,
// 与 JwChaoxingParserTests / JwQzIeasParserTests 现有惯例一致。

import XCTest
@testable import Sleepy

final class JwParseDiagnosticsTests: XCTestCase {

    // MARK: - 测试学校

    private let linyi = JwSchoolInfo(sortKey: "L", name: "临沂大学",
                                     url: "http://jwgl.lyu.edu.cn/jwglxt",
                                     type: JwProtocol.TYPE_ZF_NEW,
                                     sortKeyFull: "linyidaxue")
    private let schoolQz = JwSchoolInfo(sortKey: "H", name: "哈工程",
                                        url: "http://jw.hrbeu.edu.cn/jsxsd/",
                                        type: JwProtocol.TYPE_QZ_CRAZY,
                                        sortKeyFull: "haerbin")
    private let pku = JwSchoolInfo(sortKey: "B", name: "北京大学",
                                   url: "https://elective.pku.edu.cn",
                                   type: JwProtocol.TYPE_PKU,
                                   sortKeyFull: "beida")
    private let bnuz = JwSchoolInfo(sortKey: "B", name: "北师珠",
                                    url: "http://es.bnuz.edu.cn",
                                    type: JwProtocol.TYPE_BNUZ,
                                    sortKeyFull: "beishizhu")

    // MARK: - Fixture 加载

    /// 从测试 bundle 读取 jw_fixtures 树下的 fixture。
    /// group 为相对 jw_fixtures/ 的路径 (如 "adversarial/image-table")。
    private func fixture(_ group: String, _ name: String) throws -> String {
        let bundle = Bundle(for: JwParseDiagnosticsTests.self)
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        let subdir = "jw_fixtures/\(group)"
        let url = bundle.url(forResource: base, withExtension: ext,
                             subdirectory: "resources/" + subdir)
            ?? bundle.url(forResource: base, withExtension: ext,
                          subdirectory: subdir)
            ?? bundle.url(forResource: base, withExtension: ext)
        guard let url else {
            XCTFail("测试资源 \(subdir)/\(name) 应存在于 SleepyTests/resources")
            throw NSError(domain: "JwParseDiagnosticsTests", code: 1)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func advFixture(_ group: String, _ name: String) throws -> String {
        try fixture("adversarial/\(group)", name)
    }

    private func detectionFixture(_ name: String) throws -> String {
        try fixture("detection-pages", name)
    }

    // MARK: - 1. 会话过期 (zf_new fetch 过期返回登录页)

    func testZfNewExpiredReturnsLoginPageDetectedAsSessionExpired() throws {
        let html = try advFixture("login-expired", "zf_new_fetch_expired_returns_login.html")
        let diag = JwParseDiagnostics.classify(html, "https://jw.example.edu.cn/jwglxt/",
                                               linyi, [])
        XCTAssertEqual(diag.category, .sessionExpired, "会话过期页应判为 SESSION_EXPIRED")
        XCTAssertEqual(diag.courseCount, 0, "0 课")
        XCTAssertTrue(diag.matchedFeatures.contains {
            ["login_slogin", "登录", "captcha", "viewstate"].contains($0)
        }, "应命中登录页指纹: \(diag.matchedFeatures)")
        XCTAssertFalse(diag.userMessage.lowercased().contains("jsessionid"),
                       "userMessage 不得含学号/cookie")
        XCTAssertFalse(diag.userMessage.lowercased().contains("<html"),
                       "userMessage 不得含完整 HTML")
        XCTAssertTrue(diag.userMessage.contains("登录") || diag.userMessage.contains("会话"),
                      "userMessage 应给出登录提示: \(diag.userMessage)")
    }

    // MARK: - 2. 强智 Logon.do 登录页

    func testQzLogonLoginPageClassifiedAsSessionExpired() throws {
        let html = try advFixture("login-expired", "qz_sdust_logon_login.html")
        let diag = JwParseDiagnostics.classify(html, "http://jwgl.sdust.edu.cn/",
                                               schoolQz, [])
        XCTAssertEqual(diag.category, .sessionExpired)
        XCTAssertTrue(diag.matchedFeatures.contains("logon"),
                      "logon 路径应被命中: \(diag.matchedFeatures)")
    }

    // MARK: - 3. 无课表容器

    func testBlankHtmlNoTableContainerClassified() throws {
        let html = try advFixture("image-table", "blank_no_table.html")
        let diag = JwParseDiagnostics.classify(html, "https://jw.example.edu.cn/",
                                               linyi, [])
        XCTAssertEqual(diag.category, .noTableContainer,
                       "无任何容器 → NO_TABLE_CONTAINER")
        XCTAssertTrue(diag.matchedFeatures.contains("no_container"),
                      "matchedFeatures 应含 no_container: \(diag.matchedFeatures)")
    }

    // MARK: - 4. 图片课表

    func testImageCellZfTableClassifiedAsImageOrEmptyCells() throws {
        let html = try advFixture("image-table", "zf_image_cell.html")
        let diag = JwParseDiagnostics.classify(html, "https://jw.example.edu.cn/xskbcx.aspx",
                                               linyi, [])
        XCTAssertEqual(diag.category, .imageOrEmptyCells,
                       "图片课表应判 IMAGE_OR_EMPTY_CELLS")
        XCTAssertTrue(diag.matchedFeatures.contains("img_in_table"),
                      "应含 img_in_table 标签: \(diag.matchedFeatures)")
    }

    // MARK: - 5. 可信空学期

    func testEmptySemesterMarkerClassifiedAsEmptySemester() throws {
        let html = try advFixture("empty-semester", "unknown_protocol_all_parsers_empty.html")
        let diag = JwParseDiagnostics.classify(html, "https://jw.example.edu.cn/",
                                               linyi, [])
        XCTAssertEqual(diag.category, .emptySemester,
                       "含'尚未产生课表数据'应判 EMPTY_SEMESTER")
    }

    // MARK: - 6. 有容器无逐节行头

    func testHeaderWithoutPerRowNodeClassifiedAsHeaderNoNode() {
        // 构造: 容器在(Table1)但无任何 "第N节" 行头, 无 img, 无空课声明
        let html = #"<!DOCTYPE html><html><body><table id="Table1"><tr><td>课程</td></tr></table></body></html>"#
        let diag = JwParseDiagnostics.classify(html, "https://jw.example.edu.cn/xskbcx.aspx",
                                               linyi, [])
        XCTAssertEqual(diag.category, .headerNoNode,
                       "容器在但无行头 → HEADER_NO_NODE")
    }

    // MARK: - 7. 北大 datagrid

    func testPkuElectiveDatagridClassifiedCorrectlyForPkuSchool() throws {
        let html = try detectionFixture("pku-elective-datagrid.html")
        let diag = JwParseDiagnostics.classify(html, "https://elective.pku.edu.cn/",
                                               pku, [])
        XCTAssertTrue(diag.matchedFeatures.contains("datagrid"),
                      "PKU datagrid 容器命中: \(diag.matchedFeatures)")
        XCTAssertNotEqual(diag.category, .wrongProtocol,
                          "PKU 学校不应判 WRONG_PROTOCOL")
    }

    // MARK: - 8. 协议不匹配

    func testWrongProtocolDetectedWhenQzSchoolSeesTable1() throws {
        // 学校标 qz, 页面有 Table1 (zf) 而无 kbtable → WRONG_PROTOCOL
        let html = try advFixture("cross-fp-parsers", "zf_old_table1_into_newzf.html")
        let diag = JwParseDiagnostics.classify(html, "https://jw.example.edu.cn/xskbcx.aspx",
                                               schoolQz, [])
        XCTAssertEqual(diag.category, .wrongProtocol,
                       "qz 学校看到 zf 容器 → WRONG_PROTOCOL")
        XCTAssertTrue(diag.userMessage.contains("不一致") || diag.userMessage.contains("切换"),
                      "userMessage 应提及协议不一致: \(diag.userMessage)")
    }

    // MARK: - 9. 隐私硬约束横扫

    /// 文件头注释的硬约束"绝不把 Cookie/token/HTML 写入 userMessage"的可执行锁。
    func testUserMessageNeverContainsSensitiveDataAcrossAllFixtures() throws {
        let cases: [(html: String, school: JwSchoolInfo)] = [
            (try advFixture("login-expired", "wisedu_cas_login_expired.html"), linyi),
            (try advFixture("login-expired", "bnuz_es_default_login.html"), bnuz),
            (try advFixture("login-expired", "pku_iaaa_login_redirect.html"), pku),
            (try advFixture("image-table", "qz_image_cell.html"), schoolQz),
        ]
        let sensitivePatterns = [
            "(?i)(sessionid|csrf|token|cookie)",
            "(?i)<html|<body|<script",
            "(?i)password",
        ].map { try! NSRegularExpression(pattern: $0) }
        for (html, school) in cases {
            let diag = JwParseDiagnostics.classify(html, school.url, school, [])
            for p in sensitivePatterns {
                XCTAssertFalse(p.firstMatch(in: diag.userMessage,
                                            range: NSRange(diag.userMessage.startIndex...,
                                                           in: diag.userMessage)) != nil,
                               "[\(school.name)] userMessage 不应含敏感数据: \(diag.userMessage.prefix(50))")
            }
        }
    }
}
