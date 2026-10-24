// HolidayReminderPolicyAdapter.swift — ← util/HolidayReminderPolicyAdapter.kt (GPL-3.0)
// 纯策略(HolidayReminderPolicy)的平台边界: 从 HolidayManager/AppPrefs 取数并喂入。
//
// 结构契约(← HolidayReminderPolicyAdapterTest.kt "adapter reads effective entries
// merged by manager without merging twice"): 合并只做一次, 且只做在
// HolidayManager.getYearData() 里; 本适配器禁止再调 mergeSegments/toSets,
// 只从 yearData.entries 按两种 API 类型过滤, 可用性直接取 yearData.available。
// 在适配器里自己合并一遍 = 把同一逻辑复制成第二处真源: toSets 的"非 transfer_workday
// 即节假日"与安卓两个 == 过滤不等价, 且手搓的缓存探测会与 manager 内部的
// hasCachedData 判定漂移。契约测试 SleepyTests/HolidayReminderPolicyAdapterTests.swift 锁此。

import Foundation

enum HolidayReminderPolicyAdapter {
    static func decide(date: Date, tableId: Int64) async -> HolidayReminderPolicy.Result {
        // ← Android L9 HolidayManager.getYearData(ctx, date.year): 返回"已合并用户覆盖并
        // 按天展开"的生效条目 + available。getYearData 内部 available = hasCachedData ||
        // !fetchFailed(← HolidayManager.kt yearData() L169), 且 fetchEntries 解析成功即
        // 清除 yearFetchFailed(← kt L221; iOS 落点 HolidayManager.swift 的
        // yearFetchFailed.removeValue), 因此瞬时网络失败不会把标记卡在整个进程生命周期,
        // 缓存命中年也不会被误判 dataUnavailable 而走策略兜底分支。
        let yearData = await HolidayManager.getYearData(date.year)
        let holidays = Set(yearData.entries
            .filter { $0.type == HolidayManager.TYPE_PUBLIC_HOLIDAY }
            .map { $0.date })
        let workdays = Set(yearData.entries
            .filter { $0.type == HolidayManager.TYPE_TRANSFER_WORKDAY }
            .map { $0.date })
        let transfers = AppPrefs.shared.getHolidayTransfers(tableId)
        return HolidayReminderPolicy.decide(
            date: date,
            publicHolidays: holidays,
            transferWorkdays: workdays,
            transfers: transfers,
            rulesEnabled: AppPrefs.shared.isHolidayReminderRulesEnabled(),
            publicHolidayReminder: AppPrefs.shared.isHolidayReminderPublicHolidayEnabled(),
            transferHolidayReminder: AppPrefs.shared.isHolidayReminderTransferHolidayEnabled(),
            makeupWorkdayReminder: AppPrefs.shared.isHolidayReminderMakeupWorkdayEnabled(),
            ordinaryWeekendReminder: AppPrefs.shared.isHolidayReminderOrdinaryWeekendEnabled(),
            // ← Android L29 dataAvailable = yearData.available
            dataAvailable: yearData.available
        )
    }
}
