import XCTest
@testable import Sleepy

final class JwSgAssetParserTests: XCTestCase {
    func testMapsBridgeFieldsAndDeduplicatesWeeks() throws {
        let source = #"[{"name":"  高等数学  ","teacher":" 张老师 ","position":" A101 ","day":7,"startSection":3,"endSection":4,"weeks":[3,1,2,2]}]"#
        let courses = try JwParserRegistry.parserFor("sg_asset", source).generateCourseList()
        XCTAssertEqual(courses.count, 1)
        let course = try XCTUnwrap(courses.first)
        XCTAssertEqual(course.name, "高等数学")
        XCTAssertEqual(course.teacher, "张老师")
        XCTAssertEqual(course.room, "A101")
        XCTAssertEqual([course.day, course.startNode, course.endNode, course.startWeek, course.endWeek, course.type], [7, 3, 4, 1, 3, 0])
    }

    func testSparseParityWeeksNeverInventMissingOccurrences() throws {
        let source = #"[{"name":"稀疏课程","day":1,"startSection":1,"endSection":2,"weeks":[1,5,7,10,12]}]"#
        let courses = try JwSgAssetParser(source).generateCourseList()
        let expanded = courses.flatMap { course in
            (course.startWeek...course.endWeek).filter {
                course.type == 0 || (course.type == 1 && $0 % 2 == 1) || (course.type == 2 && $0 % 2 == 0)
            }
        }
        XCTAssertEqual(expanded, [1,5,7,10,12])
        let odd = try JwSgAssetParser(#"[{"name":"单周","day":2,"startSection":1,"endSection":1,"weeks":[1,3,5]}]"#).generateCourseList()
        XCTAssertEqual(odd.first?.type, 1)
        XCTAssertEqual(odd.first?.endWeek, 5)
    }

    func testRejectsCustomTimesInvalidRangesAndMalformedRows() throws {
        let source = #"[{"name":"自定义","isCustomTime":true,"day":1,"startSection":1,"endSection":2,"weeks":[1]},{"name":"倒序","day":1,"startSection":3,"endSection":2,"weeks":[1]},{"name":"周零","day":0,"startSection":1,"endSection":2,"weeks":[1]},{"name":"空周","day":1,"startSection":1,"endSection":2,"weeks":[0,-1]},{"name":"小数","day":1.5,"startSection":1,"endSection":2,"weeks":[1]},null,{},"bad"]"#
        XCTAssertTrue(try JwSgAssetParser(source).generateCourseList().isEmpty)
        for invalid in ["<html>login</html>", "{}", "[]"] {
            let parser = JwSgAssetParser(invalid)
            XCTAssertTrue(try parser.generateCourseList().isEmpty)
            XCTAssertEqual(parser.protocolConfidence, 0)
        }
    }

    func testDoesNotClaimOtherJsonProtocols() {
        let parser = JwSgAssetParser(#"[{"day":1,"weeks":[1],"kcm":"课程","skzc":"01"}]"#)
        XCTAssertEqual(parser.protocolConfidence, 0)
        XCTAssertTrue(parser.protocolMatchedFeatures.isEmpty)
    }
}
