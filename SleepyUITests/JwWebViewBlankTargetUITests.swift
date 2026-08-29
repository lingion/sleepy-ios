// JwWebViewBlankTargetUITests.swift — a.v.1.0.41 教务 WebView 新窗导航修复(端到端)
//
// 用户报告: 教务系统(哈工程金智)重定向多次后停在中间页, 点功能卡片不跳下一页。
// 根因: 教务卡片用 target="_blank"/window.open; WKWebView 无 UIDelegate 时静默丢弃
// 新窗请求(Android WebView 默认在当前页打开, 移植时丢失该语义)。
// 修复: JwWebViewLoginScreen 挂 NavUIDelegate → createWebViewWith 在当前 webview 内加载。
//
// 端到端验证走"自定义 URL 登录"入口(UrlDirectRow), 加载 runner 侧本地 HTTP server 页面,
// 页面含 4 类卡片(target=_blank / window.open / 普通 href / location.href), 自动点击后断言
// WebView 实际到达第二页。页面在 load 后 0.3s 自点, 无需 UI 坐标命中卡片。
//
// 注: 本地 server 跑在 UI test runner 进程, 与被测 app 同模拟器, 127.0.0.1 互通。
import XCTest

final class JwWebViewBlankTargetUITests: XCTestCase {

    var app: XCUIApplication!
    private var server: UISampleServer!

    override func setUpWithError() throws {
        continueAfterFailure = false
        server = UISampleServer()
        app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-SLEEPY_UI_TEST_SEED"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["pill_schedule"].waitForExistence(timeout: 10))
    }

    override func tearDownWithError() throws {
        app.terminate()
        server.stop()
    }

    /// 走 Manage → 导入 → 教务导入 → 搜索框输入本地 URL → UrlDirectRow 进 WebView
    private func navigateToWebView() {
        app.descendants(matching: .any)["pill_manage"].tap()
        app.descendants(matching: .any)["manage_import"].waitForExistence(timeout: 8)
        app.descendants(matching: .any)["manage_import"].tap()
        app.descendants(matching: .any)["import_jw"].waitForExistence(timeout: 8)
        app.descendants(matching: .any)["import_jw"].tap()
        let search = app.descendants(matching: .any)["school_search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10), "学校选择页未出现")
        search.tap()
        search.typeText(server.baseURL + "/page.html")
        // UrlDirectRow 出现("Login with this URL" 行)
        let urlRow = app.descendants(matching: .any).matching(identifier: "url_direct_row")
            .element(boundBy: 0)   // Text 挂 id 后其容器行也会继承可命中, 取第一个
        XCTAssertTrue(urlRow.waitForExistence(timeout: 8), "自定义 URL 登录行未出现")
        urlRow.tap()
    }

    private func cardPageHtml(autoClickTarget: String) -> String {
        """
        <!DOCTYPE html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">\
        <title>JW模拟</title></head><body style="margin:0">
        <a id="card_blank" href="page2.html" target="_blank" \
           style="display:block;padding:40px 20px;font-size:28px;background:#cfe">CardBlank</a>
        <a id="card_jsopen" href="javascript:void(0)" onclick="window.open('page2.html')" \
           style="display:block;padding:40px 20px;font-size:28px;background:#cfc">CardJsOpen</a>
        <a id="card_normal" href="page2.html" \
           style="display:block;padding:40px 20px;font-size:28px;background:#fcc">CardNormal</a>
        <script>
        window.addEventListener('load', function(){
          setTimeout(function(){
            var el = document.getElementById('\(autoClickTarget)');
            if (el) el.click();
          }, 400);
        });
        </script>
        </body></html>
        """
    }

    private let page2Html = """
    <!DOCTYPE html><html><head><title>第二页</title></head>\
    <body style="margin:0"><h1 id="arrived" style="font-size:40px;padding:40px">PAGE2-ARRIVED</h1></body></html>
    """

    // MARK: - target="_blank" 卡片(用户报障的核心场景)

    func testTargetBlankCardNavigatesToNextPage() throws {
        server.route["/page.html"] = cardPageHtml(autoClickTarget: "card_blank")
        server.route["/page2.html"] = page2Html
        navigateToWebView()
        // WebView 自动点 target=_blank 卡片 → NavUIDelegate 拦截 → 当前页加载 page2
        let arrived = app.staticTexts["PAGE2-ARRIVED"].waitForExistence(timeout: 10)
        if !arrived { print("★★★ server requests: \(server.requests)") }
        XCTAssertTrue(arrived, "target=_blank 卡片点击后应到达第二页(NavUIDelegate 拦截新窗在当前页打开)")
    }

    // MARK: - window.open 卡片

    func testWindowOpenCardNavigatesToNextPage() throws {
        server.route["/page.html"] = cardPageHtml(autoClickTarget: "card_jsopen")
        server.route["/page2.html"] = page2Html
        navigateToWebView()
        let arrived = app.staticTexts["PAGE2-ARRIVED"].waitForExistence(timeout: 10)
        if !arrived { print("★★★ server requests: \(server.requests)") }
        XCTAssertTrue(arrived, "window.open 卡片点击后应到达第二页")
    }

    // MARK: - 普通 href 卡片(无回归)

    func testNormalCardStillNavigates() throws {
        server.route["/page.html"] = cardPageHtml(autoClickTarget: "card_normal")
        server.route["/page2.html"] = page2Html
        navigateToWebView()
        let arrived = app.staticTexts["PAGE2-ARRIVED"].waitForExistence(timeout: 10)
        if !arrived { print("★★★ server requests: \(server.requests)") }
        XCTAssertTrue(arrived, "普通链接跳转不应受修复影响")
    }
}

/// UI test runner 侧极简 HTTP server: 按路径返回预置 HTML。
/// route 用 NSLock 保护(accept 线程读 / 测试线程写); requests 记录每个命中路径供断言。
final class UISampleServer {
    private let lock = NSLock()
    private var routes: [String: String] = [:]
    private(set) var requests: [String] = []
    private var socketFD: Int32 = -1
    private var thread: Thread?
    private(set) var port: UInt16 = 0

