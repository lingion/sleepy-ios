import XCTest
import SwiftUI
import UIKit
@testable import Sleepy

final class CourseColorPreviewTests: XCTestCase {
    private func row(_ id: Int64, table: Int64 = 1, mode: Int = CourseColorMode.GROUP,
                     color: String = "") -> CourseEntity {
        CourseEntity(groupId: "shared", tableId: table, courseName: "Math", day: 1,
                     startNode: 1, step: 2, startWeek: 1, endWeek: 20,
                     color: color, colorMode: mode, id: id)
    }

    func testCustomCourseKeepsRedWhenUniformColorIsSelected() throws {
        let item = try XCTUnwrap(CourseColorPreview.groups(from: [
            row(1, mode: CourseColorMode.CUSTOM, color: "#FFFF0000")
        ]).first)
        let color = item.color(isDark: false, neutral: .blue, colorless: true, persistedHue: 120)
        XCTAssertEqual(UIColor(color), UIColor.red)
    }

    func testMissingPersistedHueUsesHomeFallbackInsteadOfPlannedHue() throws {
        let item = try XCTUnwrap(CourseColorPreview.groups(from: [row(1)]).first)
        let expected = CourseColorUtil.pickCourseColorSwiftUIWithGroupRows(
            row(1), groupRows: [row(1)], isDark: false, neutralColor: .gray)
        XCTAssertEqual(UIColor(item.color(isDark: false, neutral: .gray,
                                         colorless: false, persistedHue: nil)), UIColor(expected))
    }

    func testAutoPreviewRetainsWholeGroupAndDoesNotMixTimetables() throws {
        let auto = row(3, mode: CourseColorMode.AUTO)
        let base = row(2, color: "#FFFF0000")
        let otherTable = row(1, table: 2, color: "#FF0000FF")
        let groups = CourseColorPreview.groups(from: [auto, otherTable, base])
        XCTAssertEqual(groups.count, 2)
        let item = try XCTUnwrap(groups.first)
        XCTAssertEqual(item.groupRows.map(\.id), [3, 2])
        let expected = CourseColorUtil.pickCourseColorSwiftUIWithGroupRows(
            auto, groupRows: [auto, base], isDark: true, neutralColor: .gray, persistedHue: 80)
        XCTAssertEqual(UIColor(item.color(isDark: true, neutral: .gray,
                                         colorless: false, persistedHue: 80)), UIColor(expected))
    }

    func testPreviewLimitPreservesLaterRowsOfSelectedGroup() throws {
        var courses = (1...7).map { row(Int64($0), table: Int64($0)) }
        courses.append(row(8, table: 1))
        let groups = CourseColorPreview.groups(from: courses)
        XCTAssertEqual(groups.count, 5)
        XCTAssertEqual(try XCTUnwrap(groups.first).groupRows.map(\.id), [1, 8])
    }
}
