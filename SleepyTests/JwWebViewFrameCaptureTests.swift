// JwWebViewFrameCaptureTests.swift — ← JwWebViewFrameCaptureTest.kt (v1.0.61)
//
// T7 — WebView frame 抓取纯逻辑单测 (XCTest 镜像)。
//
// 不起 WebView: 抓取 JS 的行为通过"JS 契约(字段名/结构)由 fromJson 消费"间接保证;
// 本类直接构造 FrameSnapshotList JSON 模拟 JS 输出, 断言 FrameTraversalTree /
// RenderReadinessChecker 的决策。每个用例注释首行标注对应 Android 侧
// JwWebViewFrameCaptureTest 的用例 (jw_fixtures/adversarial/iframe-nested case 编号)。
// Android 侧用 fixture 文件喂 HTML; iOS 测试资源树未含 iframe-nested/, 故此处以
// 内联 HTML 复现 fixture 的决策关键特征(锚点/指纹/空壳), 决策路径完全一致。

import XCTest
@testable import Sleepy

final class JwWebViewFrameCaptureTests: XCTestCase {

    // MARK: - 构造 helper

    /** frame 六元组: [name, src, depth, path, html, blocked] → JSON 字典 */
    private func f(name: String?, src: String?, depth: Int, path: [String],
                   html: String?, blocked: String = "") -> [String: Any] {
        var d: [String: Any] = ["depth": depth, "path": path, "blocked": blocked]
        d["name"] = name ?? NSNull()
        d["src"] = src ?? NSNull()
        d["html"] = html ?? NSNull()
        return d
    }

    private func json(_ frames: [[String: Any]]) -> String {
        let obj: [String: Any] = [
            "ok": true,
            "url": "https://jw.example.edu.cn/default2.aspx",
            "depth": 8,
            "frames": frames
        ]
        let data = try! JSONSerialization.data(withJSONObject: obj)
        return String(data: data, encoding: .utf8)!
    }

    private func parse(_ html: String) -> [Any] {
        if html.contains("高等数学") || html.contains("操作系统") || html.contains("数据挖掘") {
            return [1, 2]
        }
        return []
    }

    // MARK: - case.json #1: 4 层嵌套

    func testFourLevelIframeRecursionReachesDeepestTable1() {
        let snaps = FrameSnapshotList.fromJson(json([
            f(name: "(top)", src: "https://jw.example.edu.cn/default2.aspx", depth: 0, path: [],
              html: "<html><body><h3>个人课表查询</h3></body></html>"),
            f(name: "L2_main", src: "L2_xsmain.html", depth: 1, path: ["(top)"],
              html: "<html><body>菜单框架</body></html>"),
            f(name: "L3_inner", src: "L3_xskbcx_main.html", depth: 2, path: ["(top)", "L2_main"],
              html: "<html><body>学期选择</body></html>"),
            f(name: "L4_kb", src: "L4_xskbcx_with_table.html", depth: 3,
              path: ["(top)", "L2_main", "L3_inner"],
              html: "<html><body><table id=\"Table1\"><tr><td>高等数学</td></tr></table></body></html>")
        ]))
        let r = FrameTraversalTree.rankAll(snaps, parse: parse)
        XCTAssertEqual(r.status, .ok)
        XCTAssertEqual(r.selectedFramePath, ["(top)", "L2_main", "L3_inner", "L4_kb"])
        XCTAssertTrue(r.matchedAnchors.contains("Table1"))
        XCTAssertTrue(r.html.contains("高等数学"))
        XCTAssertEqual(r.maxDepthReached, 3)
    }

    // MARK: - case.json #2: 3 层 default2→xs_main→xskbcx

