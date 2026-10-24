// JwCaptureDump.swift — ← JwCaptureDump.kt
// 排查全量包 dump — 把诊断会话的全量证据打成 zip 落盘,再拉系统分享面板。
//
// 设计动机: 学生手头只有"导入失败"反馈, 把诊断取证反推到我们这边。
// 点「导出排查全量包」→ zip 落盘 → 自动拉 UIActivityViewController → 学生微信发回。
//
// 隐私: 1B 完全不脱敏 — Cookie/学号/表单值/HTML 原文全保留。学生知道他在发什么。
//
// 路径分流 (方案 A):
//   iOS 沙箱: NSFileManager + 临时目录, 写完 UIApplication 调 share(_:) 拉分享面板
//   (iOS 没有 MediaStore.Downloads 等价物, 走 NSTemporaryDirectory + UIActivityVC)
//
// 内容 (与 Android 1:1):
//   summary.txt          — 状态/锚点/帧路径/重试/hint/学校/版本
//   frames/xxx.html      — 每个可达 frame 的 outerHTML 原文 (FrameCaptureResult 已含)
//   dom-inventory.txt    — DOM_INVENTORY_JS 现场抓的可点元素清单
//   netlog.txt           — JwDiagnosticSession 全程网络请求日志
//   console.txt          — JwDiagnosticSession console 日志
//   cookies-full.txt     — Cookie 全量值
//   5-storage/storage.json — Web Storage(sessionStorage + localStorage)全键值
//   2-inline/links.json  — 页面链接全集 + select 下拉枚举(学期码)
//   4-net-replay/        — 同源资源重取结果 + 失败原因
//   4-net-live/          — 页面运行时真实 fetch/XHR 请求与响应
//   4-downloads/         — WebView 下载元数据 + 真实下载文件字节
//   env/device.txt       — 设备 / iOS SDK / WebView 实现版本
//   6-logs/              — 采集过程日志 / HAR 1.2 / 采集汇总
//   INDEX.txt            — 目录说明 + 文件清单

import Foundation
import ZIPFoundation
#if canImport(UIKit)
import UIKit
#endif

/// 排查全量包导出。
/// 1:1 对照 Android JwCaptureDump.kt:三组重载 exportDump 兼容旧调用方,
/// 纯函数 buildZip 可在测试中以 nil ctx 调用,IO 走 shareDump 调用方提供的 Activity/UIActivityVC 桥。
enum JwCaptureDump {

    private static let TAG = "JwCaptureDump"
    private static let RELATIVE_DIR = "Sleepy/教务日志"
    private static let ZIP_BASE = "sleepy-jw-dump"
    private static let MIME = "application/zip"

    // MARK: - 入口 (三组重载 — 对齐 Android 2026-09-18 用户对标桌面 collector)

    /// 入口 — 由 JwErrorDialog "导出排查全量包" 按钮回调。
    /// IO 阻塞, 必须在工作线程调用。
    static func exportDump(
        school: JwSchoolInfo,
        result: FrameCaptureResult,
        domInventoryJson: String?
    ) -> DumpResult {
        exportDump(school: school, result: result, domInventoryJson: domInventoryJson,
                   cookiesFull: nil, storageJson: nil, linksJson: nil)
    }

    static func exportDump(
        school: JwSchoolInfo,
        result: FrameCaptureResult,
        domInventoryJson: String?,
        cookiesFull: String?,
        storageJson: String?,
        linksJson: String?
    ) -> DumpResult {
        exportDump(school: school, result: result, domInventoryJson: domInventoryJson,
                   cookiesFull: cookiesFull, storageJson: storageJson, linksJson: linksJson,
                   resourceReplayJson: nil)
    }

