import Foundation

struct WebDAVConfig: Codable, Equatable {
    var serverURL: String
    var directory: String
    var username: String = ""
}

struct WebDAVConnection: Codable, Equatable {
    let config: WebDAVConfig
    let password: String

    static func draft(config: WebDAVConfig, enteredPassword: String, saved: Self?) -> Self {
        let config = normalized(config)
        let sameDestination = saved.map { normalized($0.config) == config } ?? false
        let password = enteredPassword.isEmpty && sameDestination ? (saved?.password ?? "") : enteredPassword
        return Self(config: config, password: password)
    }

    private static func normalized(_ config: WebDAVConfig) -> WebDAVConfig {
        WebDAVConfig(serverURL: config.serverURL.trimmingCharacters(in: .whitespacesAndNewlines),
                     directory: config.directory.trimmingCharacters(in: .whitespacesAndNewlines)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "/")),
                     username: config.username.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

struct WebDAVRemoteBackup: Equatable, Identifiable {
    var id: String { fileName }
    let fileName: String
    let sizeBytes: Int64
    let modifiedAt: Date?
}

enum WebDAVError: Error, Equatable {
    case invalidConfiguration
    case httpsRequired
    case authentication
    case forbidden
    case redirectRefused
    case alreadyExists
    case httpStatus(Int)
    case fileTooLarge
    case invalidResponse
    case network
}

struct WebDAVResponse {
    let statusCode: Int
    var bytes = Data()
}

protocol WebDAVTransport {
    func send(_ request: URLRequest, maximumResponseBytes: Int) async throws -> WebDAVResponse
}

/// User-triggered transfer of .sleepybackup archives. Configuration and credentials
/// are supplied by the caller and do not participate in the backup payload.
struct WebDAVClient {
    static let maximumBackupBytes = 100 * 1024 * 1024
    private static let maximumXMLBytes = 2 * 1024 * 1024

    private let transport: WebDAVTransport

    init(transport: WebDAVTransport = WebDAVURLSessionTransport.shared) {
        self.transport = transport
    }

    /// A missing backup folder is created underneath the configured server root.
    /// Call only after the user chooses to test/setup this destination.
    func testConnection(config: WebDAVConfig, password: String) async throws {
        let target = try Target(config, password: password)
        var result = try await propfind(target, depth: "0")
        if result.statusCode == 404 {
            for prefix in target.prefixes {
                let response = try await send(target.request(.mkcol, url: prefix), limit: 0)
                try requireStatus(response, [201, 405])
            }
            result = try await propfind(target, depth: "0")
        }
        try requireStatus(result, [207])
        let entries = try WebDAVMultiStatus.parse(result.bytes)
        guard entries.contains(where: {
            $0.isCollection && target.relativePath(for: $0.href) == []
        }) else { throw WebDAVError.invalidResponse }
    }

    func listBackups(config: WebDAVConfig, password: String) async throws -> [WebDAVRemoteBackup] {
        let target = try Target(config, password: password)
        let result = try await propfind(target, depth: "1")
        try requireStatus(result, [207])
        var seen = Set<String>()
        let timestamp = Self.modifiedDateFormatter()
        return try WebDAVMultiStatus.parse(result.bytes).compactMap { entry -> WebDAVRemoteBackup? in
            guard !entry.isCollection, let path = target.relativePath(for: entry.href), path.count == 1,
                  let name = path.first, Self.isBackupName(name), seen.insert(name).inserted else { return nil }
            return WebDAVRemoteBackup(fileName: name, sizeBytes: entry.sizeBytes,
                                      modifiedAt: timestamp.date(from: entry.modified))
        }.sorted { first, second in
            let a = first.modifiedAt ?? .distantPast
            let b = second.modifiedAt ?? .distantPast
            return a == b ? first.fileName < second.fileName : a > b
        }
    }

    func upload(config: WebDAVConfig, password: String, fileName: String, bytes: Data) async throws {
        guard bytes.count <= Self.maximumBackupBytes else { throw WebDAVError.fileTooLarge }
        guard !bytes.isEmpty else { throw WebDAVError.invalidResponse }
        let target = try Target(config, password: password)
        let url = try target.fileURL(fileName)
        let response = try await send(target.request(.put, url: url, body: bytes), limit: 0)
        try requireStatus(response, [200, 201, 204])
    }

    func download(config: WebDAVConfig, password: String, fileName: String) async throws -> Data {
        let target = try Target(config, password: password)
        let url = try target.fileURL(fileName)
        let response = try await send(target.request(.get, url: url), limit: Self.maximumBackupBytes)
        try requireStatus(response, [200])
        guard !response.bytes.isEmpty else { throw WebDAVError.invalidResponse }
        return response.bytes
    }

    private func propfind(_ target: Target, depth: String) async throws -> WebDAVResponse {
        let body = Data("""
            <?xml version="1.0" encoding="utf-8"?>
            <d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/><d:getlastmodified/><d:getcontentlength/></d:prop></d:propfind>
            """.utf8)
        var request = target.request(.propfind, url: target.directory, body: body)
        request.setValue(depth, forHTTPHeaderField: "Depth")
        return try await send(request, limit: Self.maximumXMLBytes)
    }

