// WidgetCourseCard.swift — ← WidgetBitmapRenderers.kt drawCourse
// 课程胶囊卡(Today/TwoDay 列表用):统一取色 + 亮度自适应文字色 + 名称截断。
// Canvas 手绘 → SwiftUI 等价布局:pad 3dp / 圆角 8dp / 名称 BOLD + meta 逐行垂直居中。

import SwiftUI
import UIKit

/// meta 行「时间 · 地点」 ← Android courseMetaLines (WidgetBitmapRenderers.kt:1060) 四分支:
/// 任一侧空白 → 只画另一侧(整宽截断, = Android 单侧 listOf 后 ellipsize 全宽);
/// 双侧都有 → 合并单行放得下就**不截断**(Android fits 分支, 不加省略号);
/// 放不下 → 同一行内时间/地点各占一半宽(分隔符宽度对半摊), 各自字符级截断加省略号
/// (Android ellipsizeBy:1070)。旧实现合并串整串尾部截断 → 窄列地点整段消失。
/// ★ 测量口径差异 [B]: Android paint.measureText / iOS NSAttributedString.size,
///   同字号下宽度近似但不逐位相等; 仅影响截断点 ±1 字, 不影响布局几何。
private struct WidgetMetaLine: View {
    let time: String
    let room: String
    let fontSize: CGFloat

    private static let sep = " · "
    private var uiFont: UIFont { UIFont.systemFont(ofSize: fontSize) }

    var body: some View {
        let combined = time.isEmpty ? room : (time + Self.sep + room)
        if time.isEmpty || room.isEmpty {
            // 单侧: 占满整行, 超宽 SwiftUI 尾部省略 ≈ Android ellipsize 全宽
            Text(combined)
                .font(.system(size: fontSize))
                .lineLimit(1)
        } else {
            // 双侧: GeometryReader 拿真实预算宽后按 Android 同逻辑判定 —
            // 整串放得下 → 不截断 (fits 分支); 放不下 → 时间/地点各占半宽
            // (分隔符宽对半摊, ellipsizeBy:1070)。不用 ViewThatFits (iOS 16+,
            // 目标 15.6); 测量口径见头注 [B]。
            GeometryReader { geo in
                let w = geo.size.width
                if width(combined) <= w {
                    Text(combined)
                        .font(.system(size: fontSize))
                        .fixedSize()
                } else {
                    let half = max((w - width(Self.sep)) / 2, 0)
                    HStack(spacing: 0) {
                        Text(ellipsize(time, maxW: half))
                        Text(Self.sep)
                        Text(ellipsize(room, maxW: half))
                    }
                    .font(.system(size: fontSize))
                    .fixedSize()
                }
            }
            .frame(height: lineHeight)
        }
    }

    private func width(_ s: String) -> CGFloat {
        ceil((s as NSString).size(withAttributes: [.font: uiFont]).width)
    }

    /// 字符级贪心截断 + "…" ← Android ellipsizeBy (1070-1075)
    private func ellipsize(_ s: String, maxW: CGFloat) -> String {
        if width(s) <= maxW { return s }
        var t = s
        while !t.isEmpty && width(t + "…") > maxW { t.removeLast() }
        return t + "…"
    }

