// WidgetBindingStore.swift — ← WidgetBindingCore.kt + WidgetBindingStore.kt
// 小组件逐实例课表绑定存储。原版本 侧 SharedPreferences("widget_bindings") + "app_widget_<id>"
// 键的忠实对应:iOS 侧为 App Group 共享容器中的 JSON 文件,键 = widget kind。
//
// ★ 平台差异(差异表#8 附注): WidgetKit StaticConfiguration 不暴露 appWidgetId 等价物,
//   WidgetCenter.getCurrentConfigurations 的 WidgetInfo 无稳定实例 ID。原版本 的"每个已放置
//   实例独立绑定"在 iOS 的粒度上限是 per-kind(同 kind 所有实例共享 TimelineEntry 内容,
//   本就无法逐实例渲染)。因此键从 appWidgetId 收窄为 kind,语义逐条对应:
//   - null 绑定 = 跟随全局默认表 (WidgetTableResolver.resolveCurrentTable)
//   - 绑定的表被删 = 惰性失效:读取时校验表仍存在,否则回退 resolver(存储不回写,←
//     WidgetBindingCore.resolveBoundTableId 的注释语义)

import Foundation

enum WidgetBindingStore {
    // ← WidgetBindingCore.PREFS_NAME("widget_bindings")+ JSON 后缀
    private static func storeURL() -> URL {
        AppGroupResolver.sharedDirectory().appendingPathComponent("widget_bindings.json")
    }

    // ← WidgetBindingCore.parseAll: 读取 kind -> tableId 全量映射(坏文件/不存在 = 空)
    private static func loadAll() -> [String: Int64] {
        guard let data = try? Data(contentsOf: storeURL()),
              let map = try? JSONDecoder().decode([String: Int64].self, from: data) else {
            return [:]
        }
        return map
    }

    private static func saveAll(_ map: [String: Int64]) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        try? data.write(to: storeURL(), options: .atomic)
    }

    // ← WidgetBindingCore.read
    static func get(_ kind: String) -> Int64? {
        loadAll()[kind]
    }

    // ← WidgetBindingCore.write
    static func put(_ kind: String, tableId: Int64) {
        var map = loadAll()
        map[kind] = tableId
        saveAll(map)
    }

    // ← WidgetBindingCore.delete
    static func remove(_ kind: String) {
        var map = loadAll()
        map.removeValue(forKey: kind)
        saveAll(map)
    }

    // ← WidgetBindingCore.resolveBoundTableId: 绑定 id 指向的表仍存在才返回,
    //   否则 nil → 调用方回退 WidgetTableResolver.resolveCurrentTable。
    static func resolveBoundTable(_ kind: String, repo: ScheduleRepository) -> TimeTableEntity? {
        guard let bound = get(kind) else { return nil }
        let all = (try? repo.getAllTables()) ?? []
        return all.first { $0.id == bound }
    }
}
