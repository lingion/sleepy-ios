// CustomThemeStore.swift — ← data/CustomThemeStore.kt
// 自定义主题存储:用户在编辑器里配出的主题存 4 个"源角色"种子(primary/secondary/
// tertiary 种子 hex + surfaceHue/surfaceChroma 表面中性倾向),完整 WakeUpColorScheme
// 由 CustomSchemeDeriver 按 M3 角色关系派生,深浅两套同源生成。
//
// 序列化形状是跨版本存储契约,key 名一字不可改:
//   [{"id","name","primary","secondary","tertiary","surfaceHue","surfaceChroma","createdAt"}]
//
// ★ 平台差异(iOS 存储落点):Android 用独立 SharedPreferences 文件
//   (PREFS_NAME="custom_themes")。iOS 侧 widget extension 读主题走的是
//   AppPrefs.shared(其 UserDefaults 域 = themeKey 所在域;App Group entitlement
//   已按 project.yml 注释剥除,AppGroupResolver 回退沙箱,全仓无 UserDefaults(suiteName:))。
//   因此本 store 与 AppPrefs 共用同一 UserDefaults 域 —— themeKey 对 widget 可见,
//   自定义主题就对 widget 可见;两者可见性严格同源,不会出现"widget 知道选中的是
//   custom:<id> 却读不到该 id"的半截状态。未来 AppPrefs 迁 App Group suite,本 store 自动跟随。
//
// 解析容错语义对齐 HolidayManager:整文档损坏 → 空列表;坏行(缺 id/形状错)跳过、
// 好行保留;缺可选数值字段(surfaceHue/surfaceChroma/createdAt)落默认值而非整行丢弃。

import Combine
import Foundation

// MARK: - ← CustomTheme data class

struct CustomTheme: Codable, Equatable {
    let id: String
    let name: String
    /// 主交互色种子(按钮/选中态/当前周胶囊/链接色),"#RRGGBB"
    let primary: String
    /// 次级强调种子(芯片/次级容器底色),"#RRGGBB"
    let secondary: String
    /// 第三强调种子(节次 chip 等点缀),"#RRGGBB"
    let tertiary: String
    /// 表面中性色色相倾向 0.0-360.0(与 primary 同相即主题氛围一致性来源)
    let surfaceHue: Double
    /// 表面中性色饱和度倾向,推荐 4-12(0 = 纯灰,过高 = 彩色表面)
    let surfaceChroma: Double
    let createdAt: Int64

    init(id: String, name: String, primary: String, secondary: String, tertiary: String,
         surfaceHue: Double, surfaceChroma: Double, createdAt: Int64) {
        self.id = id
        self.name = name
        self.primary = primary
        self.secondary = secondary
        self.tertiary = tertiary
        self.surfaceHue = surfaceHue
        self.surfaceChroma = surfaceChroma
        self.createdAt = createdAt
    }

    /// ← Kotlin data class 自动生成的 copy():编辑器草稿只替换需要的字段,其余原样带走。
    func copy(id: String? = nil, name: String? = nil, primary: String? = nil, secondary: String? = nil,
              tertiary: String? = nil, surfaceHue: Double? = nil, surfaceChroma: Double? = nil,
              createdAt: Int64? = nil) -> CustomTheme {
        CustomTheme(
            id: id ?? self.id,
            name: name ?? self.name,
            primary: primary ?? self.primary,
            secondary: secondary ?? self.secondary,
            tertiary: tertiary ?? self.tertiary,
            surfaceHue: surfaceHue ?? self.surfaceHue,
            surfaceChroma: surfaceChroma ?? self.surfaceChroma,
            createdAt: createdAt ?? self.createdAt
        )
    }
}

// MARK: - ← CustomThemeCore(纯逻辑核心,所有语义集中在此以便单测)

enum CustomThemeCore {

    /// UserDefaults key — 存 JSON 数组字符串(← KEY_THEMES)
    static let KEY_THEMES = "custom_themes"

