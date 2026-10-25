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
        // Java String.hashCode("grp-A") = 98627929(手工核验:
        // h=103; 103*31+114=3307; 3307*31+112=102629; 102629*31+45=3181544; 3181544*31+65=98627929)
        // 验证 javaHash 本身正确性(与 JVM 一致),用已知值:
        XCTAssertEqual(0, CourseColorUtil.javaHash(""), "空串 hash=0 (Java 语义)")
        // "a" = 97
        XCTAssertEqual(97, CourseColorUtil.javaHash("a"))
        // 非 ASCII 钉桩: Java/Kotlin hashCode 按 UTF-16 code unit 迭代(不是 UTF-8 字节)。
        // "高等数学" = (((0x9AD8*31+0x7B49)*31+0x6570)*31+0x5B66) = 1212073767。
        // 若误按 UTF-8 字节迭代,中文课名 groupId 两端哈希不同 → 同课跨端异色。
        XCTAssertEqual(98627929, CourseColorUtil.javaHash("grp-A"))
        XCTAssertEqual(1212073767, CourseColorUtil.javaHash("高等数学"),
                       "UTF-16 code unit 语义钉桩(Java String.hashCode 同值)")
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

    func testHasCustomColorFullWidthSpaceIsFalse() {
        // ← Kotlin isNotBlank 按 Character.isWhitespace 视全角空格 U+3000 为空;
        // Foundation .whitespacesAndNewlines 不覆盖 U+3000 → 必须用复刻谓词,否则同输入两端判定不同
        XCTAssertFalse(CourseColorUtil.hasCustomColor(course("\u{3000}")))
        XCTAssertFalse(CourseColorUtil.hasCustomColorHex("\u{3000}"))
        XCTAssertTrue(CourseColorUtil.hasCustomColorHex("\u{3000}#FF5722"), "空白+色值仍判自定义")
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
        // 6 位补 alpha=FF(仍带 '#')
        XCTAssertEqual(0xFFFF5722, CourseColorUtil.parseColor("#FF5722"))
        XCTAssertNil(CourseColorUtil.parseColor("notacolor"))
        // ← android.graphics.Color.parseColor 对齐: 无 '#' 前缀必抛异常 → 落空回退分支。
        // "FF5722" 照收会让坏 hex 自定义色两端走不同分支(GROUP/AUTO/CUSTOM 回落路径分歧)。
        XCTAssertNil(CourseColorUtil.parseColor("FF5722"), "无 # 前缀必须判非法(Android 语义)")
        XCTAssertNil(CourseColorUtil.parseColor("#FF57"), "位数不足")
        XCTAssertNil(CourseColorUtil.parseColor("#GGHHIIJK"), "非 hex 字符")
        XCTAssertNil(CourseColorUtil.parseColor(""), "空串")
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

    // ============================ 改组色(issue#22 spec §6.2 恢复) ============================

    private func groupCourse(_ id: Int64, color: String, mode: Int) -> CourseEntity {
        var c = CourseEntity(groupId: "grp-A", tableId: 1, courseName: "高等数学",
                             day: 1, startNode: 1, step: 2, startWeek: 1, endWeek: 16, color: color)
        c.id = id
        c.colorMode = mode
        return c
    }

    /// 同一输入下 hex-only 与实体版判定必须相同 — 哨兵值收敛到 SENTINEL_COLOR 单点
    func testHasCustomColorHexConsistentWithEntityVersion() {
        for hex in ["#FF5722", "#FF6750A4", "#ff6750a4", "", "  "] {
            XCTAssertEqual(CourseColorUtil.hasCustomColor(course(hex)),
                           CourseColorUtil.hasCustomColorHex(hex),
                           "hex=\(hex) 两版判定应一致")
        }
    }

    func testGroupSourceColorHexTakesMinIdGroupRow() {
        let rows = [
            groupCourse(3, color: "#FF0000FF", mode: CourseColorMode.GROUP),
            groupCourse(1, color: "#FFFF0000", mode: CourseColorMode.GROUP),
            groupCourse(2, color: "#FF00FF00", mode: CourseColorMode.CUSTOM),
        ]
        // 组色源 = GROUP 模式中最小 id 行的 color
        XCTAssertEqual("#FFFF0000", CourseColorUtil.groupSourceColorHex(rows))
    }

    func testGroupSourceColorHexFallsBackToMinIdRow() {
        let rows = [
            groupCourse(2, color: "#FF00FF00", mode: CourseColorMode.CUSTOM),
            groupCourse(1, color: "#FFFF0000", mode: CourseColorMode.AUTO),
        ]
        XCTAssertEqual("#FFFF0000", CourseColorUtil.groupSourceColorHex(rows))
    }

    /// spec §5.2"组色变则自动跟随": forRow 的 hue = baseHue(组色源) + idx×黄金角。
    /// iOS 真 UIColor/parseColor 可用(不像 Android JVM 桩), 直接锁组色源参与 + 行序发散。
    func testAutoRowHueConsumesGroupSourceAndDiverges() {
        let rows = [
            groupCourse(1, color: "#FFFF0000", mode: CourseColorMode.GROUP),
            groupCourse(2, color: "#FFFF0000", mode: CourseColorMode.GROUP),
        ]
        let hue1 = GoldenAngleColor.forRow(rows[0], rows, "#FFFF0000")
        let hue2 = GoldenAngleColor.forRow(rows[1], rows, "#FFFF0000")
        // 同输入确定性
        XCTAssertEqual(hue1, GoldenAngleColor.forRow(rows[0], rows, "#FFFF0000"), accuracy: 0)
        // 不同行 idx 发散(黄金角 137.508°)
        XCTAssertEqual(137.508, Double((Double(hue2) - Double(hue1) + 360).truncatingRemainder(dividingBy: 360)), accuracy: 0.01)
        // 组色源参与 baseHue: 换组色源 → hue 变(Android JVM 不可断言, iOS 真解析可断言)
        let hue1OtherSource = GoldenAngleColor.forRow(rows[0], rows, "#FF00FF00")
        XCTAssertNotEqual(hue1, hue1OtherSource, accuracy: 0.001)
    }

    // ============================ issue#22 3 态取色镜像用例(← CourseColorUtilTest.kt) ============================

    /// ← Android multiCourse(): 同组 g1、按 id 区分行
    private func multiCourse(_ id: Int64, color: String, mode: Int, groupId: String = "g1") -> CourseEntity {
        var c = CourseEntity(groupId: groupId, tableId: 1, courseName: "x",
                             day: 1, startNode: 1, step: 1, startWeek: 1, endWeek: 16,
                             color: color)
        c.id = id
        c.colorMode = mode
        return c
    }

    /// ← `WithGroupRows GROUP 模式回退到 stableHue(等价旧路径)`
    func testWithGroupRowsGroupModeFallsBackToStableHue() {
        let c = multiCourse(1, color: "#FF6750A4", mode: CourseColorMode.GROUP)
        let color = CourseColorUtil.pickCourseColorSwiftUIWithGroupRows(
            c, groupRows: [c], isDark: false, neutralColor: neutral)
        XCTAssertTrue(!colorsEqual(color, neutral), "GROUP 哨兵色应走 HSL stableHue(不为 neutral)")
        let expected = CourseColorUtil.hslToColor(CourseColorUtil.stableHue("g1"), 0.55, 0.82)
        XCTAssertTrue(colorsEqual(color, expected), "GROUP 回退与旧路径 stableHue 等价")
    }

    /// ← `WithGroupRows CUSTOM 模式用 row color(优先于 neutral)`
    func testWithGroupRowsCustomUsesRowColor() {
        let c = multiCourse(1, color: "#FF112233", mode: CourseColorMode.CUSTOM)
        let color = CourseColorUtil.pickCourseColorSwiftUIWithGroupRows(
            c, groupRows: [c], isDark: false, neutralColor: neutral)
        XCTAssertTrue(colorsEqual(color, Color(uiArgb: 0xFF112233)),
                      "CUSTOM 应解析 row.color 精确值(iOS 无 JVM 桩, 可断精确 ARGB)")
        XCTAssertTrue(!colorsEqual(color, neutral), "CUSTOM 分支优先于 neutral")
    }

    /// ← `WithGroupRows AUTO 模式 color 字段被忽略 — 即使填了色也按 row id 算`
    func testWithGroupRowsAutoIgnoresRowColorField() {
        let rows = [
            multiCourse(1, color: "#FFFF0000", mode: CourseColorMode.GROUP),
            multiCourse(2, color: "#FF00FF00", mode: CourseColorMode.AUTO),
        ]
        // AUTO 行 color 填了绿(恰与 neutral 同值),但应按组色源(红)+ golden angle 算 hue
        let color = CourseColorUtil.pickCourseColorSwiftUIWithGroupRows(
            rows[1], groupRows: rows, isDark: false, neutralColor: neutral)
        XCTAssertTrue(!colorsEqual(color, neutral), "AUTO 不应消费 row.color 字段")
        let expected = CourseColorUtil.hslToColor(
            GoldenAngleColor.forRow(rows[1], rows, "#FFFF0000"), 0.55, 0.82)
        XCTAssertTrue(colorsEqual(color, expected), "AUTO 走组色源 + 黄金角 + HSL 路径")
    }

    /// ← `GoldenAngleColor AUTO 模式 idx 0_1_2 hue 按 golden angle 推进`(绝对值钉桩,含模 360 回绕)
    func testGoldenAngleAutoAbsoluteHueProgression() {
        // 组色源=红(hue 0°),AUTO 行按行序 idx 1/2/3 → 137.508 / 275.016 / 52.524
        let rows = [
            multiCourse(1, color: "#FFFF0000", mode: CourseColorMode.GROUP),
            multiCourse(2, color: "", mode: CourseColorMode.AUTO),
            multiCourse(3, color: "", mode: CourseColorMode.AUTO),
            multiCourse(4, color: "", mode: CourseColorMode.AUTO),
        ]
        let h1 = GoldenAngleColor.forRow(rows[1], rows, "#FFFF0000")
        let h2 = GoldenAngleColor.forRow(rows[2], rows, "#FFFF0000")
        let h3 = GoldenAngleColor.forRow(rows[3], rows, "#FFFF0000")
        XCTAssertEqual(h1, 137.508, accuracy: 0.5)
        XCTAssertEqual(h2, 275.016, accuracy: 0.5)
        XCTAssertEqual(h3, 52.524, accuracy: 0.5)  // 412.524 % 360 = 52.524 回绕钉桩
    }

    /// ← `GoldenAngleColor baseHue 边界 — baseHue idx 1 回绕`。
    /// 注: Android 用例注释称 #FFFF00C8 hue≈350、期望落 (100,150),两处均与事实不符:
    ///   1. androidx RGBToHSL 实算 #FFFF00C8 hue = 312.94(非 350);
    ///   2. Android JVM 环境 parseColor 为 mockable 桩恒返 0 → baseHue 恒 0,
    ///      其 (100,150) 断言靠 137.508 过,并未真正钉住组色 hue。
    /// iOS 真解析,按事实值钉桩: baseHue=312.94, idx1=(312.94+137.508)%360=90.45,
    /// 钉住 iOS rgbToHslHue 与 androidx colorToHSL 的 hue 值一致 + 值域 [0,360) 回绕正确。
    func testGoldenAngleBaseHueWrapAroundBoundary() {
        let rows = [
            multiCourse(1, color: "#FFFF00C8", mode: CourseColorMode.GROUP),
            multiCourse(2, color: "", mode: CourseColorMode.AUTO),
        ]
        let h0 = GoldenAngleColor.forRow(rows[0], rows, "#FFFF00C8")
        let h1 = GoldenAngleColor.forRow(rows[1], rows, "#FFFF00C8")
        XCTAssertEqual(h0, 312.941, accuracy: 0.05)
        XCTAssertEqual(h1, 90.449, accuracy: 0.05)
        XCTAssertTrue(h1 >= 0 && h1 < 360, "回绕后必须落在 [0,360): \(h1)")
        XCTAssertEqual(137.508, Double((Double(h1) - Double(h0) + 360)
            .truncatingRemainder(dividingBy: 360)), accuracy: 0.01)
    }

    /// ← `GROUP 行写入组色后渲染走 hasCustomColor 优先回落`(setGroupSourceColor 落库路径)
    func testGroupRowColorChangeAffectsRendering() {
        let rows = [
            multiCourse(1, color: "#FF6750A4", mode: CourseColorMode.GROUP),
            multiCourse(2, color: "#FF6750A4", mode: CourseColorMode.GROUP),
        ]
        // 改组色前: 哨兵值 → stableHue 路径
        let before = CourseColorUtil.pickCourseColorSwiftUIWithGroupRows(
            rows[0], groupRows: rows, isDark: false, neutralColor: neutral)
        // 模拟 setGroupSourceColor 落库后的行
        let after = rows.map { var c = $0; c.color = "#FF123456"; return c }
        let afterColor = CourseColorUtil.pickCourseColorSwiftUIWithGroupRows(
            after[0], groupRows: after, isDark: false, neutralColor: neutral)
        XCTAssertTrue(!colorsEqual(before, afterColor), "改组色后 GROUP 行渲染色必须改变")
        XCTAssertTrue(colorsEqual(afterColor, Color(uiArgb: 0xFF123456)),
                      "落库后 GROUP 行走 hasCustomColor 解析优先,精确 #FF123456")
    }
}
