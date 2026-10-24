// JwWebViewConfigBuilder.swift — ← ui/screen/imports/JwWebViewClientBuilder.kt (v1.0.61, 151 行)
//
// WebView 客户端配置装配器 — WKWebView 形态移植。
//
// ## Android 原架构 (HEBZYHJ 闪退根因, 2026-09-09)
// 旧实现 inline 在 JwWebViewLoginScreen factory 闭包内 new 出 WebViewClient,
// callback 体内触碰 view.settings.userAgentString → WebView.checkThread() →
// RuntimeException → 进程终止。修复 = 架构边界:
//   1. 工厂期(主线程)一次性读 userAgent / schoolHost → 缓存进 JwInterceptorContext
//   2. callback 体内只读 ctx 注入的字符串/单例, 不再触碰任何 view.* 方法
//   3. interceptor 按 school.url 装配, 默认 client 不感知协议特例
//   4. JwWebViewCallbackThreadAffinenessTest 锁死架构边界
//
// ## iOS 平台差异 (装配件对照表)
//   Android WebViewClient              → 本文件 JwWebViewNavigationDelegate
//                                         (WKNavigationDelegate 实现, ← JwWebViewClientImpl)
//   shouldInterceptRequest 拦截链       → WKWebView 不暴露逐请求同步拦截 API。
//         WKURLSchemeHandler 只对自定义 scheme 生效(教务是 http/https, 挂不上)。
//         SEP XRW 剥离的等价杠杆在 iOS 是 **customUserAgent**:
//         WKWebView 不像 chromium 强注 XRW 头, iOS 侧 SEP 401 根因
//         本就不存在 → interceptor 链在 iOS 缩为「按 school 预备 UA 覆盖」,
//         与 JwWebViewLoginScreen.applyDesktopUserAgent 同一杠杆。
//         逐请求诊断在 iOS 的公开替代 = decidePolicyFor(navigationAction) +
//         decidePolicyFor(navigationResponse) 两回调配对(仅主框架导航; 子资源不
//         可见, fetch/XHR 层由 DIAGNOSTIC_NETWORK_INSTALL_JS 覆盖)。recordRequest
//         在响应回调与暂存请求配对后接线 —
//         ← Android JwDiagnosticSession.recordRequest(request, response)。
//   onReceivedSslError + SslBypassRegistry → didReceive serverTrust challenge
//         (JwWebViewNavigationDelegate 已实现: 注册域内 useCredential 放行自签,
//          其余 performDefaultHandling = 系统校验失败即拒 — 与 Android
//          proceed()/cancel() 语义对齐)。ATS 对 TLS 版本/明文限制的例外仍需
//         Info.plist — 保守不放开, 消费方接入由集成者决策。
//   doUpdateVisitedHistory / onPageFinished → didCommit / didFinish navigation
//         (JwWebViewNavigationDelegate 已实现 → onUrlChanged / onPageFinished 回调)
//   DESKTOP_VIEWPORT_JS 双注入(立即+300ms) → didFinish 内 evaluateJavaScript +
//         0.3s asyncAfter 重注入 (SO 19953717 重复注入模式, 兜底 SPA 迟挂 meta);
//         config 侧另挂 WKUserScript(.atDocumentEnd) 供仅用 config 的场景首注入。
//   CookieManager.getInstance()       → WKWebsiteDataStore.default().httpCookieStore
//         (async API; 工厂期捕获 store 引用, callback 体内只读该引用)
//
// ## 生命周期
// 装配完成后 delegate 不额外持有 webView 引用(回调形参临时传递, 不存字段 —
// ← Android JwWebViewClientImpl 同不变量)。userAgent / schoolHost / cookieStore
// 都是 immutable 引用, 无 GC/线程问题(WKWebView 所有 delegate 回调本身就在主线程)。
//
// ## 消费方接线 (集成者, 不在本文件范围)
// WebViewCoordinator.makeWebView 应改为:
//   let (config, ctx) = JwWebViewClientBuilder.build(school:desktopMode:)
//   wv.customUserAgent = ctx.userAgent.isEmpty ? nil : ctx.userAgent
//   let delegate = JwWebViewClientBuilder.makeNavigationDelegate(
//       school: school, desktopMode: desktopUa,
//       onPageFinished: ..., onUrlChanged: ...)
//   wv.navigationDelegate = delegate        // ★ WKWebView 弱持 delegate,
//                                            //   coordinator 必须强持有该属性
//   urlObserver = delegate.observeUrlChanges(of: wv)  // pushState 型 URL 变化
// applyDesktopUserAgent(desktop:) 中必须先
//   delegate.desktopViewport = desktop      // 再 reload(顺序不可反)。
// Android 端 UA 切换 = key(recreateKey) 销毁重建 WebView+client, desktopViewport
// 恒等于当前 desktopMode; iOS 原地 reload 不重建 delegate, 若标志停留在构造期
// false, 「手机模式打开 → 切桌面」主路径就复现 2026-09-13 修掉的 viewport 缺失。

