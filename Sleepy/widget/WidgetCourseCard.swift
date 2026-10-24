// WidgetCourseCard.swift — ← WidgetBitmapRenderers.kt drawCourse
// 课程胶囊卡(Today/TwoDay 列表用):统一取色 + 亮度自适应文字色 + 名称截断。
// Canvas 手绘 → SwiftUI 等价布局:pad 3dp / 圆角 8dp / 名称 BOLD + meta 逐行垂直居中。

import SwiftUI

struct WidgetCourseCard: View {
    let course: CourseEntity
    let timeJson: String
    let scheme: WidgetScheme
    let colorless: Bool
    var fontSizeSp: CGFloat = 12
    var displayMode: String = "node"
    /// issue#22: 同 groupId 全行(含自身) — AUTO/CUSTOM 取色按行判; 空=回退 [course]
    var groupRows: [CourseEntity] = []
    /// issue#26: widget 场景别名 — true 显示别名(trim 后, 空回退原名), false 原名
    var useAlias: Bool = false
    /// 灰显行 (← WidgetBitmapRenderers.kt drawCourse isGrey): 与「删除线」样式合取时课程名加删除线
    var isGrey: Bool = false

    var body: some View {
        // 统一取色入口 (决策 D3) — colorless 灰底传 secondaryContainer
        // issue#22: 改走 *WithGroupRows 三态入口
        let bgColor = CourseColorUtil.pickCourseColorSwiftUIWithGroupRows(course,
            groupRows: groupRows.isEmpty ? [course] : groupRows,
            isDark: scheme.isDark, neutralColor: scheme.secondaryContainer, colorless: colorless)
        // 文字色亮度自适应 (决策 D5-13) — 深色自定义课色上切白字, 浅色底仍 onSurface
        let textColor = CourseColorUtil.textColorOn(bg: bgColor, isDark: scheme.isDark,
                                                    onSurface: scheme.onSurface)
        let timeStr = timeString
        let meta = course.room.isEmpty ? timeStr : "\(timeStr) · \(course.room)"
        // ← WidgetBitmapRenderers.kt:153: 灰显行且「删除线」样式 → 课程名加删除线 (仅 dim 不删线是旧缺口)
        let strike = isGrey && AppPrefs.shared.getHolidayStyle() == "strikethrough"

        VStack(alignment: .leading, spacing: 2) {
            Text(displayName)
                .strikethrough(strike)
                .font(.system(size: fontSizeSp, weight: .bold))
                .lineLimit(1)
            if !meta.isEmpty {
                Text(meta)
                    .font(.system(size: fontSizeSp - 2))
                    .lineLimit(1)
            }
        }
        .foregroundColor(textColor)
        .padding(.horizontal, 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(bgColor)
        .cornerRadius(8)
    }

    // ★ displayMode (决策 D5-12, 对齐 CourseTableView.LessonRow):
    //   "time" → 具体时间段 "08:00-09:35"; "node"(默认) → 节次 "3-4节"
    private var timeString: String {
        if displayMode == "time" && !timeJson.isEmpty {
            let t = TimeTableUtils.courseTimeString(
                courseStartNode: course.startNode,
                courseStep: course.step,
                timeJson: timeJson,
                ownTime: course.ownTime,
                startTime: course.startTime,
                endTime: course.endTime)
            if let t = t { return t }
        }
        return course.nodeString(isShort: true)
    }

    // Android: measureText 超 maxWidth → 逐字截断加 "…"(SwiftUI lineLimit(1) 等价)
    // issue#26: 展示名走 CourseDisplayUtil — useAlias→trim 别名, 空回退原名
    private var displayName: String { CourseDisplayUtil.displayName(course, useAlias) }
}

// MARK: - 「+N」溢出胶囊 ← WidgetBitmapRenderers.renderNavCapsule

/// 溢出胶囊 (8c0fcbea 恒画 / ab27230c 结束态「+0」): 高 20dp · 最小宽 30dp ·
/// 11sp bold · surfaceVariant 底 + onSurfaceVariant 字 · 全圆角。
/// Android 侧它是底部条里的 ImageView 且**不挂 PendingIntent**(不可点);
/// iOS 侧 widget 整体只有一个 widgetURL,胶囊本身同样不单独响应点击 → 语义一致。
struct WidgetMoreCapsule: View {
    let hidden: Int
    let scheme: WidgetScheme

