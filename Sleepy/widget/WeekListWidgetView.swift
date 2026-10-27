// WeekListWidgetView.swift — ← WeekListWidget.kt + WidgetBitmapRenderers.renderWeekList
// 本周课表(列表) widget — 7 列日列(列数随 visibleDays)。
// 列卡片: primaryContainer(今天) / surfaceContainer(其他), 14dp 圆角。
// 课程: 彩色胶囊背景 + 常规字重课名 (安卓 L899 Typeface.DEFAULT; bold 的是 chip 文字)。
//
// 对齐 Android 定稿语义 (2c937b11 / 895fe72f / ede839af):
//  1. SMALL 档 = 最近 3 天「列脸」(renderWeekListCompact → 换列后走同一常规排版),
//     不再是两行纯文本; 无课日不再残留日期胶囊;
//  2. 每列 FIXED 窗口: availH = hDp − 58 − statusH, 行高 19 / 行距 0 / 页脚预留 19,
//     截断时列底画「+N」(未截断不画,与 TwoDay 的「恒画」口径不同 —— 安卓即如此);
//  3. 学期外顶部全宽状态行占位 16dp,同时从列可用高里扣掉。
//
// v1.0.61 对齐 (F125, ← WeekListWidget.kt L183-206 + Receiver 闸门 L60-64):
//  4. 装载器走 WidgetWeekDataLoader.resolve(kind) — 日期 = source.dateFor (钳制周=1
//     预习 / NEAREST_BUSY_DAY 跳周都随 display 走);
//  5. 取课走 source.coursesOn(调休按日期反向查, 审计 [A]-1 修复): AFTER_END 清空仅当
//     非补班日, 任一列有课 → 状态改写 IN_RANGE (Android L205);
//     旧 effectiveDayOfWeek 正向映射为错位口径, 已弃用;
//  6. isGrey = HolidayManager.shouldGrey(date, tableId) 灰显 0.6 alpha +
//     「strikethrough」样式 (Android renderWeekListRegular L871-920);
//  7. compactWindow = WidgetCompactWindow.build(...) 三天真实日期窗口 (2026-09-15 用户令,
//     Android L199-205), SMALL 档日列 = compactShownDays 单一口径 (§9.1);
//  8. statusH 闸门 = semesterStatus != IN_RANGE || weekDisplayStatus != NORMAL
//     (Android L60-61); 今天列高亮 = isDateToday(day.date) (Android L828, 展示周≠自然周
//     时按星期判会错列)。
// forceScroll 条带 (WidgetScrollStore/ScrollStripService) = Android 专有宿主,
// iOS 由列底「+N」窗口截断等价承担 (平台差异, 非缺陷; compactFace 不叠窗口的
// Android 分支在 iOS 统一走窗口, 否则小档溢出无处报告)。

import SwiftUI
import WidgetKit

struct WeekListWidgetEntry: TimelineEntry {
    let date: Date
    let data: WeekData
}

// MARK: - loadData ← WeekListWidgetReceiver.Companion.loadDataSync (v1.0.61 对齐, F125)

/// WeekList 专用装载器 — 逐行对齐 Android companion:
/// WidgetWeekDataLoader.resolve(kind) → 展示周=display.targetWeek、日期=source.dateFor
/// (学期前钳制周=1 预习 / NEAREST_BUSY_DAY 跳周都随 display 走) → AFTER_END 课程清空
/// (L188) → 调休映射 effectiveDayOfWeek 取课 (L187) → isGrey (L195) →
/// compactWindow 三天真实日期窗口 (L199-205) → weekDisplayStatus (L206)。
/// Android runBlocking → iOS async (TimelineProvider completion 允许异步回调),
/// 与 TwoDayWidgetDataLoader 同模式; WeekView 共用本装载器
/// (← WeekViewWidget.kt L186 注释「与 WeekListWidget.loadDataSync 完全一致」)。
enum WeekListWidgetDataLoader {