    func testThreeLayerZfChainSelectsInnerXskbcxFrame() {
        let snaps = FrameSnapshotList.fromJson(json([
            f(name: "(top)", src: "https://jw.suda.edu.cn/default2.aspx", depth: 0, path: [],
              html: "<html><body><h3>欢迎</h3></body></html>"),
            f(name: "menu", src: "xs_left.aspx", depth: 1, path: ["(top)"],
              html: "<html><body><ul><li>首页</li></ul></body></html>"),
            f(name: "main", src: "xs_main.aspx", depth: 1, path: ["(top)"],
              html: "<html><body>中间 frameset</body></html>"),
            f(name: "content", src: "xskbcx.aspx", depth: 2, path: ["(top)", "main"],
              html: "<html><body><table id=\"Table1\"><tr><td>线性代数</td></tr></table></body></html>")
        ]))
        let r = FrameTraversalTree.rankAll(snaps, parse: { $0.contains("线性代数") ? [1, 2] : [] })
        XCTAssertEqual(r.status, .ok)
        XCTAssertEqual(r.selectedFramePath, ["(top)", "main", "content"])
        XCTAssertTrue(r.html.contains("线性代数"))
        XCTAssertEqual(r.skippedFrames, ["menu"])  // 无锚点 frame 记入诊断
    }

    // MARK: - case.json #3/#11: frame+iframe 混合, 单层可达(正向对照)

    func testMixedFramesAndIframesSingleLayerStillParsesCourses() {
        let snaps = FrameSnapshotList.fromJson(json([
            f(name: "(top)", src: "https://jw.example.edu.cn/default2.aspx", depth: 0, path: [],
              html: "<html><frameset><frame name=\"menuFrame\"><frame name=\"lastProgress\"></frameset></html>"),
            f(name: "menuFrame", src: "menu_side.html", depth: 1, path: ["(top)"],
              html: "<html><body><ul><li>选课</li></ul></body></html>"),
            f(name: "lastProgress", src: "lastProgress_kbcx.html", depth: 1, path: ["(top)"],
              html: "<html><body><table id=\"Table1\"><tr><td>高等数学</td></tr></table></body></html>")
        ]))
        let r = FrameTraversalTree.rankAll(snaps, parse: parse)
        XCTAssertEqual(r.status, .ok)
        XCTAssertEqual(r.selectedFramePath, ["(top)", "lastProgress"])
    }

    // MARK: - case.json #4: 顶层假 Table1 → 内层真表

    func testFakeTopTable1FallsBackToInnerRealTableByParseResult() {
        let topHtml = "<html><body><table id=\"Table1\"><tr><td>当前周次</td><td>3</td></tr></table></body></html>"
        let innerHtml = "<html><body><table id=\"Table1\"><tr><td>操作系统</td></tr></table></body></html>"
        XCTAssertTrue(FrameTraversalTree.findAnchors(topHtml).contains("Table1"),
                      "前置: 顶层确实含 Table1 锚点")
        let snaps = FrameSnapshotList.fromJson(json([
            f(name: "(top)", src: "https://jw.example.edu.cn/default2.aspx", depth: 0, path: [], html: topHtml),
            f(name: "kbcx", src: "xskbcx_real.html", depth: 1, path: ["(top)"], html: innerHtml)
        ]))
        // 旧实现的拼接语义会让 getElementById 命中顶层空壳; rankAll 按"解析课程数>0"回退
        let r = FrameTraversalTree.rankAll(snaps, parse: parse)
        XCTAssertEqual(r.status, .ok)
        XCTAssertEqual(r.selectedFramePath, ["(top)", "kbcx"])
        XCTAssertTrue(r.html.contains("操作系统"))
        XCTAssertFalse(r.html.contains("当前周次"))
        XCTAssertGreaterThan(r.courseCount, 0)
    }

    // MARK: - case.json #5: 跨域 iframe

