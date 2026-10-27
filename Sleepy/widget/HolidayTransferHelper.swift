// HolidayTransferHelper.swift — ← widget/HolidayTransferHelper.kt
// 某表某天应"按星期几取课"; 映射命中 → targetDate 的星期几, 未映射=自然星期。
// tableId 为 nil(无表/兜底) → 自然星期。

import Foundation

enum HolidayTransferHelper {
    /// ← Android L14-18: 某表某天实际上谁的课 (取课语义) — 补班日→sourceDate,
    /// 放假日→nil(无课), 未映射/无表→原日期。
    static func courseDateForDate(_ tableId: Int64?, _ date: Date) -> Date? {
        guard let tableId = tableId else { return date }
        let transfers = AppPrefs.shared.getHolidayTransfers(tableId)
        return HolidayTransferOps.courseDateForDate(date, transfers)
    }

    static func effectiveDayOfWeek(_ tableId: Int64?, _ date: Date) -> Int {
        guard let tableId = tableId else {
            let raw = DateUtils.isoCalendar.component(.weekday, from: date)
            return raw == 1 ? 7 : raw - 1
        }
        let transfers = AppPrefs.shared.getHolidayTransfers(tableId)
        return HolidayTransferOps.effectiveDayOfWeek(date, transfers)
    }
}
