// LocaleAndL10nTests.swift — 语言切换即时生效(← Android Activity.recreate 等价链)
// 覆盖: applyLanguage 广播 L10n.didChangeNotification + L10n 读 LocaleHelper.currentBundle
// (切换后立即取到新语言值, 而非 Bundle.main 固定语言) + applyLanguage 持久化 AppPrefs。

import XCTest
@testable import Sleepy

final class LocaleAndL10nTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // 每用例从已知状态出发(AppPrefs 为进程级单例, 测试间串扰需显式复位)
        AppPrefs.shared.setLanguage("zh-CN")
    }

    override func tearDown() {
        AppPrefs.shared.setLanguage("zh-CN")
        super.tearDown()
    }

    func testApplyLanguagePostsDidChangeNotification() {
        let exp = expectation(forNotification: L10n.didChangeNotification, object: nil)
        LocaleHelper.applyLanguage("en")
        wait(for: [exp], timeout: 2)
    }

    func testApplyLanguagePersistsToPrefs() {
        LocaleHelper.applyLanguage("ja")
        XCTAssertEqual(AppPrefs.shared.getLanguage(), "ja")
    }

    func testL10nReadsCurrentLanguageImmediately() {
        // 切 en 后 L10n 立即取英文值(修复前: 固定 Bundle.main, 切换不生效)
        LocaleHelper.applyLanguage("en")
        XCTAssertEqual(L10n.t("settings_language"), "Language")
        LocaleHelper.applyLanguage("zh-CN")
        XCTAssertEqual(L10n.t("settings_language"), "语言 / Language")
    }

    func testL10nFormatUsesCurrentLanguage() {
        LocaleHelper.applyLanguage("en")
        XCTAssertEqual(L10n.format("course_count_format", 2), "2 courses")
        LocaleHelper.applyLanguage("zh-CN")
        XCTAssertEqual(L10n.format("course_count_format", 2), "2 门")
    }

    func testCourseCountFormatMatchesAndroidBaseline() {
        // ← strings.xml: %1$d 门 / %1$d courses(5 语言对照)
        let cases: [(String, Int, String)] = [
            ("zh-CN", 1, "1 门"), ("zh-TW", 1, "1 門"),
            ("en", 1, "1 courses"), ("ja", 1, "1 コマ"), ("es", 1, "1 cursos"),
        ]
        for (lang, n, expected) in cases {
            LocaleHelper.applyLanguage(lang)
            XCTAssertEqual(L10n.format("course_count_format", n), expected, "语言 \(lang)")
        }
        LocaleHelper.applyLanguage("zh-CN")
    }
}