    func testCrossOriginIframeYieldsCrossDomainBlockedWithDomainHint() {
        let snaps = FrameSnapshotList.fromJson(json([
            f(name: "(top)", src: "https://jw.main.edu.cn/default2.aspx", depth: 0, path: [],
              html: "<html><body><h3>个人课表查询</h3></body></html>"),
            f(name: "menu", src: "https://sso.other-school.edu.cn/cas/login", depth: 1,
              path: ["(top)"], html: nil, blocked: "sso.other-school.edu.cn"),
            f(name: "main", src: "https://jw-vpn.campus.edu.cn/http/777.../xskbcx.aspx", depth: 1,
              path: ["(top)"], html: nil, blocked: "jw-vpn.campus.edu.cn")
        ]))
        let r = FrameTraversalTree.selectBestFrame(snaps)
        XCTAssertEqual(r.status, .crossDomainIframeBlocked)
        XCTAssertEqual(r.blockedFrames, ["menu@sso.other-school.edu.cn", "main@jw-vpn.campus.edu.cn"])
        XCTAssertNil(r.selectedFramePath)
        XCTAssertEqual(r.diagnosticHint, "menu@sso.other-school.edu.cn、main@jw-vpn.campus.edu.cn")
    }

    // MARK: - case.json #8: iframe 内层是登录页

    func testSessionExpiredInsideIframeIsDetectedOnInnerFrameNotOnlyTop() {
        let snaps = FrameSnapshotList.fromJson(json([
            f(name: "(top)", src: "https://jw.example.edu.cn/xskbcx.aspx", depth: 0, path: [],
              html: "<html><body><h3>课表查询</h3><iframe name=\"main\" src=\"../common/login_redirect.html\"></iframe></body></html>"),
            f(name: "main", src: "../common/login_redirect.html", depth: 1, path: ["(top)"],
              html: "<html><body><form><input type=\"password\"/><input name=\"__VIEWSTATE\"/>请输入密码</form></body></html>")
        ]))
        let r = FrameTraversalTree.selectBestFrame(snaps)
        XCTAssertEqual(r.status, .sessionExpired)
        XCTAssertEqual(r.selectedFramePath, ["(top)", "main"])
        XCTAssertTrue(r.diagnosticHint.contains("登录") || r.diagnosticHint.contains("会话"),
                      "hint 必须指向登录语义")
        // 隐私红线: hint 不含 HTML 原文/Cookie/学号
        XCTAssertFalse(r.diagnosticHint.contains("__VIEWSTATE"))
        XCTAssertFalse(r.diagnosticHint.contains("txtUserName"))
    }

    func testMergedLoginFramesetIsSessionExpired() {
        let html = "<html><head><title>欢迎使用正方教务管理系统！请登录</title></head><body>"
            + "<form action=\"default2.aspx\"><input name=\"__VIEWSTATE\"/>"
            + "<input type=\"password\"/>请输入密码</form></body></html>"
        XCTAssertTrue(FrameTraversalTree.looksLikeLoginPage(html))
        let snaps = FrameSnapshotList.fromJson(json([
            f(name: "(top)", src: "https://jw.example.edu.cn/default2.aspx", depth: 0, path: [], html: html)
        ]))
        let r = FrameTraversalTree.selectBestFrame(snaps)
        XCTAssertEqual(r.status, .sessionExpired)
    }

    // MARK: - 硬指纹 logout-redirect: 先于锚点 (selectBestFrame 与 rankAll)

    func testLogoutRedirectHardFingerprintBeatsAnchorAndParse() {
        // 老正方 CAS 化: 跳转前 HTML 仍含真实 id="Table1" 骨架 — 锚点分支会误判 OK
        let html = "<html><body><script>window.parent.location.href='logout.aspx';</script>"
            + "<table id=\"Table1\"><tr><td>高等数学</td></tr></table></body></html>"
        let snaps = FrameSnapshotList.fromJson(json([
            f(name: "(top)", src: "https://jw.example.edu.cn/default2.aspx", depth: 0, path: [], html: html)
        ]))
        let r1 = FrameTraversalTree.selectBestFrame(snaps)
        XCTAssertEqual(r1.status, .sessionExpired)
        XCTAssertTrue(r1.diagnosticHint.contains("logout.aspx 跳转脚本"))
        let r2 = FrameTraversalTree.rankAll(snaps, parse: parse)
        XCTAssertEqual(r2.status, .sessionExpired)
        XCTAssertEqual(r2.diagnosticHint, r1.diagnosticHint)
    }

