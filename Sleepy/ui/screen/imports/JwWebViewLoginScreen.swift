// JwWebViewLoginScreen.swift — ← ui/screen/imports/JwWebViewLoginScreen.kt (v1.0.61, 2514 行)
// 教务 WebView 登录页。
// 原版本 WebView+JS 桥 → WKWebView + WKScriptMessageHandler:
//   - loadUrl("javascript:") → evaluateJavaScript(直接回调, 无需桥)
//   - addJavascriptInterface(__sleepyBridge) → WKScriptMessageHandler(name: "__sleepyBridge")
//   - SSL 自签 proceed → didReceive serverTrust challenge (JwWebViewNavigationDelegate
//     已实现注册域豁免; 本屏 coordinator 走同一 SslBypassRegistry? — 见 coordinator 注释)
//   - 新窗(target=_blank/window.open) → NavUIDelegate.createWebViewWith 在当前
//     webview 内加载(原版本 WebView 默认语义); 无它教务卡片点不动(a.v.1.0.41)
//   - 桌面 UA 切换(#18) → TopBar 原生按钮: customUserAgent + reload + 每跳注入
//     DESKTOP_VIEWPORT_JS(布局由 meta viewport 宽度驱动, UA 字符串对布局零影响 —
//     2026-09-13 实锤; ← 原 onPageFinished 注入)
//   - 刷新 → TopBar 原生按钮 webView.reload(), 进度走 estimatedProgress KVO
//   - 浏览器式地址栏(← editingUrl/urlDraft/submitUrl): http/https 白名单挡
//     javascript: 注入 + 无 scheme 自动补 https:// + ImeAction.Go 等价 submitLabel(.go)
// 抓 HTML: 默认路径 = captureWithRetry(CAPTURE_FRAMES_JS DFS 深度8 → selectBestFrame →
//   RenderReadinessChecker 1500ms×3 重试), 状态路由 SESSION_EXPIRED/WRONG_PAGE/
//   CROSS_DOMAIN_IFRAME_BLOCKED/IFRAME_NAV_PENDING/CONTAINER_EMPTY_AFTER_DELAY 走
//   onCaptureError(避免伪"0 课"), OK/EMPTY_SEMESTER 才 onHtmlCaptured。
// wisedu(金智) 协议: WebView 内 fetch 课表 JSON(WISEDU_FETCH_JS 原文移植)。
// fetch 派发全部过 20s 超时闸(evaluateFetchWithTimeout, 禁无限 pending)。
// 诊断接线: __sleepyNetworkBridge + DIAGNOSTIC_NETWORK_INSTALL_JS 每跳重装 +
//   console 桥 + 下载字节有界采集(2MB 上限, Cookie 回放) → JwDiagnosticSession。

import SwiftUI
import WebKit

// ← DESKTOP_USER_AGENT: Chrome 121 / Windows 10 桌面 UA — 无 原版本/iPhone 词汇,
// 触发门户桌面版布局(UCAS SEP 等门户手机 UA 下无"个人课表"入口)
private let jwDesktopUserAgent =
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) " +
    "Chrome/121.0.0.0 Safari/537.36"

// ← FETCH_TIMEOUT_MS = 20_000L: fetch JS 注入超时闸 — 教务宕机时 20s 无 evaluate
// 回调即报超时, 禁无限 pending。
private let jwFetchTimeoutSeconds: Double = 20

