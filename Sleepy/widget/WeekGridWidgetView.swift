// WeekGridWidgetView.swift — ← WeekGridWidgetProvider.kt (v19 网格 + v21 竖排课名)
// 本周课表(网格) widget — 视觉复刻 CourseTableView: 圆角卡片 + gap + today 高亮 + 课名竖排居中。
//
// Canvas bitmap → SwiftUI 网格(平台差异表#5);布局参数逐项对齐:
// outerPad 6 / headH 56 / timeW 40 / gapH 1.5 / gapW 2.5 / 卡片圆角 10 / 容器圆角 18。
// v21 竖排(直书): token 化课名 — CJK 直立 / Latin run≥2 整组旋转90° / 标点按方案A'/B。

import SwiftUI
import WidgetKit

struct WeekGridWidgetEntry: TimelineEntry {
    let date: Date
    let data: WeekData
}

struct WeekGridWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> WeekGridWidgetEntry {
        WidgetArchiveLog.append(kind: "WeekGridWidgetV19", family: context.family.description, result: "success")
        // 占位脸不读 DB (异步装载不能同步等); 真实数据在 snapshot/timeline 到达。
        return WeekGridWidgetEntry(date: Date(), data: WeekData(days: [], hasTable: false))
    }

    func getSnapshot(in context: Context, completion: @escaping (WeekGridWidgetEntry) -> Void) {
        WidgetArchiveLog.append(kind: "WeekGridWidgetV19", family: context.family.description, result: "success")
        Task {
            let data = await WeekGridWidgetLoader.loadWeekData(kind: "WeekGridWidgetV19")
            completion(WeekGridWidgetEntry(date: Date(), data: data))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeekGridWidgetEntry>) -> Void) {
        Task {
            let data = await WeekGridWidgetLoader.loadWeekData(kind: "WeekGridWidgetV19")
            let entry = WeekGridWidgetEntry(date: Date(), data: data)
            let refresh = Date().addingTimeInterval(6 * 3600)
            WidgetArchiveLog.append(kind: "WeekGridWidgetV19", family: context.family.description, result: "success")
            completion(Timeline(entries: [entry], policy: .after(refresh)))
        }
    }
}

// MARK: - View ← renderBitmap

struct WeekGridWidgetEntryView: View {
    let entry: WeekGridWidgetEntry
    @Environment(\.widgetFamily) private var widgetFamily
    @Environment(\.colorScheme) private var widgetColorScheme

    var body: some View {
        // iOS 26 「透明/着色」样式探测 (← WidgetBackgroundCompat): glass 态配色换白 alpha;
        // SMALL 档 Today 紧凑面与网格主体共用同一探测结果
        WidgetGlassModeContent { isGlass in
            // issue#26: SMALL 档 — 仅渲染今日紧凑面(复用 Today compact face;
            // TodayWidgetEntryView 自身再探测 glass, 嵌套探测无害)
            if widgetFamily == .systemSmall {
                WeekGridMinimumTodayFace(data: entry.data)
            } else {
                gridBody(isGlass: isGlass)
            }
        }
        .widgetURL(URL(string: "sleepy://open"))
    }

    // ← 常规/中大尺寸: 网格渲染(冲突分栏走 ConflictLayoutEngine.gridDayLanes)
    @ViewBuilder
    private func gridBody(isGlass: Bool) -> some View {
        // today 高亮铺满整个 body, 分隔线跨全列, 三行表头墨迹可越出时间列 —
        // 全部在 body 层用画布坐标绝对定位 (复刻 Android Canvas 绘制顺序)
        WeekGridBody(data: entry.data, layout: WeekGridBody.GridLayout(), isGlass: isGlass)
    }
}

// MARK: - 网格主体 ← renderBitmap 主体段

private struct WeekGridBody: View {
    /// 渲染层常量 (← dp() 同参数)
    struct GridLayout {
        let outerPad: CGFloat = 6
        let headH: CGFloat = 56
        let gapH: CGFloat = 1.5
        let gapW: CGFloat = 2.5
        /// Android: timeW = if (widgetHeaderHideTime) dp(36f) else dp(40f)
        func timeWForHideTime(_ hideTime: Bool) -> CGFloat { hideTime ? 36 : 40 }
    }

    let data: WeekData
    let layout: GridLayout
    /// iOS 26 「透明/着色」样式 (← WeekGridWidgetEntryView 探测) — glass 态配色换白 alpha
    let isGlass: Bool
    @Environment(\.colorScheme) private var widgetColorScheme

