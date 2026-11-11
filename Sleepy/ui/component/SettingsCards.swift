// SettingsCards.swift — ← ui/component/SettingsCards.kt
// 设置页公共卡片 — 自 AppearanceScreen 抽出(外观/通用两页共用):
// SectionHeader 分组标题 / SettingsCard 折叠卡 / DisplayModeOption 单选项 / SettingToggleRow 开关行。

import SwiftUI
import UIKit  // tabWidth 实测需 UIFont/NSString sizing(同目录 PillNavigationBar 惯例)

// ← Android v1.0.64 SettingsLayout：只作用于设置页的尺寸与文字层级。
enum SettingsLayout {
    static let pageInset: CGFloat = 16
    static let cardInset: CGFloat = 16
    static let cardGap: CGFloat = 12
    static let sectionGap: CGFloat = 24
    static let headerGap: CGFloat = 8
    static let descriptionGap: CGFloat = 4
    static let controlGap: CGFloat = 12
    static let minRowHeight: CGFloat = 48
    static let headingStyle = Font.system(size: 14, weight: .semibold)
    static let itemStyle = Font.system(size: 14)
    static let descriptionStyle = Font.system(size: 12)
}

struct SettingsSection<Content: View>: View {
    let title: String
    var first = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsLayout.headerGap) {
            SectionHeader(title: title)
            content()
        }
        .padding(.top, first ? 0 : SettingsLayout.sectionGap - SettingsLayout.cardGap)
    }
}

// ← SectionHeader
struct SectionHeader: View {
    @Environment(\.localWakeUpColors) private var colors
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsLayout.descriptionGap) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(colors.onBackground)
            if let subtitle = subtitle, !subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(colors.onSurfaceVariant)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// ← 原版本 AnimatedVisibility/expandVertically 默认 spec = spring(NoBouncy, StiffnessMediumLow≈400)
//   → iOS 等价 dampingFraction 1.0(无回弹), response = 2π/√400 ≈ 0.31。
//   thumb 类弹簧另见 SleepyMotion.sleepyThumbSpring(High 硬度 0.18, 不同用途不同档)。
private let sleepySettingsExpand = Animation.spring(response: 0.31, dampingFraction: 1.0)

// ← SettingsCard: 折叠卡(箭头随展开旋转, 内容高度+淡入同拍)
//
// 展开动画 ← 原版本 AnimatedVisibility(expandVertically()+fadeIn() /
// shrinkVertically()+fadeOut()): Compose 侧可见性切换由 AnimatedVisibility 自带
// 动画, 不依赖调用方是否包动画; iOS 的 transition 只在「动画事务内的状态变更」
// 生效, 而调用方(GeneralSettingsScreen.toggleSection)是裸改状态 —— 因此这里用
// .animation(sleepySettingsExpand, value: expanded): 无论状态来自卡片点击还是
// 外部切 set, 都与 原版本 一样自动展开/收起。箭头 .rotationEffect(对应
// animateFloatAsState)与内容 .transition 由同一 value 驱动 → 同拍。
struct SettingsCard<Content: View>: View {
    @Environment(\.localWakeUpColors) private var colors
    let title: String
    let expanded: Bool
    let onToggle: () -> Void
    @ViewBuilder let content: () -> Content