    /// Android 侧 SharedPreferences 文件名(iOS 与 AppPrefs 同域,见文件头平台差异说明)
    static let PREFS_NAME = "custom_themes"

    /// 缺省表面色相 — 与默认淡紫模板的紫相一致
    static let DEFAULT_SURFACE_HUE = 265.0

    /// 缺省表面饱和度 — 低 chroma 中性色推荐区间(4-12)中值
    static let DEFAULT_SURFACE_CHROMA = 8.0

    /// ← UUID.randomUUID().toString()
    static func newId() -> String { UUID().uuidString }

    /// 序列化为 JSON 数组字符串。key 集合 = 8 字段契约;对象内 key 顺序不参与契约
    /// (JSON 对象无序,Android JSONObject 同样不保证顺序),用 sortedKeys 取确定性输出。
    static func toJson(_ themes: [CustomTheme]) -> String {
        let rows: [[String: Any]] = themes.map { t in
            [
                "id": t.id,
                "name": t.name,
                "primary": t.primary,
                "secondary": t.secondary,
                "tertiary": t.tertiary,
                "surfaceHue": t.surfaceHue,
                "surfaceChroma": t.surfaceChroma,
                "createdAt": t.createdAt
            ]
        }
        guard JSONSerialization.isValidJSONObject(rows),
              let data = try? JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    /// 反序列化。整文档损坏/非数组 → 空列表;坏行跳过、好行保留;可选字段缺省兜底。
    static func parse(_ json: String) -> [CustomTheme] {
        guard let data = json.data(using: .utf8) else { return [] }
        // 不用 .fragmentsAllowed:"" / "null" / 标量都会 throw → 与 Android JSONArray() 抛错同语义
        guard let raw = try? JSONSerialization.jsonObject(with: data),
              let rows = raw as? [Any] else {
            return []
        }
        var out: [CustomTheme] = []
        for element in rows {
            // arr.optJSONObject(i) ?: continue — 非对象行直接跳过
            guard let row = element as? [String: Any] else { continue }
            let id = optString(row, "id", "")
            // id 是唯一键(upsert/delete/getById 都靠它),缺失行不可救 — 跳过
            if id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            out.append(CustomTheme(
                id: id,
                name: optString(row, "name", ""),
                primary: optString(row, "primary", "#6750A4"),
                secondary: optString(row, "secondary", "#625B71"),
                tertiary: optString(row, "tertiary", "#7D5260"),
                surfaceHue: optDouble(row, "surfaceHue", DEFAULT_SURFACE_HUE),
                surfaceChroma: optDouble(row, "surfaceChroma", DEFAULT_SURFACE_CHROMA),
                createdAt: optLong(row, "createdAt", 0)
            ))
        }
        return out
    }

    /// upsert by id:存在即原位替换,不存在追加尾部
    static func upsert(_ list: inout [CustomTheme], _ theme: CustomTheme) {
        if let idx = list.firstIndex(where: { $0.id == theme.id }) {
            list[idx] = theme
        } else {
            list.append(theme)
        }
    }

    /// 删除指定 id;@return 是否真的删了(未知 id = false,列表不动)
    @discardableResult
    static func delete(_ list: inout [CustomTheme], _ id: String) -> Bool {
        let before = list.count
        list.removeAll { $0.id == id }
        return list.count != before
    }

    static func getById(_ list: [CustomTheme], _ id: String) -> CustomTheme? {
        list.first { $0.id == id }
    }

    // ── org.json optXxx 等价(缺字段/类型不符 → 默认值,不抛) ──

    private static func optString(_ row: [String: Any], _ key: String, _ def: String) -> String {
        switch row[key] {
        case let s as String: return s
        case let n as NSNumber: return n.stringValue   // org.json optString 会把数字转字符串
        default: return def
        }
    }

    private static func optDouble(_ row: [String: Any], _ key: String, _ def: Double) -> Double {
        switch row[key] {
        case let n as NSNumber:
            let v = n.doubleValue
            return v.isNaN || v.isInfinite ? def : v
        case let s as String:
            guard let v = Double(s.trimmingCharacters(in: .whitespaces)) else { return def }
            return v.isNaN || v.isInfinite ? def : v
        default: return def
        }
    }

    private static func optLong(_ row: [String: Any], _ key: String, _ def: Int64) -> Int64 {
        switch row[key] {
        case let n as NSNumber: return n.int64Value
        case let s as String: return Int64(s.trimmingCharacters(in: .whitespaces)) ?? def
        default: return def
        }
    }
}

// MARK: - ← CustomThemeStore(Android SharedPreferences 门面的 iOS 等价)

/// 全部逻辑在 CustomThemeCore,此处只做 UserDefaults 桥接。
enum CustomThemeStore {

