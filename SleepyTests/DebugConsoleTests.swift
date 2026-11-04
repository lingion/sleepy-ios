#if DEBUG
import XCTest
import Network
import UIKit
@testable import Sleepy

final class DebugConsoleTests: XCTestCase {
    private func request(_ method: String = "POST", _ path: String, token: String? = nil,
                         body: [String: Any] = [:]) throws -> ConsoleRequest {
        ConsoleRequest(method: method, path: path, headers: token.map { ["x-sleepy-token": $0] } ?? [:],
                       body: try JSONSerialization.data(withJSONObject: body))
    }

    func testHTTPUTF8BodySurvivesEveryPacketBoundary() throws {
        let body = Data("{\"text\":\"线性代数\"}".utf8)
        let wire = Data("POST /v1/data/course HTTP/1.1\r\nContent-Length: \(body.count)\r\nX-Sleepy-Token: abc\r\n\r\n".utf8) + body
        for boundary in 1..<wire.count {
            var parser = ConsoleHTTPParser()
            XCTAssertNil(try parser.append(Data(wire.prefix(boundary))))
            let result = try XCTUnwrap(parser.append(Data(wire.dropFirst(boundary))))
            XCTAssertEqual(result.body, body)
            XCTAssertEqual(result.path, "/v1/data/course")
            XCTAssertEqual(result.headers["x-sleepy-token"], "abc")
        }
    }

    func testHTTPRejectsAmbiguousLengthsChunkingAndPipeline() {
        let malformed = [
            "POST /v1/clock HTTP/1.1\r\nContent-Length: 0\r\ncontent-length: 1\r\n\r\nx",
            "POST /v1/clock HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n",
            "POST /v1/clock HTTP/1.1\r\nContent-Length: -1\r\n\r\n",
            "POST /v1/clock HTTP/1.1\r\nContent-Length: 1048577\r\n\r\n",
            "GET /v1/hello HTTP/1.1\r\n\r\nGET /v1/clock HTTP/1.1\r\n\r\n"
        ]
        for wire in malformed {
            var parser = ConsoleHTTPParser()
            XCTAssertThrowsError(try parser.append(Data(wire.utf8)))
        }
        var parser = ConsoleHTTPParser()
        XCTAssertThrowsError(try parser.append(Data(repeating: 65, count: ConsoleHTTPParser.headerLimit + 1)))
    }

    @MainActor
    func testAuthUnknownRoutesExpiryStopAndRestart() throws {
        var monotonic: TimeInterval = 100
        let tokens = ConsoleTokenStore(now: { monotonic })
        let router = ConsoleRouter(tokens: tokens)
        var writes = 0
        router.register("POST", "/v1/write") { _ in writes += 1; return [:] as [String: Any] }
        router.active = true
        let first = try tokens.issue()
        XCTAssertEqual(first.count, 64)
        XCTAssertEqual(router.dispatch(try request("POST", "/unknown")).status, 401)
        XCTAssertEqual(router.dispatch(try request("POST", "/v1/write", token: "bad")).status, 401)
        XCTAssertEqual(router.dispatch(try request("POST", "/unknown", token: first)).status, 404)
        XCTAssertEqual(router.dispatch(try request("POST", "/v1/write", token: first)).status, 200)
        monotonic += ConsoleTokenStore.ttl
        XCTAssertEqual(router.dispatch(try request("POST", "/v1/write", token: first)).status, 401)
        let second = try tokens.issue()
        XCTAssertNotEqual(first, second)
        router.stop()
        XCTAssertFalse(tokens.valid(second))
        XCTAssertEqual(router.dispatch(try request("POST", "/v1/write", token: second)).status, 401)
        XCTAssertTrue(router.paths.isEmpty)
        XCTAssertEqual(writes, 1)
    }

    @MainActor
    func testHelloCannotBeReadFromBrowserOrigin() throws {
        let router = ConsoleRouter()
        router.register("POST", "/v1/hello") { _ in ["token": "must-not-leak"] }
        let result = router.dispatch(ConsoleRequest(method: "POST", path: "/v1/hello",
            headers: ["origin": "https://example.com"], body: Data()))
        XCTAssertEqual(result.status, 403)
        XCTAssertFalse(String(decoding: result.body, as: UTF8.self).contains("must-not-leak"))
    }

