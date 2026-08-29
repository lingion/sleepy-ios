// CourseTableView.swift — ← ui/component/CourseTableView.kt (733 行)
// Cards 网格视图 + FullWeekView(7days) + 公共小组件。
//
// 架构(逐行对齐):
//   BoxWithConstraints → colW(dp) → Column(verticalScroll) → 表头 Row + 固定高 grid Box
//   时间栏/课程卡全用 offset 绝对定位 → 滚动同步。
// 布局常量: headH 52 / timeW 68 / slotH 52 / gapH 4 / gapW 5 / rowH 56。

import SwiftUI

/// 时段定义 — 5 个时段(WakeUp 默认 12 节对应 1-2/3-5/6-7/8-10/11-13) ← TimeSlot
struct TimeSlot {
    let label: String        // "1-2节"
    let startHour: Int
    let startMinute: Int
    let endHour: Int
    let endMinute: Int
    var displayStart: String { String(format: "%02d:%02d", startHour, startMinute) }
    var displayEnd: String { String(format: "%02d:%02d", endHour, endMinute) }
    let nodeStart: Int
    var nodeEnd: Int { nodeStart }  // 派生段(段内多节由调用方展开为单节行)

    var timeString: String { "\(displayStart)-\(displayEnd)" }
}

// MARK: - CardsGridView ← CardsGridView

struct CardsGridView: View {
    @Environment(\.localWakeUpColors) private var colors
    @Environment(\.localCoursePalette) private var palette
    let courses: [CourseEntity]
    let timeSlots: [TimeSlot]
    var visibleDays: Set<Int> = Set(1...7)
    var showDate: Bool = false
    var startDate: String = ""
    var currentWeek: Int = 1
    var today: Int = DateUtils.todayDayOfWeek()
    let onCourseClick: (CourseEntity) -> Void
    var greyDays: Set<Int> = []  // 本周应灰显的星期几 (1-7) — 节假日/周末灰显

    var body: some View {
        let maxNode = timeSlots.map { $0.nodeEnd }.max() ?? 12
        let sortedDays = visibleDays.sorted()
        let dayCount = sortedDays.count

        // 布局常量(全 dp)
        let headH: CGFloat = 52
        let timeW: CGFloat = 68
        let slotH: CGFloat = 52
        let gapH: CGFloat = 4
        let gapW: CGFloat = 5
        let rowH: CGFloat = slotH + gapH   // 56

        GeometryReader { geo in
            // 根据容器宽度计算列宽；窄屏优先压缩时间栏和间距，避免卡片向右溢出。
            let sideInset: CGFloat = 16
            let timeW = min(68, max(52, geo.size.width * 0.16))
            let gapW = min(5, max(3, geo.size.width * 0.012))
            let contentW = max(geo.size.width - sideInset - timeW - gapW * CGFloat(dayCount), 0)
            let colW = max(contentW / CGFloat(dayCount), 28)
            let gridH = rowH * CGFloat(maxNode)   // grid 内容区固定高度

            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    // ---- 表头 ----
                    // 首列留白 = timeW + gapW，与下方 grid 的 cardX 对齐；高度随日期行自适应
                    let hasDateRow = showDate && !startDate.isEmpty
                    HStack(spacing: gapW) {
                        Spacer().frame(width: timeW + gapW)
                        ForEach(sortedDays, id: \.self) { day in
                            let dateStr: String? = {
                                guard showDate, !startDate.isEmpty,
                                      let d = DateUtils.dateOfWeek(startDate: startDate, week: currentWeek, dayOfWeek: day) else { return nil }
                                return DateUtils.shortDate(d)
                            }()
                            DayHeadCell(day: day, isToday: day == today,
                                        isGrey: greyDays.contains(day),
                                        courseCount: courses.filter { $0.day == day }.count,
                                        dateStr: dateStr)
                                .frame(width: colW)
                                .frame(maxHeight: .infinity)
                        }
                    }
                    .frame(height: hasDateRow ? 56 : headH)

                    Spacer().frame(height: gapH)

                    // ---- Grid 主体: 固定高度, 内部绝对定位 ----
                    ZStack(alignment: .topLeading) {
                        // 时间栏
                        ForEach(Array(timeSlots.enumerated()), id: \.element.nodeStart) { i, slot in
                            SingleTimeHeadCell(slot: slot)
                                .frame(width: timeW, height: slotH)
                                .offset(y: rowH * CGFloat(i))
                        }
                        // 课程卡片
                        ForEach(courses) { course in
                            if visibleDays.contains(course.day), (1...maxNode).contains(course.startNode) {
                                let dayIdx = sortedDays.firstIndex(of: course.day) ?? 0
                                let steps = min(max(course.step, 1), maxNode - course.startNode + 1)
                                let cardX = timeW + gapW + (colW + gapW) * CGFloat(dayIdx)
                                let cardY = rowH * CGFloat(course.startNode - 1)
                                let cardH = rowH * CGFloat(steps) - gapH

                                CourseOverlayCard(course: course, cardHeight: cardH,
                                                  isDark: CourseColorUtil.isPaletteDark(palette),
                                                  isGrey: greyDays.contains(course.day)) {
                                    onCourseClick(course)
                                }
                                .frame(width: colW, height: cardH)
                                .offset(x: cardX, y: cardY)
                            }
                        }
                    }
                    .frame(width: max(geo.size.width - sideInset, 0),
                           height: gridH, alignment: .topLeading)
                }
                .padding(8)
            }
        }
        .background(colors.surfaceContainerHigh)
        .cornerRadius(SleepyShapes.large)
    }

}

