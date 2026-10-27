// WeekViewWidgetView.swift — ← WeekViewWidget.kt + WidgetBitmapRenderers.renderWeekView
// 本周课表(周视图) widget — 复刻 DaySummaryCell (CourseTableView.kt L559-L642)。
// 列卡片同 WeekList;课程列表: 纯文本无胶囊背景, take(5)/FIXED 窗口, onSurfaceVariant 色,
// today 列 onPrimaryContainer@0.82alpha, 课程间分隔线(可选开关)。
//
// v1.0.61 对齐 (← WeekViewWidget.kt companion L193-237 + push 闸门 L44-93):
//  1. 装载器复用 WeekListWidgetDataLoader (Android 注释「与 WeekListWidget.loadDataSync
//     完全一致」): resolve(kind) 展示周 / AFTER_END 清空 / 调休映射 / isGrey /
//     compactWindow / weekDisplayStatus 全量接线;
//  2. 每列 FIXED 窗口: availH = hDp − 56 − statusH, heightOf = wrapMax2Lines 行数 ×
//     lineH + 3dp, 页脚 lineH+3 (computeWeekViewWindows L163-183);
//  3. SMALL 档日列 = compactShownDays 单一口径 (compactWindow 优先, §9.1);
//  4. 灰显 = 标题+chip alpha 153/255 (renderWeekViewRegular L1169-1186; 课名不灰);
//  5. 分隔线开关不改变总前进量: ON/OFF 均恒 3dp (L1219-1235)。
// forceScroll 条带 = Android 专有宿主, iOS 由列底「+N」窗口截断等价承担 (平台差异);
// compactFace 与 WeekList 同先例统一叠窗口 (iOS 无条带可滚, 否则溢出无处报告)。

import SwiftUI
import WidgetKit

struct WeekViewWidgetEntry: TimelineEntry {
    let date: Date
    let data: WeekData
}

struct WeekViewWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> WeekViewWidgetEntry {
        WidgetArchiveLog.append(kind: "WeekViewWidgetRV", family: context.family.description, result: "success")
        // 占位脸不读 DB (异步装载不能同步等); 真实数据在 snapshot/timeline 到达。
        return WeekViewWidgetEntry(date: Date(), data: WeekData(days: [], hasTable: false))
    }

    func getSnapshot(in context: Context, completion: @escaping (WeekViewWidgetEntry) -> Void) {
        WidgetArchiveLog.append(kind: "WeekViewWidgetRV", family: context.family.description, result: "success")
        Task {
            let data = await WeekListWidgetDataLoader.loadData(kind: "WeekViewWidgetRV")
            completion(WeekViewWidgetEntry(date: Date(), data: data))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeekViewWidgetEntry>) -> Void) {
        Task {
            let now = Date()
            let data = await WeekListWidgetDataLoader.loadData(kind: "WeekViewWidgetRV")
            let refresh = now.addingTimeInterval(6 * 3600)  // 半天兜底;数据变化由 App 端 reloadAllTimelines 触发
            WidgetArchiveLog.append(kind: "WeekViewWidgetRV", family: context.family.description, result: "success")
            completion(Timeline(entries: [WeekViewWidgetEntry(date: now, data: data)], policy: .after(refresh)))
        }
    }
}

// MARK: - View ← renderWeekView

struct WeekViewWidgetEntryView: View {
    @Environment(\.widgetFamily) private var widgetFamily
    @Environment(\.colorScheme) private var widgetColorScheme
    let entry: WeekViewWidgetEntry

