import XCTest
@testable import Sleepy

final class JwHomeDispatchRegressionTests: XCTestCase {
    private func fixture() throws -> String {
        let bundle = Bundle(for: JwHomeDispatchRegressionTests.self)
        let url = try XCTUnwrap(bundle.url(forResource: "kingo_zx_sample", withExtension: "html")
            ?? bundle.url(forResource: "kingo_zx_sample", withExtension: "html", subdirectory: "resources"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testHomeRegistrationDoesNotPretendToParseCourses() throws {
        XCTAssertTrue(JwParserRegistry.supports("jw_home"))
        let parser = try JwParserRegistry.parserFor("jw_home", fixture())
        XCTAssertTrue(try parser.generateCourseList().isEmpty)
        XCTAssertEqual(parser.protocolConfidence, 0)
        XCTAssertTrue(parser.protocolMatchedFeatures.isEmpty)
    }

    func testHomeDispatchRunsRealAutomaticDetection() throws {
        let html = try fixture()
        let home = JwParseDispatch.parse(html, "jw_home")
        let automatic = JwParseDispatch.parse(html, "")
        XCTAssertNil(home.error)
        XCTAssertEqual(home.courses.count, 2)
        XCTAssertEqual(home.courses.map(\.name), ["线性代数", "线性代数"])
        XCTAssertEqual(home.courses.map(\.day), [1, 3])
        XCTAssertEqual(home.attempts, automatic.attempts)
        XCTAssertFalse(home.attempts.contains { $0.type == "jw_home" })
        XCTAssertFalse(JwParserRegistry.TYPE_PRIORITY.contains { $0.0 == "jw_home" })
    }

    func testLoginPageProducesNoCoursesAndDoesNotUseSentinelCandidate() {
        let outcome = JwParseDispatch.parse("<html><form><input type='password'></form></html>", "jw_home")
        XCTAssertTrue(outcome.courses.isEmpty)
        XCTAssertNil(outcome.error)
        XCTAssertFalse(outcome.attempts.contains { $0.type == "jw_home" })
    }

    func testExplicitProtocolStillUsesExactDispatch() throws {
        let outcome = JwParseDispatch.parse(try fixture(), JwProtocol.TYPE_KINGO_ZX)
        XCTAssertNil(outcome.error)
        XCTAssertEqual(outcome.courses.count, 2)
        XCTAssertEqual(outcome.attempts.count, 1)
        XCTAssertEqual(outcome.attempts.first?.type, JwProtocol.TYPE_KINGO_ZX)
        XCTAssertNotNil(JwParseDispatch.parse("<html></html>", "unknown-protocol").error)
    }
}
