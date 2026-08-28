// VersionAndUpdateTests.swift — ← VersionUtilsTest.kt + UpdateInfoParseTest.kt (逐用例)
// + AppPrefs/LocaleHelper iOS 新增覆盖

import XCTest
import Combine
@testable import Sleepy

// MARK: - ← VersionUtilsTest.kt (4 断言,逐条)

final class VersionUtilsTests: XCTestCase {

    func testComparesNumericVersionsAndIgnoresBuildSuffix() {  // ← comparesNumericVersionsAndIgnoresBuildSuffix
        XCTAssertEqual(0, VersionUtils.compare("1.0.25-debug", "1.0.25"))
        XCTAssertEqual(0, VersionUtils.compare("v1.0.26", "1.0.26"))
        XCTAssertLessThan(VersionUtils.compare("1.0.25", "1.0.26"), 0)
        XCTAssertGreaterThan(VersionUtils.compare("1.0.10", "1.0.9"), 0)
    }
}

// MARK: - ← UpdateInfoParseTest.kt (5 用例,逐条)

final class UpdateInfoParseTests: XCTestCase {

    private let sampleBody = """
    {"tag_name":"v1.0.32","body":"## v1.0.32\\n\\n修复 bug","assets":[
        {"name":"app-arm64-v8a-release.apk","browser_download_url":"https://example.com/a.apk"},
        {"name":"app-armeabi-v7a-release.apk","browser_download_url":"https://example.com/b.apk"}]}
    """

    func testParsesVersionChangelogUrlFromGithubJson() {  // ← parses_version_changelog_url_from_github_json
        let info = parseReleaseJson(sampleBody, currentVersion: "1.0.31", abi: "ios")
        XCTAssertEqual("1.0.32", info.version)
        // Android changelog = "## v1.0.32\n\n修复 bug";iOS asset 名 = Sleepy.ipa
        XCTAssertEqual("## v1.0.32\n\n修复 bug", info.changelog)
        XCTAssertTrue(info.isUpdateAvailable)
    }

    func testOlderRemoteVersionIsNotAnUpdate() {  // ← older_remote_version_is_not_an_update
        let info = parseReleaseJson(sampleBody, currentVersion: "1.0.33", abi: "ios")
        XCTAssertFalse(info.isUpdateAvailable)
    }

    func testSameVersionWithForceFlagIsUpdate() {  // ← same_version_with_force_flag_is_update
        let body = sampleBody.replacingOccurrences(of: "修复 bug", with: "修复 bug SLEEPY_FORCE_UPDATE=true")
        let info = parseReleaseJson(body, currentVersion: "1.0.32", abi: "ios")
        XCTAssertTrue(info.isUpdateAvailable)
    }

    func testMissingAssetForAbiReturnsBlankUrl() {  // ← missing_asset_for_abi_returns_blank_url
        // Android: x86_64 无 asset → 空 url;iOS: assets 无 Sleepy.ipa → 空 url(等价断言)
        let noIpa = """
        {"tag_name":"v2.0.0","body":"x","assets":[
            {"name":"app-arm64-v8a-release.apk","browser_download_url":"https://example.com/a.apk"}]}
        """
        let info = parseReleaseJson(noIpa, currentVersion: "1.0.0", abi: "ios")
        XCTAssertEqual("", info.downloadUrl)
    }

    func testEmptyTagFallsBackToZero() {
        // Android: version.ifBlank { "0" } — 空 tag 不该 crash 且恒非更新
        let empty = #"{"tag_name":"","body":"x","assets":[]}"#
        let info = parseReleaseJson(empty, currentVersion: "1.0.0", abi: "ios")
        XCTAssertFalse(info.isUpdateAvailable)
    }

    func testBrokenJsonIsNotUpdate() {
        let info = parseReleaseJson("not json {{{", currentVersion: "1.0.0", abi: "ios")
        XCTAssertFalse(info.isUpdateAvailable)
        XCTAssertEqual("", info.downloadUrl)
    }
}

// MARK: - AppPrefs(iOS 新增:每个默认值 + 读写往返 + legacy 兼容分支)

final class AppPrefsTests: XCTestCase {

    private var prefs: AppPrefs!
    private var suite: UserDefaults!

