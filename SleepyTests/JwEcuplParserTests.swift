// JwEcuplParserTests.swift — ← 原版本 v1.0.62 JwEcuplParserTest.kt (逐用例移植)
//
// 华东政法大学 (ECUPL) 主表解析器契约锁。
// 覆盖 10 个 regex_invariants: R1/R3/R4/R9/R10 主表 + R2/R5/R6/R7/R8 INDIRECT。
//
// fixture: SleepyTests/resources/ecupl_sample.html / ecupl_metadata_only.html
//          / ecupl_super_sample.html
//   (与 原版本 app/src/test/resources/jw/ 同名文件逐字节一致, md5 已校验)

import XCTest
@testable import Sleepy

final class JwEcuplParserTests: XCTestCase {

    // MARK: - 载入工具

    /// ← 原 `javaClass.classLoader.getResourceAsStream("jw/$name")`
    private func res(_ name: String) throws -> String {
        let bundle = Bundle(for: JwEcuplParserTests.self)
        guard let url = bundle.url(forResource: name, withExtension: "html")
                ?? bundle.url(forResource: name, withExtension: "html", subdirectory: "resources") else {
            XCTFail("测试资源 \(name).html 应存在")
            throw NSError(domain: "test", code: 1)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func mainSample() throws -> String { try res("ecupl_sample") }
    private func metadataOnly() throws -> String { try res("ecupl_metadata_only") }
    private func superSample() throws -> String { try res("ecupl_super_sample") }

    // ← 原 JwEcuplParserTest.kt: metadataFixturesNeverInventScheduleCoordinates
    // Metadata tables have course titles and week notes, but no actual weekday/period.
    func testMetadataFixturesNeverInventScheduleCoordinates() throws {
        XCTAssertTrue(try JwEcuplParser(metadataOnly()).generateCourseList().isEmpty)
        XCTAssertTrue(try JwEcuplParser(superSample()).generateCourseList().isEmpty)
    }

    // ← 原 JwEcuplParserTest.kt: taskActivityIndexProducesObservedSchedule
    func testTaskActivityIndexProducesObservedSchedule() throws {
        let courses = try JwEcuplParser(mainSample()).generateCourseList()
        XCTAssertFalse(courses.isEmpty)
        XCTAssertEqual("民法(总则)(001)", courses.first?.name)
        XCTAssertEqual(1, courses.first?.day)
        XCTAssertEqual(1, courses.first?.startNode)
    }

    // ---- D. confidence + matchedFeatures ----

    // ← 原 JwEcuplParserTest.kt: `mainSample yields high confidence with 5+ features`
    func testMainSampleYieldsHighConfidenceWith5PlusFeatures() throws {
        let parser = JwEcuplParser(try mainSample())
        let conf = parser.protocolConfidence
        XCTAssertTrue(conf >= 80, "conf ≥ 80, 实际 \(conf)")
        let features = parser.protocolMatchedFeatures
        XCTAssertTrue(features.count >= 3, "features ≥ 5(原实断言 ≥3), 实际 \(features.count)")
        XCTAssertTrue(features.contains { $0.hasPrefix("ecupl:") })
    }

    // ---- E. Isolation - empty HTML returns empty ----

    // ← 原 JwEcuplParserTest.kt: `empty HTML yields zero courses and zero confidence`
    func testEmptyHtmlYieldsZeroCoursesAndZeroConfidence() throws {
        let parser = JwEcuplParser("<html><body></body></html>")
        let courses = try parser.generateCourseList()
        XCTAssertEqual(0, courses.count)
        XCTAssertEqual(0, parser.protocolConfidence)
    }

    // ---- F. Non-ECUPL HTML ----

    // ← 原 JwEcuplParserTest.kt: `non-ecupl HTML yields empty course list`
    func testNonEcuplHtmlYieldsEmptyCourseList() throws {
        let html = "<html><body><div>no listTable here</div></body></html>"
        let courses = try JwEcuplParser(html).generateCourseList()
        XCTAssertEqual(0, courses.count)
    }
}
