// WidgetTableResolver.swift — ← WidgetTableResolver.kt
// Widget 共用:找当前要展示的课表。
//
// 策略(与 App 内默认课表一致):
// 1. 默认表(isDefault=true)且有课 → 用它
// 2. 否则任意有课的表(按课程数最多)
// 3. 否则 nil(widget 显示"请先创建课表")
//
// ★ 修复(继承自 Android):旧逻辑"优先选非默认表中课程数最多的",导致只要存在任何非默认表
//   (如测试/导入副表),widget 就脱离用户在 App 里设的默认表,App 与 widget 不同步。
//
// 平台对应:Android 的 resolveBoundTable(widgetId: Int) 按 appWidgetId 逐实例绑定;
// iOS WidgetKit 无稳定实例 ID,粒度收窄为 per-kind(差异表#8 附注),绑定读取复用
// WidgetBindingStore.get(kind)。

import Foundation

enum WidgetTableResolver {
    static func resolveCurrentTable(_ repo: ScheduleRepository) -> TimeTableEntity? {
        let all = (try? repo.getAllTables()) ?? []
        // 单遍解析: 每张表的课程列表只物化一次 (课程数与「是否有课」同源),
        // 不再默认表检查 + max 各读一遍 = 每表 2x 列表物化。
        // 选择语义与 Android 逐位一致:
        //   1. 第一个「默认表且有课」直接用 (defaultHit, firstOrNull 口径);
        //   2. 否则课程数最多的表 (并列取先出现者, maxByOrNull 口径), 全空 → nil。
        var best: TimeTableEntity? = nil
        var bestCount = -1
        var defaultHit: TimeTableEntity? = nil
        for table in all {
            let count = ((try? repo.getCourses(table.id)) ?? []).count
            if table.isDefault && count > 0 && defaultHit == nil { defaultHit = table }
            if count > bestCount {
                best = table
                bestCount = count
            }
        }
        // issue#40: 选出的表若绑定了独立时间节次表, 出口水合 —
        // 节次时间/智慧节次/节次数按绑定表解释, 兼容列兜底。悬空引用静默回退旧列。
        guard let chosen = defaultHit ?? (bestCount > 0 ? best : nil) else { return nil }
        return chosen.hydratedWith(getPeriodTableOrNull(repo, chosen.periodTableId))
    }

    /// Resolve the table a specific widget instance is bound to.
    ///
    /// Returns the bound table if the user has explicitly bound one and it
    /// still exists in the database. Returns nil when the widget has no
    /// binding or the bound table was deleted — callers should fall back to
    /// [resolveCurrentTable] in that case.
    ///
    /// Lazy invalidation: a deleted table does NOT rewrite the binding entry;
    /// [WidgetBindingStore.remove] is invoked only when the widget instance
    /// itself is removed.
    /// - Parameter kind: iOS 侧 per-kind 粒度(对应 Android 的 appWidgetId)。
    static func resolveBoundTable(_ kind: String, repo: ScheduleRepository) -> TimeTableEntity? {
        guard let boundId = WidgetBindingStore.get(kind) else { return nil }
        guard let table = ((try? repo.getTable(boundId)) ?? nil) else { return nil }
        // issue#40: 绑定实例同样按其绑定的独立时间节次表水合
        return table.hydratedWith(getPeriodTableOrNull(repo, table.periodTableId))
    }

    /// issue#40: nil 安全取时间节次表 — id 为 nil 或查无此行都返回 nil
    /// (getPeriodTable 返回 optional, try? 产生双层 optional, 拉平一层)
    private static func getPeriodTableOrNull(
        _ repo: ScheduleRepository,
        _ periodTableId: Int64?
    ) -> PeriodTableEntity? {
        guard let id = periodTableId else { return nil }
        return (try? repo.getPeriodTable(id)) ?? nil
    }
}
