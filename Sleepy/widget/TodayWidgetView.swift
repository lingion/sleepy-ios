// TodayWidgetView.swift — ← TodayWidget.kt (Receiver) + WidgetBitmapRenderers.renderToday
// 桌面 Today 小组件 — 今日课程列表。
//
// 对齐 原版本 定稿语义 (ede839af / ab19fd26 / 8c0fcbea / ab27230c / 2dbad515 / 895fe72f):
//  1. 固定窗口: 正文只放得下 availH 的行, 溢出折成底部「+N」胶囊 (无滚动);
//  2. 行几何: 行高 30 / 行距 4 / 冲突行同栏堆叠距 3, 冲突课并排分栏;
//  3. 底部条: 只剩「+N」胶囊 (原版本 的 ◀▶↻ 翻天按钮依赖 PendingIntent + per-widgetId
//     状态,iOS 15.6 部署目标下 WidgetKit 无等价物 → 不实现,详见对齐报告);
//  4. 「+N」恒画且不可点: 有溢出 +N,无溢出/全部上完「+0」;
//  5. ALL_DONE: 不写「今日课程已结束」长状态行,空正文 + 「+0」胶囊即结束标记;
//  6. 分簇用 timeJson: 非标准时间课不再被占位节点误判成冲突行。

import SwiftUI
import WidgetKit
#if compiler(>=5.9)
import AppIntents
#endif

// MARK: - Entry

struct TodayWidgetEntry: TimelineEntry {
    let date: Date
    let data: WidgetData
    /// 该 entry 生效时刻的当日分钟 ← 课程边界锚点 (WidgetBoundaryScheduler 等价)
    var nowMin: Int? = nil
    var navKey: String = "TodayWidgetRV"
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
            let timeline = await Self.timeline(familyDescription: context.family.description)
            completion(timeline)
        }
    }

    static func timeline(familyDescription: String,
                         overrideTableId: Int64? = nil) async -> Timeline<TodayWidgetEntry> {
        let now = Date()
        let navKey = TodayDateNavStore.widgetKey(kind: "TodayWidgetRV", tableId: overrideTableId)
        let data = await TodayWidgetLoader.loadData(kind: "TodayWidgetRV", now: now,
                                                  overrideTableId: overrideTableId, navKey: navKey)
        let nextDayData = await loadNextDayData(kind: "TodayWidgetRV", current: data, from: now,
                                              overrideTableId: overrideTableId, navKey: navKey)
        let entries = timelineEntries(data: data, nextDayData: nextDayData, from: now, navKey: navKey)
        // 次日 00:05 换日 (数据变化仍由 App 端 WidgetCenter.reloadAllTimelines 触发)
        var cal = DateUtils.isoCalendar
        cal.timeZone = .current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(3600)
        let refresh = cal.date(bySettingHour: 0, minute: 5, second: 0, of: tomorrow) ?? tomorrow
        WidgetArchiveLog.append(kind: "TodayWidgetRV", family: familyDescription, result: "success")
        return Timeline(entries: entries, policy: .after(refresh))
    }

    static func rolloverDate(data: WidgetData, from now: Date) -> Date? {
        guard data.isToday, data.hasTable, data.semesterStatus == .inRange,
              !data.courses.isEmpty else { return nil }
        return WidgetWindows.boundaryDates(courses: data.courses, timeJson: data.timeJson, from: now).last
    }

    static func loadNextDayData(kind: String, current: WidgetData, from now: Date,
                                overrideTableId: Int64? = nil, navKey: String? = nil) async -> WidgetData? {
        let effectiveNavKey = navKey ?? TodayDateNavStore.widgetKey(kind: kind, tableId: overrideTableId)
        guard AppPrefs.shared.isNearestBusyDay(), !TodayDateNavStore.hasNavigation(effectiveNavKey),
              let rollover = rolloverDate(data: current, from: now) else { return nil }
        let candidate = await TodayWidgetLoader.loadData(kind: kind, now: rollover,
                                                         overrideTableId: overrideTableId,
                                                         navKey: effectiveNavKey)
        guard candidate.hasTable, !Calendar.current.isDate(candidate.date, inSameDayAs: current.date) else {
            return nil
        }
        return candidate
    }

    static func timelineEntries(data: WidgetData, nextDayData: WidgetData?,
                                from now: Date,
                                navKey: String = "TodayWidgetRV") -> [TodayWidgetEntry] {
        guard data.isToday, data.hasTable, data.semesterStatus == .inRange,
              !data.courses.isEmpty else {
            let nowMin = data.isToday ? WidgetWindows.nowMinutes(now) : nil
            return [TodayWidgetEntry(date: now, data: data, nowMin: nowMin, navKey: navKey)]
        }
        let boundaries = WidgetWindows.boundaryDates(courses: data.courses, timeJson: data.timeJson, from: now)
        guard let rollover = boundaries.last else {
            if let nextDayData {
                return [TodayWidgetEntry(date: now, data: nextDayData, nowMin: nil, navKey: navKey)]
            }
            return [TodayWidgetEntry(date: now, data: data, nowMin: WidgetWindows.nowMinutes(now), navKey: navKey)]
        }
        var entries = [TodayWidgetEntry(date: now, data: data, nowMin: WidgetWindows.nowMinutes(now), navKey: navKey)]
        for at in boundaries.dropLast() {
            entries.append(TodayWidgetEntry(date: at, data: data, nowMin: WidgetWindows.nowMinutes(at), navKey: navKey))
        }
        if let nextDayData {
            entries.append(TodayWidgetEntry(date: rollover, data: nextDayData, nowMin: nil, navKey: navKey))
            var cal = DateUtils.isoCalendar
            cal.timeZone = .current
            let nextStart = cal.startOfDay(for: nextDayData.date)
            for at in WidgetWindows.boundaryDates(courses: nextDayData.courses,
                                                 timeJson: nextDayData.timeJson, from: nextStart) {
                entries.append(TodayWidgetEntry(date: at, data: nextDayData,
                                                nowMin: WidgetWindows.nowMinutes(at), navKey: navKey))
            }
        } else {
            entries.append(TodayWidgetEntry(date: rollover, data: data,
                                            nowMin: WidgetWindows.nowMinutes(rollover), navKey: navKey))
        }
        return entries
    }
}

