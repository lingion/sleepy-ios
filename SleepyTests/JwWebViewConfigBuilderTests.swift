// JwWebViewConfigBuilderTests.swift — ← JwWebViewClientBuilder.kt 装配层单测
//
// 覆盖 fix_hint 指定两项: SslBypassRegistry 纯逻辑 + assembleInterceptors/build
// 装配语义。registrableDomain 用例对齐 Android SchoolDomainMatchTest(同一启发式
// 算法, JwWebViewCallbackThreadAffinenessTest 之外的第二道契约锁)。
//
// 平台注: WKWebView 实例化/真实 challenge 不在单测驱动 — SSL 放行决策就是
// SslBypassRegistry.isAllowed(委托本文件纯逻辑), 回调壳层的接线由
// WebViewNavigationPolicyTests(已有)与集成后的真机验证覆盖。

import XCTest
import WebKit
@testable import Sleepy

final class JwWebViewConfigBuilderTests: XCTestCase {

    private func school(_ url: String) -> JwSchoolInfo {
        JwSchoolInfo(sortKey: "T", name: "测试大学", url: url, type: "zf_new")
    }

    // MARK: - SslBypassRegistry.registrableDomain(← Android 同算法契约)

    func testRegistrableDomainSubdomainsCollapse() {
        XCTAssertEqual(SslBypassRegistry.registrableDomain("one.hfut.edu.cn"), "hfut.edu.cn")
        XCTAssertEqual(SslBypassRegistry.registrableDomain("jxglstu.hfut.edu.cn"), "hfut.edu.cn")
        XCTAssertEqual(SslBypassRegistry.registrableDomain("jw.ahu.edu.cn"), "ahu.edu.cn")
        XCTAssertEqual(SslBypassRegistry.registrableDomain("jwxt.cumtb.edu.cn"), "cumtb.edu.cn")
    }

    func testRegistrableDomainPlainTwoPartAndShortHosts() {
        XCTAssertEqual(SslBypassRegistry.registrableDomain("a.b.example.com"), "example.com")
        XCTAssertEqual(SslBypassRegistry.registrableDomain("localhost"), "localhost")
        XCTAssertEqual(SslBypassRegistry.registrableDomain("edu.cn"), "edu.cn")
    }

    func testRegistrableDomainCaseAndDotNormalization() {
        // 大小写折叠 + 首尾空白/尾点剥离(← Android .lowercase().trim().trimEnd('.'))
        XCTAssertEqual(
            SslBypassRegistry.registrableDomain(" ONE.HFUT.EDU.CN. "),
            "hfut.edu.cn")
    }

    func testRegistrableDomainAcUkSuffix() {
        XCTAssertEqual(SslBypassRegistry.registrableDomain("www.cam.ac.uk"), "cam.ac.uk")
    }

    // MARK: - SslBypassRegistry.isAllowed

    func testIsAllowedSameRegistrableDomainAndSubdomain() {
        XCTAssertTrue(SslBypassRegistry.isAllowed(host: "jwgl.hfut.edu.cn",
                                                  schoolHost: "one.hfut.edu.cn"))
        XCTAssertTrue(SslBypassRegistry.isAllowed(host: "hfut.edu.cn",
                                                  schoolHost: "hfut.edu.cn"))
    }

    func testIsAllowedRejectsForeignAndBlank() {
        XCTAssertFalse(SslBypassRegistry.isAllowed(host: "evil.com",
                                                   schoolHost: "hfut.edu.cn"))
        XCTAssertFalse(SslBypassRegistry.isAllowed(host: "hfut.edu.cn.attacker.net",
                                                   schoolHost: "hfut.edu.cn"))
        XCTAssertFalse(SslBypassRegistry.isAllowed(host: "", schoolHost: "hfut.edu.cn"))
        XCTAssertFalse(SslBypassRegistry.isAllowed(host: "hfut.edu.cn", schoolHost: "  "))
    }

    // MARK: - host(of:)

