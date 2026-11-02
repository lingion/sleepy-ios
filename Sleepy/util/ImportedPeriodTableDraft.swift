// ImportedPeriodTableDraft.swift — ← util/ImportedPeriodTableDraft.kt (v1.0.62, GPL-3.0)
// 导入新建课表的作息表草稿 — 用户 2026-10-05(2a): 三个入口作息表行为统一。

import Foundation

/// A selected existing schedule stays shared; otherwise confirmed rows own the new schedule.
/// 选中既有作息表(bindingId != nil)→ 共享不新建; 否则确认页最终行 owns 新作息表
/// (无 P 区块的旧格式/粘贴文本也恒以 confirmedTimeJson 兜底建表)。
func importedPeriodTableDraft(bindingId: Int64?,
                              name: String,
                              confirmedTimeJson: String) -> PeriodTableEntity? {
    if bindingId != nil { return nil }
    return PeriodTableEntity(
        name: name,
        nodesPerDay: max(TimeTableUtils.parseTimeSlotRows(confirmedTimeJson).count, 1),
        timeJson: confirmedTimeJson)
}
