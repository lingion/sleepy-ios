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
            // 算出每列宽度(dp)
            let colW = max((geo.size.width - 16 - timeW - gapW * CGFloat(dayCount + 1)) / CGFloat(dayCount), 0)
            let gridH = rowH * CGFloat(maxNode)   // grid 内容区固定高度

            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    // ---- 表头 ----
                    HStack(spacing: gapW) {
                        Spacer().frame(width: timeW)
                        ForEach(sortedDays, id: \.self) { day in
                            let dateStr: String? = {
                                guard showDate, !startDate.isEmpty,
                                      let d = DateUtils.dateOfWeek(startDate: startDate, week: currentWeek, dayOfWeek: day) else { return nil }
                                return DateUtils.shortDate(d)
                            }()
                            DayHeadCell(day: day, isToday: day == today,
                                        courseCount: courses.filter { $0.day == day }.count,
                                        dateStr: dateStr)
                                .frame(width: colW)
                                .frame(height: dateStr != nil ? 56 : headH)
                        }
                    }
                    .frame(height: headH)

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

                                CourseOverlayCard(course: course, isDark: CourseColorUtil.isPaletteDark(palette)) {
                                    onCourseClick(course)
                                }
                                .frame(width: colW, height: cardH)
                                .offset(x: cardX, y: cardY)
                            }
                        }
                    }
                    .frame(width: geo.size.width - 16, height: gridH, alignment: .topLeading)
                }
                .padding(8)
            }
        }
        .background(colors.surfaceContainerHigh)
        .cornerRadius(SleepyShapes.large)
        .overlay(
            RoundedRectangle(cornerRadius: SleepyShapes.large)
                .strokeBorder(colors.outline.opacity(SleepyTheme.Alpha.tinted), lineWidth: 0.5)
        )
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
            Text(slot.timeString)
                .font(SleepyTextStyle.micro())
                .foregroundColor(colors.onSurfaceVariant)
                .lineLimit(1)
        }
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colors.surface)
        .cornerRadius(SleepyShapes.medium)
        .overlay(
            RoundedRectangle(cornerRadius: SleepyShapes.medium)
                .strokeBorder(colors.outline.opacity(SleepyTheme.Alpha.tinted), lineWidth: 0.5)
        )
        .padding(2)
    }
}

// ← CourseOverlayCard
private struct CourseOverlayCard: View {
    @Environment(\.localWakeUpColors) private var colors
    let course: CourseEntity
    let isDark: Bool
    let onClick: () -> Void

