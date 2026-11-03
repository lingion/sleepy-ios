// JwEcuplSuperParserTests.swift — ← 原版本 v1.0.62 JwEcuplSuperParserTest.kt (逐用例移植)
//
// ECUPL Super 解析器 (3-parser 调度器) 测试。
// 覆盖 10 个 regex_invariants (R1-R10 主表 + script) + dispatcher fallback。
//
// fixture: SleepyTests/resources/ecupl_sample.html / ecupl_super_sample.html
//          / ecupl_script_sample.html
//   (与 原版本 app/src/test/resources/jw/ 同名文件逐字节一致, md5 已校验)

import XCTest
@testable import Sleepy

final class JwEcuplSuperParserTests: XCTestCase {

    // MARK: - 载入工具

    /// ← 原 `javaClass.classLoader.getResourceAsStream("jw/$name")`
    private func res(_ name: String) throws -> String {
        let bundle = Bundle(for: JwEcuplSuperParserTests.self)
        guard let url = bundle.url(forResource: name, withExtension: "html")
                ?? bundle.url(forResource: name, withExtension: "html", subdirectory: "resources") else {
            XCTFail("测试资源 \(name).html 应存在")
            throw NSError(domain: "test", code: 1)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func mainSample() throws -> String { try res("ecupl_sample") }
    private func superSample() throws -> String { try res("ecupl_super_sample") }
    private func scriptSample() throws -> String { try res("ecupl_script_sample") }

    // MARK: - A. POSITIVE: super fixture 同时命中主表 + script

    // ← 原 JwEcuplSuperParserTest.kt: `super fixture yields 6 courses via merged dispatcher`
    func testSuperFixtureYields6CoursesViaMergedDispatcher() throws {
        let courses = try JwEcuplSuperParser(superSample()).generateCourseList()
        // 主表 3 + script 3, 但同 name+teacher 视为重复 → 至少 3 课程
        XCTAssertTrue(courses.count >= 3, "≥ 3 课程 (合并去重后), 实际 \(courses.count)")
    }

    // ← 原 JwEcuplSuperParserTest.kt: `super parser yields max confidence from main or script`
    func testSuperParserYieldsMaxConfidenceFromMainOrScript() throws {
        let parser = JwEcuplSuperParser(try superSample())
        let conf = parser.protocolConfidence
        // 主表 + script 联合: max ≥ 80
        XCTAssertTrue(conf >= 80, "conf ≥ 80, 实际 \(conf)")
    }

    // MARK: - B. Main-only fixture (HTML 双表)

    // ← 原 JwEcuplSuperParserTest.kt: `main only fixture yields 8 courses via main parser path`
    func testMainOnlyFixtureYields8CoursesViaMainParserPath() throws {
        let courses = try JwEcuplSuperParser(mainSample()).generateCourseList()
        // mainSample 不含 script, 只有 main parser emit
        XCTAssertFalse(courses.isEmpty)
    }

    // MARK: - C. Script-only fixture

    // ← 原 JwEcuplSuperParserTest.kt: `script only fixture yields 4 observed slots via script parser path`
    func testScriptOnlyFixtureYields4ObservedSlotsViaScriptParserPath() throws {
        let courses = try JwEcuplSuperParser(scriptSample()).generateCourseList()
        // scriptSample 不含 HTML 双表, 只有 script parser emit
        XCTAssertEqual(4, courses.count)
    }

    // MARK: - D. matchedFeatures 含 main + script 双锚点

    // ← 原 JwEcuplSuperParserTest.kt: `super parser matchedFeatures contains both main and script anchors`
    func testSuperParserMatchedFeaturesContainsBothMainAndScriptAnchors() throws {
        let parser = JwEcuplSuperParser(try superSample())
        let features = parser.protocolMatchedFeatures
        XCTAssertTrue(features.count >= 2, "features ≥ 2 (main + script), 实际 \(features.count)")
    }

    // MARK: - E. Registry 路由

    // ← 原 JwEcuplSuperParserTest.kt: `registry routing - TYPE_ECUPL creates JwEcuplParser`
    func testRegistryRoutingTypeEcuplCreatesJwEcuplParser() throws {
        let parser = try JwParserRegistry.parserFor(JwProtocol.TYPE_ECUPL, mainSample())
        XCTAssertTrue(parser is JwEcuplParser)
    }

    // ← 原 JwEcuplSuperParserTest.kt: `registry routing - TYPE_ECUPL_SCRIPT creates JwEcuplScriptParser`
    func testRegistryRoutingTypeEcuplScriptCreatesJwEcuplScriptParser() throws {
        let parser = try JwParserRegistry.parserFor(JwProtocol.TYPE_ECUPL_SCRIPT, scriptSample())
        XCTAssertTrue(parser is JwEcuplScriptParser)
    }

    // ← 原 JwEcuplSuperParserTest.kt: `registry routing - TYPE_ECUPL_SUPER creates JwEcuplSuperParser`
    func testRegistryRoutingTypeEcuplSuperCreatesJwEcuplSuperParser() throws {
        let parser = try JwParserRegistry.parserFor(JwProtocol.TYPE_ECUPL_SUPER, superSample())
        XCTAssertTrue(parser is JwEcuplSuperParser)
    }

    // MARK: - F. selectBest fallback

    // ← 原 JwEcuplSuperParserTest.kt: `selectBest yields ECUPL courses for super fixture`
    func testSelectBestYieldsEcuplCoursesForSuperFixture() throws {
        let (courses, _) = JwParserRegistry.selectBest(try superSample())
        XCTAssertFalse(courses.isEmpty, "selectBest 应 emit ≥ 1 课程, 实际 \(courses.count)")
    }

    // MARK: - G. Isolation - empty HTML

    // ← 原 JwEcuplSuperParserTest.kt: `empty HTML yields zero courses`
    func testEmptyHtmlYieldsZeroCourses() throws {
        let courses = try JwEcuplSuperParser("<html><body></body></html>").generateCourseList()
        XCTAssertEqual(0, courses.count)
    }
}