    private func send(_ request: URLRequest, limit: Int) async throws -> WebDAVResponse {
        do {
            try Task.checkCancellation()
            let response = try await transport.send(request, maximumResponseBytes: limit)
            try Task.checkCancellation()
            if (200...299).contains(response.statusCode), limit > 0, response.bytes.count > limit {
                throw WebDAVError.fileTooLarge
            }
            return response
        } catch let error as WebDAVError {
            throw error
        } catch {
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            throw WebDAVError.network
        }
    }

    private func requireStatus(_ response: WebDAVResponse, _ accepted: Set<Int>) throws {
        let status = response.statusCode
        guard !accepted.contains(status) else { return }
        switch status {
        case 300...399: throw WebDAVError.redirectRefused
        case 401: throw WebDAVError.authentication
        case 403: throw WebDAVError.forbidden
        case 412: throw WebDAVError.alreadyExists
        case 413: throw WebDAVError.fileTooLarge
        default: throw WebDAVError.httpStatus(status)
        }
    }

    private static func isBackupName(_ name: String) -> Bool {
        name.range(of: #"\A[A-Za-z0-9._-]{1,180}\.sleepybackup\z"#,
                   options: [.regularExpression, .caseInsensitive]) != nil &&
            name.unicodeScalars.allSatisfy(\.isASCII)
    }

    private static func modifiedDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }

    private enum Method: String {
        case propfind = "PROPFIND", mkcol = "MKCOL", put = "PUT", get = "GET"
    }

    private struct Target {
        let directory: URL
        let prefixes: [URL]
        let directorySegments: [String]
        let authorization: String?
        let host: String
        let port: Int

        init(_ config: WebDAVConfig, password: String) throws {
            guard var parts = URLComponents(string: config.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)),
                  let host = parts.host, !host.isEmpty, let scheme = parts.scheme else {
                throw WebDAVError.invalidConfiguration
            }
            guard scheme.lowercased() == "https" else { throw WebDAVError.httpsRequired }
            guard parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
                  (1...65_535).contains(parts.port ?? 443),
                  let base = Self.pathSegments(parts.percentEncodedPath) else { throw WebDAVError.invalidConfiguration }

            let user = config.username.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !user.contains(":"), user.rangeOfCharacter(from: .controlCharacters) == nil,
                  !user.isEmpty || password.isEmpty else { throw WebDAVError.invalidConfiguration }
            let relative = config.directory.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                .components(separatedBy: "/")
            guard relative.allSatisfy(Self.isPathSegment) else { throw WebDAVError.invalidConfiguration }

            var urls: [URL] = []
            var segments = base
            parts.scheme = "https"
            for component in relative {
                segments.append(component)
                parts.path = "/" + segments.joined(separator: "/") + "/"
                guard let url = parts.url else { throw WebDAVError.invalidConfiguration }
                urls.append(url)
            }
            guard let directory = urls.last else { throw WebDAVError.invalidConfiguration }
            self.directory = directory
            self.prefixes = urls
            self.directorySegments = segments
            self.authorization = user.isEmpty ? nil : "Basic " + Data("\(user):\(password)".utf8).base64EncodedString()
            self.host = host
            self.port = parts.port ?? 443
        }

        func fileURL(_ name: String) throws -> URL {
            guard isBackupName(name) else { throw WebDAVError.invalidConfiguration }
            return directory.appendingPathComponent(name, isDirectory: false)
        }

        /// Interpret servers' absolute or relative hrefs without assigning them permission
        /// to redirect a download. Only the direct filename is retained by listBackups.
        func relativePath(for href: String) -> [String]? {
            guard !href.isEmpty, let url = URL(string: href, relativeTo: directory)?.absoluteURL,
                  let parts = URLComponents(url: url, resolvingAgainstBaseURL: true),
                  parts.scheme?.lowercased() == "https", parts.host?.caseInsensitiveCompare(host) == .orderedSame,
                  (parts.port ?? 443) == port, parts.user == nil, parts.password == nil,
                  parts.query == nil, parts.fragment == nil,
                  let path = Self.pathSegments(parts.percentEncodedPath),
                  path.starts(with: directorySegments) else { return nil }
            return Array(path.dropFirst(directorySegments.count))
        }

        func request(_ method: Method, url: URL, body: Data? = nil) -> URLRequest {
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
            request.httpMethod = method.rawValue
            request.httpBody = body
            request.setValue(authorization, forHTTPHeaderField: "Authorization")
            request.setValue(method == .propfind ? "application/xml, text/xml" : "*/*", forHTTPHeaderField: "Accept")
            if method == .propfind { request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type") }
            if method == .put {
                request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
                request.setValue("*", forHTTPHeaderField: "If-None-Match")
            }
            return request
        }

        private static func pathSegments(_ encoded: String) -> [String]? {
            let innerPath = encoded.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !innerPath.isEmpty else { return [] }
            var result: [String] = []
            for part in innerPath.components(separatedBy: "/") {
                guard let decoded = part.removingPercentEncoding, isPathSegment(decoded) else { return nil }
                result.append(decoded)
            }
            return result
        }

        private static func isPathSegment(_ segment: String) -> Bool {
            !segment.isEmpty && segment != "." && segment != ".." &&
                segment.rangeOfCharacter(from: CharacterSet(charactersIn: "/\\").union(.controlCharacters)) == nil
        }
    }
}

