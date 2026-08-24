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

import Foundation

enum WidgetTableResolver {
    static func resolveCurrentTable(_ repo: ScheduleRepository) -> TimeTableEntity? {
        let all = (try? repo.getAllTables()) ?? []
        // 优先:默认表且有课
        if let def = all.first(where: { $0.isDefault }) {
            let hasCourses = ((try? repo.getCourses(def.id)) ?? []).isEmpty == false
            if hasCourses { return def }
        }
        // 次选:任意有课的表(课程数最多)
        let counts = all.map { (table: $0, count: ((try? repo.getCourses($0.id)) ?? []).count) }
        return counts.max(by: { $0.count < $1.count })
            .flatMap { $0.count > 0 ? $0.table : nil }
    }
}