    var body: some View {
        let data = entry.data
        let isDark = effectiveWidgetIsDark(themeMode: data.themeMode, snapshotIsDark: data.isDark, envScheme: widgetColorScheme)
        let s = resolveWidgetScheme(themeKey: data.themeKey, isDark: isDark)
        let showSeparator = AppPrefs.shared.isWidgetSeparator()
        let todayDow = DateUtils.todayDayOfWeek(today: Date())
        // issue#26: widget 全局一档别名开关
        let useAlias = AppPrefs.shared.isWidgetUseAlias()
        let tier = WidgetLayoutTier(family: widgetFamily)
        // 状态行占位 16dp ← WeekViewWidget.kt L66-67: semesterStatus != IN_RANGE ||
        // weekDisplayStatus != NORMAL (自动跳最近有课日时同样抬列顶)
        let statusH: CGFloat = (data.semesterStatus != .inRange || data.weekDisplayStatus != .normal) ? 16 : 0

        return GeometryReader { proxy in
            // ← renderWeekView L1067: SMALL 变体 + 容器 <150dp 才走 compact 脸
            // (日列 = compactShownDays 单一口径 — compactWindow 优先三天真实日期窗口,
            //  空才回退今天邻域 ≤3 列; §9.1); 容器被拖大 ≥150dp → 内部升档回全量排版。
            let isCompact = widgetFamily == .systemSmall && proxy.size.width < 150
            let days = isCompact
                ? WidgetCompactHelpers.compactShownDays(data, AppPrefs.shared.getVisibleDays(), todayDow)
                : shownDays(data)
            // ← push() L68-70 闸门: hasTable && 列非空 && 任一天有课 (数据层 days 全量口径);
            // compactFace 不叠窗口是 Android 条带先例, iOS 与 WeekList 同规统一叠窗口
            // (无条带可滚, 否则溢出无处报告)。
            let colW = days.isEmpty ? 0
                : (proxy.size.width - 12 - 4 * CGFloat(days.count - 1)) / CGFloat(days.count)
            let wins = (data.hasTable && !days.isEmpty && data.days.contains { !$0.courses.isEmpty })
                ? WidgetWindows.weekView(days: days, heightDp: proxy.size.height, tier: tier,
                                         statusH: statusH, colW: colW)
                : nil
            Group {
                if !data.hasTable || days.isEmpty {
                    Text(L10n.format("widget_create_schedule"))
                        .font(.system(size: 15))
                        .foregroundColor(s.onSurface)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    VStack(spacing: 0) {
                        // ★ 学期外: 顶部全宽状态行(只画一次, 同 renderWeekList)
                        if data.semesterStatus != .inRange {
                            Text(data.semesterStatus == .beforeStart
                                 ? L10n.format("semester_not_started")
                                 : L10n.format("semester_ended"))
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(s.onSurfaceVariant)
                                .frame(maxWidth: .infinity)
                                .padding(.bottom, 4)
                        }
                        HStack(alignment: .top, spacing: 4) {
                            ForEach(Array(days.enumerated()), id: \.offset) { colIdx, day in
                                WeekViewDayColumn(day: day, scheme: s,
                                                  // ← renderWeekViewRegular L1157: 今天高亮按
                                                  // 真实日期判 (展示周≠自然周/compactWindow 跨周
                                                  // 时按星期会错列, 同 WeekList L828 先例)
                                                  isToday: DateUtils.isDateToday(day.date),
                                                  showSeparator: showSeparator, useAlias: useAlias,
                                                  window: colIdx < (wins?.count ?? 0) ? wins?[colIdx] : nil)
                            }
                        }
                    }
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sleepyWidgetBackground { s.bg }
        .widgetURL(URL(string: "sleepy://open"))
    }
}

private struct WeekViewDayColumn: View {
    let day: DayData
    let scheme: WidgetScheme
    let isToday: Bool
    let showSeparator: Bool
    /// issue#26: widget 场景别名 — 课名展示名
    let useAlias: Bool
    /// 本列 FIXED 窗口; nil = 无窗口 → 回退 take(5) (← visibleByCol ?: courses.take(5))
    let window: WidgetWindowCore.WindowResult?

    var body: some View {
        let s = scheme
        // 窗口装得下前 N 门, 其余折成列底「+N」; 无窗口 = take(5) 封顶 (静态脸口径)
        let visible: [CourseEntity]
        if let window = window {
            visible = window.visible.flatMap { $0.row.courses }
        } else {
            visible = Array(day.courses.prefix(5))
        }
        let footerText: String? = window.flatMap { $0.footer ? "+\($0.hiddenAheadCourses)" : nil }
        // 灰显作用域 ← renderWeekViewRegular L1169-1186: 标题 + chip (bg/文字) alpha 153;
        // 课名文字不灰 (L1208-1211 无 applyAlpha), 页脚不灰 (L1238-1243)
        let greyAlpha: Double = day.isGrey ? 153.0 / 255.0 : 1.0

        return VStack(alignment: .center, spacing: 0) {
            // 星期标题
            Text(weekDayLabels[day.dayOfWeek])
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(isToday ? s.onPrimaryContainer : s.onSurface)
                .opacity(greyAlpha)
                .padding(.top, 1)   // 安卓标题基线 colTop+12 (字形顶≈+4)
                .padding(.bottom, 11) // chip 顶 colTop+26

            if !day.courses.isEmpty {
                // 课程数量 chip — chip 文字继承标题 BOLD (L1171 设 bold, L1196 才重置;
                // chip 绘制在 L1187-1191 之间); 宽 = 文本长度*6+12dp、高 14dp 固定公式
                // (L1182-1183), 非自然字宽。
                let chipText = "\(day.courses.count) 门"
                Text(chipText)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(s.onSurfaceVariant)
                    .opacity(greyAlpha)
                    .frame(width: CGFloat(chipText.count) * 6 + 12, height: 14)
                    .background(s.surfaceVariant.opacity(greyAlpha))
                    .cornerRadius(50)
                    .padding(.bottom, 4)  // 4dp gap (DaySummaryCell L624)

                // 课程 mini-list — 最多2行换行 + 课程间分隔线(可选)。
                // 分隔线开关不改变总前进量 (安卓 L1219-1235: ON = 1.5+线1+1.5 恒 3dp,
                // OFF = 纯 3dp): spacing 0 + 每课固定 .padding(.bottom,3), 线画在
                // 3dp 间隙正中 (offset −1 → 线占 [1,2], 与安卓描边 [cy+1, cy+2] 同段)。
                VStack(alignment: .center, spacing: 0) {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { idx, course in
                        // today → onPrimaryContainer@0.82alpha, 其他 → onSurfaceVariant
                        Text(CourseDisplayUtil.displayName(course, useAlias))
                            .font(.system(size: 9))
                            .foregroundColor(isToday
                                ? s.onPrimaryContainer.opacity(0.82)
                                : s.onSurfaceVariant)
                            .multilineTextAlignment(.leading) // 安卓 Paint 默认 LEFT, 画在 x+textPad
                            .lineLimit(2)   // wrapMax2Lines → 最多2行,超出截断 (安卓只截断不缩字)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4) // textPad 4dp
                            .padding(.bottom, 3)     // courseGap 3dp (含尾课收尾, 同安卓 idx==last 分支)
                            .overlay(alignment: .bottom) {
                                if showSeparator && idx < visible.count - 1 {
                                    Rectangle()
                                        .fill(s.onSurfaceVariant.opacity(0.4))
                                        .frame(height: 1)
                                        .padding(.horizontal, 4)
                                        .offset(y: -1)
                                }
                            }
                    }
                    // 列底「+N」短页脚 (仅窗口真的截断时画 ← footerByCol; 9dp bold,
                    // 安卓页脚不随灰显降 alpha)
                    if let footerText = footerText {
                        Text(footerText)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(s.onSurfaceVariant)
                            .frame(maxWidth: .infinity)
                    }
                }
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(isToday ? s.primaryContainer : s.surfaceContainer)
        .cornerRadius(14)
    }
}

struct WeekViewWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WeekViewWidgetRV", provider: WeekViewWidgetProvider()) { entry in
            WeekViewWidgetEntryView(entry: entry)
        }
        .configurationDisplayName(L10n.format("widget_week_view_label"))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        // iOS 17+ 系统边距关闭, 维持既有自管 padding 布局 (iOS 16 及以下 no-op)
        .contentMarginsDisabled()
    }
}

// ← weekViewCompactColumns / compactDays 旧转发已删 (无调用点);
// compact 选列单一事实源 = WidgetCompactHelpers.compactShownDays /
// weekViewCompactColumns (← WidgetBitmapRenderers.kt 同名函数)。