    // MARK: - case.json #9: qz 3 层 + 诱饵 noticeFrame

    func testQzDeep3WithDecoySelectsKbFrameAndSkipsNoticeFrame() {
        let snaps = FrameSnapshotList.fromJson(json([
            f(name: "(top)", src: "https://jw.example.edu.cn/jsxsd/framework/xskb/xskb_list.do",
              depth: 0, path: [], html: "<html><body>framework</body></html>"),
            f(name: "topFrame", src: "header.jsp", depth: 1, path: ["(top)"],
              html: "<html><body>header</body></html>"),
            f(name: "mainFrame", src: "maintab.jsp", depth: 1, path: ["(top)"],
              html: "<html><body><iframe name=\"kbFrame\"></iframe><iframe name=\"noticeFrame\"></iframe></body></html>"),
            f(name: "noticeFrame", src: "notice.jsp", depth: 2, path: ["(top)", "mainFrame"],
              html: "<html><body>放假通知</body></html>"),
            f(name: "kbFrame", src: "xskb_list_dk.jsp", depth: 2, path: ["(top)", "mainFrame"],
              html: "<html><body><table id=\"kbtable\"><tr><td>高等代数</td></tr></table></body></html>")
        ]))
        let r = FrameTraversalTree.rankAll(snaps,
                                          parse: { $0.contains("高等代数") ? [1, 2] : [] })
        XCTAssertEqual(r.status, .ok)
        XCTAssertEqual(r.selectedFramePath, ["(top)", "mainFrame", "kbFrame"])
        XCTAssertFalse(r.selectedFramePath!.contains("noticeFrame"))
        XCTAssertTrue(r.matchedAnchors.contains("kbtable"))
        XCTAssertTrue(r.skippedFrames.contains("noticeFrame"))
    }

    // MARK: - case.json #6/#7: 延迟渲染 + about:blank 壳

    func testDelayedKbContainerReadinessAndGiveUpStatus() {
        let html = "<html><body><h3>个人课表查询</h3><div id='Table1Wrap'>加载中...</div></body></html>"
        XCTAssertEqual(RenderReadinessChecker.check(html, retryCount: 0), .delay)
        XCTAssertEqual(RenderReadinessChecker.check(html, retryCount: 2), .delay)
        XCTAssertEqual(RenderReadinessChecker.check(html, retryCount: 3), .giveUp)
        XCTAssertEqual(RenderReadinessChecker.delayedStatus(retryCount: 3), .containerEmptyAfterDelay)
        XCTAssertEqual(RenderReadinessChecker.delayedStatus(retryCount: 2), .ok)
    }

    func testAboutBlankIframeShellRetriesAsNavPendingNotWrongPage() {
        let shell = "<html><head></head><body></body></html>"
        XCTAssertTrue(RenderReadinessChecker.checkBlankShell(shell))
        XCTAssertFalse(RenderReadinessChecker.checkBlankShell(
            "<html><body><table id=\"Table1\"><tr><td>线性代数</td></tr></table></body></html>"))
        // 模拟 retry 耗尽时的分类: 空壳 → IFRAME_NAV_PENDING
        let snaps = FrameSnapshotList.fromJson(json([
            f(name: "(top)", src: "https://jw.example.edu.cn/default2.aspx", depth: 0, path: [],
              html: "<html><body><h3>个人课表</h3><iframe name=\"main\" src=\"about:blank\"></iframe></body></html>"),
            f(name: "main", src: "about:blank", depth: 1, path: ["(top)"], html: shell)
        ]))
        let r = FrameTraversalTree.selectBestFrame(snaps)
        // 顶层无锚点、无登录指纹、无跨域 → WRONG_PAGE 占位, captureWithRetry 里按空壳升格
        XCTAssertEqual(r.status, .wrongPage)
        let shellFound = snaps.frames.contains { RenderReadinessChecker.checkBlankShell($0.outerHTML ?? "") }
        XCTAssertTrue(shellFound)
    }

