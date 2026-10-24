// JwDiagnosticSession.swift — ← JwDiagnosticSession.kt (208 行)
//
// 诊断会话 — 边加载边记 WebView 期间的网络请求 + console 输出 + 导航 URL。
//
// 设计动机: 用户点"导入此页"失败时, App 必须已经掌握本次会话的全量证据。
// 学生不可能帮我们"再访问一次把请求记下来",失败就是失败,要的就是当下快照。
//
// 线程模型: WKWebView delegate 回调主线程, NSURLProtocol 子线程。
// 必须线程安全 — 使用 NSLock (lock-free 但受 App 锁保护)。
//
// 容量策略: 500 条/通道。教务页整页加载 ~100-300 条请求 (含 iframe/CSS/字体), 500
// 足够覆盖完整学期的登录链。超出后头丢弃 (addFirst 后降序, 然后 removeLast 截断)。

import Foundation

final class JwDiagnosticSession {

    static let shared = JwDiagnosticSession()
    static let RING_LIMIT = 500

    private struct RequestLog {
        let ts: Int64
        let method: String
        let url: String
        let status: Int
        let mime: String?
        let requestHeaders: String?
        let responseHeaders: String?
        let isRedirect: Bool
        let isMainFrame: Bool
    }

    private struct ConsoleLog {
        let ts: Int64
        let level: String
        let message: String
        let sourceId: String?
    }

    private struct DownloadLog {
        let ts: Int64
        let url: String
        let userAgent: String
        let contentDisposition: String
        let mime: String
        let length: Int64
        let body: Data?
        let bodyTruncated: Bool
    }

    private var requests: [RequestLog] = []
    private var consoles: [ConsoleLog] = []
    private var downloads: [DownloadLog] = []
    private var jsNetwork: [String] = []
    private let startTimeMs: Int64 = JwDiagnosticSession.monotonicMs()
    private var sessionId: String = JwDiagnosticSession.makeSessionId()
    private let lock = NSLock()

    /// 单调毫秒时钟 — 对标 Android SystemClock.elapsedRealtime(): 自设备启动计数,
    /// 不受 NTP 校时/手动改表影响, ts 偏移恒为非负、不跳变。
    private static func monotonicMs() -> Int64 {
        Int64(ProcessInfo.processInfo.systemUptime * 1000)
    }