// ← WebVPN 重写形态指纹 "/http/<hex>/" (原 Regex 原文, 大小写敏感同 原版本)
private let jwWebvpnHexRegex = try! NSRegularExpression(pattern: #"/http/[0-9a-f]{4,8}/"#)

/// ← evaluateFetchWithTimeout 的 answered 标志盒 (Swift 局部可变捕获需引用盒)。
private final class JwTimeoutGate {
    var answered = false
}

/// console 桥注入 JS — iOS 平台等价物: WKWebView 无 原版本 WebChromeClient.
/// onConsoleMessage 公开回调, 以 JS shim 包 console.log/info/warn/error →
/// postMessage 到 __sleepyConsole → coordinator 转 JwDiagnosticSession.recordConsole。
/// (recordConsole(msg) 接线; level/sourceId 语义一一对应)
let jwConsoleShimJs = """
(function(){
  if (window.__sleepyConsoleInstalled) return;
  window.__sleepyConsoleInstalled = true;
  var fns = ['log','info','warn','error'];
  var orig = {};
  fns.forEach(function(fn){
    orig[fn] = console[fn];
    console[fn] = function(){
      try {
        var parts = Array.prototype.slice.call(arguments).map(function(a){
          if (typeof a === 'string') return a;
          try { return JSON.stringify(a); } catch(e) { return String(a); }
        });
        window.webkit.messageHandlers.__sleepyConsole.postMessage(
          {level: fn, message: parts.join(' '), sourceId: String(location.href)});
      } catch(e) {}
      return orig[fn].apply(console, arguments);
    };
  });
})();
"""

struct JwWebViewLoginScreen: View {
    // (WISEDU_FETCH_JS 定义在文件尾 WiseduFetchJs enum; 前置引用走 static)

    @Environment(\.localWakeUpColors) private var colors
    @Environment(\.sleepyUIStyle) private var style
    let school: JwSchoolInfo
    // termStartDate ← 原版本 JwWebViewLoginScreen 第 4 回调参数: JSON 直连协议
    // (boya_pp 等) 从接口拿到的第一周周一, 供确认页开学日期预填; 无则空串
    let onHtmlCaptured: (String, JwSchoolInfo, [(Int, String, String)], String) -> Void
    var onBack: (() -> Void)? = nil
    let onDismiss: () -> Void
    // 排查包导出通道 (webViewForDump / onWebViewReady): coordinator 就绪时
    // 上抛一次, 调用方持有引做 dump JS 段 evaluate. 默认 nil — 不传 = 不启用.
    var onWebViewReady: ((WebViewCoordinator) -> Void)? = nil
    // ← 原版本 参数 onCaptureError: (FrameCaptureResult, hint) -> Unit: 状态路由/
    // 超时闸的失败通道 (Activity 弹失败对话框带排查包入口)。调用方传入即上抛;
    // 默认 nil = 本屏以 snackbar 呈现 hint (不落 onHtmlCaptured 伪"0 课")。
    // 接线对话框归集成者(JwImportFlow 侧), 见 needs_shared_wiring。
    var onCaptureError: ((FrameCaptureResult, String) -> Void)? = nil

    var selectedSgAdapterId: String = ""
    var onSgAdapterSelected: ((String) -> Void)? = nil
    @State private var chosenSgAdapterId = ""
    @State private var sgAdapterChoices: [JwSgAssetBridge.Manifest.Adapter] = []
    @State private var showSgAdapterChoices = false
    @State private var progress: Double = 0
    @State private var webViewCoordinator: WebViewCoordinator? = nil
    @State private var snackMessage: String? = nil
    // ← desktopUa = remember { mutableStateOf(false) } — 默认手机 UA。
    // 原版本 本屏无持久化(纯会话态, 离开页面即重置), iOS @State 等价
    @State private var desktopUa = false
    @State private var thuCaptureToken = UUID()
    // ← currentUrl = remember { mutableStateOf(school.url) } — 导航回调回写的实时 URL,
    // 顶栏副标题显示(title Column 第二行 Text(currentUrl))
    @State private var currentUrl: String = ""
    // ← editingUrl = remember { mutableStateOf(false) } + urlDraft
    // (rememberTextFieldState(school.url)) — 浏览器式地址栏编辑态
    @State private var editingUrl = false
    @State private var urlDraft: String = ""

    init(school: JwSchoolInfo,
         onHtmlCaptured: @escaping (String, JwSchoolInfo, [(Int, String, String)], String) -> Void,
         onBack: (() -> Void)? = nil,
         onDismiss: @escaping () -> Void,
         onWebViewReady: ((WebViewCoordinator) -> Void)? = nil,
         onCaptureError: ((FrameCaptureResult, String) -> Void)? = nil,
         selectedSgAdapterId: String = "",
         onSgAdapterSelected: ((String) -> Void)? = nil) {
        self.school = school
        self.onHtmlCaptured = onHtmlCaptured
        self.onBack = onBack
        self.onDismiss = onDismiss
        self.onWebViewReady = onWebViewReady
        self.onCaptureError = onCaptureError
        self.selectedSgAdapterId = selectedSgAdapterId
        self.onSgAdapterSelected = onSgAdapterSelected
        _chosenSgAdapterId = State(initialValue: selectedSgAdapterId)
        _desktopUa = State(initialValue: JwClassicEamsFetch.initialDesktopUa(school))
    }

    var body: some View {
        VStack(spacing: 0) {
            // TopBar(校名 + 实时 URL / 地址栏编辑态)
            HStack(spacing: 0) {
                // ← navigationIcon IconButton: editingUrl 退编辑, 否则 onBack
                Button(action: {
                    if editingUrl { editingUrl = false } else { backOrDismiss() }
                }) {
                    AndroidSettingsIcon(name: .arrowBack, size: 24)   // ← 原 ArrowBack 默认 24dp regular
                        .foregroundColor(colors.onBackground)
                        .frame(width: style == .classic ? 48 : nil,
                               height: style == .classic ? 48 : nil)
                        .contentShape(Circle())
                }
                .buttonStyle(SleepyPlatformButtonStyle(cornerRadius: 20, shape: .circle))
                .frame(width: 48, height: 48)
                .contentShape(Circle())
                .accessibilityLabel(L10n.format("back"))   // ← contentDescription = R.string.back
                // ← title: editingUrl ? OutlinedTextField(urlDraft) : Column(name, currentUrl)
                if editingUrl {
                    // ← OutlinedTextField state=urlDraft, SingleLine, placeholder=jw_url_hint,
                    //   imeAction=Go → onSubmit 触发 submitUrl()
                    TextField(L10n.format("jw_url_hint"), text: $urlDraft)
                        .font(.system(size: 16))
                        .foregroundColor(colors.onSurface)
                        .submitLabel(.go)          // ← ImeAction.Go 等价
                        .onSubmit(submitUrl)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(colors.outline, lineWidth: 1)
                        )
                        .accessibilityIdentifier("jw_url_input")
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(school.name)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(colors.onBackground)
                        // ← 原版本 顶栏副标题 = currentUrl (实时导航 URL, maxLines=1),
                        //   非协议名 (v1.0.61 对齐修正); 初始未导航时显示 school.url
                        //   (← currentUrl = remember { mutableStateOf(school.url) })
                        Text(currentUrl.isEmpty ? school.url : currentUrl)
                            .font(.system(size: 12))
                            .foregroundColor(colors.onSurfaceVariant)
                            .lineLimit(1)
                    }
                }
                Spacer()
                // ← actions Edit/Check IconButton: 进编辑态(urlDraft := currentUrl)
                //   或提交; enabled = webViewRef != null
                Button(action: {
                    if editingUrl {
                        submitUrl()
                    } else {
                        urlDraft = currentUrl
                        editingUrl = true
                    }
                }) {
                    Group {
                        if editingUrl {
                            AndroidMaterialIcon(name: .check, size: 24)
                        } else {
                            AndroidSettingsIcon(name: .edit, size: 24)
                        }
                    }   // ← M3 Icon 24dp
                        .frame(width: style == .liquidGlass ? nil : 48,
                               height: style == .liquidGlass ? nil : 48)
                        .contentShape(Circle())
                        .foregroundColor(webViewCoordinator == nil
                            ? colors.onSurface.opacity(0.38)
                            : colors.onBackground)
                }
                .buttonStyle(SleepyPlatformButtonStyle(cornerRadius: 20, shape: .circle))
                .frame(width: 48, height: 48)
                .contentShape(Circle())
                .disabled(webViewCoordinator == nil)
                .accessibilityLabel(L10n.format(editingUrl ? "jw_url_submit" : "jw_edit_url"))
                .accessibilityIdentifier("jw_edit_url")
                if !editingUrl {
                    if sgAdapterChoices.count > 1 {
                        Button { showSgAdapterChoices = true } label: {
                            AndroidSettingsIcon(name: .school, size: 24)
                                .foregroundColor(colors.onBackground)
                                .frame(width: style == .classic ? 48 : nil,
                                       height: style == .classic ? 48 : nil)
                        }
                        .buttonStyle(SleepyPlatformButtonStyle(cornerRadius: 20, shape: .circle))
                        .frame(width: 48, height: 48)
                        .disabled(webViewCoordinator == nil)
                        .accessibilityLabel(L10n.t("jw_sg_choose_adapter"))
                        .accessibilityIdentifier("jw_select_adapter")
                    }
                    // ← actions UA IconButton(#18): 部分门户手机 UA 下无"个人课表"入口。
                    // 图标随状态切换: 手机 UA → Computer(点了变桌面), 桌面 UA → PhoneMobile
                    // (点了回手机); enabled = webViewRef != null
                    Button(action: toggleDesktopUa) {
                        AndroidSettingsIcon(name: desktopUa ? .phoneAndroid : .computer, size: 24)   // ← M3 Icon 24dp
                            .frame(width: style == .liquidGlass ? nil : 48,
                                   height: style == .liquidGlass ? nil : 48)
                            .contentShape(Circle())
                            .foregroundColor(webViewCoordinator == nil
                                ? colors.onSurface.opacity(0.38)   // ← disabled: onSurface 38%
                                : colors.onBackground)   // ← actionIconContentColor
                    }
                    .buttonStyle(SleepyPlatformButtonStyle(cornerRadius: 20, shape: .circle))
                    .frame(width: 48, height: 48)
                    .contentShape(Circle())
                    .disabled(webViewCoordinator == nil)
                    // ← contentDescription: jw_toggle_mobile_ua / jw_toggle_desktop_ua
                    .accessibilityLabel(L10n.format(desktopUa ? "jw_toggle_mobile_ua"
                                                              : "jw_toggle_desktop_ua"))
                    .accessibilityIdentifier("jw_toggle_ua")
                    // ← actions 刷新 IconButton: webViewRef?.reload(); 刷新进度表现由
                    // estimatedProgress KVO 驱动上方进度条(原 progress 1..99 同判)
                    Button(action: { webViewCoordinator?.reload() }) {
                        AndroidSettingsIcon(name: .refresh, size: 24)   // ← Icons.Outlined.Refresh
                            .frame(width: style == .liquidGlass ? nil : 48,
                                   height: style == .liquidGlass ? nil : 48)
                            .contentShape(Circle())
                            .foregroundColor(webViewCoordinator == nil
                                ? colors.onSurface.opacity(0.38)
                                : colors.onBackground)
                    }
                    .buttonStyle(SleepyPlatformButtonStyle(cornerRadius: 20, shape: .circle))
                    .frame(width: 48, height: 48)
                    .contentShape(Circle())
                    .disabled(webViewCoordinator == nil)
                    .accessibilityLabel(L10n.format("jw_refresh"))   // ← contentDescription
                    .accessibilityIdentifier("jw_refresh")
                }
            }
            .padding(.horizontal, 4)
            .frame(height: 64)
            .background(colors.background)

            ZStack(alignment: .top) {
                JwWebView(
                    url: school.url.isEmpty ? "https://www.baidu.com" : school.url,
                    school: school,
                    desktopUa: desktopUa,
                    onProgressChange: { p in progress = p },
                    // ← onNavigationUrlChanged: !editingUrl 时回写 currentUrl
                    //   (编辑态不覆盖用户正在输入的草稿)
                    onUrlChanged: { url in
                        thuCaptureToken = UUID()
                        if !editingUrl, let url = url, !url.isEmpty { currentUrl = url }
                    },
                    onCoordinatorCreated: { coordinator in
                        webViewCoordinator = coordinator
                        currentUrl = coordinator.currentURLString ?? school.url
                        prepareSgAdapter(coordinator)
                        onWebViewReady?(coordinator)   // 排查包导出通道 (dump JS 段引)
                    },
                    onHtmlCaptured: { html in onHtmlCaptured(html, school, [], "") },
                    // ← onCaptureError 通道: FrameCaptureResult 状态路由的失败上抛
                    onCaptureError: showCaptureError,
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
                    Text(JwCaptureGuidance.navigationHint(for: school.type))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colors.onSurface)
                }
                Spacer()
                Button(action: capture) {
                    HStack(spacing: 6) {
                        AndroidSettingsIcon(name: .checkCircle, size: 24)   // ← 原 CheckCircle 默认 24dp
                        Text(L10n.format("jw_import_page"))
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(webViewCoordinator == nil
                        ? colors.onSurface.opacity(0.38)   // ← 原 disabled: onSurface 38%
                        : colors.onPrimary)
                    .padding(.horizontal, style == .liquidGlass ? 0 : 24)   // ← M3 Button ContentPadding 24/8 (高 40)
                    .padding(.vertical, style == .liquidGlass ? 0 : 8)
                    .sleepyControlSurface(cornerRadius: SleepyShapes.extraLarge,
                        tint: webViewCoordinator == nil ? colors.onSurface.opacity(0.12) : colors.primary,
                        prominent: true)
                }
                .buttonStyle(SleepyPlatformButtonStyle(prominent: true, cornerRadius: SleepyShapes.extraLarge))
                .frame(minHeight: style == .liquidGlass ? 44 : nil)
                .tint(webViewCoordinator == nil ? colors.onSurface.opacity(0.12) : colors.primary)
                .disabled(webViewCoordinator == nil)   // ← 原 enabled = webViewRef != null
            }
            .padding(16)
            .background(colors.surface)
        }
        .confirmationDialog(L10n.t("jw_sg_choose_adapter"), isPresented: $showSgAdapterChoices, titleVisibility: .visible) {
            ForEach(sgAdapterChoices) { adapter in
                Button((adapter.adapterName?.isEmpty == false ? adapter.adapterName! : adapter.id) + " · " + adapter.importUrl) {
                    thuCaptureToken = UUID()
                    webViewCoordinator?.cancelFetch()
                    chosenSgAdapterId = adapter.id
                    onSgAdapterSelected?(adapter.id)
                    if let url = URL(string: adapter.importUrl), ["http", "https"].contains(url.scheme ?? "") {
                        webViewCoordinator?.webView?.load(URLRequest(url: url))
                    }
                }
            }
            Button(L10n.t("cancel"), role: .cancel) {}
        }
        .onDisappear { thuCaptureToken = UUID(); webViewCoordinator?.cancelFetch() }
        .overlay(alignment: .bottom) {
            if let msg = snackMessage {
                Text(msg)
                    .font(.system(size: 14)) // ← 原 Snackbar bodyMedium 14
                    .foregroundColor(colors.onSurface)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(colors.surfaceContainerHighest)
                    .cornerRadius(8)
                    .padding(.bottom, 80)
                    .task(id: msg) {
                        // ← M3 SnackbarDuration.Short ≈ 4s (原版本 默认系统时长);
                        //   旧自造 2.5s 漂移修正 (F083 UI 细节项)
                        try? await Task.sleep(nanoseconds: 4_000_000_000)
                        guard !Task.isCancelled else { return }
                        withAnimation { snackMessage = nil }
                    }
            }
        }
    }

    // ← BackHandler: editingUrl 退编辑 → wv.canGoBack() ? goBack() : onBack()
    // (网页历史优先, 再退屏)。chevron 与系统返回共用本入口。
    private func backOrDismiss() {
        if editingUrl {
            editingUrl = false
            return
        }
        if let coordinator = webViewCoordinator, coordinator.canGoBack {
            coordinator.goBack()
        } else if let onBack {
            onBack()
        } else {
            onDismiss()
        }
    }

    // 浏览器式地址栏: 校验 + 规范化 + 提交导航 (← submitUrl)。
    // ① 仅 http/https 放行 — 挡 javascript: 注入;
    // ② 无 scheme 自动补 https://, 与浏览器地址栏惯例一致;
    // ③ 提交后立即退出编辑态 — currentUrl 由导航回调回写, 不手工猜 URL。
    private func submitUrl() {
        let raw = urlDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return }
        let lower = raw.lowercased()
        let normalized = (lower.hasPrefix("http://") || lower.hasPrefix("https://"))
            ? raw : "https://\(raw)"
        guard let uri = URL(string: normalized),
              let scheme = uri.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              let host = uri.host, !host.isEmpty else {
            snackMessage = L10n.format("jw_url_invalid")
            return
        }
        editingUrl = false
        webViewCoordinator?.loadURL(normalized)
    }

    // ← onCaptureError 通道: FrameCaptureResult 状态路由失败的展示出口。
    // 原版本 把 (result, hint) 上抛给 Activity 弹失败对话框(带排查包入口);
    // iOS 调用方(JwImportFlow)传入 onCaptureError 即原样上抛; 未传时以 snackbar
    // 呈现 hint, 避免伪"0 课"落库。对话框接线需求见 needs_shared_wiring。
    private func showCaptureError(_ result: FrameCaptureResult, _ hint: String) {
        if let onCaptureError {
            onCaptureError(result, hint)
        } else {
            snackMessage = hint
        }
    }

    // ← actions UA IconButton onClick: desktopUa = !desktopUa; uaSwitchReload++。
    // 原版本 因 UA 仅创建期可靠而销毁重建 WebView(cookie 全局共享、当前 URL 保留);
    // iOS 等价 customUserAgent(对 reload/后续导航生效)+ reload — cookie 走默认共享
    // WKWebsiteDataStore。先设 delegate desktopViewport 标志再 reload, 顺序不可反
    // (← JwWebViewConfigBuilder 消费方契约: didFinish 注入时机在 reload 之后)
    private func toggleDesktopUa() {
        guard webViewCoordinator != nil else { return }
        desktopUa.toggle()
        webViewCoordinator?.applyDesktopUserAgent(desktopUa)
    }

    // ← CaptureBar onCapture: 派发全协议; fetch JS 一律过 20s 超时闸
    // (evaluateFetchWithTimeout, 禁无限 pending — 教务宕机时桥回调永不到达)。
    private func prepareSgAdapter(_ coordinator: WebViewCoordinator) {
        guard school.type == JwProtocol.TYPE_SG_ASSET else { return }
        do {
            let choices = try JwSgAssetBridge.entries(schoolName: school.name)
            sgAdapterChoices = choices
            if let restored = JwSgAssetBridge.restoreChoice(choices, savedId: chosenSgAdapterId) {
                chosenSgAdapterId = restored.id
                onSgAdapterSelected?(restored.id)
                if let url = URL(string: restored.importUrl), ["http", "https"].contains(url.scheme ?? "") {
                    coordinator.webView?.load(URLRequest(url: url))
                }
            } else { showSgAdapterChoices = true }
        } catch { snackMessage = error.localizedDescription }
    }

    private func capture() {
        guard let coordinator = webViewCoordinator else {
            // ← 原版本 webViewRef==null 分支走 onCaptureError(webviewNotReadyMsg)
            showCaptureError(FrameCaptureResult(selectedFramePath: nil, html: "",
                                                matchedAnchors: [], status: .unknown),
                             L10n.format("jw_webview_not_ready"))
            return
        }
        snackMessage = L10n.format("jw_fetching")
        let pageCaptureToken = UUID()
        thuCaptureToken = pageCaptureToken
        let fetchURL = coordinator.currentURLString ?? ""
        if let capture = Jw1064CaptureScripts.selection(type: school.type, currentUrl: fetchURL) {
            coordinator.evaluateFetchWithTimeout(capture.script, timeout: capture.timeout)
            return
        }
        if school.type == JwProtocol.TYPE_SG_ASSET {
            do {
                guard JwSgAssetBridge.restoreChoice(sgAdapterChoices, savedId: chosenSgAdapterId) != nil else {
                    showSgAdapterChoices = true; return
                }
                let id = UUID().uuidString
                coordinator.evaluateFetchWithTimeout(try JwSgAssetBridge.bridgeJs(schoolName: school.name,
                    selectedAdapterId: chosenSgAdapterId, sessionId: id), timeout: 120, captureId: id)
            } catch {
                showCaptureError(FrameCaptureResult(selectedFramePath: nil, html: "",
                    matchedAnchors: [], status: .unknown), error.localizedDescription)
            }
            return
        }
        if school.type == JwProtocol.TYPE_CLASSIC_EAMS {
            coordinator.evaluateFetchWithTimeout(JwClassicEamsFetch.js)
            return
        }
        // wisedu (金智 jwapp): 课表数据在 JSON API 不在页面 HTML, fetch 拿 JSON(结果走 JS 桥回调)
        if school.type == JwProtocol.TYPE_WISEDU {
            coordinator.evaluateFetchWithTimeout(WiseduFetchJs.js)
            return
        }
        // 东北大学新版金智教务: 课表只在 homeapp mobile JSON API 中
        if school.type == JwProtocol.TYPE_NEU {
            coordinator.evaluateFetchWithTimeout(NeuFetchJs.js); return
        }
        if let script = JwSeuFetchJs.script(for: school.type) {
            coordinator.evaluateFetchWithTimeout(script); return
        }
        if school.type == JwProtocol.TYPE_NUIT {
            coordinator.evaluateFetchWithTimeout(NuitFetchJs.js); return
        }
        if school.type == JwProtocol.TYPE_KUST {
            coordinator.evaluateFetchWithTimeout(KustFetchJs.js); return
        }
        // SWJTU YETHAN 逐专平台: CAS 登录后从 localStorage 取 ytoken, 同源 GET 课表 JSON
        if school.type == JwProtocol.TYPE_YETHAN {
            coordinator.evaluateFetchWithTimeout(YethanFetchJs.js); return
        }
        // CQU(重庆大学门户): 同走 JS 桥 fetch 四个 REST API, Bearer token 取自 localStorage
        if school.type == JwProtocol.TYPE_CQU {
            coordinator.evaluateFetchWithTimeout(CquFetchJs.js); return
        }
        // 新青果 NTSS: 下钻 frame + getCalendarWeekDatas 全学期单请求, envelope 透传 JwCfNewParser
        if school.type == JwProtocol.TYPE_CF_NEW {
            coordinator.evaluateFetchWithTimeout(CfNewFetchJs.js); return
        }
        // WHUT(武汉理工): 金智 jwapp 变体 — kcbcxby 微应用三段 fetch
        if school.type == JwProtocol.TYPE_WHUT {
            coordinator.evaluateFetchWithTimeout(WhutFetchJs.js); return
        }
        // 超星综合教务: getMenuList 取学期 → queryKbForGrdb 个人课表 → getZclistByXnxq 节次
        if school.type == JwProtocol.TYPE_CHAOXING {
            coordinator.evaluateFetchWithTimeout(ChaoxingFetchJs.js); return
        }
        // 博雅研究生平台 (/pp/ 前端): term 列表取学期+开学日 → setting/current 节次 → 逐周排课行
        if school.type == JwProtocol.TYPE_BOYA_PP {
            coordinator.evaluateFetchWithTimeout(BoyaPpFetchJs.js); return
        }
        // 强智移动教务 SPA: serverconfig.json 发现 ApiUrl → sessionStorage.Token 逐周抓课表
        if school.type == JwProtocol.TYPE_QZ_APP {
            coordinator.evaluateFetchWithTimeout(QzAppFetchJs.js); return
        }
        // 北京交通大学 AA 平台 (issue #19): 双端点 HTML 拼 sleepy-bjtu-doc 标记组合源
        if school.type == JwProtocol.TYPE_BJTU {
            coordinator.evaluateFetchWithTimeout(BjtuFetchJs.js); return
        }
        // 合工大 EAMS5: 前缀按学校 URL 推断; 安大自建'新教务'走金智 EAMS 新版 GET 路径
        // (print-data 三段, 5 仓共识: 安大 POST /ws/schedule-table/datum 返 HTTP 500
        //  不存在该 endpoint) — fetch JS 单独走 EAMS5_AHU_FETCH_JS (2026-09-06 cross-verified)
        if school.type == JwProtocol.TYPE_EAMS5 {
            let prefix = Eams5PathPrefix.fromSchoolUrl(school.url)
            let isAhu = school.url.lowercased().contains("ahu.edu.cn")
                || fetchURL.lowercased().contains("ahu.edu.cn")
            let template = isAhu ? Jw1064CaptureScripts.JwAhuCapture : Eams5FetchJs.js
            coordinator.evaluateFetchWithTimeout(
                template.replacingOccurrences(of: EAMS5_PREFIX_PLACEHOLDER, with: prefix))
            return
        }
        // T5: 新版正方 — WebView 内 fetch kbList JSON。
        // 路径指纹: school.type 显式 zf_new, 或 URL 含 /jwglxt/、/kbcx/ (广东医科等新版),
        // 或 WebVPN /http/<hex>/ 重写形态; QZ_IEAS (移动教务 ieas2.1) 不派发 ZF_NEW。
        let isZfNew = Jw1064CaptureScripts.shouldUseZfNewFetch(type: school.type, currentUrl: fetchURL)
        if isZfNew {
            // Use the capture gate so navigation and timeouts invalidate stale results.
            coordinator.evaluateFetchWithTimeout(JwZfNewFetchJs.js)
            return
        }
        // T7: DFS frame 抓取 + ready 重试, 决策在 Swift 层(可测可日志)。
        // OK/EMPTY_SEMESTER → onHtmlCaptured (0 课交给确认页按空学期文案报);
        // 其余状态 → onCaptureError (避免伪"0 课")。
        // #18: UCAS 入口是 SEP 门户, 学生登录后常停在 SEP 应用列表页点导入
        // (还没跳到 xkgo 课表页) → WRONG_PAGE 且域为 sep.ucas.ac.cn 时 hint 换精确动线指引
        // (回调内重读 wv.url, 非派发时快照)。
        coordinator.captureWithRetry(retryCount: 0) { r in
            let liveURL = coordinator.currentURLString ?? fetchURL
            let hint = JwCaptureGuidance.errorHint(for: r, schoolType: school.type, currentURL: liveURL)
            switch r.status {
            case .ok, .emptySemester:
                if school.type == JwProtocol.TYPE_THU {
                    Task { @MainActor in
                        do {
                            let payload = try await JwThuSemesterCapture.capture(r.html)
                            guard thuCaptureToken == pageCaptureToken, coordinator.currentURLString == liveURL else { return }
                            coordinator.captureOnce { current in
                                guard thuCaptureToken == pageCaptureToken else { return }
                                guard coordinator.currentURLString == liveURL,
                                      current.status == .ok || current.status == .emptySemester,
                                      JwThuCapturePayload.sameSemester(r.html, current.html) else {
                                    showCaptureError(current, "采集期间学期或页面已改变，请重新导入"); return
                                }
                                onHtmlCaptured(payload, school, [], "")
                            }
                        } catch {
                            guard thuCaptureToken == pageCaptureToken else { return }
                            showCaptureError(r, error.localizedDescription)
                        }
                    }
                } else { onHtmlCaptured(r.html, school, [], "") }
            case .sessionExpired, .crossDomainIframeBlocked, .containerEmptyAfterDelay,
                 .iframeNavPending, .wrongPage, .unknown:
                showCaptureError(r, hint)
            }
        }
    }

    // ← handleWiseduResult: {ok:true,data:...} / {ok:false,err:...}
    // 失败/空数据走 onCaptureError 通道(← 原版本), 不落 onHtmlCaptured 伪"0 课"。
    private func handleWiseduResult(_ json: String) {
        guard let data = json.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            let msg = L10n.format("jw_fetch_format_error")
            showCaptureError(FrameCaptureResult(selectedFramePath: nil, html: "",
                                                 matchedAnchors: [], status: .unknown), msg)
            return
        }
        if (obj["ok"] as? Bool) == true {
            guard let content = obj["data"] as? String,
                  !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                let msg = L10n.format("jw_fetch_failed_no_response")
                showCaptureError(FrameCaptureResult(selectedFramePath: nil, html: "",
                                                     matchedAnchors: [], status: .unknown), msg)
                return
            }
            var periods: [(Int, String, String)] = []
            if let arr = obj["periods"] as? [[String: Any]] {
                for (i, p) in arr.enumerated() {
                    let node = (p["node"] as? NSNumber)?.intValue ?? (i + 1)
                    periods.append((node, p["start"] as? String ?? "", p["end"] as? String ?? ""))
                }
            }
            // CQU fetch 走通但 time-pattern 没给节次: 落库前明确提示,
            // 用户可在确认页手填节次时间, 而非报误导性的「空学期」
            if periods.isEmpty, school.type == JwProtocol.TYPE_CQU {
                snackMessage = L10n.format("jw_fetch_no_courses")
            }
            // 学期起始日: boya_pp 等 JSON 直连协议随 payload 回传 termBeginTime 前 10 位
            let termStartDate = (obj["startDate"] as? String) ?? ""
            var termStart = termStartDate
            // YETHAN: config 抓了但旧实现无人消费 (死载荷)。采集包 yethan_common-config.json
            // 实锤 data.termLessonStr = "08:00-08:45,08:50-09:35,…" (courseSysDayLesson 个
            // HH:MM-HH:MM 槽), data.termStartDate = 开学日 → 填 periods/startDate, 用户免手填节次。
            if periods.isEmpty, school.type == JwProtocol.TYPE_YETHAN {
                if let cfg = (obj["yethanConfig"] as? [String: Any])?["data"] as? [String: Any] {
                    let lessonStr = (cfg["termLessonStr"] as? String) ?? ""
                    if !lessonStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        let slots = lessonStr.split(separator: ",").compactMap { seg -> (String, String)? in
                            let p = seg.trimmingCharacters(in: .whitespacesAndNewlines)
                                .split(separator: "-")
                            return p.count == 2
                                ? (String(p[0].trimmingCharacters(in: .whitespacesAndNewlines)),
                                   String(p[1].trimmingCharacters(in: .whitespacesAndNewlines)))
                                : nil
                        }
                        periods = slots.enumerated().map { (i, s) in (i + 1, s.0, s.1) }
                    }
                    let cfgStart = (cfg["termStartDate"] as? String) ?? ""
                    if termStart.isEmpty, !cfgStart.isEmpty { termStart = cfgStart }
                }
            }
            let effectiveStartDate = termStart.isEmpty ? termStartDate : termStart
            var payload = content
            if school.type == JwProtocol.TYPE_SG_ASSET {
                let adapter = JwSgAssetBridge.restoreChoice(sgAdapterChoices, savedId: chosenSgAdapterId)
                var provenance: [String: Any] = [:]
                if let adapter {
                    provenance = ["schoolId": adapter.schoolId ?? "", "adapterId": adapter.id, "name": adapter.adapterName ?? "",
                                  "category": adapter.category ?? "", "importUrl": adapter.importUrl]
                }
                do {
                    payload = try JwSgSourceMetadata.stringify(["sleepySgAsset": true,
                        "coursesJson": content, "config": obj["sgConfig"] as? [String: Any] ?? [:], "adapter": provenance])
                    _ = try JwSgSourceMetadata.capture(payload, school.type)
                } catch { snackMessage = error.localizedDescription; return }
            }
            var capturedSchool = school
            if obj["protocol"] as? String == "chaoxing_share",
               Jw1064CaptureScripts.isChaoxingShareUrl(webViewCoordinator?.currentURLString ?? "") {
                capturedSchool.type = "chaoxing_share"
            } else if school.type == JwProtocol.TYPE_SG_ASSET,
                      let adapter = JwSgAssetBridge.restoreChoice(sgAdapterChoices, savedId: chosenSgAdapterId) {
                capturedSchool.url = adapter.importUrl
            }
            onHtmlCaptured(payload, capturedSchool, periods, effectiveStartDate)
        } else {
            let err = (obj["err"] as? String) ?? ""
            let msg = L10n.format("jw_fetch_failed",
                                  err.isEmpty ? L10n.format("jw_page_not_loaded") : err)
            showCaptureError(FrameCaptureResult(selectedFramePath: nil, html: "",
                                                matchedAnchors: [], status: .unknown), msg)
        }
    }
}

