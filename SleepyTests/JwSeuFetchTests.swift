import XCTest
import WebKit
@testable import Sleepy

final class JwSeuFetchTests: XCTestCase {
    private struct Capture {
        let payload: [String: Any]
        let requests: [[String: Any]]
    }

    private final class Page: NSObject, WKURLSchemeHandler {
        let html: String
        init(_ html: String) { self.html = html }

        func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
            let bytes = Data("<!doctype html><html><body>\(html)</body></html>".utf8)
            urlSchemeTask.didReceive(URLResponse(url: urlSchemeTask.request.url!,
                                                 mimeType: "text/html",
                                                 expectedContentLength: bytes.count,
                                                 textEncodingName: "utf-8"))
            urlSchemeTask.didReceive(bytes)
            urlSchemeTask.didFinish()
        }

        func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
    }

    private final class Probe: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let loaded: XCTestExpectation
        let completed: XCTestExpectation
        var payload: [String: Any]?

        init(loaded: XCTestExpectation, completed: XCTestExpectation) {
            self.loaded = loaded
            self.completed = completed
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loaded.fulfill()
        }

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            if let body = message.body as? [String: Any], let json = body["json"] as? String {
                payload = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any]
            }
            completed.fulfill()
        }
    }

    private func resource(_ name: String, ext: String) throws -> String {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: ext)
            ?? bundle.url(forResource: name, withExtension: ext, subdirectory: "resources"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func validScheduleBody() throws -> String {
        let rows = try JSONSerialization.jsonObject(with: Data(resource("seu_courses", ext: "json").utf8))
        let bytes = try JSONSerialization.data(withJSONObject: ["datas": ["xskcb": ["rows": rows]]],
                                               options: [.sortedKeys])
        return try XCTUnwrap(String(data: bytes, encoding: .utf8))
    }

    @MainActor
    private func run(_ script: String, html: String = "", host: String = "ehall.seu.edu.cn",
                     path: String = "/", status: Int = 200, body: String? = nil) throws -> Capture {
        let scheduleBody = try body ?? validScheduleBody()
        let encodedBody = try JSONSerialization.data(withJSONObject: [scheduleBody])
        let bodyLiteral = try XCTUnwrap(String(data: encodedBody, encoding: .utf8))
        let loaded = expectation(description: "Fixture page loaded")
        let completed = expectation(description: "Production script returned its bridge result")
        let probe = Probe(loaded: loaded, completed: completed)
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(Page(html), forURLScheme: "sleepy-seu")
        config.userContentController.add(probe, name: "__sleepyBridge")
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
        webView.navigationDelegate = probe
        defer {
            webView.stopLoading()
            config.userContentController.removeScriptMessageHandler(forName: "__sleepyBridge")
        }
        webView.load(URLRequest(url: try XCTUnwrap(URL(string: "sleepy-seu://\(host)\(path)"))))
        wait(for: [loaded], timeout: 30)

        let fixture = """
        window.__seuRequests = [];
        window.__sleepyBridge = {onWiseduResult:function(json){
          window.webkit.messageHandlers.__sleepyBridge.postMessage({json:json});
        }};
        window.fetch = function(url, options) {
          options = options || {};
          window.__seuRequests.push({url:String(url), method:options.method || 'GET',
            credentials:options.credentials || '', body:options.body || ''});
          if (String(url).indexOf('/index.do') >= 0) return Promise.resolve({ok:true});
          if (String(url).indexOf('/dqxnxq.do') >= 0) return Promise.resolve({ok:true,json:function(){
            return Promise.resolve({datas:{dqxnxq:{rows:[
              {DM:'2026-2027-1',SFDQ:'1'}, {DM:'2026-2027-2'}
            ]}}});
          }});
          if (String(url).indexOf('/xskcb.do') >= 0) return Promise.resolve({
            ok:\(status >= 200 && status < 300 ? "true" : "false"), status:\(status),
            text:function(){return Promise.resolve(\(bodyLiteral)[0]);}
          });
          return Promise.reject(new Error('Unexpected fixture request: ' + url));
        };
        """
        let evaluated = expectation(description: "Script evaluated")
        webView.evaluateJavaScript(fixture + "\n" + script) { _, error in
            XCTAssertNil(error)
            evaluated.fulfill()
        }
        wait(for: [evaluated, completed], timeout: 10)
        let payload = try XCTUnwrap(probe.payload)
        let readRequests = expectation(description: "Read requests")
        var requests: [[String: Any]]?
        webView.evaluateJavaScript("window.__seuRequests") { result, error in
            XCTAssertNil(error)
            requests = result as? [[String: Any]]
            readRequests.fulfill()
        }
        wait(for: [readRequests], timeout: 10)
        return Capture(payload: payload, requests: try XCTUnwrap(requests))
    }

    @MainActor
    private func compareWithAndroid(_ ios: String, html: String = "", host: String = "ehall.seu.edu.cn",
                                    path: String = "/", status: Int = 200, body: String? = nil) throws -> Capture {
        let android = try resource("seu_gateway_android_v1063", ext: "js")
        let expected = try run(android, html: html, host: host, path: path, status: status, body: body)
        let actual = try run(ios, html: html, host: host, path: path, status: status, body: body)
        XCTAssertEqual(NSDictionary(dictionary: actual.payload), NSDictionary(dictionary: expected.payload))
        XCTAssertEqual(NSArray(array: actual.requests), NSArray(array: expected.requests))
        return actual
    }

    func testOnlySeuSelectsTheDedicatedGatewayFetch() throws {
        XCTAssertNotNil(JwSeuFetchJs.script(for: JwProtocol.TYPE_SEU))
        XCTAssertNil(JwSeuFetchJs.script(for: JwProtocol.TYPE_WISEDU))
        XCTAssertNil(JwSeuFetchJs.script(for: JwProtocol.TYPE_NEU))
        XCTAssertNil(JwSeuFetchJs.script(for: nil))
    }

    @MainActor
    func testPortalRootPrefersMainSelectedTermOverIframeAndApiCurrentTerm() throws {
        let script = try XCTUnwrap(JwSeuFetchJs.script(for: JwProtocol.TYPE_SEU))
        let capture = try compareWithAndroid(script, html: """
        <input id="dqxnxq2" value="2026-2027-2">
        <iframe srcdoc="<input id='dqxnxq2' value='2026-2027-1'>"></iframe>
        """)
        XCTAssertEqual(capture.payload["ok"] as? Bool, true)
        XCTAssertEqual(capture.payload["xnxq"] as? String, "2026-2027-2")
        XCTAssertEqual(capture.requests.last?["body"] as? String, "XNXQDM=2026-2027-2")
        let data = try XCTUnwrap(capture.payload["data"] as? String)
        XCTAssertEqual(try JwSeuParser(data).generateCourseList().count, 6)
    }

    @MainActor
    func testPortalRootFindsSelectedTermInsideSameOriginIframe() throws {
        let script = try XCTUnwrap(JwSeuFetchJs.script(for: JwProtocol.TYPE_SEU))
        let capture = try compareWithAndroid(script, html: """
        <iframe srcdoc="<input id='dqxnxq2' value='2026-2027-2'>"></iframe>
        """)
        XCTAssertEqual(capture.payload["ok"] as? Bool, true)
        XCTAssertEqual(capture.requests.last?["body"] as? String, "XNXQDM=2026-2027-2")
    }

    @MainActor
    func testOtherRootHostsRemainOutsideTheGatewayAllowlist() throws {
        let script = try XCTUnwrap(JwSeuFetchJs.script(for: JwProtocol.TYPE_SEU))
        let capture = try compareWithAndroid(script, host: "example.edu.cn")
        XCTAssertEqual(capture.payload["ok"] as? Bool, false)
        XCTAssertTrue(capture.requests.isEmpty)
    }

    @MainActor
    func testSharedWiseduValidRowsAndApiFailuresMatchAndroid() throws {
        let scenarios: [(Int, String?, String?)] = [
            (200, nil, nil),
            (403, "<html>login</html>", "WISEDU_HTTP_403"),
            (200, "<html>login</html>", "课表接口返回非 JSON"),
            (200, "{\"error\":\"session expired\"}", "课表接口响应缺少 xskcb.rows 数组")
        ]
        for (status, body, error) in scenarios {
            let capture = try compareWithAndroid(WiseduFetchJs.js, path: "/jwapp/",
                                                  status: status, body: body)
            if let error = error {
                XCTAssertEqual(capture.payload["ok"] as? Bool, false)
                XCTAssertTrue((capture.payload["err"] as? String)?.contains(error) == true)
                XCTAssertNil(capture.payload["data"], "An API error must not become an empty schedule")
            } else {
                XCTAssertEqual(capture.payload["ok"] as? Bool, true)
                XCTAssertEqual(capture.payload["xnxq"] as? String, "2026-2027-1")
                let data = try XCTUnwrap(capture.payload["data"] as? String)
                XCTAssertEqual(try JwSeuParser(data).generateCourseList().count, 6)
            }
        }
    }
}

