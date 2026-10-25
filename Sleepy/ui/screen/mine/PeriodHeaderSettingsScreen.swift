// PeriodHeaderSettingsScreen.swift — ← ui/screen/mine/PeriodHeaderSettingsScreen.kt
// 节次表头设置页: 五种样式实时预览(阿拉伯/中文/财务/圈圈/罗马) + 布局切换(老式/三行式)
// + 显示节号开关 + 三行式悬挂量滑杆(-1..1, 0.1 步进)。
//
// 偏好读写: AppPrefs.getPeriodHeaderLayout/Style/Hanging + isPeriodHeaderShowX
// (v1.0.60 已落地 iOS AppPrefs — 见 AppPrefs.swift "节次表头设置" MARK)。

import SwiftUI

struct PeriodHeaderSettingsScreen: View {
    @Environment(\.localWakeUpColors) private var colors
    let onBack: () -> Void

    private let prefs = AppPrefs.shared

    @State private var layout: String = AppPrefs.shared.getPeriodHeaderLayout()
    @State private var style: String = AppPrefs.shared.getPeriodHeaderStyle()
    @State private var hangingUnits: Float = AppPrefs.shared.getPeriodHeaderHanging()
    @State private var showX: Bool = AppPrefs.shared.isPeriodHeaderShowX()

    var body: some View {
        VStack(spacing: 0) {
            SettingsTopBar(title: L10n.t("appearance_period_header"), onBack: onBack)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // ── 实时预览 ──
                    HeaderStylePreviews(
                        layout: layout,
                        selectedStyle: style,
                        hangingUnits: hangingUnits,
                        showX: showX,
                        onStyleSelected: { value in
                            style = value
                            prefs.setPeriodHeaderStyle(value)
                        })

                    // ── 布局切换(legacy / three_line) ──
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.t("appearance_header_layout"))
                            .font(.system(size: 12, weight: .medium))   // ← labelMedium
                            .foregroundColor(colors.onSurfaceVariant)
                        SegmentedSwitcher(
                            options: [
                                ("legacy", L10n.t("appearance_layout_legacy")),
                                ("three_line", L10n.t("appearance_layout_three_line"))
                            ],
                            selected: layout,
                            onSelect: { selected in
                                layout = selected
                                prefs.setPeriodHeaderLayout(selected)
                            },
                            // ← Android containerColor = surfaceContainerHighest
                            //   (SettingsCards 同款: 嵌在页面背景上降一级保持对比)
                            containerColor: colors.surfaceContainerHighest)
                        // ← Android Modifier.fillMaxWidth().height(40.dp)。
                        //   SegmentedSwitcher.swift(共享文件, 本任务禁改)内部固定 42pt 高,
                        //   外层压 40 布局槽: 胶囊视觉 42 上下各溢 1pt, 落在 6pt 行距内无碰撞
                        //   (SettingsCards 36pt 槽同法)。待共享接线项(height 参数)落地后改传参。
                        .frame(height: 40)
                    }

                    // ── 显示节号 + 三行式悬挂量 ──
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(L10n.t("appearance_header_show_x"), isOn: Binding(
                            get: { showX },
                            set: { newValue in
                                showX = newValue
                                prefs.setPeriodHeaderShowX(newValue)
                            }))
                        if layout == "three_line" {
                            // ← Android String.format("%+.1f", hangingUnits)
                            Text(L10n.format("appearance_header_hanging",
                                             String(format: "%+.1f", hangingUnits)))
                                .font(.system(size: 14))   // ← bodyMedium
                                .foregroundColor(colors.onSurfaceVariant)
                            Slider(
                                value: Binding(
                                    get: { Double(hangingUnits) },
                                    set: { v in
                                        hangingUnits = Float((v * 10).rounded() / 10)
                                    }),
                                in: -1...1) { _ in
                                    prefs.setPeriodHeaderHanging(hangingUnits)
                                }
                        }
                    }
                }
                .padding(16)
            }
        }
        .background(colors.background)
        .navigationBarHidden(true)
    }
}

// MARK: - 预览网格(样式选择)

/// 五种样式的实时预览 — 每张卡 = 选中样式渲染一个 previewSlot(node 12, 08:00-08:45)。
/// 视觉对齐 Compose HeaderStylePreviews: 卡片宽 = 逐样式实测(threeLineWidthDp/
/// legacyLineWidthDp, scale=1)+ 46pt 防挤压下限, 高 52pt — "谁的内容更长谁的卡片
/// 变宽, 禁硬钉宽"; 三行式五卡共享同一 previewFont(字号统一);
/// 选中态 primaryContainer, 未选中 surfaceContainer, 圆角 medium。
private struct HeaderStylePreviews: View {
    @Environment(\.localWakeUpColors) private var colors
    let layout: String
    let selectedStyle: String
    let hangingUnits: Float
    let showX: Bool
    let onStyleSelected: (String) -> Void

    /// 预览槽位(← Android previewSlot: label "12", 08:00-08:45, nodeStart=nodeEnd=12)
    private static let previewSlot = TimeSlot(
        label: "12", startHour: 8, startMinute: 0, endHour: 8, endMinute: 45,
        nodeStart: 12)