// MARK: - 新窗拦截(WebView 默认"当前页打开新窗"语义)

/// WKUIDelegate: 拦截 target="_blank" / window.open, 在当前 webview 内加载。
/// 无此 delegate 时 WKWebView 静默丢弃新窗请求 → 教务卡片点不动。
/// shared 单例: 每个 JwWebViewLoginScreen 建新 coordinator, 但 delegate 行为无状态。
final class NavUIDelegate: NSObject, WKUIDelegate {
    static let shared = NavUIDelegate()

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let url = navigationAction.request.url else { return nil }
        // 非 http(s)(如 about:blank / javascript:)不接管, 返回 nil 丢弃
        guard url.scheme == "http" || url.scheme == "https" else { return nil }
        // 在当前 webview 内加载(对齐 原版本 WebView 默认行为)
        webView.load(URLRequest(url: url))
        return nil
    }
}

// MARK: - WKWebView 包装 ← JwWebView

/// WKWebView 协调器(← WebView + WebViewClient + WebChromeClient + JS 桥 + 诊断接线)
///
/// 导航代理分工: WKWebView 只容一个 navigationDelegate — coordinator 挂前位,
/// 逐回调转发给 JwWebViewClientBuilder 装配出的 delegate(← 原实现
/// webViewClient = JwWebViewClientBuilder.build(...)), 仅在 navigationResponse
/// 处截下载(setDownloadListener 的"不可内嵌展示即下载"同触发条件)。
final class WebViewCoordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    var webView: WKWebView?
    private let onProgressChange: (Double) -> Void
    private let onHtmlCaptured: (String) -> Void
    // ← 原版本 onCaptureError(FrameCaptureResult, hint) 通道(超时闸/状态路由共用)
    private let onCaptureError: (FrameCaptureResult, String) -> Void
    private let onWiseduResult: (String) -> Void
    private var progressObserver: NSKeyValueObservation?
    private var urlObserver: NSKeyValueObservation?
    // WKWebView 弱持 navigationDelegate — 强持有 builder 装配的 delegate,
    // ← 原 webViewClient 强引用同语义
    private var clientDelegate: JwWebViewNavigationDelegate?
    private let school: JwSchoolInfo
    private let initialDesktopUa: Bool
    private let onUrlChanged: (String?) -> Void
    private var lastNavUrl: String?
    private let fetchBudget = JwFetchBudget()
    private var fetchDeliveryEpoch = UUID()
    private var fetchTimeoutWork: DispatchWorkItem?
    private var sgRequests: [[String: Any]] = []
    private var sgAttempts: [Int: Int] = [:]
    private var sgAlert: UIAlertController?

    init(school: JwSchoolInfo,
         desktopUa: Bool,
         onProgressChange: @escaping (Double) -> Void,
         onUrlChanged: @escaping (String?) -> Void,
         onHtmlCaptured: @escaping (String) -> Void,
         onCaptureError: @escaping (FrameCaptureResult, String) -> Void,
         onWiseduResult: @escaping (String) -> Void) {
        self.school = school
        self.initialDesktopUa = desktopUa
        self.onProgressChange = onProgressChange
        self.onUrlChanged = onUrlChanged
        self.onHtmlCaptured = onHtmlCaptured
        self.onCaptureError = onCaptureError
        self.onWiseduResult = onWiseduResult
        super.init()
    }

    func makeWebView(url: URL) -> WKWebView {
        // ← JwWebViewClientBuilder.build(school, desktopMode): 装配 config(桌面 viewport
        // WKUserScript + ctx 快照)。v1.0.61 对齐: 此前本屏自建裸 config, builder 全工程
        // 零引用(死代码)→ #18 桌面 viewport 钉宽实际不生效。现经 builder 装配。
        let (config, ctx) = JwWebViewClientBuilder.build(school: school, desktopMode: initialDesktopUa)
        // javaScriptCanOpenWindowsAutomatically 已由 build() 内部装配 prefs
        // (JwWebViewConfigBuilder:113), 本屏不再重复手设 — v1.0.61 对齐去冗余,
        // 行为零变化
        // ← addJavascriptInterface(__sleepyBridge) → ScriptMessageHandler
        config.userContentController.add(self, name: "__sleepyBridge")
        config.userContentController.add(self, name: "__sleepySgInteraction")
        config.userContentController.add(self, name: "__sleepySgAcknowledged")
        // ← addJavascriptInterface(DiagnosticNetworkBridge("__sleepyNetworkBridge")):
        // recorder 兼容增量回调(权威导出走 pull)→ recordJsNetwork。
        config.userContentController.add(self, name: "__sleepyNetworkBridge")
        // ← WebChromeClient.onConsoleMessage → recordConsole: WKWebView 无该公开回调,
        // 以 console shim 文档级注入(全 frame) + __sleepyConsole 桥等价。
        config.userContentController.add(self, name: "__sleepyConsole")
        config.userContentController.addUserScript(WKUserScript(
            source: jwConsoleShimJs, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        // ← 诊断 recorder 文档级首注入(≈ 原版本 工厂期 evaluateJavascript) +
        //   每次 didFinish 重装(页面脚本可能替换 fetch/XHR 全局 — 原版本 同注释)。
        config.userContentController.addUserScript(WKUserScript(
            source: DiagNetworkInstallJs.js, injectionTime: .atDocumentStart, forMainFrameOnly: false))

        let wv = WKWebView(frame: .zero, configuration: config)
        // ← desktopUa 时 settings.userAgentString = DESKTOP_USER_AGENT(创建期生效杠杆
        // 与 applyDesktopUserAgent 同一机制; ctx.userAgent 空串 = 平台默认手机 UA)
        wv.customUserAgent = ctx.userAgent.isEmpty ? nil : ctx.userAgent
        // ★ 教务系统功能卡片大量使用 target="_blank" / window.open。
        //   原版本 WebView 默认在当前 WebView 内打开新窗; WKWebView 无 UIDelegate
        //   时静默丢弃新窗请求 → 用户卡在教务中间页点卡片无反应(a.v.1.0.41 修复)。
        //   NavUIDelegate 拦截 createWebViewWith, 在当前 webview 内加载新窗 URL。
        wv.uiDelegate = NavUIDelegate.shared
        // ← settings: domStorage WKWebView 默认开; 缩放手势
        wv.allowsBackForwardNavigationGestures = true

        // ← webViewClient = JwWebViewClientBuilder.build(...): SSL 注册域豁免 /
        //   主框架请求记录 / 桌面 viewport 双注入(立即 + 300ms)在 delegate 内;
        //   onPageFinished 回调里重装诊断 recorder(每跳 evaluateJavascript)。
        //   本 coordinator 作为外层 navigationDelegate 逐回调转发(下载处截获)。
        let delegate = JwWebViewClientBuilder.makeNavigationDelegate(
            school: school,
            desktopMode: initialDesktopUa,
            onPageFinished: { [weak self] finished in
                guard let self = self else { return }
                self.lastNavUrl = finished
                // Install after every navigation: page scripts may replace fetch/XHR globals.
                self.webView?.evaluateJavaScript(DiagNetworkInstallJs.js, completionHandler: nil)
                self.webView?.evaluateJavaScript(jwConsoleShimJs, completionHandler: nil)
            },
            onUrlChanged: self.onUrlChanged)
        clientDelegate = delegate
        wv.navigationDelegate = self

        // estimatedProgress KVO(← onProgressChanged)
        progressObserver = wv.observe(\.estimatedProgress, options: .new) { [weak self] _, change in
            DispatchQueue.main.async {
                self?.onProgressChange((change.newValue ?? 0) * 100)
            }
        }
        // SPA pushState/replaceState 型 URL 变化 = 原 doUpdateVisitedHistory 全语义
        urlObserver = delegate.observeUrlChanges(of: wv)

        // ← JwDiagnosticSession.resetSession() 工厂期重置 + recorder 首装(文档级
        //   userScript 已挂, 此处覆盖当前文档场景 — 原版本 工厂期同双保险)
        JwDiagnosticSession.shared.resetSession()
        wv.evaluateJavaScript(DiagNetworkInstallJs.js, completionHandler: nil)
        wv.load(URLRequest(url: url))
        webView = wv
        return wv
    }

    var currentURLString: String? {
        webView?.url?.absoluteString ?? lastNavUrl
    }

    // ← wv.canGoBack() / wv.goBack(): 网页历史优先返回(BackHandler 语义)
    var canGoBack: Bool { webView?.canGoBack ?? false }
    func goBack() { webView?.goBack() }

    // ← submitUrl 的 webViewRef?.loadUrl(normalized)
    func loadURL(_ urlString: String) {
        guard let u = URL(string: urlString) else { return }
        webView?.load(URLRequest(url: u))
    }

    func evaluate(_ js: String, completion: ((String?) -> Void)? = nil) {
        webView?.evaluateJavaScript(js) { result, _ in
            completion?(result as? String)
        }
    }

    // ← evaluateFetchWithTimeout: evaluateJavascript 无内建超时, 教务宕机/挂起时
    // 桥回调永远不来, 用户只见「正在抓取」无限 pending。20s 无回调即报超时
    // (禁无限 pending)。状态 CONTAINER_EMPTY_AFTER_DELAY, hint = jw_fetch_timeout。
    func evaluateFetchWithTimeout(_ js: String, timeout: TimeInterval = jwFetchTimeoutSeconds,
                                  captureId: String = UUID().uuidString) {
        guard let wv = webView else { return }
        cancelFetch()
        fetchBudget.begin(id: captureId, timeout: timeout)
        scheduleFetchTimeout(captureId)
        wv.evaluateJavaScript(scopeJwFetchScript(js, captureId: captureId)) { [weak self] _, error in
            guard let self, let error, (error as NSError).code != WKError.javaScriptResultTypeIsUnsupported.rawValue,
                  self.fetchBudget.complete(id: captureId) else { return }
            self.fetchTimeoutWork?.cancel()
            self.onCaptureError(FrameCaptureResult(selectedFramePath: nil, html: "", matchedAnchors: [], status: .unknown), error.localizedDescription)
        }
    }

    private func scheduleFetchTimeout(_ id: String) {
        fetchTimeoutWork?.cancel()
        guard let seconds = fetchBudget.remainingSeconds(id: id) else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.fetchBudget.captureId == id else { return }
            self.cancelFetch()
            self.onCaptureError(FrameCaptureResult(selectedFramePath: nil, html: "", matchedAnchors: [], status: .containerEmptyAfterDelay), L10n.format("jw_fetch_timeout"))
        }
        fetchTimeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    func cancelFetch() {
        fetchDeliveryEpoch = UUID()
        if let id = fetchBudget.captureId,
           let quoted = try? JwSgSourceMetadata.stringify([id]) {
            webView?.evaluateJavaScript("if(window.SleepySgShim)SleepySgShim.cancelSession(" + String(quoted.dropFirst().dropLast()) + ");", completionHandler: nil)
        }
        fetchBudget.cancel(); fetchTimeoutWork?.cancel(); fetchTimeoutWork = nil
        sgAlert?.dismiss(animated: false); sgAlert = nil; sgRequests = []; sgAttempts = [:]
    }

    private func receiveSgInteraction(_ request: [String: Any]) {
        guard let id = request["sessionId"] as? String, id == fetchBudget.captureId,
              request["requestId"] is NSNumber, let kind = request["kind"] as? String,
              ["alert", "prompt", "selection"].contains(kind) else { return }
        sgRequests.append(request)
        fetchBudget.setWaiting(id: id, waiting: true); fetchTimeoutWork?.cancel()
        if sgRequests.count == 1 { presentSgInteraction() }
    }

    private func presentSgInteraction(error: String = "") {
        guard let request = sgRequests.first, let session = request["sessionId"] as? String,
              session == fetchBudget.captureId, let requestId = request["requestId"] as? Int else { return }
        let kind = request["kind"] as? String ?? ""
        let detail = error.isEmpty ? (request[kind == "alert" ? "content" : "tip"] as? String ?? "") : error
        let alert = UIAlertController(title: request["title"] as? String, message: detail, preferredStyle: .alert)
        sgAlert = alert
        if kind == "prompt" { alert.addTextField { $0.text = request["defaultText"] as? String ?? "" } }
        if kind == "selection", let items = request["items"] as? [String] {
            for (index, item) in items.enumerated() {
                alert.addAction(UIAlertAction(title: item, style: .default) { [weak self] _ in self?.respondSg(session, requestId, index) })
            }
        } else {
            alert.addAction(UIAlertAction(title: (request["confirmText"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? L10n.t("confirm"), style: .default) { [weak self, weak alert] _ in
                self?.respondSg(session, requestId, kind == "alert" ? true : (alert?.textFields?.first?.text ?? ""))
            })
        }
        alert.addAction(UIAlertAction(title: L10n.t("cancel"), style: .cancel) { [weak self] _ in self?.respondSg(session, requestId, kind == "alert" ? false : NSNull()) })
        var presenter = webView?.window?.rootViewController
        while let next = presenter?.presentedViewController, !(next is UIAlertController) { presenter = next }
        presenter?.present(alert, animated: true)
    }

    private func respondSg(_ session: String, _ request: Int, _ value: Any) {
        guard session == fetchBudget.captureId else { return }
        let attempt = (sgAttempts[request] ?? 0) + 1; sgAttempts[request] = attempt
        guard let args = try? JwSgSourceMetadata.stringify([session, request, attempt, value]) else { return }
        webView?.evaluateJavaScript("SleepySgShim.respond.apply(null," + args + ");", completionHandler: nil)
    }

    private func acknowledgeSgInteraction(_ ack: [String: Any]) {
        guard let session = ack["sessionId"] as? String, session == fetchBudget.captureId,
              let request = ack["requestId"] as? Int, let active = sgRequests.first,
              active["requestId"] as? Int == request, ack["attemptId"] as? Int == sgAttempts[request] else { return }
        sgAlert = nil
        if ack["accepted"] as? Bool == true {
            sgRequests.removeFirst(); sgAttempts[request] = nil
            if sgRequests.isEmpty { fetchBudget.setWaiting(id: session, waiting: false); scheduleFetchTimeout(session) }
            else { DispatchQueue.main.async { self.presentSgInteraction() } }
        } else { DispatchQueue.main.async { self.presentSgInteraction(error: ack["error"] as? String ?? "") } }
    }

    // ← captureOnce: evaluateJavascript(CAPTURE_FRAMES_JS + "(8);") → selectBestFrame。
    // 单次 DFS 深度 8 → frame 树重建 → 锚点/登录指纹/跨域决策。回调已在主线程。
    func captureOnce(onResult: @escaping (FrameCaptureResult) -> Void) {
        guard let wv = webView else {
            DispatchQueue.main.async {
                onResult(FrameCaptureResult(selectedFramePath: nil, html: "",
                                            matchedAnchors: [], status: .wrongPage,
                                            diagnosticHint: "WebView 未返回响应"))
            }
            return
        }
        let frameScript = school.type == JwProtocol.TYPE_THU
            ? CaptureFramesJs.js.replacingOccurrences(of: "win.document.documentElement.outerHTML", with: JwThuSemesterCapture.liveHtmlJs)
            : CaptureFramesJs.js
        wv.evaluateJavaScript(frameScript + "(8);") { result, _ in
            guard let raw = result as? String, !raw.isEmpty, raw != "null" else {
                onResult(FrameCaptureResult(selectedFramePath: nil, html: "",
                                            matchedAnchors: [], status: .wrongPage,
                                            diagnosticHint: "WebView 未返回响应"))
                return
            }
            // evaluateJavaScript 回传 String 即 JS 字符串值本身; 防御性兼容
            // JSON 字面量形态(带外层引号+转义 — 原版本 侧需 JSONTokener 解一层)
            var payload = raw
            if raw.hasPrefix("\""),
               let unquoted = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? String {
                payload = unquoted
            }
            onResult(FrameTraversalTree.selectBestFrame(FrameSnapshotList.fromJson(payload), declaredType: self.school.type))
        }
    }

    // ← captureWithRetry: 空壳 iframe / 延迟渲染容器按 1500ms 间隔重试, 至多 3 次。
    // ① 空壳 iframe 先于 Readiness 判定(about:blank 壳不属于"容器空");
    // ② readiness 只看选中 frame 的 html; GIVE_UP 时按 SESSION_EXPIRED /
    //    IFRAME_NAV_PENDING / CONTAINER_EMPTY_AFTER_DELAY 升格, 避免伪"0 课"。
    func captureWithRetry(retryCount: Int, onResult: @escaping (FrameCaptureResult) -> Void) {
        captureOnce { [weak self] first in
            guard self != nil else { return }
            let blank = first.html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || RenderReadinessChecker.checkBlankShell(first.html)
            let readiness: RenderReadinessChecker.Readiness
            if retryCount >= 3 {
                readiness = .giveUp
            } else if blank {
                readiness = .delay    // 空壳 → 等导航
            } else {
                readiness = RenderReadinessChecker.check(first.html, retryCount: retryCount)
            }
            switch readiness {
            case .ready:
                onResult(first)
            case .delay:
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                    self?.captureWithRetry(retryCount: retryCount + 1, onResult: onResult)
                }
            case .giveUp:
                let status: FrameCaptureStatus = first.status == .sessionExpired
                    ? .sessionExpired : (blank ? .iframeNavPending : .containerEmptyAfterDelay)
                let hint: String
                if first.status == .sessionExpired {
                    hint = first.diagnosticHint
                } else if first.html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    hint = "课表框架尚未开始加载(重试 \(retryCount) 次), 请等页面完全显示课表后再点导入"
                } else {
                    hint = "课表容器存在但内容未填充(重试 \(retryCount) 次), 请等待页面完全加载后再点导入"
                }
                onResult(FrameCaptureResult(
                    selectedFramePath: first.selectedFramePath,
                    html: first.html,
                    matchedAnchors: first.matchedAnchors,
                    courseCount: first.courseCount,
                    status: status,
                    blockedFrames: first.blockedFrames,
                    retryCount: retryCount,
                    maxDepthReached: first.maxDepthReached,
                    skippedFrames: first.skippedFrames,
                    diagnosticHint: hint,
                    allFrames: first.allFrames))
            }
        }
    }

    /// 下载实体抓取 — ← 原 setDownloadListener + DOWNLOAD_FETCH_EXECUTOR:
    /// 有界 GET 下载字节(上限 2MB、Cookie 回放)→ recordDownload(..., body)。
    /// iOS 等价: 导航响应不可内嵌展示(canShowMIMEType == false)即 原版本 下载监听器
    /// 的同触发条件 → 后台 URLSession GET 取字节。
    /// Cookie 回放: 读 WKWebsiteDataStore.default 的 httpCookieStore(与 WebView 同一
    ///   存储, ← CookieManager.getInstance().getCookie(downloadUrl)); URLSessionConfiguration
    ///   .default 共享同一系统 HTTPCookieStorage 桥接域, 显式补头双保险。
    /// UA 回放: customUserAgent 字段即本屏设置的桌面/默认 UA — 直接读该字段语义,
    ///   不 KVC 私有 API(禁脆弱运行时键名)。
    /// 有界: 一次性 task, 回调即释放(≈ 有界池语义, 无 per-download 线程泄漏)。
    private func captureDownloadBytes(response: HTTPURLResponse) {
        guard let url = response.url else { return }
        let disposition = response.value(forHTTPHeaderField: "Content-Disposition")
        let mime = response.mimeType
        let ua = webView?.customUserAgent ?? ""
        let store = WKWebsiteDataStore.default().httpCookieStore
        store.getAllCookies { cookies in
            var request = URLRequest(url: url)
            request.timeoutInterval = 15   // readTimeout 15s(← conn.readTimeout)
            if !ua.isEmpty { request.setValue(ua, forHTTPHeaderField: "User-Agent") }
            let path = url.path.isEmpty ? "/" : url.path
            let matched = cookies.filter { c in
                let host = url.host ?? ""
                let name = c.domain.hasPrefix(".") ? String(c.domain.dropFirst()) : c.domain
                let domainOk = host == name || host.hasSuffix("." + name)
                return domainOk && path.hasPrefix(c.path)
            }
            if !matched.isEmpty {
                request.setValue(HTTPCookie.requestHeaderFields(with: matched)["Cookie"],
                                 forHTTPHeaderField: "Cookie")
            }
            URLSession.shared.dataTask(with: request) { data, resp, _ in
                let statusCode = (resp as? HTTPURLResponse)?.statusCode ?? 0
                let body = (200...299).contains(statusCode) ? data : nil
                // readNBytes(2MB) 等价: 截前 2MB(recordDownload 内部再封顶一次, 双保险)
                let capped = body.map { Data($0.prefix(2 * 1024 * 1024)) }
                JwDiagnosticSession.shared.recordDownload(
                    url: url.absoluteString,
                    userAgent: ua.isEmpty ? nil : ua,
                    contentDisposition: disposition,
                    mime: mime,
                    length: data.map { Int64($0.count) } ?? response.expectedContentLength,
                    body: capped)
            }.resume()
        }
    }

    // MARK: WKNavigationDelegate 转发(← JwWebViewNavigationDelegate 实现体)

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        clientDelegate?.webView(webView, decidePolicyFor: navigationAction,
                                decisionHandler: decisionHandler)
            ?? decisionHandler(.allow)
    }

    /// 响应侧: 不可内嵌展示的导航 = 下载 → 截字节 + cancel(页面不渲染二进制);
    /// 其余交 builder delegate 记录后放行。
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if !navigationResponse.canShowMIMEType,
           let http = navigationResponse.response as? HTTPURLResponse {
            captureDownloadBytes(response: http)
            decisionHandler(.cancel)
            return
        }
        clientDelegate?.webView(webView, decidePolicyFor: navigationResponse,
                                decisionHandler: decisionHandler)
            ?? decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        clientDelegate?.webView(webView, didCommit: navigation)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        cancelFetch()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        clientDelegate?.webView(webView, didFinish: navigation)
    }

    func webView(_ webView: WKWebView,
                 didReceive challenge: URLAuthenticationChallenge,
                 completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if let clientDelegate {
            clientDelegate.webView(webView, didReceive: challenge,
                                   completionHandler: completionHandler)
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    // ← 原版本 UA 切换 = key(recreateKey) 销毁重建 (userAgentString 仅创建期可靠)。
    // WKWebView 的 customUserAgent 设置后对 reload/后续导航即生效, set + reload 等价;
    // 传 nil 恢复默认手机 UA(重建时不设 userAgentString)。
    // ★ 先翻 delegate desktopViewport 再 reload — JwWebViewConfigBuilder 消费方契约,
    //   顺序不可反, 否则「手机打开→切桌面」主路径 viewport 注入缺失(#18 回归)。
    func applyDesktopUserAgent(_ desktop: Bool) {
        guard let wv = webView else { return }
        clientDelegate?.desktopViewport = desktop
        wv.customUserAgent = desktop ? jwDesktopUserAgent : nil
        wv.reload()
    }

    // ← actions 刷新 IconButton onClick: webViewRef?.reload()
    func reload() {
        webView?.reload()
    }

    // ← @JavascriptInterface onWiseduResult / DiagnosticNetworkBridge.onNetworkRecord /
    //   WebChromeClient.onConsoleMessage — 三桥统一路由
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        switch message.name {
        case "__sleepyBridge":
            if let body = message.body as? [String: Any],
               let json = body["json"] as? String {
                guard let payload = JwSgSourceMetadata.object(json), let id = payload["captureId"] as? String,
                      fetchBudget.complete(id: id) else { return }
                fetchTimeoutWork?.cancel(); sgAlert?.dismiss(animated: false); sgAlert = nil; sgRequests = []
                let epoch = fetchDeliveryEpoch
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.fetchDeliveryEpoch == epoch else { return }
                    self.onWiseduResult(json)
                }
            }
        case "__sleepySgInteraction":
            if let request = message.body as? [String: Any] { receiveSgInteraction(request) }
        case "__sleepySgAcknowledged":
            if let ack = message.body as? [String: Any] { acknowledgeSgInteraction(ack) }
        case "__sleepyNetworkBridge":
            // recorder 增量 flush 兼容通道(权威导出走 pull)— ← recordJsNetwork
            if let json = message.body as? String {
                JwDiagnosticSession.shared.recordJsNetwork(json)
            } else if let body = message.body as? [String: Any],
                      let json = body["json"] as? String {
                JwDiagnosticSession.shared.recordJsNetwork(json)
            }
        case "__sleepyConsole":
            if let body = message.body as? [String: Any] {
                JwDiagnosticSession.shared.recordConsole(
                    level: body["level"] as? String ?? "log",
                    message: body["message"] as? String ?? "",
                    sourceId: body["sourceId"] as? String)
            }
        default:
            break
        }
    }
}