import Foundation
import WebKit

/// 拦截器上下文 — 工厂期(主线程)一次性捕获的平台资源。
/// (← Android JwInterceptorContext; cookieManager 类型换成 WKHTTPCookieStore)
struct JwInterceptorContext {
    /// 生效 UA 快照 — desktopMode 时为 desktopUserAgent; 默认手机 UA 时 WKWebView
    /// 无公开同步读 UA 的 API, 以空串表示「平台默认」(消费方 customUserAgent = nil)。
    /// (← Android webView.settings.userAgentString 工厂期一次捕获; 差异已在语义注释)
    let userAgent: String
    /// WKWebsiteDataStore.default().httpCookieStore — 主线程捕获的共享单例引用
    let cookieStore: WKHTTPCookieStore
    /// school.url 提取的 host(工厂期解析, callback 内不再碰 webView.url)
    let schoolHost: String
}

/// WebViewClient 装配器 — iOS 对应产出 WKWebViewConfiguration + WKWebView 现场配置。
/// (object → enum: 无状态纯装配)
enum JwWebViewClientBuilder {

    /// 装配 WKWebViewConfiguration, 配套给即将创建的 WKWebView。
    ///
    /// - Parameters:
    ///   - school: 学校信息 — 决定 interceptor 装配 + 提取 schoolHost。
    ///   - desktopMode: 桌面 UA 模式 (issue #18 PCUA)。true 时附加 viewport 覆盖
    ///     WKUserScript(钉布局宽 1024px, 触发 Bootstrap 桌面分支 — UA 字符串本身
    ///     对布局零影响)。全协议启用(2026-09-13 Android 侧同步决策: 只换 UA 不注
    ///     viewport 时非 UCAS 校切换毫无反应)。
    ///   - messageHandlerName: JS 桥名(默认 __sleepyBridge, 桥接约定)。
    /// - Returns: 已完成全部静态配置(桥/UA/脚本)的 configuration + ctx。
    static func build(
        school: JwSchoolInfo,
        desktopMode: Bool = false,
        messageHandlerName: String = "__sleepyBridge"
    ) -> (config: WKWebViewConfiguration, ctx: JwInterceptorContext) {
        let config = WKWebViewConfiguration()

        // 主线程读: WKWebView 无同步读当前 UA 的公开 API — 桌面模式取本装配器
        // 预备的 desktopUserAgent, 默认模式记空串(= 平台 UA)。★ 生效杠杆是
        // WKWebView.customUserAgent(与登录屏 applyDesktopUserAgent 同一机制);
        // 不能写 applicationNameForUserAgent — 那是拼在默认 UA 尾部的后缀,
        // 最终 UA 仍含 iPhone/Mobile, 门户照旧返回移动版 (v1.0.60 漂移修复)。
        let userAgent = desktopMode ? JwWebViewClientBuilder.desktopUserAgent : ""
        let schoolHost = host(of: school.url)
        let ctx = JwInterceptorContext(
            userAgent: userAgent,
            cookieStore: WKWebsiteDataStore.default().httpCookieStore,
            schoolHost: schoolHost
        )

        let prefs = WKPreferences()
        prefs.javaScriptCanOpenWindowsAutomatically = true
        config.preferences = prefs

        // 桌面 viewport 覆盖全协议启用(同 Android 2026-09-13 决策):
        // 桌面 UA + 1024px 视口 = 响应式门户真正切桌面分支。
        // WKUserScript atDocumentEnd = 首注入; SPA 迟挂 meta 的兜底重注入由
        // makeNavigationDelegate 产出的 delegate 在 didFinish 双注入完成
        // (← Android onPageFinished 立即 + postDelayed 300ms)。
        if desktopMode {
            config.userContentController.addUserScript(WKUserScript(
                source: desktopViewportJs,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true))
        }
        _ = messageHandlerName  // ScriptMessageHandler 注册由持有 WKScriptMessageHandler
                                // 的 coordinator 完成(config 不持 handler 引用,
                                // 避免环; 见 JwWebViewLoginScreen.WebViewCoordinator)
        return (config, ctx)
    }

