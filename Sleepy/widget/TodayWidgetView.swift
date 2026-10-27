// TodayWidgetView.swift — ← TodayWidget.kt (Receiver) + WidgetBitmapRenderers.renderToday
// 桌面 Today 小组件 — 今日课程列表。
//
// 对齐 Android 定稿语义 (ede839af / ab19fd26 / 8c0fcbea / ab27230c / 2dbad515 / 895fe72f):
//  1. 固定窗口: 正文只放得下 availH 的行, 溢出折成底部「+N」胶囊 (无滚动);
//  2. 行几何: 行高 30 / 行距 4 / 冲突行同栏堆叠距 3, 冲突课并排分栏;
//  3. 底部条: 只剩「+N」胶囊 (Android 的 ◀▶↻ 翻天按钮依赖 PendingIntent + per-widgetId
//     状态,iOS 15.6 部署目标下 WidgetKit 无等价物 → 不实现,详见对齐报告);
//  4. 「+N」恒画且不可点: 有溢出 +N,无溢出/全部上完「+0」;
//  5. ALL_DONE: 不写「今日课程已结束」长状态行,空正文 + 「+0」胶囊即结束标记;
//  6. 分簇用 timeJson: 非标准时间课不再被占位节点误判成冲突行。

import SwiftUI
import WidgetKit

// MARK: - Entry

struct TodayWidgetEntry: TimelineEntry {
    let date: Date
    let data: WidgetData
    /// 该 entry 生效时刻的当日分钟 ← 课程边界锚点 (WidgetBoundaryScheduler 等价)
    var nowMin: Int? = nil
}

struct TodayWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayWidgetEntry {
        WidgetArchiveLog.append(kind: "TodayWidgetRV", family: context.family.description, result: "success")
        // 占位脸不读 DB (async 装载不能同步等, 与 TwoDay/WeekList placeholder 同规)。
        return TodayWidgetEntry(date: Date(), data: WidgetData(date: Date(), courses: [],
                                                               timeJson: TimeTableUtils.DEFAULT_TIME_JSON,
                                                               hasTable: false))
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayWidgetEntry) -> Void) {
        WidgetArchiveLog.append(kind: "TodayWidgetRV", family: context.family.description, result: "success")
        Task {
            let now = Date()
            let data = await TodayWidgetLoader.loadData(kind: "TodayWidgetRV")
            completion(TodayWidgetEntry(date: now, data: data, nowMin: WidgetWindows.nowMinutes(now)))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayWidgetEntry>) -> Void) {
        Task {
            let data = await TodayWidgetLoader.loadData(kind: "TodayWidgetRV")
            let now = Date()
            var entries = [TodayWidgetEntry(date: now, data: data, nowMin: WidgetWindows.nowMinutes(now))]
            // ← WidgetBoundaryScheduler: 每节课下课的下一分钟 (end+1) 一颗边界,窗口跟着前移。
            // Android 用 AlarmManager 重推,iOS 等价 = 把边界做成 timeline entry,到点自动换页。
            if data.hasTable && data.semesterStatus == .inRange {
                for at in WidgetWindows.boundaryDates(courses: data.courses, timeJson: data.timeJson, from: now) {
                    entries.append(TodayWidgetEntry(date: at, data: data, nowMin: WidgetWindows.nowMinutes(at)))
                }
            }
            // 次日 00:05 换日 (数据变化仍由 App 端 WidgetCenter.reloadAllTimelines 触发)
            var cal = DateUtils.isoCalendar
            cal.timeZone = .current
            let tomorrow = cal.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(3600)
            let refresh = cal.date(bySettingHour: 0, minute: 5, second: 0, of: tomorrow) ?? tomorrow
            WidgetArchiveLog.append(kind: "TodayWidgetRV", family: context.family.description, result: "success")
            completion(Timeline(entries: entries, policy: .after(refresh)))
        }
    }
}

// MARK: - View ← renderTodayRegular (Android 已删小档纯文本脸,三档同一渲染器)

struct TodayWidgetEntryView: View {
    @Environment(\.widgetFamily) var widgetFamily
    @Environment(\.colorScheme) private var widgetColorScheme
    let entry: TodayWidgetEntry