    /// 与 AppPrefs 同一存储域(见文件头平台差异说明)。单测可注入独立 suite 隔离。
    static var defaults: UserDefaults { AppPrefs.shared.sharedBackedStore }

    private static func loadAll(_ d: UserDefaults) -> [CustomTheme] {
        guard let json = d.string(forKey: CustomThemeCore.KEY_THEMES) else { return [] }
        return CustomThemeCore.parse(json)
    }

    private static func saveAll(_ themes: [CustomTheme], _ d: UserDefaults) {
        d.set(CustomThemeCore.toJson(themes), forKey: CustomThemeCore.KEY_THEMES)
    }

    /// ← CustomThemeStore.kt:150 `fun changes(ctx): Flow<String>` 的 Combine 等价。
    ///
    /// 语义逐项对应 Android callbackFlow:
    /// - 订阅即发当前序列化文档(cold-flow 逐订阅现取,对应 callbackFlow 每次 collect 现读
    ///   `getString(key, null).orEmpty()` → 用 `Deferred` 把首值延迟到订阅时刻计算);
    /// - registerOnSharedPreferenceChangeListener(key == KEY_THEMES) →
    ///   `NotificationCenter` 监听 `UserDefaults.didChangeNotification`,按 object === 注入域过滤;
    ///   同域其他 key 的写入也会被放行,但下方 removeDuplicates 会把"文档未变"的推送吞掉,
    ///   可观测输出与 Android 的 key 过滤完全一致;
    /// - distinctUntilChanged → `removeDuplicates()`。
    ///
    /// 发出值本身即 invalidation token:同 id 就地编辑也会改变文档内容,下游
    /// (SleepyThemeProvider 的 customThemeVersion 位)只需据此重走 [getById] 读取,不消费内容。
    /// ← MainActivity.kt:171 的订阅方在 iOS 由 AppRoot 接线(见集成说明)。
    static func changes(_ d: UserDefaults = CustomThemeStore.defaults) -> AnyPublisher<String, Never> {
        NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification)
            .filter { ($0.object as? UserDefaults) === d }
            .map { _ in d.string(forKey: CustomThemeCore.KEY_THEMES) ?? "" }
            .prepend(Deferred { Just(d.string(forKey: CustomThemeCore.KEY_THEMES) ?? "") })
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    static func getAll(_ d: UserDefaults = CustomThemeStore.defaults) -> [CustomTheme] {
        loadAll(d)
    }

    static func getById(_ id: String, _ d: UserDefaults = CustomThemeStore.defaults) -> CustomTheme? {
        CustomThemeCore.getById(loadAll(d), id)
    }

    /// upsert by id — 编辑既有主题复用同入口
    static func save(_ theme: CustomTheme, _ d: UserDefaults = CustomThemeStore.defaults) {
        var list = loadAll(d)
        CustomThemeCore.upsert(&list, theme)
        saveAll(list, d)
    }

    /// 删除;@return 是否真的删了
    @discardableResult
    static func delete(_ id: String, _ d: UserDefaults = CustomThemeStore.defaults) -> Bool {
        var list = loadAll(d)
        let removed = CustomThemeCore.delete(&list, id)
        if removed { saveAll(list, d) }
        return removed
    }
}
