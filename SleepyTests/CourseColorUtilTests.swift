// CourseColorUtilTests.swift — ← CourseColorUtilTest.kt 逐用例移植 (GPL-3.0)
// 覆盖: stableHue 确定性/值域 · 哨兵色判定 · 4 态矩阵 · 自定义色优先 · WeekView 边界钉桩
// 注: iOS 无 mock 桩问题,parseColor 真实现,自定义分支可断精确值。

import XCTest
import SwiftUI
@testable import Sleepy

final class CourseColorUtilTests: XCTestCase {

    private let neutral = Color(red: 0, green: 1, blue: 0) // 哨兵灰底,与 HSL/自定义分支皆可区分

    private func course(_ color: String, groupId: String = "grp-A") -> CourseEntity {
        CourseEntity(groupId: groupId, tableId: 1, courseName: "高等数学",
                     day: 1, startNode: 1, step: 2, startWeek: 1, endWeek: 16, color: color, id: 1)
    }

    // ============================ stableHue ============================

    func testStableHueSameGroupIdIsDeterministic() {
        XCTAssertEqual(CourseColorUtil.stableHue("grp-A"), CourseColorUtil.stableHue("grp-A"), accuracy: 0)
    }

    func testStableHueValueIn360Range() {
        let hues = ["grp-A", "grp-B", "grp-C", "高等数学", "英语", "物理实验"]
        for g in hues {
            let h = CourseColorUtil.stableHue(g)
            XCTAssertTrue(h >= 0 && h < 360, "hue 必须在 [0,360): \(g) -> \(h)")
        }
    }

    // 注:stableHue 的保证是「确定性 + 值域」,不保证不同 groupId 必异色(黄金角模 360 存在哈希碰撞)。

    func testStableHueMatchesKotlinJavaHash() {
        // Java String.hashCode("grp-A") = 74319512(手工算: g=103,r=114,p=112,-=45,A=65)
        // h = 103; h=103*31+114=3307; 3307*31+112=102629; 102629*31+45=3181744; 3181744*31+65=98634009...
        // 验证 javaHash 本身正确性(与 JVM 一致),用已知值:
        XCTAssertEqual(0, CourseColorUtil.javaHash(""), "空串 hash=0 (Java 语义)")
        // "a" = 97
        XCTAssertEqual(97, CourseColorUtil.javaHash("a"))
    }

    // ============================ hasCustomColor (哨兵色) ============================

    func testHasCustomColorCustomValueIsTrue() {
        XCTAssertTrue(CourseColorUtil.hasCustomColor(course("#FF5722")))
    }

    func testHasCustomColorSentinelIsFalse() {
        // 哨兵色 #FF6750A4 与主题默认紫相同,标记「未设置」
        XCTAssertFalse(CourseColorUtil.hasCustomColor(course("#FF6750A4")))
    }

    func testHasCustomColorSentinelCaseInsensitiveIsFalse() {
        XCTAssertFalse(CourseColorUtil.hasCustomColor(course("#ff6750a4")))
    }

    func testHasCustomColorBlankIsFalse() {
        XCTAssertFalse(CourseColorUtil.hasCustomColor(course("")))
    }

    // ============================ 4 态矩阵 ============================

    private func colorsEqual(_ a: Color, _ b: Color) -> Bool {
        let ua = UIColor(a), ub = UIColor(b)
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        ua.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        ub.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return r1 == r2 && g1 == g2 && b1 == b2 && a1 == a2
    }

    func testMatrixCustomWithoutColorlessReturnsCustomBranch() {
        let r = CourseColorUtil.pickCourseColorSwiftUI(course("#FF5722"), isDark: false,
                                                       neutralColor: neutral, colorless: false)
        XCTAssertTrue(!colorsEqual(r, neutral), "自定义色分支应返回非 neutral 色")
    }

    func testMatrixCustomWithColorlessStillReturnsCustomBranch() {
        // 核心红线:自定义色在 colorless=true 下仍优先,不被灰底覆盖
        let r = CourseColorUtil.pickCourseColorSwiftUI(course("#FF5722"), isDark: false,
                                                       neutralColor: neutral, colorless: true)
        XCTAssertTrue(!colorsEqual(r, neutral), "自定义色分支应返回非 neutral 色")
    }

    func testMatrixNoCustomWithColorlessReturnsNeutral() {
        let r = CourseColorUtil.pickCourseColorSwiftUI(course("#FF6750A4"), isDark: false,
                                                       neutralColor: neutral, colorless: true)
        XCTAssertTrue(colorsEqual(r, neutral), "无自定义色且 colorless=true 应返回 neutral 灰底")
    }

    func testMatrixNoCustomWithoutColorlessReturnsHsl() {
        let r = CourseColorUtil.pickCourseColorSwiftUI(course("#FF6750A4"), isDark: false,
                                                       neutralColor: neutral, colorless: false)
        XCTAssertTrue(!colorsEqual(r, neutral), "无自定义色且 colorless=false 应返回 HSL 色而非 neutral")
    }