    static func exportDump(
        school: JwSchoolInfo,
        result: FrameCaptureResult,
        domInventoryJson: String?,
        cookiesFull: String?,
        storageJson: String?,
        linksJson: String?,
        resourceReplayJson: String?,
        networkLiveJson: String? = nil
    ) -> DumpResult {
        let stamp = JwDiagnosticSession.shared.currentSessionId()
        let zipName = "\(ZIP_BASE)-\(stamp).zip"
        do {
            let zipBytes = try buildZip(
                school: school, result: result, domInventoryJson: domInventoryJson,
                cookiesFull: cookiesFull, storageJson: storageJson, linksJson: linksJson,
                resourceReplayJson: resourceReplayJson, networkLiveJson: networkLiveJson
            )
            if let url = writeZip(zipName: zipName, zipBytes: zipBytes) {
                return .ok(zipName: zipName, url: url)
            }
            return .fail(reason: "存储失败")
        } catch {
            return .fail(reason: error.localizedDescription)
        }
    }

    // MARK: - 纯函数 — 拼 zip 字节流 (测试直接调用, 无 IO)

    static func buildZip(
        school: JwSchoolInfo,
        result: FrameCaptureResult,
        domInventoryJson: String?
    ) throws -> Data {
        try buildZip(school: school, result: result, domInventoryJson: domInventoryJson,
                     cookiesFull: nil, storageJson: nil, linksJson: nil)
    }

    static func buildZip(
        school: JwSchoolInfo,
        result: FrameCaptureResult,
        domInventoryJson: String?,
        cookiesFull: String?,
        storageJson: String?,
        linksJson: String?
    ) throws -> Data {
        try buildZip(school: school, result: result, domInventoryJson: domInventoryJson,
                     cookiesFull: cookiesFull, storageJson: storageJson, linksJson: linksJson,
                     resourceReplayJson: nil)
    }

    static func buildZip(
        school: JwSchoolInfo,
        result: FrameCaptureResult,
        domInventoryJson: String?,
        cookiesFull: String?,
        storageJson: String?,
        linksJson: String?,
        resourceReplayJson: String?,
        networkLiveJson: String? = nil
    ) throws -> Data {
        var manifest: [(String, String)] = []   // (path, description)
        // ZIPFoundation 走 in-memory archive — Data 缓冲, 写完一次 .data 拿出。
        // 注意: Archive 没有 init(data:), 只能先 addEntry 后取 archive.data。
        // 用临时内存 archive 模式 (AccessMode = .create 但不绑定 URL) — 通过 Int8 stdio file handle。
        // 简化方案: 写到 tmp zip 文件 → 读出 Data → 删除文件。
        // 为保持纯函数语义: 用自定义 Pipe 风格的 WritableByteChannel 不便; 改用 FileManager.temporaryDirectory 中转。
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("sleepy-capture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tmpDir)
        }
        let zipUrl = tmpDir.appendingPathComponent("dump.zip")
        // ZIPFoundation: Archive.addEntry with relative path → throws on duplicate.
        guard let archive = try? Archive(url: zipUrl, accessMode: .create) else {
            throw NSError(domain: TAG, code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "archive open failed"])
        }

        try writeSummary(archive: archive, manifest: &manifest, school: school, result: result)
        try writeFrames(archive: archive, manifest: &manifest, result: result)
        try writeInventory(archive: archive, manifest: &manifest, json: domInventoryJson)
        try writeText(archive: archive, manifest: &manifest, name: "netlog.txt",
                      content: JwDiagnosticSession.shared.exportNetlog(),
                      description: "全程网络请求(方法/状态/MIME/请求头/响应头/重定向)")
        try writeText(archive: archive, manifest: &manifest, name: "console.txt",
                      content: JwDiagnosticSession.shared.exportConsole(),
                      description: "WebView console 输出")
        try writeText(archive: archive, manifest: &manifest, name: "cookies-full.txt",
                      content: cookiesFull ?? "(no cookies captured)",
                      description: "Cookie 全量值(1B 不脱敏, 排查登录态)")
        try writeText(archive: archive, manifest: &manifest, name: "5-storage/storage.json",
                      content: storageJson ?? "{\"sessionStorage\":{},\"localStorage\":{}}",
                      description: "Web Storage 全量键值(sessionStorage + localStorage)")
        try writeText(archive: archive, manifest: &manifest, name: "2-inline/links.json",
                      content: linksJson ?? "{\"links\":[],\"selects\":[]}",
                      description: "页面链接全集 + select 下拉枚举(学期码)")
        try writeResourceReplay(archive: archive, manifest: &manifest, json: resourceReplayJson)
        try writeNetworkLive(archive: archive, manifest: &manifest,
                             json: networkLiveJson ?? JwDiagnosticSession.shared.exportJsNetwork())
        try writeEnvironment(archive: archive, manifest: &manifest)
        // 桌面 collector 6-logs/collect-log.txt 对标 — 逐文件采集记录 (时间序)。
        try writeText(archive: archive, manifest: &manifest, name: "6-logs/collect-log.txt",
                      content: buildCollectLog(manifest: manifest),
                      description: "采集过程逐文件日志(时间序, 对标桌面 collector)")
        try writeIndex(archive: archive, manifest: manifest)

