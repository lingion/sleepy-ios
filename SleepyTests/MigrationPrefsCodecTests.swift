// MigrationPrefsCodecTests.swift — Android MigrationPrefsCodec.kt 契约测试
// (android_test=null — 本文件按 fix_hint 补契约锁, 参照 MigrationDatabaseCodecTests 风格)
//
// 锁定 v1.0.61 对齐修复的行为:
//   1. decode 向前兼容 — 缺省字段回落构造默认值 (Kotlin ignoreUnknownKeys +
//      encodeDefaults + 默认参数语义)
//   2. INT/LONG 按存储宽度往返 — Android→iOS→Android 类型不丢
//   3. Bool 不被误分为 INT (__NSCFBoolean objCType 'c' 陷阱)
//   4. collect 只含本域实际持久化键 — 注册域默认值不导出 (== Android prefs.all)
//   5. apply(merge:false) 只清本域 — 绝不碰标准域/其他 suite
//   6. STRING_SET 以 [String] 形态往返, 不写 Set/NSSet (运行时 abort 陷阱)
//   7. encode→decode 全类型信封往返

import XCTest
@testable import Sleepy

final class MigrationPrefsCodecTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "MigrationPrefsCodecTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - 1. decode 向前兼容 (缺省字段回落默认值)

    func testDecodeEmptyObjectYieldsEmptySnapshot() throws {
        // Kotlin: `{}` → PrefsSnapshot(files = emptyMap())
        let snap = try MigrationPrefsCodec.decode("{}")
        XCTAssertTrue(snap.files.isEmpty)
    }

    func testDecodeMissingEntriesDefaultsToEmpty() throws {
        // Kotlin: files 里的 {} → PrefsFileSnapshot(entries = emptyMap())
        let snap = try MigrationPrefsCodec.decode(#"{"files":{"sleepy_prefs":{}}}"#)
        XCTAssertEqual(snap.files["sleepy_prefs"]?.entries.count, 0)
    }

    func testDecodePrefValueMissingOptionalFieldsDefaults() throws {
        // Kotlin: 只有 type 的 PrefValue → 其余字段回落默认 (bool=false, number=0,
        // float=0f, string="", stringSet=[])
        let snap = try MigrationPrefsCodec.decode(
            #"{"files":{"f":{"entries":{"k":{"type":"BOOL"}}}}}"#)
        let v = try XCTUnwrap(snap.files["f"]?.entries["k"])
        XCTAssertEqual(v.type, .BOOL)
        XCTAssertFalse(v.bool)
        XCTAssertEqual(v.number, 0)
        XCTAssertEqual(v.float, 0)
        XCTAssertEqual(v.string, "")
        XCTAssertTrue(v.stringSet.isEmpty)
    }

    func testDecodeIgnoresUnknownKeys() throws {
        // Kotlin ignoreUnknownKeys=true 只跳过「类对象内」未声明的键:
        // PrefValue 里的 futureField、PrefsSnapshot 顶层的 extraTop 都被两端忽略。
        let snap = try MigrationPrefsCodec.decode(
            #"{"files":{"f":{"entries":{"k":{"type":"STRING","string":"ok","futureField":42}}}},"extraTop":42}"#)
        XCTAssertEqual(snap.files["f"]?.entries["k"]?.string, "ok")
    }

    func testDecodeRejectsNonObjectEntryInFilesMap() {
        // 两端一致 (真值 = MigrationPrefsCodec.kt:36): ignoreUnknownKeys 不适用于
        // map 的值类型 — files.extraTop=1 在 Kotlin 端让 MapSerializer 抛
        // SerializationException (值必须是 PrefsFileSnapshot 对象), iOS 同样抛。
        // 坏包必须在触碰本机数据之前被拒 (MigrationExecutor.kt:101
        // "导入先完整读包校验, 坏包在写任何本机数据前被拒绝"), 不许静默跳过。
        XCTAssertThrowsError(try MigrationPrefsCodec.decode(
            #"{"files":{"f":{"entries":{"k":{"type":"STRING","string":"ok"}}},"extraTop":1}}"#))
    }

    func testDecodeMissingTypeStillThrows() {
        // Kotlin PrefValue.type 无默认值 → 缺 type 是协议错误, 不许静默回落
        XCTAssertThrowsError(try MigrationPrefsCodec.decode(
            #"{"files":{"f":{"entries":{"k":{"bool":true}}}}}"#))
    }

    // MARK: - 2/3. 类型判别与往返

    func testCollectBoolNotMisclassifiedAsInt() {
        // 回归锁: 旧实现 case "B" 永不命中 (__NSCFBoolean objCType='c'),
        // true/false 会被误分为 INT。
        defaults.set(true, forKey: "flag_on")
        defaults.set(false, forKey: "flag_off")
        let snap = MigrationPrefsCodec.collect(defaults, suiteName: suiteName)
        XCTAssertEqual(snap.entries["flag_on"]?.type, .BOOL)
        XCTAssertEqual(snap.entries["flag_on"]?.bool, true)
        XCTAssertEqual(snap.entries["flag_off"]?.type, .BOOL)
        XCTAssertEqual(snap.entries["flag_off"]?.bool, false)
    }

    func testCollectIntWidthIsINTLongWidthIsLONG() {
        // Android: putInt → INT, putLong → LONG, 与数值范围无关。
        // iOS: Int32/更窄落 ≤32 位 → INT; Int/Int64 落 'q' → LONG。
        // 关键回归: 值域内的 Long (小数值 Int64) 旧实现按范围误标 INT。
        defaults.set(NSNumber(value: Int32(7)), forKey: "narrow")
        defaults.set(NSNumber(value: Int64(7)), forKey: "small_long")  // 值小但是 LONG
        defaults.set(42, forKey: "swift_int")                           // Swift Int → LONG
        defaults.set(Int64(9_000_000_000), forKey: "big_long")
        let snap = MigrationPrefsCodec.collect(defaults, suiteName: suiteName)
        XCTAssertEqual(snap.entries["narrow"]?.type, .INT)
        XCTAssertEqual(snap.entries["small_long"]?.type, .LONG,
                       "值域内的 64 位存储必须标 LONG, 否则回灌 Android 后 getLong 抛 ClassCastException")
        XCTAssertEqual(snap.entries["swift_int"]?.type, .LONG)
        XCTAssertEqual(snap.entries["big_long"]?.type, .LONG)
        XCTAssertEqual(snap.entries["big_long"]?.number, 9_000_000_000)
    }

    func testApplyIntWritesNarrowWidthApplyLongWritesWideWidth() {
        // 信封还原: INT → ≤32 位存储(重导出仍 INT), LONG → 64 位(重导出仍 LONG)。
        let snapshot = MigrationPrefsCodec.PrefsFileSnapshot(entries: [
            "i": MigrationPrefsCodec.PrefValue(type: .INT, number: 5),
            "l": MigrationPrefsCodec.PrefValue(type: .LONG, number: 5),   // 小值 LONG
            "b": MigrationPrefsCodec.PrefValue(type: .BOOL, bool: true),
            "s": MigrationPrefsCodec.PrefValue(type: .STRING, string: "hi"),
            "set": MigrationPrefsCodec.PrefValue(type: .STRING_SET, stringSet: ["b", "a"]),
        ])
        MigrationPrefsCodec.apply(defaults, snapshot, merge: true, suiteName: suiteName)
        let again = MigrationPrefsCodec.collect(defaults, suiteName: suiteName)
        XCTAssertEqual(again.entries["i"]?.type, .INT)
        XCTAssertEqual(again.entries["l"]?.type, .LONG, "LONG 写回后重导出仍 LONG — Android→iOS→Android 类型保持")
        XCTAssertEqual(again.entries["b"]?.type, .BOOL)
        XCTAssertEqual(again.entries["s"]?.string, "hi")
        XCTAssertEqual(again.entries["set"]?.type, .STRING_SET)
        XCTAssertEqual(again.entries["set"]?.stringSet, ["a", "b"], "stringSet 排序与 Android sorted() 一致")
        // 常规读取 API 不受精确宽度影响
        XCTAssertEqual(defaults.integer(forKey: "l"), 5)
        XCTAssertEqual(defaults.string(forKey: "s"), "hi")
    }

    // MARK: - 4. collect 源集合 = 本域实际持久化键

    func testCollectExcludesRegisteredDefaults() {
        // 回归锁: 旧实现用 dictionaryRepresentation() — 注册域默认值被当成
        // 持久化键导出, Android prefs.all 不会包含这些键。
        defaults.register(defaults: ["__reg_only__": 9])
        defaults.set("persisted", forKey: "__real__")
        let snap = MigrationPrefsCodec.collect(defaults, suiteName: suiteName)
        XCTAssertNil(snap.entries["__reg_only__"],
                     "仅注册未持久化的键不得进快照 (Android prefs.all 语义)")
        XCTAssertEqual(snap.entries["__real__"]?.string, "persisted")
    }

    func testCollectKeepsAppKeysWithAppleishNames() {
        // Android 契约: 未知键原样保留, 不按键名过滤。
        // 旧实现 hasPrefix("NS")/("Apple") 会丢键; CFPreferencesCopyKeyList 路径
        // 不存在该问题。
        defaults.set("x", forKey: "AppleStyleMirror")
        defaults.set("y", forKey: "NSFooCustom")
        let snap = MigrationPrefsCodec.collect(defaults, suiteName: suiteName)
        XCTAssertEqual(snap.entries["AppleStyleMirror"]?.string, "x")
        XCTAssertEqual(snap.entries["NSFooCustom"]?.string, "y")
    }

    // MARK: - 5/6. apply(merge:false) 只清本域

    func testApplyNonMergeClearsOnlyTargetSuite() {
        // 回归锁: 旧实现对 suite 实例 removePersistentDomain(bundleId) —
        // 清错域 (目标 suite 漏清 + 标准域误伤)。
        let otherSuiteName = suiteName + ".other"
        let other = UserDefaults(suiteName: otherSuiteName)!
        defer { other.removePersistentDomain(forName: otherSuiteName) }

        defaults.set("stale", forKey: "gone")
        other.set("keep", forKey: "other_key")

        let replacement = MigrationPrefsCodec.PrefsFileSnapshot(entries: [
            "fresh": MigrationPrefsCodec.PrefValue(type: .STRING, string: "new")
        ])
        MigrationPrefsCodec.apply(defaults, replacement, merge: false, suiteName: suiteName)

        let reread = MigrationPrefsCodec.collect(defaults, suiteName: suiteName)
        XCTAssertNil(reread.entries["gone"], "整文件替换必须清掉本域旧键")
        XCTAssertEqual(reread.entries["fresh"]?.string, "new")
        XCTAssertEqual(other.string(forKey: "other_key"), "keep",
                       "非合并导入绝不清空其他 suite")
    }

    func testApplyMergeKeepsOtherKeys() {
        defaults.set("keepme", forKey: "a")
        let patch = MigrationPrefsCodec.PrefsFileSnapshot(entries: [
            "a": MigrationPrefsCodec.PrefValue(type: .STRING, string: "overwritten"),
            "b": MigrationPrefsCodec.PrefValue(type: .INT, number: 3),
        ])
        MigrationPrefsCodec.apply(defaults, patch, merge: true, suiteName: suiteName)
        let snap = MigrationPrefsCodec.collect(defaults, suiteName: suiteName)
        XCTAssertEqual(snap.entries["a"]?.string, "overwritten")
        XCTAssertEqual(snap.entries["b"]?.type, .INT)
    }

    // MARK: - 6b. STRING_SET 落盘形态

    func testStringSetPersistsAsArrayAndReadsBack() {
        // 本运行时 UserDefaults 写 Set/NSSet 直接 abort — codec 必须写 [String]。
        let snapshot = MigrationPrefsCodec.PrefsFileSnapshot(entries: [
            "courses": MigrationPrefsCodec.PrefValue(type: .STRING_SET, stringSet: ["语文", "数学"])
        ])
        MigrationPrefsCodec.apply(defaults, snapshot, merge: true, suiteName: suiteName)
        let raw = defaults.object(forKey: "courses")
        XCTAssertTrue(raw is [String], "STRING_SET 必须以数组形态持久化, 实际 \(type(of: raw as Any))")
        let snap = MigrationPrefsCodec.collect(defaults, suiteName: suiteName)
        XCTAssertEqual(snap.entries["courses"]?.stringSet, ["数学", "语文"].sorted())
    }

    // MARK: - 7. encode→decode 往返

    func testEncodeDecodeRoundTripAllTypes() throws {
        let original = MigrationPrefsCodec.PrefsSnapshot(files: [
            "sleepy_prefs": MigrationPrefsCodec.PrefsFileSnapshot(entries: [
                "b": .init(type: .BOOL, bool: true),
                "i": .init(type: .INT, number: -12),
                "l": .init(type: .LONG, number: 9_000_000_000),
                "f": .init(type: .FLOAT, float: 1.25),
                "s": .init(type: .STRING, string: "高数 @楼3"),
                "ss": .init(type: .STRING_SET, stringSet: ["x", "y"]),
            ]),
            "widget_bindings": MigrationPrefsCodec.PrefsFileSnapshot(entries: [:]),
        ])
        let text = try MigrationPrefsCodec.encode(original)
        let decoded = try MigrationPrefsCodec.decode(text)
        XCTAssertEqual(decoded.files.count, 2)
        let e = decoded.files["sleepy_prefs"]!.entries
        XCTAssertEqual(e["b"], .init(type: .BOOL, bool: true))
        XCTAssertEqual(e["i"]?.type, .INT)
        XCTAssertEqual(e["i"]?.number, -12)
        XCTAssertEqual(e["l"]?.number, 9_000_000_000)
        XCTAssertEqual(e["f"]?.float, 1.25, "0.125/1.25 在 binary32 与 JSON 往返中精确可表示")
        XCTAssertEqual(e["s"]?.string, "高数 @楼3")
        XCTAssertEqual(e["ss"]?.stringSet, ["x", "y"])
        XCTAssertEqual(decoded.files["widget_bindings"]?.entries.count, 0)
    }

    func testEncodeFieldNamesMatchAndroidProtocol() throws {
        // kotlinx 字段名: type/bool/number/float/string/stringSet; 枚举值大写。
        // encodeDefaults=true → 全字段都出现。
        let snapshot = MigrationPrefsCodec.PrefsSnapshot(files: [
            "f": MigrationPrefsCodec.PrefsFileSnapshot(entries: [
                "k": MigrationPrefsCodec.PrefValue(type: .STRING_SET, stringSet: ["a"])
            ])
        ])
        let json = try MigrationPrefsCodec.encode(snapshot)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let files = try XCTUnwrap(obj["files"] as? [String: Any])
        let entries = try XCTUnwrap((files["f"] as? [String: Any])?["entries"] as? [String: Any])
        let k = try XCTUnwrap(entries["k"] as? [String: Any])
        XCTAssertEqual(k["type"] as? String, "STRING_SET")
        XCTAssertEqual(k["stringSet"] as? [String], ["a"])
        // encodeDefaults: 未用字段也在
        XCTAssertEqual(k["bool"] as? Bool, false)
        XCTAssertEqual(k["number"] as? Int64, 0)
    }

    // MARK: - unknown 类型不阻断 (Android else -> null)

    func testCollectSkipsUnsupportedValueTypes() {
        defaults.set(Date(), forKey: "a_date")   // 非 plist 原生偏好类型
        defaults.set("ok", forKey: "a_string")
        let snap = MigrationPrefsCodec.collect(defaults, suiteName: suiteName)
        XCTAssertNil(snap.entries["a_date"], "未知值类型跳过不阻断导出")
        XCTAssertEqual(snap.entries["a_string"]?.type, .STRING)
    }
}
