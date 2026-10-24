// CustomThemeTests.swift — ← app/src/test/java/com/lingion/sleepy/data/CustomThemeCoreTest.kt
//                          + ← app/src/test/java/com/lingion/sleepy/ui/theme/CustomSchemeDeriverTest.kt
//
// 两组纯逻辑测试(不碰 UI):存储 Core 的 JSON 契约/upsert/delete 语义 + 派生引擎 5 条契约。
// iOS 侧新增第三组:custom:<id> 解析接线(ThemePresets.CUSTOM_KEY_PREFIX / provider 回落种子 /
// resolveWidgetScheme 三分支),Android 由 Theme.kt 的 Compose 测试覆盖,iOS 立守卫。
//
// 数值断言一律带容差:iOS 侧 Color → UIColor → 分量存在色域转换与 8-bit 量化,
// 逐位相等不成立(Android Compose Color 是纯 Float 载体,可以精确相等)。

import Combine
import XCTest
import SwiftUI
@testable import Sleepy

/// Color → [r, g, b]:Swift 元组不能当 XCTAssertEqual 的 Equatable 参数,统一转数组比
private func rgbComponents(_ color: Color) -> [Float] {
    let c = CustomSchemeDeriver.rgb(of: color)
    return [c.r, c.g, c.b]
}

// MARK: - ← CustomThemeCoreTest.kt

final class CustomThemeCoreTests: XCTestCase {

    private let sample = CustomTheme(
        id: "11111111-2222-3333-4444-555555555555",
        name: "主题 1",
        primary: "#AABBCC",
        secondary: "#112233",
        tertiary: "#445566",
        surfaceHue: 265.0,
        surfaceChroma: 8.0,
        createdAt: 1_700_000_000
    )

    // ── 序列化形状契约 ──

    func testSerializedJsonContainsAllDocumentedFields() {
        let json = CustomThemeCore.toJson([sample])
        // 设计文档定的 8 字段形状,key 名是跨版本存储契约,禁改名
        for field in ["id", "name", "primary", "secondary", "tertiary", "surfaceHue", "surfaceChroma", "createdAt"] {
            XCTAssertTrue(json.contains("\"\(field)\""), "serialized JSON must contain field \"\(field)\"")
        }
    }

    func testRoundtripPreservesAllFields() {
        let parsed = CustomThemeCore.parse(CustomThemeCore.toJson([sample]))
        XCTAssertEqual(1, parsed.count)
        XCTAssertEqual(sample, parsed[0])
    }