        // 写出落盘 → 读 Data → 删
        let data = try Data(contentsOf: zipUrl)
        return data
    }

    // MARK: - 各段写包

    private static func writeSummary(
        archive: Archive,
        manifest: inout [(String, String)],
        school: JwSchoolInfo,
        result: FrameCaptureResult
    ) throws {
        let session = JwDiagnosticSession.shared.currentSessionId()
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let appBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        // 对齐 Android `debug=${BuildConfig.DEBUG}` → 输出 true/false 字面量, 而非条件编译指令文本。
        #if DEBUG
        let debug = "true"
        #else
        let debug = "false"
        #endif
        let path = result.selectedFramePath?.joined(separator: "/") ?? "<none>"
        let sb = """
        # Sleepy JW Diagnostic Summary
        session=\(session)
        appVersion=\(appVersion) (\(appBuild))
        debug=\(debug)
        school=\(school.name) type=\(school.type ?? "null") url=\(school.url)
        status=\(String(describing: result.status))
        courseCount=\(result.courseCount)
        selectedFramePath=\(path)
        matchedAnchors=\(result.matchedAnchors.joined(separator: ","))
        retryCount=\(result.retryCount) maxDepthReached=\(result.maxDepthReached)
        blockedFrames=\(result.blockedFrames.joined(separator: ";"))
        skippedFrames=\(result.skippedFrames.joined(separator: ","))
        diagnosticHint=\(result.diagnosticHint)
        """
        try writeText(archive: archive, manifest: &manifest, name: "summary.txt",
                      content: sb, description: "状态/锚点/帧路径/重试/hint/学校/版本")
    }

    private static func writeFrames(
        archive: Archive,
        manifest: inout [(String, String)],
        result: FrameCaptureResult
    ) throws {
        // 全帧落盘 (对齐桌面 collector 1-dom/): 每个可达 frame 一个 html; 选中帧标 0- 前缀。
        var seen = Set<String>()
        var idx = 1
        for (framePath, html) in result.allFrames {
            if html.isBlank { continue }
            let safe = framePath.replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "_",
                                                     options: .regularExpression).prefix(80).description
            if !seen.insert(safe).inserted { continue }
            let isSelected: Bool = {
                guard let sel = result.selectedFramePath else { return false }
                let selStr = sel.joined(separator: "_").replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "_",
                                                                              options: .regularExpression)
                return framePath.hasSuffix(selStr)
            }()
            let name = isSelected ? "frames/0-\(safe).html" : "frames/\(idx)-\(safe).html"
            try writeText(archive: archive, manifest: &manifest, name: name,
                          content: html,
                          description: isSelected ? "选中 frame 的 outerHTML 原文" : "可达 frame outerHTML 原文")
            idx += 1
        }
        if !manifest.contains(where: { $0.0.hasPrefix("frames/") }) && !result.html.isBlank {
            let safe = (result.selectedFramePath?.last ?? "selected")
                .replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "_", options: .regularExpression)
            try writeText(archive: archive, manifest: &manifest, name: "frames/0-\(safe).html",
                          content: result.html,
                          description: "选中 frame 的 outerHTML 原文(无全帧快照兜底)")
        }
    }

    private static func writeInventory(
        archive: Archive,
        manifest: inout [(String, String)],
        json: String?
    ) throws {
        let body: String
        if let json = json, !json.isBlank {
            body = json
        } else {
            body = "{\"url\":\"(no document)\",\"total\":0,\"items\":[]}"
        }
        try writeText(archive: archive, manifest: &manifest, name: "dom-inventory.txt",
                      content: body,
                      description: "DOM 可点元素清单(a/button/input/select/textarea/label)")
    }

    /// Writes the real same-origin resource responses collected in the WebView page.
    /// Entries with an error remain metadata-only; no synthetic body is generated.
    private static func writeResourceReplay(
        archive: Archive,
        manifest: inout [(String, String)],
        json: String?
    ) throws {
        guard let raw = json, !raw.isBlank,
              let data = raw.data(using: .utf8),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [Any]
        else { return }
        // 对齐 Android rows.toString() — org.json 紧凑格式, 无 prettyPrinted。
        let manifestJson = compactJSONString(rows) ?? "[]"
        try writeText(archive: archive, manifest: &manifest, name: "4-net-replay/manifest.json",
                      content: manifestJson,
                      description: "资源重取结果与失败原因")
        for (i, row) in rows.enumerated() {
            // 对齐 Android rows.optJSONObject(i) ?: continue — 非对象元素只跳过, 不丢整包。
            guard let row = row as? [String: Any] else { continue }
            if row["error"] != nil { continue }
            guard let body = row["body"] as? String, !body.isBlank else { continue }
            try writeText(archive: archive, manifest: &manifest, name: "4-net-replay/\(i + 1).body",
                          content: body, description: "同源资源真实响应体")
        }
    }

    /**
     * 审计修复: runtime 网络数据有三种到达形态, 全部归一为 {live,replay,weeks} 对象 —
     *  1. 双引号包裹 (DIAGNOSTIC_NETWORK_SNAPSHOT_JS 快照路径, JS 返回值被外层 JSON 编码)
     *  2. 裸数组 (exportJsNetwork() 默认值是 JSONArray)
     *  3. 正常对象 {live,replay,weeks}
     * 解析失败 = 空对象兜底, 但绝不静默丢已捕获证据。
     */
    private static func parseNetworkLiveRoot(json: String?) -> [String: Any] {
        guard let raw = json?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isBlank else {
            return [:]
        }
        // 形态1: 双引号包裹 → 解开外层字符串字面量
        var inner = raw
        if inner.hasPrefix("\"") {
            if let data = inner.data(using: .utf8),
               let unwrapped = try? JSONSerialization.jsonObject(with: data) as? String {
                inner = unwrapped
            }
        }
        // 形态2: 裸数组 → 归一为 {live: [...]}
        if inner.hasPrefix("[") {
            if let data = inner.data(using: .utf8),
               let arr = try? JSONSerialization.jsonObject(with: data) as? [Any] {
                return ["live": arr]
            }
            return [:]
        }
        if let data = inner.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return obj
        }
        return [:]
    }

    private static func writeNetworkLive(
        archive: Archive,
        manifest: inout [(String, String)],
        json: String?
    ) throws {
        let root = parseNetworkLiveRoot(json: json)
        // 对齐 Android root.optJSONArray(...) + rows.optJSONObject(i) ?: continue —
        // 非对象元素逐条跳过, 不整包丢弃。
        let rows = (root["live"] as? [Any]) ?? []
        let replay = (root["replay"] as? [Any]) ?? []
        let weeks = (root["weeks"] as? [Any]) ?? []

        // 4-net-live/manifest.json — 对齐 Android rows.toString() 紧凑格式。
        let rowsJson = compactJSONString(rows) ?? "[]"
        try writeText(archive: archive, manifest: &manifest, name: "4-net-live/manifest.json",
                      content: rowsJson,
                      description: "页面运行时真实 fetch/XHR 请求与响应")

        var headers = StringBuilder()
        var urls: [String] = []   // 保序去重
        var seenUrls = Set<String>()
        for (i, rowAny) in rows.enumerated() {
            // 对齐 Android rows.optJSONObject(i) ?: continue — 编号仍用原始数组下标 i。
            guard let row = rowAny as? [String: Any] else { continue }
            let method = (row["method"] as? String) ?? "GET"
            let url = (row["url"] as? String) ?? ""
            if !url.isBlank, seenUrls.insert(url).inserted {
                urls.append(url)
            }
            if let responseHeaders = row["responseHeaders"] {
                // 对齐 Android responseHeaders.toString() — org.json 紧凑 JSON,
                // 不能用 String(describing:) (Swift 字典字面量语法, 非法 JSON)。
                let rendered = compactJSONString(responseHeaders) ?? ""
                if !rendered.isBlank {
                    headers.appendLine("== \(method) \(url) ==")
                    headers.appendLine(rendered)
                    headers.appendLine()
                }
            }
            if let body = row["responseBody"] as? String, !body.isBlank {
                try writeText(archive: archive, manifest: &manifest, name: "4-net-live/\(i + 1).body",
                              content: body, description: "真实响应正文")
            }
        }
        if !replay.isEmpty {
            try writeText(archive: archive, manifest: &manifest,
                          name: "4-net-replay-withparam/manifest.json",
                          content: compactJSONString(replay) ?? "[]",
                          description: "基于已观察 POST 请求的重放结果")
        }
        if !weeks.isEmpty {
            try writeText(archive: archive, manifest: &manifest,
                          name: "4-net-replay-weeks/manifest.json",
                          content: compactJSONString(weeks) ?? "[]",
                          description: "基于已观察周参数的 1..25 周重放计划")
        }
        try writeText(archive: archive, manifest: &manifest, name: "6-logs/network-live.json",
                      content: rowsJson, description: "机器可读运行时网络记录")
        try writeText(archive: archive, manifest: &manifest, name: "6-logs/all-urls.txt",
                      content: urls.joined(separator: "\n"),
                      description: "运行时发现的 URL")
        if !headers.isEmpty {
            try writeText(archive: archive, manifest: &manifest, name: "6-logs/response-headers.txt",
                          content: headers.toString(), description: "运行时响应头汇总")
        }

        // WebView 下载元数据
        // 对齐 Android downloadText.lines().size — Kotlin lines() 保留空行,
        // 必须用 components(separatedBy:) (split 默认丢弃空片段, 空行多的文本会误判跳过)。
        let downloadText = JwDiagnosticSession.shared.exportDownloads()
        if downloadText.components(separatedBy: "\n").count > 2 {
            try writeText(archive: archive, manifest: &manifest, name: "4-downloads/manifest.txt",
                          content: downloadText, description: "WebView 下载元数据")
        }
        // 下载实体 — 桌面 collector 4-downloads/ 对标: 实际文件字节落包
        for (idx, body) in JwDiagnosticSession.shared.exportDownloadBodies() {
            let path = "4-downloads/\(idx + 1).body"
            try addDataEntry(archive: archive, path: path, data: body)
            manifest.append((path, "真实下载文件字节(前 2MB)"))
        }

        if let har = buildHar(rows: rows) {
            try writeText(archive: archive, manifest: &manifest, name: "6-logs/capture.har",
                          content: har, description: "HAR 1.2 网络回放文件")
        }
        // 对齐 Android org.json 插入序 networkRecords → replayRecords → weekPlans → responseBodies。
        // Swift 字典不保序, .sortedKeys 会按字母排; 手工按 Android 顺序拼串。
        let responseBodies = rows.reduce(into: 0) { count, any in
            if let row = any as? [String: Any],
               let body = row["responseBody"] as? String, !body.isBlank { count += 1 }
        }
        let summaryJson = """
        {
          "networkRecords": \(rows.count),
          "replayRecords": \(replay.count),
          "weekPlans": \(weeks.count),
          "responseBodies": \(responseBodies)
        }
        """ + "\n"
        try writeText(archive: archive, manifest: &manifest, name: "6-logs/collection-summary.json",
                      content: summaryJson, description: "机器可读采集汇总")
    }

    /** Build a HAR 1.2 representation from runtime records. Bodies are bounded to 64 KiB
     *  each to keep the file usable in browsers; full bodies live under 4-net-live. */
    private static func buildHar(rows: [Any]) -> String? {
        if rows.isEmpty { return nil }
        // 对齐 Android rows.optJSONObject(i) ?: continue — 非对象行只跳过。
        let entries: [[String: Any]] = rows.compactMap { rowAny in
            guard let row = rowAny as? [String: Any] else { return nil }
            let method = (row["method"] as? String) ?? "GET"
            let url = (row["url"] as? String) ?? ""
            let requestHeadersJson = row["requestHeaders"] as? [String: Any]
            let request: [String: Any] = {
                var r: [String: Any] = [
                    "method": method,
                    "url": url,
                    "httpVersion": "HTTP/1.1",
                    "cookies": [] as [String],
                    "headers": toHarHeaders(requestHeadersJson),
                    "queryString": harQueryString(url: url),
                    "headersSize": -1
                ]
                let reqBody = (row["requestBody"] as? String) ?? ""
                r["bodySize"] = reqBody.utf8.count
                if !reqBody.isEmpty {
                    let ct = (requestHeadersJson?["Content-Type"] as? String) ?? ""
                    r["postData"] = ["mimeType": ct, "text": reqBody]
                }
                return r
            }()
            let status = (row["status"] as? Int) ?? -1
            let raw = (row["responseBody"] as? String) ?? ""
            let truncated = raw.count > 65536 ? String(raw.prefix(65536)) : raw
            let responseHeadersJson = row["responseHeaders"] as? [String: Any]
            let contentType = (responseHeadersJson?["Content-Type"] as? String) ?? "application/octet-stream"
            let response: [String: Any] = [
                "status": status < 0 ? 0 : status,
                "statusText": status < 0 ? "unknown" : "",
                "httpVersion": "HTTP/1.1",
                "cookies": [] as [String],
                "headers": toHarHeaders(responseHeadersJson),
                "content": [
                    // HAR 1.2 spec: content.size is REQUIRED — full body size even when text is truncated.
                    "size": raw.utf8.count,
                    "text": truncated,
                    "mimeType": contentType
                ] as [String: Any],
                // HAR 1.2: redirectURL is the redirect target; only meaningful on 3xx.
                "redirectURL": (status >= 300 && status < 400) ? ((row["finalUrl"] as? String) ?? "") : "",
                "headersSize": -1,
                "bodySize": raw.utf8.count
            ]
            return [
                "startedDateTime": "1970-01-01T00:00:00.000Z",
                "time": 0,
                "request": request,
                "response": response,
                "cache": [:] as [String: Any],
                "timings": ["send": 0, "wait": 0, "receive": 0]
            ]
        }
        let log: [String: Any] = [
            "version": "1.2",
            "creator": ["name": "sleepy-ios", "version": "ios"],
            "entries": entries
        ]
        let builder: [String: Any] = ["log": log]
        // 对齐 Android builder.toString() — 紧凑格式, 无 prettyPrinted。
        return compactJSONString(builder)
    }

    private static func harQueryString(url: String) -> [[String: String]] {
        // 对齐 Android Uri.parse(url).query — 含空格的 URL 用 URL(string:) 返 nil,
        // 先 percent-encode 空格再解; 仍失败则退到手工切 query 段。
        let query: String
        if let encoded = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let components = URLComponents(string: encoded), let q = components.query {
            query = q
        } else if let range = url.range(of: "?") {
            var tail = String(url[range.upperBound...])
            if let hash = tail.range(of: "#") { tail = String(tail[..<hash.lowerBound]) }
            query = tail
        } else {
            return []
        }
        guard !query.isBlank else { return [] }
        // 对齐 Android query.split('&') — CharSequence.split 保留空片段。
        return query.split(separator: "&", omittingEmptySubsequences: false).map { item in
            let parts = item.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            return [
                "name": parts.first ?? "",
                "value": parts.count > 1 ? parts[1] : ""
            ]
        }
    }

    /** collect-log.txt — 每个已导出文件一行; 对标桌面 collector 的采集过程日志。 */
    private static func buildCollectLog(manifest: [(String, String)]) -> String {
        let session = JwDiagnosticSession.shared.currentSessionId()
        var sb = StringBuilder()
        sb.appendLine("# Session: \(session)")
        sb.appendLine("# Collected \(manifest.count) entries")
        sb.appendLine("")
        for (path, _) in manifest {
            sb.appendLine("+ collected \(path)")
        }
        return sb.toString()
    }

    private static func toHarHeaders(_ map: [String: Any]?) -> [[String: String]] {
        guard let map = map else { return [] }
        return map.map { k, v in ["name": k, "value": String(describing: v)] }
    }

    /// 对齐 Android org.json `.toString()` — 紧凑(非 pretty)JSON。
    /// Kotlin `Any.toString()`: String → 原样; JSONObject/JSONArray → 紧凑 JSON;
    /// Number/Boolean → 字面量。JSONSerialization 默认输出即无缩进。
    private static func compactJSONString(_ object: Any) -> String? {
        if let s = object as? String { return s }
        // org.json 的 JSONObject.NULL.toString() = "null"。
        if object is NSNull { return "null" }
        if let n = object as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue ? "true" : "false" }
            return n.stringValue
        }
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object)
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func writeEnvironment(
        archive: Archive,
        manifest: inout [(String, String)]
    ) throws {
        let device = UIDevice.current
        let systemVersion = device.systemVersion
        let model = device.model
        let systemName = device.systemName
        // WebView 版本 — iOS 系统 WebView = WKWebView (WebKit), 与系统绑定;
        // 这里附 iOS 系统版本 + WebKit 隐式版本 (无法单独查询)
        let env = """
        # Device / WebView Environment
        systemName=\(systemName) systemVersion=\(systemVersion) model=\(model) name=\(device.name)
        appPackage=\(Bundle.main.bundleIdentifier ?? "(none)")
        webviewPackage=com.apple.WebKit (system) webviewVersion=(system, iOS \(systemVersion))
        """
        try writeText(archive: archive, manifest: &manifest, name: "env/device.txt",
                      content: env, description: "设备/iOS SDK/WebView 实现版本")
    }

    /** INDEX.txt — 桌面 collector 7 段目录说明 + 文件清单(对标)。 */
    private static func writeIndex(
        archive: Archive,
        manifest: [(String, String)]
    ) throws {
        let session = JwDiagnosticSession.shared.currentSessionId()
        let sb = """
        Sleepy JW Diagnostic Package (sleepy-ios)
        session=\(session)

        == 目录说明 ==
        summary.txt  状态/锚点/帧路径/重试/hint/学校/版本
        frames/      所有可达 frame 的 outerHTML 原文
        dom-inventory.txt  DOM 可点元素清单(失败时反循救命)
        netlog.txt   全程网络请求 + 请求头/响应头/重定向标记
        console.txt  WebView console 输出
        cookies-full.txt  Cookie 全量值(1B 不脱敏,排查登录态)
        5-storage/  Web Storage(sessionStorage + localStorage)全键值
        2-inline/links.json  页面链接全集 + select 下拉枚举(学期码)
        env/device.txt  iOS SDK/包名/WebView 实现版本
        4-net-replay/  同源资源真实响应 + 失败原因
        4-net-live/    页面运行时真实 fetch/XHR + 响应体
        4-downloads/   WebView 下载元数据 + 真实下载文件字节
        6-logs/        采集过程日志 + HAR 1.2 + 采集汇总

        == 文件清单 (path | 说明) ==
        \(manifest.map { "\($0.0)  |  \($0.1)" }.joined(separator: "\n"))

        == 自查提示 ==
        接口响应/页面可能含你的姓名/学号;提交前搜索改成 XXX 即可,不影响适配。
        """
        let path = "INDEX.txt"
        try addDataEntry(archive: archive, path: path, data: Data(sb.utf8))
    }

    private static func writeText(
        archive: Archive,
        manifest: inout [(String, String)],
        name: String,
        content: String,
        description: String
    ) throws {
        let data = Data(content.utf8)
        try addDataEntry(archive: archive, path: name, data: data)
        manifest.append((name, description))
    }

    /// ZIPFoundation 0.9.20 provider-based addEntry: chunked (position, size) -> Data.
    /// Provider 是 module 级 typealias (Data+Compression.swift:38),不是 Archive 嵌套。
    /// 闭包以 trailing 形式直接传给 addEntry — 不能绑定到 `let provider: Provider` 再传,
    /// 那会让 Swift 误判闭包需要 @escaping(addEntry 的 provider 形参本身未标 @escaping)。
    private static func addDataEntry(archive: Archive, path: String, data: Data) throws {
        var cursor = 0
        try archive.addEntry(with: path, type: .file,
                             uncompressedSize: Int64(data.count),
                             compressionMethod: .deflate,
                             bufferSize: 32 * 1024,
                             progress: nil) { _, size in
            // 末尾切片可能 < size — provider 越界返回空 Data,框架会停。
            if cursor >= data.count { return Data() }
            let end = min(cursor + size, data.count)
            let chunk = data.subdata(in: cursor..<end)
            cursor = end
            return chunk
        }
    }

    // MARK: - 落盘 + 分享

    /// iOS: 写临时目录返回 URL。调用方负责 share(_:) 拉 UIActivityViewController。
    /// iOS 没有 MediaStore.Downloads 等价物 (Android 那边走的),统一走 tmp + 分享面板。
    @discardableResult
    private static func writeZip(zipName: String, zipBytes: Data) -> URL? {
        let baseDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(RELATIVE_DIR, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        let fileURL = baseDir.appendingPathComponent(zipName)
        do {
            try zipBytes.write(to: fileURL, options: [.atomic])
            return fileURL
        } catch {
            return nil
        }
    }

    /// 落盘成功后由 UI 调 — 拉系统分享面板 (UIActivityViewController)。
    /// iOS: 走 UIActivityViewController (Android 那边是 Intent.createChooser)。
    @MainActor
    static func share(url: URL) {
        #if canImport(UIKit)
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        // 找当前最顶 UIViewController 展示 — 避免 iPad 上无 anchor 闪退
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            var top = root
            while let presented = top.presentedViewController { top = presented }
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = top.view
                popover.sourceRect = CGRect(x: top.view.bounds.midX,
                                             y: top.view.bounds.midY,
                                             width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            top.present(activityVC, animated: true)
        }
        #endif
    }

    // MARK: - 返回结果

    enum DumpResult {
        case ok(zipName: String, url: URL)
        case fail(reason: String)
    }
}

// MARK: - StringBuilder (轻量,可链式 appendLine)

private final class StringBuilder {
    private var buffer = ""

    func append(_ s: String) { buffer.append(s) }
    func appendLine(_ s: String) { buffer.append(s); buffer.append("\n") }
    func appendLine() { buffer.append("\n") }
    var isEmpty: Bool { buffer.isEmpty }
    func toString() -> String { buffer }
}

// MARK: - isBlank / StringBuilder

// isBlank 来自 Sleepy/util/HolidayManager.swift 公共扩展 (与 Kotlin isBlank 1:1)

