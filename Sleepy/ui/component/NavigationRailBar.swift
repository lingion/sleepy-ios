// NavigationRailBar.swift — 宽屏横屏左侧导航栏 ← Android 版本 SleepyNavHost.kt
// issue#45 ③ (WindowWidthSizeClass != Compact 且横屏 → 官方 Material3
// NavigationRail + Row{rail, Master-Detail 双栏内容})
//
// ★ 2026-10-27 对齐 PR#114 master-detail 终态: rail 不再是 4 项平铺, 而是
//   3 固定槽 [Today, Manage, Mine] —— 当前右半 tab 所在槽渲染「跑道胶囊」
//   (← Android CombinedRailItem: Schedule 图标 + 该 tab 图标上下排列, 中线
//   发丝分隔, 56dp 宽 full-rounded primaryContainer 强高亮, 无文字标签,
//   图标 22dp); 另两槽 = 普通图标+文字项(← PlainRailItem, 恒未选中态)。
//   Schedule 无独立槽 = 左半课表永久固定(双栏语义), 胶囊即「课表+X」合项。
//
// iOS 原生等价 = NavigationSplitView sidebar，但本工程导航是 AppRootViewModel
// 自绘 overlay 状态机(全量 UITests/深链/转场都挂在它上面)，切 NavigationSplitView
// 等于重写路由层 → 不可行。故与 Android 选择官方 NavigationRail 的思路一致,
// iOS 侧用系统控件语感的自绘侧栏(本组件), 保持 root.currentTab 单点真值不变。
//
// 视觉规格(对齐 Android tablet rail):
//   - 宽 80pt(M3 默认 railWidth=80)
//   - 胶囊 = 56×(28+28+分隔) full-rounded primaryContainer, 图标 22pt,
//     发丝横线 0.5pt 左右缩进 10
//   - 普通项 = 图标(20) + 标签(12), 垂直堆叠, 项间距 8
//   - badge = 图标右上 7pt primary 圆点(← Android v1.0.60 badge 语义;
//     Mine 在胶囊形态时点画在从 tab 图标右上 = tabShowUpdateDot 同位)
//   - 顶对齐(M3 默认 verticalArrangement 从顶部开始)

import SwiftUI

struct NavigationRailBar: View {
    @Environment(\.localWakeUpColors) private var colors
    /// 3 个固定槽数据(today/manage/mine, 顺序即槽位顺序)。
    let rightTabs: [PillNavItemData]
    /// 当前右半 tab id(= 胶囊所在槽; ← Android effectiveRightTab)。
    let selectedTab: AppRootViewModel.Tab
    /// Schedule SF Symbol(胶囊上半图标 ← Android Tab.Schedule.icon)。
    let scheduleIcon: String

    /// M3 NavigationRail 默认宽度
    static let railWidth: CGFloat = 80

    var body: some View {
        VStack(spacing: 8) {
            ForEach(rightTabs) { item in
                if item.id == tabId(selectedTab) {
                    // ← Android when(effectiveRightTab) 分支: 当前槽 = 跑道胶囊
                    CombinedRailItemView(item: item,
                                         scheduleIcon: scheduleIcon,
                                         colors: colors)
                } else {
                    // 另两槽 = 普通项(恒未选中态, ← Android PlainRailItem
                    // selected=false; Mine 普通项时 badge 由 item.badge 携带)
                    RailItemView(item: item, colors: colors)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 16)
        .frame(width: Self.railWidth)
        .frame(maxHeight: .infinity)
        .background(colors.background)
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

// MARK: - 跑道胶囊(← Android CombinedRailItem)

/// Schedule + 当前 tab 图标上下组合, 无 label, 56pt 宽 full-rounded 胶囊;
/// 选中整组强高亮(primaryContainer 底 + onPrimaryContainer 图标),
/// 未选中透明底(← Android 语义: 胶囊只在当前槽出现, 恒 selected=true)。
private struct CombinedRailItemView: View {
    let item: PillNavItemData
    let scheduleIcon: String
    let colors: WakeUpColorScheme

    var body: some View {
        Button(action: item.onClick) {
            VStack(spacing: 0) {
                iconSlot(scheduleIcon, desc: L10n.t("tab_schedule"), dot: false)
                // 中线发丝分隔(← Android HorizontalDivider 0.5dp,
                // onSurfaceVariant × Alpha.hairline(0.3), 左右 padding 10)
                Rectangle()
                    .fill(colors.onSurfaceVariant.opacity(SleepyTheme.Alpha.hairline))
                    .frame(height: 0.5)
                    .padding(.horizontal, 10)
                iconSlot(item.icon, desc: item.label, dot: item.badge)
            }
            .frame(width: 56)
            .padding(.vertical, 4)
            .background(
                // full-rounded 胶囊(← Android RoundedCornerShape(percent = 50))
                RoundedRectangle(cornerRadius: 28)
                    .fill(item.selected ? colors.primaryContainer : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // 胶囊项标识: rail_schedule_<从tab>(与 pill_*/rail_* 同命名空间;
        // ← Android tab_schedule_today 字符串已删, 组合语义由 id 前缀承载)
        .accessibilityIdentifier("rail_schedule_\(item.id)")
    }

    private func iconSlot(_ name: String, desc: String, dot: Bool) -> some View {
        ZStack(alignment: .topTrailing) {
            // 28pt 图标盒(← Android Box(size=28) 居中 22dp 图标)
            Color.clear.frame(width: 28, height: 28)
            Image(systemName: name)
                .font(.system(size: 22))
                .foregroundColor(item.selected ? colors.onPrimaryContainer
                                               : colors.onSurfaceVariant)
                .frame(width: 28, height: 28)
            if dot {
                // 7pt primary 红点(← Android NavigationTabIcon showUpdateDot)
                Circle()
                    .fill(colors.primary)
                    .frame(width: 7, height: 7)
                    .offset(x: 4, y: -2)
            }
        }
        .accessibilityLabel(desc)
    }
}

// MARK: - 普通 rail 项(← Android PlainRailItem: NavigationRailItem icon+label)

private struct RailItemView: View {
    let item: PillNavItemData
    let colors: WakeUpColorScheme

    var body: some View {
        Button(action: item.onClick) {
            VStack(spacing: 4) {
                ZStack {
                    // 选中胶囊(← M3 indicator; master-detail 下普通项恒未选中,
                    // 保留形态与 pill/旧 rail 一致)
                    RoundedRectangle(cornerRadius: 16)
                        .fill(item.selected ? colors.primaryContainer : Color.clear)
                        .frame(width: 56, height: 32)
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: item.icon)
                            .font(.system(size: 20))
                            .foregroundColor(item.selected ? colors.onPrimaryContainer
                                                           : colors.onSurfaceVariant)
                        if item.badge {
                            Circle()
                                .fill(colors.primary)
                                .frame(width: 7, height: 7)
                                .offset(x: 4, y: -3)
                        }
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
        .buttonStyle(.plain)
        // 与 pill_* 同命名空间: rail_<id>; UITests 宽屏分支按此定位
        .accessibilityIdentifier("rail_\(item.id)")
    }
}