    /// ← Android styles: 五种样式的 FlowRow 标签
    private static let styles: [(String, String)] = [
        ("arabic", "1  2  3"),
        ("chinese", "一  二  三"),
        ("financial", "壹  贰  叁"),
        ("circled", "①  ②  ③"),
        ("roman", "Ⅰ  Ⅱ  Ⅲ"),
    ]

    /// ← Android styleWidths: 每种样式按自己的文字包络实测卡宽 (dp→pt 1:1)。
    /// legacy 布局同样按实测 (标签/时间串取大) — 与三行式同一精神, 禁硬钉 68dp。
    private var styleWidths: [CGFloat] {
        let slots = [Self.previewSlot]
        return Self.styles.map { value, _ in
            layout == "three_line"
                ? threeLineWidthDp(slots: slots, headerStyle: value, scale: 1,
                                   hangingUnits: CGFloat(hangingUnits), showX: showX)
                : legacyLineWidthDp(slots: slots, headerStyle: value, scale: 1,
                                    showX: showX)
        }
    }

    /// ← Android contentWidths: 防挤压下限 46dp (= 网格 d(46f) 的 scale=1 基准)
    private var contentWidths: [CGFloat] {
        styleWidths.map { max($0, 46) }
    }

    /// ← Android previewFont: 字号统一 = 同一算法(forPreview)、同一输入
    /// (最长样式实测宽 + 52pt 卡高) — 圈圈/罗马/汉字五卡全同字号;
    /// legacy 无自适应字号链 → nil (各卡走基准字号)。
    private var previewFont: PeriodHeaderAdaptiveFont? {
        guard layout == "three_line" else { return nil }
        return PeriodHeaderAdaptiveFont.forPreview(
            cardWidthSp: styleWidths.max() ?? 46,
            cardHeightSp: 52)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.t("appearance_header_preview"))
                .font(.system(size: 14, weight: .semibold))   // ← titleSmall
                .foregroundColor(colors.onSurface)

            // ← FlowRow 等价: 换行流式布局
            FlowLayout(spacing: 8) {
                ForEach(Array(Self.styles.enumerated()), id: \.element.0) { idx, pair in
                    styleCard(value: pair.0, label: pair.1,
                              contentWidth: contentWidths[idx],
                              sharedFont: previewFont)
                }
            }
        }
    }

    private func styleCard(value: String, label: String,
                           contentWidth: CGFloat,
                           sharedFont: PeriodHeaderAdaptiveFont?) -> some View {
        let isSelected = value == selectedStyle
        return Button {
            onStyleSelected(value)
        } label: {
            VStack(spacing: 5) {
                // 预览卡: 宽 = contentWidths[styleIndex] (实测, ≥46pt 下限), 高 52pt。
                // 3pt 内边距在卡面之内 (← Android Surface(w×52){ Box(padding 3){ cell } }):
                // cell .padding(pad) 先包内容, 再 .frame(w×52) 定卡面 — 内容盒 =
                // (w - 2×pad) × 46pt, 与 SingleTimeHeadCell 的 3dp 内边距逐层相等
                // (2026-09-28 令: padding 只由卡片层负责, 两条链必须相等)。
                // 旧写法 frame→background→padding 把 pad 挤出卡面 (内容 52 满高 +
                // 82×58 布局足迹), 现已按 Android 层序归位。
                PeriodHeaderCellContent(
                    displayStart: Self.previewSlot.displayStart,
                    displayEnd: Self.previewSlot.displayEnd,
                    nodeStart: Self.previewSlot.nodeStart,
                    nodeEnd: Self.previewSlot.nodeEnd,
                    isPlaceholder: Self.previewSlot.isPlaceholder,
                    layout: layout,
                    style: value,
                    scale: 1,
                    hangingUnitsOverride: CGFloat(hangingUnits),
                    showXOverride: showX,
                    sharedFont: sharedFont)
                .padding(periodHeaderCardPadDp)
                .frame(width: contentWidth, height: 52)
                .background(colors.surfaceContainerLow)
                .cornerRadius(SleepyShapes.small)

                Text(label)
                    .font(.system(size: 11))   // ← labelSmall
                    .foregroundColor(isSelected ? colors.onPrimaryContainer : colors.onSurfaceVariant)
            }
            .padding(6)
            // ← Android Surface widthIn(min = 76.dp): 外卡最小宽 76pt, 实际随内容变宽
            .frame(minWidth: 76)
            .background(isSelected ? colors.primaryContainer : colors.surfaceContainer)
            .cornerRadius(SleepyShapes.medium)
        }
        .buttonStyle(SleepyButtonStyle())
    }
}

// MARK: - 简易流式布局(← Compose FlowRow)

/// 水平流式排列, 放不下自动换行 — Compose FlowRow 的 SwiftUI 等价(轻实现)。
private struct FlowLayout<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        // iOS 15 兼容: 无 Layout 协议 → 用 LazyVGrid adaptive 列近似流式换行
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: spacing)],
                  alignment: .leading, spacing: spacing) {
            content()
        }
    }
}
