// JwNewUrpParserTests.swift — ← JwNewUrpParser.kt (v1.0.62)
// 覆盖三处对齐点: weekBitsToRanges stride-2 段行为、optString+trim 语义、
// org.json getJSONObject 异常冒泡 + optJSONArray 字符串强制转换。

import XCTest
@testable import Sleepy

final class JwNewUrpParserTests: XCTestCase {

    private func html(withDateList dateListJson: String) -> String {
        "<script>var kbxx_json = {\"dateList\":\(dateListJson)};</script>"
    }

    private func timePlace(classDay: Int, classWeek: String) -> String {
        "{\"classDay\":\(classDay),\"classSessions\":3,\"continuingSession\":2," +
        "\"classWeek\":\"\(classWeek)\",\"campusName\":\"校区\",\"teachingBuildingName\":\"一教\",\"classroomName\":\"301\"}"
    }

    private func course(name: String, teacher: String, timePlaces: [String]) -> String {
        "{\"courseName\":\"\(name)\",\"attendClassTeacher\":\"\(teacher)\"," +
        "\"timeAndPlaceList\":[\(timePlaces.joined(separator: ","))]}"
    }

    // MARK: - weekBits 归并 (private static,经端到端课程输出验证)

    private func assertWeeksMatchBitmap(_ courses: [JwCourse], bitmap: String,
                                       file: StaticString = #filePath, line: UInt = #line) {
        let expected = bitmap.enumerated().compactMap { $0.element == "1" ? $0.offset + 1 : nil }
        let actual = courses.flatMap { course -> [Int] in
            guard course.startWeek <= course.endWeek else {
                XCTFail("周次范围不得倒置", file: file, line: line)
                return []
            }
            return (course.startWeek...course.endWeek).filter { week in
                course.type == 0 || (course.type == 1 && week % 2 == 1)
                    || (course.type == 2 && week % 2 == 0)
            }
        }.sorted()
        XCTAssertEqual(actual, expected, "展开课程必须完整保留输入周次且不能重复或新增", file: file, line: line)
    }

    func test_twoElementOddStrideRun_preservesBothWeeks() throws {
        // classWeek "10100000000000000000" → bits [1,3]
        // 867b814 与当前 Android: 两元素 stride-2 段必须保留末周。
        let bitmap = "10100000000000000000"
        let src = html(withDateList: "[{\"selectCourseList\":[" +
            course(name: "体育", teacher: "张老师",
                   timePlaces: [timePlace(classDay: 1, classWeek: bitmap)]) + "]}]")
        let courses = try JwNewUrpParser(src).generateCourseList()
        XCTAssertEqual(1, courses.count)
        XCTAssertEqual(1, courses[0].startWeek)
        XCTAssertEqual(3, courses[0].endWeek)
        XCTAssertEqual(1, courses[0].type) // 奇数开头 → 单周
        assertWeeksMatchBitmap(courses, bitmap: bitmap)
    }

    func test_twoElementEvenStrideRun_preservesBothWeeksTypeDouble() throws {
        // "01010000000000000000" → bits [2,4] → Android Triple(2,4,type=2)
        let bitmap = "01010000000000000000"
        let src = html(withDateList: "[{\"selectCourseList\":[" +
            course(name: "实验", teacher: "李老师",
                   timePlaces: [timePlace(classDay: 2, classWeek: bitmap)]) + "]}]")
        let courses = try JwNewUrpParser(src).generateCourseList()
        XCTAssertEqual(1, courses.count)
        XCTAssertEqual(2, courses[0].startWeek)
        XCTAssertEqual(4, courses[0].endWeek)
        XCTAssertEqual(2, courses[0].type) // 偶数开头 → 双周
        assertWeeksMatchBitmap(courses, bitmap: bitmap)
    }

    func test_fourElementStrideRun_midList_preservesEveryWeek() throws {
        // bits [1,3,6,8]: 段 [1,3] → (1,3,1); 段 [6,8] → (6,8,2)。
        // 与 867b814 和当前 Android 在 while 前保留第二周的契约一致。
        let bitmap = "10100101000000000000"
        let src = html(withDateList: "[{\"selectCourseList\":[" +
            course(name: "选修", teacher: "王老师",
                   timePlaces: [timePlace(classDay: 3, classWeek: bitmap)]) + "]}]")
        let courses = try JwNewUrpParser(src).generateCourseList()
        XCTAssertEqual(2, courses.count)
        XCTAssert([(1, 3, 1), (6, 8, 2)].elementsEqual(
                       courses.map { ($0.startWeek, $0.endWeek, $0.type) },
                        by: { $0 == $1 }))  // 元组非 Equatable, 用 by: 谓词版 elementsEqual
        assertWeeksMatchBitmap(courses, bitmap: bitmap)
    }

    func test_continuousStrideRun_beyondTwoElements_extendsEnd() throws {
        // "10101000000000000000" → bits [1,3,5] → (1,5,1) —— while 推进过 2 元素后 end 更新
        let src = html(withDateList: "[{\"selectCourseList\":[" +
            course(name: "选修A", teacher: "赵老师",
                   timePlaces: [timePlace(classDay: 4, classWeek: "10101000000000000000")]) + "]}]")
        let courses = try JwNewUrpParser(src).generateCourseList()
        XCTAssertEqual(1, courses.count)
        XCTAssert((1, 5, 1) == (courses[0].startWeek, courses[0].endWeek, courses[0].type))
    }