    var baseURL: String { "http://127.0.0.1:\(port)" }

    var route: [String: String] {
        get { lock.lock(); defer { lock.unlock() }; return routes }
        set { lock.lock(); defer { lock.unlock() }; routes = newValue }
    }

    init() {
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr = in_addr(s_addr: INADDR_LOOPBACK.bigEndian)
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        let bindOK = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindOK == 0, listen(fd, 8) == 0 else { close(fd); return }
        var bound = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &bound) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                _ = getsockname(fd, $0, &len)
            }
        }
        port = UInt16(bigEndian: bound.sin_port)
        socketFD = fd
        thread = Thread { [weak self] in self?.acceptLoop() }
        thread?.stackSize = 256 * 1024
        thread?.start()
    }

    private func acceptLoop() {
        while true {
            let client = accept(socketFD, nil, nil)
            guard client >= 0 else { break }
            var buf = [UInt8](repeating: 0, count: 8192)
            _ = read(client, &buf, 8192)
            let request = String(bytes: buf.prefix(while: { $0 != 0 }), encoding: .utf8) ?? ""
            // 解析请求路径 "GET /x HTTP/1.1"
            let path = request.split(separator: "\r\n").first
                .map { $0.split(separator: " ").count > 1 ? String($0.split(separator: " ")[1]) : "/" } ?? "/"
            lock.lock()
            requests.append(path)
            let html = routes[path] ?? "<html><body>404</body></html>"
            lock.unlock()
            var out = Data("HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n".utf8)
            out.append(Data(html.utf8))
            out.withUnsafeBytes { ptr in
                var sent = 0
                while sent < ptr.count {
                    let n = write(client, ptr.baseAddress!.advanced(by: sent), ptr.count - sent)
                    if n <= 0 { break }
                    sent += n
                }
            }
            close(client)
        }
    }

    func stop() {
        if socketFD >= 0 { close(socketFD); socketFD = -1 }
    }
}