struct JwWebView: UIViewRepresentable {
    let url: String
    let school: JwSchoolInfo
    let desktopUa: Bool
    let onProgressChange: (Double) -> Void
    let onUrlChanged: (String?) -> Void
    let onCoordinatorCreated: (WebViewCoordinator) -> Void
    let onHtmlCaptured: (String) -> Void
    let onCaptureError: (FrameCaptureResult, String) -> Void
    let onWiseduResult: (String) -> Void

    func makeCoordinator() -> WebViewCoordinator {
        WebViewCoordinator(school: school,
                           desktopUa: desktopUa,
                           onProgressChange: onProgressChange,
                           onUrlChanged: onUrlChanged,
                           onHtmlCaptured: onHtmlCaptured,
                           onCaptureError: onCaptureError,
                           onWiseduResult: onWiseduResult)
    }

    func makeUIView(context: Context) -> WKWebView {
        let wv = context.coordinator.makeWebView(
            url: URL(string: url) ?? URL(string: "https://www.baidu.com")!)
        // ★ coordinator 回传必须脱离 view-update 事务: makeUIView 在渲染事务内,
        //   同步写父视图 @State 会被 SwiftUI 丢弃 → capture() 永远拿到 nil,
        //   真机点"导入本页"必弹 "WebView 未就绪"(2026-09-04 6sp 真机实测)
        DispatchQueue.main.async { self.onCoordinatorCreated(context.coordinator) }
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

// MARK: - WISEDU_FETCH_JS(逐行移植, 桥回调改 WKScriptMessage postMessage)
//
// 路径指纹判定(/jwapp/ 在路径中即可, 不锁定单一 hostname — T5/T11 拆雷):
// 原版本 按 location.pathname.indexOf('/jwapp/') >= 0, 覆盖所有金智部署校
// (哈工程只是其中之一; 硬编码 hostname 会让 ahyz 等校 iOS 点导入必失败)。

enum WiseduFetchJs {
    static let js = """
    (function(){
      try {
        var pathOk = location.pathname.indexOf('/jwapp/') >= 0;
        if (!pathOk) {
          window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify({ok:false, err:'请先登录并进入教务系统后再点导入'})});
          return;
        }
        // 0. 先 GET 我的课表(wdkb)微应用入口，初始化 app 会话；否则 module API 返回 403
        // 会话已死时入口/module API 返回 403 HTML 页（如 AHYZ openresty 金智壳），
        // 必须先看状态码再解析，否则 r.json() 抛 SyntaxError 文案不可读。
        fetch('/jwapp/sys/wdkb/*default/index.do', {credentials:'include'})
        .then(function(response){
          if (!response.ok) {
            throw new Error('WISEDU_HTTP_403: 会话已过期或无权访问，请返回上一步退出登录后重新进入教务登录');
          }
          return fetch('/jwapp/sys/wdkb/modules/jshkcb/dqxnxq.do', {
            method:'POST',
            headers:{'X-Requested-With':'XMLHttpRequest'},
            credentials:'include'
          });
        })
        .then(function(response){
          if (!response.ok) {
            throw new Error('WISEDU_HTTP_403: 会话已过期或无权访问，请返回上一步退出登录后重新进入教务登录');
          }
          return response.json();
        })
        .then(function(d){
          var rows = [];
          try { rows = d.datas.dqxnxq.rows || []; } catch(e) {}

          // 教务页面允许用户切换学期，但 dqxnxq 的 rows[0] 不一定是页面当前选项。
          // 先从当前页面的 select/option 读取用户实际选中的 XNXQDM，避免静默回退到旧学期。
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
          // 某些 Wisedu 页面不是原生 select，而是自定义控件；这时匹配已选/激活节点文本。
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
          // HEU 当前课表页使用 data-elem="XNXQMC" 展示当前学期，不是 select 或 active 节点。
          // 例如："2026-2027学年1学期"；将展示文本映射到接口中的 DM："2026-2027-1"。
          if (!xnxq) {
            var termNode = document.querySelector('[data-elem="XNXQMC"]');
            var termText = termNode ? (termNode.textContent || '') : '';
            var termMatch = termText.match(/(20[0-9]{2})-(20[0-9]{2})\\s*学年\\s*([12])\\s*学期/);
            if (termMatch) {
              var termDm = termMatch[1] + '-' + termMatch[2] + '-' + termMatch[3];
              // HEU 的 dqxnxq 接口可能只返回旧的当前学期，而页面已切到下一学期。
              // 页面显示的学期才是用户选择，不能再要求它必须出现在这份旧列表中。
              xnxq = termDm;
            }
          }
          // 若页面没有学期控件，才使用接口标记的当前学期；禁止无条件取 rows[0]。
          // 兼容标记字段: SFDQ / CURRENT / SFSY (在服/有效标志, 2026-10-01 ahyz 采集包实锤 SFSY=1)。
          // 多学期部署仍必须靠上述 DOM 先识别, 只有列表唯一才允许直接取, 防止误选旧学期。
          if (!xnxq) {
            var current = rows.find(function(row) {
              var dm = row.DM;
              if (!dm) return false;
              return row.SFDQ === '1' || row.SFDQ === 1
                || row.CURRENT === '1' || row.current === true
                || row.SFSY === '1' || row.SFSY === 1;
            });
            if (current) {
              xnxq = String(current.DM);
            } else if (rows.length === 1 && rows[0].DM) {
              // 唯一学期: 无显式 current 标记时安全取 rows[0]。
              xnxq = String(rows[0].DM);
            }
          }
          if (!xnxq) throw new Error('无法识别当前选中的学期，请先在教务页面选择学期后再点导入');
          return fetch('/jwapp/sys/wdkb/modules/xskcb/xskcb.do', {
            method:'POST',
            headers:{'Content-Type':'application/x-www-form-urlencoded','X-Requested-With':'XMLHttpRequest'},
            body:'XNXQDM='+encodeURIComponent(xnxq),
            credentials:'include'
          }).then(function(r){
            if (!r.ok) throw new Error('WISEDU_HTTP_' + r.status + '：课表接口拒绝访问，请重新登录后重试');
            return r.text().then(function(txt){
              var payload;
              try { payload = JSON.parse(txt); }
              catch(e) { throw new Error('课表接口返回非 JSON，登录态可能失效'); }
              if (!payload || !payload.datas || !payload.datas.xskcb ||
                  !Array.isArray(payload.datas.xskcb.rows)) {
                throw new Error('课表接口响应缺少 xskcb.rows 数组，请重新登录后重试');
              }
              return {xnxq:xnxq, txt:txt};
            });
          });
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

// MARK: - CQU_FETCH_JS(← JwWebViewLoginScreen.kt CQU_FETCH_JS 原文移植, 桥回调改 WKScriptMessage postMessage)
//
// 重庆大学门户(my.cqu.edu.cn): localStorage 取 Bearer token → 串
// session/info-detail + my-table-detail + time-pattern 三接口, 学号取自 .trigger-user-name
// (复用 __sleepyBridge 回调通道, payload 同 wisedu {ok, data, periods})。
// 已知: 2026-06 起统一身份认证需动态验证码双因素, WebView 人工登录不受影响。

enum CquFetchJs {
    static let js = """
    (function(){
      try {
        if (location.hostname.indexOf('cqu.edu.cn') < 0) {
          window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify({ok:false, err:'请先登录并进入重庆大学门户后再点导入'})});
          return;
        }
        var token = '';
        try { token = (localStorage.getItem('cqu_edu_ACCESS_TOKEN') || '').replaceAll('"', ''); } catch(e) {}
        if (!token) {
          window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify({ok:false, err:'未取到登录凭据，请先登录 my.cqu.edu.cn 再点导入'})});
          return;
        }
        var studentId = '';
        try {
          var el = document.querySelector('.trigger-user-name');
          var m = el ? (el.innerText || '').match(/\\[(.*?)\\]/) : null;
          studentId = m ? m[1] : '';
        } catch(e) {}
        if (!studentId) {
          window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify({ok:false, err:'页面上未找到学号，请确认已登录门户首页'})});
          return;
        }
        var auth = {credentials:'include', headers:{'Content-Type':'application/json', 'Authorization':'Bearer ' + token}};
        fetch('/api/resourceapi/session/info-detail', auth)
        .then(function(r){
          if (!r.ok) throw new Error('获取学期信息失败 HTTP ' + r.status);
          return r.json();
        })
        .then(function(session){
          var termId = session.curSessionId;
          if (!termId) throw new Error('学期信息里没有 curSessionId');
          var body = Object.assign({}, auth, {method:'POST', body: JSON.stringify([studentId])});
          return fetch('/api/timetable/class/timetable/student/my-table-detail?sessionId=' + encodeURIComponent(termId), body);
        })
        .then(function(r){
          if (!r.ok) throw new Error('获取课表失败 HTTP ' + r.status + '（登录态可能过期，请刷新重登）');
          return r.text();
        })
        .then(function(txt){
          var periods = [];
          return fetch('/api/workspace/time-pattern/session-time-pattern', auth)
          .then(function(r){ return r.ok ? r.json() : null; })
          .then(function(tp){
            try {
              var vos = (tp && tp.data && tp.data.classPeriodVOS) || [];
              for (var i = 0; i < vos.length; i++) {
                var v = vos[i];
                periods.push({
                  node: v.periodOrder || (i + 1),
                  start: v.startTime || '',
                  end: v.endTime || ''
                });
              }
              periods.sort(function(a,b){ return a.node - b.node; });
            } catch(e) { periods = []; }
            window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify({ok:true, data:txt, periods:periods})});
          });
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