#if compiler(>=5.9)
@available(iOS 17.0, *)
struct TodayWidgetIntentProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TodayWidgetEntry {
        TodayWidgetProvider().placeholder(in: context)
    }

    func snapshot(for configuration: SelectTimetableIntent, in context: Context) async -> TodayWidgetEntry {
        WidgetArchiveLog.append(kind: "TodayWidgetRV", family: context.family.description, result: "success")
        let now = Date()
        let tableId = configuration.timetable?.id
        let navKey = TodayDateNavStore.widgetKey(kind: "TodayWidgetRV", tableId: tableId)
        let data = await TodayWidgetLoader.loadData(kind: "TodayWidgetRV", now: now,
                                                  overrideTableId: tableId, navKey: navKey)
        return TodayWidgetEntry(date: now, data: data, nowMin: WidgetWindows.nowMinutes(now), navKey: navKey)
    }

    func timeline(for configuration: SelectTimetableIntent, in context: Context) async -> Timeline<TodayWidgetEntry> {
        await TodayWidgetProvider.timeline(familyDescription: context.family.description,
                                           overrideTableId: configuration.timetable?.id)
    }
}

@available(iOS 17.0, *)
struct TodayIntentWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "TodayWidgetRV", intent: SelectTimetableIntent.self,
                               provider: TodayWidgetIntentProvider()) { entry in
            TodayWidgetEntryView(entry: entry, allowsNavigation: true)
        }
        .configurationDisplayName(L10n.format("widget_today_label"))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .sleepyContentMarginsDisabled()
    }
}
#endif

// MARK: - View ← renderTodayRegular (原版本 已删小档纯文本脸,三档同一渲染器)

struct TodayWidgetEntryView: View {
    @Environment(\.widgetFamily) var widgetFamily
    @Environment(\.sleepyWidgetGalleryFamily) private var galleryFamily
    @Environment(\.colorScheme) private var widgetColorScheme
    @Environment(\.colorSchemeContrast) private var widgetContrast
    let entry: TodayWidgetEntry
    var allowsNavigation: Bool = false

    var body: some View {
        // iOS 26 主屏「透明/着色」样式探测 (← WidgetBackgroundCompat): glass 态配色
        // 整体换白 alpha 层级, 否则系统把不透明主题色整组染白 → 文字/图标不可辨
        WidgetGlassModeContent { mode in
            content(renderingMode: mode)
        }
        .widgetURL(URL(string: "sleepy://open"))
    }