    var body: some View {
        Text(WidgetWindowCore.capsuleText(hidden: hidden))
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(scheme.onSurfaceVariant)
            .frame(minWidth: 30)
            .frame(height: 20)
            .padding(.horizontal, 8)
            .background(scheme.surfaceVariant)
            .cornerRadius(10)
            .accessibilityLabel(L10n.format("more_sections", hidden))
    }
}

/// 列底「+N」胶囊 ← renderTwoDayRegular / renderWeekListRegular 页脚:
/// 高 18 / 水平内距 8 / 11sp bold / surfaceVariant 底 / onSurfaceVariant 字 / 全圆角,不可点。
struct WidgetFooterCapsule: View {
    /// nil = 该列不画页脚 (WeekList 仅在窗口截断时画)
    let text: String?
    let scheme: WidgetScheme

    init(text: String?, scheme: WidgetScheme) {
        self.text = text
        self.scheme = scheme
    }

    var body: some View {
        if let text = text {
            Text(text)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(scheme.onSurfaceVariant)
                .padding(.horizontal, 8)
                .frame(height: 18)
                .background(scheme.surfaceVariant)
                .cornerRadius(9)
        }
    }
}

// MARK: - 渲染行 ← renderTodayRegular / renderTwoDayRegular 的行绘制

/// 一个渲染行 = 一个冲突区域: 无冲突课整宽单卡;冲突课并排分栏(栏间浅细竖线),
/// 同栏多课纵向堆叠(行高由最高栏决定)。与 ConflictLayoutEngine.weekLaneRows 同口径。
struct WidgetCourseRowView: View {
    let row: ConflictLayoutEngine.WeekLaneRow
    /// 全量课程 (AUTO/CUSTOM 取色按同 groupId 行判)
    let allCourses: [CourseEntity]
    let timeJson: String
    let scheme: WidgetScheme
    let colorless: Bool
    var displayMode: String = "node"
    var useAlias: Bool = false
    /// 灰显列 (TwoDay 传 day.isGrey; Today 无灰显传默认 false) → 卡片文字删除线判定
    var isGrey: Bool = false
    var rowHeight: CGFloat = WidgetRowGeometry.rowH
    var fontSizeSp: CGFloat = 11
    var laneFontSizeSp: CGFloat = 10
    var laneGap: CGFloat = 5
    var stackGap: CGFloat = WidgetRowGeometry.stackGap

    var body: some View {
        if row.laneCount <= 1 {
            card(row.courses[0], fontSize: fontSizeSp)
                .frame(height: rowHeight)
        } else {
            HStack(alignment: .top, spacing: 0) {
                ForEach(0..<row.laneCount, id: \.self) { lane in
                    if lane > 0 { separator }
                    laneView(lane)
                        .frame(maxWidth: .infinity, alignment: .top)
                }
            }
        }
    }

    private func laneView(_ lane: Int) -> some View {
        VStack(spacing: stackGap) {
            ForEach(row.courses.filter { (row.laneOf[$0.id] ?? 0) == lane }) { course in
                card(course, fontSize: laneFontSizeSp)
                    .frame(height: rowHeight)
            }
        }
    }

    /// 栏间浅细竖线 ← sepColor = onSurface RGB @ 30% alpha
    private var separator: some View {
        Rectangle()
            .fill(scheme.onSurface.opacity(0.3))
            .frame(width: 1)
            .frame(maxHeight: .infinity)
            .frame(width: laneGap)
    }

    private func card(_ course: CourseEntity, fontSize: CGFloat) -> some View {
        WidgetCourseCard(course: course, timeJson: timeJson, scheme: scheme,
                         colorless: colorless, fontSizeSp: fontSize, displayMode: displayMode,
                         groupRows: allCourses.filter { $0.groupId == course.groupId },
                         useAlias: useAlias, isGrey: isGrey)
    }
}