    func testClockOffsetsComposeAndTokenTTLDoesNotUseVirtualTime() throws {
        defer { AppClock.reset() }
        AppClock.reset()
        let real = Date(timeIntervalSince1970: 1_800_000_000)
        let tokens = ConsoleTokenStore(now: { 100 })
        let token = try tokens.issue()
        _ = try AppClock.apply(["mode": "absolute", "dayOffset": 7], realNow: real)
        let next = try AppClock.apply(["mode": "offset", "deltaMs": -1000], realNow: real)
        XCTAssertEqual(next["offsetMs"] as? Double, 604_799_000)
        XCTAssertTrue(tokens.valid(token))
        XCTAssertThrowsError(try AppClock.apply(["mode": "offset", "deltaMs": true], realNow: real))
        XCTAssertEqual(AppClock.debugOffset, 604_799_000)
        _ = try AppClock.apply(["mode": "reset"], realNow: real)
        XCTAssertEqual(AppClock.debugOffset, 0)
    }

    /// 共享接线验收：只改变 console 自己的 GET 返回值不能通过此测试。
    func testBusinessWeekAndTodayConsumeVirtualClock() throws {
        defer { AppClock.reset() }
        let virtual = try XCTUnwrap(DateUtils.isoCalendar.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 12)))
        _ = try AppClock.apply(["mode": "absolute", "epochMs": Int(virtual.timeIntervalSince1970 * 1000)])
        // 周二锚点在 CI 不同时区归一到同一周，避免 CST 零点落在前一天周日。
        XCTAssertEqual(DateUtils.currentWeek(startDate: "2026-09-08"), 2)
        XCTAssertEqual(DateUtils.todayDayOfWeek(), 1)
        XCTAssertTrue(DateUtils.isDateToday(virtual))
    }

    @MainActor
    func testInvalidCourseBatchWritesNothingThenValidBatchPreservesExplicitGroups() throws {
        let repo = ScheduleRepository(try AppDatabase.inMemory())
        let handlers = ConsoleDataHandlers(repository: repo)
        let id = try repo.insertTable(TimeTableEntity(name: "console:test", startDate: "2026-09-07"))
        let good: [String: Any] = ["courseName": "数学", "groupId": "fixture-group", "day": 1,
            "startNode": 1, "step": 2, "startWeek": 1, "endWeek": 16]
        var bad = good; bad["day"] = 8
        XCTAssertThrowsError(try handlers.course(["tableId": id, "courses": [good, bad]]))
        XCTAssertTrue(try repo.getCourses(id).isEmpty)
        _ = try handlers.course(["tableId": id, "courses": [good]])
        let rows = try repo.getCourses(id)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.groupId, "fixture-group")
        XCTAssertEqual(rows.first?.tableId, id)
    }

    @MainActor
    func testReservedPrefsRejectWholeBatchAndResetPreservesUserTables() throws {
        let suite = "DebugConsoleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); AppClock.reset() }
        let repo = ScheduleRepository(try AppDatabase.inMemory())
        let handlers = ConsoleDataHandlers(repository: repo, prefs: AppPrefs(defaults: defaults), prefsDomain: suite)
        defaults.set("original", forKey: "fixture")
        XCTAssertThrowsError(try handlers.putPrefs(["fixture": "changed", "console_token": "forbidden"]))
        XCTAssertEqual(defaults.string(forKey: "fixture"), "original")
        let user = try repo.insertTable(TimeTableEntity(name: "我的课程", startDate: "2026-09-07"))
        let fixture = try repo.insertTable(TimeTableEntity(name: "console:temporary", startDate: "2026-09-07"))
        _ = try handlers.resetSession()
        XCTAssertNotNil(try repo.getTable(user))
        XCTAssertNil(try repo.getTable(fixture))
        XCTAssertEqual(defaults.string(forKey: "fixture"), "original")
    }

    func testSelectorUsesANDAndStableIndexWithoutFallback() throws {
        let nodes = [
            ConsoleUINode(tag: "save", text: "保存", className: "UIButton", role: "Button", clickable: true, reachable: true, bounds: .zero),
            ConsoleUINode(tag: "save", text: "保存副本", className: "UIButton", role: "Button", clickable: true, reachable: true, bounds: .zero)
        ]
        XCTAssertEqual(try ConsoleUISelector(["testTag": "save", "text": "保存", "clickable": true]).select(nodes).count, 1)
        XCTAssertTrue(try ConsoleUISelector(["testTag": "save", "clickable": false]).select(nodes).isEmpty)
        XCTAssertEqual(try ConsoleUISelector(["textContains": "保存", "index": 1]).select(nodes).first?.text, "保存副本")
        XCTAssertTrue(try ConsoleUISelector(["testTag": "save", "index": -1]).select(nodes).isEmpty)
        XCTAssertThrowsError(try ConsoleUISelector(["index": 0]))
    }

    @MainActor
    func testNativeUIActionInvokesRealControlAndScreenshotIsPNG() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKey = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
        let controller = UIViewController()
        window.rootViewController = controller
        let button = UIButton(frame: CGRect(x: 20, y: 20, width: 100, height: 44))
        button.accessibilityIdentifier = "fixture.save"
        button.accessibilityLabel = "保存"
        var tapped = 0
        button.addAction(UIAction { _ in tapped += 1 }, for: .touchUpInside)
        controller.view.addSubview(button)
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        defer { window.isHidden = true; previousKey?.makeKeyAndVisible() }
        let ui = ConsoleUIHandlers(root: nil, window: { window })
        _ = try ui.action(["action": "tap", "selector": ["testTag": "fixture.save"]])
        XCTAssertEqual(tapped, 1)
        XCTAssertThrowsError(try ui.action(["action": "tap", "selector": ["testTag": "missing"]]))
        XCTAssertEqual(tapped, 1)
        let screenshot = try XCTUnwrap(ui.screenshot() as? [String: Any])
        let png = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(screenshot["image"] as? String)))
        XCTAssertEqual(Array(png.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
        XCTAssertEqual(screenshot["bytes"] as? Int, png.count)
    }

    @MainActor
    func testRealLoopbackListenerReturnsAuthenticatedEnvelope() async throws {
        let router = ConsoleRouter()
        router.active = true
        let token = try router.tokens.issue()
        router.register("GET", "/v1/fixture") { _ in ["value": "真实回环"] }
        let listener = ConsoleListener(router: router)
        defer { listener.stop(); router.stop() }
        let ready = expectation(description: "loopback listening")
        var port: UInt16 = 0
        listener.onReady = { port = $0; ready.fulfill() }
        try listener.start(port: 0)
        await fulfillment(of: [ready], timeout: 5)
        var request = URLRequest(url: try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/v1/fixture")))
        request.setValue(token, forHTTPHeaderField: "X-Sleepy-Token")
        let (body, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(envelope["ok"] as? Bool, true)
        XCTAssertEqual((envelope["data"] as? [String: Any])?["value"] as? String, "真实回环")
        router.stop()
        let (_, revoked) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((revoked as? HTTPURLResponse)?.statusCode, 401)
        listener.stop()
        request.timeoutInterval = 1
        do {
            _ = try await URLSession.shared.data(for: request)
            XCTFail("stopped listener must not accept another HTTP request")
        } catch {
            XCTAssertFalse(router.tokens.valid(token))
        }
    }

    @MainActor
    func testIncompleteRequestTimesOutWithoutExecutingRoute() async throws {
        let router = ConsoleRouter()
        var commands = 0
        router.register("POST", "/v1/hello") { _ in commands += 1; return ["ok": true] }
        let listener = ConsoleListener(router: router, requestTimeout: 0.1)
        defer { listener.stop(); router.stop() }
        let ready = expectation(description: "ready")
        var port: UInt16 = 0
        listener.onReady = { port = $0; ready.fulfill() }
        try listener.start(port: 0)
        await fulfillment(of: [ready], timeout: 5)
        let closed = expectation(description: "partial request closed by deadline")
        let client = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        defer { client.cancel() }
        client.start(queue: .main)
        client.send(content: Data("POST /v1/hello HTTP/1.1\r\nContent-Length: 100\r\n\r\n{".utf8), completion: .contentProcessed { _ in })
        client.receive(minimumIncompleteLength: 1, maximumLength: 1024) { _, _, complete, error in
            XCTAssertTrue(complete || error != nil)
            closed.fulfill()
        }
        await fulfillment(of: [closed], timeout: 5)
        XCTAssertEqual(commands, 0)
    }
}
#endif