    /// 装配导航 delegate — ← Android build(...) 返回的 JwWebViewClientImpl。
    /// 覆盖 onPageFinished/onUrlChanged 回调、桌面 viewport 双注入、主框架诊断
    /// 记录、SSL 注册域豁免。callback 体内禁止触碰 webView 的 main-thread-only
    /// 现场读取, 全部走 ctx 快照(← JwWebViewCallbackThreadAffinenessTest 不变量)。
    static func makeNavigationDelegate(
        school: JwSchoolInfo,
        desktopMode: Bool = false,
        onPageFinished: @escaping (String?) -> Void = { _ in },
        onUrlChanged: @escaping (String?) -> Void = { _ in }
    ) -> JwWebViewNavigationDelegate {
        let schoolHost = host(of: school.url)
        let ctx = JwInterceptorContext(
            userAgent: desktopMode ? desktopUserAgent : "",
            cookieStore: WKWebsiteDataStore.default().httpCookieStore,
            schoolHost: schoolHost
        )
        _ = assembleInterceptors(school)  // 装配点保留(见函数注释), iOS 当前无逐请求改写
        return JwWebViewNavigationDelegate(
            ctx: ctx,
            desktopViewport: desktopMode,  // ← Android val desktopViewport = desktopMode
            onPageFinished: onPageFinished,
            onUrlChanged: onUrlChanged
        )
    }

    /// 按 school 协议族装配拦截器链。当前 Android 侧只挂 SEP XRW 剥离 (UCAS #18) —
    /// iOS 无 chromium 强注 XRW 头的根因, 链为空但保留结构: 新协议在这里加一行即可。
    /// (← assembleInterceptors; 返回 UA 覆盖建议而非 response 改写器)
    static func assembleInterceptors(_ school: JwSchoolInfo) -> [String] {
        var list: [String] = []
        // UCAS #18: Android SEP SSO 域 (sep.ucas.ac.cn) 剥 X-Requested-With;
        // iOS WKWebView 不强注该头, 无操作。保留分支注释作装配点。
        if school.url.lowercased().contains(UCAS_DOMAIN) {
            // list.append(...) — 未来 iOS 特有协议问题在此装配
        }
        return list
    }

    /// school.url → host(工厂期一次性解析)。(← school.url.toUri().host)
    static func host(of url: String) -> String {
        guard let u = URL(string: url) else { return "" }
        return u.host ?? ""
    }