    private static func makeSessionId() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd-HHmmss"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        // 时区跟随设备本地 — 对齐 Android SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US)
        // 的设备默认时区; 强行 UTC 会让 UTC+8 用户的会话 id 比本机时刻早 8 小时。
        return fmt.string(from: Date())
    }

    func resetSession() {
        lock.lock(); defer { lock.unlock() }
        requests.removeAll()
        consoles.removeAll()
        downloads.removeAll()
        jsNetwork.removeAll()
        sessionId = JwDiagnosticSession.makeSessionId()
    }

    func currentSessionId() -> String {
        lock.lock(); defer { lock.unlock() }
        return sessionId
    }

    /// WKURLSchemeHandler / WKNavigationDelegate 回调里调。
    /// status/mime 由 NSURLResponse 推断 (200/404/500 + Content-Type)。
    func recordRequest(method: String, url: String, status: Int, mime: String?,
                       requestHeaders: [String: String]?, responseHeaders: [String: String]?,
                       isRedirect: Bool = false, isMainFrame: Bool = false) {
        lock.lock()
        let log = RequestLog(
            ts: Self.monotonicMs() - startTimeMs,
            method: method,
            url: url,
            status: status,
            mime: mime,
            requestHeaders: Self.headersText(requestHeaders),
            responseHeaders: Self.headersText(responseHeaders),
            isRedirect: isRedirect,
            isMainFrame: isMainFrame
        )
        requests.insert(log, at: 0)
        if requests.count > Self.RING_LIMIT { requests.removeLast() }
        lock.unlock()
    }

    private static func headersText(_ h: [String: String]?) -> String? {
        guard let h = h, !h.isEmpty else { return nil }
        return h.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
    }

    /// WKWebView WKScriptMessageHandler / evaluateJavaScript 拿 console; 也可走 WKWebView 私有 API。
    func recordConsole(level: String, message: String, sourceId: String?) {
        lock.lock()
        let log = ConsoleLog(
            ts: Self.monotonicMs() - startTimeMs,
            level: level,
            message: message,
            sourceId: sourceId
        )
        consoles.insert(log, at: 0)
        if consoles.count > Self.RING_LIMIT { consoles.removeLast() }
        lock.unlock()
    }

    func recordDownload(url: String, userAgent: String?, contentDisposition: String?, mime: String?, length: Int64) {
        recordDownload(url: url, userAgent: userAgent, contentDisposition: contentDisposition, mime: mime, length: length, body: nil)
    }

    /// 下载实捕获版 — body 前 2MB 落 ring buffer; 桌面 collector 4-downloads/ 对标。
    func recordDownload(url: String, userAgent: String?, contentDisposition: String?, mime: String?, length: Int64, body: Data?) {
        guard !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        lock.lock()
        let cap = 2 * 1024 * 1024
        let truncated = body != nil && (body!.count > cap)
        let cappedBody = body.flatMap { truncated ? Data($0.prefix(cap)) : $0 }
        let log = DownloadLog(
            ts: Self.monotonicMs() - startTimeMs,
            url: url,
            userAgent: userAgent ?? "",
            contentDisposition: contentDisposition ?? "",
            mime: mime ?? "",
            length: length,
            body: cappedBody,
            bodyTruncated: truncated
        )
        downloads.insert(log, at: 0)
        if downloads.count > Self.RING_LIMIT { downloads.removeLast() }
        lock.unlock()
    }

    /// 按记录顺序导出下载实体字节 (nil = 该条无实体)。
    func exportDownloadBodies() -> [(index: Int, body: Data)] {
        lock.lock(); defer { lock.unlock() }
        return downloads.reversed().enumerated().compactMap { (idx, d) in
            d.body.map { (idx, $0) }
        }
    }

    func exportDownloads() -> String {
        lock.lock(); defer { lock.unlock() }
        var sb = "# Download metadata\n"
        for d in downloads.reversed() {
            sb += "+\(d.ts)ms \(d.mime) \(d.length) \(d.url)\n"
            sb += "  User-Agent: \(d.userAgent)\n"
            sb += "  Content-Disposition: \(d.contentDisposition)\n"
        }
        return sb
    }

    /// 页面 recorder 的增量回调; 限制单条大小和总条数,避免异常页面耗尽内存。
    func recordJsNetwork(_ json: String) {
        guard !json.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        lock.lock()
        let cap = 512 * 1024
        let truncated = String(json.prefix(cap))
        jsNetwork.insert(truncated, at: 0)
        if jsNetwork.count > Self.RING_LIMIT { jsNetwork.removeLast() }
        lock.unlock()
    }

    func exportJsNetwork() -> String {
        lock.lock(); defer { lock.unlock() }
        return "[" + jsNetwork.reversed().joined(separator: ",") + "]"
    }

    /// dump 阶段由 JwCaptureDump 调用,生成 netlog.txt 用的文本。
    func exportNetlog() -> String {
        lock.lock(); defer { lock.unlock() }
        var sb = "# Session: \(sessionId)\n"
        sb += "# Total: \(requests.count) requests\n"
        sb += "# Format: +offsetMs METHOD status mime [MAIN|sub] [REDIRECT] url\n\n"
        for r in requests.reversed() {
            var flags = ""
            if r.isMainFrame { flags += " MAIN" }
            if r.isRedirect { flags += " REDIRECT" }
            let status = r.status < 0 ? "unknown" : String(r.status)
            sb += "+\(r.ts)ms \(r.method) \(status) \(r.mime ?? "-")\(flags) \(r.url)\n"
            if let h = r.requestHeaders {
                sb += "  > \(h.replacingOccurrences(of: "\n", with: "\n  > "))\n"
            }
            if let h = r.responseHeaders {
                sb += "  < \(h.replacingOccurrences(of: "\n", with: "\n  < "))\n"
            }
        }
        return sb
    }

    func exportConsole() -> String {
        lock.lock(); defer { lock.unlock() }
        var sb = "# Session: \(sessionId)\n"
        sb += "# Total: \(consoles.count) console messages\n"
        sb += "# Format: +offsetMs LEVEL sourceId:line:col  message\n\n"
        for c in consoles.reversed() {
            sb += "+\(c.ts)ms \(c.level) \(c.sourceId ?? "-"): \(c.message)\n"
        }
        return sb
    }
}
