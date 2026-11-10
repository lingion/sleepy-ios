// UcasDetailFetch.swift — ← UcasDetailFetch.kt 1:1 translation (GPL-3.0)
//
// UCAS (#18) 课程详情页抓取器。
//
// personSchedule 网格页 (xkgo.ucas.ac.cn:3000) 的课程格链接指向跨源详情站
// xkcts.ucas.ac.cn:8443 — WebView 页面上下文 fetch 会被 CORS 拦 (采集器 v1.2
// 也因此被迫走 tab 导航)。但详情页**免登录** (issue #18 v1.2 采集包实测:
// 无 cookie 直连 200 + 完整周次数据), 所以原生 HTTP 直抓即可, 无须会话凭证。
//
// 用法: 网格 HTML 进, 组合源出。任一详情失败均停止导入，避免缺失课程。

import Foundation

enum UcasDetailFetch {

    /// 连接/读取超时 (← HttpURLConnection connectTimeout / readTimeout = 10s)。
    /// URLSession 不单独暴露 connect timeout, timeoutIntervalForRequest 同时覆盖
    /// 建连与两次读之间的空档, 语义等价偏严。
    private static let timeoutSec: TimeInterval = 10

    /// 详情页抓取上限 (实测一门课 11 页; 上限防异常网格撑爆导入流程)
    static let MAX_DETAILS = 50

    /// 详情站对默认 UA 会 403, 必须带桌面 Chrome UA (同一字符串)
    private static let userAgent =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
        "(KHTML, like Gecko) Chrome/152.0.0.0 Safari/537.36"

    private enum FetchError: Error, Equatable {
        case badURL
        case nonHTTP
        case http(Int)
    }

    /// 无 cookie 会话 (详情页免登录, 带 cookie 反而把会话指纹送出跨源站)
    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = timeoutSec
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.httpCookieStorage = nil
        cfg.httpShouldSetCookies = false
        cfg.urlCache = nil
        return URLSession(configuration: cfg)
    }()

    struct Detail: Equatable {
        let url: String
        let html: String
    }

    /// 主入口: 网格 HTML → 逐课抓详情 → 拼组合源。
    /// Every detail must decode before returning the combined source.
    static func enrich(_ gridHtml: String) async throws -> String {
        try await enrichWith(gridHtml, fetch: fetchOne)
    }

    static func enrichWith(_ gridHtml: String, fetch: (String) async throws -> String) async throws -> String {
        let urls = extractDetailUrlsSafe(gridHtml)
        if urls.isEmpty { return gridHtml }
        guard urls.count <= MAX_DETAILS else { throw JwParseError(message: "课程详情数量超过单次导入上限，无法完整导入") }
        var details: [Detail] = []
        for url in urls {
            let html = try await fetch(url)
            guard !JwUcasParser.parseDetailPages(html).isEmpty else { throw JwParseError(message: "课程详情未提供完整上课安排，请重新进入课表页后重试") }
            details.append(Detail(url: url, html: html))
        }
        return combine(gridHtml, details)
    }

    /// 纯函数: 网格 + (url, html) 列表 → 带 JwUcasParser.DETAIL_MARKER_OPEN 分段的组合源
    static func combine(_ gridHtml: String, _ details: [Detail]) -> String {
        var out = gridHtml
        for detail in details {
            out += "\n"
            out += JwUcasParser.DETAIL_MARKER_OPEN
            out += detail.url
            out += "-->\n"
            out += detail.html
            out += "\n"
            out += JwUcasParser.DETAIL_MARKER_CLOSE
            out += "\n"
        }
        return out
    }

    /// 抓单个详情页; 非 200 / 网络异常抛出, 由调用方整体处理
    static func fetchOne(_ url: String) async throws -> String {
        guard let u = URL(string: url) else { throw FetchError.badURL }
        var request = URLRequest(url: u)
        request.httpMethod = "GET"
        request.timeoutInterval = timeoutSec
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FetchError.nonHTTP }
        guard http.statusCode == 200 else { throw FetchError.http(http.statusCode) }
        let enc = encoding(forContentType: http.value(forHTTPHeaderField: "Content-Type"))
        if let text = String(data: data, encoding: enc) { return text }
        // 声明字符集与实际字节不符 → 有损 UTF-8 解码 (Java BufferedReader 同样不抛)
        return String(decoding: data, as: UTF8.self)
    }

    /// Content-Type 里的 charset=, 缺失/未知回落 UTF-8 (charset(name) 默认值)
    static func encoding(forContentType contentType: String?) -> String.Encoding {
        let name = charsetName(contentType) ?? ""
        if !name.isEmpty {
            let cf = CFStringConvertIANACharSetNameToEncoding(name as CFString)
            if cf != kCFStringEncodingInvalidId {
                return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
            }
        }
        return .utf8
    }

    /// 抽 charset= 值 (大小写不敏感, 去引号, 到 ';' 为止)
    static func charsetName(_ contentType: String?) -> String? {
        guard let contentType = contentType, !contentType.isEmpty else { return nil }
        let re = try! NSRegularExpression(pattern: #"(?i)charset\s*=\s*"?([^;"'\s]+)"#)
        guard let m = re.firstMatch(in: contentType, range: NSRange(contentType.startIndex..., in: contentType)),
              let r = Range(m.range(at: 1), in: contentType) else { return nil }
        return String(contentType[r])
    }

    /// ← 原版本 的 try { extractDetailUrls } catch { emptyList() }
    private static func extractDetailUrlsSafe(_ gridHtml: String) -> [String] {
        gridHtml.isEmpty ? [] : JwUcasParser.extractDetailUrls(gridHtml)
    }
}