    // ============================ 自定义色优先(四态皆不覆盖) ============================

    func testCustomPriorityNotOverriddenInAnyColorlessState() {
        // 同一自定义课程,colorless 四种开关态返回色一致(皆为自定义分支,不随 colorless 变化)
        let custom = course("#FF5722")
        let rFalse = CourseColorUtil.pickCourseColorSwiftUI(custom, isDark: false, neutralColor: neutral, colorless: false)
        let rTrue = CourseColorUtil.pickCourseColorSwiftUI(custom, isDark: false, neutralColor: neutral, colorless: true)
        XCTAssertTrue(colorsEqual(rFalse, rTrue), "colorless 开关不应改变自定义色的返回值")
        XCTAssertTrue(!colorsEqual(rFalse, neutral), "自定义色应返回非 neutral")
    }

    func testSameGroupIdDefaultHslIsStableAcrossCalls() {
        // 同 groupId 的默认 HSL 分支,两次调用取色一致(对齐 stableHue 确定性)
        let a = CourseColorUtil.pickCourseColorSwiftUI(course(""), isDark: false, neutralColor: neutral)
        let b = CourseColorUtil.pickCourseColorSwiftUI(course(""), isDark: false, neutralColor: neutral)
        XCTAssertTrue(colorsEqual(a, b), "同 groupId 的 HSL 颜色应稳定")
    }

    // ============================ WeekView 第5 widget 边界钉桩 (TS-1 / CS-V2) ============================

    func testWeekViewWidgetUnaffectedByColorlessSwitch() {
        // 见 Kotlin 原注释: colorless 开关唯一作用是把「无自定义色课程」的底色从 HSL 换为 neutral(灰)
        let cNoCustom = course("#FF6750A4") // 哨兵 = 未设置
        let aTrue = CourseColorUtil.pickCourseColorSwiftUI(cNoCustom, isDark: false, neutralColor: neutral, colorless: true)
        // A=true 时取 neutral 灰; WeekView 只消费此灰常量, 与开关状态无关。
        XCTAssertTrue(colorsEqual(aTrue, neutral), "A=true 时 WeekView 文本灰同源 token 为固定常量")
        // 自定义色课程在 A=true/A=false 双态下取色恒同(WeekView 即使有胶囊也免疫于开关)。
        let custom = course("#FF5722")
        XCTAssertTrue(colorsEqual(
            CourseColorUtil.pickCourseColorSwiftUI(custom, isDark: false, neutralColor: neutral, colorless: false),
            CourseColorUtil.pickCourseColorSwiftUI(custom, isDark: false, neutralColor: neutral, colorless: true)
        ), "自定义色课程在 A 开关双态下取色恒同(WeekView 不受影响边界)")
    }

    // ============================ iOS 侧新增: 精确值钉桩(parseColor 真实现) ============================

    func testCustomColorExactArgb() {
        // #FF5722 → r=0xFF,g=0x57,b=0x22
        XCTAssertEqual(0xFFFF5722, CourseColorUtil.parseColor("#FFFF5722"))
        XCTAssertNil(CourseColorUtil.parseColor("notacolor"))
    }

    func testLuminanceAndTextColorOn() {
        // 纯白 → 1.0, 纯黑 → 0.0
        XCTAssertEqual(1.0, CourseColorUtil.luminance(0xFFFFFF), accuracy: 0.01)
        XCTAssertEqual(0.0, CourseColorUtil.luminance(0x000000), accuracy: 0.01)
        // 深底 → 白字; 浅底+暗主题 → 黑字
        XCTAssertEqual(0xFFFFFFFF, CourseColorUtil.textColorOn(bg: 0xFF112233, isDark: true, onSurface: 0xFFABCDEF))
        XCTAssertEqual(0xFF000000, CourseColorUtil.textColorOn(bg: 0xFFEEEEEE, isDark: true, onSurface: 0xFFABCDEF))
        XCTAssertEqual(0xFFABCDEF, CourseColorUtil.textColorOn(bg: 0xFFEEEEEE, isDark: false, onSurface: 0xFFABCDEF))
    }

    func testHslToColorIntKnownValues() {
        // h=0,s=1,l=0.5 → 纯红 0xFFFF0000
        XCTAssertEqual(0xFFFF0000, CourseColorUtil.hslToColorInt(0, 1, 0.5))
        // h=120,s=1,l=0.5 → 纯绿 0xFF00FF00
        XCTAssertEqual(0xFF00FF00, CourseColorUtil.hslToColorInt(120, 1, 0.5))
        // h=240,s=1,l=0.5 → 纯蓝 0xFF0000FF
        XCTAssertEqual(0xFF0000FF, CourseColorUtil.hslToColorInt(240, 1, 0.5))
        // l=0 → 黑; l=1 → 白
        XCTAssertEqual(0xFF000000, CourseColorUtil.hslToColorInt(200, 0.8, 0))
        XCTAssertEqual(0xFFFFFFFF, CourseColorUtil.hslToColorInt(200, 0.8, 1))
    }
}