    var body: some View {
        let data = entry.data
        let isDark = effectiveWidgetIsDark(themeMode: data.themeMode, snapshotIsDark: data.isDark, envScheme: widgetColorScheme)
        let s = resolveWidgetScheme(themeKey: data.themeKey, isDark: isDark)
        let prefs = AppPrefs.shared
        let colorless = prefs.isWidgetColorless()
        let displayMode = prefs.getDisplayMode()   // ★ 用户显示设置 (决策 D5-12)
        let showDate = prefs.isShowDate()
        let useAlias = prefs.isWidgetUseAlias()    // issue#26: widget 全局一档别名开关
        let tier = WidgetLayoutTier(family: widgetFamily)
        // 时间窗只在「今天」生效 (Android data.isToday);非今天走 HEAD 从头截断
        let nowMin = Calendar.current.isDate(entry.date, inSameDayAs: data.date) ? entry.nowMin : nil

        return GeometryReader { proxy in
            let win = TodayWidgetEntryView.window(data: data, heightDp: proxy.size.height,
                                                  tier: tier, nowMin: nowMin)
            // 标题行 ← todayHeaderParts (WidgetBitmapRenderers.kt:271-278):
            // 跳转态「最近有课的一天 · 周X」 > isToday ?「今天 · 周X」:「M/D · 周X」;
            // 右侧日期仅「今日态 + showDate」画 (iOS 无导航 UI, 回今天 action 恒不画,
            // 与 Android 静态渲染 showBackToToday=false 同口径, TodayWidget.kt:329)
            let titleText: String = {
                let dayLabel: String
                if data.weekDisplayStatus == .nearestBusyDay {
                    dayLabel = L10n.format("schedule_nearest_busy_day")
                } else if data.isToday {
                    dayLabel = L10n.format("today_today")
                } else {
                    dayLabel = data.dateLabel
                }
                return "\(dayLabel) · \(data.dayName)"
            }()

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(titleText)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(s.primary)
                        .lineLimit(1) // 安卓 ellipsize 单行 (min 预算 40dp)
                    Spacer(minLength: 4)
                    if showDate && data.isToday {
                        Text(data.dateLabel)
                            .font(.system(size: 12))
                            .foregroundColor(s.onSurfaceVariant)
                            .lineLimit(1)
                    }
                }
                .frame(height: 20, alignment: .top) // 表头固定前进量 20dp ← Android y+=20f

                statusOrCourses(data: data, win: win, scheme: s, colorless: colorless,
                                displayMode: displayMode, useAlias: useAlias)

                Spacer(minLength: 0)

                // 底部条 (← configureTodayBar): 「+N」胶囊恒画、不可点,左对齐
                HStack(spacing: 4) {
                    WidgetMoreCapsule(hidden: win?.hiddenAheadCourses ?? 0, scheme: s)
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        // 唯一背景 = containerBackground (iOS 17+ 剥离场景生效; iOS ≤16 回退 .background)。
        // 旧 GeometryReader 内容上的 .background(s.bg) 是前景不透明层, 会使
        // StandBy/锁屏剥离失效 — 与 sleepyWidgetBackground 的采用目的冲突, 已删。
        .sleepyWidgetBackground { s.bg }
        .widgetURL(URL(string: "sleepy://open"))
    }

    /// 固定窗口: 只有「有课表 + 学期内 + 有课」才有行轴,其余状态无窗口语义
    static func window(data: WidgetData, heightDp: CGFloat, tier: WidgetLayoutTier,
                       nowMin: Int?) -> WidgetWindowCore.WindowResult? {
        guard data.hasTable, data.semesterStatus == .inRange, !data.courses.isEmpty else { return nil }
        return WidgetWindows.today(courses: data.courses, timeJson: data.timeJson,
                                   heightDp: heightDp, tier: tier, nowMin: nowMin)
    }

    @ViewBuilder
    private func statusOrCourses(data: WidgetData, win: WidgetWindowCore.WindowResult?,
                                 scheme s: WidgetScheme, colorless: Bool,
                                 displayMode: String, useAlias: Bool) -> some View {
        if !data.hasTable {
            Text(L10n.format("widget_create_schedule"))
                .font(.system(size: 15))
                .foregroundColor(s.onSurface)
        } else if data.semesterStatus != .inRange {
            // ★ 学期外: 状态标题 + 提示行,不画课程
            // ← Android y+=22f 行前进量 (frame 固定高, 旧 padding6+自然行高 使
            //   第二行比安卓低 ≈2pt)
            Text(data.semesterStatus == .beforeStart
                 ? L10n.format("semester_not_started")
                 : L10n.format("semester_ended"))
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(s.onSurface)
                .frame(height: 22, alignment: .top)
            Text(L10n.format("today_semester_out_hint"))
                .font(.system(size: 11))
                .foregroundColor(s.onSurfaceVariant)
        } else if data.courses.isEmpty {
            // 今日无课 → 大字提示 + 副文案 (22dp 行前进量同上)
            Text(L10n.format("today_no_course"))
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(s.onSurface)
                .frame(height: 22, alignment: .top)
            Text(L10n.format("today_rest"))
                .font(.system(size: 12))
                .foregroundColor(s.onSurfaceVariant)
        } else if win?.status == .allDone {
            // ALL_DONE (ab27230c): 空正文,唯一结束标记 = 底部「+0」胶囊
            EmptyView()
        } else if let rows = win?.visible.map({ $0.row }), !rows.isEmpty {
            // 固定窗口内的行 (行序即窗口序),溢出部分折进「+N」
            VStack(alignment: .leading, spacing: WidgetRowGeometry.rowGap) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    WidgetCourseRowView(row: row, allCourses: data.courses, timeJson: data.timeJson,
                                        scheme: s, colorless: colorless, displayMode: displayMode,
                                        useAlias: useAlias, isGrey: data.isGrey)
                }
            }
            // ← drawCourse(greyAlpha 0x99): 节假日/周末灰显整列课卡降透明度 (与 TwoDay 同口径)
            .opacity(data.isGrey ? 153.0 / 255.0 : 1)
        } else {
            // 时间窗锚点之后暂无可显示行 (例如下课后、下一节前的空档)
            EmptyView()
        }
    }

}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodayWidgetRV", provider: TodayWidgetProvider()) { entry in
            TodayWidgetEntryView(entry: entry)
        }
        .configurationDisplayName(L10n.format("widget_today_label"))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        // iOS 17+ 系统边距关闭, 维持既有自管 padding 布局 (iOS 16 及以下 no-op)
        .contentMarginsDisabled()
    }
}
