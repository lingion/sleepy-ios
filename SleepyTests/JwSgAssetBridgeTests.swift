import XCTest
import JavaScriptCore
@testable import Sleepy

final class JwSgAssetBridgeTests: XCTestCase {
    private func runtime() throws -> JSContext {
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript(#"""
        var window = this;
        var messages = [];
        var timers = [];
        var webkit = {messageHandlers:{__sleepyBridge:{postMessage:function(value){messages.push(JSON.parse(value.json));}}}};
        function setTimeout(fn, delay){timers.push({fn:fn, delay:delay, active:true}); return timers.length-1;}
        function clearTimeout(id){if(timers[id]) timers[id].active=false;}
        """#)
        return context
    }

    private func messages(_ context: JSContext) throws -> [[String: Any]] {
        let json = try XCTUnwrap(context.evaluateScript("JSON.stringify(messages)")?.toString())
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])
    }

    func testBridgeTransportsCoursesPeriodsAndSemesterWithoutDecodingCourses() throws {
        let context = try runtime()
        context.evaluateScript(JwSgAssetBridge.assemble(vendorJs: #"""
        shiguangBridgePromise.saveImportedCourses('[{"name":"数学","day":2,"startSection":1,"endSection":2,"weeks":[1,3]}]');
        shiguangBridgePromise.savePresetTimeSlots('[{"number":1,"startTime":"08:00","endTime":"08:45"}]');
        shiguangBridgePromise.saveCourseConfig('{"semesterStartDate":"2026-09-07"}');
        shiguangBridge.notifyTaskCompletion();
        """#))
        XCTAssertNil(context.exception)
        let output = try messages(context)
        XCTAssertEqual(output.count, 1)
        XCTAssertEqual(output.first?["ok"] as? Bool, true)
        XCTAssertEqual(output.first?["startDate"] as? String, "2026-09-07")
        let periods = try XCTUnwrap(output.first?["periods"] as? [[String: Any]])
        XCTAssertEqual(periods.first?["start"] as? String, "08:00")
        XCTAssertEqual(periods.first?["node"] as? Int, 1)
        let payload = try XCTUnwrap(output.first?["data"] as? String)
        let courses = try JwSgAssetParser(payload).generateCourseList()
        XCTAssertEqual(courses.first?.name, "数学")
        XCTAssertEqual(courses.first?.type, 1)
    }

    func testCompletionWithoutSubmissionAndVendorExceptionFailExplicitly() throws {
        for script in ["shiguangBridge.notifyTaskCompletion();", "throw new Error('vendor failed');",
                       "AndroidBridgePromise.saveComboSchedule('{}'); shiguangBridge.notifyTaskCompletion();"] {
            let context = try runtime()
            context.evaluateScript(JwSgAssetBridge.assemble(vendorJs: script))
            XCTAssertNil(context.exception)
            let output = try messages(context)
            XCTAssertEqual(output.count, 1)
            XCTAssertEqual(output.first?["ok"] as? Bool, false)
            XCTAssertFalse((output.first?["err"] as? String ?? "").isEmpty)
        }
    }

    func testRepeatedAttemptRequiresReloadAndLateCompletionCannotChangeSession() throws {
        let context = try runtime()
        context.evaluateScript(JwSgAssetBridge.assemble(vendorJs: "", sessionId: "first"))
        context.evaluateScript("SleepySgShim.cancelSession('first');")
        context.evaluateScript("shiguangBridge.notifyTaskCompletion();")
        XCTAssertTrue(try messages(context).isEmpty)
        context.evaluateScript(JwSgAssetBridge.assemble(vendorJs: "", sessionId: "second"))
        XCTAssertNotNil(context.exception)
    }

    func testManifestPreservesEveryAdapterAndRequiresAnExplicitChoice() throws {
        let manifest = Data(#"{"schools":[{"sgName":"测试大学（校区）","adapters":[{"adapterId":"first","jsPath":"third_party/shiguang/js/A/first.js","importUrl":"https://jw.example.edu"},{"adapterId":"second","jsPath":"third_party/shiguang/js/A/second.js","importUrl":"https://jw.example.edu/2"}]}]}"#.utf8)
        let entries = try JwSgAssetBridge.entries(schoolName: " 测试大学(校区) ", manifest: manifest)
        XCTAssertEqual(entries.count, 2)
        XCTAssertNil(JwSgAssetBridge.restoreChoice(entries, savedId: ""))
        XCTAssertNil(JwSgAssetBridge.restoreChoice(entries, savedId: "obsolete"))
        XCTAssertEqual(try JwSgAssetBridge.entry(schoolName: "测试大学(校区)", manifest: manifest, selectedAdapterId: "second").importUrl, "https://jw.example.edu/2")
        XCTAssertThrowsError(try JwSgAssetBridge.entry(schoolName: "测试大学(校区)", manifest: manifest))
        XCTAssertThrowsError(try JwSgAssetBridge.entry(schoolName: "测试大学", manifest: manifest))
    }

    func testAllNineVendorBridgeMethodsAndAndroidAliasesAreInstalled() throws {
        let context = try runtime()
        context.evaluateScript(JwSgAssetBridge.assemble(vendorJs: ""))
        for name in ["showAlert", "showPrompt", "showSingleSelection", "saveImportedCourses",
                     "savePresetTimeSlots", "saveCourseConfig", "saveComboSchedule"] {
            XCTAssertEqual(context.evaluateScript("typeof shiguangBridgePromise.\(name)")?.toString(), "function", name)
        }
        for name in ["showToast", "notifyTaskCompletion"] {
            XCTAssertEqual(context.evaluateScript("typeof shiguangBridge.\(name)")?.toString(), "function", name)
        }
        XCTAssertEqual(context.evaluateScript("AndroidBridge === shiguangBridge && AndroidBridgePromise === shiguangBridgePromise")?.toBool(), true)
        XCTAssertThrowsError(try JwSgAssetBridge.bridgeJs(schoolName: "缺失", resourceRoot: nil))
    }
}
