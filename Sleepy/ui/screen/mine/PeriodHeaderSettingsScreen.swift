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
    // v1.0.62 B4: 旧式表头「隐藏时间行」(← AppPrefs.isPeriodHeaderHideTime)
    @State private var hideTime: Bool = AppPrefs.shared.isPeriodHeaderHideTime()
    @State private var timeAlignment: String = AppPrefs.shared.getPeriodHeaderTimeAlignment()
    // 同一页面身份内仅捕获一次，切换布局/重复 onAppear 都保留进页基线。
    @State private var baselineHanging: Float? = nil

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
                        hideTime: hideTime,
                        centerTime: timeAlignment == "center",
                        onStyleSelected: { value in
                            style = value
                            prefs.setPeriodHeaderStyle(value)
                        })

                    // ── 布局切换(legacy / three_line) ──
                    SettingsFlatCard(title: L10n.t("appearance_header_layout"),
                                     options: [L10n.t("appearance_layout_legacy"), L10n.t("appearance_layout_three_line")],
                                     selectedIndex: Binding(get: { layout == "three_line" ? 1 : 0 }, set: {
                                         layout = $0 == 1 ? "three_line" : "legacy"
                                         prefs.setPeriodHeaderLayout(layout)
                                     }))

                    // ── 显示节号 + 三行式悬挂量 ──
                    VStack(alignment: .leading, spacing: SettingsLayout.controlGap) {
                        SettingToggleRow(label: L10n.t("appearance_header_show_x"), checked: showX) {
                            showX = $0
                            prefs.setPeriodHeaderShowX($0)
                        }
                        // v1.0.62 B4: 隐藏时间行仅适用旧式两行表头; 三行式以时间为主体, 不适用。
                        if layout == "legacy" {
                            SettingToggleRow(label: L10n.t("appearance_header_hide_time"),
                                             subtitle: L10n.t("appearance_header_hide_time_sub"), checked: hideTime) {
                                hideTime = $0
                                prefs.setPeriodHeaderHideTime($0)
                            }
                        }
                        if layout == "three_line" {
                            VStack(spacing: 4) {
                                Text("\(L10n.t("appearance_header_hanging"))  \(String(format: "%+.1f", hangingUnits))")
                                    .font(.system(size: 14))   // ← bodyMedium
                                    .foregroundColor(colors.onSurfaceVariant)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                NativeBaselineSlider(
                                    value: Double(hangingUnits),
                                    range: -1...1,
                                    baseline: baselineHanging.map { Double($0) },
                                    label: L10n.t("appearance_header_hanging"),
                                    valueText: String(format: "%+.1f", hangingUnits),
                                    onValueChange: { v in
                                        hangingUnits = Float((v * 10).rounded() / 10)
                                    },
                                    onFinished: {
                                        prefs.setPeriodHeaderHanging(hangingUnits)
                                    })
                                    .frame(height: 44)
                            }
                        }
                    }
                    .padding(SettingsLayout.cardInset)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(colors.surfaceContainer)
                    .cornerRadius(SleepyShapes.large)

                    if layout == "legacy", !hideTime {
                        SettingsFlatCard(title: L10n.t("appearance_header_time_alignment"),
                                         options: [L10n.t("appearance_header_alignment_dash"), L10n.t("appearance_header_alignment_center")],
                                         selectedIndex: Binding(get: { timeAlignment == "center" ? 1 : 0 }, set: {
                                             timeAlignment = $0 == 1 ? "center" : "dash"
                                             prefs.setPeriodHeaderTimeAlignment(timeAlignment)
                                         }))
                    }
                }
                .padding(16)
            }
        }
        .background(colors.background)
        .navigationBarHidden(true)
        .onAppear { captureBaselines() }
    }

    private func captureBaselines() {
        guard baselineHanging == nil else { return }
        baselineHanging = hangingUnits
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
    // v1.0.62 B4: 旧式表头「隐藏时间行」实时值(预览卡与列宽同步反映)
    let hideTime: Bool
    let centerTime: Bool
    let onStyleSelected: (String) -> Void

    /// 预览槽位(previewSlot: label "12", 08:00-08:45, nodeStart=nodeEnd=12)
    private static let previewSlot = TimeSlot(
        label: "12", startHour: 8, startMinute: 0, endHour: 8, endMinute: 45,
        nodeStart: 12)

    /// ← 原版本 styles: 五种样式的 FlowRow 标签
    private static let styles: [(String, String)] = [
        ("arabic", "1  2  3"),
        ("chinese", "一  二  三"),
        ("financial", "壹  贰  叁"),
        ("circled", "①  ②  ③"),
        ("roman", "Ⅰ  Ⅱ  Ⅲ"),
    ]

    /// ← 原版本 styleWidths: 每种样式按自己的文字包络实测卡宽 (dp→pt 1:1)。
    /// legacy 布局同样按实测 (标签/时间串取大) — 与三行式同一精神, 禁硬钉 68dp。
    private var styleWidths: [CGFloat] {
        let slots = [Self.previewSlot]
        return Self.styles.map { value, _ in
            layout == "three_line"
                ? threeLineWidthDp(slots: slots, headerStyle: value, scale: 1,
                                   hangingUnits: CGFloat(hangingUnits), showX: showX)
                : legacyTimeWidthDp(slots: slots, headerStyle: value, scale: 1,
                                    showX: showX, hideTime: hideTime, centerTime: centerTime)
        }
    }

    /// ← 原版本 contentWidths: 防挤压下限 46dp (= 网格 d(46f) 的 scale=1 基准)
    private var contentWidths: [CGFloat] {
        styleWidths.map { max($0, 46) }
    }

    /// ← 原版本 previewFont: 字号统一 = 同一算法(forPreview)、同一输入
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
                // 3pt 内边距在卡面之内 (Surface(w×52){ Box(padding 3){ cell } }):
                // cell .padding(pad) 先包内容, 再 .frame(w×52) 定卡面 — 内容盒 =
                // (w - 2×pad) × 46pt, 与 SingleTimeHeadCell 的 3dp 内边距逐层相等
                // (2026-09-28 令: padding 只由卡片层负责, 两条链必须相等)。
                // 旧写法 frame→background→padding 把 pad 挤出卡面 (内容 52 满高 +
                // 82×58 布局足迹), 现已按 原版本 层序归位。
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
                    hideTimeOverride: hideTime,
                    centerTimeOverride: centerTime,
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
            // ← 原版本 Surface widthIn(min = 76.dp): 外卡最小宽 76pt, 实际随内容变宽
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
