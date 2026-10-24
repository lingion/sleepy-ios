// TwoDayWidgetView.swift — ← TwoDayWidget.kt (Receiver + companion loadDataSync)
//   + WidgetBitmapRenderers.renderTwoDayRegular
// 最近两天 widget — 左右两栏并排, 中间竖直分隔。
// 选日语义 (← TwoDayWidget.kt loadDataSync, v1.0.61 对齐):
//   NORMAL → 今天 + 明天; NEAREST_BUSY_DAY → 最近两个未来有课日
//   (用户 2026-09-23 定稿: 11/2 + 12/2, 不再是 targetDate+1; 不足两日 →
//   targetDate + targetDate+1 兜底)。星期取课走 HolidayTransferHelper 调休映射,
//   灰显走 HolidayManager.shouldGrey (issue#44)。
//
// 对齐 Android 定稿语义 (2dbad515 / 8c0fcbea / ab27230c / 895fe72f / f7e80c84):
//  1. 顶部「最近两天」标题行已删 (2dbad515), 直接以列标题起排;
//  2. 每列 FIXED 窗口独立 (今天列 TIME_WINDOW / 明天列 HEAD), 行高 36 / 行距 6 / 堆叠 3;
//  3. 每列「+N」胶囊恒画且各说各的 (合并求和禁回流), 上完/没课列显示「+0」;
//  4. ALL_DONE 列正文留空 —— 「无课程」文案不残留, 只剩列底「+0」标记 (ab27230c);
//  5. 三档同一渲染器 (Android renderTwoDay 已无 compact 分支), 2×2 靠窗口数学装 2 节;
//  6. 课程边界即刷新窗口 (f7e80c84 的 iOS 等价 = timeline entry 落在 end+1)。
//  7. forceScroll 条带 (WidgetScrollStore/ScrollStripService) = Android 专有宿主,
//     iOS 由列底「+N」胶囊等价承担 (平台差异, 非缺陷)。

import SwiftUI
import WidgetKit

struct TwoDayWidgetEntry: TimelineEntry {
    let date: Date
    let data: TwoDayData
    /// 该 entry 生效时刻的当日分钟 ← 课程边界锚点;nil = 不做时间窗截断
    var nowMin: Int? = nil
}

// MARK: - loadDataSync ← TwoDayWidgetReceiver.Companion.loadDataSync (v1.0.61 对齐)

/// TwoDay 专用装载器 — 与 WidgetDataLoaders.swift 的通用版不同, 本实现逐行对齐
/// Android companion: resolve(appWidgetId) → NEAREST_BUSY_DAY 选两列日 (用户
/// 2026-09-23 定稿 11/2+12/2) → 调休映射星期 → 按日 semesterStatus → 灰显。
/// Android runBlocking → iOS async (TimelineProvider completion 允许异步回调)。
enum TwoDayWidgetDataLoader {

    static func loadData(kind: String) async -> TwoDayData {
        let today = Date()
        let prefs = AppPrefs.shared
        let isDark = prefs.isDarkMode()
        let themeKey = prefs.getThemeKey()
        let themeMode = prefs.getThemeMode()
        let fallback = TwoDayData(days: [], hasTable: false, isDark: isDark,
                                  themeKey: themeKey, themeMode: themeMode)
        guard let source = await WidgetWeekDataLoader.resolve(kind) else { return fallback }
        let table = source.table
        let cal = DateUtils.isoCalendar
        let dates: [Date]
        if source.display.status == .nearestBusyDay {
            // 两列 = 最近两个未来有课日 (用户 2026-09-23 定稿: 11/2 + 12/2, 不再是
            // targetDate+1 的日历相邻日); 无第二个有课日 → 该列保持 targetDate+1 的
            // 日历顺序, 与「无课显示日历相邻」旧语义对齐。
            let nearest = WeekDisplayResolver.findNearestBusyDays(
                startDate: table.startDate,
                actualWeek: source.display.actualWeek,
                maxWeek: table.maxWeek,
                today: today,
                courses: source.courses,
                count: 2
            )
            dates = nearest.count >= 2
                ? Array(nearest.prefix(2))
                : [source.display.targetDate,
                   cal.date(byAdding: .day, value: 1, to: source.display.targetDate) ?? source.display.targetDate]
        } else {
            dates = [today, cal.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86400)]
        }
        let status = DateUtils.semesterStatus(startDate: table.startDate,
                                              maxWeek: table.maxWeek,
                                              today: dates.first ?? today)
        var days: [DayData] = []
        for date in dates {
            let week = DateUtils.currentWeek(startDate: table.startDate, today: date)
            let dow = HolidayTransferHelper.effectiveDayOfWeek(table.id, date)
            let courses = status != .inRange ? [] : source.coursesFor(dayOfWeek: dow, week: week)
            days.append(DayData(date: date, dayOfWeek: dow, courses: courses,
                                timeJson: table.timeJson,
                                isGrey: await HolidayManager.shouldGrey(date, tableId: table.id)))
        }
        return TwoDayData(days: days, hasTable: true, isDark: isDark, themeKey: themeKey,
                          themeMode: themeMode, semesterStatus: status,
                          weekDisplayStatus: source.display.status)
    }
}

