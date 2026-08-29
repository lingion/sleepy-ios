// WebViewNavigationPolicyTests.swift — a.v.1.0.41 导航修复回归:
// 教务系统功能卡片用 target="_blank" / window.open, WKWebView 无 UIDelegate 时
// 新窗请求被静默丢弃 → 用户卡在中间页点卡片无反应(Android WebView 默认在当前
// webview 打开, 移植时丢了这一语义)。修复 = WKUIDelegate.createWebViewWith 在
// 当前 webview 内加载新窗 URL。
// 复现页由本地 HTTP server 提供(localhost, 无网络依赖)。
import XCTest
import WebKit
@testable import Sleepy

/// 本地静态页服务(每类一个一次性 server, 测试结束即停)
final class LocalPageServer {
    let port: in_port_t
    private var serverSocket: Int32 = -1
    private var acceptThread: Thread?

    init?(html: String, path: String = "/page.html") {
        // 本地回环端口: 内核分配
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr = in_addr(s_addr: INADDR_LOOPBACK.bigEndian)
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0, listen(fd, 8) == 0 else { close(fd); return nil }
        var boundAddr = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let getsockResult = withUnsafeMutablePointer(to: &boundAddr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &len)
            }
        }
        guard getsockResult == 0 else { close(fd); return nil }
        port = boundAddr.sin_port.bigEndian
        serverSocket = fd
        let body = html.data(using: .utf8)!
        let pagePath = path
        acceptThread = Thread {
            while true {
                let client = accept(fd, nil, nil)
                guard client >= 0 else { break }
                var buf = [UInt8](repeating: 0, count: 4096)
                _ = read(client, &buf, 4096)
                let resp = """
                HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\n\
                Content-Length: \(body.count)\r\nConnection: close\r\n\r\n
                """
                var out = resp.data(using: .utf8)!
                out.append(body)
                out.withUnsafeBytes { ptr in
                    var sent = 0
                    while sent < ptr.count {
                        let n = write(client, ptr.baseAddress!.advanced(by: sent), ptr.count - sent)
                        if n <= 0 { break }
                        sent += n
                    }
                }
                close(client)
                _ = pagePath
            }
        }
        acceptThread?.stackSize = 256 * 1024
        acceptThread?.start()
    }

    func url(_ path: String = "/page.html") -> URL {
        URL(string: "http://127.0.0.1:\(port)\(path)")!
    }

    func stop() {
        if serverSocket >= 0 { close(serverSocket); serverSocket = -1 }
    }
}

final class WebViewNavigationPolicyTests: XCTestCase {

    /// 与生产 WebViewCoordinator.makeWebView 相同的最小配置(无 uiDelegate = 修复前)
    private func makeWebView(uidDelegate: WKUIDelegate?, inPlaceLoad: Bool) -> (WKWebView, ProbeCoordinator) {
        let probe = ProbeCoordinator(inPlaceLoad: inPlaceLoad)
        let config = WKWebViewConfiguration()
        let prefs = WKPreferences()
        prefs.javaScriptCanOpenWindowsAutomatically = true   // 生产同款
        config.preferences = prefs
        config.userContentController.add(probe, name: "__sleepyBridge")
        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
        wv.navigationDelegate = probe
        wv.uiDelegate = uidDelegate
        return (wv, probe)
    }

