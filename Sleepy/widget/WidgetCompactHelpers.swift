// WidgetCompactHelpers.swift — ← WidgetBitmapRenderers.kt 的四个 compact 纯函数:
//   compactShownDays / compactWindowDates / weekViewCompactColumns / weekGridMinimumTodayData
//
// 平台差异 (对齐任务项 1): Android 渲染器是 Canvas bitmap 管道 (PLATFORM_EXEMPT 不逐符号移植),
// 但这四个函数是**数据选择纯函数** (哪个日列进 compact 脸 / 最小档落在哪一天),
// 与 Canvas 无关 → 照常移植为 enum 纯函数 (文件头注明平台差异)。
// WeekViewWidgetView.swift 已有 weekViewCompactColumns 的旧副本 (对齐期先行版),
// 本文件为单一事实源; 旧副本保留为转发以不破既有调用点。

import Foundation

enum WidgetCompactHelpers {

    /// 最小档 compact 脸实际显示日列 — 渲染器与高度闸门共用单一口径 (§9.1):
    /// compactWindow 非空 → 三天真实日期窗口 (2026-09-15 用户令, 可跨上下周, 按日期升序);
    /// 空 → 回退旧 weekViewCompactColumns 今天邻域 ≤3 列口径(防御: 数据源未提供窗口时)。
    /// visibleDays 过滤后为空集则回退未过滤窗口(防御, 对齐 D5-12 空集回退惯例)。
    static func compactShownDays(_ data: WeekData, _ visibleDays: Set<Int>, _ todayDow: Int) -> [DayData] {
        if !data.compactWindow.isEmpty {
            var win: [DayData]
            if visibleDays.isEmpty {
                win = data.compactWindow
            } else {
                win = data.compactWindow.filter { visibleDays.contains($0.dayOfWeek) }
                if win.isEmpty { win = data.compactWindow }
            }
            return win.sorted { $0.date < $1.date }
        }
        let pool: [DayData] = visibleDays.isEmpty ? data.days
            : data.days.filter { visibleDays.contains($0.dayOfWeek) }
        let dows = weekViewCompactColumns(WeekData(days: pool, hasTable: data.hasTable), todayDow: todayDow)
        return data.days.filter { dows.contains($0.dayOfWeek) }.sorted { $0.dayOfWeek < $1.dayOfWeek }
    }

    /// 最小档三天窗口的真实日期 (2026-09-15 用户令, 渲染与单测共用单一事实来源):
    /// todayFirst=true → 今天/明天/后天(今日居于第一位); false → 昨天/今天/明天(今日居于第二位)。
    /// 固定三天, 不跳空天; 日期可越出本周(上下周打通由数据层按所在周周次过滤课程)。
    /// 纯函数零 Date() — today 由调用方注入。
    static func compactWindowDates(_ today: Date, _ todayFirst: Bool, _ anchorDate: Date? = nil) -> [Date] {
        let anchor = anchorDate ?? today
        if todayFirst {
            return [anchor,
                    Calendar.isoAddDays(anchor, 1),
                    Calendar.isoAddDays(anchor, 2)]
        }
        return [Calendar.isoAddDays(anchor, -1),
                anchor,
                Calendar.isoAddDays(anchor, 1)]
    }

    /// WeekView 小档列选取(渲染与单测共用单一事实来源):
    /// 有课的日子优先成池; 今天必保(无课也追加进池, 锚点语义);
    /// 按"与今天的距离"取最近 maxColumns 列, 最终按星期升序输出(从左到右绘制顺序)。
    /// 纯函数零 Date() — todayDow 由调用方注入。
    static func weekViewCompactColumns(_ data: WeekData, todayDow: Int, maxColumns: Int = 3) -> [Int] {
        var pool = data.days.filter { !$0.courses.isEmpty }.map { $0.dayOfWeek }
        if pool.isEmpty { pool = data.days.map { $0.dayOfWeek } }
        if !pool.contains(todayDow) { pool.append(todayDow) }
        // Kotlin sortedBy 稳定排序: tie 保持池内原序
        let ranked = pool.enumerated().sorted { a, b in
            let da = abs(a.element - todayDow), db = abs(b.element - todayDow)
            return da != db ? da < db : a.offset < b.offset
        }
        return Array(ranked.prefix(maxColumns).map { $0.element }).sorted()
    }

    /// WeekGrid 最小档数据映射 — WeekData → 今日 WidgetData (v1.0.60 口径:
    /// NEAREST_BUSY_DAY 时 targetDate = nearestBusyTargetDate (数据源显式给出),
    /// 缺省回退最早有课日 → 最早日 → today (Android v1.0.61+ 同口径)。
    /// 最小档(1×1 列)不再"折叠成单列的网格脸", 直接复用今日课程·小的渲染器:
    /// 宿主只换数据, 渲染走 renderToday(SMALL) → 与今日课程·小像素同源同一张脸。
    /// 纯函数零 Date() — today 由调用方注入。
    static func weekGridMinimumTodayData(_ data: WeekData, today: Date) -> WidgetData {
        let timeJson = data.days.first?.timeJson ?? ""
        // ← Android weekGridMinimumTodayData (:1029-35): 数据源显式 targetDate 优先;
        //   整周数据下 minBy=周一不一定是跳转目标日 → 最早有课日次之, minDate 再次。
        let targetDate: Date
        if data.weekDisplayStatus == .nearestBusyDay {
            targetDate = data.nearestBusyTargetDate
                ?? data.days.first(where: { !$0.courses.isEmpty })?.date
                ?? data.days.map({ $0.date }).min()
                ?? today
        } else {
            targetDate = today
        }
        let targetDay = data.days.first { DateUtils.isoCalendar.isDate($0.date, inSameDayAs: targetDate) }
        return WidgetData(
            date: targetDate,
            courses: targetDay?.courses ?? [],
            timeJson: timeJson,
            hasTable: data.hasTable,
            isDark: data.isDark,
            themeKey: data.themeKey,
            themeMode: data.themeMode,
            semesterStatus: data.semesterStatus,
            isToday: DateUtils.isoCalendar.isDate(targetDate, inSameDayAs: today),
            isGrey: targetDay?.isGrey ?? false,
            weekDisplayStatus: data.weekDisplayStatus
        )
    }
}