struct TwoDayWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> TwoDayWidgetEntry {
        WidgetArchiveLog.append(kind: "TwoDayWidgetRV", family: context.family.description, result: "success")
        // 占位脸不读 DB (与 WeekListWidgetProvider.placeholder 同规): WidgetKit gallery 不能等
        //   async,而旧同步装载 (WidgetDataLoaders.TwoDayWidgetLoader) 是 v1.0.61 前的错位实现
        //   —— 写死 today/+86400、星期走 DateUtils.todayDayOfWeek 无调休映射、isGrey 恒 false、
        //   无 weekDisplayStatus, gallery 里会露出与真实档不一致的脸。真实数据 snapshot/timeline 到达。
        return TwoDayWidgetEntry(date: Date(),
                                 data: TwoDayData(days: [], hasTable: false),
                                 nowMin: WidgetWindows.nowMinutes(Date()))
    }

    func getSnapshot(in context: Context, completion: @escaping (TwoDayWidgetEntry) -> Void) {
        WidgetArchiveLog.append(kind: "TwoDayWidgetRV", family: context.family.description, result: "success")
        Task {
            let now = Date()
            let data = await TwoDayWidgetDataLoader.loadData(kind: "TwoDayWidgetRV")
            completion(TwoDayWidgetEntry(date: now, data: data, nowMin: WidgetWindows.nowMinutes(now)))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TwoDayWidgetEntry>) -> Void) {
        Task {
            let now = Date()
            let data = await TwoDayWidgetDataLoader.loadData(kind: "TwoDayWidgetRV")
            var entries = [TwoDayWidgetEntry(date: now, data: data, nowMin: WidgetWindows.nowMinutes(now))]
            // ← WidgetBoundaryScheduler: 今天列每节课下课的下一分钟一颗边界,窗口跟着前移
            //   (NEAREST_BUSY_DAY 选日下两列都不是今天 → 天然无边界, 与 Android 同语义)
            if let today = data.days.first(where: { $0.isToday }),
               data.hasTable, data.semesterStatus == .inRange {
                for at in WidgetWindows.boundaryDates(courses: today.courses, timeJson: today.timeJson, from: now) {
                    entries.append(TwoDayWidgetEntry(date: at, data: data, nowMin: WidgetWindows.nowMinutes(at)))
                }
            }
            // 次日 00:05 换日 (今天/明天窗口滚动)
            let cal = DateUtils.isoCalendar
            let tomorrow = cal.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(3600)
            let refresh = cal.date(bySettingHour: 0, minute: 5, second: 0, of: tomorrow) ?? tomorrow
            WidgetArchiveLog.append(kind: "TwoDayWidgetRV", family: context.family.description, result: "success")
            completion(Timeline(entries: entries, policy: .after(refresh)))
        }
    }

}

// MARK: - View ← renderTwoDayRegular

struct TwoDayWidgetEntryView: View {
    @Environment(\.widgetFamily) var widgetFamily
    @Environment(\.colorScheme) private var widgetColorScheme
    let entry: TwoDayWidgetEntry