    var body: some View {
        let bg = CourseColorUtil.pickCourseColorSwiftUI(
            course, isDark: isDark,
            neutralColor: colors.surfaceVariant,
            colorless: AppPrefs.shared.isCourseColorless())
        let fg = CourseColorUtil.textColorOn(bg: bg, isDark: isDark, onSurface: colors.onSurface)
        // 副信息(教室/教师/无) — grid_sub_info 设置决定
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
                    // 无副信息: 课程名整体居中(原行为)
                    Text(course.courseName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(fg)
                        .lineLimit(6)
                        .multilineTextAlignment(.center)
                } else {
                    // 有副信息: 课程名在上半区居中, 副信息贴卡底
                    VStack(spacing: 0) {
                        Text(course.courseName)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(fg)
                            .lineLimit(6)
                            .multilineTextAlignment(.center)
                            .frame(maxHeight: .infinity)
                        Text(subText)
                            .font(SleepyTextStyle.micro())
                            .foregroundColor(fg.opacity(SleepyTheme.Alpha.highContent))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .padding(4)
        .background(bg)
        .cornerRadius(SleepyShapes.medium)
        .overlay(
            RoundedRectangle(cornerRadius: SleepyShapes.medium)
                .strokeBorder(colors.outline.opacity(SleepyTheme.Alpha.tinted), lineWidth: 0.5)
        )
        .padding(2)
    }
}

// ← DayHeadCell
private struct DayHeadCell: View {
    @Environment(\.localWakeUpColors) private var colors
    let day: Int
    let isToday: Bool
    let courseCount: Int
    var dateStr: String? = nil

    var body: some View {
        let bg = isToday ? colors.primaryContainer : colors.surface
        let fg = isToday ? colors.onPrimaryContainer : colors.onSurface
        let subFg = isToday ? colors.onPrimaryContainer.opacity(SleepyTheme.Alpha.highContent)
                            : colors.onSurfaceVariant

        VStack(spacing: 1) {
            Text(DateUtils.localizedDay(day))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(fg)
                .lineLimit(1)
            if let dateStr = dateStr {
                Text(dateStr)
                    .font(.system(size: 10))
                    .foregroundColor(subFg)
                    .lineLimit(1)
            } else {
                Text(courseCount == 0 ? L10n.format("no_course")
                                      : L10n.format("course_count_format", courseCount))
                    .font(SleepyTextStyle.micro())
                    .foregroundColor(subFg)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(bg)
        .cornerRadius(SleepyShapes.large)
        .overlay(
            RoundedRectangle(cornerRadius: SleepyShapes.large)
                .strokeBorder(colors.outline.opacity(SleepyTheme.Alpha.tinted), lineWidth: 0.5)
        )
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

    var body: some View {
        let byDay = Dictionary(grouping: courses, by: { $0.day })

        ScrollView(.vertical) {
            VStack(spacing: 0) {
                WeekStrip(byDay: byDay, visibleDays: visibleDays, today: today)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                DetailPanel(byDay: byDay, visibleDays: visibleDays, displayMode: displayMode,
                            timeJson: timeJson, today: today, onCourseClick: onCourseClick)
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

    var body: some View {
        HStack(spacing: 6) {
            ForEach(visibleDays.sorted(), id: \.self) { day in
                DaySummaryCell(day: day, courses: byDay[day] ?? [], isToday: day == today)
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

    var body: some View {
        let bg = isToday ? colors.primaryContainer : colors.surfaceContainer
        let fg = isToday ? colors.onPrimaryContainer : colors.onSurface

        VStack(spacing: 4) {
            // 日期
            Text(DateUtils.localizedDay(day))
                .font(SleepyTextStyle.dayLabel())
                .foregroundColor(fg)

            Spacer().frame(height: 6)

            // Chip: 课程数 — 列窄换行退化为纯数字(Android textMeasurer 逻辑)
            if courses.isEmpty {
                Spacer().frame(height: 14)
            } else {
                // 等价适配: minimumScaleFactor 替代 measure 换行检测
                Text("\(courses.count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(colors.onSurfaceVariant)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(colors.surfaceVariant)
                    .cornerRadius(50)
                    .lineLimit(1)
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
    let onCourseClick: (CourseEntity) -> Void

    var body: some View {
        VStack(spacing: 10) {
            ForEach(visibleDays.sorted(), id: \.self) { day in
                let dayCourses = (byDay[day] ?? []).sorted { $0.startNode < $1.startNode }
                DetailDayCard(day: day, courses: dayCourses, isToday: day == today,
                              displayMode: displayMode, timeJson: timeJson,
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
    let onCourseClick: (CourseEntity) -> Void

    var body: some View {
        VStack(spacing: 8) {
            // 头部: 星期 + 今天标记
            HStack {
                Text(DateUtils.localizedDay(day) + (isToday ? L10n.format("today_suffix") : ""))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(colors.onSurface)
                Spacer()
            }

            if courses.isEmpty {
                Text(DateUtils.localizedDay(day) + L10n.format("no_course_today"))
                    .font(.system(size: 12))
                    .foregroundColor(colors.onSurfaceVariant)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 7) {
                    ForEach(courses) { c in
                        LessonRow(course: c, displayMode: displayMode, timeJson: timeJson) {
                            onCourseClick(c)
                        }
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(courses.isEmpty ? Color.clear : colors.surface)
        .cornerRadius(SleepyShapes.medium)
        .overlay(
            // 空课: outlineVariant 描边卡
            Group {
                if courses.isEmpty {
                    RoundedRectangle(cornerRadius: SleepyShapes.medium)
                        .strokeBorder(colors.outlineVariant, lineWidth: 1)
                }
            }
        )
    }
}

// ← LessonRow
private struct LessonRow: View {
    @Environment(\.localWakeUpColors) private var colors
    @Environment(\.localCoursePalette) private var palette
    let course: CourseEntity
    let displayMode: String
    let timeJson: String
    let onClick: () -> Void

    var body: some View {
        let isDark = CourseColorUtil.isPaletteDark(palette)
        let bg = CourseColorUtil.pickCourseColorSwiftUI(
            course, isDark: isDark, neutralColor: colors.surfaceVariant,
            colorless: AppPrefs.shared.isCourseColorless())
        let fg = CourseColorUtil.textColorOn(bg: bg, isDark: isDark, onSurface: colors.onSurface)

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
                        .foregroundColor(fg)
                        .frame(width: 42, alignment: .leading)
                } else {
                    Text(nodeLabel)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(fg)
                        .frame(width: 42, alignment: .leading)
                        .lineLimit(1)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(course.courseName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(fg)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if !meta.isEmpty {
                        Text(meta)
                            .font(SleepyTextStyle.smallMeta())
                            .foregroundColor(fg.opacity(SleepyTheme.Alpha.highContent))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(bg)
            .cornerRadius(SleepyShapes.medium)
        }
        .buttonStyle(.plain)
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
