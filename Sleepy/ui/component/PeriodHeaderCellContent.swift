// PeriodHeaderCellContent.swift — ← ui/component/PeriodHeaderCellContent.kt 逐行翻译 (GPL-3.0)
// 三行式 / 老式节次表头卡片内容 — 预览/周视图/小组件唯一的宽度事实来源 + 渲染入口。
//
// 行为契约(逐行对齐 Compose 版):
//   - layout == "three_line": 悬挂式 (hanging) 三行, 字号自适应 (PeriodHeaderAdaptiveFont)
//   - layout == "legacy"      : 两行, dash 轴对齐 (LegacyDashColumn / VerticalFit)
//   - sharedFont / sharedPlacement / sharedLegacyAxis 整列同源, 来自上游网格侧
//   - 内边距 0 — 卡片层负责 (与 Android 同一契约)

import SwiftUI

/** ← PERIOD_HEADER_CARD_PAD_DP = 3dp (卡片内边距事实来源, 预览/网格/widget 同一常量). */
let periodHeaderCardPadDp: CGFloat = 3

/// 三行式表头字号/行高常量(基线 11sp/12sp, 乘 scale 联动)。
/// ← headerTimeStyle / headerLabelStyle: 仅作为宽度预算基线, 实际绘制字号由卡片尺寸自适应。
func headerTimeStyle(scale: CGFloat) -> Font {
    .system(size: 11 * scale) // ← SleepyTextStyle.micro + fontSize 11*scale
}
func headerLabelStyle(scale: CGFloat) -> Font {
    .system(size: 12 * scale, weight: .semibold) // ← SleepyTextStyle.smallMeta SemiBold 12*scale
}

/// ← headerTimeStyle lineHeight = (13f * scale).sp — Android 强制行高, 与字号 11sp 不成自然比例,
/// 宽度预算/legacy 行高都必须用这一常数, 禁用 UIFont.lineHeight (≈1.19×) 近似。
func headerTimeLineHeightPx(scale: CGFloat) -> CGFloat { 13 * scale }
/// ← headerLabelStyle lineHeight = (14f * scale).sp
func headerLabelLineHeightPx(scale: CGFloat) -> CGFloat { 14 * scale }

/** 自适应字号 → SwiftUI Font: 数值单位是 sp (font.px 与 density 无关的字号语义)。*/
func adaptiveHeaderTimeStyle(scale: CGFloat, font: PeriodHeaderAdaptiveFont) -> Font {
    .system(size: font.timeSize * scale)
}
func adaptiveHeaderLabelStyle(scale: CGFloat, font: PeriodHeaderAdaptiveFont) -> Font {
    .system(size: font.labelSize * scale, weight: .semibold)
}

/// 节次表头单元格(预览/周视图/小组件共用) — 真实网格列宽与设置页预览卡共用同一算法。
struct PeriodHeaderCellContent: View {
    @Environment(\.localWakeUpColors) private var colors

    /// ← data class TimeSlot 的渲染期最小集; iOS TimeSlot 已存在于 CourseTableView.swift,
    /// 渲染函数单独解构字段避免跨文件耦合。
    let displayStart: String
    let displayEnd: String
    let nodeStart: Int
    let nodeEnd: Int
    /// 渲染期占位节次(buildRenderSlotPlan 生成的空档): label 空 = 占位行
    let isPlaceholder: Bool

    let layout: String      // "three_line" | "legacy"
    let style: String       // "arabic" | "chinese" | "financial" | "circled" | "roman"
    var scale: CGFloat = 1
    var hangingUnitsOverride: CGFloat? = nil
    var showXOverride: Bool? = nil
    var sharedFont: PeriodHeaderAdaptiveFont? = nil
    var sharedPlacement: PeriodHeaderPlacement? = nil
    var sharedLegacyAxis: CGFloat? = nil

