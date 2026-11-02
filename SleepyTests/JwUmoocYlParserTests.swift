// JwUmoocYlParserTests.swift — iOS 侧自建的 UMOOC / 奕联(YL) 课表契约锁。
//
// ★ 上游没有 oracle: Android v1.0.62 的 `WakeUpCompat.parseUmooc` / `parseYl`
//   在真实 Jsoup 1.23.2 下是**死代码** —— 它们写 `cell.text().trim().split("\n")`
//   并要求 `lines.size >= 2`, 而 Jsoup 的 `Element.text()` 把 `<br>` 折成空格,
//   `split("\n")` 永远只得到 1 行 ⇒ 永远返回空列表。
//   Android 仓库里既没有 UMOOC/YL 的单测, 也没有对应 fixture。
//   所以本文件的期望值由 iOS 侧依据「该解析器本意」自行定义, 并在
//   `Sleepy/data/jw/JwWakeUpCompatParsers.swift` 里显式记录两处与 Android 的差异。
//
// fixture: SleepyTests/resources/umooc_sample.html, SleepyTests/resources/yl_sample.html

import XCTest
@testable import Sleepy

final class JwUmoocYlParserTests: XCTestCase {

    private func load(_ name: String) throws -> String {
        let bundle = Bundle(for: JwUmoocYlParserTests.self)
        guard let url = bundle.url(forResource: name, withExtension: "html")
                ?? bundle.url(forResource: name, withExtension: "html", subdirectory: "resources") else {
            XCTFail("测试资源 \(name).html 应存在")
            throw NSError(domain: "test", code: 1)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - UMOOC

    func testUmoocParsesTimetableCellsIntoNameTeacherRoomWeeks() throws {
        let html = try load("umooc_sample")
        let courses = try JwUmoocParser(html).generateCourseList()

        let math = try XCTUnwrap(courses.first { $0.name == "高等数学" }, "高等数学 应存在")
        XCTAssertEqual("张三", math.teacher)
        XCTAssertEqual("六教6A201", math.room)
        XCTAssertEqual(1, math.startWeek)
        XCTAssertEqual(16, math.endWeek)
        XCTAssertEqual(0, math.type)
    }

    func testUmoocColumnIndexMapsToWeekday() throws {
        // fixture 第 0 行: [节次, 高等数学, 大学物理, 数据结构, 空, 英语, 空, 空]
        // → 单元格下标 1..7 对应周一..周日, 即 day = cellIndex + 1。
        let html = try load("umooc_sample")
        let courses = try JwUmoocParser(html).generateCourseList()

        let math = try XCTUnwrap(courses.first { $0.name == "高等数学" })
        let physics = try XCTUnwrap(courses.first { $0.name == "大学物理" })
        let ds = try XCTUnwrap(courses.first { $0.name == "数据结构" })
        let eng = try XCTUnwrap(courses.first { $0.name == "英语" })

        XCTAssertEqual(2, math.day)     // cellIndex 1
        XCTAssertEqual(3, physics.day)  // cellIndex 2
        XCTAssertEqual(4, ds.day)       // cellIndex 3
        XCTAssertEqual(6, eng.day)      // cellIndex 5
    }

    func testUmoocRowIndexMapsToStartNode() throws {
        let html = try load("umooc_sample")
        let courses = try JwUmoocParser(html).generateCourseList()

        let math = try XCTUnwrap(courses.first { $0.name == "高等数学" })
        let pe = try XCTUnwrap(courses.first { $0.name == "体育" })
        XCTAssertEqual(1, math.startNode)  // 第 0 行
        XCTAssertEqual(1, math.endNode)
        XCTAssertEqual(2, pe.startNode)     // 第 1 行
        XCTAssertEqual(2, pe.endNode)
    }

    func testUmoocParityMarkersMapToSingleAndDoubleWeek() throws {
        // 与 Android 的差异点 b: iOS 取自然映射 单→1 / 双→2 / 其余→0。
        // Android 写的是 单→1 / 双→0 / 其余→2, 与 JwCourse.type 语义冲突。
        let html = try load("umooc_sample")
        let courses = try JwUmoocParser(html).generateCourseList()

        let ds = try XCTUnwrap(courses.first { $0.name == "数据结构" }, "数据结构 应存在")
        XCTAssertEqual(1, ds.type)
        XCTAssertEqual(3, ds.startWeek)
        XCTAssertEqual(15, ds.endWeek)

        let eng = try XCTUnwrap(courses.first { $0.name == "英语" }, "英语 应存在")
        XCTAssertEqual(2, eng.type)
    }

    func testUmoocFallsBackToMarkerParserWhenTimetableMissing() throws {
        // 容器缺失时, 走 WakeUpMarkerParser 的通用形态(与 Android 的
        // `parsed.ifEmpty { super.generateCourseList() }` 同型)。
        let noTimetable = "<html><body><table><tr><td>高等数学<br>张三<br>1-16周<br>六教6A201</td></tr></table></body></html>"
        let parser = JwUmoocParser(noTimetable)
        XCTAssertEqual(0, parser.matchedFeatureList.count)
        XCTAssertEqual(0, try parser.generateCourseList().count)
    }

    func testUmoocRegisteredInRegistry() {
        XCTAssertTrue(JwParserRegistry.isRoutable(JwProtocol.TYPE_UMOOC),
                      "TYPE_UMOOC must be registered in the factory table")
    }

    // MARK: - 奕联(YL)

    func testYlParsesCourseTimeTableContainer() throws {
        let html = try load("yl_sample")
        let courses = try JwYlParser(html).generateCourseList()

        let math = try XCTUnwrap(courses.first { $0.name == "高等数学" }, "高等数学 应存在")
        XCTAssertEqual("张三", math.teacher)
        XCTAssertEqual("六教6A201", math.room)
        XCTAssertEqual(1, math.startWeek)
        XCTAssertEqual(16, math.endWeek)
        XCTAssertEqual(2, math.day)     // cellIndex 1
        XCTAssertEqual(1, math.startNode)
    }

    func testYlUsesTbodyRowsOnly() throws {
        // fixture 的 tbody 有 2 行; 表头(thead)不在 tbody 内 ⇒ 不参与行号。
        let html = try load("yl_sample")
        let courses = try JwYlParser(html).generateCourseList()
        let pe = try XCTUnwrap(courses.first { $0.name == "体育" }, "体育 应存在")
        XCTAssertEqual(2, pe.startNode)
        XCTAssertEqual(4, pe.day)       // 第 1 行 cellIndex 3
    }

    func testYlRegisteredInRegistry() {
        XCTAssertTrue(JwParserRegistry.isRoutable(JwProtocol.TYPE_YL),
                      "TYPE_YL must be registered in the factory table")
    }

    // MARK: - 跨协议

    func testUmoocAndYlDoNotCollideWithEachOther() throws {
        let umooc = try load("umooc_sample")
        let yl = try load("yl_sample")
        let umoocParser = JwUmoocParser(umooc)
        let ylParser = JwYlParser(yl)
        XCTAssertNotEqual(umoocParser.matchedFeatureList, ylParser.matchedFeatureList)
        // YL 的 fixture 不含 .timetable 容器 ⇒ UMOOC 解析器取不到课。
        XCTAssertEqual(0, try JwUmoocParser(yl).generateCourseList().count)
    }
}