    init(title: String, expanded: Bool, onToggle: @escaping () -> Void,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.expanded = expanded
        self.onToggle = onToggle
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: SettingsLayout.controlGap) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(colors.onSurface)
                Spacer()
                // 箭头随展开旋转, 与内容动画同拍
                // ← 原版本 animateFloatAsState(if (expanded) 180f else 0f)
                AndroidSettingsIcon(name: .expandMore, size: 20)
                    .foregroundColor(colors.onSurfaceVariant)
                    .rotationEffect(.degrees(expanded ? 180 : 0))
            }
            .padding(.vertical, 12)
            .frame(minHeight: SettingsLayout.minRowHeight)
            // 展开动画: 高度+淡入同拍, 替代此前无事务包裹的瞬间弹出
            if expanded {
                // ← 原版本 AnimatedVisibility 内 Column{Spacer(4); content()}: 标题→内容总间距 8, 内容子项间距 0
                VStack(alignment: .leading, spacing: 0) {
                    content()
                }
                .padding(.top, SettingsLayout.headerGap)
                .padding(.bottom, SettingsLayout.cardInset)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, SettingsLayout.cardInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.surfaceContainer)
        .cornerRadius(SleepyShapes.large)
        // 高度展开 + 箭头旋转 + 内容淡入统一由 expanded 变化驱动(= 原实现
        // AnimatedVisibility/animateFloatAsState 的「谁切都动画」), 🚫依赖调用方包 withAnimation
        .animation(sleepySettingsExpand, value: expanded)
        // ← 原版本 .noRippleClickable(onToggle) 加在 background 之后、padding 之前:
        //   整卡(含 16pt 内边距与展开内容中非交互区域)都是切换命中区;
        //   子级 Button/Toggle/Slider 优先消费各自点击, 不受父级 tap 影响。
        .contentShape(Rectangle())
        .onTapGesture { onToggle() }
        .accessibilityIdentifier("card_\(title)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default) { onToggle() }
    }
}

// ← SettingsFlatCard: 平铺卡(不折叠) — 标题行右侧内嵌课表页同款 SegmentedSwitcher
//   Classic 保留 Material 轨道，Liquid Glass 由系统 segmented Picker 呈现。
//   ← 原版本 SettingsCards.kt:109-161 全参: subtitle(标题下 bodySmall 行)、
//   options 为空 = 单开关卡(由 content 自行露出控件)、content ColumnScope 尾槽。
struct SettingsFlatCard<Content: View>: View {
    @Environment(\.localWakeUpColors) private var colors
    let title: String
    var subtitle: String? = nil
    let options: [String]
    @Binding var selectedIndex: Int
    /// ← 原 onSelect 默认 {}; nil = 只回写 selectedIndex。
    var onSelect: ((Int) -> Void)?
    let content: () -> Content
    @State private var measuredWidth: CGFloat = 0

    init(title: String,
         subtitle: String? = nil,
         options: [String] = [],
         // ← 原版本 selectedKey: Int = 0 — 默认值对齐, 单开关卡无需显式传绑定
         selectedIndex: Binding<Int> = .constant(0),
         onSelect: ((Int) -> Void)? = nil,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.options = options
        self._selectedIndex = selectedIndex
        self.onSelect = onSelect
        self.content = content
    }