    var body: some View {
        // 内边距由卡片层统一负责, 这里不再叠加 — Compose 版同口径
        GeometryReader { geo in
            let cardW = geo.size.width
            let cardH = geo.size.height
            let showX = showXOverride ?? AppPrefs.shared.isPeriodHeaderShowX()  // ← showXOverride ?: AppPrefs.isPeriodHeaderShowX(context)
            let label: String = (showX && nodeStart == nodeEnd)
                ? PeriodHeaderFormatter.fullLabel(nodeStart, style)
                : PeriodHeaderFormatter.range(nodeStart, nodeEnd, style)

            if layout == "three_line" {
                threeLineBody(cardW: cardW, cardH: cardH, label: label, showX: showX)
            } else {
                legacyBody(cardW: cardW, cardH: cardH, label: label)
            }
        }
    }

    // MARK: - 三行式

    /// 三行式测量结果 (纯计算, 非 ViewBuilder — if 赋值块在 ViewBuilder 里不合法)
    private struct ThreeLineMeasure {
        let adLabelFont: UIFont
        let adTimeFont: UIFont
        let startH: CGFloat
        let labelH: CGFloat
        let contentHeight: CGFloat
        let timeBaseLeft: CGFloat
        let labelLeft: CGFloat
        let inkUnionWidthPx: CGFloat
        let placement: PeriodHeaderPlacement
    }

    private func measureThreeLine(cardW: CGFloat, cardH: CGFloat, label: String, showX: Bool) -> ThreeLineMeasure {
        // 文字测量用 UIKit UIFont 实例 (SwiftUI Font 在 View 外测不准, 必须底层 UIFont)
        let labelFont: UIFont = UIFont.systemFont(ofSize: 12 * scale, weight: .semibold)
        let timeFont: UIFont = UIFont.systemFont(ofSize: 11 * scale)
        let baseStartW = textWidth(displayStart, font: timeFont)
        let baseEndW = textWidth(displayEnd, font: timeFont)
        let baseLabelW = textWidth(label, font: labelFont)
        let hangingUnits = (hangingUnitsOverride ?? CGFloat(AppPrefs.shared.getPeriodHeaderHanging()))
            .clamped(to: -1...1) // ← (hangingUnitsOverride ?: AppPrefs.getPeriodHeaderHanging(context)).coerceIn(-1f, 1f)
        let baseMetrics = PeriodHeaderMetrics(
            startWidth: baseStartW, endWidth: baseEndW, labelWidth: baseLabelW,
            showX: showX && nodeStart == nodeEnd
        )
        // sharedFont 来自上游网格列最紧约束; 未传(预览)时按本卡自适应
        var adaptiveFont = sharedFont ?? PeriodHeaderAdaptiveFont.compute(
            cardWidthSp: cardW, cardHeightSp: cardH,
            inkWidthSp: baseMetrics.inkWidth(u: hangingUnits),
            timeMaxWidthSp: baseMetrics.timeMax,
            labelWidthSp: baseLabelW
        )
        // 重测自适应字号下的字宽/字高
        var adLabelFont: UIFont = .systemFont(ofSize: adaptiveFont.labelSize * scale, weight: .semibold)
        var adTimeFont: UIFont = .systemFont(ofSize: adaptiveFont.timeSize * scale)
        var startWidth = textWidth(displayStart, font: adTimeFont)
        var endWidth = textWidth(displayEnd, font: adTimeFont)
        var labelWidth = textWidth(label, font: adLabelFont)
        // 行盒高 = 强制 lineHeight = size × 1.25 × scale (← adaptiveHeaderTimeStyle/LabelStyle),
        // 禁用 UIFont.lineHeight (自然行高 ≈1.19–1.21×, 比 Android 小 ~5% → 缩字守卫/行距不像素同源)
        var startH = adaptiveHeaderLineHeightPx(size: adaptiveFont.timeSize, scale: scale)
        var labelH = adaptiveHeaderLineHeightPx(size: adaptiveFont.labelSize, scale: scale)
        var endH = adaptiveHeaderLineHeightPx(size: adaptiveFont.timeSize, scale: scale)
        // 不重叠硬约束: 三行行盒总高 > 卡高 → 等比缩字, 宁小勿叠
        let requiredHPx = startH + labelH + endH
        if requiredHPx > cardH && requiredHPx > 0 && cardH > 0 {
            let shrink = cardH / requiredHPx
            adaptiveFont = PeriodHeaderAdaptiveFont(
                timeSize: max(adaptiveFont.timeSize * shrink, 0.1),
                labelSize: max(adaptiveFont.labelSize * shrink, 0.1)
            )
            adLabelFont = .systemFont(ofSize: adaptiveFont.labelSize * scale, weight: .semibold)
            adTimeFont = .systemFont(ofSize: adaptiveFont.timeSize * scale)
            startWidth = textWidth(displayStart, font: adTimeFont)
            endWidth = textWidth(displayEnd, font: adTimeFont)
            labelWidth = textWidth(label, font: adLabelFont)
            startH = adaptiveHeaderLineHeightPx(size: adaptiveFont.timeSize, scale: scale)
            labelH = adaptiveHeaderLineHeightPx(size: adaptiveFont.labelSize, scale: scale)
            endH = adaptiveHeaderLineHeightPx(size: adaptiveFont.timeSize, scale: scale)
        }
        let metrics = PeriodHeaderMetrics(
            startWidth: startWidth, endWidth: endWidth, labelWidth: labelWidth,
            showX: showX && nodeStart == nodeEnd
        )
        let placement = sharedPlacement ?? metrics.solvePlacement(u: hangingUnits)
        // 真实墨迹并集左/右缘 (px, 相对元素矩形左缘)
        let timeMaxW = max(startWidth, endWidth)
        let inkLeftPx = min(placement.timeBaseLeft, placement.labelLeft)
        let inkRightPx = max(placement.timeBaseLeft + timeMaxW, placement.labelLeft + labelWidth)
        let inkUnionWidthPx = max(inkRightPx - inkLeftPx, 0)
        let contentHeight = startH + labelH + endH
        let timeBaseLeft = placement.timeBaseLeft - inkLeftPx
        let labelLeft = placement.labelLeft - inkLeftPx
        return ThreeLineMeasure(
            adLabelFont: adLabelFont, adTimeFont: adTimeFont,
            startH: startH, labelH: labelH,
            contentHeight: contentHeight, timeBaseLeft: timeBaseLeft,
            labelLeft: labelLeft, inkUnionWidthPx: inkUnionWidthPx,
            placement: placement
        )
    }

