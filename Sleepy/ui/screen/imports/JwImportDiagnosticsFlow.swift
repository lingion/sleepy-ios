// JwImportDiagnosticsFlow.swift — ← ui/screen/imports/JwImportActivity.kt v1.0.60
//                                    exportDiagnosticDump 管线 (行 235-376) 纯逻辑拆出
//
// 排查全量包导出管线编排器。原版本 把这段 inline 在 Activity 的 Compose
// 闭包里(state 捕获耦合 UI); iOS 按「纯逻辑独立 enum/struct + UI 装载注明平台
// 差异」拆出 — 阶段推进/顺序/超时/降级全在本文件, 可单测。
//
// 管线 9 段(枚举序即执行序, 与 DiagDumpProgress.DumpStage 一一对应):
//   DomInventory → Storage → Links → NetworkSnapshot → NetworkReplay(30s)
//   → ResourceReplay(16s) → Cookies → ZipAssembly → SaveShare
//
// ## 宣布-再执行(announce-then-execute)不变量 (2026-09-22 用户反馈定法)
// 执行第 N 段时进度卡必须已标第 N 段名 — 旧 advance-after 惯性下用户盯着
// 「网络快照」字样实际在跑 30s 重放, 误判死循环。故每段:
//   entering(stage) → 执行 → leaveStage()(stepsDone+1)
//
// ## 平台差异(UI 装载部分, 由调用方负责)
//   - 原 evaluateJavascript + suspendCancellableCoroutine → iOS
//     WKWebView.evaluateJavaScript(异步 completion 回调, 主线程)。
//     本类型通过 injected evalJs 闭包抽象, 单测传 stub。
//   - 原版本 __sleepyDiagBridge addJavascriptInterface / removeJavascriptInterface
//     → iOS WKScriptMessageHandler 注册/注销(桥名 __sleepyDiagBridge, 主线程)。
//     注入 JS 侧回调仍是 window.webkit.messageHandlers.__sleepyDiagBridge
//     .postMessage({json:...})(桥接约定)。重放 JS 的回调桥名一致。
//   - 原版本 CookieManager.getInstance().getCookie(webView.url)(主线程约束)
//     → iOS WKHTTPCookieStore.getAllCookies(异步); 同样在 Cookies 段完成。
//   - 原版本 withContext(Dispatchers.IO) zip → iOS Task.detached(qos: .userInitiated)。
//   - 原版本 JwCaptureDump.share(ctx, ...) → iOS UIActivityViewController。
//
// 失败语义: 任一段 JS 求值失败/超时 → 该段结果为 nil, 管线继续(排查包宁缺
// 一段不整体失败); school == nil 时 ZipAssembly 段直接 Fail("未选择学校")。

import Foundation

/// 诊断导出管线编排器 — 每次导出建一个实例(承载 stepsDone 状态)。
/// (原版本 版是闭包局部 var stepsDone + 嵌套 fun; Swift 拆成可测 struct)
struct JwImportDiagnosticsFlow {

    /// 进度推进回调: 每进入一段发一次(= dumpProgress = DiagDumpProgress(...))
    let onProgress: (DiagDumpProgress) -> Void
    /// 状态文案回调(成功/失败 snackbar): = statusMsg = ...
    let onStatus: (String) -> Void

    /// stepsDone = 已完成原子步骤数(0..DumpStage.allCases.count)。
    /// 宣布-再执行: entering 先发当前段进度, 完成后 leaveStage 递增。
    private(set) var stepsDone = 0

    init(onProgress: @escaping (DiagDumpProgress) -> Void,
         onStatus: @escaping (String) -> Void) {
        self.onProgress = onProgress
        self.onStatus = onStatus
    }

    private mutating func entering(_ stage: DumpStage) {
        onProgress(DiagDumpProgress(stage: stage, stepsDone: stepsDone))
    }

    private mutating func leaveStage() { stepsDone += 1 }

    // MARK: - 求值抽象(平台差异注入点)

    /// 主线程串行 JS 求值: 返回解包后的字符串; null/空/解引失败 → nil。
    /// (← evalJs: evaluateJavascript 回调里 JSONTokener 解一层引号)
    typealias EvalJs = (String) async -> String?

    /// 网络重放段: 注入 DIAGNOSTIC_NETWORK_EXPORT_JS 并等 __sleepyDiagBridge
    /// 回调, 30s 超时 → nil。(原版本: withTimeoutOrNull(30_000L))
    typealias ReplayBridgeEval = (String, TimeInterval) async -> String?

    /// Cookie 全量值: WKHTTPCookieStore.getAllCookies 拼 "k=v; ..."。
    /// (← CookieManager.getInstance().getCookie(webView.url))
    typealias CookieFetch = () async -> String?

