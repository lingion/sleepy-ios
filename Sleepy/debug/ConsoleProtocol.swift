#if DEBUG && !WIDGET_EXT && !WATCH_APP
import Foundation
import CoreFoundation
import Security

struct ConsoleFailure: Error {
    let code: Int
    let message: String
    init(_ code: Int, _ message: String) { self.code = code; self.message = message }
    init(_ message: String) { self.init(400, message) }
}

struct ConsoleResponse {
    let status: Int
    let body: Data

    static func ok(_ data: Any = [String: Any]()) -> ConsoleResponse {
        encode(200, ["ok": true, "data": data])
    }

    static func error(_ code: Int, _ message: String) -> ConsoleResponse {
        encode(code, ["ok": false, "error": message, "code": code])
    }

    private static func encode(_ code: Int, _ object: [String: Any]) -> ConsoleResponse {
        guard JSONSerialization.isValidJSONObject(object),
              let body = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            return ConsoleResponse(status: 500, body: Data("{\"ok\":false,\"error\":\"response encoding failed\",\"code\":500}".utf8))
        }
        return ConsoleResponse(status: code, body: body)
    }

    var wireData: Data {
        let header = "HTTP/1.1 \(status) \(status == 200 ? "OK" : "Error")\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\n\r\n"
        return Data(header.utf8) + body
    }
}

struct ConsoleRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data
    var query: [String: String] = [:]

    func object() throws -> [String: Any] {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            throw ConsoleFailure("body must be a JSON object")
        }
        return object
    }
}

/// 单连接单请求；拒绝歧义分帧，不支持 chunked/流水线。
struct ConsoleHTTPParser {
    static let headerLimit = 16 * 1024
    static let bodyLimit = 1024 * 1024
    private var buffer = Data()

    mutating func append(_ data: Data) throws -> ConsoleRequest? {
        guard data.count <= Self.headerLimit + Self.bodyLimit - buffer.count else {
            throw ConsoleFailure(413, "request too large")
        }
        buffer.append(data)
        guard let boundary = buffer.range(of: Data("\r\n\r\n".utf8)) else {
            guard buffer.count <= Self.headerLimit else { throw ConsoleFailure(431, "headers too large") }
            return nil
        }
        guard boundary.upperBound <= Self.headerLimit,
              let head = String(data: buffer[..<boundary.lowerBound], encoding: .utf8) else {
            throw ConsoleFailure(400, "invalid headers")
        }
        let lines = head.components(separatedBy: "\r\n")
        let start = lines[0].split(separator: " ", omittingEmptySubsequences: false)
        guard start.count == 3, ["HTTP/1.0", "HTTP/1.1"].contains(String(start[2])),
              ["GET", "POST", "DELETE"].contains(String(start[0])),
              start[1].hasPrefix("/"), !start[1].hasPrefix("//"), !start[1].contains("#") else {
            throw ConsoleFailure("invalid request line")
        }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":"), colon != line.startIndex else {
                throw ConsoleFailure("invalid header")
            }
            let name = String(line[..<colon]).lowercased()
            guard name.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }),
                  headers[name] == nil else { throw ConsoleFailure("duplicate or invalid header") }
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard !value.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) else {
                throw ConsoleFailure("invalid header value")
            }
            headers[name] = value
        }
        guard headers["transfer-encoding"] == nil else { throw ConsoleFailure("chunked requests unsupported") }
        guard headers["expect"] == nil else { throw ConsoleFailure(417, "Expect unsupported") }
        let rawLength = headers["content-length"] ?? "0"
        guard !rawLength.isEmpty, rawLength.utf8.allSatisfy({ (48...57).contains($0) }),
              let length = Int(rawLength), length <= Self.bodyLimit else {
            throw ConsoleFailure(413, "invalid or oversized Content-Length")
        }
        let end = boundary.upperBound + length
        guard buffer.count >= end else { return nil }
        guard buffer.count == end else { throw ConsoleFailure("pipelining unsupported") }
        let path = String(start[1].split(separator: "?", maxSplits: 1)[0])
        var query: [String: String] = [:]
        for item in URLComponents(string: String(start[1]))?.queryItems ?? [] { query[item.name] = item.value ?? "" }
        return ConsoleRequest(method: String(start[0]), path: path, headers: headers,
                              body: Data(buffer[boundary.upperBound..<end]), query: query)
    }
}

/// 与业务虚拟时间隔离：过期计时只取单调时钟，token 不持久化/不入日志。
final class ConsoleTokenStore {
    private var token: String?
    private var issuedAt: TimeInterval = 0
    private let now: () -> TimeInterval
    static let ttl: TimeInterval = 24 * 3600

