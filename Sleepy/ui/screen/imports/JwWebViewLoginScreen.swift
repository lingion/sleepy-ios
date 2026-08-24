// JwWebViewLoginScreen.swift — ← ui/screen/imports/JwWebViewLoginScreen.kt (515 行)
// 教务 WebView 登录页。
// Android WebView+JS 桥 → WKWebView + WKScriptMessageHandler:
//   - loadUrl("javascript:") → evaluateJavaScript(直接回调, 无需桥)
//   - addJavascriptInterface(__sleepyBridge) → WKScriptMessageHandler(name: "__sleepyBridge")
//   - SSL 自签 proceed → 不实现(WKWebView 默认拒绝;ATS 例外需 Info.plist, 保守不放开)
// 抓 HTML: document.documentElement.outerHTML + iframe/frame 合并(同一份 JS)。
// wisedu(金智) 协议: WebView 内 fetch 课表 JSON(WISEDU_FETCH_JS 原文移植)。

import SwiftUI
import WebKit

struct JwWebViewLoginScreen: View {
    // (WISEDU_FETCH_JS 定义在文件尾 WiseduFetchJs enum; 前置引用走 static)

    @Environment(\.localWakeUpColors) private var colors
    let school: JwSchoolInfo
    let onHtmlCaptured: (String, JwSchoolInfo, [(Int, String, String)]) -> Void
    let onBack: () -> Void

    @State private var progress: Double = 0
    @State private var webViewCoordinator: WebViewCoordinator? = nil
    @State private var snackMessage: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            // TopBar(校名 + 协议名)
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(colors.onBackground)
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 2) {
                    Text(school.name)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(colors.onBackground)
                    Text(JwProtocol.displayName(school.type))
                        .font(.system(size: 12))
                        .foregroundColor(colors.onSurfaceVariant)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(colors.background)

            ZStack(alignment: .top) {
                JwWebView(
                    url: school.url.isEmpty ? "https://www.baidu.com" : school.url,
                    onProgressChange: { p in progress = p },
                    onCoordinatorCreated: { coordinator in webViewCoordinator = coordinator },
                    onHtmlCaptured: { html in onHtmlCaptured(html, school, []) },
                    onWiseduResult: handleWiseduResult)

                if progress >= 1 && progress < 100 {
                    ProgressView(value: progress / 100)
                        .tint(colors.primary)
                        .frame(height: 3)
                        .padding(.top, 4)
                }
            }

            // CaptureBar
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.format("jw_after_login"))
                        .font(.system(size: 12))
                        .foregroundColor(colors.onSurfaceVariant)
                    Text(L10n.format("jw_nav_hint"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colors.onSurface)
                }
                Spacer()
                Button(action: capture) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle")
                        Text(L10n.format("jw_import_page"))
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(colors.onPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(colors.primary)
                    .cornerRadius(SleepyShapes.extraLarge)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(colors.surface)
        }
        .overlay(alignment: .bottom) {
            if let msg = snackMessage {
                Text(msg)
                    .font(.system(size: 13))
                    .foregroundColor(colors.onSurface)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(colors.surfaceContainerHighest)
                    .cornerRadius(8)
                    .padding(.bottom, 80)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            withAnimation { snackMessage = nil }
                        }
                    }
            }
        }
    }

    // ← CaptureBar onCapture
    private func capture() {
        guard let coordinator = webViewCoordinator else {
            snackMessage = L10n.format("jw_webview_not_ready")
            return
        }
        snackMessage = L10n.format("jw_fetching")
        // wisedu (金智): 课表数据在 JSON API, fetch 拿 JSON(结果走 JS 桥回调)
        if school.type == JwProtocol.TYPE_WISEDU {
            coordinator.evaluate(WiseduFetchJs.js)
            return
        }
        // 同步 evaluateJavascript 拿 HTML(iframe/frame 合并)
        let js = """
        (function() {
            try {
                var ifrs = document.getElementsByTagName('iframe');
                var iframeContent = '';
                for (var i = 0; i < ifrs.length; i++) {
                    try { iframeContent += ifrs[i].contentDocument.documentElement.outerHTML; } catch(e) {}
                }
                var frs = document.getElementsByTagName('frame');
                var frameContent = '';
                for (var i = 0; i < frs.length; i++) {
                    try { frameContent += frs[i].contentDocument.documentElement.outerHTML; } catch(e) {}
                }
                var html = (document.documentElement && document.documentElement.outerHTML) || '';
                JSON.stringify({ok:true, url:location.href, len:html.length+iframeContent.length+frameContent.length, html:html+iframeContent+frameContent});
            } catch(err) {
                JSON.stringify({ok:false, err:String(err)});
            }
        })();
        """
        coordinator.evaluate(js) { raw in
            guard let raw = raw, raw != "null", !raw.isEmpty,
                  let data = raw.data(using: .utf8),
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                snackMessage = L10n.format("jw_fetch_failed_no_response")
                return
            }
            guard (obj["ok"] as? Bool) == true,
                  let html = obj["html"] as? String, !html.isEmpty else {
                let err = (obj["err"] as? String) ?? ""
                snackMessage = L10n.format("jw_fetch_failed",
                                           err.isEmpty ? L10n.format("jw_page_not_loaded") : err)
                return
            }
            onHtmlCaptured(html, school, [])
        }
    }

    // ← handleWiseduResult: {ok:true,data:...} / {ok:false,err:...}
    private func handleWiseduResult(_ json: String) {
        guard let data = json.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            snackMessage = L10n.format("jw_fetch_format_error")
            return
        }
        if (obj["ok"] as? Bool) == true {
            guard let content = obj["data"] as? String, !content.isEmpty else {
                snackMessage = L10n.format("jw_fetch_failed_no_response")
                return
            }
            var periods: [(Int, String, String)] = []
            if let arr = obj["periods"] as? [[String: Any]] {
                for (i, p) in arr.enumerated() {
                    let node = (p["node"] as? NSNumber)?.intValue ?? (i + 1)
                    periods.append((node, p["start"] as? String ?? "", p["end"] as? String ?? ""))
                }
            }
            onHtmlCaptured(content, school, periods)
        } else {
            let err = (obj["err"] as? String) ?? ""
            snackMessage = L10n.format("jw_fetch_failed",
                                       err.isEmpty ? L10n.format("jw_page_not_loaded") : err)
        }
    }
}