    var body: some View {
        let data = entry.data
        let isDark = effectiveWidgetIsDark(themeMode: data.themeMode, snapshotIsDark: data.isDark, envScheme: widgetColorScheme)
        let s = resolveWidgetScheme(themeKey: data.themeKey, isDark: isDark)
        let prefs = AppPrefs.shared
        let colorless = prefs.isWidgetColorless()
        let displayMode = prefs.getDisplayMode()
        let showDate = prefs.isShowDate()
        // issue#26: widget 全局一档别名开关
        let useAlias = prefs.isWidgetUseAlias()
        let tier = WidgetLayoutTier(family: widgetFamily)
        // 时间窗只作用在「今天」列 (WidgetWindows.twoDay 内按 day.isToday 判定)
        let nowMin = entry.nowMin

        return GeometryReader { proxy in
            let wins = Self.twoDayWindows(data: data, heightDp: proxy.size.height, tier: tier,
                                          nowMin: nowMin)
            VStack(alignment: .leading, spacing: 0) {
                if !data.hasTable || data.days.isEmpty {
                    Text(L10n.format("widget_create_schedule"))
                        .font(.system(size: 15))
                        .foregroundColor(s.onSurface)
                    Spacer(minLength: 0)
                } else if data.semesterStatus != .inRange {
                    // ★ 学期外: 状态标题 + 提示行, 不渲染课程
                    Text(data.semesterStatus == .beforeStart
                         ? L10n.format("semester_not_started")
                         : L10n.format("semester_ended"))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(s.onSurface)
                        .padding(.bottom, 6)
                    Text(L10n.format("today_semester_out_hint"))
                        .font(.system(size: 11))
                        .foregroundColor(s.onSurfaceVariant)
                    Spacer(minLength: 0)
                } else {
                    // ★ 左右两栏: 每天一列, 中间竖直分隔 (id 用列序 — 调休映射下
                    //   两列 dayOfWeek 可能相同, 不能作 identity)
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(Array(data.days.enumerated()), id: \.offset) { colIdx, day in
                            TwoDayColumn(day: day, scheme: s, colorless: colorless,
                                         displayMode: displayMode, showDate: showDate,
                                         isLast: colIdx == data.days.count - 1,
                                         window: colIdx < (wins?.count ?? 0) ? wins?[colIdx] : nil,
                                         useAlias: useAlias)
                        }
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(s.bg)
        .widgetURL(URL(string: "sleepy://open"))
    }

    /// ← TwoDayWidget.computeTwoDayWindows: 每列独立窗口; 无课表/学期外/两天全空 → nil
    static func twoDayWindows(data: TwoDayData, heightDp: CGFloat, tier: WidgetLayoutTier,
                              nowMin: Int?) -> [WidgetWindowCore.WindowResult]? {
        guard data.hasTable, !data.days.isEmpty,
              data.semesterStatus == .inRange,
              data.days.contains(where: { !$0.courses.isEmpty }) else { return nil }
        return WidgetWindows.twoDay(days: data.days, heightDp: heightDp, tier: tier, nowMin: nowMin)
    }
}

private struct TwoDayColumn: View {
    let day: DayData
    let scheme: WidgetScheme
    let colorless: Bool
    let displayMode: String
    let showDate: Bool
    let isLast: Bool
    /// 本列 FIXED 窗口;nil = 无窗口 (整列直排, 由容器裁切)
    let window: WidgetWindowCore.WindowResult?
    /// issue#26: widget 场景别名 — 透传给课程胶囊
    let useAlias: Bool

    var body: some View {
        let s = scheme
        let rows = window?.visible.map(\.row)
            ?? ConflictLayoutEngine.weekLaneRows(day.courses, timeJson: day.timeJson)

        return VStack(alignment: .leading, spacing: 0) {
            // 列标题: 今天/明天/星期 + 日期(★ showDate=false 时隐藏)
            HStack(alignment: .firstTextBaseline, spacing: 6) { // 安卓日期间隔 titleW+6dp
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(s.primary)
                if showDate {
                    Text(day.dayLabel)
                        .font(.system(size: 10))
                        .foregroundColor(s.onSurfaceVariant)
                }
            }
            .padding(.top, 0.5)  // 安卓标题基线 listTop+12 (字形顶≈+3.5)
            .padding(.bottom, 5) // 课程起点 listTop+20

            if day.courses.isEmpty {
                Text(L10n.format("no_course"))
                    .font(.system(size: 11))
                    .foregroundColor(s.onSurfaceVariant)
            } else if window?.status == .allDone {
                // ← ab27230c: 全上完 → 整列留空, 「无课程」文案不残留, 只剩列底「+0」
                EmptyView()
            } else {
                // ★ WidgetKit 不支持 ScrollView 归档: 窗口外的课由列底「+N」报告
                VStack(spacing: WidgetRowGeometry.twoDayRowGap) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        WidgetCourseRowView(row: row, allCourses: day.courses, timeJson: day.timeJson,
                                            scheme: s, colorless: colorless,
                                            displayMode: displayMode, useAlias: useAlias,
                                            rowHeight: WidgetRowGeometry.twoDayRowH,
                                            fontSizeSp: 10, laneFontSizeSp: 9)
                    }
                }
                // ← drawCourse(greyAlpha 0x99): 节假日/周末灰显整列课卡降透明度 (issue#44)
                //   strikethrough 样式在 WidgetCourseCard 文字层 (共享文件, 见接线说明)
                .opacity(day.isGrey ? 153.0 / 255.0 : 1)
            }
            Spacer(minLength: 0)
            // ← 8c0fcbea / ab27230c: 每列「+N」恒画 (含「+0」), 各列独立计数, 不可点
            WidgetFooterCapsule(
                text: window.map { WidgetWindowCore.capsuleText(hidden: $0.hiddenAheadCourses) },
                scheme: s)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // 列间竖直分隔线
        .overlay(alignment: .trailing) {
            if !isLast {
                Rectangle()
                    .fill(s.onSurfaceVariant.opacity(0.125))  // 0x20 alpha ≈ 12.5%
                    .frame(width: 1)
                    .padding(.trailing, -5)
            }
        }
    }

    private var title: String {
        if day.isToday { return L10n.format("today_today") }
        if day.isTomorrow { return L10n.format("tomorrow") }
        return day.dayName
    }
}

struct TwoDayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TwoDayWidgetRV", provider: TwoDayWidgetProvider()) { entry in
            TwoDayWidgetEntryView(entry: entry)
        }
        .configurationDisplayName(L10n.format("widget_twoday_label"))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
