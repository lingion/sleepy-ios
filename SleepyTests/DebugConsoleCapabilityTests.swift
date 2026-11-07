#if DEBUG
import XCTest
@testable import Sleepy

final class DebugConsoleCapabilityTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("console-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @MainActor
    func testCatalogChangesRealRowPreservesIdentityAndReloadsPersistence() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("overrides.json")
        let store = ConsoleCatalogStore(file: file)
        store.setActive(true)
        let school = JwSchoolInfo(sortKey: "A", name: "fixture", url: "https://old.example.edu", type: "qz",
                                  status: "unverified", enableFetch: false, catalogId: "identity")
        let command: [String: Any] = ["op": "set", "name": "fixture", "status": "supported",
                                     "type": "zf", "url": "https://new.example.edu"]
        XCTAssertThrowsError(try store.handle(command, consumerWired: false, base: { [school] }))
        XCTAssertFalse(store.contains("fixture"))
        _ = try store.handle(command, consumerWired: true, base: { [school] })
        let changed = try XCTUnwrap(store.apply(to: [school]).first)
        XCTAssertEqual(changed.url, "https://new.example.edu")
        XCTAssertEqual(changed.type, "zf")
        XCTAssertEqual(changed.status, "supported")
        XCTAssertEqual(changed.catalogId, school.catalogId)
        XCTAssertFalse(changed.enableFetch)
        let loaded = ConsoleCatalogStore(file: file)
        XCTAssertEqual(loaded.apply(to: [school]).first?.url, school.url, "not enabled until console starts")
        loaded.setActive(true)
        XCTAssertEqual(loaded.apply(to: [school]).first?.url, changed.url)
        // 上游新 patch 替换上一条 Override；未写的字段回 base，不保留旧 patch。
        _ = try loaded.handle(["op": "set", "name": "fixture", "status": "pending"], consumerWired: true, base: { [school] })
        XCTAssertEqual(loaded.apply(to: [school]).first?.url, school.url)
        try loaded.clear()
        XCTAssertFalse(loaded.contains("fixture"))
    }

    func testCatalogPersistenceFailureLeavesMemoryUntouched() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        // 把父目录占为文件，确定性触发 persist 失败。
        let blocker = directory.appendingPathComponent("file-not-directory")
        try Data([0]).write(to: blocker)
        let store = ConsoleCatalogStore(file: blocker.appendingPathComponent("overrides.json"))
        store.setActive(true)
        XCTAssertThrowsError(try store.put(name: "fixture", patch: ["status": "supported"]))
        XCTAssertFalse(store.contains("fixture"))
    }

    func testMockReturnsHTTPStatusHeadersAndBytesInRegistrationOrder() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConsoleJWMockStore(directory: directory)
        store.setActive(true)
        let pattern = #"example\.edu/detail"#
        _ = try store.put(["url_pattern": pattern, "respond_with": "b64", "body": Data("课程详情".utf8).base64EncodedString(),
                           "status": 202, "content_type": "text/html; charset=utf-8", "headers": ["X-Fixture": "first"]])
        _ = try store.put(["url_pattern": pattern, "body": "second"])
        let request = URLRequest(url: URL(string: "https://example.edu/detail?id=1")!)
        let result = try XCTUnwrap(store.response(for: request))
        XCTAssertEqual(String(data: result.0, encoding: .utf8), "课程详情")
        let response = try XCTUnwrap(result.1 as? HTTPURLResponse)
        XCTAssertEqual(response.statusCode, 202)
        XCTAssertEqual(response.value(forHTTPHeaderField: "X-Fixture"), "first")
        XCTAssertNil(store.response(for: URLRequest(url: URL(string: "https://other.edu/detail")!)))
        store.setActive(false)
        XCTAssertNil(store.response(for: request))
        let reloaded = ConsoleJWMockStore(directory: directory)
        reloaded.setActive(true)
        XCTAssertEqual(reloaded.response(for: request)?.0, result.0)
        _ = try reloaded.delete(["url_pattern": pattern])
        XCTAssertTrue(reloaded.list().isEmpty, "all same-pattern entries removed")
        XCTAssertThrowsError(try reloaded.delete(["url_pattern": pattern]))
    }

    func testMockBadRegexFileTraversalAndInvalidBase64DoNotMutateRules() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConsoleJWMockStore(directory: directory)
        store.setActive(true)
        XCTAssertThrowsError(try store.put(["url_pattern": "[", "body": "bad"]))
        XCTAssertThrowsError(try store.put(["url_pattern": ".*", "respond_with": "b64", "body": "!"]))
        for path in ["../escape", "a/../../escape", "/absolute", "C:\\escape", "\\root"] {
            XCTAssertNil(ConsoleJWMockStore.bodyFile(path, directory: directory))
        }
        let outside = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("link"), withDestinationURL: outside)
        XCTAssertNil(ConsoleJWMockStore.bodyFile("link/escape.html", directory: directory))
        XCTAssertTrue(store.list().isEmpty)
        try Data("<html>fixture</html>".utf8).write(to: directory.appendingPathComponent("fixture.html"))
        _ = try store.put(["url_pattern": ".*", "respond_with": "file", "body": "fixture.html"])
        XCTAssertEqual(store.list().first?.body, Data("<html>fixture</html>".utf8))
    }

    @MainActor
    func testLogRingsAreBoundedOrderedAndDoNotExposeRequestSecrets() throws {
        let store = ConsoleLogStore(capacity: 2)
        store.record(.started); store.record(.clockChanged); store.record(.stopped)
        let secret = "secret-token-and-passphrase"
        let request = ConsoleRequest(method: "POST", path: "/unknown/\(secret)", headers: ["x-sleepy-token": secret],
                                     body: Data(secret.utf8), query: ["token": secret])
        store.recordRequest(request, status: 401, knownPaths: ["/v1/hello"])
        let result = store.snapshot(limit: 1)
        let app = try XCTUnwrap(result["app"] as? [[String: Any]])
        XCTAssertEqual(app.count, 1)
        XCTAssertEqual(app.first?["message"] as? String, "listener stopped")
        let audit = try XCTUnwrap(result["audit"] as? [[String: Any]])
        XCTAssertEqual(audit.first?["path"] as? String, "[unknown]")
        XCTAssertEqual(audit.first?["code"] as? Int, 401)
        let encoded = try JSONSerialization.data(withJSONObject: result)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains(secret))
        XCTAssertEqual((store.snapshot()["app"] as? [[String: Any]])?.count, 2)
    }

    @MainActor
    func testTriggerAliasesAwaitSchedulerAndUnsupportedTypesHaveNoSideEffects() async throws {
        let repo = ScheduleRepository(try AppDatabase.inMemory())
        let data = ConsoleDataHandlers(repository: repo)
        var calls = 0
        let trigger = ConsoleTriggerHandlers(repository: repo, data: data, reschedule: {
            await Task.yield()
            calls += 1
        })
        for type in ["notification", "before_class_alarm", "schedule_before_class_now"] {
            let result = try await trigger.handle(["type": type]) as? [String: Any]
            XCTAssertEqual(result?["type"] as? String, type)
        }
        XCTAssertEqual(calls, 3)
        for type in ConsoleTriggerHandlers.unsupported {
            do { _ = try await trigger.handle(["type": type]); XCTFail("unsupported must not succeed") }
            catch let error as ConsoleFailure { XCTAssertEqual(error.code, 501) }
        }
        XCTAssertEqual(calls, 3)
        XCTAssertTrue(try repo.getAllTables().isEmpty)
    }

    @MainActor
    func testSoonestCourseUsesVirtualClockAndCleanupUsesUpstreamPredicates() async throws {
        defer { AppClock.reset() }
        let virtual = try XCTUnwrap(DateUtils.isoCalendar.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 12)))
        _ = try AppClock.apply(["mode": "absolute", "epochMs": Int(virtual.timeIntervalSince1970 * 1000)])
        let repo = ScheduleRepository(try AppDatabase.inMemory())
        let user = try repo.insertTable(TimeTableEntity(name: "我的课程", startDate: "2026-09-07"))
        let data = ConsoleDataHandlers(repository: repo)
        let trigger = ConsoleTriggerHandlers(repository: repo, data: data, reschedule: {})
        _ = try await trigger.handle(["type": "add_soonest_course", "delayMin": 5, "courseName": "fixture"])
        let table = try XCTUnwrap(repo.getDefaultTable())
        XCTAssertNotEqual(table.id, user)
        let course = try XCTUnwrap(repo.getCourses(table.id).first)
        XCTAssertTrue(course.ownTime)
        XCTAssertEqual(course.startTime, "12:05")
        XCTAssertEqual(course.endTime, "12:50")
        XCTAssertEqual(course.day, 1)
        _ = try await trigger.handle(["type": "sync"])
        XCTAssertNil(try repo.getTable(table.id))
        XCTAssertEqual(try repo.getDefaultTable()?.id, user)
    }

    func testHTTPParsesDeleteAndLogQuery() throws {
        var parser = ConsoleHTTPParser()
        let body = "{\"all\":true}"
        let request = try XCTUnwrap(parser.append(Data("DELETE /v1/jw/mock HTTP/1.1\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)".utf8)))
        XCTAssertEqual(request.method, "DELETE")
        var logParser = ConsoleHTTPParser()
        let log = try XCTUnwrap(logParser.append(Data("GET /v1/log?limit=2 HTTP/1.1\r\n\r\n".utf8)))
        XCTAssertEqual(log.path, "/v1/log")
        XCTAssertEqual(log.query["limit"], "2")
    }

    @MainActor
    func testAsyncTriggerRouteCannotBypassAuthOrRevocation() async throws {
        let router = ConsoleRouter()
        router.active = true
        var calls = 0
        router.registerAsync("POST", "/v1/trigger") { _ in calls += 1; return ["executed": true] }
        let token = try router.tokens.issue()
        let unauthenticated = ConsoleRequest(method: "POST", path: "/v1/trigger", headers: [:], body: Data())
        let denied = await router.dispatchAsync(unauthenticated)
        XCTAssertEqual(denied.status, 401)
        XCTAssertEqual(calls, 0)
        let authenticated = ConsoleRequest(method: "POST", path: "/v1/trigger", headers: ["x-sleepy-token": token], body: Data())
        let accepted = await router.dispatchAsync(authenticated)
        XCTAssertEqual(accepted.status, 200)
        XCTAssertEqual(calls, 1)
        router.stop()
        let revoked = await router.dispatchAsync(authenticated)
        XCTAssertEqual(revoked.status, 401)
        XCTAssertEqual(calls, 1)
    }
}
#endif
