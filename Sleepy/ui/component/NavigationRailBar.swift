// NavigationRailBar.swift — 宽屏横屏左侧导航栏 ← 原版本 SleepyNavHost.kt
// issue#45 ③ (WindowWidthSizeClass != Compact 且横屏 → 官方 Material3
// NavigationRail + Row{rail, Master-Detail 双栏内容})
//
// ★ 2026-10-27 对齐 PR#114 master-detail 终态: rail 不再是 4 项平铺, 而是
//   3 固定槽 [Today, Manage, Mine] —— 当前右半 tab 所在槽渲染「跑道胶囊」
//   (CombinedRailItem: Schedule 图标 + 该 tab 图标上下排列, 中线
//   发丝分隔, 56dp 宽 full-rounded primaryContainer 强高亮, 无文字标签,
//   图标 22dp); 另两槽 = 普通图标+文字项(← PlainRailItem, 恒未选中态)。
//   Schedule 无独立槽 = 左半课表永久固定(双栏语义), 胶囊即「课表+X」合项。
//
// iOS 原生等价 = NavigationSplitView sidebar，但本工程导航是 AppRootViewModel
// 自绘 overlay 状态机(全量 UITests/深链/转场都挂在它上面)，切 NavigationSplitView
// 等于重写路由层 → 不可行。故与 原版本 选择官方 NavigationRail 的思路一致,
// iOS 侧用系统控件语感的自绘侧栏(本组件), 保持 root.currentTab 单点真值不变。
//
// 视觉规格(对齐 原 tablet rail):
//   - 宽 80pt(M3 默认 railWidth=80)
//   - 胶囊 = 56×(28+28+分隔) full-rounded primaryContainer, 图标 22pt,
//     发丝横线 0.5pt 左右缩进 10
//   - 普通项 = 图标(20) + 标签(12), 垂直堆叠, 项间距 8
//   - badge = 图标右上 7pt primary 圆点(v1.0.60 badge 语义;
//     Mine 在胶囊形态时点画在从 tab 图标右上 = tabShowUpdateDot 同位)
//   - 顶对齐(M3 默认 verticalArrangement 从顶部开始)

import SwiftUI

struct NavigationRailBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.localWakeUpColors) private var colors
    @Environment(\.sleepyUIStyle) private var style
    @Namespace private var selectionNamespace
    /// 3 个固定槽数据(today/manage/mine, 顺序即槽位顺序)。
    let rightTabs: [PillNavItemData]
    /// 当前右半 tab id(= 胶囊所在槽; ← 原版本 effectiveRightTab)。
    let selectedTab: AppRootViewModel.Tab
    /// Motion follows the actual route, including Schedule while Today is
    /// displayed as its derived right pane.
    let motionSelectedTab: AppRootViewModel.Tab
    /// Schedule SF Symbol(胶囊上半图标 ← 原版本 Tab.Schedule.icon)。
    let scheduleIcon: String
    /// Medium landscape windows use four ordinary tabs and one content pane.
    /// The combined Schedule + selected-tab item only applies while Schedule is pinned.
    var scheduleIsPinned: Bool = true

    /// M3 NavigationRail 默认宽度
    static let railWidth: CGFloat = 80

    var body: some View {
        VStack(spacing: 8) {
            if style == .liquidGlass {
                SleepyNativeGlassGroup(spacing: 8) {
                    VStack(spacing: 8) {
                        navigationItems
                    }
                    .frame(width: 64)
                    .sleepyNativeGlassSurface(cornerRadius: 32)
                }
            } else {
                navigationItems
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 16)
        .frame(width: Self.railWidth)
        .frame(maxHeight: .infinity)
        .background {
            if style != .liquidGlass { colors.background }
        }
        .animation(SleepyMotionPolicy(reduceMotion: reduceMotion).defaultSpatial, value: selectedTab)
        .androidNavigationIconBar(selectedIDs: [motionTabID])
    }

    private var motionTabID: String {
        switch motionSelectedTab {
        case .schedule: return "schedule"
        case .today: return "today"
        case .manage: return "manage"
        case .mine: return "mine"
        }
    }

    private var navigationItems: some View {
        ForEach(rightTabs) { item in
            if scheduleIsPinned && item.id == tabId(selectedTab) {
                CombinedRailItemView(item: item, scheduleIcon: scheduleIcon, colors: colors,
                                     selectionNamespace: selectionNamespace)
                    .transition(SleepyMotionPolicy(reduceMotion: reduceMotion).content)
            } else {
                RailItemView(item: item, colors: colors, selectionNamespace: selectionNamespace)
                    .transition(SleepyMotionPolicy(reduceMotion: reduceMotion).content)
            }
        }
    }

    /// Tab → rail item id 映射(胶囊/普通项判定共用)。
    private func tabId(_ tab: AppRootViewModel.Tab) -> String {
        switch tab {
        case .schedule: return "today"   // 派生右半永不为 schedule(AppRoot
                                        //   tabletRightTab), 兜底按 Today 槽
        case .today: return "today"
        case .manage: return "manage"
        case .mine: return "mine"
        }
    }
}