    func test_consecutiveWeeklyRun_yieldsTypeZero() throws {
        // "11110000000000000000" → bits [1,2,3,4] → (1,4,0)
        let src = html(withDateList: "[{\"selectCourseList\":[" +
            course(name: "高数", teacher: "钱老师",
                   timePlaces: [timePlace(classDay: 1, classWeek: "11110000000000000000")]) + "]}]")
        let courses = try JwNewUrpParser(src).generateCourseList()
        XCTAssertEqual(1, courses.count)
        XCTAssert((1, 4, 0) == (courses[0].startWeek, courses[0].endWeek, courses[0].type))
    }

    // MARK: - optString + Kotlin .trim() 语义

    func test_newlinePaddedValues_areTrimmedLikeKotlinTrim() throws {
        let tp = "{\"classDay\":1,\"classSessions\":1,\"continuingSession\":1," +
                 "\"classWeek\":\"11000000000000000000\",\"campusName\":\"\\n校区 \",\"teachingBuildingName\":\"楼\",\"classroomName\":\" 101\\n\"}"
        let src = html(withDateList: "[{\"selectCourseList\":[{\"courseName\":\"\\n离散\\n\",\"attendClassTeacher\":\" 孙老师 \"," +
            "\"timeAndPlaceList\":[" + tp + "]}]}]")
        let courses = try JwNewUrpParser(src).generateCourseList()
        XCTAssertEqual(1, courses.count)
        XCTAssertEqual("离散", courses[0].name)
        XCTAssertEqual("孙老师", courses[0].teacher)
        XCTAssertEqual("校区 楼 101", courses[0].room)
        XCTAssertFalse(courses[0].name.contains("\n"))
        XCTAssertFalse(courses[0].room.contains("\n"))
    }

    // MARK: - getJSONObject 异常冒泡

    func test_nonObjectElementInCourseList_throwsNotSilentlyDropped() {
        let src = html(withDateList: "[{\"selectCourseList\":[\"notAnObject\"]}]")
        XCTAssertThrowsError(try JwNewUrpParser(src).generateCourseList())
    }

    func test_nonObjectElementInTimeAndPlaceList_throws() {
        let src = html(withDateList: "[{\"selectCourseList\":[" +
            "{\"courseName\":\"X\",\"attendClassTeacher\":\"Y\",\"timeAndPlaceList\":[42]}]}]")
        XCTAssertThrowsError(try JwNewUrpParser(src).generateCourseList())
    }

    func test_nonObjectFirstDateElement_throws() {
        let src = html(withDateList: "[\"oops\"]")
        XCTAssertThrowsError(try JwNewUrpParser(src).generateCourseList())
    }

    // MARK: - optJSONArray 语义 (instanceof 检查, 无字符串强制转换)

    func test_timeAndPlaceListAsJsonString_isNotCoerced_skippedLikeAndroid() throws {
        // org.json optJSONArray 仅做 instanceof JSONArray: 值是数组字符串 → null → continue
        let tp = timePlace(classDay: 5, classWeek: "11000000000000000000")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let src = html(withDateList: "[{\"selectCourseList\":[{\"courseName\":\"弦乐\"," +
            "\"attendClassTeacher\":\"周老师\",\"timeAndPlaceList\":\"[" + tp + "]\"}]}]")
        let courses = try JwNewUrpParser(src).generateCourseList()
        XCTAssertTrue(courses.isEmpty)
    }

    func test_timeAndPlaceListAsGarbageString_isSkippedSilently() throws {
        // Android: 非 JSONArray → null → continue(不抛)
        let src = html(withDateList: "[{\"selectCourseList\":[{\"courseName\":\"坏\",\"attendClassTeacher\":\"T\",\"timeAndPlaceList\":\"{not an array\"}]}]")
        let courses = try JwNewUrpParser(src).generateCourseList()
        XCTAssertTrue(courses.isEmpty)
    }

    func test_optInt_stringValues_areCoercedLikeOrgJson() throws {
        // org.json optInt: 字符串值走 Integer.parseInt(trim()) → " 3 " → 3
        let tp = "{\"classDay\":\"1\",\"classSessions\":\" 3 \",\"continuingSession\":\"2\"," +
                 "\"classWeek\":\"11000000000000000000\",\"campusName\":\"校区\",\"teachingBuildingName\":\"\",\"classroomName\":\"\"}"
        let src = html(withDateList: "[{\"selectCourseList\":[{\"courseName\":\"课\",\"attendClassTeacher\":\"师\",\"timeAndPlaceList\":[" + tp + "]}]}]")
        let courses = try JwNewUrpParser(src).generateCourseList()
        XCTAssertEqual(1, courses.count)
        XCTAssertEqual(1, courses[0].day)
        XCTAssertEqual(3, courses[0].startNode)
        XCTAssertEqual(4, courses[0].endNode)
    }

    // MARK: - T8 置信度

    func test_confidenceAndFeatures() {
        let full = html(withDateList: "[{\"selectCourseList\":[{\"courseName\":\"A\",\"attendClassTeacher\":\"B\",\"timeAndPlaceList\":[" + timePlace(classDay: 1, classWeek: "11000000000000000000") + "]}]}]")
        let parser = JwNewUrpParser(full)
        XCTAssertEqual(100, parser.confidenceValue)
        XCTAssertEqual(["dateList", "selectCourseList", "timeAndPlaceList", "classWeek"], parser.matchedFeatureList)

        XCTAssertEqual(80, JwNewUrpParser("dateList selectCourseList").confidenceValue)
        XCTAssertEqual(50, JwNewUrpParser("only dateList here").confidenceValue)
        XCTAssertEqual(0, JwNewUrpParser("nothing").confidenceValue)
    }
}