    @ViewBuilder
    private func threeLineBody(cardW: CGFloat, cardH: CGFloat, label: String, showX: Bool) -> some View {
        let m = measureThreeLine(cardW: cardW, cardH: cardH, label: label, showX: showX)
        let adLabelFont = m.adLabelFont
        let adTimeFont = m.adTimeFont
        let contentHeight = m.contentHeight
        let timeBaseLeft = m.timeBaseLeft
        let labelLeft = m.labelLeft

        // ← Android 结构: 外层 Box(fillMaxSize, Center) { 内层 Box(inkUnionWidth × contentHeight) {
        //     Text(start) TopStart.offset(timeBaseLeft); Text(label) CenterStart.offset(labelLeft);
        //     Text(end) BottomStart.offset(timeBaseLeft) } }
        // 三行行盒总高可能 < 卡高 (缩字守卫触发时) — 盒高 = 行盒总高, 外层 Center 上下间隙均分,
        // 水平同理左右均分 (Android 2026-10-04 实测: 盒左对齐使整块贴卡左而非居中)。
        let topPad = (cardH - contentHeight) / 2
        // 左不钳 0: 墨迹盒 > 卡宽时 Android Center 让两侧均分溢出 (overflow Visible 同口径)
        let leftPad = (cardW - m.inkUnionWidthPx) / 2

        ZStack(alignment: .topLeading) {
            // 行盒 = 强制 lineHeight 框 (← Compose 单行测量高 = lineHeight 整值):
            // Text 自然行高 ≈1.19–1.21×, 直接摆放会比守卫/垂直解使用的行盒矮 ~5%;
            // 用 .frame(height:) 钉回 1.25×size×scale, 字形盒在行盒内居中 (半 leading 近似)。
            // 第一行: 开始时间, 行盒顶 = contentHeight 顶, x = timeBaseLeft
            Text(displayStart)
                .font(Font(adTimeFont))
                .foregroundColor(colors.onSurfaceVariant)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(height: m.startH, alignment: .center)
                .offset(x: timeBaseLeft + leftPad, y: topPad)
            // 第二行: 标签, 垂直中点对齐, x = labelLeft (端点异锚悬挂偏移)
            // (中点近似 = topPad + startH + (labelH)/2 - labelH/2 = topPad + startH, 用行盒近似)
            Text(label)
                .font(Font(adLabelFont))
                .foregroundColor(colors.onSurface)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(height: m.labelH, alignment: .center)
                .offset(x: labelLeft + leftPad, y: topPad + m.startH)
            // 第三行: 结束时间, 行盒底 = contentHeight 底, x = timeBaseLeft (与第一行同左缘基线)
            Text(displayEnd)
                .font(Font(adTimeFont))
                .foregroundColor(colors.onSurfaceVariant)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(height: m.startH, alignment: .center)
                .offset(x: timeBaseLeft + leftPad, y: topPad + m.startH + m.labelH)
        }
        .frame(width: cardW, height: cardH, alignment: .topLeading)
    }