final class JwWebViewFetchDeliveryTests: XCTestCase {
    private final class BridgeProbe: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let loaded: XCTestExpectation
        let onMessage: (WKUserContentController, WKScriptMessage) -> Void

        init(loaded: XCTestExpectation,
             onMessage: @escaping (WKUserContentController, WKScriptMessage) -> Void) {
            self.loaded = loaded
            self.onMessage = onMessage
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loaded.fulfill()
        }

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            onMessage(userContentController, message)
        }
    }

    @MainActor
    private func bridgeResults(cancelAfterAcceptance: Bool) throws -> [String] {
        let loaded = expectation(description: "Local capture page loaded")
        let drained = expectation(description: "Accepted bridge delivery queue drained")
        var results: [String] = []
        let coordinator = WebViewCoordinator(
            school: JwSchoolInfo(sortKey: "T", name: "测试"), desktopUa: false,
            onProgressChange: { _ in }, onUrlChanged: { _ in },
            onHtmlCaptured: { _ in XCTFail("Bridge capture must use its result callback") },
            onCaptureError: { _, hint in XCTFail(hint) },
            onWiseduResult: { results.append($0) })
        let probe = BridgeProbe(loaded: loaded) { controller, message in
            coordinator.userContentController(controller, didReceive: message)
            if cancelAfterAcceptance { coordinator.cancelFetch() }
            DispatchQueue.main.async { drained.fulfill() }
        }
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(probe, name: "__sleepyBridge")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = probe
        coordinator.webView = webView
        defer {
            coordinator.cancelFetch()
            coordinator.webView = nil
            webView.stopLoading()
            configuration.userContentController.removeScriptMessageHandler(forName: "__sleepyBridge")
        }
        webView.loadHTMLString("<!doctype html><html><body>Capture fixture</body></html>", baseURL: nil)
        wait(for: [loaded], timeout: 10)
        coordinator.evaluateFetchWithTimeout("""
        window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify({ok:true,data:'[]'})});
        """, captureId: "adapter-a")
        wait(for: [drained], timeout: 10)
        return results
    }

    @MainActor
    func testAcceptedBridgeResultIsDeliveredWhileCaptureRemainsCurrent() throws {
        let results = try bridgeResults(cancelAfterAcceptance: false)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first.flatMap(JwSgSourceMetadata.object)?["captureId"] as? String, "adapter-a")
    }

    @MainActor
    func testCancellingFetchDropsAnAlreadyAcceptedQueuedBridgeResult() throws {
        XCTAssertTrue(try bridgeResults(cancelAfterAcceptance: true).isEmpty)
    }
}
