import XCTest
@testable import Sleepy

private actor WakeUpFixtureTransport: WakeUpShareTransport {
    private var responses: [WakeUpShareHTTPResponse]
    private(set) var requests: [URLRequest] = []

    init(_ responses: [WakeUpShareHTTPResponse]) { self.responses = responses }

    func send(_ request: URLRequest) async throws -> WakeUpShareHTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else { throw URLError(.badServerResponse) }
        return responses.removeFirst()
    }
}

private actor WakeUpCancellableTransport: WakeUpShareTransport {
    let started: XCTestExpectation
    let cancelled: XCTestExpectation
    private(set) var requestCount = 0

    init(started: XCTestExpectation, cancelled: XCTestExpectation) {
        self.started = started
        self.cancelled = cancelled
    }

    func send(_ request: URLRequest) async throws -> WakeUpShareHTTPResponse {
        requestCount += 1
        started.fulfill()
        do {
            try await Task.sleep(nanoseconds: 60_000_000_000)
            throw URLError(.timedOut)
        } catch {
            if Task.isCancelled { cancelled.fulfill() }
            throw error
        }
    }
}

final class WakeUpShareClientTests: XCTestCase {
    private func client(_ transport: WakeUpShareTransport) -> WakeUpShareClient {
        WakeUpShareClient(transport: transport, nowMs: { WakeUpShareFixtures.nowMs }, random: { WakeUpShareFixtures.nonce })
    }

    /// 传输/解包测试的合成响应; 加密字节正确性另由独立 vendor 金标锁定。
    private func encryptedResponse(shareData: String = WakeUpShareFixtures.rawSchedule,
                                   nested: Bool = true) throws -> WakeUpShareHTTPResponse {
        let plain = try JSONSerialization.data(withJSONObject: ["shareData": shareData])
        let encrypted = try WakeUpV6170Crypto.rc4(plain, key: WakeUpShareFixtures.rc4Key).base64EncodedString()
        let data: Any = nested ? ["data": encrypted] : encrypted
        return WakeUpShareHTTPResponse(status: 200, body: try JSONSerialization.data(withJSONObject: ["errNo": 0, "data": data]))
    }