    // MARK: - Legacy 两行

    @ViewBuilder
    private func legacyBody(cardW: CGFloat, cardH: CGFloat, label: String) -> some View {
        // 测量走共享路径 ← Android legacyRowInk (基准字号, 行高 13×scale/14×scale)
        let rowInk = legacyRowInk(displayStart: displayStart, displayEnd: displayEnd,
                                  label: label, scale: scale)
        let axisX = sharedLegacyAxis ?? max(rowInk.labelPx / 2, rowInk.timeLeftPx)
        let vertical = legacyColumnVerticalFit(
            rows: [rowInk],
            cardContentHeightPx: cardH,
            rowGapPx: 2 * scale
        )
        let baseFont = PeriodHeaderAdaptiveFont(
            timeSize: PeriodHeaderAdaptiveFont.BASE_TIME_SP,
            labelSize: PeriodHeaderAdaptiveFont.BASE_LABEL_SP
        )
        let effectiveScale = scale * vertical.fontScale
        let labelFontScaled = UIFont.systemFont(ofSize: baseFont.labelSize * effectiveScale, weight: .semibold)
        let timeFontScaled = UIFont.systemFont(ofSize: baseFont.timeSize * effectiveScale)
        let labelLeft = axisX - rowInk.labelPx / 2
        let timeLeft = axisX - rowInk.timeLeftPx - rowInk.dashPx / 2

        // 外层 Box 摆两行 (label + time) 绝对定位
        ZStack(alignment: .topLeading) {
            // 行盒钉回强制 lineHeight (size×1.25×effectiveScale, ← adaptiveHeader*Style),
            // 字形盒行内居中 = Compose 半 leading 布局; 行距由 offset 保证 (行盒紧贴)。
            // 第一行: label 水平以 dash 轴居中
            Text(label)
                .font(Font(labelFontScaled))
                .foregroundColor(colors.onSurface)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(height: adaptiveHeaderLineHeightPx(size: baseFont.labelSize, scale: effectiveScale))
                .offset(x: labelLeft, y: vertical.labelTopPx)
            // 第二行: 时间串 start/dash/end 整体左缘 = timeLeft
            // (行盒高钉回 time 强制 lineHeight, 与 label 行同口径)
            // ← Android Box{ Text(CenterStart).width(startW) / offset(x=startW).width(dashW) /
            //   offset(x=startW+dashW) }: 每段钉在"基准字号实测宽"的盒里, 缩字 (fontScale<1)
            //   时 dash/end 锚点不随字形收拢漂移 (HStack 固有宽布局会把 dash 左移, dash 轴偏)。
            ZStack(alignment: .topLeading) {
                Text(displayStart)
                    .font(Font(timeFontScaled))
                    .foregroundColor(colors.onSurfaceVariant)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(width: rowInk.timeLeftPx, alignment: .leading)
                Text("-")
                    .font(Font(timeFontScaled))
                    .foregroundColor(colors.onSurfaceVariant)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(width: rowInk.dashPx, alignment: .leading)
                    .offset(x: rowInk.timeLeftPx)
                Text(displayEnd)
                    .font(Font(timeFontScaled))
                    .foregroundColor(colors.onSurfaceVariant)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .offset(x: rowInk.timeLeftPx + rowInk.dashPx)
            }
            .frame(height: adaptiveHeaderLineHeightPx(size: baseFont.timeSize, scale: effectiveScale))
            .offset(x: timeLeft, y: vertical.timeTopPx)
        }
        // ← Android Box(fillMaxSize) 默认 TopStart: 两行按 vertical/axis 解出的绝对
        // offset 从盒左上起算; 缺 alignment 参数会退化为 center, 卡大于内容时整体下移
        // (label/time 的 offset 语义 = 相对盒顶, 不是相对中心)。
        .frame(width: cardW, height: cardH, alignment: .topLeading)
    }

