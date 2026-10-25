// CourseDisplayUtilTests.swift — ← CourseDisplayUtilTest.kt 逐用例移植 (GPL-3.0)
// 覆盖: issue#26 展示名解析 — 关 = 原名(默认, 升级行为不变); 开 = 别名(空回退原名)。
// 纯逻辑单测, 无 iOS/Android 平台差异。

import XCTest
@testable import Sleepy

final class CourseDisplayUtilTests: XCTestCase {

    private func course(name: String, alias: String = "") -> CourseEntity {
        CourseEntity(groupId: "g1", tableId: 1, courseName: name,
                     day: 1, startNode: 3, step: 2, startWeek: 1, endWeek: 16,
                     color: "#FF6750A4", alias: alias)
    }

    func testSwitchOffReturnsOriginalName() {
        let c = course(name: "高等数学", alias: "高数")
        XCTAssertEqual("高等数学", CourseDisplayUtil.displayName(c, false))
    }

    func testSwitchOnWithAliasReturnsAlias() {
        let c = course(name: "高等数学", alias: "高数")
        XCTAssertEqual("高数", CourseDisplayUtil.displayName(c, true))
    }

    func testSwitchOnWithBlankAliasFallsBackToOriginal() {
        let c = course(name: "大学英语", alias: "   ")
        XCTAssertEqual("大学英语", CourseDisplayUtil.displayName(c, true))
    }

    func testSwitchOnWithEmptyAliasFallsBackToOriginal() {
        let c = course(name: "大学英语", alias: "")
        XCTAssertEqual("大学英语", CourseDisplayUtil.displayName(c, true))
    }

    func testLambdaOverloadDelegatesToBooleanVersion() {
        let c = course(name: "数据结构", alias: "DS")
        // Kotlin: displayName(c) { it.alias.isNotBlank() } — Swift 等价 isNotBlank = trim 后非空
        XCTAssertEqual("DS", CourseDisplayUtil.displayName(c) {
            !$0.alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        })
        XCTAssertEqual("数据结构", CourseDisplayUtil.displayName(c) { _ in false })
    }

    func testAliasIsDisplayOnlyField() {
        // 别名不影响 inWeek/startNode 等业务字段
        let c = course(name: "数据结构", alias: "DS")
        XCTAssertTrue(c.inWeek(3))
        XCTAssertEqual(3, c.startNode)
    }
}