    init(now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) { self.now = now }

    func issue() throws -> String {
        if let token, valid(token) { return token }
        var bytes = [UInt8](repeating: 0, count: 32)
        let result = bytes.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, $0.count, $0.baseAddress!) }
        guard result == errSecSuccess else { throw ConsoleFailure(500, "token generation failed") }
        let value = bytes.map { String(format: "%02x", $0) }.joined()
        token = value
        issuedAt = now()
        return value
    }

    func valid(_ candidate: String?) -> Bool {
        guard let token, let candidate, now() - issuedAt >= 0, now() - issuedAt < Self.ttl else { return false }
        let a = Array(token.utf8), b = Array(candidate.utf8)
        guard a.count == b.count else { return false }
        return zip(a, b).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }

    func revoke() { token = nil; issuedAt = 0 }
}

@MainActor
final class ConsoleRouter {
    typealias Handler = (ConsoleRequest) throws -> Any
    typealias AsyncHandler = (ConsoleRequest) async throws -> Any
    var active = false
    let tokens: ConsoleTokenStore
    private var routes: [String: Handler] = [:]
    private var asyncRoutes: [String: AsyncHandler] = [:]
    var paths: [String] { Array(Set((Array(routes.keys) + Array(asyncRoutes.keys)).compactMap { $0.split(separator: " ").last.map(String.init) })).sorted() }

    init(tokens: ConsoleTokenStore = ConsoleTokenStore()) { self.tokens = tokens }
    func register(_ method: String, _ path: String, _ handler: @escaping Handler) { routes["\(method) \(path)"] = handler }
    func registerAsync(_ method: String, _ path: String, _ handler: @escaping AsyncHandler) {
        asyncRoutes["\(method) \(path)"] = handler
    }
    func stop() { active = false; tokens.revoke(); routes.removeAll(); asyncRoutes.removeAll() }

    private func rejection(_ request: ConsoleRequest) -> ConsoleResponse? {
        // 本机浏览器不属于控制面客户端；不提供 CORS/网页驱动执行入口。
        guard request.headers["origin"] == nil, request.headers["sec-fetch-site"] == nil else {
            return .error(403, "browser-origin requests refused")
        }
        let publicPath = request.path == "/v1/hello" || request.path == "/v1/enable"
        if !publicPath && (!active || !tokens.valid(request.headers["x-sleepy-token"])) {
            return .error(401, "unauthorized")
        }
        return nil
    }

    func dispatchAsync(_ request: ConsoleRequest) async -> ConsoleResponse {
        if Task.isCancelled { return .error(503, "request cancelled") }
        if let rejected = rejection(request) { return rejected }
        guard let handler = asyncRoutes["\(request.method) \(request.path)"] else { return dispatch(request) }
        do { return .ok(try await handler(request)) }
        catch let failure as ConsoleFailure { return .error(failure.code, failure.message) }
        catch { return .error(500, "command failed") }
    }

    func dispatch(_ request: ConsoleRequest) -> ConsoleResponse {
        if let rejected = rejection(request) { return rejected }
        guard let handler = routes["\(request.method) \(request.path)"] else { return .error(404, "unknown route") }
        do { return .ok(try handler(request)) }
        catch let failure as ConsoleFailure { return .error(failure.code, failure.message) }
        catch { return .error(500, "command failed") }
    }
}

enum ConsoleJSON {
    static func string(_ o: [String: Any], _ key: String, default fallback: String? = nil) throws -> String {
        if o[key] == nil, let fallback { return fallback }
        guard let value = o[key] as? String else { throw ConsoleFailure("\(key) must be a string") }
        return value
    }
    static func integer(_ o: [String: Any], _ key: String, default fallback: Int? = nil) throws -> Int {
        if o[key] == nil, let fallback { return fallback }
        guard let n = o[key] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
              n.doubleValue.isFinite, abs(n.doubleValue) <= 9_007_199_254_740_991,
              let value = Int(exactly: n.doubleValue) else { throw ConsoleFailure("\(key) must be an integer") }
        return value
    }
    static func bool(_ o: [String: Any], _ key: String, default fallback: Bool = false) throws -> Bool {
        guard let raw = o[key] else { return fallback }
        guard let n = raw as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else {
            throw ConsoleFailure("\(key) must be a boolean")
        }
        return n.boolValue
    }
    static func encoded<T: Encodable>(_ value: T) throws -> Any {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
    }
}
#endif