// MARK: - WKWebView 包装 ← JwWebView

/// WKWebView 协调器(← WebView + WebViewClient + WebChromeClient + JS 桥)
final class WebViewCoordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    var webView: WKWebView?
    private let onProgressChange: (Double) -> Void
    private let onHtmlCaptured: (String) -> Void
    private let onWiseduResult: (String) -> Void
    private var progressObserver: NSKeyValueObservation?

    init(onProgressChange: @escaping (Double) -> Void,
         onHtmlCaptured: @escaping (String) -> Void,
         onWiseduResult: @escaping (String) -> Void) {
        self.onProgressChange = onProgressChange
        self.onHtmlCaptured = onHtmlCaptured
        self.onWiseduResult = onWiseduResult
        super.init()
    }

    func makeWebView(url: URL) -> WKWebView {
        let config = WKWebViewConfiguration()
        let prefs = WKPreferences()
        prefs.javaScriptCanOpenWindowsAutomatically = true
        config.preferences = prefs
        // ← addJavascriptInterface(__sleepyBridge) → ScriptMessageHandler
        config.userContentController.add(self, name: "__sleepyBridge")

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = self
        // ← settings: domStorage WKWebView 默认开; 缩放手势
        wv.allowsBackForwardNavigationGestures = true

        // estimatedProgress KVO(← onProgressChanged)
        progressObserver = wv.observe(\.estimatedProgress, options: .new) { [weak self] _, change in
            DispatchQueue.main.async {
                self?.onProgressChange((change.newValue ?? 0) * 100)
            }
        }
        wv.load(URLRequest(url: url))
        webView = wv
        return wv
    }

    func evaluate(_ js: String, completion: ((String?) -> Void)? = nil) {
        webView?.evaluateJavaScript(js) { result, _ in
            completion?(result as? String)
        }
    }

    // ← @JavascriptInterface onWiseduResult
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == "__sleepyBridge" else { return }
        if let body = message.body as? [String: Any],
           let json = body["json"] as? String {
            DispatchQueue.main.async { self.onWiseduResult(json) }
        }
    }
}

struct JwWebView: UIViewRepresentable {
    let url: String
    let onProgressChange: (Double) -> Void
    let onCoordinatorCreated: (WebViewCoordinator) -> Void
    let onHtmlCaptured: (String) -> Void
    let onWiseduResult: (String) -> Void

    func makeCoordinator() -> WebViewCoordinator {
        WebViewCoordinator(onProgressChange: onProgressChange,
                           onHtmlCaptured: onHtmlCaptured,
                           onWiseduResult: onWiseduResult)
    }

