// JwEcuplScriptParserTests.swift — ← Android v1.0.64 JwEcuplScriptParserTest.kt
//
// ECUPL script 子协议 (R5/R6/R7) 解析器测试。
// 覆盖 3 个 regex_invariants + isolation tests。
//
// fixture: SleepyTests/resources/ecupl_script_sample.html / ecupl_super_sample.html
//   (与 原版本 app/src/test/resources/jw/ 同名文件逐字节一致, md5 已校验)

import XCTest
@testable import Sleepy

final class JwEcuplScriptParserTests: XCTestCase {

    // MARK: - 载入工具

    /// ← 原 `javaClass.classLoader.getResourceAsStream("jw/$name")`
    private func res(_ name: String) throws -> String {
        let bundle = Bundle(for: JwEcuplScriptParserTests.self)
        guard let url = bundle.url(forResource: name, withExtension: "html")
                ?? bundle.url(forResource: name, withExtension: "html", subdirectory: "resources") else {
            XCTFail("测试资源 \(name).html 应存在")
            throw NSError(domain: "test", code: 1)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func scriptSample() throws -> String { try res("ecupl_script_sample") }
    private func superSample() throws -> String { try res("ecupl_super_sample") }

    /// ← Kotlin `Regex.findAll(source)`
    private func allMatches(_ re: NSRegularExpression, _ s: String) -> [NSTextCheckingResult] {
        re.matches(in: s, range: NSRange(location: 0, length: s.utf16.count))
    }

    /// ← Kotlin `MatchResult.groupValues[i]`
    private func group(_ s: String, _ m: NSTextCheckingResult, _ i: Int) -> String {
        let r = m.range(at: i)
        guard r.location != NSNotFound, let sw = Range(r, in: s) else { return "" }
        return String(s[sw])
    }

    // MARK: - A. R5: CourseTable 锚点

    // ← 原 JwEcuplScriptParserTest.kt: `R5 new CourseTable matches across newlines`
    func testR5NewCourseTableMatchesAcrossNewlines() throws {
        let src = try scriptSample()
        let match = JwEcuplScriptParser.reCourseTable
            .firstMatch(in: src, range: NSRange(location: 0, length: src.utf16.count))
        XCTAssertNotNil(match)
        // 起始日: 2024-02-26
        if let match { XCTAssertEqual("2024-02-26", group(src, match, 1)) }
    }

    // MARK: - B. R6: 时间矩阵 ≥ 1 对

    // ← 原 JwEcuplScriptParserTest.kt: `R6 time pair regex finds at least 12 pairs`
    func testR6TimePairRegexFindsAtLeast12Pairs() throws {
        let src = try scriptSample()
        let pairs = allMatches(JwEcuplScriptParser.reTimePair, src)
        XCTAssertTrue(pairs.count >= 12, "≥ 12 时间对, 实际 \(pairs.count)")
        XCTAssertEqual("800", group(src, pairs[0], 1))
        XCTAssertEqual("845", group(src, pairs[0], 2))
    }

    // MARK: - C. R7: newActivity + addActivityByTime 配对 emit 课程

    // ← 原 JwEcuplScriptParserTest.kt: `R7 newActivity yields 4 observed slots via script path`
    func testR7NewActivityYields4ObservedSlotsViaScriptPath() throws {
        let courses = try JwEcuplScriptParser(scriptSample()).generateCourseList()
        XCTAssertEqual(4, courses.count)
        // 第 1 课程: 民法(总则), 张教授
        let civilLaw = courses[0]
        XCTAssertEqual("民法(总则)", civilLaw.name)
        XCTAssertEqual("张教授", civilLaw.teacher)
        XCTAssertEqual("明法楼A101", civilLaw.room)
        XCTAssertEqual(1, civilLaw.day)
        XCTAssertEqual(1, civilLaw.startNode)
        XCTAssertEqual(2, civilLaw.endNode)
        XCTAssertEqual(1, civilLaw.startWeek)
        XCTAssertEqual(16, civilLaw.endWeek)
        XCTAssertTrue(courses.contains {
            $0.name == "民法(总则)" && $0.day == 4 && $0.startNode == 3 && $0.endNode == 4
        })
    }

    // MARK: - D. End-to-end: super fixture 同时含 HTML + script, script 路径仍 emit 课程

    // ← 原 JwEcuplScriptParserTest.kt: `super fixture yields 3 courses via R7 path`
    func testSuperFixtureYields3CoursesViaR7Path() throws {
        let courses = try JwEcuplScriptParser(superSample()).generateCourseList()
        XCTAssertEqual(3, courses.count)
        let names = Set(courses.map { $0.name })
        XCTAssertTrue(names.contains("民法(总则)"))
        XCTAssertTrue(names.contains("刑法"))
        XCTAssertTrue(names.contains("法理学"))
    }

    // ← 原 JwEcuplScriptParserTest.kt: `unmatched minutes and overflowing bitmap emit no invented courses`
    func testUnmatchedMinutesAndOverflowingBitmapEmitNoInventedCourses() throws {
        let base = try scriptSample()
        let unmatched = base.replacingOccurrences(of: "activity,1,800,940", with: "activity,1,801,940")
        XCTAssertEqual(3, try JwEcuplScriptParser(unmatched).generateCourseList().count)
        let overflow = base.replacingOccurrences(of: "131070", with: "18446744073709551616")
        XCTAssertEqual(0, try JwEcuplScriptParser(overflow).generateCourseList().count)
    }

    // ← 原 JwEcuplScriptParserTest.kt: `sparse decimal bitmap retains gaps and date offset`
    func testSparseDecimalBitmapRetainsGapsAndDateOffset() throws {
        let html = try scriptSample().replacingOccurrences(of: "\"2024-02-26\",131070", with: "\"2024-03-04\",42")
        let courses = try JwEcuplScriptParser(html).generateCourseList()
            .filter { $0.name == "民法(总则)" && $0.day == 1 }
        // ← Kotlin `(startWeek..endWeek step (type==0 ? 1 : 2))` flatMap
        var weeks: [Int] = []
        for c in courses {
            let step = c.type == 0 ? 1 : 2
            var w = c.startWeek
            while w <= c.endWeek { weeks.append(w); w += step }
        }
        XCTAssertEqual([2, 4, 6], weeks)
    }

    // ← 原 JwEcuplScriptParserTest.kt: `separate scripts do not cross pair slots`
    func testSeparateScriptsDoNotCrossPairSlots() throws {
        let unrelated = "<script language=\"JavaScript\">newActivity(\"bad\",\"bad\",\"x\",\"bad\",\"x\",\"bad\",\"2024-02-26\",65535);addActivityByTime(activity,7,480,525);</script>"
        let courses = try JwEcuplScriptParser(unrelated + scriptSample()).generateCourseList()
        XCTAssertEqual(4, courses.count)
    }

    // ← 原 JwEcuplScriptParserTest.kt: `classic routing uses script matrix for spaced activity with empty room`
    func testClassicRoutingUsesScriptMatrixForSpacedActivityWithEmptyRoom() throws {
        let html = try scriptSample()
            .replacingOccurrences(of: "\"明法楼A101\"", with: "\"\"")
            .replacingOccurrences(of: "newActivity(\"C001\"", with: "newActivity(  \"C001\"")
        let courses = try JwImportViewModel.parseHtmlStatic(html, JwProtocol.TYPE_CLASSIC_EAMS).courses
        XCTAssertEqual(4, courses.count)
        XCTAssertTrue(courses.contains {
            $0.name == "民法(总则)" && $0.room.isEmpty && $0.day == 4 && $0.startNode == 3
        })
    }

    // MARK: - E. confidence

    // ← 原 JwEcuplScriptParserTest.kt: `scriptSample yields high confidence`
    func testScriptSampleYieldsHighConfidence() throws {
        let parser = JwEcuplScriptParser(try scriptSample())
        let conf = parser.protocolConfidence
        XCTAssertTrue(conf >= 80, "conf ≥ 80, 实际 \(conf)")
    }

    // MARK: - F. Isolation - empty HTML

    // ← 原 JwEcuplScriptParserTest.kt: `empty HTML yields zero courses and zero confidence`
    func testEmptyHtmlYieldsZeroCoursesAndZeroConfidence() throws {
        let parser = JwEcuplScriptParser("<html><body></body></html>")
        let courses = try parser.generateCourseList()
        XCTAssertEqual(0, courses.count)
        XCTAssertEqual(0, parser.protocolConfidence)
    }

    // MARK: - G. Non-ECUPL script

    // ← 原 JwEcuplScriptParserTest.kt: `non-ecupl script yields empty list`
    func testNonEcuplScriptYieldsEmptyList() throws {
        let html = "<html><body><script>alert('hello');</script></body></html>"
        let courses = try JwEcuplScriptParser(html).generateCourseList()
        XCTAssertEqual(0, courses.count)
        XCTAssertEqual(0, JwEcuplScriptParser(html).protocolConfidence)
    }
}