    func testHostOfUrl() {
        XCTAssertEqual(JwWebViewClientBuilder.host(of: "https://jwgl.hrbeu.edu.cn/jwapp"),
                       "jwgl.hrbeu.edu.cn")
        XCTAssertEqual(JwWebViewClientBuilder.host(of: "not a url"), "")
    }

    // MARK: - assembleInterceptors(装配点结构)

    func testAssembleInterceptorsStructure() {
        // iOS 无 chromium XRW 强注根因 → 链恒空, 但 UCAS 域不得抛错(装配点保留)
        XCTAssertEqual(JwWebViewClientBuilder.assembleInterceptors(
            school("https://sep.ucas.ac.cn/")), [])
        XCTAssertEqual(JwWebViewClientBuilder.assembleInterceptors(
            school("https://jwgl.hrbeu.edu.cn")), [])
    }

    // MARK: - build(config + ctx)

    func testBuildDesktopMode() {
        let (config, ctx) = JwWebViewClientBuilder.build(
            school: school("https://sep.ucas.ac.cn/Account/Login"), desktopMode: true)
        // 桌面 UA = 逐字对照常量; 生效杠杆 = customUserAgent(消费方), 非后缀拼接
        XCTAssertEqual(ctx.userAgent, JwWebViewClientBuilder.desktopUserAgent)
        XCTAssertEqual(ctx.schoolHost, "sep.ucas.ac.cn")
        // viewport WKUserScript 首注入已挂
        XCTAssertTrue(config.userContentController.userScripts.contains {
            $0.source == JwWebViewClientBuilder.desktopViewportJs
        }, "desktopMode 必须挂 viewport 覆盖 WKUserScript")
    }

    func testBuildDefaultModeNoUserAgentNoScript() {
        let (config, ctx) = JwWebViewClientBuilder.build(
            school: school("https://jwgl.hrbeu.edu.cn"), desktopMode: false)
        // 默认手机 UA: WKWebView 无同步读 UA API → 空串 = 平台默认(消费方 nil)
        XCTAssertEqual(ctx.userAgent, "")
        XCTAssertTrue(config.userContentController.userScripts.isEmpty)
        // ★ 回归锁: v1.0.60 曾把桌面 UA 写进 applicationNameForUserAgent(后缀位),
        // 最终 UA 仍含 iPhone → 门户零反应。装配器不得再设该字段。
        XCTAssertNotEqual(config.applicationNameForUserAgent,
                          JwWebViewClientBuilder.desktopUserAgent)
    }

    // MARK: - 常量逐字契约(与 Android JwWebViewLoginScreen.kt 对齐)

    func testDesktopConstantsVerbatim() {
        XCTAssertTrue(JwWebViewClientBuilder.desktopUserAgent.contains("Chrome/121.0.0.0"))
        XCTAssertFalse(JwWebViewClientBuilder.desktopUserAgent.contains("iPhone"))
        XCTAssertFalse(JwWebViewClientBuilder.desktopUserAgent.contains("Android"))
        XCTAssertTrue(JwWebViewClientBuilder.desktopViewportJs.contains("width=1024"))
        XCTAssertTrue(JwWebViewClientBuilder.desktopViewportJs.contains("scrollTo(0,0)"))
    }

    // MARK: - makeNavigationDelegate 装配产物

    func testMakeNavigationDelegateCtxSnapshot() {
        let delegate = JwWebViewClientBuilder.makeNavigationDelegate(
            school: school("https://jw.ahu.edu.cn"), desktopMode: true)
        // ctx 在工厂期捕获 schoolHost — callback 期不再解析 school.url
        XCTAssertEqual(delegate.ctx.schoolHost, "jw.ahu.edu.cn")
        XCTAssertEqual(delegate.ctx.userAgent, JwWebViewClientBuilder.desktopUserAgent)
    }