    func testTwoStageHTTPFlowProducesExistingParserInputAndExactShareRequest() async throws {
        let transport = WakeUpFixtureTransport([
            WakeUpShareHTTPResponse(status: 200, body: WakeUpShareFixtures.antispamBody),
            try encryptedResponse()
        ])
        let json = try await client(transport).fetchScheduleJson("【来自WakeUp课程表】分享口令为「AbCdEf123456」")
        let parsed = try ScheduleParser.parse(json, defaultTableId: 42).get()
        XCTAssertEqual(parsed.courses.count, 3)
        XCTAssertEqual(Set(parsed.courses.map(\.courseName)), ["高等数学", "大学英语"])
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        XCTAssertEqual(root["startDate"] as? String, "2025-09-01")
        let info = try XCTUnwrap(root["tableInfo"] as? [String: Any])
        XCTAssertEqual(info["nodesPerDay"] as? Int, 5)
        XCTAssertEqual((info["timeList"] as? [[String: Any]])?.compactMap { $0["node"] as? Int }, [1, 2, 5])
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.map { $0.url?.path }, ["/pluto/app/antispam", "/share_schedule/getv2"])
        for request in requests {
            XCTAssertEqual(request.url?.scheme, "https")
            XCTAssertEqual(request.url?.host, "api.wakeup.fun")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.timeoutInterval, 15)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded; charset=UTF-8")
            XCTAssertEqual(request.value(forHTTPHeaderField: "na__zyb_source__"), "wakeup")
            XCTAssertEqual(request.value(forHTTPHeaderField: "zyb-cuid"), "C77D5D04D94F5F56C8A0A6DC3DBF240A|0")
            XCTAssertEqual(request.value(forHTTPHeaderField: "zyb-adid"), "d58a81f457529caf0e642e7f9d97e447112bd763")
            XCTAssertNil(request.value(forHTTPHeaderField: "zyb-did"))
        }
        XCTAssertTrue(String(decoding: try XCTUnwrap(requests[0].httpBody), as: UTF8.self).hasSuffix("&"))
        XCTAssertEqual(String(decoding: try XCTUnwrap(requests[1].httpBody), as: UTF8.self), WakeUpShareFixtures.shareRequestBody)
    }

    func testFlatEncryptedResponseAndResultSignatureFallback() async throws {
        let body = try JSONSerialization.data(withJSONObject: ["result": ["data": WakeUpShareFixtures.signB]])
        let transport = WakeUpFixtureTransport([.init(status: 200, body: body), try encryptedResponse(nested: false)])
        let raw = try await client(transport).fetchRawShareData("AbCdEf123456")
        XCTAssertEqual(raw, WakeUpShareFixtures.rawSchedule)
    }

    func testInvalidInputDoesNotReachNetworkAndOfflineFormatsDoNotRouteOnline() async throws {
        let transport = WakeUpFixtureTransport([])
        do {
            _ = try await client(transport).fetchScheduleJson("短")
            XCTFail("非法口令应拒绝")
        } catch { XCTAssertEqual(error as? WakeUpShareError, .invalidCode) }
        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
        for text in [#"{"name":"schedule","courses":[]}"#, "BEGIN:VCALENDAR\nEND:VCALENDAR", "<html>abcdefghijk</html>", "sleepy-v1\nt|name=abcdefghijk"] {
            XCTAssertFalse(WakeUpShareClient.looksLikeShareCode(text), text)
        }
        XCTAssertTrue(WakeUpShareClient.looksLikeShareCode("AbCdEf123456"))
        XCTAssertTrue(WakeUpShareClient.looksLikeShareCode("分享口令为「AbCdEf123456」"))
    }

    func testHTTPBusinessAndMalformedResponsesFailBeforeSecondRequest() async throws {
        let cases: [(WakeUpShareHTTPResponse, WakeUpShareError)] = [
            (.init(status: 503, body: Data()), .http(503)),
            (.init(status: 200, body: WakeUpShareFixtures.serverRejection), .service(6)),
            (.init(status: 200, body: WakeUpShareFixtures.invalidJSON), .invalidResponse),
            (.init(status: 200, body: Data(#"{"data":5}"#.utf8)), .missingSignature),
            (.init(status: 200, body: Data(#"{"data":"garbage"}"#.utf8)), .invalidToken)
        ]
        for (response, expected) in cases {
            let transport = WakeUpFixtureTransport([response])
            do {
                _ = try await client(transport).fetchScheduleJson("AbCdEf123456")
                XCTFail("错误响应不能成功")
            } catch { XCTAssertEqual(error as? WakeUpShareError, expected) }
            let requests = await transport.requests
            XCTAssertEqual(requests.count, 1)
        }
    }

    func testMalformedSharePayloadAndExpiredCodeDoNotBecomeSuccessfulImport() async throws {
        let secondResponses: [(WakeUpShareHTTPResponse, WakeUpShareError)] = [
            (.init(status: 200, body: Data(#"{"data":{}}"#.utf8)), .missingEncryptedData),
            (.init(status: 200, body: Data(#"{"data":"%%%"}"#.utf8)), .decryptionFailed),
            (try encryptedResponse(shareData: ""), .incompleteSchedule)
        ]
        for (response, expected) in secondResponses {
            let transport = WakeUpFixtureTransport([.init(status: 200, body: WakeUpShareFixtures.antispamBody), response])
            do {
                _ = try await client(transport).fetchScheduleJson("AbCdEf123456")
                XCTFail("错误载荷不能当作空课表导入")
            } catch { XCTAssertEqual(error as? WakeUpShareError, expected) }
        }
    }

    func testCancellationReachesInFlightTransportAndNeverStartsShareRequest() async throws {
        let started = expectation(description: "antispam started")
        let cancelled = expectation(description: "transport observed cancellation")
        let transport = WakeUpCancellableTransport(started: started, cancelled: cancelled)
        let api = client(transport)
        let task = Task { try await api.fetchScheduleJson("AbCdEf123456") }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("取消必须抛错")
        } catch { XCTAssertTrue(error is CancellationError) }
        await fulfillment(of: [cancelled], timeout: 2)
        let count = await transport.requestCount
        XCTAssertEqual(count, 1)
    }

    func testDateNormalizationAndKeyExtractionMatchVendorExamples() throws {
        XCTAssertEqual(WakeUpShareProtocol.convertToSemesterStartDate("9/1/2025"), "2025-09-01")
        XCTAssertEqual(WakeUpShareProtocol.convertToSemesterStartDate("2025/9/1"), "2025-09-01")
        XCTAssertNil(WakeUpShareProtocol.convertToSemesterStartDate("2025/13/45"))
        XCTAssertNil(WakeUpShareProtocol.convertToSemesterStartDate("2025/2/29"))
        XCTAssertEqual(try WakeUpShareProtocol.validatedKey("分享口令：abcdefgh12345678"), "abcdefgh12345678")
        XCTAssertEqual(try WakeUpShareProtocol.validatedKey("abc-def_ghi jklmnop"), "abc-def_ghi")
        XCTAssertEqual(try WakeUpShareProtocol.validatedKey("「ZXcV34asdfGHjk」"), "ZXcV34asdfGHjk")
        XCTAssertThrowsError(try WakeUpShareProtocol.parseRawScheduleData("{}\n[]"))
    }

    func testOversizedInputResponseAndNodeExpansionFailExplicitly() async throws {
        XCTAssertThrowsError(try WakeUpShareProtocol.normalizeNodes(["nodes": Int.max]))
        let transport = WakeUpFixtureTransport([.init(status: 200,
            body: Data(repeating: 32, count: WakeUpShareURLSessionTransport.maximumResponseBytes + 1))])
        do {
            _ = try await client(transport).fetchScheduleJson("AbCdEf123456")
            XCTFail("超限响应应拒绝")
        } catch { XCTAssertEqual(error as? WakeUpShareError, .responseTooLarge) }
    }

    @MainActor
    func testImportModelCancellationClearsBusyStateWithoutDeliveringPreview() async {
        let started = expectation(description: "sheet request started")
        let cancelled = expectation(description: "sheet request cancelled")
        let transport = WakeUpCancellableTransport(started: started, cancelled: cancelled)
        let model = WakeUpShareImportModel(client: client(transport))
        model.fetch("AbCdEf123456") { _ in XCTFail("取消后不能交付预览") }
        XCTAssertTrue(model.isLoading)
        await fulfillment(of: [started], timeout: 2)
        model.cancel()
        await fulfillment(of: [cancelled], timeout: 2)
        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.errorMessage)
    }
}