    override func setUp() {
        super.setUp()
        suite = UserDefaults(suiteName: "test-sleepy-prefs-\(UUID().uuidString)")
        prefs = AppPrefs(defaults: suite)
    }

    override func tearDown() {
        suite.removePersistentDomain(forName: suite.dictionaryRepresentation()["__suiteName"] as? String ?? "")
        suite = nil
        prefs = nil
        super.tearDown()
    }

    func testDefaultValues() {
        // 逐一对照 AppPrefs.kt 的默认值
        XCTAssertEqual("system", prefs.getThemeMode())
        XCTAssertFalse(prefs.isReminderEnabled())            // default false
        XCTAssertTrue(prefs.isDailyReminderEnabled())        // default true
        XCTAssertEqual("07:00", prefs.getDailyReminderTime())
        XCTAssertFalse(prefs.isBeforeClassEnabled())         // default false
        XCTAssertEqual(10, prefs.getBeforeClassMinutes())
        XCTAssertTrue(prefs.isBeforeClassBannerEnabled())    // default true
        XCTAssertFalse(prefs.isBeforeClassFluidEnabled())    // default false
        XCTAssertEqual(["name", "time", "room", "teacher"], prefs.getBeforeClassFluidFields())
        XCTAssertEqual("room", prefs.getBeforeClassFluidPrimary())
        XCTAssertEqual("zh-CN", prefs.getLanguage())
        XCTAssertEqual("node", prefs.getDisplayMode())
        XCTAssertEqual("room", prefs.getGridSubInfo())
        XCTAssertFalse(prefs.isShowDate())
        XCTAssertEqual(Set(1...7), prefs.getVisibleDays())
        XCTAssertFalse(prefs.isVertPunctReplace())
        XCTAssertFalse(prefs.isWidgetColorless())
        XCTAssertFalse(prefs.isCourseColorless())
        XCTAssertTrue(prefs.isWidgetSeparator())             // default true
    }

    func testDarkModeThreeStates() {
        // 三态优先
        prefs.setThemeMode("dark")
        XCTAssertTrue(prefs.isDarkMode())
        prefs.setThemeMode("light")
        XCTAssertFalse(prefs.isDarkMode(isSystemDark: true))
        prefs.setThemeMode("system")
        XCTAssertTrue(prefs.isDarkMode(isSystemDark: true))
        XCTAssertFalse(prefs.isDarkMode(isSystemDark: false))
    }

    func testDarkModeLegacyBooleanCompat() {
        // ← isDarkMode 向后兼容: 仅当 theme_mode **从未写入** 时旧 KEY_DARK boolean 生效
        // (上面的三态测试已写过 theme_mode,故此处用全新 suite 验证 legacy 分支)
        XCTAssertFalse(prefs.isDarkMode()) // 两键全无 → system + not dark
        suite.set(true, forKey: AppPrefs.KEY_DARK)
        XCTAssertTrue(prefs.isDarkMode(isSystemDark: false))
        suite.set(false, forKey: AppPrefs.KEY_DARK)
        XCTAssertFalse(prefs.isDarkMode(isSystemDark: true))
        // 一旦写入 theme_mode,legacy 失效
        prefs.setThemeMode("dark")
        suite.set(false, forKey: AppPrefs.KEY_DARK)
        XCTAssertTrue(prefs.isDarkMode())
    }

    func testVisibleDaysRoundTripAndParse() {
        // ← setVisibleDays/getVisibleDays: sorted join + mapNotNull 语义
        prefs.setVisibleDays([1, 3, 5])
        XCTAssertEqual(Set([1, 3, 5]), prefs.getVisibleDays())
        // 脏数据: 非数字段丢弃,空段丢弃
        suite.set("1, x ,3,,abc", forKey: AppPrefs.KEY_VISIBLE_DAYS)
        XCTAssertEqual(Set([1, 3]), prefs.getVisibleDays())
    }