    // MARK: - 管线主体 (← exportDiagnosticDump)

    /// 运行完整 9 段管线。lastCaptureResult 为 nil 直接失败(无抓取记录)。
    ///
    /// - Parameters:
    ///   - school: 学校(null → ZipAssembly 段 Fail("未选择学校"))。
    ///   - lastCaptureResult: WebView 侧保留的 FrameCaptureResult(无则失败)。
    ///   - webView 求值闭包集(见 typealiases; UI 层装配真实 WKWebView 实现)。
    ///   - dumpExport: zip 组装+落盘(IO 段) → DumpResult。
    ///   - share: 成功后拉系统分享面板。
    ///   - strings: L10n 装载(jw_diag_export_failed / jw_diag_export_saved)。
    mutating func run(
        school: JwSchoolInfo?,
        lastCaptureResult: FrameCaptureResult?,
        evalJs: EvalJs,
        replayEval: ReplayBridgeEval,
        fetchCookies: CookieFetch,
        dumpExport: (JwSchoolInfo, FrameCaptureResult, String?, String?, String?, String?, String?, String?, String?) async -> JwCaptureDump.DumpResult,
        share: (String, URL) -> Void,
        noCaptureMsg: String,
        failFmt: (String) -> String,
        savedFmt: (String) -> String
    ) async {
        guard let result = lastCaptureResult else {
            onStatus(failFmt(noCaptureMsg))
            return
        }

        // 现场抓取辅助 — 页面还在, 弹窗不关页: DOM 清单 + Storage + Links
        // 三段 JS 顺序跑 (evaluateJavaScript 回调顺序有保 — 主线程串行)
        entering(.domInventory)
        let inventoryJson = await evalJs(DomInventoryJs.js)
        leaveStage()
        entering(.storage)
        let storageJson = await evalJs(StorageJs.js)
        leaveStage()
        entering(.links)
        let linksJson = await evalJs(LinksJs.js)
        leaveStage()

        // 页面运行时真实 fetch/XHR 记录，和资源重取分开保存。
        entering(.networkSnapshot)
        let networkLiveSnapshot = await evalJs(DiagNetworkSnapshotJs.js)
        leaveStage()

        entering(.networkReplay)
        // 网络重放经一次性桥(__sleepyDiagBridge)回传, 30s 上限
        let networkReplayJson = await replayEval("__networkReplay__", 30)
        leaveStage()

        entering(.resourceReplay)
        // evaluateJavaScript 不等待 Promise; 资源重取通过一次性 JS bridge 回传。
        // JS 自带 15s deadline; 16s 外层超时覆盖注入接口不可用/回调永不到达的页面。
        let resourceReplayJson = await replayEval("__resourceReplay__", 16)
        leaveStage()

        entering(.cookies)
        // Cookie 全量值 — WKHTTPCookieStore(async API), 与 JS 段同段完成
        let cookiesFull = await fetchCookies()
        leaveStage()

        entering(.zipAssembly)
        var dumpResult: JwCaptureDump.DumpResult
        if let school = school {
            dumpResult = await dumpExport(
                school, result, inventoryJson, cookiesFull, storageJson,
                linksJson, resourceReplayJson, networkReplayJson, networkLiveSnapshot)
        } else {
            dumpResult = .fail(reason: "未选择学校")
        }
        leaveStage()

        switch dumpResult {
        case .ok(let zipName, let url):
            entering(.saveShare)
            onProgress(DiagDumpProgress(stage: .saveShare, stepsDone: DumpStage.allCases.count))
            onStatus(savedFmt(zipName))
            share(zipName, url)
        case .fail(let reason):
            onStatus(failFmt(reason))
        }
    }

    /// 求值解包(静态纯函数, 单测可直跑): WKWebView evaluateJavaScript 回调的
    /// raw 是 JSON 字符串字面量(带引号+转义), 先解一层; "null"/空 → nil。
    /// (evalJs 内 JSONTokener(raw).nextValue().toString())
    static func unwrapEvalResult(_ raw: String?) -> String? {
        guard let raw = raw, !raw.isEmpty, raw != "null" else { return nil }
        // 带 JSON 引号 → 解一层转义; 解不动原样返回(evaluateJavaScript 对字符串
        // 结果统一 JSON 编码, JS 侧 return 的裸对象场景不存在)
        guard raw.hasPrefix("\""), let data = raw.data(using: .utf8),
              let unquoted = (try? JSONSerialization.jsonObject(with: data,
                  options: [.fragmentsAllowed])) as? String else {
            return (raw == "null" || raw.isEmpty) ? nil : raw
        }
        return unquoted.isEmpty ? nil : unquoted
    }
}