// MARK: - BOYA_PP_FETCH_JS(← JwWebViewLoginScreen.kt BOYA_PP_FETCH_JS 原文移植, 桥回调改 WKScriptMessage postMessage)
//
// 博雅研究生平台 (/pp/ 前端, 首校燕山大学研究生 yjsxt.ysu.edu.cn): currentUser 取当前
// 学期名 → microForm/term 定学期 (termBeginTime/weekEnd 在此) → setting/current 取
// lessonConfig 节次时间 → 逐周 byStudent 并发拉全学期排课行合并成 {term, rows}。
// 实测不带 whichWeek 的 byStudent 只回不完整子集, 必须按 weekEnd 逐周抓; 单周偶发失败
// 静默跳过, 但 401 登录失效必须中止 (否则以部分数据伪装完整课表)。
// payload 额外带 startDate (termBeginTime 前 10 位) → 确认页开学日期预填。

enum BoyaPpFetchJs {
    static let js = """
    (function(){
      try {
        // 入口是燕大 CAS (cer.ysu.edu.cn), 登录后回调落到 yjsxt.ysu.edu.cn —
        // 只在平台域放行, CAS 页上点导入给出明确提示而非 404 请求
        if (location.hostname.indexOf('yjsxt.ysu.edu.cn') < 0 && location.pathname.indexOf('/pp/') < 0) {
          window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify({ok:false, err:'请先完成统一身份认证登录并进入研究生平台后再点导入'})});
          return;
        }
        var hdrs = {'Protocol-Type': location.protocol.replace(/:/g, '')};
        try {
          var m = document.cookie.match(/(?:^|;\\s*)token=([^;]+)/);
          var tk = m ? decodeURIComponent(m[1]) : '';
          if (!tk) {
            var raw = sessionStorage.getItem('ROOT:APPSTORE');
            if (raw) { var j = JSON.parse(raw); if (j && j.token) tk = j.token; }
          }
          if (tk) hdrs['token'] = tk;
        } catch(e) {}
        var get = function(url){
          return fetch(url, {credentials:'include', headers:hdrs}).then(function(r){
            if (r.status === 401) throw new Error('登录态已失效，请重新登录研究生平台后再点导入');
            if (!r.ok) throw new Error('接口请求失败 HTTP ' + r.status);
            return r.json();
          }).then(function(j){
            if (!j || (j.code !== 200 && j.code !== '200')) {
              throw new Error((j && j.message) ? j.message : '接口返回异常');
            }
            return j.data;
          });
        };
        get('/api/login/currentUser')
        .then(function(u){ return (u && u.termName) ? String(u.termName) : ''; })
        .catch(function(){ return ''; })
        .then(function(termName){
          return get('/api/microForm/term').then(function(terms){
            var list = terms || [];
            var cur = null;
            for (var i = 0; i < list.length; i++) {
              if (termName && list[i].termName === termName) { cur = list[i]; break; }
              if (!termName && String(list[i].currentTerm) === '是') { cur = list[i]; }
            }
            if (!cur || !cur.termName) throw new Error('未找到当前学期，请确认已进入本学期课表页');
            return cur;
          });
        })
        .then(function(term){
          var T = term.termName;
          var periodsP = get('/api/schedule/class/setting/current?yearTerm=' + encodeURIComponent(T))
          .then(function(cfg){
            var periods = [];
            try {
              var lc = (cfg && cfg.lessonConfig) || [];
              for (var i = 0; i < lc.length; i++) {
                var t = lc[i].lessonTime || [];
                periods.push({
                  node: lc[i].lessonNumber || (i + 1),
                  start: String(t[0] || '').slice(11, 16),
                  end: String(t[1] || '').slice(11, 16)
                });
              }
              periods.sort(function(a, b){ return a.node - b.node; });
            } catch(e) { periods = []; }
            return periods;
          }).catch(function(){ return []; });
          // 总周数: weekEnd 优先 ("19"), 兜底按起止日推算, 再兜底 30
          var maxWeek = parseInt(term.weekEnd, 10);
          if (!(maxWeek >= 1 && maxWeek <= 30)) {
            try {
              var ms = new Date(term.termEndTime) - new Date(term.termBeginTime);
              maxWeek = Math.ceil(ms / (7 * 24 * 3600 * 1000));
            } catch(e) { maxWeek = 0; }
            if (!(maxWeek >= 1 && maxWeek <= 30)) maxWeek = 30;
          }
          var weekReqs = [];
          for (var w = 1; w <= maxWeek; w++) {
            weekReqs.push(
              get('/api/schedule/table/byStudent?page=0&size=500&whichWeek=' + w +
                  '&yearTerm=' + encodeURIComponent(T))
              .then(function(rows){ return rows || []; })
              .catch(function(e){
                // 单周偶发失败不致命, 静默跳过; 但 401 登录失效必须中止 —
                // 否则会以部分数据伪装成完整课表
                if (e && String(e.message || '').indexOf('登录态已失效') >= 0) throw e;
                return [];
              })
            );
          }
          return Promise.all([Promise.all(weekReqs), periodsP]).then(function(rs){
            var rows = [];
            for (var k = 0; k < rs[0].length; k++) rows = rows.concat(rs[0][k]);
            if (!rows.length) throw new Error('课表为空：请先在研究生平台"我的课表"页确认本学期已有课程');
            window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify({
              ok: true,
              data: JSON.stringify({term: T, rows: rows}),
              periods: rs[1],
              startDate: String(term.termBeginTime || '').slice(0, 10)
            })});
          });
        })
        .catch(function(e){
          window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify({ok:false, err:String(e && e.message || e)})});
        });
      } catch(err) {
        window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify({ok:false, err:String(err)})});
      }
    })();
    """
}