// ← SingleTimeHeadCell
private struct SingleTimeHeadCell: View {
    @Environment(\.localWakeUpColors) private var colors
    let slot: TimeSlot

    var body: some View {
        VStack(spacing: 1) {
            Text(L10n.format("period_format_node", slot.label))
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(colors.onSurface)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .allowsTightening(true)
            Text(slot.timeString)
                .font(SleepyTextStyle.micro())
                .foregroundColor(colors.onSurfaceVariant)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .allowsTightening(true)
        }
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colors.surfaceContainerLow)
        .cornerRadius(SleepyShapes.medium)
        .padding(2)
    }
}

// ← CourseOverlayCard
private struct CourseOverlayCard: View {
    @Environment(\.localWakeUpColors) private var colors
    let course: CourseEntity
    var cardHeight: CGFloat = 0   // 0 = 调用方未提供, 回退旧行为
    let isDark: Bool
    var isGrey: Bool = false      // 节假日灰显
    let onClick: () -> Void

    var body: some View {
        let bg = CourseColorUtil.pickCourseColorSwiftUI(
            course, isDark: isDark,
            neutralColor: colors.surfaceVariant,
            colorless: AppPrefs.shared.isCourseColorless())
        let fg = CourseColorUtil.textColorOn(bg: bg, isDark: isDark, onSurface: colors.onSurface)
        // 节假日灰显：色块叠 alpha + 文字应用 strikethrough 样式 ← effectiveBg/effectiveFg/textDecoration
        let effectiveBg = isGrey ? bg.opacity(SleepyTheme.Alpha.inactive) : bg
        let effectiveFg = isGrey ? fg.opacity(SleepyTheme.Alpha.inactive) : fg
        let strikethrough = isGrey && AppPrefs.shared.getHolidayStyle() == "strikethrough"
        // 副信息(教室/教师/无) — grid_sub_info 设置决定
        let bodyFont = cardHeight >= 110 ? 10.0 : 11.0
        let subInfo = AppPrefs.shared.getGridSubInfo()
        let subText: String = {
            switch subInfo {
            case "room": return course.room
            case "teacher": return course.teacher
            default: return ""
            }
        }()

        Button(action: onClick) {
            Group {
                if subText.isEmpty {
                    // 无副信息: 课程名整体居中(原行为); 名字长时压缩字体防横向溢出
                    Text(course.courseName)
                        .font(.system(size: bodyFont, weight: .semibold))
                        .foregroundColor(effectiveFg)
                        .strikethrough(strikethrough)
                        .lineLimit(6)
                        .minimumScaleFactor(0.6)
                        .allowsTightening(true)
                        .multilineTextAlignment(.center)
                } else {
                    // 有副信息: 课程名在上半区居中, 副信息贴卡底; 两者都允许缩放
                    VStack(spacing: 2) {
                        Text(course.courseName)
                            .font(.system(size: bodyFont, weight: .semibold))
                            .foregroundColor(effectiveFg)
                            .strikethrough(strikethrough)
                            .lineLimit(4)
                            .minimumScaleFactor(0.6)
                            .allowsTightening(true)
                            .multilineTextAlignment(.center)
                            .frame(maxHeight: .infinity)
                        Text(subText)
                            .font(SleepyTextStyle.micro())
                            .foregroundColor(effectiveFg.opacity(SleepyTheme.Alpha.highContent))
                            .strikethrough(strikethrough)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                            .allowsTightening(true)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(SleepyButtonStyle())
        .accessibilityIdentifier("gridcell_\(course.id)")
        .padding(4)
        .background(effectiveBg)
        .cornerRadius(SleepyShapes.medium)
        .padding(2)
    }
}

// ← DayHeadCell
private struct DayHeadCell: View {
    @Environment(\.localWakeUpColors) private var colors
    let day: Int
    let isToday: Bool
    var isGrey: Bool = false
    let courseCount: Int
    var dateStr: String? = nil

    var body: some View {
        let bg = isToday ? colors.primaryContainer : colors.surface
        let fg = isGrey ? colors.onSurfaceVariant.opacity(SleepyTheme.Alpha.inactive)
                        : (isToday ? colors.onPrimaryContainer : colors.onSurface)
        let subFg = isGrey ? colors.onSurfaceVariant.opacity(SleepyTheme.Alpha.inactive)
                           : (isToday ? colors.onPrimaryContainer.opacity(SleepyTheme.Alpha.highContent)
                                      : colors.onSurfaceVariant)

        VStack(spacing: 1) {
            Text(DateUtils.localizedDay(day))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(fg)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .allowsTightening(true)
            if let dateStr = dateStr {
                Text(dateStr)
                    .font(.system(size: 10))
                    .foregroundColor(subFg)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .allowsTightening(true)
            } else {
                Text(courseCount == 0 ? L10n.format("no_course")
                                      : L10n.format("course_count_format", courseCount))
                    .font(SleepyTextStyle.micro())
                    .foregroundColor(subFg)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .allowsTightening(true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(bg)
        .cornerRadius(SleepyShapes.large)
        .padding(.horizontal, 1)
        .padding(.vertical, 6)
    }
}

// =====================================================================================
// 7days full 视图 — switchable.html #fullView ← FullWeekView
// =====================================================================================

struct FullWeekView: View {
    @Environment(\.localWakeUpColors) private var colors
    @Environment(\.localCoursePalette) private var palette
    let courses: [CourseEntity]
    var visibleDays: Set<Int> = Set(1...7)
    var displayMode: String = "node"
    var timeJson: String = ""
    var today: Int = DateUtils.todayDayOfWeek()
    let onCourseClick: (CourseEntity) -> Void
    var greyDays: Set<Int> = []  // 本周应灰显的星期几 (1-7)

    var body: some View {
        let byDay = Dictionary(grouping: courses, by: { $0.day })

        ScrollView(.vertical) {
            VStack(spacing: 0) {
                WeekStrip(byDay: byDay, visibleDays: visibleDays, today: today, greyDays: greyDays)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                DetailPanel(byDay: byDay, visibleDays: visibleDays, displayMode: displayMode,
                            timeJson: timeJson, today: today, greyDays: greyDays,
                            onCourseClick: onCourseClick)
                // (参数顺序: byDay/visibleDays/displayMode/timeJson/today/onCourseClick)
            }
        }
    }
}

// ← WeekStrip
private struct WeekStrip: View {
    @Environment(\.localWakeUpColors) private var colors
    let byDay: [Int: [CourseEntity]]
    let visibleDays: Set<Int>
    let today: Int
    var greyDays: Set<Int> = []

    var body: some View {
        HStack(spacing: 6) {
            ForEach(visibleDays.sorted(), id: \.self) { day in
                DaySummaryCell(day: day, courses: byDay[day] ?? [], isToday: day == today,
                               isGrey: greyDays.contains(day))
            }
        }
    }
}

// ← DaySummaryCell
private struct DaySummaryCell: View {
    @Environment(\.localWakeUpColors) private var colors
    let day: Int
    let courses: [CourseEntity]
    let isToday: Bool
    var isGrey: Bool = false

    var body: some View {
        let bg = isToday ? colors.primaryContainer : colors.surfaceContainer
        let fg = isGrey ? colors.onSurfaceVariant.opacity(SleepyTheme.Alpha.inactive)
                        : (isToday ? colors.onPrimaryContainer : colors.onSurface)

        VStack(spacing: 4) {
            // 日期
            Text(DateUtils.localizedDay(day))
                .font(SleepyTextStyle.dayLabel())
                .foregroundColor(fg)

            Spacer().frame(height: 6)

            // Chip: 课程数 — "N 门" 完整文字, 列宽放不下退化为纯数字。
            // ← Android textMeasurer: fullText 在列宽内换行(lineCount>1) → 只显数字。
            //   ViewThatFits 等价: fullText(单行)放得下用 fullText, 否则回退数字。
            // chipFg ← Android: onSurfaceVariant@alpha(grey ? inactive : 1)
            let chipFg = isGrey ? colors.onSurfaceVariant.opacity(SleepyTheme.Alpha.inactive)
                                : colors.onSurfaceVariant
            if courses.isEmpty {
                Spacer().frame(height: 14)
            } else {
                ViewThatFits(in: .horizontal) {
                    Text(L10n.format("course_count_format", courses.count))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(chipFg)
                        .lineLimit(1)
                    Text("\(courses.count)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(chipFg)
                        .lineLimit(1)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(colors.surfaceVariant)
                .cornerRadius(50)
            }

            Spacer().frame(height: 4)

            // Mini-list: 前 5 门课名
            VStack(spacing: 2) {
                ForEach(courses.prefix(5)) { c in
                    Text(c.courseName)
                        .font(SleepyTextStyle.micro())
                        .foregroundColor(isToday
                            ? colors.onPrimaryContainer.opacity(SleepyTheme.Alpha.highContent)
                            : colors.onSurfaceVariant)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 132)
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .background(bg)
        .cornerRadius(SleepyShapes.medium)
    }
}

// ← DetailPanel
private struct DetailPanel: View {
    @Environment(\.localWakeUpColors) private var colors
    let byDay: [Int: [CourseEntity]]
    let visibleDays: Set<Int>
    let displayMode: String
    let timeJson: String
    let today: Int
    var greyDays: Set<Int> = []
    let onCourseClick: (CourseEntity) -> Void

    var body: some View {
        VStack(spacing: 10) {
            ForEach(visibleDays.sorted(), id: \.self) { day in
                let dayCourses = (byDay[day] ?? []).sorted { $0.startNode < $1.startNode }
                DetailDayCard(day: day, courses: dayCourses, isToday: day == today,
                              displayMode: displayMode, timeJson: timeJson,
                              isGrey: greyDays.contains(day),
                              onCourseClick: onCourseClick)
            }
        }
        .padding(12)
        .background(colors.surfaceContainerHigh)
        .cornerRadius(SleepyShapes.large)
    }
}

// ← DetailDayCard
private struct DetailDayCard: View {
    @Environment(\.localWakeUpColors) private var colors
    let day: Int
    let courses: [CourseEntity]
    let isToday: Bool
    var displayMode: String = "node"
    var timeJson: String = ""
    var isGrey: Bool = false
    let onCourseClick: (CourseEntity) -> Void

    var body: some View {
        let greyFg = colors.onSurfaceVariant.opacity(SleepyTheme.Alpha.inactive)
        VStack(spacing: 8) {
            // 头部: 星期 + 今天标记
            HStack {
                Text(DateUtils.localizedDay(day) + (isToday ? L10n.format("today_suffix") : ""))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isGrey ? greyFg : colors.onSurface)
                Spacer()
            }

            if courses.isEmpty {
                Text(DateUtils.localizedDay(day) + L10n.format("no_course_today"))
                    .font(.system(size: 12))
                    .foregroundColor(isGrey ? greyFg : colors.onSurfaceVariant)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 7) {
                    ForEach(courses) { c in
                        LessonRow(course: c, displayMode: displayMode, timeJson: timeJson,
                                  isGrey: isGrey) {
                            onCourseClick(c)
                        }
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        // 空课 surfaceContainerLow(← DetailDayCard L597), 无描边
        .background(courses.isEmpty ? colors.surfaceContainerLow : colors.surface)
        .cornerRadius(SleepyShapes.medium)
    }
}

// ← LessonRow
private struct LessonRow: View {
    @Environment(\.localWakeUpColors) private var colors
    @Environment(\.localCoursePalette) private var palette
    let course: CourseEntity
    let displayMode: String
    let timeJson: String
    var isGrey: Bool = false
    let onClick: () -> Void

    var body: some View {
        let isDark = CourseColorUtil.isPaletteDark(palette)
        let bg = CourseColorUtil.pickCourseColorSwiftUI(
            course, isDark: isDark, neutralColor: colors.surfaceVariant,
            colorless: AppPrefs.shared.isCourseColorless())
        let fg = CourseColorUtil.textColorOn(bg: bg, isDark: isDark, onSurface: colors.onSurface)
        // 节假日灰显 ← effectiveBg/effectiveFg/textDecoration
        let effectiveBg = isGrey ? bg.opacity(SleepyTheme.Alpha.inactive) : bg
        let effectiveFg = isGrey ? fg.opacity(SleepyTheme.Alpha.inactive) : fg
        let strikethrough = isGrey && AppPrefs.shared.getHolidayStyle() == "strikethrough"

        // time 模式: 时间段在连字符后折行; node 模式: 节次标签
        let timeParts: (String, String)? = displayMode == "time" && !timeJson.isEmpty
            ? TimeTableUtils.courseTimeParts(courseStartNode: course.startNode, courseStep: course.step,
                                             timeJson: timeJson, ownTime: course.ownTime,
                                             startTime: course.startTime, endTime: course.endTime)
            : nil
        let nodeLabel = course.nodeString(isShort: true)

        // meta: 教师 · 教室
        let meta: String = {
            var s = ""
            if !course.teacher.isEmpty { s += course.teacher }
            if !course.room.isEmpty {
                if !s.isEmpty { s += " · " }
                s += course.room
            }
            return s
        }()

        Button(action: onClick) {
            HStack(alignment: .top, spacing: 8) {
                if let parts = timeParts {
                    Text("\(parts.0)-\n\(parts.1)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(effectiveFg)
                        .strikethrough(strikethrough)
                        .frame(width: 42, alignment: .leading)
                } else {
                    Text(nodeLabel)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(effectiveFg)
                        .strikethrough(strikethrough)
                        .frame(width: 42, alignment: .leading)
                        .lineLimit(1)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(course.courseName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(effectiveFg)
                        .strikethrough(strikethrough)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if !meta.isEmpty {
                        Text(meta)
                            .font(SleepyTextStyle.smallMeta())
                            .foregroundColor(effectiveFg.opacity(SleepyTheme.Alpha.highContent))
                            .strikethrough(strikethrough)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(effectiveBg)
            .cornerRadius(SleepyShapes.medium)
        }
        .buttonStyle(SleepyButtonStyle())
        .accessibilityIdentifier("lesson_\(course.id)")   // ← G5: 详情锚点
    }
}

// =====================================================================================
// 公共小组件
// =====================================================================================

// ← SectionHead
struct SectionHead: View {
    @Environment(\.localWakeUpColors) private var colors
    let title: String
    var action: String? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(SleepyTextStyle.sectionHead())
                .foregroundColor(colors.onSurface)
            Spacer()
            if let action = action {
                Text(action)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(colors.primary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