    // (无文字测量成员方法 — textWidth / 行高公式均为文件作用域自由函数, 与三个宽度 API 同源)
}

// MARK: - 文字测量 (UIKit 底层, SwiftUI Font 在 View 外测不准)
// 文件作用域自由函数: 渲染 (PeriodHeaderCellContent) 与宽度预算 API
// (threeLineWidthDp / legacyLineWidthDp / legacyRowInk) 共享同一测量路径。

func textWidth(_ s: String, font: UIFont) -> CGFloat {
    let attrs: [NSAttributedString.Key: Any] = [.font: font]
    let size = (s as NSString).size(withAttributes: attrs)
    return size.width
}

/// ← adaptiveHeaderTimeStyle / adaptiveHeaderLabelStyle 强制 lineHeight = size × 1.25 × scale
/// (Android 渲染侧不用系统自然行高; Compose 单行测量高 = lineHeight 整值)。
func adaptiveHeaderLineHeightPx(size: CGFloat, scale: CGFloat) -> CGFloat { size * 1.25 * scale }

/// 三行表头列所需宽度(pt ← threeLineWidthDp, dp→pt 1:1 项目惯例):
/// 在用户滑杆移动到极限时仍能完整显示三行文字。
/// 联合墨迹包络 = timeMax + 2×标签宽 (端点异锚各悬出半标签), 下限 = 3×开始时间宽轨道。
/// 与 PeriodHeaderCellContent 共享同一公式, 真实网格列宽与设置页预览卡共用。
///
/// 2026-09-30 修截断: 列宽按自适应字号 (16sp) 投影, 不再用基准字号 (12sp) 测 —
/// 基准 12sp 测的墨迹宽比 16sp 实际渲染窄 33%, 列宽不够 → 文字被裁掉。
func threeLineWidthDp(
    slots: [TimeSlot],
    headerStyle: String,
    scale: CGFloat,
    hangingUnits: CGFloat = 0,
    showX: Bool = false,
    targetLabelSp: CGFloat = 16
) -> CGFloat {
    let timeFont = UIFont.systemFont(ofSize: 11 * scale)              // ← headerTimeStyle
    let labelFont = UIFont.systemFont(ofSize: 12 * scale, weight: .semibold) // ← headerLabelStyle
    // 投影到目标字号: 基准 12sp 测的宽度 × (目标字号 / 基准字号)
    let projection = targetLabelSp / PeriodHeaderAdaptiveFont.BASE_LABEL_SP
    var maxGroup: CGFloat = 0
    for slot in slots {
        let label = (showX && slot.nodeStart == slot.nodeEnd)
            ? PeriodHeaderFormatter.fullLabel(slot.nodeStart, headerStyle)
            : PeriodHeaderFormatter.range(slot.nodeStart, slot.nodeEnd, headerStyle)
        let metrics = PeriodHeaderMetrics(
            startWidth: textWidth(slot.displayStart, font: timeFont),
            endWidth: textWidth(slot.displayEnd, font: timeFont),
            labelWidth: textWidth(label, font: labelFont),
            showX: showX && slot.nodeStart == slot.nodeEnd
        )
        maxGroup = max(maxGroup, metrics.inkWidth(u: hangingUnits) * projection)
    }
    // + 卡片内边距 ×2 (periodHeaderCardPadDp, 预览/网格/widget 同一常量), 乘 scale
    return maxGroup + 2 * periodHeaderCardPadDp * scale
}