    @ViewBuilder
    private func content(renderingMode: SleepyWidgetRenderingMode) -> some View {
        let data = entry.data
        let isDark = effectiveWidgetIsDark(themeMode: data.themeMode, snapshotIsDark: data.isDark, envScheme: widgetColorScheme)
        let s = resolveWidgetScheme(themeKey: data.themeKey, isDark: isDark, renderingMode: renderingMode,
                                    increasedContrast: widgetContrast == .increased)
        let prefs = AppPrefs.shared
        let colorless = prefs.isWidgetColorless()
        let displayMode = prefs.getDisplayMode()   // ★ 用户显示设置 (决策 D5-12)
        let showDate = prefs.isShowDate()
        let useAlias = prefs.isWidgetUseAlias()    // issue#26: widget 全局一档别名开关
        let tier = WidgetLayoutTier(family: galleryFamily ?? widgetFamily)
        // 时间窗只在「今天」生效 (原版本 data.isToday);非今天走 HEAD 从头截断
        let nowMin = Calendar.current.isDate(entry.date, inSameDayAs: data.date) ? entry.nowMin : nil

        return GeometryReader { proxy in
            let win = TodayWidgetEntryView.window(data: data, heightDp: proxy.size.height,
                                                  tier: tier, nowMin: nowMin)
            // 标题行 ← todayHeaderParts (WidgetBitmapRenderers.kt:271-278):
            // 跳转态「最近有课的一天 · 周X」 > isToday ?「今天 · 周X」:「M/D · 周X」;
            // 右侧日期仅「今日态 + showDate」画 (iOS 无导航 UI, 回今天 action 恒不画,
            // 与 原版本 静态渲染 showBackToToday=false 同口径, TodayWidget.kt:329)
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
                .frame(height: 20, alignment: .top) // 表头固定前进量 20dp ← 原 y+=20f

                statusOrCourses(data: data, win: win, scheme: s, colorless: colorless,
                                displayMode: displayMode, useAlias: useAlias)

                Spacer(minLength: 0)

                // Bottom bar: +N capsule always left-aligned, optional trailing day nav buttons.
                HStack(spacing: 4) {
                    WidgetMoreCapsule(hidden: win?.hiddenAheadCourses ?? 0, scheme: s)
                    Spacer(minLength: 0)
                    if allowsNavigation {
                        todayNavButtons(data: data, scheme: s, compact: tier == .small,
                                        interactive: galleryFamily == nil, navKey: entry.navKey)
                    }
                }
                .frame(height: WidgetRowGeometry.navBarH)
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        // 唯一背景 = containerBackground (iOS 17+ 剥离场景生效; iOS ≤16 回退 .background)。
        // 旧 GeometryReader 内容上的 .background(s.bg) 是前景不透明层, 会使
        // StandBy/锁屏剥离失效 — 与 sleepyWidgetBackground 的采用目的冲突, 已删。
        // glass 态 s.bg = .clear → 容器底交给系统玻璃材质, 半透前景保持 alpha。
        .sleepyWidgetBackground { s.bg }
    }

    @ViewBuilder
    private func todayNavButtons(data: WidgetData, scheme: WidgetScheme,
                                 compact: Bool, interactive: Bool, navKey: String) -> some View {
        let spacing: CGFloat = compact ? 4 : 6
        HStack(spacing: spacing) {
            todayNavButton(systemName: "chevron.left", labelKey: "today_nav_prev_day",
                           delta: -1, navKey: navKey, scheme: scheme,
                           compact: compact, interactive: interactive)
            if !data.isToday {
                todayNavButton(systemName: "arrow.counterclockwise", labelKey: "today_nav_back_to_today",
                               delta: 0, navKey: navKey, scheme: scheme,
                               compact: compact, interactive: interactive)
            }
            todayNavButton(systemName: "chevron.right", labelKey: "today_nav_next_day",
                           delta: 1, navKey: navKey, scheme: scheme,
                           compact: compact, interactive: interactive)
        }
    }

    @ViewBuilder
    private func todayNavButton(systemName: String, labelKey: String, delta: Int,
                                navKey: String, scheme: WidgetScheme,
                                compact: Bool, interactive: Bool) -> some View {
        let size = CGSize(width: compact ? 24 : 34, height: compact ? 22 : 26)
        let label = Image(systemName: systemName)
            .font(.system(size: compact ? 10 : 12, weight: .semibold))
            .foregroundColor(scheme.onSurfaceVariant)
            .frame(width: size.width, height: size.height)
            .background(scheme.surfaceVariant)
            .cornerRadius(compact ? 7 : 8)
            .contentShape(Rectangle())
            .accessibilityLabel(L10n.format(labelKey))

        if interactive {
#if compiler(>=5.9)
            if #available(iOS 17.0, *) {
                Button(intent: TodayNavIntent(delta: delta, widgetKey: navKey)) {
                    label
                }
                .buttonStyle(.plain)
            } else {
                Link(destination: TodayDateNavStore.navURL(delta: delta, widgetKey: navKey)) {
                    label
                }
            }
#else
            Link(destination: TodayDateNavStore.navURL(delta: delta, widgetKey: navKey)) {
                label
            }
#endif
        } else {
            label
        }
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
            // ← 原版本 y+=22f 行前进量 (frame 固定高, 旧 padding6+自然行高 使
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
            TodayWidgetEntryView(entry: entry, allowsNavigation: true)
        }
        .configurationDisplayName(L10n.format("widget_today_label"))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .sleepyContentMarginsDisabled()
    }
}
