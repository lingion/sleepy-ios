// ThemeAndPinyinTests.swift — D4 主题 + PinyinMatcher 测试(Android 无对应测试文件,iOS 立守卫)

import XCTest
import SwiftUI
@testable import Sleepy

final class ThemePresetTests: XCTestCase {

    func testPresetKeysAndCount() {
        // ← all = listOf(Default, Spring, Ocean, Peach, Slate);KEY_SYSTEM 不在列表(特殊处理)
        XCTAssertEqual(5, ThemePresets.all.count)
        XCTAssertEqual(["default", "spring", "ocean", "peach", "slate"], ThemePresets.all.map { $0.key })
        XCTAssertEqual("system", ThemePresets.KEY_SYSTEM)
    }

    func testByKeyFallback() {
        // ← byKey: null→Default; 未知→Default; 已知→对应
        XCTAssertEqual(ThemePresets.default.key, ThemePresets.byKey(nil).key)
        XCTAssertEqual(ThemePresets.default.key, ThemePresets.byKey("nonexistent").key)
        XCTAssertEqual(ThemePresets.spring.key, ThemePresets.byKey("spring").key)
        XCTAssertEqual(ThemePresets.ocean.key, ThemePresets.byKey("ocean").key)
    }

    func testDefaultSchemeColors() {
        // 抽查默认 scheme 关键色(0xFF6750A4 primary / 0xFFD0BCFF dark primary)
        let l = ThemePresets.default.light
        XCTAssertEqual(Color(0xFF6750A4), l.primary)
        XCTAssertEqual(Color(0xFF21005D), l.onPrimaryContainer)
        let d = ThemePresets.default.dark
        XCTAssertEqual(Color(0xFFD0BCFF), d.primary)
    }

    func testCoursePaletteProbeColors() {
        // ← LightCoursePalette.primary=0xFFEADDFF / Dark=0xFF4F378B(CourseColorUtil.isPaletteDark 消费)
        XCTAssertEqual(Color(0xFFEADDFF), lightCoursePalette.primary)
        XCTAssertEqual(Color(0xFF4F378B), darkCoursePalette.primary)
    }

    func testThemeProviderSystemKeyUsesDynamic() {
        // KEY_SYSTEM → 不走 preset(dynamic 分支);返回的 scheme 背景应为语义色
        // (无法直接断言语义色相等,断言不等于任一预设的背景)
        let dyn = SleepyThemeProvider.dynamicSystemScheme(dark: false)
        XCTAssertNotEqual(ThemePresets.default.light.background, dyn.background)
    }

    func testLocalizedNamesResolve() {
        // nameKey 必须能在 5 语言 strings 里解析(至少 zh-Hans)
        let zh = LocaleHelper.bundle(for: "zh-CN")
        for preset in ThemePresets.all {
            let name = zh.localizedString(forKey: preset.nameKey, value: nil, table: nil)
            XCTAssertNotNil(name, preset.nameKey)
            XCTAssertFalse(name == preset.nameKey, "\(preset.nameKey) 应有翻译值")
        }
    }
}

final class PinyinMatcherTests: XCTestCase {

    func testFirstLetterOf() {
        // ← BASIC_MAP 抽查
        XCTAssertEqual("H", PinyinMatcher.firstLetterOf("哈"))
        XCTAssertEqual("G", PinyinMatcher.firstLetterOf("工"))
        XCTAssertEqual("D", PinyinMatcher.firstLetterOf("大"))
        // 非汉字 → nil
        XCTAssertNil(PinyinMatcher.firstLetterOf("a"))
        XCTAssertNil(PinyinMatcher.firstLetterOf("1"))
    }

    func testNamePinyinShort() {
        // sortKey 单字母前缀 + 汉字取首字母
        XCTAssertEqual("aahgdsx", PinyinMatcher.namePinyinShort("阿哈工大数学", "A"))
        XCTAssertEqual("ahg", PinyinMatcher.namePinyinShort("阿哈工", ""))
        // 英文数字原样(小写)
        XCTAssertEqual("x1y2", PinyinMatcher.namePinyinShort("X1Y2", ""))
    }

    func testMatch() {
        // 名字直接包含
        XCTAssertTrue(PinyinMatcher.match("哈尔滨工程大学", "H", "哈尔滨"))
        // 拼音首字母
        XCTAssertTrue(PinyinMatcher.match("哈尔滨工程大学", "H", "hebgcdx"))
        XCTAssertTrue(PinyinMatcher.match("哈尔滨工程大学", "H", "heb"))
        // sortKey 前缀参与匹配(输入 h 应命中 H 前缀)
        XCTAssertTrue(PinyinMatcher.match("工程大学", "G", "gc"))
        // 空查询恒 true
        XCTAssertTrue(PinyinMatcher.match("任意", "R", "  "))
        // 不匹配
        XCTAssertFalse(PinyinMatcher.match("工程大学", "G", "zzz"))
        // 别名命中
        XCTAssertTrue(PinyinMatcher.match("学校A", "X", "别名", aliases: ["我的别名"]))
    }
}