/// No redirect may carry Basic authentication to an unapproved endpoint.
/// URLSession's standard TLS validation remains enabled.
final class WebDAVURLSessionTransport: WebDAVTransport {
    static let shared = WebDAVURLSessionTransport()

    final class RefuseRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    private let session: URLSession

    init(configuration: URLSessionConfiguration = .ephemeral) {
        configuration.timeoutIntervalForResource = 45
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        session = URLSession(configuration: configuration, delegate: RefuseRedirects(), delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }

    func send(_ request: URLRequest, maximumResponseBytes: Int) async throws -> WebDAVResponse {
        let (stream, raw) = try await session.bytes(for: request)
        defer { stream.task.cancel() }
        guard let response = raw as? HTTPURLResponse else { throw WebDAVError.invalidResponse }
        let status = response.statusCode
        guard (200...299).contains(status), maximumResponseBytes > 0 else { return WebDAVResponse(statusCode: status) }
        guard response.expectedContentLength <= Int64(maximumResponseBytes) else { throw WebDAVError.fileTooLarge }
        var bytes = Data()
        for try await byte in stream {
            guard bytes.count < maximumResponseBytes else { throw WebDAVError.fileTooLarge }
            bytes.append(byte)
        }
        return WebDAVResponse(statusCode: status, bytes: bytes)
    }
}

/// Read DAV property sets only when their individual HTTP status succeeded.
private final class WebDAVMultiStatus: NSObject, XMLParserDelegate {
    struct Entry {
        var href = ""
        var isCollection = false
        var sizeBytes: Int64 = 0
        var modified = ""
        var readable = false
        var responseOK = true
    }

    private struct PropertySet {
        var isCollection: Bool?
        var sizeBytes: Int64?
        var modified: String?
        var successful = false
    }

    private var path: [String] = []
    private var multistatus = false
    private var entry: Entry?
    private var properties: PropertySet?
    private var text = ""
    private var results: [Entry] = []

    static func parse(_ bytes: Data) throws -> [Entry] {
        // DAV is requested as UTF-8. Reject declarations that could expand entities before parsing.
        guard !bytes.contains(0), let xml = String(data: bytes, encoding: .utf8),
              !xml.contains("<!DOCTYPE"), !xml.contains("<!ENTITY") else { throw WebDAVError.invalidResponse }
        let document = WebDAVMultiStatus()
        let parser = XMLParser(data: bytes)
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = document
        guard parser.parse(), document.multistatus else { throw WebDAVError.invalidResponse }
        return document.results
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        guard path.count < 32 else { parser.abortParsing(); return }
        path.append(namespaceURI == "DAV:" ? elementName : "")
        text = ""
        switch path {
        case ["multistatus"]: multistatus = true
        case ["multistatus", "response"]: entry = Entry()
        case ["multistatus", "response", "propstat"]: properties = PropertySet()
        case ["multistatus", "response", "propstat", "prop", "resourcetype"]: properties?.isCollection = false
        case ["multistatus", "response", "propstat", "prop", "resourcetype", "collection"]: properties?.isCollection = true
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        text += String(decoding: CDATABlock, as: UTF8.self)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch path {
        case ["multistatus", "response", "href"]: entry?.href = value
        case ["multistatus", "response", "status"]: entry?.responseOK = Self.isSuccess(value)
        case ["multistatus", "response", "propstat", "status"]: properties?.successful = Self.isSuccess(value)
        case ["multistatus", "response", "propstat", "prop", "getcontentlength"]:
            properties?.sizeBytes = Int64(value).flatMap { $0 >= 0 ? $0 : nil }
        case ["multistatus", "response", "propstat", "prop", "getlastmodified"]: properties?.modified = value
        case ["multistatus", "response", "propstat"]:
            if let valid = properties, valid.successful {
                entry?.readable = true
                if let collection = valid.isCollection { entry?.isCollection = collection }
                if let size = valid.sizeBytes { entry?.sizeBytes = size }
                if let modified = valid.modified { entry?.modified = modified }
            }
            properties = nil
        case ["multistatus", "response"]:
            if let readable = entry, readable.readable, readable.responseOK { results.append(readable) }
            entry = nil
        default: break
        }
        path.removeLast()
        text = ""
    }

    private static func isSuccess(_ statusLine: String) -> Bool {
        let fields = statusLine.split(whereSeparator: \.isWhitespace)
        guard fields.count >= 2, fields[0].hasPrefix("HTTP/"), let code = Int(fields[1]) else { return false }
        return (200...299).contains(code)
    }
}
