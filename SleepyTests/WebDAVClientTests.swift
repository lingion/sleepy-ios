import Foundation
import XCTest
@testable import Sleepy

private actor WebDAVFixtureTransport: WebDAVTransport {
    struct Call {
        let request: URLRequest
        let limit: Int
    }

    private var responses: [WebDAVResponse]
    private(set) var calls: [Call] = []

    init(_ responses: [WebDAVResponse] = []) { self.responses = responses }

    func send(_ request: URLRequest, maximumResponseBytes: Int) async throws -> WebDAVResponse {
        calls.append(Call(request: request, limit: maximumResponseBytes))
        guard !responses.isEmpty else { throw URLError(.resourceUnavailable) }
        return responses.removeFirst()
    }
}

/// Exercises the real session reader without making a network request.
private final class WebDAVFixtureURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        let announced = url.path == "/announced" ? ["Content-Length": "9"] : [:]
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: announced)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data([1, 2]))
        client?.urlProtocol(self, didLoad: Data([3, 4]))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class WebDAVClientTests: XCTestCase {
    private let config = WebDAVConfig(serverURL: "https://dav.example.test/remote.php/dav/",
                                     directory: "/Sleepy/备份/", username: "student")
    private let directory = "/remote.php/dav/Sleepy/%E5%A4%87%E4%BB%BD/"
    private let safeFile = "sleepy-20261120.sleepybackup"

    func testConnectionChecksTheExactCollectionAndSendsBasicAuth() async throws {
        let transport = WebDAVFixtureTransport([xml([collection(directory)])])
        let client = WebDAVClient(transport: transport)
        try await client.testConnection(config: config, password: "test-only")
        let calls = await transport.calls
        let call = try XCTUnwrap(calls.first)
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(call.request.url?.absoluteString, "https://dav.example.test" + directory)
        XCTAssertEqual(call.request.httpMethod, "PROPFIND")
        XCTAssertEqual(call.request.value(forHTTPHeaderField: "Depth"), "0")
        XCTAssertEqual(call.request.value(forHTTPHeaderField: "Authorization"),
                       "Basic " + Data("student:test-only".utf8).base64EncodedString())
        XCTAssertEqual(call.limit, 2 * 1024 * 1024)
    }

    func testMissingCollectionCreatesPrefixesAndThenVerifies() async throws {
        let transport = WebDAVFixtureTransport([
            .init(statusCode: 404), .init(statusCode: 405), .init(statusCode: 201), xml([collection(directory)])
        ])
        try await WebDAVClient(transport: transport).testConnection(config: config, password: "")
        let calls = await transport.calls
        XCTAssertEqual(calls.map { $0.request.httpMethod }, ["PROPFIND", "MKCOL", "MKCOL", "PROPFIND"])
        XCTAssertEqual(calls.map { $0.request.url?.absoluteString }, [
            "https://dav.example.test" + directory,
            "https://dav.example.test/remote.php/dav/Sleepy/",
            "https://dav.example.test" + directory,
            "https://dav.example.test" + directory
        ])
    }

    func testUnauthorizedAndRedirectDoNotTriggerAnotherRequest() async throws {
        for (status, expected) in [(401, WebDAVError.authentication), (302, .redirectRefused)] {
            let transport = WebDAVFixtureTransport([.init(statusCode: status)])
            await checkError(expected) {
                try await WebDAVClient(transport: transport).testConnection(config: self.config, password: "test-only")
            }
            let count = await transport.calls.count
            XCTAssertEqual(count, 1)
        }
    }

    func testInvalidConfigurationNeverReachesTransport() async throws {
        let transport = WebDAVFixtureTransport()
        let client = WebDAVClient(transport: transport)
        let inputs: [(String, String, String, String, WebDAVError)] = [
            ("http://dav.example.test", "Sleepy", "a", "b", .httpsRequired),
            ("https://a:b@dav.example.test", "Sleepy", "a", "b", .invalidConfiguration),
            ("https://dav.example.test?x=1", "Sleepy", "a", "b", .invalidConfiguration),
            ("https://dav.example.test/%2e%2e/path", "Sleepy", "a", "b", .invalidConfiguration),
            ("https://dav.example.test/one%2Ftwo", "Sleepy", "a", "b", .invalidConfiguration),
            ("https://dav.example.test", "Sleepy/../Other", "a", "b", .invalidConfiguration),
            ("https://dav.example.test", "Sleepy", "a:b", "pass", .invalidConfiguration),
            ("https://dav.example.test", "Sleepy", "", "pass", .invalidConfiguration)
        ]
        for (url, folder, user, password, error) in inputs {
            await checkError(error) {
                try await client.testConnection(config: .init(serverURL: url, directory: folder, username: user),
                                                password: password)
            }
        }
        let count = await transport.calls.count
        XCTAssertEqual(count, 0)
    }

    func testListAcceptsOnlyDirectSameOriginSuccessfulBackupFiles() async throws {
        let first = "a.sleepybackup"
        let second = "z.sleepybackup"
        let transport = WebDAVFixtureTransport([xml([
            collection(directory),
            file(directory + first, bytes: 24, modified: "Wed, 18 Nov 2026 20:00:00 GMT"),
            file(second, bytes: 32, modified: "Thu, 19 Nov 2026 20:00:00 GMT"),
            file(directory + "nested/incorrect.sleepybackup"),
            file(directory + "a%2Fb.sleepybackup"),
            file("https://other.example.test" + directory + "incorrect.sleepybackup"),
            file("https://dav.example.test:8443" + directory + "incorrect.sleepybackup"),
            file(directory + "invalid.sleepybackup?token=x"),
            file(directory + "plain.zip"),
            collection(directory + "folder.sleepybackup"),
            file(directory + "denied.sleepybackup", status: 403),
            file(directory + first)
        ])])
        let files = try await WebDAVClient(transport: transport).listBackups(config: config, password: "")
        let depth = await transport.calls.first?.request.value(forHTTPHeaderField: "Depth")
        XCTAssertEqual(depth, "1")
        XCTAssertEqual(files.map(\.fileName), [second, first])
        XCTAssertEqual(files.map(\.sizeBytes), [32, 24])
    }

    func testWrongResourceOrInvalidXMLFailsConnectionVerification() async throws {
        for response in [
            xml([file(directory)]),
            xml([collection("/other/")]),
            .init(statusCode: 207, bytes: Data("<html/>".utf8)),
            .init(statusCode: 207, bytes: Data(#"<!DOCTYPE d [<!ENTITY example "sample">]><multistatus xmlns="DAV:"/>"#.utf8)),
            .init(statusCode: 207, bytes: "<multistatus xmlns=\"DAV:\"/>".data(using: .utf16LittleEndian)!)
        ] {
            let transport = WebDAVFixtureTransport([response])
            await checkError(.invalidResponse) {
                try await WebDAVClient(transport: transport).testConnection(config: self.config, password: "")
            }
        }
    }

    func testUploadIsAtomicNonOverwriteAtTheServer() async throws {
        let transport = WebDAVFixtureTransport([.init(statusCode: 201), .init(statusCode: 412)])
        let client = WebDAVClient(transport: transport)
        let bytes = Data([1, 2, 3])
        try await client.upload(config: config, password: "", fileName: safeFile, bytes: bytes)
        await checkError(.alreadyExists) {
            try await client.upload(config: self.config, password: "", fileName: self.safeFile, bytes: bytes)
        }
        let calls = await transport.calls
        XCTAssertEqual(calls.map { $0.request.httpMethod }, ["PUT", "PUT"])
        XCTAssertEqual(calls.first?.request.url?.absoluteString, "https://dav.example.test" + directory + safeFile)
        XCTAssertEqual(calls.first?.request.value(forHTTPHeaderField: "If-None-Match"), "*")
        XCTAssertEqual(calls.first?.request.value(forHTTPHeaderField: "Content-Type"), "application/octet-stream")
        XCTAssertEqual(calls.first?.request.httpBody, bytes)
    }

    func testDownloadReturnsRawBytesAndRestrictsFileNames() async throws {
        let transport = WebDAVFixtureTransport([.init(statusCode: 200, bytes: Data([7, 8]))])
        let client = WebDAVClient(transport: transport)
        for name in ["../sync.sleepybackup", "dir/one.sleepybackup", "data.zip", "a%2Fb.sleepybackup"] {
            await checkError(.invalidConfiguration) {
                _ = try await client.download(config: self.config, password: "", fileName: name)
            }
        }
        let data = try await client.download(config: config, password: "", fileName: safeFile)
        let calls = await transport.calls
        XCTAssertEqual(data, Data([7, 8]))
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.request.httpMethod, "GET")
        XCTAssertEqual(calls.first?.limit, 100 * 1024 * 1024)
    }

    func testRejectsTooLargeOrEmptyResponsesBeforeImport() async throws {
        let transport = WebDAVFixtureTransport([
            .init(statusCode: 413), .init(statusCode: 200),
            .init(statusCode: 207, bytes: Data(count: 2 * 1024 * 1024 + 1))
        ])
        let client = WebDAVClient(transport: transport)
        await checkError(.fileTooLarge) {
            _ = try await client.download(config: self.config, password: "", fileName: self.safeFile)
        }
        await checkError(.invalidResponse) {
            _ = try await client.download(config: self.config, password: "", fileName: self.safeFile)
        }
        await checkError(.fileTooLarge) {
            _ = try await client.listBackups(config: self.config, password: "")
        }
    }

    func testSessionStreamEnforcesDeclaredAndReceivedLengths() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WebDAVFixtureURLProtocol.self]
        let transport = WebDAVURLSessionTransport(configuration: configuration)
        let streamed = URLRequest(url: URL(string: "https://dav.example.test/stream")!)
        let announced = URLRequest(url: URL(string: "https://dav.example.test/announced")!)
        let success = try await transport.send(streamed, maximumResponseBytes: 4)
        XCTAssertEqual(success.bytes, Data([1, 2, 3, 4]))
        await checkError(.fileTooLarge) {
            _ = try await transport.send(streamed, maximumResponseBytes: 3)
        }
        await checkError(.fileTooLarge) {
            _ = try await transport.send(announced, maximumResponseBytes: 4)
        }
    }

    func testSavedPasswordNeverFollowsAnEditedDestination() async throws {
        let saved = WebDAVConnection(config: config, password: "remembered")
        XCTAssertEqual(WebDAVConnection.draft(config: config, enteredPassword: "", saved: saved).password,
                       "remembered")
        let other = [
            WebDAVConfig(serverURL: "https://another.example.test", directory: config.directory, username: config.username),
            WebDAVConfig(serverURL: config.serverURL, directory: "Different directory", username: config.username),
            WebDAVConfig(serverURL: config.serverURL, directory: config.directory, username: "different-user")
        ]
        for target in other {
            XCTAssertEqual(WebDAVConnection.draft(config: target, enteredPassword: "", saved: saved).password, "")
            XCTAssertEqual(WebDAVConnection.draft(config: target, enteredPassword: "new", saved: saved).password, "new")
        }
    }

    private func checkError(_ expected: WebDAVError, operation: () async throws -> Void) async {
        do { try await operation(); XCTFail("Expected \(expected)") }
        catch { XCTAssertEqual(error as? WebDAVError, expected) }
    }

    private func xml(_ responses: [String]) -> WebDAVResponse {
        .init(statusCode: 207,
              bytes: Data(("<D:multistatus xmlns:D=\"DAV:\">" + responses.joined() + "</D:multistatus>").utf8))
    }

    private func collection(_ href: String) -> String { entry(href, props: "<D:resourcetype><D:collection/></D:resourcetype>") }

    private func file(_ href: String, bytes: Int = 0, modified: String = "", status: Int = 200) -> String {
        entry(href, props: "<D:resourcetype/><D:getcontentlength>\(bytes)</D:getcontentlength><D:getlastmodified>\(modified)</D:getlastmodified>",
              status: status)
    }

    private func entry(_ href: String, props: String, status: Int = 200) -> String {
        """
        <D:response><D:href>\(href)</D:href><D:propstat>
        <D:prop>\(props)</D:prop><D:status>HTTP/1.1 \(status) Status</D:status>
        </D:propstat></D:response>
        """
    }
}