    /// UIFont.lineHeight (ascender−descender+leading) — 与 Text 单行高一致口径
    private var lineHeight: CGFloat { uiFont.lineHeight }
}

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
        // ← WidgetBitmapRenderers.kt courseMetaLines (1060) + drawCourse hasMeta (112):
        // trim 后判空, 任一侧空白只画另一侧 (不再产出 " · A101" 前导分隔符)
        let t = timeStr.trimmingCharacters(in: .whitespaces)
        let r = course.room.trimmingCharacters(in: .whitespaces)
        // ← WidgetBitmapRenderers.kt:153: 灰显行且「删除线」样式 → 课程名加删除线 (仅 dim 不删线是旧缺口)
        let strike = isGrey && AppPrefs.shared.getHolidayStyle() == "strikethrough"

        VStack(alignment: .leading, spacing: 2) {
            Text(displayName)
                .strikethrough(strike)
                .font(.system(size: fontSizeSp, weight: .bold))
                .lineLimit(1)
            if !t.isEmpty || !r.isEmpty {
                WidgetMetaLine(time: t, room: r, fontSize: fontSizeSp - 2)
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

/// 胶囊共用几何: 文本水平内距 8·s、字 11·s bold、圆角 = 显示高/2。
/// ★ minWidth: Today 的 bitmap 有整胶囊最小宽 30dp (renderNavCapsule:597
///   max(30, 文本+16)); TwoDay/WeekList 页脚**没有最小宽** (renderTwoDayRegular:1461
///   pillW = 文本+16, 仅上限 colW) → 页脚传 nil, 勿再统一。
/// ★ frame(minWidth:).padding(8) 的顺序使整胶囊最小宽 = minWidth+16 (含 padding)。
private struct WidgetCapsulePill: View {
    let text: String
    let scheme: WidgetScheme
    let height: CGFloat       // 胶囊显示高 (圆角 = h/2; Today 16 ← 20×0.8, 页脚 18)
    let fontScale: CGFloat    // Today = 0.8 ← ImageView 16dp + adjustViewBounds 等比缩放
    let minTextWidth: CGFloat? // Today = 14·0.8 (整胶囊 30·0.8=24); 页脚 nil = 无最小宽

    var body: some View {
        Text(text)
            .font(.system(size: 11 * fontScale, weight: .bold))
            .foregroundColor(scheme.onSurfaceVariant)
            .modifier(OptionalMinWidth(width: (minTextWidth ?? 0) * fontScale))
            .padding(.horizontal, 8 * fontScale)
            .frame(height: height)
            .fixedSize(horizontal: true, vertical: false)
            .background(scheme.surfaceVariant)
            .cornerRadius(height / 2)
    }
}

/// minWidth==0 时不加 frame (页脚无最小宽, 对齐 Android text+16 公式)
private struct OptionalMinWidth: ViewModifier {
    let width: CGFloat
    func body(content: Content) -> some View {
        if width > 0 { content.frame(minWidth: width) }
        else { content }
    }
}

/// Today 底部条「+N」胶囊 (8c0fcbea 恒画 / ab27230c 结束态「+0」): surfaceVariant 底 +
/// onSurfaceVariant 字 · 全圆角,不可点。
/// ★ 几何 = Android **显示态**尺寸: bitmap 按 20dp 高 / 整胶囊最小宽 30dp 渲染
///   (WidgetBitmapRenderers.kt:580-595), 但真实视图塞进 16dp 高 ImageView 且
///   adjustViewBounds 等比缩放 ×0.8 (widget_today_nav_static.xml:38-43)
///   → 显示态 = 高 16 · 最小宽 30×0.8=24 · 字 ≈ 8.8 · 内距 6.4 · 圆角 8。
///   文本比 30dp 宽时, Android 显示 max(30,文本+16)×0.8 = 文本×0.8+16×0.8×? ——
///   注意 ×0.8 同时缩文本与内距: 等价于按显示尺寸直接绘制 字 8.8 + 内距 6.4。
/// Android 侧它是底部条里的 ImageView 且**不挂 PendingIntent**(不可点);
/// iOS 侧 widget 整体只有一个 widgetURL,胶囊本身同样不单独响应点击 → 语义一致。
struct WidgetMoreCapsule: View {
    let hidden: Int
    let scheme: WidgetScheme

    var body: some View {
        WidgetCapsulePill(text: WidgetWindowCore.capsuleText(hidden: hidden),
                          scheme: scheme, height: 16, fontScale: 0.8,
                          minTextWidth: 14)
            .accessibilityLabel(L10n.format("more_sections", hidden))
    }
}

/// 列底「+N」胶囊 ← renderTwoDayRegular / renderWeekListRegular 页脚:
/// bitmap 按 18dp 高直接绘制 (无 ImageView 缩放), 整胶囊最小宽 30dp、
/// 内距 8dp、11sp bold、surfaceVariant 底、列内水平居中、全圆角 9,不可点。
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
            WidgetCapsulePill(text: text, scheme: scheme, height: 18, fontScale: 1,
                              minTextWidth: nil)
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