    func testRoundtripMultipleThemesPreservesOrder() {
        let second = sample.copy(id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", name: "主题 2")
        let parsed = CustomThemeCore.parse(CustomThemeCore.toJson([sample, second]))
        XCTAssertEqual([sample.id, second.id], parsed.map { $0.id })
    }

    // ── 容错语义 ──

    func testMalformedJsonReturnsEmptyList() {
        XCTAssertTrue(CustomThemeCore.parse("{not json").isEmpty)
        XCTAssertTrue(CustomThemeCore.parse("").isEmpty)
        XCTAssertTrue(CustomThemeCore.parse("null").isEmpty)
        // 对象而非数组 — 形状错同样容错为空
        XCTAssertTrue(CustomThemeCore.parse("{\"id\":\"x\"}").isEmpty)
    }

    func testBadRowsSkippedGoodRowsKept() {
        let json = """
        [
          {"id":"good-1","name":"好主题","primary":"#AABBCC","secondary":"#112233","tertiary":"#445566","surfaceHue":265.0,"surfaceChroma":8.0,"createdAt":1},
          {"name":"缺 id 的坏行","primary":"#FFFFFF","secondary":"#FFFFFF","tertiary":"#FFFFFF","surfaceHue":0.0,"surfaceChroma":0.0,"createdAt":2},
          {"id":"good-2","name":"也好","primary":"#000001","secondary":"#000002","tertiary":"#000003","surfaceHue":120.0,"surfaceChroma":4.0,"createdAt":3}
        ]
        """
        let parsed = CustomThemeCore.parse(json)
        XCTAssertEqual(["good-1", "good-2"], parsed.map { $0.id })
    }

    func testMissingOptionalFieldsFallBackToDefaults() {
        // 容错宽容:缺 surfaceHue/Chroma/createdAt 不整行丢弃(向后兼容旧版本数据)
        let json = """
        [{"id":"minimal","name":"M","primary":"#AABBCC","secondary":"#112233","tertiary":"#445566"}]
        """
        let parsed = CustomThemeCore.parse(json)
        XCTAssertEqual(1, parsed.count)
        let theme = parsed[0]
        XCTAssertEqual(CustomThemeCore.DEFAULT_SURFACE_HUE, theme.surfaceHue, accuracy: 0.001)
        XCTAssertEqual(CustomThemeCore.DEFAULT_SURFACE_CHROMA, theme.surfaceChroma, accuracy: 0.001)
        XCTAssertEqual(0, theme.createdAt)
    }

    // ── upsert / delete 语义 ──

    func testUpsertExistingIdReplacesInPlace() {
        var list = [sample]
        CustomThemeCore.upsert(&list, sample.copy(name: "改名了", secondary: "#999999"))
        XCTAssertEqual(1, list.count)
        XCTAssertEqual("改名了", list[0].name)
        XCTAssertEqual("#999999", list[0].secondary)
    }

    func testUpsertNewIdAppends() {
        var list: [CustomTheme] = []
        CustomThemeCore.upsert(&list, sample)
        XCTAssertEqual([sample], list)
    }

    func testDeleteRemovesOnlyTargetId() {
        let other = sample.copy(id: "other-id")
        var list = [sample, other]
        XCTAssertTrue(CustomThemeCore.delete(&list, sample.id))
        XCTAssertEqual([other], list)
    }

    func testDeleteUnknownIdReturnsFalseAndMutatesNothing() {
        var list = [sample]
        XCTAssertNil(CustomThemeCore.getById(list, "missing"))
        XCTAssertFalse(CustomThemeCore.delete(&list, "missing"))
        XCTAssertEqual([sample], list)
    }

    // ── getById ──

    func testGetByIdFindsExactMatch() {
        let other = sample.copy(id: "other-id")
        XCTAssertEqual(sample, CustomThemeCore.getById([sample, other], sample.id))
        XCTAssertNotNil(CustomThemeCore.getById([sample, other], "other-id"))
    }

    func testGetByIdEmptyListReturnsNil() {
        XCTAssertNil(CustomThemeCore.getById([], sample.id))
    }

    // ── 门面(可注入 UserDefaults,不碰宿主 standard defaults)──

    func testStoreFacadeRoundtripAndDelete() {
        let suite = UserDefaults(suiteName: "test-custom-themes-\(UUID().uuidString)")!
        defer { suite.removePersistentDomain(forName: suite.dictionaryRepresentation()["__suiteName"] as? String ?? "") }

        let second = sample.copy(id: "second-id", name: "主题 2")
        XCTAssertTrue(CustomThemeStore.getAll(suite).isEmpty)

        CustomThemeStore.save(sample, suite)
        CustomThemeStore.save(second, suite)
        XCTAssertEqual([sample.id, second.id], CustomThemeStore.getAll(suite).map { $0.id })
        XCTAssertEqual(sample, CustomThemeStore.getById(sample.id, suite))
        XCTAssertNil(CustomThemeStore.getById("nope", suite))

        // upsert:同 id 改名 → 原位替换,顺序不变
        CustomThemeStore.save(sample.copy(name: "改名了"), suite)
        XCTAssertEqual([sample.id, second.id], CustomThemeStore.getAll(suite).map { $0.id })
        XCTAssertEqual("改名了", CustomThemeStore.getById(sample.id, suite)?.name)

        XCTAssertTrue(CustomThemeStore.delete(sample.id, suite))
        XCTAssertFalse(CustomThemeStore.delete(sample.id, suite))
        XCTAssertEqual([second.id], CustomThemeStore.getAll(suite).map { $0.id })
    }

    /// 门面写坏数据 → 读回空(整篇损坏容错语义在门面上同样成立)
    func testStoreFacadeToleratesCorruptDocument() {
        let suite = UserDefaults(suiteName: "test-custom-themes-\(UUID().uuidString)")!
        defer { suite.removePersistentDomain(forName: suite.dictionaryRepresentation()["__suiteName"] as? String ?? "") }
        suite.set("{not json", forKey: CustomThemeCore.KEY_THEMES)
        XCTAssertTrue(CustomThemeStore.getAll(suite).isEmpty)
    }

    // ── ← CustomThemeStore.changes() 反应式失效信号(对应 Android callbackFlow+distinctUntilChanged;
    //    CustomThemeSaveAppliesImmediatelyTest 契约 2 的 iOS 立测:同 id 就地编辑必须发出新 token)──

    /// didChangeNotification 经 CFPreferences 广播投递,可能落到下一轮 runloop —
    /// 统一用 runloop 泵等待目标计数,超时即失败。
    private func pumpUntil(_ count: Int, in received: () -> [String], timeout: TimeInterval = 2.0) {
        let deadline = Date().addingTimeInterval(timeout)
        while received().count < count, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
    }

    func testChangesEmitsCurrentDocumentThenSameIdEditToken() {
        let suite = UserDefaults(suiteName: "test-custom-changes-\(UUID().uuidString)")!
        var received: [String] = []
        let cancellable = CustomThemeStore.changes(suite).sink { received.append($0) }
        defer { cancellable.cancel() }

        // 订阅即收当前文档:未写入过 → 空串(← Android trySend(getString ?: "") 初值)
        XCTAssertEqual([""], received)

        CustomThemeStore.save(sample, suite)
        pumpUntil(2, in: { received })
        XCTAssertEqual(2, received.count, "save must emit the new serialized document")
        let afterSave = received[1]
        XCTAssertTrue(afterSave.contains(sample.id))

        // 同 id 就地编辑(themeKey 不变)→ 文档内容变 → 必须再发一个不同 token
        CustomThemeStore.save(sample.copy(name: "改名了"), suite)
        pumpUntil(3, in: { received })
        XCTAssertEqual(3, received.count, "same-id in-place edit must produce a fresh invalidation token")
        XCTAssertNotEqual(afterSave, received[2])

        // distinctUntilChanged:文档未变的其他写入(同域其他 key)不得重复发
        suite.set("noise", forKey: "unrelated_key_in_same_domain")
        let countBeforeNoise = received.count
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(countBeforeNoise, received.count, "unchanged document must not re-emit (removeDuplicates)")
    }

    func testChangesIgnoresOtherDefaultsDomains() {
        let suiteA = UserDefaults(suiteName: "test-custom-changes-A-\(UUID().uuidString)")!
        let suiteB = UserDefaults(suiteName: "test-custom-changes-B-\(UUID().uuidString)")!
        var received: [String] = []
        let cancellable = CustomThemeStore.changes(suiteA).sink { received.append($0) }
        defer { cancellable.cancel() }

        // 另一域写主题 → object !== suiteA → 过滤,不发出
        CustomThemeStore.save(sample, suiteB)
        let countAfterInitial = received.count
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(countAfterInitial, received.count, "other UserDefaults domain must not drive this subscription")

        // 本域删除 → 发出空文档 token(删除后文档为 "[]":saveAll 写序列化空数组,
        //   ← Android 同语义,getString 返回 "[]" 而非 null)
        CustomThemeStore.save(sample, suiteA)
        pumpUntil(2, in: { received })
        CustomThemeStore.delete(sample.id, suiteA)
        pumpUntil(3, in: { received })
        XCTAssertEqual(3, received.count)
        XCTAssertEqual("[]", received[2], "deleting the only theme emits the empty serialized document")
    }
}

// MARK: - ← CustomSchemeDeriverTest.kt

final class CustomSchemeDeriverTests: XCTestCase {