// MARK: - 跑道胶囊(CombinedRailItem)

/// Schedule + 当前 tab 图标上下组合, 无 label, 56pt 宽 full-rounded 胶囊;
/// 选中整组强高亮(primaryContainer 底 + onPrimaryContainer 图标),
/// 未选中透明底(语义: 胶囊只在当前槽出现, 恒 selected=true)。
private struct CombinedRailItemView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.sleepyUIStyle) private var style
    let item: PillNavItemData
    let scheduleIcon: String
    let colors: WakeUpColorScheme
    let selectionNamespace: Namespace.ID

    @ViewBuilder
    var body: some View {
        if style == .liquidGlass {
            Button(action: item.onClick) {
                VStack(spacing: 2) {
                    AndroidMaterialIcon(name: .calendarMonth, size: 22)
                        .frame(width: 28, height: 28)
                    Divider().frame(width: 28)
                    NavigationIcon(id: item.id, selected: item.selected, size: 22,
                                   activationID: item.id)
                        .frame(width: 28, height: 28)
                }
                .foregroundColor(item.selected ? colors.onPrimaryContainer : colors.onSurfaceVariant)
                .frame(width: 56, height: 68)
                .sleepyNativeGlassSelection(item.selected, cornerRadius: 28,
                                           tint: colors.primaryContainer, namespace: selectionNamespace)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .androidNavigationIconPress(id: item.id)
            .tint(item.selected ? colors.onPrimaryContainer : colors.onSurfaceVariant)
            .frame(width: 56, height: 68)
            .accessibilityIdentifier("rail_schedule_\(item.id)")
            .accessibilityLabel("\(L10n.t("tab_schedule")), \(item.label)")
            .accessibilityAddTraits(item.selected ? .isSelected : [])
        } else {
            classicButton
        }
    }

    private var classicButton: some View {
        Button(action: item.onClick) {
            VStack(spacing: 0) {
                iconSlot(scheduleIcon, desc: L10n.t("tab_schedule"))
                // 中线发丝分隔(HorizontalDivider 0.5dp,
                // onSurfaceVariant × Alpha.hairline(0.3), 左右 padding 10)
                Rectangle()
                    .fill(colors.onSurfaceVariant.opacity(SleepyTheme.Alpha.hairline))
                    .frame(height: 0.5)
                    .padding(.horizontal, 10)
                iconSlot(item.icon, desc: item.label)
            }
            .frame(width: 56)
            .padding(.vertical, 4)
            .background(
                // full-rounded 胶囊(RoundedCornerShape(percent = 50))
                RoundedRectangle(cornerRadius: 28)
                    .fill(item.selected ? colors.primaryContainer : Color.clear)
                    .animation(SleepyMotionPolicy(reduceMotion: reduceMotion).fastEffects, value: item.selected)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(SleepyMotionButtonStyle())
        .androidNavigationIconPress(id: item.id)
        // 胶囊项标识: rail_schedule_<从tab>(与 pill_*/rail_* 同命名空间;
        // ← 原版本 tab_schedule_today 字符串已删, 组合语义由 id 前缀承载)
        .accessibilityIdentifier("rail_schedule_\(item.id)")
        .accessibilityLabel("\(L10n.t("tab_schedule")), \(item.label)")
        .accessibilityAddTraits(item.selected ? .isSelected : [])
    }

    private func iconSlot(_ name: String, desc: String) -> some View {
        // 28pt 图标盒(Box(size=28) 居中 22dp 图标; v1.0.60 showUpdateDot 随更新切片移除)
        Group {
            if name == scheduleIcon {
                AndroidMaterialIcon(name: .calendarMonth, size: 22)
            } else {
                NavigationIcon(id: item.id, selected: item.selected, size: 22,
                               activationID: item.id)
            }
        }
            .foregroundColor(item.selected ? colors.onPrimaryContainer
                                           : colors.onSurfaceVariant)
            .animation(SleepyMotionPolicy(reduceMotion: reduceMotion).fastEffects, value: item.selected)
            .frame(width: 28, height: 28)
            .accessibilityLabel(desc)
    }
}

// MARK: - 普通 rail 项(PlainRailItem: NavigationRailItem icon+label)

private struct RailItemView: View {
    @Environment(\.sleepyUIStyle) private var style
    let item: PillNavItemData
    let colors: WakeUpColorScheme
    let selectionNamespace: Namespace.ID

    @ViewBuilder
    var body: some View {
        if style == .liquidGlass {
            Button(action: item.onClick) {
                VStack(spacing: 4) {
                    NavigationIcon(id: item.id, selected: item.selected, size: 20)
                    Text(item.label)
                        .font(.system(size: 12, weight: item.selected ? .semibold : .regular))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .foregroundColor(item.selected ? colors.onPrimaryContainer : colors.onSurfaceVariant)
                .frame(width: 56, height: 54)
                .sleepyNativeGlassSelection(item.selected, cornerRadius: 27,
                                           tint: colors.primaryContainer, namespace: selectionNamespace)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .androidNavigationIconPress(id: item.id)
            .tint(item.selected ? colors.onPrimaryContainer : colors.onSurfaceVariant)
            .frame(width: 56, height: 54)
            .accessibilityIdentifier("rail_\(item.id)")
            .accessibilityLabel(item.label)
            .accessibilityAddTraits(item.selected ? .isSelected : [])
        } else {
            classicButton
        }
    }

    private var classicButton: some View {
        Button(action: item.onClick) {
            VStack(spacing: 4) {
                ZStack {
                    // 选中胶囊(← M3 indicator; master-detail 下普通项恒未选中,
                    // 保留形态与 pill/旧 rail 一致)
                    RoundedRectangle(cornerRadius: 16)
                        .fill(item.selected ? colors.primaryContainer : Color.clear)
                        .frame(width: 56, height: 32)
                    ZStack(alignment: .topTrailing) {
                        NavigationIcon(id: item.id, selected: item.selected, size: 20)
                            .foregroundColor(item.selected ? colors.onPrimaryContainer
                                                           : colors.onSurfaceVariant)
                    }
                }
                Text(item.label)
                    .font(.system(size: 12, weight: item.selected ? .semibold : .regular))
                    .foregroundColor(item.selected ? colors.onSurface : colors.onSurfaceVariant)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.horizontal, 2)
            }
            .frame(height: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(SleepyMotionButtonStyle())
        .androidNavigationIconPress(id: item.id)
        // 与 pill_* 同命名空间: rail_<id>; UITests 宽屏分支按此定位
        .accessibilityIdentifier("rail_\(item.id)")
    }
}