/// 老式表头列所需宽度(pt ← legacyLineWidthDp): 用户 2026-10-03 第二轮定稿 — dash 轴几何。
/// 列内所有行的 dash (时间串 "08:00-09:35" 中间 "-") 落在同一 X, 标签同轴居中;
/// 列宽 = 轴左最大延伸 + 轴右最大延伸 + pad×2 ("最宽的那一行, 余量也流出来")。
/// 与 PeriodHeaderCellContent legacy 分支共享同一字号, 测量与渲染同源。
func legacyLineWidthDp(
    slots: [TimeSlot],
    headerStyle: String,
    scale: CGFloat,
    showX: Bool = false
) -> CGFloat {
    let timeFont = UIFont.systemFont(ofSize: 11 * scale)
    let labelFont = UIFont.systemFont(ofSize: 12 * scale, weight: .semibold)
    let rows = slots.filter { !$0.isPlaceholder }.map { slot -> LegacyDashRowInk in
        let label = (showX && slot.nodeStart == slot.nodeEnd)
            ? PeriodHeaderFormatter.fullLabel(slot.nodeStart, headerStyle)
            : PeriodHeaderFormatter.range(slot.nodeStart, slot.nodeEnd, headerStyle)
        // 宽度预算只用横向墨迹 — 行高留 0 (与 Android LegacyDashRowInk 默认一致)
        return LegacyDashRowInk(
            labelPx: textWidth(label, font: labelFont),
            timeLeftPx: textWidth(slot.displayStart, font: timeFont),
            dashPx: textWidth("-", font: timeFont),
            timeRightPx: textWidth(slot.displayEnd, font: timeFont)
        )
    }
    let geometry = legacyDashColumnPx(rows: rows, padPx: 0)
    // + 卡片内边距 ×2 (periodHeaderCardPadDp, 预览/网格/widget 同一常量), 乘 scale
    return geometry.columnWidthPx + 2 * periodHeaderCardPadDp * scale
}

/// 老式表头单行墨迹 ← Android legacyRowInk: 标签整宽 + 时间串三段 (start / dash / end,
/// px 实测, 含行高)。网格侧轴求解与 legacyBody 渲染共享本测量路径。
func legacyRowInk(
    displayStart: String,
    displayEnd: String,
    label: String,
    scale: CGFloat
) -> LegacyDashRowInk {
    // ← headerTimeStyle / headerLabelStyle (11sp lineHeight 13 / 12sp lineHeight 14)
    let timeFont = UIFont.systemFont(ofSize: 11 * scale)
    let labelFont = UIFont.systemFont(ofSize: 12 * scale, weight: .semibold)
    return LegacyDashRowInk(
        labelPx: textWidth(label, font: labelFont),
        timeLeftPx: textWidth(displayStart, font: timeFont),
        dashPx: textWidth("-", font: timeFont),
        timeRightPx: textWidth(displayEnd, font: timeFont),
        // 行高取两行 union 用的实测值: label=标签行高, time=start 行高
        // (dash/end 与 start 同字号同行, 行高一致; 单值代表整行)
        labelHeightPx: headerLabelLineHeightPx(scale: scale),
        timeHeightPx: headerTimeLineHeightPx(scale: scale)
    )
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
