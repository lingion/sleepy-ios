// SettingsCards.swift — ← ui/component/SettingsCards.kt
// 设置页公共卡片 — 自 AppearanceScreen 抽出(外观/通用两页共用):
// SectionHeader 分组标题 / SettingsCard 折叠卡 / DisplayModeOption 单选项 / SettingToggleRow 开关行。

import SwiftUI
import UIKit  // tabWidth 实测需 UIFont/NSString sizing(同目录 PillNavigationBar 惯例)

// ← SectionHeader
struct SectionHeader: View {
    @Environment(\.localWakeUpColors) private var colors
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(colors.onBackground)
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(colors.onSurfaceVariant)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }
}

// ← Android AnimatedVisibility/expandVertically 默认 spec = spring(NoBouncy, StiffnessMediumLow≈400)
//   → iOS 等价 dampingFraction 1.0(无回弹), response = 2π/√400 ≈ 0.31。
//   thumb 类弹簧另见 SleepyMotion.sleepyThumbSpring(High 硬度 0.18, 不同用途不同档)。
private let sleepySettingsExpand = Animation.spring(response: 0.31, dampingFraction: 1.0)

// ← SettingsCard: 折叠卡(箭头随展开旋转, 内容高度+淡入同拍)
//
// 展开动画 ← Android AnimatedVisibility(expandVertically()+fadeIn() /
// shrinkVertically()+fadeOut()): Compose 侧可见性切换由 AnimatedVisibility 自带
// 动画, 不依赖调用方是否包动画; iOS 的 transition 只在「动画事务内的状态变更」
// 生效, 而调用方(GeneralSettingsScreen.toggleSection)是裸改状态 —— 因此这里用
// .animation(sleepySettingsExpand, value: expanded): 无论状态来自卡片点击还是
// 外部切 set, 都与 Android 一样自动展开/收起。箭头 .rotationEffect(对应
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
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(colors.onSurface)
                Spacer()
                // 箭头随展开旋转, 与内容动画同拍
                // ← Android animateFloatAsState(if (expanded) 180f else 0f)
                Image(systemName: "chevron.down")
                    .font(.system(size: 20))
                    .foregroundColor(colors.onSurfaceVariant)
                    .rotationEffect(.degrees(expanded ? 180 : 0))
            }
            // 展开动画: 高度+淡入同拍, 替代此前无事务包裹的瞬间弹出
            if expanded {
                // ← Android AnimatedVisibility 内 Column{Spacer(4); content()}: 标题→内容总间距 8, 内容子项间距 0
                VStack(alignment: .leading, spacing: 0) {
                    content()
                }
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.surfaceContainer)
        .cornerRadius(SleepyShapes.large)
        // 高度展开 + 箭头旋转 + 内容淡入统一由 expanded 变化驱动(= Android
        // AnimatedVisibility/animateFloatAsState 的「谁切都动画」), 🚫依赖调用方包 withAnimation
        .animation(sleepySettingsExpand, value: expanded)
        // ← Android .noRippleClickable(onToggle) 加在 background 之后、padding 之前:
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
//   (用户 2026-09-03 指令: 整块圆角矩形 + 色块在元素上滑动, 🚫系统 Picker)。
//   ← Android SettingsCards.kt:109-161 全参: subtitle(标题下 bodySmall 行)、
//   options 为空 = 单开关卡(由 content 自行露出控件)、content ColumnScope 尾槽。
struct SettingsFlatCard<Content: View>: View {
    @Environment(\.localWakeUpColors) private var colors
    let title: String
    var subtitle: String? = nil
    let options: [String]
    @Binding var selectedIndex: Int
    /// ← Android onSelect 默认 {}; nil = 只回写 selectedIndex。
    var onSelect: ((Int) -> Void)?
    let content: () -> Content

    init(title: String,
         subtitle: String? = nil,
         options: [String] = [],
         // ← Android selectedKey: Int = 0 — 默认值对齐, 单开关卡无需显式传绑定
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
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                // ← Android 标题 weight(1f) 吃满剩余宽 → tab 永远贴本行最右
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(colors.onSurface)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // ← Android if (options.isNotEmpty()): options 为空 = 单开关卡, tab 不渲染
                if !options.isEmpty {
                    SegmentedSwitcher(
                        options: options.enumerated().map { ($0.offset, $0.element) },
                        selected: selectedIndex,
                        onSelect: { idx in
                            selectedIndex = idx
                            onSelect?(idx)
                        },
                        // ← Android containerColor = colors.surfaceContainerHighest:
                        //   嵌进 surfaceContainer 卡片时同色隐形, 降一级保持对比
                        containerColor: colors.surfaceContainerHighest
                    )
                    // ← Android Modifier.width(tabWidth).height(36.dp)。
                    //   SegmentedSwitcher.swift 目前内部固定 42pt 高(共享文件, 本任务禁改),
                    //   外层压 36 布局槽: 胶囊视觉 42 高上下各溢 3pt, 落进卡片 14pt
                    //   内边距/4pt 行距, 无碰撞。待共享接线项落地后改为组件 height 参数。
                    .frame(width: Self.tabWidth(options: options), height: 36)
                    .accessibilityLabel(Text(title))
                }
            }
            // ← Android if (subtitle != null) bodySmall 行(CalendarImportDialog 用法)
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(colors.onSurfaceVariant)
            }
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.surfaceContainer)
        .cornerRadius(SleepyShapes.large)
    }

    /// ← Android SettingsCards.kt:136-145: tabWidth = (maxLabel宽 + 16dp×2) × n + 4dp×2
    ///   (dp→pt 1:1 本项目惯例)。🚫 IntrinsicSize/系统 Picker — CJK 必须实测,
    ///   测量字号与 SegmentedSwitcher 标签一致: labelLarge SemiBold = 14pt semibold
    ///   + tracking 0.1。同步测量(非 PreferenceKey 异步测量), 与 SegmentedSwitcher
    ///   「确定性几何」约定一致。
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
    /// 无 content 重载 — ← Android content 默认 {}; 既有调用方
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
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 16))
                        .foregroundColor(selected ? colors.primary : colors.onSurface)
                    // ← Android if (subtitle.isNotEmpty())
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundColor(colors.onSurfaceVariant)
                    }
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 20))
                        .foregroundColor(colors.primary)
                }
            }
        }
        .buttonStyle(SleepyButtonStyle())
        .accessibilityIdentifier(aid)
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
    }
}

// ← SettingToggleRow
struct SettingToggleRow: View {
    @Environment(\.localWakeUpColors) private var colors
    let label: String
    /// ← Android `subtitle: String? = null` — 可空契约, nil = 无副标题行。
    ///   既有调用方传 "" 哨兵仍编译(String→String? 自动提升), 且按无副标题处理。
    var subtitle: String? = nil
    let checked: Bool
    let onCheckedChange: (Bool) -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 16))
                    .foregroundColor(colors.onSurface)
                // ← Android if (subtitle != null); "" 哨兵同样视为无
                if let subtitle = subtitle, !subtitle.isEmpty {
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
            .toggleStyle(.switch)
            .tint(colors.primary)   // checkedTrackColor=primary
            .labelsHidden()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
    }
}

// InfoCard — 通用信息卡(About/License 等用): 单色块 + 内边距 20, 由 content 提供正文。
// ← AboutScreen.kt InfoCard; v7.10.18 提到 SettingsCards.swift 共享, LicenseScreen 也用。
struct InfoCard<Content: View>: View {
    @Environment(\.localWakeUpColors) private var colors
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.surfaceContainer)
        .cornerRadius(SleepyShapes.large)
    }
}