    func makeUIView(context: Context) -> WKWebView {
        onCoordinatorCreated(context.coordinator)
        let wv = context.coordinator.makeWebView(
            url: URL(string: url) ?? URL(string: "https://www.baidu.com")!)
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

// MARK: - WISEDU_FETCH_JS(逐行移植, 桥回调改 WKScriptMessage postMessage)

enum WiseduFetchJs {
    static let js = """
    (function(){
      try {
        if (location.hostname.indexOf('jwgl.hrbeu.edu.cn') < 0) {
          window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify({ok:false, err:'请先登录并进入教务系统(jwgl.hrbeu.edu.cn)再点导入'})});
          return;
        }
        fetch('/jwapp/sys/wdkb/*default/index.do', {credentials:'include'})
        .then(function(){
          return fetch('/jwapp/sys/wdkb/modules/jshkcb/dqxnxq.do', {
            method:'POST',
            headers:{'X-Requested-With':'XMLHttpRequest'},
            credentials:'include'
          });
        })
        .then(function(r){ return r.json(); })
        .then(function(d){
          var rows = [];
          try { rows = d.datas.dqxnxq.rows || []; } catch(e) {}

          var xnxq = '';
          var selects = document.querySelectorAll('select');
          for (var i = 0; i < selects.length && !xnxq; i++) {
            var selected = selects[i].options && selects[i].options[selects[i].selectedIndex];
            var candidates = selected ? [selected.value, selected.textContent || ''] : [];
            for (var j = 0; j < candidates.length; j++) {
              var match = candidates[j].match(/20[0-9]{2}-20[0-9]{2}-[12]/);
              if (match && rows.some(function(row) { return String(row.DM || '') === match[0]; })) {
                xnxq = match[0];
                break;
              }
            }
          }
          if (!xnxq) {
            var active = document.querySelectorAll('.selected,.active,[aria-selected="true"]');
            for (var k = 0; k < active.length && !xnxq; k++) {
              var activeText = active[k].value || active[k].textContent || '';
              var activeMatch = activeText.match(/20[0-9]{2}-20[0-9]{2}-[12]/);
              if (activeMatch && rows.some(function(row) { return String(row.DM || '') === activeMatch[0]; })) {
                xnxq = activeMatch[0];
              }
            }
          }
          if (!xnxq) {
            var termNode = document.querySelector('[data-elem="XNXQMC"]');
            var termText = termNode ? (termNode.textContent || '') : '';
            var termMatch = termText.match(/(20[0-9]{2})-(20[0-9]{2})\\s*学年\\s*([12])\\s*学期/);
            if (termMatch) {
              var termDm = termMatch[1] + '-' + termMatch[2] + '-' + termMatch[3];
              xnxq = termDm;
            }
          }
          if (!xnxq) {
            var current = rows.find(function(row) {
              return row.DM && (row.SFDQ === '1' || row.SFDQ === 1 || row.CURRENT === '1' || row.current === true);
            });
            xnxq = current ? String(current.DM) : '';
          }
          if (!xnxq) throw new Error('无法识别当前选中的学期，请先在教务页面选择学期后再点导入');
          return fetch('/jwapp/sys/wdkb/modules/xskcb/xskcb.do', {
            method:'POST',
            headers:{'Content-Type':'application/x-www-form-urlencoded','X-Requested-With':'XMLHttpRequest'},
            body:'XNXQDM='+encodeURIComponent(xnxq),
            credentials:'include'
          }).then(function(r){ return r.text().then(function(txt){
            return {xnxq:xnxq, txt:txt};
          });});
        })
        .then(function(o){
          var periods = [];
          try {
            var nodes = document.querySelectorAll('[class*="jc"],[class*="jcdm"],[class*="jcbz"],[id*="node"],[id*="jc"]');
            var seen = {};
            for (var i = 0; i < nodes.length; i++) {
              var txt = (nodes[i].innerText || nodes[i].textContent || '').trim();
              var m = txt.match(/^([0-9]{1,2})[:\\s]+([0-2]?[0-9]:[0-5][0-9])[~～-]([0-2]?[0-9]:[0-5][0-9])$/);
              if (m && !seen[m[1]]) {
                seen[m[1]] = true;
                periods.push({node:parseInt(m[1],10), start:m[2], end:m[3]});
              }
            }
            if (periods.length === 0) {
              var allText = document.body.innerText || '';
              var re = /([0-9]{1,2})[:\\s]\\s*([0-2]?[0-9]:[0-5][0-9])[~～-]([0-2]?[0-9]:[0-5][0-9])/g;
              var mm;
              while ((mm = re.exec(allText)) !== null) {
                var n = parseInt(mm[1], 10);
                if (n >= 1 && n <= 20 && !seen[n]) {
                  seen[n] = true;
                  periods.push({node:n, start:mm[2], end:mm[3]});
                }
              }
            }
            periods.sort(function(a,b){ return a.node - b.node; });
          } catch(e) { periods = []; }
          window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify({
            ok:true,
            data:o.txt,
            xnxq:o.xnxq,
            periods:periods
          })});
        })
        .catch(function(e){
          window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify({ok:false, err:String(e)})});
        });
      } catch(err) {
        window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify({ok:false, err:String(err)})});
      }
    })();
    """
}