    static func loadData(kind: String) async -> WeekData {
        let today = Date()
        let prefs = AppPrefs.shared
        let isDark = prefs.isDarkMode()
        let themeKey = prefs.getThemeKey()
        let themeMode = prefs.getThemeMode()
        let fallback = WeekData(days: [], hasTable: false, isDark: isDark,
                                themeKey: themeKey, themeMode: themeMode)
        guard let source = await WidgetWeekDataLoader.resolve(kind),
              let repo = WidgetLoader.makeRepo() else { return fallback }
        let table = source.table
        let status = source.display.semesterStatus
        // ← Android L183-197: 日期=source.dateFor(周1预习/跳周随 display), 取课=source.coursesOn
        // (调休按日期反向查 — 补班日=source 星期的课并按 source 日反解周次, 放假日=无课;
        // AFTER_END 清空且保留补班日列, 任一列有课 → 状态改写 IN_RANGE 不画状态行)。
        // 旧版 effectiveDayOfWeek 正向映射为错位口径 (审计发现 [A]-1): 放假日列被填上
        // "挪走那天该上的课", 补班日列显示自己星期的课, 周次也不随 source 日反解。
        var days: [DayData] = []
        for dayOfWeek in 1...7 {
            let date = source.dateFor(dayOfWeek: dayOfWeek)
            let visible = source.coursesOn(date, previewBeforeStart: true)
            days.append(DayData(date: date, dayOfWeek: dayOfWeek, courses: visible,
                                timeJson: table.timeJson,
                                isGrey: await HolidayManager.shouldGrey(date, tableId: table.id)))
        }
        let effStatus = days.contains(where: { !$0.courses.isEmpty }) && status == .afterEnd ? .inRange : status
        // 最小档三天窗口 (2026-09-15 用户令): 真实日期, 上下周打通 (Android L199-205)
        let compactWindow = await WidgetCompactWindow.build(
            repo: repo, tableId: table.id, timeJson: table.timeJson,
            startDate: table.startDate, maxWeek: table.maxWeek,
            today: today, todayFirst: WidgetCompactWindowStore.isTodayFirst(kind),
            displayDate: source.display.status == .nearestBusyDay ? source.display.targetDate : nil
        )
        return WeekData(days: days, hasTable: true, isDark: isDark, themeKey: themeKey,
                        themeMode: themeMode, semesterStatus: effStatus,
                        compactWindow: compactWindow, weekDisplayStatus: source.display.status)
    }
}

struct WeekListWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> WeekListWidgetEntry {
        WidgetArchiveLog.append(kind: "WeekListWidgetRV", family: context.family.description, result: "success")
        // 占位脸不读 DB (异步装载不能同步等); 真实数据在 snapshot/timeline 到达。
        return WeekListWidgetEntry(date: Date(), data: WeekData(days: [], hasTable: false))
    }

    func getSnapshot(in context: Context, completion: @escaping (WeekListWidgetEntry) -> Void) {
        WidgetArchiveLog.append(kind: "WeekListWidgetRV", family: context.family.description, result: "success")
        Task {
            let data = await WeekListWidgetDataLoader.loadData(kind: "WeekListWidgetRV")
            completion(WeekListWidgetEntry(date: Date(), data: data))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeekListWidgetEntry>) -> Void) {
        Task {
            let now = Date()
            let data = await WeekListWidgetDataLoader.loadData(kind: "WeekListWidgetRV")
            let refresh = now.addingTimeInterval(6 * 3600)  // 半天兜底;数据变化由 App 端 reloadAllTimelines 触发
            WidgetArchiveLog.append(kind: "WeekListWidgetRV", family: context.family.description, result: "success")
            completion(Timeline(entries: [WeekListWidgetEntry(date: now, data: data)], policy: .after(refresh)))
        }
    }
}