// MARK: - QZ_APP_FETCH_JS(← JwWebViewLoginScreen.kt QZ_APP_FETCH_JS 原文移植, 桥回调改 WKScriptMessage postMessage)
//
// 强智移动教务 SPA (type=qz_app): 课表只在移动 JSON API 里 (token header 鉴权), 页面
// HTML 无课程数据。相对路径 serverconfig.json 免鉴权发现 ApiUrl (各校部署根可不同,
// 先试当前目录再试 /dist/serverconfig.json, 禁硬编码) → sessionStorage.Token 作 token
// 头请求。课表端点一次只回一周 (week= 空 = 当前教学周, data 恒单元素), 只抓当前周会把
// 仅在后续周出现的课整门丢掉 — 先 POST /teachingWeek 取周数列表, 再并行逐周 POST
// curriculum?week=w&kbjcmsid=, 合并成 {weeks:[<单次响应>…]} 组合源 (与燕大 boya_pp
// 逐周方案同构)。401 一律中止 (禁以部分数据伪装完整课表), 单周失败静默跳过。
// JS 只做 fetch 与传输层状态路由, 协议字段解码全部在 JwQzAppParser (跨语言 invariant)。

enum QzAppFetchJs {
static let js = """
    (function(){
      try {
        var post = function(obj){
          window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify(obj)});
        };
        var token = '';
        try { token = sessionStorage.getItem('Token') || ''; } catch(e) {}
        if (!token) {
          post({ok:false, err:'未取到登录令牌: 请先登录移动教务后再点导入'});
          return;
        }
        var getCfg = function(url){
          return fetch(url, {credentials:'include'})
            .then(function(r){
              if (!r.ok) { throw new Error('serverconfig.json HTTP ' + r.status); }
              return r.json();
            });
        };
        getCfg('serverconfig.json')
          .catch(function(){
            return getCfg('/dist/serverconfig.json');
          })
          .then(function(cfg){
            var apiUrl = String(cfg.ApiUrl || '').replace(/\\/+$/,'');
            if (!apiUrl) { throw new Error('serverconfig.json 缺 ApiUrl'); }
            return apiUrl;
          })
          .then(function(apiUrl){
            var call = function(path){
              return fetch(apiUrl + path, {
                method:'POST',
                credentials:'include',
                headers: { 'token': token }
              }).then(function(r){ return r.text(); });
            };
            // 课表端点一次只回一周 (week= 空 = 当前教学周, data 单元素);
            // 只抓当前周会丢掉仅在后续周出现的课 — 先取 teachingWeek 周数列表,
            // 再并行逐周拉取合并 (与燕大 boya_pp 逐周方案同构)
            return call('/teachingWeek').then(function(twText){
              var weekNums = [];
              try {
                var tw = JSON.parse(twText);
                if (tw && tw.code != '401' && tw.data && tw.data.length) {
                  for (var i = 0; i < tw.data.length; i++) {
                    var n = parseInt(tw.data[i].week, 10);
                    if (n >= 1 && n <= 30) weekNums.push(n);
                  }
                }
              } catch(e) {}
              if (!weekNums.length) weekNums = [1];
              var expired = false;
              var reqs = weekNums.map(function(w){
                return call('/student/curriculum?week=' + w + '&kbjcmsid=')
                  .then(function(text){
                    try { if (JSON.parse(text).code == '401') expired = true; } catch(e) {}
                    return text;
                  })
                  .catch(function(){ return null; });
              });
              return Promise.all(reqs).then(function(texts){
                if (expired) {
                  post({ok:false, err:'登录已过期: 请重新登录后再点导入'});
                  return;
                }
                var ok = texts.filter(function(t){ return t !== null; });
                if (!ok.length) {
                  post({ok:false, err:'课表接口无响应: 请确认已登录并进入课表页'});
                  return;
                }
                post({ok:true, data: JSON.stringify({weeks: ok.map(function(t){
                  try { return JSON.parse(t); } catch(e) { return null; }
                }).filter(function(j){ return j !== null; })})});
              });
            });
          })
          .catch(function(e){
            post({ok:false, err:String(e && e.message || e)});
          });
      } catch(err) {
        window.webkit.messageHandlers.__sleepyBridge.postMessage({json:JSON.stringify({ok:false, err:String(err)})});
      }
    })()
    """
}
