#if DEBUG && !WIDGET_EXT && !WATCH_APP
import Foundation

/// 公开 URLSession 回放接缝。不是 WKWebView HTTP(S) 全资源拦截器。
final class ConsoleJWMockStore {
    struct Rule: Codable {
        let urlPattern: String
        let status: Int
        let contentType: String
        let headers: [String: String]
        let body: Data

        enum CodingKeys: String, CodingKey {
            case urlPattern = "url_pattern", status, contentType = "content_type", headers, body = "body_b64"
        }
        func matches(_ url: String) -> Bool {
            guard let expression = try? NSRegularExpression(pattern: urlPattern) else { return false }
            return expression.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)) != nil
        }
        var json: [String: Any] {
            ["url_pattern": urlPattern, "status": status, "content_type": contentType,
             "headers": headers, "body_bytes": body.count]
        }
    }

    static let shared = ConsoleJWMockStore(directory: ConsoleStorage.directory)
    private let directory: URL
    private let file: URL
    private let lock = NSLock()
    private var rules: [Rule] = []
    private var active = false

    init(directory: URL) {
        self.directory = directory
        file = directory.appendingPathComponent("console_jw_mocks.json")
        if let bytes = try? Data(contentsOf: file), bytes.count <= 24 * 1024 * 1024,
           let loaded = try? JSONDecoder().decode([Rule].self, from: bytes), loaded.count <= 100 {
            rules = loaded.filter { (100...599).contains($0.status) && $0.body.count <= ConsoleHTTPParser.bodyLimit }
        }
    }

    func setActive(_ value: Bool) { lock.lock(); active = value; lock.unlock() }
    func list() -> [Rule] { lock.lock(); defer { lock.unlock() }; return rules }

    /// 返回真实 HTTPURLResponse + bytes；调用方继续既有 status/charset/解析链。
    func response(for request: URLRequest) -> (Data, URLResponse)? {
        lock.lock(); defer { lock.unlock() }
        guard active, let url = request.url,
              let rule = rules.first(where: { $0.matches(url.absoluteString) }) else { return nil }
        var headers = rule.headers.filter { $0.key.lowercased() != "content-type" }
        headers["Content-Type"] = rule.contentType
        guard let response = HTTPURLResponse(url: url, statusCode: rule.status, httpVersion: "HTTP/1.1", headerFields: headers) else { return nil }
        return (rule.body, response)
    }

    static func bodyFile(_ name: String, directory: URL) -> URL? {
        guard !name.isEmpty, !name.hasPrefix("/"), !name.hasPrefix("\\"), !name.contains(":"),
              !name.split(whereSeparator: { $0 == "/" || $0 == "\\" }).contains("..") else { return nil }
        let root = directory.resolvingSymlinksInPath().standardizedFileURL
        // resolvingSymlinksInPath 遇到不存在的段会放弃解析整条路径(link/escape.html
        // 原样返回, 前缀判定被绕过) → 解析最深的已存在祖先, 再拼回不存在的尾段。
        var existing = root.appendingPathComponent(name)
        var tail: [String] = []
        while !FileManager.default.fileExists(atPath: existing.path), existing.path != root.path {
            tail.insert(existing.lastPathComponent, at: 0)
            existing = existing.deletingLastPathComponent()
        }
        let target = tail.reduce(existing.resolvingSymlinksInPath()) { $0.appendingPathComponent($1) }
            .standardizedFileURL
        return target.path.hasPrefix(root.path + "/") ? target : nil
    }

    func put(_ object: [String: Any]) throws -> Any {
        let pattern = try ConsoleJSON.string(object, "url_pattern")
        guard !pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              pattern.utf8.count <= 2048, (try? NSRegularExpression(pattern: pattern)) != nil else {
            throw ConsoleFailure("url_pattern must be a valid regex (at most 2048 bytes)")
        }
        let source = try ConsoleJSON.string(object, "body", default: "")
        let bytes: Data
        switch try ConsoleJSON.string(object, "respond_with", default: "html") {
        case "html": bytes = Data(source.utf8)
        case "b64":
            guard let decoded = Data(base64Encoded: source) else { throw ConsoleFailure("body must be valid base64") }
            bytes = decoded
        case "file":
            guard let url = Self.bodyFile(source, directory: directory),
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true, let size = values.fileSize, size <= ConsoleHTTPParser.bodyLimit,
                  let content = try? Data(contentsOf: url) else { throw ConsoleFailure("file must exist inside DebugConsole directory") }
            bytes = content
        default: throw ConsoleFailure("respond_with must be file|b64|html")
        }
        let status = try ConsoleJSON.integer(object, "status", default: 200)
        let contentType = try ConsoleJSON.string(object, "content_type", default: "text/html")
        guard (100...599).contains(status), bytes.count <= ConsoleHTTPParser.bodyLimit,
              !contentType.contains("\r"), !contentType.contains("\n") else { throw ConsoleFailure("invalid status/content_type/body size") }
        let headers: [String: String]
        if let raw = object["headers"] {
            guard let values = raw as? [String: String] else { throw ConsoleFailure("headers must contain strings") }
            headers = values
        } else { headers = [:] }
        guard headers.allSatisfy({ key, value in
            !key.isEmpty && !key.contains(":") && !key.contains("\r") && !key.contains("\n") && !value.contains("\r") && !value.contains("\n")
        }) else { throw ConsoleFailure("invalid headers") }
        let rule = Rule(urlPattern: pattern, status: status, contentType: contentType, headers: headers, body: bytes)
        lock.lock(); defer { lock.unlock() }
        guard active else { throw ConsoleFailure(409, "mock store inactive") }
        guard rules.count < 100, rules.reduce(bytes.count, { $0 + $1.body.count }) <= 16 * 1024 * 1024 else {
            throw ConsoleFailure(413, "mock storage limit exceeded")
        }
        // 上游追加顺序=匹配优先级；重复 pattern 不覆盖，DELETE 删除全部同 pattern。
        let next = rules + [rule]
        try persist(next)
        return ["url_pattern": pattern, "bytes": bytes.count, "rules_total": rules.count]
    }

    func delete(_ object: [String: Any]) throws -> Any {
        lock.lock(); defer { lock.unlock() }
        if object["url_pattern"] != nil {
            let pattern = try ConsoleJSON.string(object, "url_pattern")
            guard rules.contains(where: { $0.urlPattern == pattern }) else { throw ConsoleFailure(404, "no matching rule") }
            try persist(rules.filter { $0.urlPattern != pattern })
            return ["removed": pattern]
        }
        guard try ConsoleJSON.bool(object, "all") else { throw ConsoleFailure("requires url_pattern or all:true") }
        try persist([])
        return ["cleared": true]
    }

    func clear() throws { _ = try delete(["all": true]) }

    private func persist(_ next: [Rule]) throws {
        try ConsoleStorage.save(JSONEncoder().encode(next), to: file)
        rules = next
    }
}
#endif
