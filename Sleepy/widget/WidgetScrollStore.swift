// WidgetScrollStore.swift — ← widget/WidgetScrollCore.kt + WidgetScrollStore.kt
// 强制滚动(实验) per-widget 布尔开关 (JSON 文件壳, 与 原版本 SharedPreferences 1:1)。
//
// ★ 平台差异(差异表#8 附注, 与 WidgetBindingStore 同因): 原版本 键 = appWidgetId
//   (每实例一档); iOS 无稳定实例 ID → 键收窄为 widget kind (同 kind 实例共享,
//   与绑定存储粒度一致)。
//
// 迁移语义 (← WidgetScrollCore 注释): 本 kind 从未显式设置过 → 继承旧全局值
// (AppPrefs.isWidgetScrollEnabled; 出厂默认 false = FIXED 固定窗口); 编辑页一旦
// 拨动即写显式值, 与旧全局彻底脱钩。
//
// ★ iOS 平台差异: WidgetKit 无 RemoteViews 滚动条带, 开关仅作迁移语义载体 +
//   未来 ScrollView 扩展位, FIXED 窗口为 iOS 唯一渲染路径。

import Foundation

/// Per-widget 强制滚动 (实验) 存储 (← WidgetScrollStore + WidgetScrollCore)。
enum WidgetScrollStore {
    /// ← PREFS_NAME("widget_scroll_prefs") + ".json" 后缀
    private static let fileName = "widget_scroll_prefs.json"
    /// ← WidgetScrollCore.key("scroll_$id") → "scroll_$kind"
    private static let keyPrefix = "scroll"

    private static func storeURL() -> URL {
        AppGroupResolver.sharedDirectory().appendingPathComponent(fileName)
    }

    /// 读取 kind -> Bool 全量映射 (坏文件/不存在 = 空)
    private static func loadAll() -> [String: Bool] {
        guard let data = try? Data(contentsOf: storeURL()),
              let map = try? JSONDecoder().decode([String: Bool].self, from: data) else {
            return [:]
        }
        return map
    }

    private static func saveAll(_ map: [String: Bool]) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        try? data.write(to: storeURL(), options: .atomic)
    }

    private static func makeKey(_ kind: String) -> String {
        "\(keyPrefix)_\(kind)"
    }

    /// 显式值; nil = 从未设置 (调用方按迁移语义回退旧全局)。← WidgetScrollCore.read
    static func read(_ kind: String) -> Bool? {
        loadAll()[makeKey(kind)]
    }

    /// ← WidgetScrollCore.write
    static func write(_ kind: String, _ enabled: Bool) {
        var map = loadAll()
        map[makeKey(kind)] = enabled
        saveAll(map)
    }

    /// ← WidgetScrollCore.delete (iOS 无 onDeleted 回调; 残键惰性无害)
    static func remove(_ kind: String) {
        var map = loadAll()
        map.removeValue(forKey: makeKey(kind))
        saveAll(map)
    }

    /// 生效值 = 显式值 ?: 旧全局 (出厂默认 false = FIXED)。← WidgetScrollCore.resolve
    static func resolve(_ explicit: Bool?, _ legacyGlobal: Bool) -> Bool {
        explicit ?? legacyGlobal
    }

    /// 本 kind 生效值 = 显式 ?: AppPrefs.isWidgetScrollEnabled (迁移默认)。
    /// 旧全局的 default 由 AppPrefs 持有, 改这里只接壳。
    static func isScrollEnabled(kind: String) -> Bool {
        resolve(read(kind), AppPrefs.shared.isWidgetScrollEnabled())
    }

    /// 写入本 kind 显式值 + 触发全量重推 (← WidgetEditViewModel.setScrollEnabled)。
    static func setScrollEnabled(kind: String, enabled: Bool) {
        write(kind, enabled)
    }
}