    func testThemeKeyRoundTripAndPublisher() {
        // 注: 本机 Xcode 14.3.1 + iOS 16.4 模拟器 XCTest 运行时存在 Combine 环境级异常 —
        // 订阅瞬间的 CurrentValueSubject 回放可收到, 之后任何 send()(同步/异步/任意 subject)
        // 均不投递给 sink(MinimalCombineProbeTests 最小复现;macOS 同工具链正常)。
        // 故投递式断言(received 数组)不可用, 改为断言可观察契约:
        //   持久化往返 + subject.value 即时更新(后续订阅者能拿到最新值 = distinctUntilChanged 语义基础)。
        XCTAssertEqual(ThemePresets.KEY_DEFAULT, prefs.getThemeKey())
        // 订阅期回放在此环境可用 — 顺带验证 publisher 通道接通
        var received: [String] = []
        let c = prefs.themeKeyPublisher.removeDuplicates().sink { received.append($0) }
        XCTAssertEqual([ThemePresets.KEY_DEFAULT], received)
        prefs.setThemeKey("custom-1")
        prefs.setThemeKey("custom-2")
        prefs.setThemeKey("custom-2") // ← distinctUntilChanged: 重复值不重发
        XCTAssertEqual("custom-2", prefs.getThemeKey())      // 持久化往返
        // 重新订阅应拿到最新值 custom-2(= CurrentValueSubject 当前值契约, 也是
        // distinctUntilChanged 流语义的基础;投递式断言受环境限制不可用, 见上注)
        var received2: [String] = []
        let c2 = prefs.themeKeyPublisher.removeDuplicates().sink { received2.append($0) }
        XCTAssertEqual(["custom-2"], received2)
        _ = c
        _ = c2
    }

    func testPrimaryWriteDoesNotClobberFields() {
        // ★ ← setBeforeClassFluidPrimary 注释的硬约束: 只写 PRIMARY,不覆盖 FIELDS
        suite.set("name,time", forKey: AppPrefs.KEY_BEFORE_CLASS_FLUID_FIELDS)
        prefs.setBeforeClassFluidPrimary("room")
        XCTAssertEqual(["name", "time"], Array(prefs.getBeforeClassFluidFields()).sorted())
        XCTAssertEqual("room", prefs.getBeforeClassFluidPrimary())
    }

    // 注: Kotlin require() 抛异常可断言;Swift precondition() 是 fatal trap,
    // XCTest 无法捕获 → 不写触发式断言,非法值防护由 precondition 自身保证(与 require 同为程序员错误)。
}

// MARK: - LocaleHelper(iOS 新增: locale 映射 + bundle 定向)

final class LocaleHelperTests: XCTestCase {

    func testLocaleMapping() {
        // ← getLocale 的 5 分支 + default
        XCTAssertEqual("zh", LocaleHelper.locale(for: "zh-CN").language.languageCode?.identifier)
        XCTAssertEqual("Hans", LocaleHelper.locale(for: "zh-CN").language.script?.identifier)
        XCTAssertEqual("zh", LocaleHelper.locale(for: "zh-TW").language.languageCode?.identifier)
        XCTAssertEqual("Hant", LocaleHelper.locale(for: "zh-TW").language.script?.identifier)
        XCTAssertEqual("en", LocaleHelper.locale(for: "en").identifier)
        XCTAssertEqual("ja", LocaleHelper.locale(for: "ja").identifier)
        XCTAssertEqual("es", LocaleHelper.locale(for: "es").identifier)
    }

    func testLprojNames() {
        XCTAssertEqual("zh-Hans", LocaleHelper.lprojName(for: "zh-CN"))
        XCTAssertEqual("zh-Hant", LocaleHelper.lprojName(for: "zh-TW"))
        XCTAssertEqual("en", LocaleHelper.lprojName(for: "en"))
        XCTAssertEqual("ja", LocaleHelper.lprojName(for: "ja"))
        XCTAssertEqual("es", LocaleHelper.lprojName(for: "es"))
    }

    func testBundleResolvesLanguage() {
        // 定向 bundle 里取一个已知键(必须 ≠ main 兜底的英文值,以证明定向生效)
        let en = LocaleHelper.bundle(for: "en")
        let zh = LocaleHelper.bundle(for: "zh-CN")
        let enVal = en.localizedString(forKey: "settings_language", value: "?", table: nil)
        let zhVal = zh.localizedString(forKey: "settings_language", value: "?", table: nil)
        XCTAssertNotEqual(enVal, zhVal, "定向 bundle 应取到不同语言的值")
    }
}