    private func fakeTheme(
        primary: String = "#7C4DFF",
        secondary: String = "#546E7A",
        tertiary: String = "#EF6C00",
        surfaceHue: Double = 265.0,
        surfaceChroma: Double = 8.0
    ) -> CustomTheme {
        CustomTheme(id: "test", name: "test", primary: primary, secondary: secondary, tertiary: tertiary,
                    surfaceHue: surfaceHue, surfaceChroma: surfaceChroma, createdAt: 0)
    }

    private func allColors(_ scheme: WakeUpColorScheme) -> [Color] {
        [
            scheme.primary, scheme.onPrimary, scheme.primaryContainer, scheme.onPrimaryContainer,
            scheme.secondary, scheme.onSecondary, scheme.secondaryContainer, scheme.onSecondaryContainer,
            scheme.tertiary, scheme.onTertiary, scheme.tertiaryContainer, scheme.onTertiaryContainer,
            scheme.background, scheme.onBackground, scheme.surface, scheme.onSurface,
            scheme.surfaceVariant, scheme.onSurfaceVariant,
            scheme.surfaceContainerLowest, scheme.surfaceContainerLow, scheme.surfaceContainer,
            scheme.surfaceContainerHigh, scheme.surfaceContainerHighest,
            scheme.outline, scheme.outlineVariant, scheme.scrim,
            scheme.error, scheme.onError, scheme.errorContainer, scheme.onErrorContainer,
        ]
    }