    /// ← DESKTOP_USER_AGENT (JwWebViewLoginScreen.kt): Chrome 121 / Windows 10
    /// 桌面 UA — 无 Android/iPhone 词汇, 触发门户桌面版布局。
    /// (登录屏 jwDesktopUserAgent 为 private; 此处独立常量, 值逐字一致)
    static let desktopUserAgent =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) " +
        "Chrome/121.0.0.0 Safari/537.36"

    /// ← DESKTOP_VIEWPORT_JS: meta viewport 钉 1024px + 回顶。
    /// (与 Android JwWebViewLoginScreen.kt 顶部常量逐字一致)
    static let desktopViewportJs =
        "(function(){var m=document.querySelector('meta[name=\"viewport\"]');" +
        "if(m){m.setAttribute('content','width=1024');}" +
        "else{m=document.createElement('meta');m.setAttribute('name','viewport');" +
        "m.setAttribute('content','width=1024');document.head.appendChild(m);}" +
        "setTimeout(function(){window.scrollTo(0,0);},0);})()"

    /// 桌面 viewport 双注入 — ← Android JwWebViewClientImpl.onPageFinished:
    ///   view?.evaluateJavascript(DESKTOP_VIEWPORT_JS) + postDelayed 同 JS 300ms。
    /// chromium/Safari 对 meta 变更的重排时机不定(SO 19953717 重复注入模式),
    /// 第二次兜底 SPA 迟挂的 meta 重写。JS 幂等(设同一 content 值), 注入多次无副作用。
    static func injectDesktopViewport(into webView: WKWebView) {
        webView.evaluateJavaScript(desktopViewportJs, completionHandler: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak webView] in
            guard let webView else { return }
            webView.evaluateJavaScript(desktopViewportJs, completionHandler: nil)
        }
    }

    private static let UCAS_DOMAIN = "ucas.ac.cn"
}

// MARK: - 导航 delegate (← JwWebViewClientImpl, 装配产物)

/// 装配出的导航代理。callback 体内**禁止**触碰 webView.settings / webView 现场状态
/// 读取 — ctx 快照是唯一数据源(← Android checkThread 架构边界, WK 侧等价约束:
/// 回调期读 webView.url 允许但统一走回调参数, 与 Android 传 url 语义一致)。
final class JwWebViewNavigationDelegate: NSObject, WKNavigationDelegate {

    let ctx: JwInterceptorContext
    /// 桌面 viewport 双注入开关。**运行时可翻转** — Android 端 UA 切换 =
    /// key(recreateKey) 销毁重建整棵 WebView+client, desktopViewport 恒与当前
    /// desktopMode 一致; iOS 端 applyDesktopUserAgent 是 customUserAgent + reload
    /// 原地切换(不重建 delegate), 若此处不可变, 「手机模式打开 → 切桌面」后
    /// didFinish 永不注入 viewport = 2026-09-13 修掉的 bug 经接线复现。
    /// 消费方契约: 先 set 本标志, 再 reload(顺序不可反, ← didCommit/didFinish 触发)。
    var desktopViewport: Bool
    private let onPageFinished: (String?) -> Void
    private let onUrlChanged: (String?) -> Void

    /// 请求侧暂存(decidePolicyFor navAction 写, navResponse 读后即清)。
    struct WKStashedRequest {
        let method: String
        let url: String
        let requestHeaders: [String: String]?
        let isMainFrame: Bool
    }
    // WKNavigationDelegate 回调全部在主线程串行, 无需额外加锁; 有界防泄漏。
    private var stashedRequests: [String: WKStashedRequest] = [:]
    private var lastStashed: WKStashedRequest?

    /// 暂存请求侧, 以 URL 绝对串为键(导航栈里 redirect 各跳 URL 互不相同)。
    func stashRequest(_ req: WKStashedRequest) {
        if stashedRequests.count > 64 { stashedRequests.removeAll() }
        stashedRequests[req.url] = req
        lastStashed = req
    }

    /// 响应回调取配对请求: 精确 URL 命中 → 取并删; 未命中 → 回退最近一次暂存
    /// (仅当它尚未被消费)。← Android shouldInterceptRequest 的 request↔response 配对。
    func takeStashedRequest(matching url: String) -> WKStashedRequest? {
        if let hit = stashedRequests[url] {
            stashedRequests[url] = nil
            if lastStashed?.url == url { lastStashed = nil }
            return hit
        }
        let fallback = lastStashed
        lastStashed = nil
        return fallback
    }