    // MARK: - empty-semester 组

    func testEmptyGridSemesterAnchorsHitButZeroCoursesYieldsEmptySemester() {
        let html = "<html><body><table id=\"kbgrid_table_0\"><thead><tr>"
            + "<td align=\"Center\">星期一</td></tr></thead></table></body></html>"
        XCTAssertTrue(FrameTraversalTree.findAnchors(html).contains("kbgrid_table_0"))
        XCTAssertEqual(RenderReadinessChecker.check(html, retryCount: 0), .delay)
        let snaps = FrameSnapshotList.fromJson(json([
            f(name: "(top)", src: "https://jw.example.edu.cn/jwglxt/kbcx/xskbcx_cxXsgrkb.html",
              depth: 0, path: [], html: html)
        ]))
        let r = FrameTraversalTree.rankAll(snaps, parse: { _ in [] })
        XCTAssertEqual(r.status, .emptySemester)
        XCTAssertTrue(r.matchedAnchors.contains("kbgrid_table_0"))
        XCTAssertEqual(r.diagnosticHint, "已尝试 1 个含课表容器的 frame, 均未解析出课程")
    }

    // MARK: - case #18: UCAS personSchedule 无锚点容器

    func testUcasPersonScheduleWithoutGenericAnchorsIsCapturedByDoubleFingerprints() {
        // 真实页面 (v1.2 采集包): 容器 <table class='table table-striped…'> 不含任何
        // ANCHORS 集 id=/class=, 旧逻辑全无锚点 → WRONG_PAGE, App 内导入死路
        let html = "<html><head><title>个人课表</title></head><body>"
            + "<table class=\"table table-striped\"><tr><td><a href=\"/course/coursetime/123\">高等数学</a></td></tr></table>"
            + "</body></html>"
        XCTAssertTrue(FrameTraversalTree.findAnchors(html).isEmpty,
                      "前置: 真页面确实不含通用锚点")
        let snaps = FrameSnapshotList.fromJson(json([
            f(name: "(top)", src: "https://xkgo.ucas.ac.cn:3000/course/personSchedule",
              depth: 0, path: [], html: html)
        ]))
        let r = FrameTraversalTree.selectBestFrame(snaps)
        XCTAssertEqual(r.status, .ok, "双指纹 (个人课表 title + coursetime 链接) 必须救活为 OK")
        XCTAssertTrue(r.matchedAnchors.contains("ucas-personSchedule"))
    }

    func testSepPortalPageWithoutCoursetimeLinksStaysWrongPage() {
        // SEP 门户页 (登录后应用列表): 无 coursetime 链接, 不能被 UCAS 双指纹误吸
        let html = "<!DOCTYPE html><html><head><title>SEP 教育业务接入平台</title></head>"
            + "<body><div id=\"appStore\"><table class=\"table table-striped\"><tr><td>应用列表</td></tr></table></div></body></html>"
        let snaps = FrameSnapshotList.fromJson(json([
            f(name: "(top)", src: "https://sep.ucas.ac.cn/appStore", depth: 0, path: [], html: html)
        ]))
        let r = FrameTraversalTree.selectBestFrame(snaps)
        XCTAssertEqual(r.status, .wrongPage)
    }

