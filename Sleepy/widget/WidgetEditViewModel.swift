// WidgetEditViewModel.swift — ← widget/WidgetEditCore.kt + WidgetEditViewModel.kt
//   (Core 纯逻辑 + 旁注映射; ViewModel 状态机等价物请见 WidgetEditScreen.swift)
//
// Read model for a single widget instance's edit screen.
//   - currentBinding: nil = "follow the app-wide default table" (i.e.
//     WidgetTableResolver.resolveCurrentTable); Int64 = 显式绑定课表 id
//   - availableTables: schedules with at least one course (空表被过滤,
//     绑定到空表只会渲染「请先创建课表」, 同 原版本 filterAvailableTables)
//
// ★ 平台差异: 原版本 用 ViewModel+StateFlow; iOS SwiftUI 端无 ViewModel 抽象,
//   状态由 WidgetEditScreen (@State + onAppear 拉数) 直接管理 → 纯逻辑归
//   WidgetEditCore (本文件 enum), UI state 变更的副作用(setBinding/setUseAlias/
//   setScrollEnabled/setCompactTodayFirst) 走 WidgetEditScreen.swift 调 facade 函数。

import Foundation
import WidgetKit

enum WidgetEditCore {

    /// Filter to tables that have at least one course. An empty table is
    /// useless to bind to (the widget would render "请先创建课表"), so we
    /// hide it from the picker. Input order is preserved — the picker shows
    /// tables in the same order the rest of the app does.
    /// - Parameter countCourses: closure wraps the suspend DAO call so the
    ///   core lambda stays synchronous (WidgetEditViewModel 预计算 counts Map)
    static func filterAvailableTables(
        _ all: [TimeTableEntity],
        countCourses: (Int64) -> Int
    ) -> [TimeTableEntity] {
        all.filter { countCourses($0.id) > 0 }
    }

    /// Read the current binding for [kind] from the raw map.
    /// ← initialBinding(raw, widgetId) — 键 = WidgetBindingCore.key(kind)
    static func initialBinding(_ raw: [String: Int64], _ kind: String) -> Int64? {
        raw[kind]
    }

    /// Apply a binding change in pure data. nil = "remove" (revert to the
    /// app-wide default table). The caller is responsible for persisting
    /// the resulting map (← WidgetEditCore.applyBindingChange)
    static func applyBindingChange(
        _ raw: inout [String: Int64],
        _ kind: String,
        _ newTableId: Int64?
    ) {
        if let newTableId = newTableId {
            raw[kind] = newTableId
        } else {
            raw.removeValue(forKey: kind)
        }
    }

    /// Translate a raw stored binding into the value the picker UI treats as
    /// "explicitly bound": the first-add sentinel (0L) and absent entries
    /// both mean "follow the app-wide default" → nil.
    /// ← displayBinding(raw: Long?): Long? = raw?.takeIf { it > 0L }
    static func displayBinding(_ raw: Int64?) -> Int64? {
        guard let v = raw, v > 0 else { return nil }
        return v
    }
}

// MARK: - Side-effect facades (写库 + 重推 widget 渲染)

/// ← vm.setBinding: 写 WidgetBindingStore + 全量刷 widget (iOS = reloadAllTimelines)
func setWidgetBinding(_ kind: String, _ tableId: Int64?) {
    if let id = tableId {
        WidgetBindingStore.put(kind, tableId: id)
    } else {
        WidgetBindingStore.remove(kind)
    }
    WidgetCenter.shared.reloadAllTimelines()
}

/// ← vm.setUseAlias: 写 AppPrefs(内部已 reloadAllTimelines) + reload
///   这里复用 AppPrefs.shared.setWidgetUseAlias, 不重复刷新

/// ← vm.setScrollEnabled: 写 WidgetScrollStore + 全量刷 widget
///   平台差异: iOS 无 RemoteViews 滚动条带, FIXED 为唯一渲染路径 → 开关仅作迁移语义载体;
///   写入仅保留 trace, 不影响当前渲染行为
func setWidgetScrollEnabled(_ kind: String, _ enabled: Bool) {
    // 旧 原版本 facade: WidgetScrollStore.setScrollEnabled(ctx, kind, enabled)
    // iOS 端不落盘 (iOS 无 RemoteViews 滚动条带, 实际不可观察);
    // 改 pref 也不动 (本字段是迁移兜底, 不再写入)。保留为 no-op 供 UI 同位调用。
    _ = enabled
    _ = kind
}

/// ← vm.setCompactTodayFirst: 写 WidgetCompactWindowStore + 全量刷 widget
func setWidgetCompactTodayFirst(_ kind: String, _ todayFirst: Bool) {
    WidgetCompactWindowStore.setTodayFirst(kind, todayFirst)
    WidgetCenter.shared.reloadAllTimelines()
}