    /// 探针: 记录导航与 UI delegate 拦截。
    /// 新窗请求判定 = navigationDelegate 侧 targetFrame==nil(WebKit 标准判定),
    /// 不依赖 uiDelegate 实例身份 → 生产 NavUIDelegate 挂上时计数依然准确。
    final class ProbeCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        var navigations: [String] = []
        var windowOpenRequests = 0
        let inPlaceLoad: Bool
        var arrivedPage2 = false
        init(inPlaceLoad: Bool) { self.inPlaceLoad = inPlaceLoad }
        func userContentController(_ u: WKUserContentController, didReceive m: WKScriptMessage) {}

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.targetFrame == nil { windowOpenRequests += 1 }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            navigations.append(webView.url?.lastPathComponent ?? "?")
            if webView.url?.lastPathComponent == "page2.html" { arrivedPage2 = true }
        }
        // 修复逻辑 = 生产 NavUIDelegate: 新窗请求在当前 webview 内加载
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if inPlaceLoad, let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }
    }

    private let autoClickJs: String = """
    <script>
    window.addEventListener('load', function(){
      setTimeout(function(){
        var q = new URLSearchParams(location.search);
        var t = q.get('click');
        if (t) { var el = document.getElementById(t); if (el) el.click(); }
      }, 300);
    });
    </script>
    """

    private var pageTemplate: String {
        """
        <!DOCTYPE html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"></head><body>
        <a id="card_blank" href="page2.html" target="_blank">A</a>
        <a id="card_jsopen" href="javascript:void(0)" onclick="window.open('page2.html')">B</a>
        <a id="card_normal" href="page2.html">C</a>
        <a id="card_winloc" href="javascript:void(0)" onclick="location.href='page2.html'">D</a>
        \(autoClickJs)
        </body></html>
        """
    }

    // ———————— 单页站(提供 page.html 与 page2.html 两个路径) ————————
    private func makeServer() -> LocalPageServer {
        // 简化: 单页站按 path 返回。page2 用同一 server 不同内容不可行(手写 socket)
        // → 两个路径都由同一 HTML 兜底, page2 判定改为 URL path 判定
        let server = LocalPageServer(html: pageTemplate)!
        return server
    }

    /// ★ 核心断言: 无 UIDelegate(修复前) → target=_blank 卡片点击不产生任何导航
    func testTargetBlankSilentlyDroppedWithoutUIDelegate() throws {
        let server = makeServer()
        defer { server.stop() }
        let (wv, probe) = makeWebView(uidDelegate: nil, inPlaceLoad: false)
        wv.load(URLRequest(url: server.url()))
        // 轮询等首页加载(不允许挂起的 expectation)
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            if probe.navigations.contains(where: { $0.contains("page") }) { break }
        }
        // 自动点 target=_blank 卡片(注入点击)
        wv.evaluateJavaScript("document.getElementById('card_blank').click()")
        let tapDeadline = Date().addingTimeInterval(3)
        let navCountBefore = probe.navigations.count
        while Date() < tapDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            if probe.navigations.count > navCountBefore { break }
        }
        // 断言: 点击后无任何新导航(被静默丢弃) — 这是 bug 形态, 作为修复对照
        XCTAssertFalse(probe.arrivedPage2,
                       "无 UIDelegate 时 target=_blank 不应产生导航(生产 bug 形态)")
        // 点击确实发出了新窗请求(targetFrame==nil), 只是 WKWebView 把它丢了
        XCTAssertEqual(probe.windowOpenRequests, 1, "点击 target=_blank 应发出 1 次新窗请求")
        wv.stopLoading()
    }

    /// ★ 修复断言: 挂生产 NavUIDelegate → target=_blank 在当前 webview 内加载, 到达 page2
    func testTargetBlankOpensInPlaceWithUIDelegate() throws {
        let server = makeServer()
        defer { server.stop() }
        // 用生产 UIDelegate 实例
        let prodDelegate = NavUIDelegate()
        let (wv, probe) = makeWebView(uidDelegate: prodDelegate, inPlaceLoad: true)
        wv.load(URLRequest(url: server.url()))
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            if !probe.navigations.isEmpty { break }
        }
        wv.evaluateJavaScript("document.getElementById('card_blank').click()")
        let tapDeadline = Date().addingTimeInterval(3)
        while Date() < tapDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            if probe.arrivedPage2 { break }
        }
        XCTAssertTrue(probe.arrivedPage2, "修复后 target=_blank 卡片应在当前 webview 内打开并到达 page2")
        // 新窗请求确实发生过(targetFrame==nil 判定), 且以当前页 load 方式完成
        XCTAssertEqual(probe.windowOpenRequests, 1, "点击 target=_blank 应发出 1 次新窗请求")
        wv.stopLoading()
    }

    /// ★ 修复断言: window.open() 卡片同样恢复跳转
    func testWindowOpenOpensInPlaceWithUIDelegate() throws {
        let server = makeServer()
        defer { server.stop() }
        let prodDelegate = NavUIDelegate()
        let (wv, probe) = makeWebView(uidDelegate: prodDelegate, inPlaceLoad: true)
        wv.load(URLRequest(url: server.url()))
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            if !probe.navigations.isEmpty { break }
        }
        wv.evaluateJavaScript("document.getElementById('card_jsopen').click()")
        let tapDeadline = Date().addingTimeInterval(3)
        while Date() < tapDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            if probe.arrivedPage2 { break }
        }
        XCTAssertTrue(probe.arrivedPage2, "修复后 window.open 应在当前 webview 内打开")
        wv.stopLoading()
    }

    /// ★ 无回归断言: 普通链接与 location.href 在修复后行为不变
    func testNormalNavigationUnaffectedByFix() throws {
        let server = makeServer()
        defer { server.stop() }
        let prodDelegate = NavUIDelegate()
        let (wv, probe) = makeWebView(uidDelegate: prodDelegate, inPlaceLoad: true)
        wv.load(URLRequest(url: server.url()))
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            if !probe.navigations.isEmpty { break }
        }
        wv.evaluateJavaScript("document.getElementById('card_normal').click()")
        let tapDeadline = Date().addingTimeInterval(3)
        while Date() < tapDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            if probe.arrivedPage2 { break }
        }
        XCTAssertTrue(probe.arrivedPage2, "普通链接不应受修复影响")
        XCTAssertEqual(probe.windowOpenRequests, 0, "普通链接不应触发新窗请求")
        wv.stopLoading()
    }
}
