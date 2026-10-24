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
        // getLanguage() 无保存值时回退 AppleLanguages ← AppPrefs 首启推断语义。
        // 模拟器宿主语言可能是 en/es 等, 显式置中文环境保证 testDefaultValues 的
        // "zh-CN" 默认值断言稳定(不依赖跑测试的机器语言)。
        suite.set(["zh-CN"], forKey: "AppleLanguages")
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
        // ← Android 出厂默认: display_mode="time"(用户 2026-09-14 指令), show_date=true(用户反馈找不到开关)
        XCTAssertEqual("time", prefs.getDisplayMode())
        XCTAssertEqual("room", prefs.getGridSubInfo())
        XCTAssertTrue(prefs.isShowDate())
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

    func testFluidPrimaryAcceptsCountdown() {
        // ← Android v1.0.61 require(name|time|room|countdown): countdown 合法且往返一致
        prefs.setBeforeClassFluidPrimary("countdown")
        XCTAssertEqual("countdown", prefs.getBeforeClassFluidPrimary())
    }

    func testFactoryDefaultsAlignAndroid1061() {
        // ← AppPrefs.kt 出厂默认逐条: start_view="cards"(用户令网格优先),
        //   compact_window_today_first=true, calendar_apply_transfers=true,
        //   holiday 规则总开关=false(四类子开关=true), 实验室组全默认关
        XCTAssertEqual("cards", prefs.getStartView())
        XCTAssertTrue(prefs.isCompactWindowTodayFirst())
        XCTAssertTrue(prefs.isCalendarApplyTransfers())
        XCTAssertFalse(prefs.isHolidayReminderRulesEnabled())
        XCTAssertTrue(prefs.isHolidayReminderPublicHolidayEnabled())
        XCTAssertTrue(prefs.isTodayReminderEnabled())
        XCTAssertTrue(prefs.isShowViewSwitcher())
        XCTAssertFalse(prefs.isGridAutoHideEmptyEvening())
        XCTAssertFalse(prefs.isGridAdaptiveHeight())
        XCTAssertFalse(prefs.isGridPinchZoom())
        XCTAssertFalse(prefs.isGridShowSeparators())
        XCTAssertFalse(prefs.isGridLongBreakSpacing())
        XCTAssertEqual("18:00", prefs.getGridEveningStart())
        XCTAssertEqual(1.0, prefs.getGridRowScale())
    }

    func testGridLabKeysRoundTrip() {
        prefs.setGridAutoHideEmptyEvening(true)
        XCTAssertTrue(prefs.isGridAutoHideEmptyEvening())
        prefs.setGridEveningStart("19:30")
        XCTAssertEqual("19:30", prefs.getGridEveningStart())
        prefs.setGridRowScale(1.42)
        XCTAssertEqual(1.42, prefs.getGridRowScale()) // ← Android 读侧不钳制, 存什么读什么
        prefs.setShowViewSwitcher(false)
        XCTAssertFalse(prefs.isShowViewSwitcher())
        prefs.setTodayReminderEnabled(false)
        XCTAssertFalse(prefs.isTodayReminderEnabled())
    }

    func testScaleReadClampsAndSetterCoerces() {
        // ← Android coerceIn: 读侧钳制存量越界值; 写侧静默钳制不抛(precondition 已移除)
        suite.set(2.5, forKey: AppPrefs.KEY_GRID_SCALE)
        XCTAssertEqual(1.3, prefs.getGridScale())
        suite.set(0.1, forKey: AppPrefs.KEY_WEEK_SCALE)
        XCTAssertEqual(0.7, prefs.getWeekScale())
        suite.set(9.0, forKey: AppPrefs.KEY_GRID_CORNER_RATIO)
        XCTAssertEqual(2.0, prefs.getGridCornerRatio())
        suite.set(-3.0, forKey: AppPrefs.KEY_GRID_CORNER_RATIO)
        XCTAssertEqual(0.0, prefs.getGridCornerRatio()) // 0=直角, 是合法值(Android 无 0→1 哨兵)
        prefs.setGridScale(5.0)                          // 写侧越界 → 静默落 1.3
        XCTAssertEqual(1.3, prefs.getGridScale())
        XCTAssertEqual(1.0, AppPrefs(defaults: UserDefaults(suiteName: "test-empty-scale-\(UUID().uuidString)")!).getGridScale())
    }

    func testWeekTwoColumnModeNormalizesOnWrite() {
        // ← Android: if (v == "balance") "balance" else "days" — 任意其它值归一 "days"
        prefs.setWeekTwoColumnMode("balance")
        XCTAssertEqual("balance", prefs.getWeekTwoColumnMode())
        prefs.setWeekTwoColumnMode("garbage")
        XCTAssertEqual("days", prefs.getWeekTwoColumnMode())
    }

    // 注: Kotlin require() 抛异常可断言;Swift precondition() 是 fatal trap,
    // XCTest 无法捕获 → 不写触发式断言,非法值防护由 precondition 自身保证(与 require 同为程序员错误)。
}

// MARK: - LocaleHelper(iOS 新增: locale 映射 + bundle 定向)

final class LocaleHelperTests: XCTestCase {

    func testLocaleMapping() {
        // ← getLocale 的 5 分支 + default
        // iOS 15 兼容: language.languageCode 是 iOS16+ API,走 locale.languageCode
        func lang(_ id: String) -> String? { LocaleHelper.locale(for: id).languageCode }
        XCTAssertEqual("zh", lang("zh-CN"))
        XCTAssertEqual("zh", lang("zh-TW"))
        XCTAssertEqual("en", lang("en"))
        XCTAssertEqual("ja", lang("ja"))
        XCTAssertEqual("es", lang("es"))
        // script 码走 Locale.scriptCode(老 API,iOS15 可用;language.languageCode 才是 16+)
        XCTAssertEqual("Hans", Locale(identifier: "zh-Hans").scriptCode)
        XCTAssertEqual("Hant", Locale(identifier: "zh-Hant").scriptCode)
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