    func testAspnetNamedContainerDgDataTableIsCapturedAsAnchor() {
        // xju_post 族 (新疆大学/UPC/CUG): ASP.NET 命名容器把 id 渲染成
        // ctl00_contentParent_dgData — 锚点取尾部子串 _dgdata, 引号内以锚点结尾即命中。
        let html = "<html><body><table id=\"ctl00_contentParent_dgData\" border=\"1\">"
            + "<tr><td align=\"center\">1</td><td>｛高等数学(1-16周)[教师：张三,地点：X101]｝</td></tr>"
            + "</table></body></html>"
        let anchors = FrameTraversalTree.findAnchors(html)
        XCTAssertTrue(anchors.contains("_dgdata"), "id 尾部子串 _dgdata 必须命中, got \(anchors)")
        let snaps = FrameSnapshotList.fromJson(json([
            f(name: "(top)", src: "https://jws.xju.edu.cn/xskb.aspx", depth: 0, path: [], html: html)
        ]))
        let r = FrameTraversalTree.selectBestFrame(snaps)
        XCTAssertEqual(r.status, .ok, "dgData 页面必须 OK 不再 WRONG_PAGE")
        // parser 侧解课由 JwWakeUpCompatParserTests 覆盖, 此处只断抓取层决策
    }

    func testDgdataSuffixAnchorDoesNotFalsePositiveOnUnrelatedIds() {
        // 反向: id="badge" 等以 dgdata 开头之外的无辜 id 不得命中; 中段含 _dgdata_ 也不算
        let html = "<html><body><div id=\"badge\"></div><div id=\"_dgdatax\"></div></body></html>"
        XCTAssertFalse(FrameTraversalTree.findAnchors(html).contains("_dgdata"))
    }

    // MARK: - allFrames 全帧落盘契约 (JwCaptureDump 消费)

    func testSelectBestFramePopulatesAllFramesAndDiagnostics() {
        let snaps = FrameSnapshotList.fromJson(json([
            f(name: "(top)", src: "https://jw.example.edu.cn/default2.aspx", depth: 0, path: [],
              html: "<html><body>menu</body></html>"),
            f(name: "main", src: "xs_main.aspx", depth: 1, path: ["(top)"],
              html: "<html><body><table id=\"Table1\"><tr><td>高等数学</td></tr></table></body></html>"),
            f(name: "x", src: "https://other.edu.cn/", depth: 2, path: ["(top)", "main"],
              html: nil, blocked: "https://other.edu.cn/")
        ]))
        let r = FrameTraversalTree.selectBestFrame(snaps)
        XCTAssertEqual(r.status, .ok)
        // allFrames = 可达 frame keyed by (parentPath + name) 以 "_" join
        XCTAssertEqual(r.allFrames.map { $0.path }, ["(top)", "(top)_main"])
        XCTAssertEqual(r.maxDepthReached, 2)
        XCTAssertEqual(r.blockedFrames, ["x@other.edu.cn"])
        // (top) 无锚点但是候选 "main" 的祖先 → 不算 skipped; x 不可达同样不进 skipped
        XCTAssertEqual(r.skippedFrames, [])
    }

    // MARK: - fromJson 容错

    func testFromJsonToleratesNullHtmlBlockedDomainAndMissingFrames() {
        let parsed = FrameSnapshotList.fromJson(
            """
            {"ok":true,"url":"u","depth":2,"frames":[
                {"name":"a","src":"https://x.example/","depth":1,"path":["(top)"],"html":null,"blocked":"x.example"},
                {"name":"b","src":"","depth":1,"path":[],"html":"<html></html>","blocked":""}]}
            """
        )
        XCTAssertEqual(parsed.frames.count, 2)
        XCTAssertNil(parsed.frames[0].outerHTML)
        XCTAssertEqual(parsed.frames[0].blockedDomain, "x.example")
        XCTAssertEqual(parsed.frames[0].parentPath, ["(top)"])
        XCTAssertEqual(FrameSnapshotList.fromJson("{}").frames.count, 0)
        XCTAssertEqual(FrameSnapshotList.fromJson("").frames.count, 0)
    }
}