    // ── 契约 1: 边界不崩溃,全角色非 NaN ──

    private func assertSchemeHealthy(_ scheme: WakeUpColorScheme, _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        for color in allColors(scheme) {
            let rgb = CustomSchemeDeriver.rgb(of: color)
            XCTAssertFalse(rgb.r.isNaN || rgb.g.isNaN || rgb.b.isNaN,
                           "\(label): color must not be NaN/undefined", file: file, line: line)
            XCTAssertTrue(rgb.r >= 0 && rgb.r <= 1 && rgb.g >= 0 && rgb.g <= 1 && rgb.b >= 0 && rgb.b <= 1,
                          "\(label): channel out of range", file: file, line: line)
        }
    }

    func testDeriveNeverCrashesOnExtremeSeedColors() {
        let extremeSeeds = ["#000000", "#FFFFFF", "#FF0000", "#00FF00", "#0000FF", "#7C4DFF",
                            "garbage", "", "#FFF", "#12"]
        for seed in extremeSeeds {
            let t = fakeTheme(primary: seed, secondary: seed, tertiary: seed)
            assertSchemeHealthy(CustomSchemeDeriver.derive(theme: t, isDark: false), "light/\(seed)")
            assertSchemeHealthy(CustomSchemeDeriver.derive(theme: t, isDark: true), "dark/\(seed)")
        }
    }

    func testDeriveNeverCrashesOnExtremeSurfaceTendency() {
        let tendencies: [(Double, Double)] = [
            (0.0, 0.0),      // 纯灰无彩
            (360.0, 100.0),  // 超界色相 + 高饱和
            (-40.0, -5.0),   // 负值
        ]
        for (hue, chroma) in tendencies {
            let t = fakeTheme(surfaceHue: hue, surfaceChroma: chroma)
            assertSchemeHealthy(CustomSchemeDeriver.derive(theme: t, isDark: false), "light/hue=\(hue)")
            assertSchemeHealthy(CustomSchemeDeriver.derive(theme: t, isDark: true), "dark/hue=\(hue)")
        }
    }

    // ── 契约 2: error 族照抄模板 ──