    func testDelegateDesktopViewportRuntimeToggle() {
        // Android UA 切换销毁重建 client → viewport 开关恒为当前态;iOS 原地
        // customUserAgent+reload 不重建 delegate → 开关必须运行时可翻转
        // (「手机模式打开 → 切桌面」主路径的回归锁, 契约: 先 set 再 reload)。
        let delegate = JwWebViewClientBuilder.makeNavigationDelegate(
            school: school("https://jwgl.hrbeu.edu.cn"), desktopMode: false)
        delegate.desktopViewport = true   // 编译即锁 var;false→true 翻转合法
        XCTAssertTrue(delegate.desktopViewport)
        delegate.desktopViewport = false
        XCTAssertFalse(delegate.desktopViewport)
    }

    // MARK: - ObjC 选择子暴露锁(WKNavigationDelegate 回调 = @objc optional)

    func testDelegateExposesWebKitSelectors() {
        // WKNavigationDelegate 的方法全部是 @objc optional: Swift 签名写错(参数
        // 类型/个数不对)时 -typecheck 照样通过, 但方法不映射到 WebKit 查询的选择子
        // → 回调永不触发 = 静默死代码(v1.0.61 审计发现的 decidePolicyFor 假签名即
        // 此病)。本测试用 responds(to:) 钉死 WebKit 实际调用的三个选择子 + SSL。
        let delegate = JwWebViewClientBuilder.makeNavigationDelegate(
            school: school("https://jw.ahu.edu.cn"), desktopMode: true)
        let asNS: NSObject = delegate
        XCTAssertTrue(asNS.responds(
            to: Selector(("webView:decidePolicyForNavigationAction:decisionHandler:"))),
            "请求侧回调未暴露 — 诊断暂存链死")
        XCTAssertTrue(asNS.responds(
            to: Selector(("webView:decidePolicyForNavigationResponse:decisionHandler:"))),
            "响应侧回调未暴露 — recordRequest 永不触发")
        XCTAssertTrue(asNS.responds(
            to: Selector(("webView:didCommitNavigation:"))))
        XCTAssertTrue(asNS.responds(
            to: Selector(("webView:didFinishNavigation:"))))
        XCTAssertTrue(asNS.responds(
            to: Selector(("webView:didReceiveAuthenticationChallenge:completionHandler:"))),
            "SSL 回调未暴露 — 私有 CA 学校在 iOS 必失败")
    }

    func testStashRequestPairingRoundTrip() {
        // ← Android shouldInterceptRequest 同时拿 request+response; iOS 拆两次
        // 回调, 配对逻辑(精确 URL 命中 → 消费; redirect 后 URL 变了 → 回退最近
        // 暂存)必须是纯逻辑可测的, 否则 recordRequest 字段错配。
        let delegate = JwWebViewClientBuilder.makeNavigationDelegate(
            school: school("https://jw.ahu.edu.cn"), desktopMode: false)
        delegate.stashRequest(.init(method: "POST",
                                    url: "https://jw.ahu.edu.cn/login",
                                    requestHeaders: ["A": "b"],
                                    isMainFrame: true))
        let hit = delegate.takeStashedRequest(matching: "https://jw.ahu.edu.cn/login")
        XCTAssertEqual(hit?.method, "POST")
        // 消费后再取 = 空(不被下一条响应重复配对)
        XCTAssertNil(delegate.takeStashedRequest(matching: "https://jw.ahu.edu.cn/login"))
        // redirect 场景: 响应 URL ≠ 请求 URL → 回退最近一次暂存
        delegate.stashRequest(.init(method: "GET",
                                    url: "https://jw.ahu.edu.cn/start",
                                    requestHeaders: nil,
                                    isMainFrame: true))
        let fallback = delegate.takeStashedRequest(matching: "https://jw.ahu.edu.cn/final")
        XCTAssertEqual(fallback?.url, "https://jw.ahu.edu.cn/start")
        XCTAssertNil(delegate.takeStashedRequest(matching: "https://never.stashed/x"))
    }
}