// 星期标题(英缩写 — Android dayLabels arrayOf("", "Mon"...))
let weekDayLabels = ["", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

/// 列数过滤(决策 D5-12, 对齐 renderWeekList L238-240): visibleDays 空集回退全周防御
func shownDays(_ data: WeekData) -> [DayData] {
    let visibleDays = AppPrefs.shared.getVisibleDays()
    if visibleDays.isEmpty { return data.days }
    return data.days.filter { visibleDays.contains($0.dayOfWeek) }.sorted { $0.dayOfWeek < $1.dayOfWeek }
}

// MARK: - View ← renderWeekList

struct WeekListWidgetEntryView: View {
    @Environment(\.widgetFamily) private var widgetFamily
    @Environment(\.colorScheme) private var widgetColorScheme
    let entry: WeekListWidgetEntry

    var body: some View {
        let data = entry.data
        let isDark = effectiveWidgetIsDark(themeMode: data.themeMode, snapshotIsDark: entry.data.isDark, envScheme: widgetColorScheme)
        let s = resolveWidgetScheme(themeKey: data.themeKey, isDark: isDark)
        let colorless = AppPrefs.shared.isWidgetColorless()
        // issue#26: widget 全局一档别名开关
        let useAlias = AppPrefs.shared.isWidgetUseAlias()
        let todayDow = DateUtils.todayDayOfWeek(today: Date())
        let tier = WidgetLayoutTier(family: widgetFamily)
        // 状态行占位 16dp ← Android push() L60-61:
        // semesterStatus != IN_RANGE || weekDisplayStatus != NORMAL (自动跳最近有课日时同样抬列顶)
        let statusH: CGFloat = (data.semesterStatus != .inRange || data.weekDisplayStatus != .normal) ? 16 : 0

        return GeometryReader { proxy in
            // ← renderWeekList L786: SMALL 变体 + 容器 <150dp 才走 compact 脸,
            // 容器被拖大 ≥150dp → 内部升档回全量排版 (iPad/大屏手机 systemSmall 实测
            // ≥150pt 时与安卓平板同口径显示全周列)。
            let isCompact = widgetFamily == .systemSmall && proxy.size.width < 150
            let days = isCompact
                ? WidgetCompactHelpers.compactShownDays(data, AppPrefs.shared.getVisibleDays(), todayDow)
                : shownDays(data)
            // ← push() L62-64 闸门: hasTable && 列非空 && 任一天有课 (数据层 days 全量口径,
            // 非过滤后 shownDays — 安卓 any 读 data.days)。学期外不在此设闸:
            // BEFORE_START 钳周=1 预习照常叠窗口截断; AFTER_END 课程清空 → any=false 自然不成窗
            // (旧 iOS 版误用 semesterStatus == .inRange 设闸, 学期前预览周第 1 周课多时无 +N 截断)。
            let wins = (data.hasTable && !days.isEmpty && data.days.contains { !$0.courses.isEmpty })
                ? WidgetWindows.weekList(days: days, heightDp: proxy.size.height, tier: tier,
                                         statusH: statusH)
                : nil
            Group {
                if !data.hasTable || days.isEmpty {
                    Text(L10n.format("widget_create_schedule"))
                        .font(.system(size: 15))
                        .foregroundColor(s.onSurface)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    VStack(spacing: 0) {
                        // ★ 学期外: 顶部全宽状态行(学期前=第1周课照常预习 / 学期后=课程已清空)
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
                                WeekListDayColumn(day: day, scheme: s, colorless: colorless,
                                                  // ← renderWeekListRegular L828: 今天高亮按真实日期判
                                                  // (展示周≠自然周 / compactWindow 跨周时按星期会错列)
                                                  isToday: DateUtils.isDateToday(day.date),
                                                  useAlias: useAlias,
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

private struct WeekListDayColumn: View {
    let day: DayData
    let scheme: WidgetScheme
    let colorless: Bool
    let isToday: Bool
    /// issue#26: widget 场景别名 — 课名展示名
    let useAlias: Bool
    /// 本列 FIXED 窗口;nil = 无窗口 (学期外/无课表 → 整列直排)
    let window: WidgetWindowCore.WindowResult?

    var body: some View {
        let s = scheme
        // 窗口只装得下前 N 门, 其余折成列底「+N」(← computeWeekListWindows)
        let visible: [CourseEntity]
        if let window = window {
            visible = window.visible.flatMap { $0.row.courses }
        } else {
            visible = day.courses
        }
        let footerText: String? = window.flatMap { $0.footer ? "+\($0.hiddenAheadCourses)" : nil }
        // 节假日/周末灰显 ← renderWeekListRegular L871-920: 文本/胶囊 alpha 153/255≈0.6,
        // 「strikethrough」样式再叠删除线 (灰显列本身由 loader isGrey 驱动)
        let grey = day.isGrey
        let greyAlpha: Double = grey ? 0.6 : 1.0
        let strikethrough = grey && AppPrefs.shared.getHolidayStyle() == "strikethrough"

        return VStack(alignment: .center, spacing: 0) {
            // 星期标题
            Text(weekDayLabels[day.dayOfWeek])
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(isToday ? s.onPrimaryContainer : s.onSurface)
                .opacity(greyAlpha)
                .padding(.top, 1)   // 安卓标题基线 colTop+12 (字形顶≈+4)
                .padding(.bottom, 11) // chip 顶 colTop+26

            if !day.courses.isEmpty {
                // 课程数量 chip — 安卓 chip 文字继承标题 BOLD (L873 设 bold 后直到 L899
                // 才重置, chip 在 L889 落在这段里); 宽 = 文本长度*6+12dp、高 14dp 固定公式
                // (L884-885), 非自然字宽 — 逐字符 6dp 槽位。
                let chipText = "\(day.courses.count) 门"
                Text(chipText)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(s.onSurfaceVariant)
                    .opacity(greyAlpha)
                    .frame(width: CGFloat(chipText.count) * 6 + 12, height: 14)
                    .background(s.surfaceVariant.opacity(greyAlpha))
                    .cornerRadius(50)
                    .padding(.bottom, 6)

                // 课程列表 — 每门课带颜色胶囊背景
                VStack(spacing: 3) {
                    ForEach(visible, id: \.id) { course in
                        // ★ 课程颜色背景 (对齐 WeekGrid 风格) — 统一入口 CourseColorUtil (决策 D3)
                        // issue#22: 同名课程多地点 — 用 day.courses 同 groupId 全行, 支持 AUTO/CUSTOM 按行判
                        let bgColor = CourseColorUtil.pickCourseColorSwiftUIWithGroupRows(
                            course, groupRows: day.courses.filter { $0.groupId == course.groupId },
                            isDark: s.isDark, neutralColor: s.secondaryContainer, colorless: colorless)
                        Text(CourseDisplayUtil.displayName(course, useAlias))
                            // 紧贴 Text  receiver 调 Text 级重载(ios 13+, 默认实线), 显式
                            // color: nil = 删除线随正文主色 —— 与修复前行为逐字相同;
                            // 挂在 View 链上只会命中 iOS16 pattern 重载(extension 不可用)。
                            .strikethrough(strikethrough, color: nil)
                            // 安卓课名走 Typeface.DEFAULT 常规字重 (L899 在课程循环前重置),
                            // 与 drawCourse 的 BOLD 卡面不同 — 本渲染器是内联循环, 不继承 bold。
                            .font(.system(size: 9))
                            .foregroundColor(CourseColorUtil.textColorOn(bg: bgColor, isDark: s.isDark,
                                                                         onSurface: s.onSurface))
                            .opacity(greyAlpha) // 安卓 applyAlpha(文字色, 153/255) (L917-920)
                            .lineLimit(1)
                            .padding(.horizontal, 2) // 文字距胶囊左/右 2dp (安卓 x+coursePad+2, 截断预算 colW-10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: 16)
                            .background(bgColor.opacity(greyAlpha))
                            .cornerRadius(4)
                            .padding(.horizontal, 3) // 胶囊两侧内缩 3dp (安卓 x+3 ~ x+colW-3)
                    }
                    // 列底「+N」短页脚 (仅窗口真的截断时画 ← footerByCol; 安卓页脚不随灰显降 alpha)
                    if let footerText = footerText {
                        Text(footerText)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(s.onSurfaceVariant)
                            .frame(maxWidth: .infinity)
                            .frame(height: 19)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // 列背景: 今天 primaryContainer / 其他 surfaceContainer, 14dp 圆角
        .background(isToday ? s.primaryContainer : s.surfaceContainer)
        .cornerRadius(14)
    }
}

struct WeekListWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WeekListWidgetRV", provider: WeekListWidgetProvider()) { entry in
            WeekListWidgetEntryView(entry: entry)
        }
        .configurationDisplayName(L10n.format("widget_week_list_label"))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        // iOS 17+ 系统边距关闭, 维持既有自管 padding 布局 (iOS 16 及以下 no-op)
        .contentMarginsDisabled()
    }
}