    func testErrorFamilyCopiesTemplateExactly() {
        let light = CustomSchemeDeriver.derive(theme: fakeTheme(), isDark: false)
        let dark = CustomSchemeDeriver.derive(theme: fakeTheme(), isDark: true)
        XCTAssertEqual(lightScheme.error, light.error)
        XCTAssertEqual(lightScheme.onError, light.onError)
        XCTAssertEqual(lightScheme.errorContainer, light.errorContainer)
        XCTAssertEqual(lightScheme.onErrorContainer, light.onErrorContainer)
        XCTAssertEqual(darkScheme.error, dark.error)
        XCTAssertEqual(darkScheme.onError, dark.onError)
        XCTAssertEqual(darkScheme.errorContainer, dark.errorContainer)
        XCTAssertEqual(darkScheme.onErrorContainer, dark.onErrorContainer)
    }

    func testScrimCopiesTemplateExactly() {
        XCTAssertEqual(lightScheme.scrim, CustomSchemeDeriver.derive(theme: fakeTheme(), isDark: false).scrim)
        XCTAssertEqual(darkScheme.scrim, CustomSchemeDeriver.derive(theme: fakeTheme(), isDark: true).scrim)
    }

    // ── 契约 3: 深浅两套 primaryContainer 明度关系 ──

    func testDarkPrimaryContainerIsDarkerThanLight() {
        let light = CustomSchemeDeriver.derive(theme: fakeTheme(), isDark: false)
        let dark = CustomSchemeDeriver.derive(theme: fakeTheme(), isDark: true)
        XCTAssertLessThan(CustomSchemeDeriver.luminance(dark.primaryContainer),
                          CustomSchemeDeriver.luminance(light.primaryContainer),
                          "dark primaryContainer must be darker than light")
        XCTAssertLessThan(CustomSchemeDeriver.luminance(dark.surface),
                          CustomSchemeDeriver.luminance(light.surface),
                          "dark surface must be darker than light")
    }

    // ── 契约 4: primary 色相跟随种子 ──

    func testPrimaryHueFollowsSeedHue() {
        // 红种子 → light primary 应仍是红色系(色相 ≈ 0°)
        let redPrimary = CustomSchemeDeriver.derive(theme: fakeTheme(primary: "#E53935"), isDark: false).primary
        let hue = CustomSchemeDeriver.hueOf(redPrimary) ?? 0
        XCTAssertTrue(hue < 30 || hue > 330, "red seed should stay red-ish, got hue=\(hue)")

        // 绿种子 → 色相应接近 120°
        let greenPrimary = CustomSchemeDeriver.derive(theme: fakeTheme(primary: "#43A047"), isDark: false).primary
        let gHue = CustomSchemeDeriver.hueOf(greenPrimary) ?? 0
        XCTAssertTrue((90...150).contains(gHue), "green seed should stay green-ish, got hue=\(gHue)")
    }

    // ── 契约 5: on 色按派生底色亮度自适应 ──

    func testOnPrimaryContrastsWithDerivedPrimary() {
        // 明度结构照抄模板(设计定稿):light primary 是深底 → 白字;dark primary 是浅底 → 深字。
        let light = CustomSchemeDeriver.derive(theme: fakeTheme(), isDark: false)
        XCTAssertLessThan(CustomSchemeDeriver.luminance(light.primary), 0.5, "light primary must be a dark ground")
        XCTAssertGreaterThan(CustomSchemeDeriver.luminance(light.onPrimary), 0.5, "…so onPrimary must be light")

        let dark = CustomSchemeDeriver.derive(theme: fakeTheme(), isDark: true)
        XCTAssertGreaterThan(CustomSchemeDeriver.luminance(dark.primary), 0.5, "dark primary must be a light ground")
        XCTAssertLessThan(CustomSchemeDeriver.luminance(dark.onPrimary), 0.5, "…so onPrimary must be dark")
    }