    var body: some View {
        let titleWidth = ceil((title as NSString).size(withAttributes: [
            .font: UIFont.systemFont(ofSize: 14, weight: .semibold)
        ]).width)
        let availableWidth = max(0, measuredWidth - SettingsLayout.cardInset * 2)
        let inline = !options.isEmpty && Self.tabWidth(options: options) + titleWidth + SettingsLayout.controlGap <= availableWidth
        VStack(alignment: .leading, spacing: SettingsLayout.headerGap) {
            if inline {
                HStack(spacing: SettingsLayout.controlGap) {
                    heading
                    if !options.isEmpty {
                        segmentedOptions.frame(width: Self.tabWidth(options: options))
                    }
                }
                .frame(minHeight: SettingsLayout.minRowHeight)
            } else {
                VStack(alignment: .leading, spacing: SettingsLayout.headerGap) {
                    heading
                    if !options.isEmpty {
                        if Self.tabWidth(options: options) <= availableWidth {
                            segmentedOptions
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(options.enumerated()), id: \.offset) { index, label in
                                    DisplayModeOption(label: label, subtitle: "", selected: selectedIndex == index) {
                                        selectedIndex = index
                                        onSelect?(index)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            // ← 原 if (subtitle != null) bodySmall 行(CalendarImportDialog 用法)
            if let subtitle = subtitle, !subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(colors.onSurfaceVariant)
            }
            content()
        }
        .padding(.horizontal, SettingsLayout.cardInset)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.surfaceContainer)
        .cornerRadius(SleepyShapes.large)
        .accessibilityElement(children: .contain)
        .background(GeometryReader { geometry in
            Color.clear
                .onAppear { measuredWidth = geometry.size.width }
                .onChange(of: geometry.size.width) { measuredWidth = $0 }
        })
    }

    private var heading: some View {
        Text(title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(colors.onSurface)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var segmentedOptions: some View {
        SegmentedSwitcher(
            options: options.enumerated().map { ($0.offset, $0.element) },
            selected: selectedIndex,
            onSelect: { idx in
                selectedIndex = idx
                onSelect?(idx)
            },
            containerColor: colors.surfaceContainerHighest,
            height: 36,
            accessibilityTitle: title)
    }

    /// Material 标签尺寸决定单行卡片能否容纳选项；原生分段沿用这份可用宽度。
    /// CJK 按 14pt semibold 和 tracking 0.1 同步测量，不依赖异步宽度偏好。
    static func tabWidth(options: [String]) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14, weight: .semibold),
            .kern: 0.1,
        ]
        let maxLabel = options
            .map { ceil(($0 as NSString).size(withAttributes: attrs).width) }
            .max() ?? 0
        return (maxLabel + 32) * CGFloat(options.count) + 8
    }
}

extension SettingsFlatCard where Content == EmptyView {
    /// 无 content 重载 — ← 原 content 默认 {}; 既有调用方
    /// (GeneralSettingsScreen/HolidaySettingsScreen 各平铺卡)签名不变即编译。
    init(title: String,
         subtitle: String? = nil,
         options: [String] = [],
         selectedIndex: Binding<Int> = .constant(0),
         onSelect: ((Int) -> Void)? = nil) {
        self.init(title: title,
                  subtitle: subtitle,
                  options: options,
                  selectedIndex: selectedIndex,
                  onSelect: onSelect) { EmptyView() }
    }
}

// ← DisplayModeOption
struct DisplayModeOption: View {
    @Environment(\.localWakeUpColors) private var colors
    let label: String
    let subtitle: String
    let selected: Bool
    let onClick: () -> Void

    /// G5 锚点(自动取 label)
    var aid: String { "opt_\(label)" }

    var body: some View {
        Button(action: onClick) {
            HStack(spacing: SettingsLayout.controlGap) {
                VStack(alignment: .leading, spacing: SettingsLayout.descriptionGap) {
                    Text(label)
                        .font(SettingsLayout.itemStyle)
                        .foregroundColor(selected ? colors.primary : colors.onSurface)
                    // ← 原 if (subtitle.isNotEmpty())
                    if !subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundColor(colors.onSurfaceVariant)
                    }
                }
                Spacer()
                if selected {
                    AndroidMaterialIcon(name: .check, size: 20)
                        .foregroundColor(colors.primary)
                }
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: SettingsLayout.minRowHeight, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(SleepyButtonStyle())
        .accessibilityIdentifier(aid)
    }
}

// ← SettingToggleRow
struct SettingToggleRow: View {
    @Environment(\.localWakeUpColors) private var colors
    let label: String
    /// ← 原 `subtitle: String? = null` — 可空契约, nil = 无副标题行。
    ///   既有调用方传 "" 哨兵仍编译(String→String? 自动提升), 且按无副标题处理。
    var subtitle: String? = nil
    let checked: Bool
    let onCheckedChange: (Bool) -> Void

    var body: some View {
        HStack(spacing: SettingsLayout.controlGap) {
            VStack(alignment: .leading, spacing: SettingsLayout.descriptionGap) {
                Text(label)
                    .font(SettingsLayout.itemStyle)
                    .foregroundColor(colors.onSurface)
                // ← 原 if (subtitle != null); "" 哨兵同样视为无
                if let subtitle = subtitle, !subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(colors.onSurfaceVariant)
                }
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { checked },
                set: { onCheckedChange($0) }
            ))
            .toggleStyle(SleepyToggleStyle())
            .tint(colors.primary)   // checkedTrackColor=primary
            .labelsHidden()
        }
        .padding(.vertical, 4)
        .frame(minHeight: SettingsLayout.minRowHeight)
    }
}

// InfoCard — 通用信息卡(About/License 等用)，内边距跟随设置页公共 token。
// ← AboutScreen.kt InfoCard; v7.10.18 提到 SettingsCards.swift 共享, LicenseScreen 也用。
struct InfoCard<Content: View>: View {
    @Environment(\.localWakeUpColors) private var colors
    var inset: CGFloat = SettingsLayout.cardInset
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(inset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.surfaceContainer)
        .cornerRadius(SleepyShapes.large)
    }
}
