// Synthetic fixtures mirror Android v1.0.64 parseUmooc / parseYl source shapes.
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

    func testUmoocCellIdentityMapsToWeekday() throws {
        // UMOOC uses the first component of each course cell id as its weekday.
        let html = try load("umooc_sample")
        let courses = try JwUmoocParser(html).generateCourseList()

        let math = try XCTUnwrap(courses.first { $0.name == "高等数学" })
        let physics = try XCTUnwrap(courses.first { $0.name == "大学物理" })
        let ds = try XCTUnwrap(courses.first { $0.name == "数据结构" })
        let eng = try XCTUnwrap(courses.first { $0.name == "英语" })

        XCTAssertEqual(1, math.day)
        XCTAssertEqual(2, physics.day)
        XCTAssertEqual(3, ds.day)
        XCTAssertEqual(5, eng.day)
    }

    func testUmoocSectionHeaderMapsToStartNode() throws {
        let html = try load("umooc_sample")
        let courses = try JwUmoocParser(html).generateCourseList()

        let math = try XCTUnwrap(courses.first { $0.name == "高等数学" })
        let pe = try XCTUnwrap(courses.first { $0.name == "体育" })
        XCTAssertEqual(1, math.startNode)  // 第1节 header
        XCTAssertEqual(1, math.endNode)
        XCTAssertEqual(2, pe.startNode)     // 第2节 header
        XCTAssertEqual(2, pe.endNode)
    }

    func testUmoocParityMarkersMapToSingleAndDoubleWeek() throws {
        // v1.0.64 expands the week set before merging adjacent or alternating weeks.
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
        // 容器缺失时, 走 WakeUpMarkerParser 的通用形态(与 原版本 的
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
        XCTAssertEqual(1, math.day)
        XCTAssertEqual(1, math.startNode)
    }

    func testYlUsesTbodyRowsOnly() throws {
        // fixture 的 tbody 有 2 行; 表头(thead)不在 tbody 内 ⇒ 不参与行号。
        let html = try load("yl_sample")
        let courses = try JwYlParser(html).generateCourseList()
        let pe = try XCTUnwrap(courses.first { $0.name == "体育" }, "体育 应存在")
        XCTAssertEqual(2, pe.startNode)
        XCTAssertEqual(3, pe.day)       // period gutter is excluded from the weekday index
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
        // YL has no #timetable container.
        XCTAssertEqual(0, try JwUmoocParser(yl).generateCourseList().count)
    }
}