    func testAchromaticSeedDerivesTemplateLuminanceStructure() {
        // 设计契约:种子只贡献色相,明度/饱和度结构照抄模板 —
        // 黑/白种子(S=0)色相回退模板相,派生 primary 明度应与模板 primary 明度一致
        let forWhite = CustomSchemeDeriver.derive(theme: fakeTheme(primary: "#FFFFFF"), isDark: false)
        let forBlack = CustomSchemeDeriver.derive(theme: fakeTheme(primary: "#000000"), isDark: false)
        let tmplLum = CustomSchemeDeriver.luminance(lightScheme.primary)
        XCTAssertLessThan(abs(CustomSchemeDeriver.luminance(forWhite.primary) - tmplLum), 0.2)
        XCTAssertLessThan(abs(CustomSchemeDeriver.luminance(forBlack.primary) - tmplLum), 0.2)
    }

    func testSurfaceFamilyUsesSurfaceTendencyNotPrimarySeed() {
        // 表面族色相应取 surfaceHue,不取 primary 种子色相
        let t = fakeTheme(primary: "#E53935", surfaceHue: 120.0, surfaceChroma: 10.0)
        let surface = CustomSchemeDeriver.derive(theme: t, isDark: false).surface
        // 中低 chroma 下色相检测可能偏移,给宽容差;关键是表面不该是红色系
        let h = CustomSchemeDeriver.hueOf(surface) ?? 0
        XCTAssertFalse(h < 30 || h > 330, "surface must not inherit red primary hue, got hue=\(h)")
    }

    func testBothModesShareSeedThemeButDifferInBrightness() {
        let light = CustomSchemeDeriver.derive(theme: fakeTheme(), isDark: false)
        let dark = CustomSchemeDeriver.derive(theme: fakeTheme(), isDark: true)
        XCTAssertNotEqual(rgbComponents(light.primary), rgbComponents(dark.primary),
                          "light and dark schemes must differ")
        XCTAssertLessThan(CustomSchemeDeriver.luminance(dark.background), 0.5)
        XCTAssertGreaterThan(CustomSchemeDeriver.luminance(light.background), 0.5)
    }

    // ── 纯数学工具守卫(Android 由上述契约间接覆盖,iOS 直接锁死)──

    func testNormalizeHueConvergesEveryInput() {
        XCTAssertEqual(0, CustomSchemeDeriver.normalizeHue(.nan))
        XCTAssertEqual(0, CustomSchemeDeriver.normalizeHue(.infinity))
        XCTAssertEqual(0, CustomSchemeDeriver.normalizeHue(0))
        XCTAssertEqual(0, CustomSchemeDeriver.normalizeHue(360))
        XCTAssertEqual(90, CustomSchemeDeriver.normalizeHue(450), accuracy: 0.0001)
        XCTAssertEqual(270, CustomSchemeDeriver.normalizeHue(-90), accuracy: 0.0001)
        XCTAssertEqual(320, CustomSchemeDeriver.normalizeHue(-40), accuracy: 0.0001)
    }

    func testParseHexTolerance() {
        XCTAssertNotNil(CustomSchemeDeriver.parseHex("#AABBCC"))
        XCTAssertNotNil(CustomSchemeDeriver.parseHex("#FFAABBCC")) // AARRGGBB 也吃
        XCTAssertNotNil(CustomSchemeDeriver.parseHex(" #aabbcc "))
        // 形状不对一律返回 nil(不抛、不猜)
        for bad in ["garbage", "", "#FFF", "#12", "AABBCC", "#GGHHII", "#AABBCCDDEE"] {
            XCTAssertNil(CustomSchemeDeriver.parseHex(bad), "\(bad) must not parse")
        }
    }

    func testRgbHsvRoundTripKeepsHueAndValue() {
        // 色相旋转承诺的数学底座:HSV → RGB → HSV 应回到同一 (h, s, v)
        for h in stride(from: 0.0, through: 359.0, by: 30.0) {
            let hf = Float(h)
            let rgb = CustomSchemeDeriver.hsvToRgb(h: hf, s: 0.6, v: 0.7)
            let back = CustomSchemeDeriver.rgbToHsv(r: rgb.r, g: rgb.g, b: rgb.b)
            XCTAssertEqual(hf, back.h, accuracy: 1.0, "hue must survive the round trip at \(h)°")
            XCTAssertEqual(0.6, back.s, accuracy: 0.01)
            XCTAssertEqual(0.7, back.v, accuracy: 0.01)
        }
    }

