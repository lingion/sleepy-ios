// JwNewUrpParserTests.swift — ← JwNewUrpParser.kt (v1.0.61)
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

    func test_twoElementOddStrideRun_yieldsStartEqualsEnd() throws {
        // classWeek "10100000000000000000" → bits [1,3]
        // Android 真值: Triple(1,1,type=1) —— 2 元素 stride-2 段 end 保持 = start
        let src = html(withDateList: "[{\"selectCourseList\":[" +
            course(name: "体育", teacher: "张老师",
                   timePlaces: [timePlace(classDay: 1, classWeek: "10100000000000000000")]) + "]}]")
        let courses = try JwNewUrpParser(src).generateCourseList()
        XCTAssertEqual(1, courses.count)
        XCTAssertEqual(1, courses[0].startWeek)
        XCTAssertEqual(1, courses[0].endWeek)
        XCTAssertEqual(1, courses[0].type) // 奇数开头 → 单周
    }

    func test_twoElementEvenStrideRun_yieldsStartEqualsEndTypeDouble() throws {
        // "01010000000000000000" → bits [2,4] → Android Triple(2,2,type=2)
        let src = html(withDateList: "[{\"selectCourseList\":[" +
            course(name: "实验", teacher: "李老师",
                   timePlaces: [timePlace(classDay: 2, classWeek: "01010000000000000000")]) + "]}]")
        let courses = try JwNewUrpParser(src).generateCourseList()
        XCTAssertEqual(1, courses.count)
        XCTAssertEqual(2, courses[0].startWeek)
        XCTAssertEqual(2, courses[0].endWeek)
        XCTAssertEqual(2, courses[0].type) // 偶数开头 → 双周
    }

    func test_fourElementStrideRun_midList_keepsKotlinEndBehaviour() throws {
        // bits [1,3,6,8]: 段 [1,3] → (1,1,1); 段 [6,8] while 不推进 → (6,6,2)。
        // 与 Android while 循环前不预设 end 完全一致。
        let src = html(withDateList: "[{\"selectCourseList\":[" +
            course(name: "选修", teacher: "王老师",
                   timePlaces: [timePlace(classDay: 3, classWeek: "10100101000000000000")]) + "]}]")
        let courses = try JwNewUrpParser(src).generateCourseList()
        XCTAssertEqual(2, courses.count)
        XCTAssert([(1, 1, 1), (6, 6, 2)].elementsEqual(
                       courses.map { ($0.startWeek, $0.endWeek, $0.type) },
                       by: { $0 == $1 }))  // 元组非 Equatable, 用 by: 谓词版 elementsEqual
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
