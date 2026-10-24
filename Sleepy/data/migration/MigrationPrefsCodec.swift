// MigrationPrefsCodec.swift — ← data/migration/MigrationPrefsCodec.kt
// 偏好/小部件/持久态 三模块共用的 codec。值带类型信封,导入端按信封还原,不靠运行时类型猜测。
//
// iOS 适配:
//   - Android SharedPreferences → UserDefaults (同 key-value 语义,UserDefaults 全是单 suite)
//   - 文件名 → suiteName 映射: iOS 用 UserDefaults(suiteName: <file>) 模拟多文件;
//     共享主 prefs("sleepy_prefs") 走 UserDefaults.standard 保持向后兼容
//     (UserDefaults.standard 持久化的 key 实际就在 app group-less 默认 suite 中)。
//   - 与 Android editor.clear() 等价 (v1.0.61 对齐修复): 只清"该实例所属域"实际
//     持久化的键。绝不对 suite 实例调 removePersistentDomain(bundleId) —
//     suite 的域按 suiteName 命名, 按 bundleId 清会误伤标准域、漏清目标域。
//   - collect/清空 的"本域实际持久化键"通过 CFPreferencesCopyKeyList 枚举
//     (dictionaryRepresentation() 会混入注册域默认值与全局域系统键, 不能直接用)。
//   - INT/LONG 判别按存储宽度 (NSNumber.objCType), 与 Android putInt/putLong
//     运行时类型判别一一对应; 写回按信封类型还原对应宽度, Android→iOS→Android
//     往返类型不丢 (旧实现按数值范围判别: 小值 Long 被误标 INT, 回灌 Android 后
//     getLong 抛 ClassCastException / `v is Long` 过滤整类丢键)。
//   - Bool: UserDefaults 落 __NSCFBoolean (objCType 'c'), 必须先按 CFBoolean 判别,
//     旧实现的 case "B" 永不命中 → 布尔被误分为 INT。
//   - STRING_SET: 本运行时 UserDefaults 拒绝 Set/NSSet 直接写入
//     (_CFPrefsValidateValueForKey abort), 故持久化为 [String];
//     读取端兼容 Array 与 Set/NSSet 两种形态。

import Foundation

/// 偏好快照 codec。
/// 与 Android MigrationPrefsCodec.kt 1:1 — JSON 协议必须保持向后兼容。
enum MigrationPrefsCodec {

    /// 值的类型信封 — 未知 type 直接 skip, 不阻断导出。
    enum PrefType: String, Codable {
        case BOOL
        case INT
        case LONG
        case FLOAT
        case STRING
        case STRING_SET
    }

    /// 单个偏好值 — 一次只承载一个字段(type 决定哪个),与 Android JSON 协议一致。
    struct PrefValue: Codable, Equatable {
        var type: PrefType
        var bool: Bool = false
        /// int 与 long 统一走这里 (JS 端 number 精度内, iOS 端 Int64)。
        var number: Int64 = 0
        var float: Float = 0
        var string: String = ""
        var stringSet: [String] = []

        // 兼容 Android JSON 字段名 'number'(JS 端 number 精度内)
    }

    struct PrefsFileSnapshot: Codable, Equatable {
        var entries: [String: PrefValue] = [:]
    }

    struct PrefsSnapshot: Codable, Equatable {
        var files: [String: PrefsFileSnapshot] = [:]
    }

    // MARK: - 手写解码 (向前兼容: 缺省字段回落构造默认值)

    /// Kotlin 端 `Json { ignoreUnknownKeys = true; encodeDefaults = true }` 且每个
    /// data class 字段都带默认值 → 缺键回落默认。Swift 合成 Codable 对非 Optional
    /// 缺键抛 keyNotFound (结构体默认值不参与解码), 故手写 init(from:): 除 type
    /// (Kotlin 无默认值, 缺键必须报错) 外全部 `decodeIfPresent(...) ?? default`。
    /// 未知键 JSONDecoder 天然忽略, 与 ignoreUnknownKeys=true 等价。
    /// 注: 手写 init(from:) 的 extension 一律放文件级 — 嵌套在 enum 内非法,
    /// 写进 struct 主体则会抑制编译器合成 (见文件底部 extension)。

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()
    private static let decoder = JSONDecoder()