    func testNeutralRgbHasNoHue() {
        XCTAssertNil(CustomSchemeDeriver.hueOf(r: 0.5, g: 0.5, b: 0.5))
        XCTAssertEqual(0, CustomSchemeDeriver.rgbToHsv(r: 1, g: 1, b: 1).s, accuracy: 0.0001)
    }

    func testAdaptOnKeepsTextContrastOnEveryDerivedGround() {
        // adaptOn 阈值(0.299r+0.587g+0.114b < 0.5 → 白字,否则黑字)在真实派生结果上的效果:
        // 每一对 (底, 字) 都必须拉开亮度差,否则文字不可读。
        let pairs: [(KeyPath<WakeUpColorScheme, Color>, KeyPath<WakeUpColorScheme, Color>)] = [
            (\WakeUpColorScheme.primary, \WakeUpColorScheme.onPrimary),
            (\WakeUpColorScheme.primaryContainer, \WakeUpColorScheme.onPrimaryContainer),
            (\WakeUpColorScheme.secondary, \WakeUpColorScheme.onSecondary),
            (\WakeUpColorScheme.secondaryContainer, \WakeUpColorScheme.onSecondaryContainer),
            (\WakeUpColorScheme.tertiary, \WakeUpColorScheme.onTertiary),
            (\WakeUpColorScheme.tertiaryContainer, \WakeUpColorScheme.onTertiaryContainer),
            (\WakeUpColorScheme.background, \WakeUpColorScheme.onBackground),
            (\WakeUpColorScheme.surface, \WakeUpColorScheme.onSurface),
            (\WakeUpColorScheme.surfaceVariant, \WakeUpColorScheme.onSurfaceVariant),
            (\WakeUpColorScheme.error, \WakeUpColorScheme.onError),
            (\WakeUpColorScheme.errorContainer, \WakeUpColorScheme.onErrorContainer),
        ]
        for seed in ["#7C4DFF", "#E53935", "#43A047", "#FFFFFF", "#000000"] {
            for isDark in [false, true] {
                let scheme = CustomSchemeDeriver.derive(theme: fakeTheme(primary: seed), isDark: isDark)
                for (baseKey, onKey) in pairs {
                    let base = CustomSchemeDeriver.luminance(scheme[keyPath: baseKey])
                    let on = CustomSchemeDeriver.luminance(scheme[keyPath: onKey])
                    XCTAssertGreaterThan(abs(base - on), 0.3,
                                         "seed=\(seed) dark=\(isDark): 底色与文字色亮度差不足(\(base) vs \(on))")
                }
            }
        }
    }
}

// MARK: - custom:<id> 解析接线(iOS 侧守卫)

final class CustomThemeResolutionTests: XCTestCase {

    func testCustomKeyPrefix() {
        XCTAssertEqual("custom:", ThemePresets.CUSTOM_KEY_PREFIX)
        XCTAssertTrue(("custom:" + "abc").hasPrefix(ThemePresets.CUSTOM_KEY_PREFIX))
        XCTAssertFalse("default".hasPrefix(ThemePresets.CUSTOM_KEY_PREFIX))
    }

    func testProviderFallbackSeedIsDefaultLavender() {
        // ← Android Theme.kt 就地构造的回落种子(#6750A4/#625B71/#7D5260, 265/8)
        let seed = SleepyThemeProvider.defaultSeedTheme
        XCTAssertEqual("#6750A4", seed.primary)
        XCTAssertEqual("#625B71", seed.secondary)
        XCTAssertEqual("#7D5260", seed.tertiary)
        XCTAssertEqual(265.0, seed.surfaceHue, accuracy: 0.001)
        XCTAssertEqual(8.0, seed.surfaceChroma, accuracy: 0.001)
    }

