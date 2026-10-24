// ReminderScreenPreviewFormatTests.swift — ← ReminderScreen.kt buildDaily/BeforeClassPreviewText
// 覆盖: resolveFormat 混合位置符(%@/%lld 顺序 + %N$s 显式)在 Darwin 上的等价语义 —
// Android .strings 迁移到 iOS 后模板保留了 %4$s 位置符, String(format:) 直接喂会崩溃(实测),
// resolveFormat 是本机唯一安全路径; 用 zh-Hans 模板逐字符锁定输出。
// (android_test 源为空 — 本文件是新增纯逻辑的配套 XCTest, 非镜像移植)

import XCTest
@testable import Sleepy

final class ReminderScreenPreviewFormatTests: XCTestCase {

    private let dailyTmpl = "示例：%@，您有 %lld 节课。第一节课是「%@」，于 %4$s 在 %5$s 上课%6$s"
    private let beforeTmpl = "示例：%@，下节课是「%@」，于 %@ 在 %4$s 上课%5$s"

    func testDailyTemplatePositionalMixMatchesAndroidOrder() {
        let out = ReminderPreviewLoader.resolveFormat(dailyTmpl,
            ["今日 10/20（周二）", "3", "高数", "08:00", "A101", "，老师：王"])
        XCTAssertEqual(out, "示例：今日 10/20（周二），您有 3 节课。第一节课是「高数」，于 08:00 在 A101 上课，老师：王")
    }

    func testDailyTemplateEmptyTeacherCollapsesToNothing() {
        let out = ReminderPreviewLoader.resolveFormat(dailyTmpl,
            ["今日 10/20（周二）", "1", "英语", "10:00", "B203", ""])
        XCTAssertEqual(out, "示例：今日 10/20（周二），您有 1 节课。第一节课是「英语」，于 10:00 在 B203 上课")
    }

    func testBeforeClassTemplatePositionalMix() {
        let out = ReminderPreviewLoader.resolveFormat(beforeTmpl,
            ["10/20（周一）", "体育", "14:00", "体育馆", ""])
        // Android values-zh-rCN 模板为「在 %4$s 上课」—— 教室与「上课」之间的空格是模板字面量,
        // Java String.format 原样保留, 期望串必须含该空格(先前逐字符比对抄漏)。
        XCTAssertEqual(out, "示例：10/20（周一），下节课是「体育」，于 14:00 在 体育馆 上课")
    }

    func testSequentialPercentConsumesInOrder() {
        // 纯顺序模板(%@ %@)行为与 String(format:) 一致 — 回归保护
        let out = ReminderPreviewLoader.resolveFormat("A%@B%@C", ["1", "2"])
        XCTAssertEqual(out, "A1B2C")
    }

    func testEscapedPercentAndOutOfRangeArgs() {
        XCTAssertEqual(ReminderPreviewLoader.resolveFormat("100%@完成", ["%"]), "100%完成")
        // 越界位置符 → 空串(禁崩溃)
        XCTAssertEqual(ReminderPreviewLoader.resolveFormat("x%9$s y", ["only"]), "x y")
    }

    func testTimeTextNilFallsBackToDashes() {
        // ← startTime ?: "--:--"
        XCTAssertEqual(ReminderPreviewLoader.timeText(nil), "--:--")
        let cal = DateUtils.isoCalendar
        let d = cal.date(bySettingHour: 8, minute: 45, second: 0, of: Date())!
        XCTAssertEqual(ReminderPreviewLoader.timeText(d), "08:45")   // PREVIEW_TIME_FORMAT "HH:mm"
    }

    private func course(ownTime: Bool = false, startTime: String = "", startNode: Int = 1) -> CourseEntity {
        CourseEntity(groupId: "g", tableId: 1, courseName: "c",
                     day: 3, startNode: startNode, step: 1, startWeek: 1, endWeek: 20,
                     color: "#FF6750A4", ownTime: ownTime, startTime: startTime)
    }

    func testCourseStartTimeOwnTimeBeatsNodeTable() {
        let nodes = TimeTableUtils.parseNodes(TimeTableUtils.DEFAULT_TIME_JSON)
        // "H:mm" 单位小时必须可解析(Android ofPattern("H:mm"))
        let got = ReminderPreviewLoader.courseStartTime(course(ownTime: true, startTime: "9:30"), nodes: nodes)
        let cal = DateUtils.isoCalendar
        let expected = cal.startOfDay(for: Date()).addingTimeInterval(9 * 3600 + 30 * 60)
        XCTAssertEqual(got, expected)
    }

    func testCourseStartTimeOwnTimeInvalidFallsToNilNotNodes() {
        // ← Android: ownTime 且非空白但解析失败 → runCatching null(不回落节点表)
        let nodes = TimeTableUtils.parseNodes(TimeTableUtils.DEFAULT_TIME_JSON)
        XCTAssertNotNil(nodes.first)   // 前提: 节点表本身可解析
        let got = ReminderPreviewLoader.courseStartTime(course(ownTime: true, startTime: "25:00", startNode: 1), nodes: nodes)
        XCTAssertNil(got)
    }

    func testCourseStartTimeBlankOwnTimeFallsBackToNodes() {
        // ← isNotBlank 语义: 纯空白 startTime → 回落节点表(非跳过)
        let nodes = TimeTableUtils.parseNodes(TimeTableUtils.DEFAULT_TIME_JSON)
        let got = ReminderPreviewLoader.courseStartTime(course(ownTime: true, startTime: "   ", startNode: 2), nodes: nodes)
        XCTAssertEqual(got, nodes.first { $0.node == 2 }?.start)
    }

    func testCourseStartTimeUnresolvableNodeReturnsNil() {
        XCTAssertNil(ReminderPreviewLoader.courseStartTime(course(startNode: 99), nodes: []))
    }
}