    var body: some View {
        let isDark = effectiveWidgetIsDark(themeMode: data.themeMode, snapshotIsDark: data.isDark,
                                            envScheme: widgetColorScheme)
        let s = resolveWidgetScheme(themeKey: data.themeKey, isDark: isDark, isGlass: isGlass)
        let colorless = AppPrefs.shared.isWidgetColorless()
        let todayDow = DateUtils.todayDayOfWeek(today: Date())
        // issue#22: 同名课程多地点 — 跨天汇总 course 全集, 传取色入口做 AUTO/CUSTOM 按行判
        let allCourses = data.days.flatMap { $0.courses }
        // issue#26: widget 全局一档别名开关 — 字号预算与绘制用同一个名字
        let useAlias = AppPrefs.shared.isWidgetUseAlias()

        // ── 数据 ── (← Android: allSlots = timeSlotsFor(timeJson); slots = allSlots.take(maxNode))
        let timeJson = data.days.first?.timeJson ?? ""
        let allSlots = TimeTableUtils.timeSlotsFor(timeJson: timeJson)
        let maxNode = max((allCourses.map { $0.startNode + $0.step - 1 }.max() ?? allSlots.count), 1)
        let slots = Array(allSlots.prefix(maxNode))
        let sortedDays = data.visibleDays.sorted()
        let dayCount = min(max(sortedDays.count, 1), 7)

        // ── 表头设置 (v1.0.60) ──
        let hideTime = AppPrefs.shared.isPeriodHeaderHideTime()
        let headerLayout = AppPrefs.shared.getPeriodHeaderLayout()
        let headerStyle = AppPrefs.shared.getPeriodHeaderStyle()
        let showX = AppPrefs.shared.isPeriodHeaderShowX()
        let showSeparators = AppPrefs.shared.isGridShowSeparators()
        let longBreakSpacing = AppPrefs.shared.isGridLongBreakSpacing()

        VStack(spacing: 0) {
            // ★ 空状态: 无课表时占位提示, 不渲染空白网格
            // ★ 学期后课程被清空 → 落到这分支; 学期状态文案优先于"去创建课表"
            if !data.hasTable || data.days.isEmpty || data.days.allSatisfy({ $0.courses.isEmpty }) {
                VStack(spacing: 4) {
                    if data.semesterStatus != .inRange {
                        Text(data.semesterStatus == .beforeStart
                             ? L10n.format("semester_not_started")
                             : L10n.format("semester_ended"))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(s.onSurface)
                        Text(L10n.format("today_semester_out_hint"))
                            .font(.system(size: 11))
                            .foregroundColor(s.onSurfaceVariant)
                    } else {
                        Text(L10n.format("widget_create_schedule"))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(s.onSurface)
                        Text(L10n.format("widget_open_sleepy"))
                            .font(.system(size: 11))
                            .foregroundColor(s.onSurfaceVariant)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { geo in
                    let ctx = Self.makeContext(
                        geo: geo, layout: layout, slots: slots,
                        allCourses: allCourses, maxNode: maxNode, dayCount: dayCount,
                        hideTime: hideTime, longBreakSpacing: longBreakSpacing,
                        timeJson: timeJson, useAlias: useAlias,
                        headerLayout: headerLayout, headerStyle: headerStyle, showX: showX)
                    let timeW = ctx.timeW
                    let headH = layout.headH
                    let dayW = ctx.dayW

                    // ★ 单一画布 (← Android renderBitmap 一张位图): header 与 body 同
                    //   原点、同 ctx.colX 几何源。此前两行分属 VStack 两个独立布局盒,
                    //   header 盒被重新居中 → 列头恒右偏 ~6pt 与课程列错位
                    //   (用户 2026-10-28「网格视图纵向没对齐」)。
                    ZStack(alignment: .topLeading) {
                        // ── Header (Day labels) ──
                        ZStack(alignment: .topLeading) {
                            // time column 角落 (x=0 宽 timeW — 与 body 时间列同位)
                            ZStack {
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(s.surface)
                                // ★ 学期前(课照常显示供预习): 角落画学期状态, 用户知道现在学期没开始
                                if data.semesterStatus == .beforeStart {
                                    Text(L10n.format("semester_not_started"))
                                        .font(.system(size: min(headH * 0.16, 9), weight: .regular))
                                        .foregroundColor(s.onSurfaceVariant)
                                        .minimumScaleFactor(0.6)
                                        .lineLimit(1)
                                        .padding(.horizontal, 2)
                                }
                            }
                            .frame(width: timeW, height: headH)
                            ForEach(Array(sortedDays.enumerated()), id: \.element) { idx, dow in
                                let isToday = dow == todayDow
                                let dayData = data.days.first { $0.dayOfWeek == dow }
                                let count = dayData?.courses.count ?? 0
                                // showDate → 短日期; 否则课程数 / —
                                let sub: String = {
                                    if data.showDate, let dd = dayData { return DateUtils.shortDate(dd.date) }
                                    return count > 0 ? "\(count)" : "—"
                                }()

                                VStack(spacing: 2) {
                                    // day name 字号 = headH * 0.24 cap 13 floor 9
                                    Text(DateUtils.localizedDay(dow))
                                        .font(.system(size: min(max(headH * 0.24, 9), 13), weight: .bold))
                                        .foregroundColor(isToday ? s.primary : s.onSurface)
                                        .minimumScaleFactor(0.7)
                                    // date or count 字号 = headH * 0.18 cap 10 floor 7
                                    Text(sub)
                                        .font(.system(size: min(max(headH * 0.18, 7), 10)))
                                        .foregroundColor(s.onSurfaceVariant)
                                        .minimumScaleFactor(0.7)
                                }
                                .frame(width: dayW, height: headH)
                                .background(isToday ? s.primaryContainer : s.surface)
                                .cornerRadius(14)
                                .offset(x: ctx.colX(idx))
                            }
                        }

                        // ── Body: today 高亮 → 分隔线 → 时间列 → 日列 (画布坐标绝对定位) ──
                        //   body 层 x 以 0 起, 整体下沉 headH (与 header 同原点同几何源)
                        ZStack(alignment: .topLeading) {
                            // today 背景铺满整列 ← Android drawRect(colX, bodyTop, colX+dayW, +bodyH) α40
                            ForEach(Array(sortedDays.enumerated()), id: \.element) { idx, dow in
                                if let dayData = data.days.first(where: { $0.dayOfWeek == dow }),
                                   DateUtils.isDateToday(dayData.date) {
                                    Rectangle()
                                        .fill(s.primaryContainer.opacity(40.0 / 255.0))
                                        .frame(width: dayW, height: ctx.bodyH)
                                        .offset(x: ctx.colX(idx))
                                }
                            }

                            // 额外分隔线 (isGridShowSeparators, ← Android showSeparators 段)
                            if showSeparators {
                                WeekGridSeparators(ctx: ctx, color: s.surfaceVariant)
                            }

                            // 时间列 (色带档仍画时间标签 — 日头保留 ← Android 分支顺序)
                            ForEach(1...maxNode, id: \.self) { i in
                                WeekGridTimeCell(index: i,
                                                 slot: i <= slots.count ? slots[i - 1] : nil,
                                                 ctx: ctx,
                                                 headerLayout: headerLayout,
                                                 headerStyle: headerStyle,
                                                 hideTime: hideTime, showX: showX,
                                                 scheme: s)
                            }

                            // 日列 (逐列裁剪 ← 位图列宽; 三行表头不裁, 墨迹可越出时间列)
                            ForEach(Array(sortedDays.enumerated()), id: \.element) { idx, dow in
                                if let dayData = data.days.first(where: { $0.dayOfWeek == dow }) {
                                    Group {
                                        if ctx.colorBandMode {
                                            WeekGridColorBandColumn(dayData: dayData, ctx: ctx,
                                                                    scheme: s, colorless: colorless,
                                                                    allCourses: allCourses)
                                        } else {
                                            WeekGridDayColumn(dayData: dayData, ctx: ctx,
                                                              scheme: s, colorless: colorless,
                                                              allCourses: allCourses, useAlias: useAlias)
                                        }
                                    }
                                    .frame(width: dayW, height: ctx.bodyH, alignment: .topLeading)
                                    .clipped()
                                    .offset(x: ctx.colX(idx))
                                }
                            }
                        }
                        // body 整组下沉 headH — 组内坐标仍「body 顶=0」(rowTop/colX 原语义),
                        // 画布级只加 y 偏移; header 组无尺寸 frame (子视图绝对 offset),
                        // 不存在被重新居中的布局盒 → 两层永不横向分叉
                        .offset(y: headH)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                    // 画布显式撑满 — offset 不扩父视图布局尺寸, 缺此 frame 时
                    // ZStack 高=bodyH → padding 后被 GeometryReader 垂直居中 (下坠28pt)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(layout.outerPad)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sleepyWidgetBackground { s.surfaceContainer }  // bgContainer
        .cornerRadius(18)
        .widgetURL(URL(string: "sleepy://open"))
    }
}

// MARK: - 几何上下文 ← renderBitmap 布局段 (含 §4.4 长课间薄带)

extension WeekGridBody {
    struct GridContext {
        let canvasW: CGFloat
        let bodyH: CGFloat
        let timeW: CGFloat
        let dayW: CGFloat
        let slotH: CGFloat
        let maxNode: Int
        let dayCount: Int
        let gapH: CGFloat
        let gapW: CGFloat
        let bandH: CGFloat
        let mealBreakAfterRows: Set<Int>
        /// §4.4 降级阶梯末档: slotH < 9 → 色带模式 (无文字非空白)
        let colorBandMode: Bool
        /// v20b: 全表最小理想字号 (← unifiedCharSize)
        let unifiedCharSize: CGFloat
        /// three_line 整列共享自适应字号 ← columnSharedFont (legacy 为 nil)
        let headerFont: PeriodHeaderAdaptiveFont?

        /// colX(idx) = timeW + gapW + idx*(dayW+gapW) — body 层 x 以 0 起 (padding 外提)
        func colX(_ idx: Int) -> CGFloat {
            timeW + gapW + CGFloat(idx) * (dayW + gapW)
        }
        /// rowTop(rowIndex) ← weekGridRowTopPx (body 顶=0): 行高刚性恒 slotH,
        /// 越过其上方的餐段后整体下移 bandH×count
        func rowTop(_ index: Int) -> CGFloat {
            let crossed = mealBreakAfterRows.count { $0 + 1 <= index }
            return gapH + CGFloat(index) * (slotH + gapH) + CGFloat(crossed) * bandH
        }
        /// spanHeightPx ← Android: rows 夹 maxNode; 餐段带不折进卡高 (行高刚性, 卡被带劈开)
        func spanH(_ index: Int, _ step: Int) -> CGFloat {
            let rows = min(index + step, maxNode) - index
            return max(slotH * CGFloat(rows) + gapH * CGFloat(max(rows - 1, 0)), 1)
        }
        /// 分隔线用: 已越过 (band 上缘 < boundary) 的餐段带数
        func crossedBands(_ boundary: Int) -> Int {
            mealBreakAfterRows.count { $0 + 1 < boundary }
        }
        /// 餐段薄带 ← mealBreakBands: row !in 0 until maxNode-1 跳过
        var mealBands: [(start: CGFloat, end: CGFloat)] {
            mealBreakAfterRows.sorted().compactMap { row in
                guard row >= 0, row < maxNode - 1 else { return nil }
                return (rowTop(row) + slotH, rowTop(row + 1))
            }
        }
        var bodyBottom: CGFloat { bodyH - gapH }
    }

    /// 系统字体缩放 ← Android configuration.fontScale (preferredFont(.body) 默认 17pt)
    static func widgetFontScale() -> CGFloat {
        let p = UIFont.preferredFont(forTextStyle: .body).pointSize
        return p > 0 ? p / 17.0 : 1
    }

    static func makeContext(geo: GeometryProxy, layout: GridLayout,
                            slots: [TimeTableUtils.TimeSlotRow],
                            allCourses: [CourseEntity], maxNode: Int, dayCount: Int,
                            hideTime: Bool, longBreakSpacing: Bool,
                            timeJson: String, useAlias: Bool,
                            headerLayout: String, headerStyle: String, showX: Bool) -> GridContext {
        let bodyW = geo.size.width - layout.outerPad * 2
        // ← weekGridBodyGeomPx: bodyH = (h − pad×2 − headH) 下限 20 (Int 域 = floor)
        let bodyH = max(floor(geo.size.height - layout.outerPad * 2 - layout.headH), 20)
        let timeW = layout.timeWForHideTime(hideTime)
        let gapH = layout.gapH
        let gapW = layout.gapW
        // ← mealBreakBandPx = 24 × density × fontScale (dp→pt 直读)
        let bandH: CGFloat = 24 * widgetFontScale()

        // 长课间薄带 ← mealBreakAfterRows: 开关 ON 且探测器命中;
        // displayIndex = slots.indexOfLast{nodeEnd==leftNode}, 限 0..<slots.lastIndex (同 Android)
        let configuredRows = TimeTableUtils.parseTimeSlotRows(timeJson)
        var mealBreakAfterRows: Set<Int> = []
        if longBreakSpacing {
            for detected in MealBreakDetector.detect(timeJson: timeJson, courses: allCourses) {
                guard detected.afterRowIndex >= 0, detected.afterRowIndex < configuredRows.count
                else { continue }
                let leftNode = configuredRows[detected.afterRowIndex].node
                guard let idx = slots.lastIndex(where: { $0.node == leftNode }),
                      idx >= 0, idx < slots.count - 1 else { continue }
                mealBreakAfterRows.insert(idx)
            }
        }
        let mealCount = mealBreakAfterRows.count { $0 >= 0 && $0 < maxNode - 1 }
        // slotH ← weekGridBodyGeomPx: 带厚先从 bodyH 扣, 余高均分等高行 (Int 域 floor)
        let slotH = max(floor(bodyH - gapH * CGFloat(maxNode + 1)
                              - bandH * CGFloat(mealCount)) / CGFloat(max(maxNode, 1)), 3)
        let dayW = max((bodyW - timeW - gapW * CGFloat(dayCount + 1)) / CGFloat(dayCount), 20)
        // ← weekGridColorBand: slotH < 9dp (px 域等价: slotHPx < 9×density → slotH(dp) < 9)
        let colorBandMode = slotH < 9

        // v20b: 全表最小理想字号 (色带档无文字可量 → 不进入)
        let unifiedCharSize: CGFloat = colorBandMode ? 11 : computeUnifiedCharSize(
            allCourses: allCourses, maxNode: maxNode, slotH: slotH, gapH: gapH,
            dayW: dayW, useAlias: useAlias)

        // three_line 整列共享字号 ← columnSharedFont
        let headerFont: PeriodHeaderAdaptiveFont? = headerLayout == "three_line"
            ? Self.columnSharedFont(slots: slots, timeW: timeW, slotH: slotH,
                                    headerStyle: headerStyle, showX: showX)
            : nil

        return GridContext(canvasW: geo.size.width, bodyH: bodyH, timeW: timeW, dayW: dayW,
                           slotH: slotH, maxNode: maxNode, dayCount: dayCount,
                           gapH: gapH, gapW: gapW, bandH: bandH,
                           mealBreakAfterRows: mealBreakAfterRows,
                           colorBandMode: colorBandMode, unifiedCharSize: unifiedCharSize,
                           headerFont: headerFont)
    }

    /// v20b 字号统一到「全表最小理想值」— 每卡 cardH/unitH 理想字号, 全表取 min。
    /// nameCeil = min(headH(56)*0.24 cap 13, (dayW−8)*0.92), 下限 11 (← Android 同式)
    static func computeUnifiedCharSize(allCourses: [CourseEntity], maxNode: Int,
                                       slotH: CGFloat, gapH: CGFloat, dayW: CGFloat,
                                       useAlias: Bool) -> CGFloat {
        let nameCeil = min(min(56 * 0.24, 13), max(dayW - 8, 8) * 0.92)
        var minIdeal = nameCeil
        for course in allCourses {
            let startIdx = max(course.startNode - 1, 0)
            let step = min(max(course.step, 1), max(maxNode - startIdx, 1))
            let cardH = max(slotH * CGFloat(step) + gapH * CGFloat(max(step - 1, 0)), 1)
            let hasRoom = !course.room.isBlank
            let availCardH = max(cardH - 8, 0)  // unifiedPad×2 = 4×2
            let roomReserve = hasRoom ? min(11 * 0.7, availCardH * 0.35) : 0
            let nameAvailH = max(availCardH - roomReserve, 0)
            let tokens = VerticalNameTokenizer.tokenize(
                CourseDisplayUtil.displayName(course, useAlias))
            let unitH = max(VerticalNameTokenizer.unitHeight(tokens), 1)
            let ideal = min(max(nameAvailH / unitH, 11), nameCeil)
            if ideal < minIdeal { minIdeal = ideal }
        }
        return minIdeal
    }

    /// columnSharedFont ← Android: 逐行基准字号(11/12sp)实测墨迹, 整列统一自适应
    static func columnSharedFont(slots: [TimeTableUtils.TimeSlotRow], timeW: CGFloat,
                                 slotH: CGFloat, headerStyle: String,
                                 showX: Bool) -> PeriodHeaderAdaptiveFont {
        let rows = slots.map { slot -> PeriodHeaderAdaptiveFont.RowConstraint in
            // WeekGrid 的 TimeSlot 恒 nodeStart==nodeEnd (widget timeSlotsFor) → showX 时 fullLabel
            let label = showX ? PeriodHeaderFormatter.fullLabel(slot.node, headerStyle)
                              : PeriodHeaderFormatter.range(slot.node, slot.node, headerStyle)
            let startW = VerticalNameTokenizer.textWidth(slot.start, size: 11, bold: false)
            let endW = VerticalNameTokenizer.textWidth(slot.end, size: 11, bold: false)
            let labelW = VerticalNameTokenizer.textWidth(label, size: 12, bold: true)
            let timeMaxW = max(startW, endW)
            return PeriodHeaderAdaptiveFont.RowConstraint(
                inkWidthSp: timeMaxW + labelW, timeMaxWidthSp: timeMaxW, labelWidthSp: labelW)
        }
        return PeriodHeaderAdaptiveFont.forColumn(
            cardWidthSp: max(timeW - 2 * 3, 1),
            // 整列统一字号取最矮行 — 行高刚性恒 slotH → 单一卡高
            cardHeightSp: max(slotH - 2 * 3, 1),
            rows: rows)
    }
}

// MARK: - 时间格 ← legacy 两行 / three_line 三行卡片

private struct WeekGridTimeCell: View {
    /// 节次序号 (1 起)
    let index: Int
    let slot: TimeTableUtils.TimeSlotRow?
    let ctx: WeekGridBody.GridContext
    let headerLayout: String
    let headerStyle: String
    let hideTime: Bool
    let showX: Bool
    let scheme: WidgetScheme

    var body: some View {
        // 透明满画布定位层 — 三行卡片墨迹可越出 timeW (位图无逐列裁剪)
        ZStack(alignment: .topLeading) {
            if headerLayout == "three_line", let slot = slot {
                threeLineContent(slot)
            } else {
                legacyContent
            }
        }
        .frame(width: ctx.canvasW, height: ctx.bodyH, alignment: .topLeading)
    }

    // ── legacy 两行: 节次号 (样式化标签) + "start-end" 时间串 ──
    @ViewBuilder
    private var legacyContent: some View {
        let rowY = ctx.rowTop(index - 1)
        let rowH = ctx.slotH
        let periodSize = min(max(rowH * 0.40, 8), 13)
        // legacy → 阿拉伯数字; 其余样式 → formatter.label
        let periodText = headerLayout == "legacy" ? "\(index)"
            : PeriodHeaderFormatter.label(index, headerStyle)
        // 基线 cy = rowY + rowH/2 + textSize×0.35
        let cy = rowY + rowH / 2 + periodSize * 0.35
        ZStack(alignment: .topLeading) {
            baselineCentered(periodText, size: periodSize, bold: true,
                             color: scheme.onSurface, cx: ctx.timeW / 2, baseline: cy)
            if let slot = slot, rowH > 18, !hideTime {
                let timeSize = min(max(rowH * 0.20, 4), 7)
                baselineCentered("\(slot.start)-\(slot.end)", size: timeSize, bold: false,
                                 color: scheme.onSurfaceVariant, cx: ctx.timeW / 2,
                                 baseline: cy + timeSize * 1.6)
            }
        }
    }

    // ── three_line 三行卡片 (surfaceContainerLow 圆角 8 + 端点异锚) ──
    @ViewBuilder
    private func threeLineContent(_ slot: TimeTableUtils.TimeSlotRow) -> some View {
        let rowY = ctx.rowTop(index - 1)
        let cardPad: CGFloat = 3
        // WeekGrid TimeSlot 恒单节点 → isSingleNode 真; 标签 = showX ? fullLabel : range(n,n)
        let label = showX ? PeriodHeaderFormatter.fullLabel(slot.node, headerStyle)
                          : PeriodHeaderFormatter.range(slot.node, slot.node, headerStyle)
        let adaptive = ctx.headerFont ?? WeekGridBody.columnSharedFont(
            slots: [slot], timeW: ctx.timeW, slotH: ctx.slotH,
            headerStyle: headerStyle, showX: showX)
        // 按自适应字号二次实测 → 几何 → placement (端点异锚)
        let startW = VerticalNameTokenizer.textWidth(slot.start, size: adaptive.timeSize, bold: false)
        let endW = VerticalNameTokenizer.textWidth(slot.end, size: adaptive.timeSize, bold: false)
        let labelW = VerticalNameTokenizer.textWidth(label, size: adaptive.labelSize, bold: true)
        let metrics = PeriodHeaderMetrics(startWidth: startW, endWidth: endW,
                                          labelWidth: labelW, showX: showX)
        let hanging = min(max(CGFloat(AppPrefs.shared.getPeriodHeaderHanging()), -1), 1)
        let placement = metrics.solvePlacement(u: hanging)
        // 卡片宽 = 元素矩形 + 内边距×2, 轨道内居中; 外框覆盖整行
        let cardW = max(placement.contentWidth + 2 * cardPad, 1)
        let cardH = max(ctx.slotH, 1)
        let cardLeft = ctx.timeW / 2 - cardW / 2
        let baseX = cardLeft + cardPad
        // 三行行盒 ← Compose Text 实际字号/字体度量: contentH = 2×timeRowH + labelRowH
        // (UIKit 度量符号约定: ascender>0 / descender<0 → 行高 = descender − ascender 取正)
        let timeFont = UIFont.systemFont(ofSize: adaptive.timeSize, weight: .regular)
        let labelFont = UIFont.systemFont(ofSize: adaptive.labelSize, weight: .bold)
        let timeRowH = timeFont.ascender - timeFont.descender
        let labelRowH = labelFont.ascender - labelFont.descender
        let contentH = timeRowH * 2 + labelRowH
        let contentTop = rowY + max(cardH - contentH, 0) / 2
        // 基线 = 行顶 + ascender (第一行行顶即 contentTop; 后行累加前行行高)
        let base1 = contentTop + timeFont.ascender
        let base2 = contentTop + timeRowH + labelFont.ascender
        let base3 = contentTop + timeRowH * 2 + labelFont.ascender

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8)
                .fill(scheme.surfaceContainerLow)
                .frame(width: cardW, height: cardH)
                .position(x: ctx.timeW / 2, y: rowY + cardH / 2)
            // 第一行: 开始时间 (onSurfaceVariant)
            leftAnchored(slot.start, font: timeFont, color: scheme.onSurfaceVariant,
                         x: baseX + placement.timeBaseLeft,
                         baseline: base1)
            // 第二行: 标签 (端点异锚, onSurface bold)
            leftAnchored(label, font: labelFont, color: scheme.onSurface,
                         x: baseX + placement.labelLeft,
                         baseline: base2)
            // 第三行: 结束时间
            leftAnchored(slot.end, font: timeFont, color: scheme.onSurfaceVariant,
                         x: baseX + placement.timeBaseLeft,
                         baseline: base3)
        }
    }

    // 基线锚定 → .position 居中换算: center = 行顶 + 行盒/2 = baseline − ascender + inkH/2
    // (UIKit ascender 为正; cy 沿用 Android "center + 0.35em" 基线口径, 换算后中心≈row 中线)
    private func baselineCentered(_ text: String, size: CGFloat, bold: Bool,
                                  color: Color, cx: CGFloat, baseline: CGFloat) -> some View {
        let font = UIFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
        let inkH = VerticalNameTokenizer.textHeight(text, font: font)
        return Text(text)
            .font(.system(size: size, weight: bold ? .bold : .regular))
            .foregroundColor(color)
            .fixedSize()
            .position(x: cx, y: baseline - font.ascender + inkH / 2)
    }

    /// 左缘锚定: x = 墨迹左缘 + 实测宽/2; y = 基线 − ascender + 行盒高/2
    /// (Text 以中心定位 → 中心 = 行顶 + 行高/2, 行顶 = 基线 − ascender)
    private func leftAnchored(_ text: String, font: UIFont, color: Color,
                              x: CGFloat, baseline: CGFloat) -> some View {
        let w = VerticalNameTokenizer.textWidth(text, font: font)
        let inkH = VerticalNameTokenizer.textHeight(text, font: font)
        return Text(text)
            .font(Font(font))
            .foregroundColor(color)
            .fixedSize()
            .position(x: x + w / 2, y: baseline - font.ascender + inkH / 2)
    }
}

// MARK: - 额外分隔线 ← showSeparators 段 (surfaceVariant α90, 0.7pt)

private struct WeekGridSeparators: View {
    let ctx: WeekGridBody.GridContext
    let color: Color

    var body: some View {
        let gridLeft = ctx.timeW
        let gridRight = ctx.timeW + ctx.gapW
            + CGFloat(ctx.dayCount) * (ctx.dayW + ctx.gapW) - ctx.gapW
        let lineW: CGFloat = 0.7
        ZStack(alignment: .topLeading) {
            // 纵线: 每列左右缘 (列间中线即上一列右缘与下一列左缘 — 间隙 2.5dp 内两线并存,
            // Android 对每列画 colX 与 colX+dayW 两条)。餐段带切断为多段 ← verticalSegments。
            ForEach(0..<ctx.dayCount, id: \.self) { idx in
                ForEach(ctx.mealBandCuts.indices, id: \.self) { seg in
                    line(x1: ctx.colX(idx), y1: ctx.mealBandCuts[seg].start,
                         x2: ctx.colX(idx), y2: ctx.mealBandCuts[seg].end, w: lineW)
                    line(x1: ctx.colX(idx) + ctx.dayW, y1: ctx.mealBandCuts[seg].start,
                         x2: ctx.colX(idx) + ctx.dayW, y2: ctx.mealBandCuts[seg].end, w: lineW)
                }
            }
            // 横线: row 0..maxNode — boundaryLineY:
            //   0 → gapH/2; maxNode → bodyBottom + gapH/2; 餐带下边界 → rowTop 原位;
            //   普通格间 → rowTop − gapH/2 (间隙中点)
            ForEach(0...ctx.maxNode, id: \.self) { row in
                line(x1: gridLeft, y1: boundaryLineY(row), x2: gridRight, y2: boundaryLineY(row),
                     w: lineW)
            }
            // 长休带(楚河汉界)上边线: 贴 band 上缘, 不中点化
            ForEach(Array(ctx.mealBands.enumerated()), id: \.offset) { _, band in
                line(x1: gridLeft, y1: band.start, x2: gridRight, y2: band.start, w: lineW)
            }
        }
    }

    func boundaryLineY(_ boundary: Int) -> CGFloat {
        if boundary <= 0 { return ctx.gapH / 2 }
        if boundary >= ctx.maxNode { return ctx.bodyBottom + ctx.gapH / 2 }
        if ctx.mealBreakAfterRows.contains(boundary - 1) { return ctx.rowTop(boundary) }
        return ctx.rowTop(boundary) - ctx.gapH / 2
    }

    func line(x1: CGFloat, y1: CGFloat, x2: CGFloat, y2: CGFloat, w: CGFloat) -> some View {
        Path { p in
            p.move(to: CGPoint(x: x1, y: y1))
            p.addLine(to: CGPoint(x: x2, y: y2))
        }
        .stroke(color.opacity(90.0 / 255.0), lineWidth: w)
    }
}

extension WeekGridBody.GridContext {
    /// 餐段带把列高纵线切断的连续开放段 ← GridSeparatorGeometry.verticalSegments
    var mealBandCuts: [(start: CGFloat, end: CGFloat)] {
        var open = bodyH
        var cuts = [(CGFloat, CGFloat)]()
        for band in mealBands.sorted(by: { $0.start < $1.start }) {
            if band.start > open { cuts.append((open, band.start)) }
            open = max(open, band.end)
        }
        if open < bodyBottom { cuts.append((open, bodyBottom)) }
        return cuts
    }
}

// MARK: - §4.4 色带档 ← colorBand 段 (日列无文字, 只画课程色条)

private struct WeekGridColorBandColumn: View {
    let dayData: DayData
    let ctx: WeekGridBody.GridContext
    let scheme: WidgetScheme
    let colorless: Bool
    let allCourses: [CourseEntity]

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(ConflictLayoutEngine.gridDayLanes(
                dayData.courses, timeJson: dayData.timeJson.isEmpty ? nil : dayData.timeJson
            ), id: \.course.id) { rect in
                let course = rect.course
                let startIdx = max(course.startNode - 1, 0)
                let step = min(max(course.step, 1), max(ctx.maxNode - startIdx, 1))
                let top = ctx.rowTop(startIdx)
                let barH = ctx.spanH(startIdx, step)
                let laneX = ctx.dayW * CGFloat(rect.laneStartFraction)
                let laneW = ctx.dayW * CGFloat(rect.laneWidthFraction)
                // iOS 26 「透明/着色」样式: 课程色被整组染白 → 直接白底, 保留
                // 灰显/正常两档 alpha (120/200), 玻璃上仍可读 (← WidgetBackgroundCompat)
                let baseColor = scheme.isGlass ? Color.white
                    : CourseColorUtil.pickCourseColorSwiftUIWithGroupRows(
                    course,
                    groupRows: allCourses.filter { $0.groupId == course.groupId }.isEmpty
                        ? [course] : allCourses.filter { $0.groupId == course.groupId },
                    isDark: scheme.isDark, neutralColor: scheme.surfaceVariant,
                    colorless: colorless,
                    persistedHue: CourseHueStore.hueFor(groupId: course.groupId))
                RoundedRectangle(cornerRadius: min(4, barH / 2))
                    .fill(baseColor.opacity(dayData.isGrey ? 120.0 / 255.0 : 200.0 / 255.0))
                    .frame(width: laneW, height: barH)
                    .offset(x: laneX, y: top)
            }
        }
        .frame(width: ctx.dayW, height: ctx.bodyH, alignment: .topLeading)
    }
}

// MARK: - Day column(课程卡)

private struct WeekGridDayColumn: View {
    let dayData: DayData
    let ctx: WeekGridBody.GridContext
    let scheme: WidgetScheme
    let colorless: Bool
    let allCourses: [CourseEntity]
    /// issue#26: widget 场景别名 — 透传课程卡
    let useAlias: Bool

    var body: some View {
        // v7.10.8: 冲突课分栏 — ConflictLayoutEngine.gridDayLanes, 冲突区域课并排各占
        // 1/N 列宽, 无冲突课整列宽(旧实现按槽叠盖, 冲突课信息丢失)
        ZStack(alignment: .topLeading) {
            ForEach(ConflictLayoutEngine.gridDayLanes(
                dayData.courses, timeJson: dayData.timeJson.isEmpty ? nil : dayData.timeJson
            ), id: \.course.id) { rect in
                WeekGridLaneCard(rect: rect, ctx: ctx, scheme: scheme, colorless: colorless,
                                 allCourses: allCourses, useAlias: useAlias,
                                 isGrey: dayData.isGrey)
            }
        }
        .frame(width: ctx.dayW, height: ctx.bodyH, alignment: .topLeading)
    }
}

// MARK: - 分栏课程卡 ← Android laneRect 定位逐值移植

private struct WeekGridLaneCard: View {
    let rect: ConflictLayoutEngine.GridLaneRect
    let ctx: WeekGridBody.GridContext
    let scheme: WidgetScheme
    let colorless: Bool
    let allCourses: [CourseEntity]
    let useAlias: Bool
    let isGrey: Bool

    // ← startIdx = max(startNode - 1, 0); step 夹 [1, maxNode - startIdx]
    private var startIdx: Int { max(rect.course.startNode - 1, 0) }
    private var clampedStep: Int { min(max(rect.course.step, 1), max(ctx.maxNode - startIdx, 1)) }
    private var cardW: CGFloat { ctx.dayW * CGFloat(rect.laneWidthFraction) }
    private var cardH: CGFloat { ctx.spanH(startIdx, clampedStep) }

    var body: some View {
        WeekGridCourseCard(course: rect.course, scheme: scheme, colorless: colorless,
                           cardW: cardW, cardH: cardH,
                           unifiedCharSize: ctx.unifiedCharSize,
                           groupRows: allCourses.filter { $0.groupId == rect.course.groupId },
                           useAlias: useAlias, isGrey: isGrey)
            .frame(width: cardW, height: cardH)
            // ← laneX = colX + dayW*laneStartFraction; cardTop = rowTop(startIdx) (含餐带偏移)
            .offset(x: ctx.dayW * CGFloat(rect.laneStartFraction),
                    y: ctx.rowTop(startIdx))
    }
}

// MARK: - 课程卡(v19k: 课名竖排居中 + 教室底部横排小字)

private struct WeekGridCourseCard: View {
    let course: CourseEntity
    let scheme: WidgetScheme
    let colorless: Bool
    /// 分栏后本卡实际宽/高 (Android cardRect) — 教室截断用宽; 高由父级
    /// spanH(startIdx, clampedStep) 给出 (含餐带劈开语义, 卡不在本层重算)
    let cardW: CGFloat
    let cardH: CGFloat
    /// v20b: 全表统一字号 ← unifiedCharSize (父级一次算好, 所有卡同值)
    let unifiedCharSize: CGFloat
    /// issue#22: 同 groupId 全行(含自身) — AUTO/CUSTOM 取色按行判
    var groupRows: [CourseEntity] = []
    /// issue#26: widget 场景别名 — 竖排课名展示名(trim 别名, 空回退原名)
    var useAlias: Bool = false
    /// issue#44: 节假日灰显列 — 文字 alpha 153 + 「删除线」样式合取删线
    var isGrey: Bool = false

    var body: some View {
        // 卡片背景色 — 统一入口 CourseColorUtil (决策 D3); colorless 灰底传 surfaceVariant
        // issue#22: 改走 *WithGroupRows 三态入口
        // iOS 26 「透明/着色」样式 (scheme.isGlass): 系统把所有不透明内容整组染白、仅保
        // alpha → 课程色失去区分且深底白字判白与卡面同色。玻璃档改白 alpha 阶梯:
        // 卡底 secondaryContainer(30%)、文字 onSurface(100%), 层级靠透明度 (← WidgetBackgroundCompat)
        let glass = scheme.isGlass
        let baseColor = glass ? Color.white : CourseColorUtil.pickCourseColorSwiftUIWithGroupRows(
            course, groupRows: groupRows.isEmpty ? [course] : groupRows,
            isDark: scheme.isDark, neutralColor: scheme.surfaceVariant, colorless: colorless,
            persistedHue: CourseHueStore.hueFor(groupId: course.groupId))
        // 文字色: 深底白字 / 浅底近黑 (isDarkOn); 灰显文字 alpha ← Android :740
        let textColor = glass ? scheme.onSurface
            : (Self.isDarkOn(baseColor) ? Color.white : Color(0xFF1D1B20))
        // ← WidgetBitmapRenderers drawCourse :741: 灰显 × 「删除线」样式 → 删线
        let strike = isGrey && AppPrefs.shared.getHolidayStyle() == "strikethrough"

        VStack(spacing: 1) {
            // ★ v21: token 化课名竖排 (灰显列文字 alpha 153/255 ← :740)
            VerticalNameView(name: displayName, charSize: unifiedCharSize,
                             nameAvailH: nameAvailH, textColor: textColor,
                             textOpacity: isGrey ? 153.0 / 255.0 : 1,
                             strike: strike)
            // ★ 教室: 底部横排小字角标, 0.62× 字号, 半透明, 按卡片宽截断省略
            if hasRoom {
                Text(roomVisible)
                    .font(.system(size: roomSize))
                    .strikethrough(strike)
                    .foregroundColor(textColor.opacity(160.0 / 255.0))
                    .lineLimit(1)
            }
        }
        .padding(4)  // unifiedPad — 可用高预算 (cardH−8) 与实际留白同源
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            // 卡底 alpha ← Android :723: 灰显列 120, 正常 200;
            // 玻璃档 = secondaryContainer (白 30%, 文字白 100% 对比足够)
            RoundedRectangle(cornerRadius: 10)
                .fill(glass ? scheme.secondaryContainer
                            : baseColor.opacity((isGrey ? 120.0 : 200.0) / 255.0))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(glass ? Color.white.opacity(0.08) : baseColor.opacity(80.0 / 255.0),
                              lineWidth: 0.5)
        )
    }

    private var roomStr: String {
        course.room.filter { $0 != "\n" && $0 != " " }
    }

    /// hasRoom ← Android course.room.isNotBlank() (原串判空, 非过滤后) —
    /// roomReserve/字号预留与绘制条件同源
    private var hasRoom: Bool { !course.room.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    // issue#26: 展示名 = CourseDisplayUtil(useAlias→trim 别名, 空回退原名) —
    // 字号预算(charSize)与绘制必须用同一个名字, 否则截断不一致 (← Android 同款注释)
    private var displayName: String { CourseDisplayUtil.displayName(course, useAlias) }

    /// availCardH ← cardRect.height() − unifiedPad×2 (:752)
    private var availCardH: CGFloat { max(cardH - 8, 0) }

    /// roomReserveH ← :754 (nameMinDp×0.7 与 35% 可用高取小) — room 字号与布局共用
    private var roomReserveH: CGFloat {
        hasRoom ? min(11 * 0.7, availCardH * 0.35) : 0
    }

    private var nameAvailH: CGFloat { max(availCardH - roomReserveH, 0) }

    /// roomRequested ← :866 0.62× 夹 [5,8]; 再被 weekGridRoomLabelLayout:206
    /// 挤占防御压到 roomReserveH/1.1 (极矮卡不压进课名区)
    private var roomSize: CGFloat {
        let requested = min(max(unifiedCharSize * 0.62, 5), 8)
        return max(min(requested, roomReserveH / 1.1), 0)
    }

    // 按卡片可用宽算能放几个字符, 超了截断 + … (中文≈0.55em宽) ← :877-882
    private var roomVisible: String {
        let availRoomW = cardW - 8  // unifiedPad*2 = 4*2 (分栏后按本卡实际宽截断)
        let maxRoomChars = max(Int(availRoomW / (roomSize * 0.55)), 2)
        return roomStr.count > maxRoomChars ? String(roomStr.prefix(maxRoomChars - 1)) + "…" : roomStr
    }

    // ← isDarkOn: 相对亮度 < 0.55 判深色
    static func isDarkOn(_ color: Color) -> Bool {
        CourseColorUtil.luminance(color) < 0.55
    }
}

// MARK: - v21 竖排课名

/// token 化课名竖排渲染 — CJK 直立逐字 / Latin run≥2 整组旋转90° / 标点方案A'旋转
struct VerticalNameView: View {
    let name: String
    let charSize: CGFloat
    let nameAvailH: CGFloat
    let textColor: Color
    /// 灰显列文字透明度 ← Android p.alpha=153/255 (:740)
    var textOpacity: CGFloat = 1
    /// 灰显 × 「删除线」样式 (:741) — 竖排逐字渲染, 全列删线以逐字删线呈现
    var strike: Bool = false

    var body: some View {
        let tokens = VerticalNameTokenizer.tokenize(name)
        // v22: 字符级贪心截断 + 极端矮卡缩放首字
        let drawn = VerticalNameTokenizer.greedyDraw(tokens: tokens, charSize: charSize,
                                                     nameAvailH: nameAvailH)
        VStack(spacing: 0) {
            ForEach(drawn.indices, id: \.self) { idx in
                let tok = drawn[idx]
                switch tok.type {
                case .cjk:
                    Text(tok.text)
                        .font(.system(size: tok.size, weight: .bold))
                        .strikethrough(strike)
                        .foregroundColor(textColor.opacity(textOpacity))
                        .frame(height: tok.h)
                case .latin, .punct:
                    // 整组顺时针旋转90°(LATIN run) / 单字旋转90°(PUNCT 方案A')
                    Text(tok.text)
                        .font(.system(size: tok.size, weight: .bold))
                        .strikethrough(strike)
                        .foregroundColor(textColor.opacity(textOpacity))
                        .rotationEffect(.degrees(90))
                        .frame(height: tok.h)
                }
            }
        }
    }
}

// MARK: - token 化器 ← tokenizeName / measureUnitHeight / PUNCT_CHARS / VERT_FORM_MAP

enum TT { case cjk, latin, punct }

struct NameToken {
    let type: TT
    let text: String
    /// 绘制高度(px) — greedyDraw 输出携带; tokenize 输出为 0
    var h: CGFloat = 0
    /// 绘制字号(px) — 极端矮卡缩放首字场景 < charSize
    var size: CGFloat = 0
}

enum VerticalNameTokenizer {
    /// 文本墨迹宽度 — ← Android paint.measureText 的 iOS 等价口径
    /// (NSAttributedString.size, 与 App 层 CourseTableView textWidth 同源)。
    /// 三行表头几何/字号自适应与竖排截断必须实测, 不能再用固定系数近似。
    static func textWidth(_ s: String, font: UIFont) -> CGFloat {
        (s as NSString).size(withAttributes: [.font: font]).width
    }

    static func textWidth(_ s: String, size: CGFloat, bold: Bool) -> CGFloat {
        textWidth(s, font: UIFont.systemFont(ofSize: size, weight: bold ? .bold : .regular))
    }

    /// 标点字符集 — 横排符号, 需特殊处理(旋转或替换)
    static let PUNCT_CHARS: Set<Character> = [
        "(", ")", "（", "）", "〔", "〕", "【", "】", "《", "》", "〈", "〉",
        "「", "」", "『", "』", "[", "]", "{", "}",
        "—", "–", "～", "~", "…", "·", "・", "、", "，", "。", "：", "；",
        "！", "？", "”", "“", "’", "‘", "\"", "'", "/", "／", "｜", "|"
    ]

    /// 方案B: 横排符号 → Unicode Vertical Forms (U+FE19–FE44)
    static let VERT_FORM_MAP: [Character: Character] = [
        "(": "︵", "（": "︵",   // U+FE35
        ")": "︶", "）": "︶",   // U+FE36
        "〔": "︹",                  // U+FE39
        "〕": "︺",                  // U+FE3A
        "【": "︻",                  // U+FE3B
        "】": "︼",                  // U+FE3C
        "《": "︽",                  // U+FE3D
        "》": "︾",                  // U+FE3E
        "〈": "︿",                  // U+FE3F
        "〉": "﹀",                  // U+FE40
        "「": "﹁",                  // U+FE41
        "」": "﹂",                  // U+FE42
        "『": "﹃",                  // U+FE43
        "』": "﹄",                  // U+FE44
        "[": "︻",                  // 复用
        "]": "︼",                  // 复用
        "{": "︷",                  // U+FE37
        "}": "︸",                  // U+FE38
        "—": "︱",                  // U+FE31
        "…": "︙"                    // U+FE19
    ]

    static func isLatin(_ ch: Character) -> Bool {
        ("A"..."Z").contains(ch) || ("a"..."z").contains(ch) || ("0"..."9").contains(ch)
    }

    static func isCJK(_ ch: Character) -> Bool {
        ("一"..."鿿").contains(ch) || ("㐀"..."䶿").contains(ch) || ("豈"..."﫿").contains(ch)
    }

    /// 课名 → token 列表。先去空白, 再扫描连续 run。
    /// 方案B(vertPunctReplace=true): 标点替换 Vertical Forms(变 CJK 直立)
    /// 方案A'(false, 默认): 标点保持原样(绘制时逐个旋转)
    static func tokenize(_ name: String, useVertForms: Bool = false) -> [NameToken] {
        let useVertForms = useVertForms || AppPrefs.shared.isVertPunctReplace()
        let s = name.filter { $0 != "\n" && $0 != " " }
        if s.isEmpty { return [] }
        var tokens: [NameToken] = []
        var sb = ""
        var runType: TT?

        func flush() {
            if !sb.isEmpty, let rt = runType {
                tokens.append(NameToken(type: rt, text: sb))
                sb = ""
            }
            runType = nil
        }

        for ch in s {
            // 方案B: 标点先替换为 Vertical Forms → 归为 CJK 直立
            let c = useVertForms ? (VERT_FORM_MAP[ch] ?? ch) : ch
            let t: TT
            if isCJK(c) { t = .cjk }
            else if PUNCT_CHARS.contains(c) { t = .punct }
            else if isLatin(c) { t = .latin }
            else { t = .cjk }  // 其他字符(含替换后的竖排符号)按 CJK 直立
            if t != runType { flush(); runType = t }
            sb.append(c)
        }
        flush()

        // 后处理: LATIN run 长度=1 → 保持直立(改判 CJK 处理)
        return tokens.map { tok in
            tok.type == .latin && tok.text.count == 1 ? NameToken(type: .cjk, text: tok.text) : tok
        }
    }

    /// 文本墨迹高度 (ascender→descender 行盒) — .position 基线换算用
    static func textHeight(_ s: String, font: UIFont) -> CGFloat {
        (s as NSString).size(withAttributes: [.font: font]).height
    }

    /// token 单位高度 — ← measureUnitHeight 逐行: CJK 每字 1em / LATIN 组高=组实测宽
    /// / PUNCT 每字实测宽 (1pt 探针字号, 与 charSize 无关的比值)
    static func unitHeight(_ tokens: [NameToken]) -> CGFloat {
        let probe = UIFont.systemFont(ofSize: 1)
        var h: CGFloat = 0
        for tok in tokens {
            switch tok.type {
            case .cjk: h += CGFloat(tok.text.count)
            case .latin: h += textWidth(tok.text, font: probe)
            case .punct: for ch in tok.text { h += textWidth(String(ch), font: probe) }
            }
        }
        return h
    }

    /// v22 字符级贪心截断 → 绘制 token 列表(任何 token 可拆到字符级, 杜绝溢出)
    /// 高度口径 = ← Android p.measureText(textSize=charSize, BOLD): 实测而非固定系数
    static func greedyDraw(tokens: [NameToken], charSize: CGFloat, nameAvailH: CGFloat) -> [NameToken] {
        struct DrawnToken {
            let type: TT
            let text: String
            let h: CGFloat
            let size: CGFloat
        }
        var drawn: [DrawnToken] = []
        var cumH: CGFloat = 0
        var truncated = false
        let ellipsisH = charSize  // 省略号占~1字高

        for tok in tokens {
            if truncated { break }
            switch tok.type {
            case .cjk:
                for ch in tok.text {
                    if cumH + charSize > nameAvailH { truncated = true; break }
                    drawn.append(DrawnToken(type: .cjk, text: String(ch), h: charSize, size: charSize))
                    cumH += charSize
                }
            case .latin:
                // 旋转组不可拆: 整组放不下即截断 (组高 = 实测组宽)
                let tokH = textWidth(tok.text, size: charSize, bold: true)
                if cumH + tokH > nameAvailH { truncated = true; break }
                drawn.append(DrawnToken(type: .latin, text: tok.text, h: tokH, size: charSize))
                cumH += tokH
            case .punct:
                for ch in tok.text {
                    let chW = textWidth(String(ch), size: charSize, bold: true)
                    if cumH + chW > nameAvailH { truncated = true; break }
                    drawn.append(DrawnToken(type: .punct, text: String(ch), h: chW, size: charSize))
                    cumH += chW
                }
            }
        }

        // 截断后腾省略号高度: 从尾部逐字移除直到 … 放得下
        var showEllipsis = truncated
        if truncated {
            while !drawn.isEmpty && cumH + ellipsisH > nameAvailH {
                cumH -= drawn.removeLast().h
            }
            if drawn.isEmpty { showEllipsis = false }  // 一个字都放不下 → 不画…
        }
        // v22: 极端矮卡 — 缩放首字字号至刚好填满 nameAvailH
        if drawn.isEmpty && !tokens.isEmpty {
            let tinySize = min(max(nameAvailH, 1), charSize)
            let first = String(tokens[0].text.first!)
            drawn.append(DrawnToken(type: .cjk, text: first, h: tinySize, size: tinySize))
            cumH = tinySize
            showEllipsis = false
        }
        if showEllipsis {
            drawn.append(DrawnToken(type: .cjk, text: "…", h: ellipsisH, size: charSize))
        }
        return drawn.map { NameToken(type: $0.type, text: $0.text, h: $0.h, size: $0.size) }
    }
}

// MARK: - SMALL 档 ← weekGridMinimumTodayData + pushTodayData(SMALL)

/// WeekGrid systemSmall: 不再"折叠成单列的网格脸", 直接渲染今日课程·小
/// (数据侧 weekGridMinimumTodayData: WeekData → 今日 WidgetData, 纯函数;
///  Android 今日·小已删纯文本脸改走常规渲染器 → iOS 直接复用 TodayWidgetEntryView)
private struct WeekGridMinimumTodayFace: View {
    let data: WeekData

    var body: some View {
        let todayData = Self.minimumTodayData(data)
        TodayWidgetEntryView(entry: TodayWidgetEntry(date: Date(), data: todayData,
                                                     nowMin: WidgetWindows.nowMinutes()))
    }

    // ← weekGridMinimumTodayData 逐行: 今日 DayData → WidgetData。
    // v1.0.60 单一事实源已迁至 WidgetCompactHelpers.weekGridMinimumTodayData
    // (← WidgetBitmapRenderers.kt 同名函数, NEAREST_BUSY_DAY 时 targetDate = 最早有课日)。
    static func minimumTodayData(_ data: WeekData) -> WidgetData {
        WidgetCompactHelpers.weekGridMinimumTodayData(data, today: Date())
    }
}

struct WeekGridWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WeekGridWidgetV19", provider: WeekGridWidgetProvider()) { entry in
            WeekGridWidgetEntryView(entry: entry)
        }
        .configurationDisplayName(L10n.format("widget_week_grid_label"))
        // 三档全开: Android 13 变体是「放置预设」(S/M/L),且全部 minResize 40dp + 自由拖拽,
        // 任何 widget 都能被拖成任意档 → iOS 三 family 全支持,档位由 WidgetLayoutTier 换算
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        // iOS 17+ 系统边距关闭, 维持既有自管 padding 布局 (iOS 16 及以下 no-op)
        .contentMarginsDisabled()
    }
}