    func testWidgetCustomBranchFallsBackToDefaultPreset() {
        // ← WidgetContent.kt resolveSchemePublic:custom 读不到 → ThemePresets.byKey(KEY_DEFAULT)
        // (注意与 App 侧不同:App 侧回落 derive(defaultSeedTheme),widget 侧回落预设方案)
        let preset = ThemePresets.byKey(ThemePresets.KEY_DEFAULT)
        let light = resolveWidgetScheme(themeKey: "custom:definitely-not-an-id", isDark: false)
        XCTAssertEqual(rgbComponents(preset.light.surface), rgbComponents(light.surface))
        XCTAssertEqual(rgbComponents(preset.light.primary), rgbComponents(light.primary))

        let dark = resolveWidgetScheme(themeKey: "custom:definitely-not-an-id", isDark: true)
        XCTAssertEqual(rgbComponents(preset.dark.surface), rgbComponents(dark.surface))
    }

    func testWidgetPresetAndSystemBranchesUnchanged() {
        let preset = ThemePresets.byKey("ocean")
        let ocean = resolveWidgetScheme(themeKey: "ocean", isDark: false)
        XCTAssertEqual(rgbComponents(preset.light.primary), rgbComponents(ocean.primary))

        let system = resolveWidgetScheme(themeKey: ThemePresets.KEY_SYSTEM, isDark: true)
        let dynamic = SleepyThemeProvider.dynamicSystemScheme(dark: true)
        XCTAssertEqual(rgbComponents(dynamic.surface), rgbComponents(system.surface))
    }
}

// MARK: - 外观页网格顺序不变量(d87eade3 + c1c166f9)

final class CustomThemeGridTests: XCTestCase {

    private func theme(_ id: String) -> CustomTheme {
        CustomTheme(id: id, name: "T-" + id, primary: "#7C4DFF", secondary: "#546E7A", tertiary: "#EF6C00",
                    surfaceHue: 265.0, surfaceChroma: 8.0, createdAt: 0)
    }

    /// 加号永远在整网格末尾 —— 与自定义主题数量无关(不变量,不是 t=0 快照)
    func testPlusEntryIsAlwaysLast() {
        for count in [0, 1, 2, 5, 13] {
            let customs = (0..<count).map { theme("id-\($0 + 1)") }
            let cells = AppearanceScreen.gridCells(presets: ThemePresets.all, customs: customs)
            XCTAssertEqual(ThemePresets.all.count + count + 1, cells.count, "count=\(count)")
            guard case .newTheme? = cells.last else {
                XCTFail("count=\(count): 加号必须在末尾,实际末尾是 \(String(describing: cells.last))")
                continue
            }
        }
    }

    /// 顺序 = 预设(按 ThemePresets.all 原序)→ 自定义(按存储原序)→ 加号
    func testOrderIsPresetsThenCustomsThenPlus() {
        let presets = ThemePresets.all
        let customs = [theme("a"), theme("b"), theme("c")]
        let cells = AppearanceScreen.gridCells(presets: presets, customs: customs)
        XCTAssertEqual(
            presets.map { "preset:" + $0.key } + ["custom:a", "custom:b", "custom:c"] + ["new-theme"],
            cells.map { $0.id }
        )
    }

    /// 加号有且只有一个;没有自定义主题时也不会冒出空的自定义位
    func testExactlyOnePlusAndNoPhantomCustomCells() {
        for count in [0, 4] {
            let customs = (0..<count).map { theme("x-\($0)") }
            let cells = AppearanceScreen.gridCells(presets: ThemePresets.all, customs: customs)
            let plusCount = cells.filter { if case .newTheme = $0 { return true } else { return false } }.count
            let customCount = cells.filter { if case .custom = $0 { return true } else { return false } }.count
            XCTAssertEqual(1, plusCount, "count=\(count)")
            XCTAssertEqual(count, customCount, "count=\(count)")
        }
    }
}