    static func encode(_ snapshot: PrefsSnapshot) throws -> String {
        let data = try encoder.encode(snapshot)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    static func decode(_ text: String) throws -> PrefsSnapshot {
        guard let data = text.data(using: .utf8) else {
            throw MigrationPackageException(message: "prefs snapshot not utf-8")
        }
        return try decoder.decode(PrefsSnapshot.self, from: data)
    }

    // MARK: - 收集

    /// 从一个 UserDefaults 实例收集全量键值(类型按运行时实际值判别)。
    ///
    /// Android `prefs.all` 只含"真正写进该文件"的键, 未知键名原样保留。iOS 的
    /// dictionaryRepresentation() 会把注册域默认值与全局域系统键一并合并进来,
    /// 直接用会导出 Android 不会导出的条目 — 键清单一律取自 persistedKeys
    /// (本域实际键, == prefs.all), 键名不做任何过滤, 与 Android "未知键原样保留"
    /// 契约一致。
    ///
    /// - Parameter suiteName: 该实例对应的 suite 名 / 文件名映射;
    ///   不确定时可省 nil (standard 实例与任意不透明实例仍走精确/对照路径)。
    static func collect(_ defaults: UserDefaults, suiteName: String? = nil) -> PrefsFileSnapshot {
        var entries: [String: PrefValue] = [:]
        for key in persistedKeys(in: defaults, suiteName: suiteName) {
            guard let raw = defaults.object(forKey: key) else { continue }
            guard let value = makePrefValue(raw) else { continue }
            entries[key] = value
        }
        return PrefsFileSnapshot(entries: entries)
    }

    /// 该域实际持久化的键清单(绝不含全局/注册域混入键)。三层路径:
    /// 1. 显式 suiteName 且该域有键清单 → CFPreferencesCopyKeyList 精确域清单;
    /// 2. standard 实例 → app 当前域 (kCFPreferencesCurrentApplication) 精确清单;
    /// 3. 兜底(不透明实例, 如注入 store 的 "prefix.fileName" 域): 对照域差分 —
    ///    对照 = 进程级私有空 suite 的字典, 它暴露 suite 实例经弱合并带出的全部
    ///    全局域键族(实测 iPhone 14 模拟器空 suite 实例混入 60+ 个 com.apple.*/
    ///    NS*/AK*/KB_*/Country/646F6E7A_* 键); 实例字典与对照逐键值比对, 值不同
    ///    (或对照没有) 的才是实例本域真正写过的键。
    ///    ⚠ 禁止退回 "dictionaryRepresentation + 系统前缀过滤": 前缀过滤杀不尽
    ///    全局键族, 空 suite 会被判非空 → 空文件误进包 → OVERWRITE 导入误清接收
    ///    端包外文件、prefFiles/prefKeys 计数虚高 (v1.0.61 对齐实测翻车根因)。
    ///    对照也不用 standard: standard 混有 app 标准域业务键, 会把与本域同名同值
    ///    的真实键误当全局掩掉。
    private static func persistedKeys(in defaults: UserDefaults, suiteName: String?) -> Set<String> {
        if let suiteName = suiteName,
           let list = keyList(suiteName as CFString) {
            return list
        }
        if defaults === UserDefaults.standard,
           let list = keyList(kCFPreferencesCurrentApplication) {
            return list
        }
        return ownKeysByControlDiff(in: defaults)
    }

    /// 进程级私有空 suite (只读对照, 永不写入): 其字典 == 全局域经弱合并带出的
    /// 键族集合。对照与目标同域时差分为空集 — 保守正确 (目标即 standard 的情形
    /// 已由路径 2 优先拦截)。
    private static let emptyControlDomain =
        UserDefaults(suiteName: "com.lingion.sleepy.MigrationPrefsEmptyControl")!

    /// 对照域差分: 见 persistedKeys 第 3 层说明。
    private static func ownKeysByControlDiff(in defaults: UserDefaults) -> Set<String> {
        let control = emptyControlDomain.dictionaryRepresentation()
        var own: Set<String> = []
        for (key, value) in defaults.dictionaryRepresentation() {
            if let controlValue = control[key],
               (controlValue as AnyObject).isEqual(value as AnyObject) {
                continue
            }
            own.insert(key)
        }
        return own
    }

    private static func keyList(_ domain: CFString) -> Set<String>? {
        guard let list = CFPreferencesCopyKeyList(
            domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost
        ) as? [String] else { return nil }
        return Set(list)
    }

    private static func makePrefValue(_ raw: Any) -> PrefValue? {
        // UserDefaults 中 Bool 与数字都以 NSNumber 持有 — Swift/OC 的布尔实际是
        // __NSCFBoolean (objCType 'c'), 必须先用 CFBooleanGetTypeID 判别,
        // 否则布尔会被下面的整型分支误分为 INT (Android Boolean → PrefType.BOOL)。
        if let n = raw as? NSNumber {
            if CFGetTypeID(n as CFTypeRef) == CFBooleanGetTypeID() {
                return PrefValue(type: .BOOL, bool: n.boolValue)
            }
            // NSNumber 的 objCType 宽度即"存储类型": Android putInt 对应 ≤32 位
            // ('c','s','i','l' 及无符号), putLong / iOS 原生 Int/Int64 对应 64 位
            // ('q')。按宽度而非数值范围判别, 与 Android 运行时类型判别一致。
            switch String(cString: n.objCType) {
            case "c", "s", "i", "l", "C", "S", "I", "L":
                return PrefValue(type: .INT, number: n.int64Value)
            case "q", "Q":
                return PrefValue(type: .LONG, number: n.int64Value)
            case "f", "d":
                // Android 无 double 型; Double 按 FLOAT 收敛 (两端类型集差异,
                // 与旧行为一致)
                return PrefValue(type: .FLOAT, float: n.floatValue)
            default:
                return nil   // 未来新类型,跳过不阻断 (Android else -> null)
            }
        }
        if let s = raw as? String {
            return PrefValue(type: .STRING, string: s)
        }
        // STRING_SET 读取端兼容多种落盘形态 (本 codec 写入为 [String];
        // 其他代码若曾用 set(Set<String>) 成功落盘则按 Set/NSSet 读回)
        if let set = raw as? Set<String> {
            return PrefValue(type: .STRING_SET, stringSet: set.sorted())
        }
        if let nsSet = raw as? NSSet {
            let strs = nsSet.compactMap { $0 as? String }
            if strs.count == nsSet.count {
                return PrefValue(type: .STRING_SET, stringSet: strs.sorted())
            }
        }
        if let arr = raw as? [String] {
            return PrefValue(type: .STRING_SET, stringSet: arr.sorted())
        }
        if let anyArr = raw as? [Any] {
            // [Any] 但 [String] cast 失败 — 尝试 string 化(谨慎)
            let strs = anyArr.compactMap { $0 as? String }
            if strs.count == anyArr.count {
                return PrefValue(type: .STRING_SET, stringSet: strs.sorted())
            }
        }
        return nil
    }

    // MARK: - 写回

    /// 写回单个 UserDefaults。
    /// - Parameters:
    ///   - merge: true=仅覆盖同名键 (Android editor 逐项 put 语义, 绝不清空);
    ///     false=先清空"本域实际持久化键"再写入, 即 editor.clear() + put... 的
    ///     整文件替换。
    ///   - suiteName: 该实例的域名 (文件名映射; 传文件名即可, standard 主 prefs
    ///     会在 persistedKeys 内自动回落 app 域)。省略时不透明实例走对照域差分
    ///     (见 persistedKeys 第 3 层) — 只删实例本域真写过的键; 与全局域同值的键
    ///     在实例读取上本就不可区分, 删留语义均与 Android 一致。
    ///   清空绝不用 removePersistentDomain(Bundle.main.bundleIdentifier):
    ///   suite 实例的域按 suiteName 命名, 按 bundleId 清会误伤标准域、漏清目标域。
    static func apply(_ defaults: UserDefaults,
                      _ snapshot: PrefsFileSnapshot,
                      merge: Bool,
                      suiteName: String? = nil) {
        if !merge {
            for key in persistedKeys(in: defaults, suiteName: suiteName) {
                defaults.removeObject(forKey: key)
            }
        }
        for (key, value) in snapshot.entries {
            switch value.type {
            case .BOOL:
                defaults.set(value.bool, forKey: key)
            case .INT:
                // 按 32 位宽度落存储 (对齐 Android putInt), 重导出仍判回 INT —
                // Android→iOS→Android 往返类型不丢。越界截断语义与 Kotlin
                // value.number.toInt() 一致。
                let truncated = Int32(bitPattern: UInt32(truncatingIfNeeded: value.number))
                defaults.set(NSNumber(value: truncated), forKey: key)
            case .LONG:
                // 64 位宽度 (对齐 Android putLong); integer/int64 读取端不受影响
                defaults.set(NSNumber(value: value.number), forKey: key)
            case .FLOAT:
                defaults.set(NSNumber(value: value.float), forKey: key)
            case .STRING:
                defaults.set(value.string, forKey: key)
            case .STRING_SET:
                // 本运行时 UserDefaults 直接写 Set/NSSet 会触发
                // _CFPrefsValidateValueForKey abort (非法 plist 类型),
                // 持久化改用 [String]; 读取端 makePrefValue 双形态兼容。
                defaults.set(value.stringSet, forKey: key)
            }
        }
    }
}

// MARK: - 手写解码 (文件级 extension, 补齐上方 PrefValue/PrefsFileSnapshot/PrefsSnapshot 的向前兼容)

extension MigrationPrefsCodec.PrefValue {
    enum CodingKeys: String, CodingKey {
        case type, bool, number, float, string, stringSet
    }
    init(from decoder: Decoder) throws {
        let k = try decoder.container(keyedBy: CodingKeys.self)
        type = try k.decode(MigrationPrefsCodec.PrefType.self, forKey: .type)
        bool = try k.decodeIfPresent(Bool.self, forKey: .bool) ?? false
        number = try k.decodeIfPresent(Int64.self, forKey: .number) ?? 0
        float = try k.decodeIfPresent(Float.self, forKey: .float) ?? 0
        string = try k.decodeIfPresent(String.self, forKey: .string) ?? ""
        stringSet = try k.decodeIfPresent([String].self, forKey: .stringSet) ?? []
    }
}

extension MigrationPrefsCodec.PrefsFileSnapshot {
    enum CodingKeys: String, CodingKey { case entries }
    init(from decoder: Decoder) throws {
        let k = try decoder.container(keyedBy: CodingKeys.self)
        entries = try k.decodeIfPresent([String: MigrationPrefsCodec.PrefValue].self, forKey: .entries) ?? [:]
    }
}

extension MigrationPrefsCodec.PrefsSnapshot {
    enum CodingKeys: String, CodingKey { case files }
    init(from decoder: Decoder) throws {
        let k = try decoder.container(keyedBy: CodingKeys.self)
        files = try k.decodeIfPresent([String: MigrationPrefsCodec.PrefsFileSnapshot].self, forKey: .files) ?? [:]
    }
}

/// 各模块覆盖的 prefs 文件清单 (debug_import 为调试通道, 永不迁移)。
/// iOS: 大多数 prefs 走 UserDefaults.standard(主文件 sleepy_prefs 直接复用);
/// 二级文件 (custom_themes / widget_bindings / ...) 走 suiteName。
enum MigrationPrefsFileMap {
    static let PREFERENCES: [String] = [
        "sleepy_prefs",     // AppPrefs 主文件(212+ 键)
        "custom_themes",    // 自定义主题
    ]
    static let WIDGETS: [String] = [
        "widget_bindings",
        "widget_scroll_prefs",
        "widget_compact_window_prefs",
        "widget_today_nav",
    ]
    static let PERSISTED_STATE: [String] = []   // iOS 端当前无独立持久态; 预留给未来扩展

    static func files(of: MigrationModule) -> [String] {
        switch `of` {
        case .PREFERENCES: return PREFERENCES
        case .WIDGETS: return WIDGETS
        case .PERSISTED_STATE: return PERSISTED_STATE
        default: return []
        }
    }
}