    init(ctx: JwInterceptorContext,
         desktopViewport: Bool,
         onPageFinished: @escaping (String?) -> Void,
         onUrlChanged: @escaping (String?) -> Void) {
        self.ctx = ctx
        self.desktopViewport = desktopViewport
        self.onPageFinished = onPageFinished
        self.onUrlChanged = onUrlChanged
        super.init()
    }

    /// 主框架导航请求侧 → 暂存请求字段 + 放行。
    /// ← Android shouldInterceptRequest 同时拿到 request 与 response;
    /// WKNavigationDelegate 把两者拆成 decidePolicyFor(navAction) 与
    /// decidePolicyFor(navResponse) 两次回调, 这里先存请求侧, 响应回调配对后
    /// 一次性 recordRequest, 避免半截记录/重复记录。
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url {
            stashRequest(WKStashedRequest(
                method: navigationAction.request.httpMethod ?? "GET",
                url: url.absoluteString,
                requestHeaders: navigationAction.request.allHTTPHeaderFields,
                isMainFrame: navigationAction.targetFrame?.isMainFrame ?? true))
        }
        decisionHandler(.allow)
    }

    /// 主框架导航响应侧 → 与暂存请求配对后记录诊断 + 放行。
    /// ← Android shouldInterceptRequest 的 JwDiagnosticSession.recordRequest。
    /// 平台差异: WKWebView 只暴露主框架导航(子资源不可见, 无同步拦截点);
    /// fetch/XHR 层的逐请求证据由登录屏 DIAGNOSTIC_NETWORK_INSTALL_JS 补齐。
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        let http = navigationResponse.response as? HTTPURLResponse
        let responseURL = navigationResponse.response.url?.absoluteString ?? ""
        // 重定向链下响应 URL ≠ 请求 URL: 先精确配对, 取不到退回「最近一次暂存」
        // (同一导航在 redirect 后仍只产生一个最终响应回调), 再取不到 = 纯 GET 兜底。
        let stashed = takeStashedRequest(matching: responseURL)
        JwDiagnosticSession.shared.recordRequest(
            method: stashed?.method ?? "GET",
            url: stashed?.url ?? responseURL,
            // Android: response==null → -1。iOS 此处必有 response, 非 HTTP 响应记 -1 对齐
            status: http?.statusCode ?? -1,
            // ← WebResourceResponse.mimeType: iOS 侧同义取 Content-Type 头
            mime: http?.value(forHTTPHeaderField: "Content-Type"),
            requestHeaders: stashed?.requestHeaders,
            // allHeaderFields 是 [AnyHashable: Any] — 折叠成 [String: String]
            // (← Android response.responseHeaders Map<String,String>)
            responseHeaders: http.map { r in
                var out: [String: String] = [:]
                for (k, v) in r.allHeaderFields {
                    if let ks = k as? String { out[ks] = String(describing: v) }
                }
                return out
            },
            // WKNavigationAction 无 isRedirect 标志, 用 3xx 状态码近似
            isRedirect: (300..<400).contains(http?.statusCode ?? 0),
            isMainFrame: navigationResponse.isForMainFrame
        )
        decisionHandler(.allow)
    }

    /// 导航提交 = Android doUpdateVisitedHistory(历史更新) → onUrlChanged。
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        onUrlChanged(webView.url?.absoluteString)
    }

    /// SPA pushState/replaceState 型 URL 变化 = Android doUpdateVisitedHistory 的
    /// 全语义覆盖 — didCommit/didFinish 只在整页导航触发, 前端路由改历史不回调它们。
    /// 消费方(coordinator)接线时调用并**持有**返回的 observation, 销毁时释放。
    func observeUrlChanges(of webView: WKWebView) -> NSKeyValueObservation {
        webView.observe(\.url, options: [.new]) { [weak self] wv, _ in
            self?.onUrlChanged(wv.url?.absoluteString)
        }
    }

    /// 页面加载完成 = Android onPageFinished → 回调 + 桌面 viewport 双注入。
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let url = webView.url?.absoluteString
        onPageFinished(url)
        onUrlChanged(url)
        // issue #18 PCUA → 2026-09-13 全协议: 桌面模式钉 1024px 布局视口,
        // 触发 @media(min-width:980px) 桌面分支。UA 字符串对响应式布局零影响,
        // viewport 是唯一杠杆。didFinish 在主线程, evaluateJavaScript 约束满足。
        if desktopViewport, url != nil {
            JwWebViewClientBuilder.injectDesktopViewport(into: webView)
        }
    }

    /// SSL 豁免 — ← Android onReceivedSslError(error.url.host 判定注册域)。
    /// 注册域内(私签/私有 CA 教务) → useCredential 放行;
    /// 其余 → performDefaultHandling(= 系统信任链校验, 失败即拒 — 中间人防护,
    /// 对应 Android 默认 cancel)。TLS 版本/明文类 ATS 限制仍需 Info.plist 例外。
    func webView(_ webView: WKWebView,
                 didReceive challenge: URLAuthenticationChallenge,
                 completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            // 非 serverTrust(如账号密码质询) → 交回默认处理
            completionHandler(.performDefaultHandling, nil)
            return
        }
        // 用 protectionSpace.host(回调参数), 不读 webView.url — 同 Android 用
        // error.url 而非 view.url 的线程亲和约束
        if SslBypassRegistry.isAllowed(host: challenge.protectionSpace.host,
                                       schoolHost: ctx.schoolHost) {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

// MARK: - SSL 豁免注册表 (← SslBypassRegistry, JwWebViewLoginScreen.kt 2115)
//
// 仅对学校 URL 的注册域 (含其子域) 放行自签/私有 CA 证书 —
// 部分高校教务确用私有 CA。除此之外的 SSL 错误一律 cancel (中间人防护)。
//
// iOS 消费点: JwWebViewNavigationDelegate.webView(_:didReceive:challenge:)
// 的 serverTrust 分支 — 注册域内 useCredential(forTrust:) 即 Android
// handler.proceed() 的等价; TLS 握手层之外的 ATS 限制仍需 Info.plist 例外。
// 纯逻辑, 单测可直跑 (SleepyTests/JwWebViewConfigBuilderTests)。

enum SslBypassRegistry {

    /// 取注册域: 无公共后缀库, 用启发式 — 取末两段 (xx.edu.cn 形态取末三段)。
    /// 剥离序列逐字对齐 Android `host.lowercase().trim().trimEnd('.')`:
    /// 先两侧剥空白, 再尾部剥任意个 '.'(前导点保留 — 与 Android 同语义,
    /// 三段后缀形态下 takeLast(3) 结果一致)。
    static func registrableDomain(_ host: String) -> String {
        var h = host.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)[...]
        while h.last == "." { h = h.dropLast() }
        let stripped = String(h)
        if stripped.isEmpty { return "" }
        let parts = stripped.components(separatedBy: ".")
        if parts.count <= 2 { return stripped }
        let secondLevel = parts[parts.count - 2]
        // 多段公共后缀 (edu.cn / edu.hk / ac.uk 等): 公共后缀 + 域名 = 末三段
        let tld = parts.last ?? ""
        if (tld == "cn" || tld == "hk" || tld == "uk" || tld == "tw" || tld == "jp"),
           ["edu", "ac", "gov", "org"].contains(secondLevel) {
            return parts.suffix(3).joined(separator: ".")
        }
        return parts.suffix(2).joined(separator: ".")
    }

    /// host 是否与 schoolHost 同注册域 (或为其子域)。
    /// 空白判定对齐 Kotlin isBlank()(URL 解析产出的 host 不含奇异 Unicode 空白,
    /// whitespacesAndNewlines 覆盖实际可达输入)。
    static func isAllowed(host: String, schoolHost: String) -> Bool {
        if host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || schoolHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        return registrableDomain(host) == registrableDomain(schoolHost)
    }
}
