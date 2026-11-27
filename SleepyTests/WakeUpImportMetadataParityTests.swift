import Foundation
import XCTest
@testable import Sleepy

final class WakeUpImportMetadataParityTests: XCTestCase {
    func testSharePayloadKeepsUserMetadataAndIgnoresDisabledClocks() throws {
        let raw = """
        {}
        [{"node":1,"startTime":"08:00","endTime":"08:45"}]
        {"nodes":1,"startDate":"2026-08-31","maxWeek":21,"tableName":"Autumn term"}
        [{"id":1,"courseName":"Lab"},{"id":2,"courseName":"Lecture"}]
        [{"id":1,"day":1,"startNode":1,"step":1,"startWeek":1,"endWeek":12,"type":0,"courseNote":"Bring a notebook","ownTime":true,"startTime":"13:10","endTime":"14:40"},{"id":2,"day":2,"startNode":1,"step":1,"startWeek":1,"endWeek":12,"type":0,"ownTime":false,"startTime":"16:00","endTime":"17:00"}]
        """
        let parts = try WakeUpShareProtocol.parseRawScheduleData(raw)
        let json = try WakeUpShareProtocol.buildScheduleJson(parts)
        let parsed = try ScheduleParser.parse(json, defaultTableId: 12).get()
        XCTAssertEqual(parsed.tableName, "Autumn term")
        XCTAssertEqual(parsed.startDate, "2026-08-31")
        XCTAssertEqual(parsed.maxWeek, 21)
        XCTAssertEqual(parsed.courses.count, 2)
        let lab = try XCTUnwrap(parsed.courses.first)
        XCTAssertEqual(lab.note, "Bring a notebook")
        XCTAssertEqual(lab.ownTime, true)
        XCTAssertEqual(lab.startTime, "13:10")
        XCTAssertEqual(lab.endTime, "14:40")
        let lecture = try XCTUnwrap(parsed.courses.last)
        XCTAssertEqual(lecture.ownTime, false)
        XCTAssertEqual(lecture.startTime, "")
    }

    func testEncodedShareTextKeepsDeclaredWeeksAndNote() throws {
        let encoded = "%5B%7B%22name%22%3A%22Lab%22%2C%22note%22%3A%22Bring+a+notebook%22%7D%5D"
        let raw = """
        【来自WakeUp课程表】
        课程分享:
        {"name":"Fall","courseDetailJson":"\(encoded)","tableInfo":{"startDate":"2026-08-31","maxWeek":"21"}}
        """
        let parsed = try ScheduleParser.parse(raw, defaultTableId: 12).get()
        XCTAssertEqual(parsed.tableName, "Fall")
        XCTAssertEqual(parsed.startDate, "2026-08-31")
        XCTAssertEqual(parsed.maxWeek, 21)
        XCTAssertEqual(parsed.courses.first?.note, "Bring a notebook")
    }
}
