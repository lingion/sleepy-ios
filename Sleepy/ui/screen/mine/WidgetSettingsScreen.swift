// WidgetSettingsScreen.swift — ← ui/screen/mine/WidgetSettingsScreen.kt (v1.0.62 B4)
// 小组件设置页(设计 §3): 原通用页「小组件」板块整体平移至此, 与「通用」并列。
//
// 内容 = 外观开关组(去色/分隔线/最近忙日) + 「添加或管理桌面小组件」条目 +
// 页尾「刷新所有小组件」按钮(2026-10-18 用户定版: 自「我的」页迁来,
// 仅当桌面已有已放置实例时出现 — 数据源与「添加或管理」列表同一条
// loadPlacedWidgets, 零新通路)。页尾留 navExtra 余量, 与底部悬浮栏约定对齐。
//
// 偏好存储键零迁移 — 与 GeneralSettingsScreen 时代完全一致。
//
// ★ 平台差异(差异表#8 附注): Android ON_RESUME 重扫桌面实例; iOS 无 lifecycle
//   等价 → 管理页 fullScreenCover 关闭回调处 reload(去画廊/桌面增删小组件后
//   回本页, 刷新按钮出现/消失态不滞留), 首次进入走 .task。

import SwiftUI
import WidgetKit

struct WidgetSettingsScreen: View {
    @Environment(\.localWakeUpColors) private var colors
    @Environment(\.localNavExtraBottomPadding) private var navExtra
    // ★ v7.10.18 原生化: onDismiss(由 MineScreen fullScreenCover 关闭)
    let onDismiss: () -> Void

    // ← expanded rememberSaveable 默认 true(会话态足够, 与通用页折叠卡同精神)
    @State private var expanded = true
    // ← AppPrefs.isWidgetColorless / isWidgetSeparator / isNearestBusyDay
    @State private var widgetColorless = AppPrefs.shared.isWidgetColorless()
    @State private var widgetSeparator = AppPrefs.shared.isWidgetSeparator()
    @State private var nearestBusyDay = AppPrefs.shared.isNearestBusyDay()

    // ← 已放置实例 = 页尾刷新按钮的存在条件(单一真源, 同「添加或管理」页)
    @State private var placedItems: [PlacedWidgetItem] = []
    // ← onOpenWidgetManagement: 跳二级页列出已放置的小组件(右上 ＋ 进画廊)
    @State private var showManage = false
    // ← 刷新成功反馈: 按钮迁移自「我的」页, snackbar 链随迁
    @State private var snackMessage: String? = nil

    private let prefs = AppPrefs.shared

    // ← 显示项变更后立即刷小组件(管线随板块自 GeneralSettingsScreen 平移)
    //   WidgetUpdater.notifyDataChanged → WidgetCenter.reloadAllTimelines
    private func refreshWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    // ← vm.reload() 等价: 重扫已放置实例(单一真源 = WidgetCenter)
    private func reloadPlaced() {
        Task { placedItems = await loadPlacedWidgets() }
    }

    var body: some View {
        VStack(spacing: 0) {
            SettingsTopBar(title: L10n.format("mine_widget"), onBack: onDismiss)
            ScrollView {
                VStack(spacing: 16) {
                    SectionHeader(title: L10n.format("appearance_section_widget"))

                    SettingsCard(title: L10n.format("settings_widget"),
                                 expanded: expanded,
                                 onToggle: { expanded.toggle() }) {
                        SettingToggleRow(label: L10n.format("settings_widget_colorless"),
                                         subtitle: L10n.format("settings_widget_colorless_sub"),
                                         checked: widgetColorless) {
                            widgetColorless = $0
                            prefs.setWidgetColorless($0)
                            refreshWidgets()
                        }
                        SubDivider()
                        SettingToggleRow(label: L10n.format("settings_widget_separator"),
                                         subtitle: L10n.format("settings_widget_separator_sub"),
                                         checked: widgetSeparator) {
                            widgetSeparator = $0
                            prefs.setWidgetSeparator($0)
                            refreshWidgets()
                        }
                        SubDivider()
                        SettingToggleRow(label: L10n.format("settings_nearest_busy_day"),
                                         subtitle: L10n.format("settings_nearest_busy_day_sub"),
                                         checked: nearestBusyDay) {
                            nearestBusyDay = $0
                            // Android setNearestBusyDay + refreshWidgets; iOS setter 内部已
                            // reloadAllTimelines(AppPrefs.swift), 再显式刷一次与 Android 同构无害
                            prefs.setNearestBusyDay($0)
                            refreshWidgets()
                        }
                    }

                    // 添加或管理桌面小组件: 跳「添加或管理」页(右上 ＋ 进画廊)
                    manageEntry

                    // 刷新所有小组件: 桌面已有已放置实例才出现(空桌面 = 无可刷, 按钮隐藏)
                    if !placedItems.isEmpty {
                        refreshButton
                    }
                }
                .padding(16)
                // 页尾余量(→ Android LocalNavExtraBottomPadding): 悬浮底栏不压按钮
                .padding(.bottom, navExtra)
            }
        }
        .background(colors.background)
        .navigationBarHidden(true)
        // ← SnackbarHost: 底部胶囊浮层(仓库同款, 与 MineScreen 同式读 DockSpec)
        .overlay(alignment: .bottom) {
            if let msg = snackMessage {
                Text(msg)
                    .font(.system(size: 14)) // ← Android Snackbar bodyMedium 14
                    .accessibilityIdentifier("widget_settings_snackbar")
                    .foregroundColor(colors.onSurface)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(colors.surfaceContainerHighest)
                    .cornerRadius(8)
                    .padding(.bottom, DockSpec.capsuleHeight + DockSpec.bottomFloat + 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: msg) {
                        // ← 2.5s: 与 MineScreen 镜像同族页统一停留时长
                        let life: Double = ProcessInfo.processInfo.arguments
                            .contains("-SLEEPY_UI_TEST_SEED") ? 6 : 2.5
                        try? await Task.sleep(nanoseconds: UInt64(life * 1_000_000_000))
                        guard !Task.isCancelled else { return }
                        withAnimation { snackMessage = nil }
                    }
            }
        }
        // ← 首次进入取已放置实例(等价 Android 首帧 collect)
        .task { reloadPlaced() }
        .fullScreenCover(isPresented: $showManage) {
            WidgetManagementScreen(onDismiss: {
                showManage = false
                // ← Android ON_RESUME 重扫: 画廊 pin/编辑绑定后回本页重扫,
                //    刷新按钮出现/消失态不滞留
                reloadPlaced()
            })
        }
    }

    // ← 管理入口行: GeneralSettingsScreen 时代同款(titleSmall + ChevronRight 20dp)
    private var manageEntry: some View {
        Button { showManage = true } label: {
            HStack {
                Text(L10n.format("widget_manage_entry"))
                    .font(.system(size: 14, weight: .medium)) // ← Android titleSmall 14sp Medium
                    .foregroundColor(colors.onSurface)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 20))
                    .foregroundColor(colors.onSurfaceVariant)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(colors.surfaceContainer)
            .cornerRadius(SleepyShapes.large)
        }
        .buttonStyle(SleepyButtonStyle())
        .accessibilityIdentifier("settings_widget_manage_entry")
    }

    // ← FilledTonalButton: secondaryContainer 底 + Refresh 图标(自「我的」页迁来)
    private var refreshButton: some View {
        Button {
            refreshWidgets()
            snackMessage = L10n.format("mine_refresh_widgets_done")
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 24))   // ← Android Icon 默认 24dp
                Text(L10n.format("mine_refresh_widgets"))
                    .font(.system(size: 14, weight: .medium))   // ← labelLarge 14 Medium
            }
            .foregroundColor(colors.onSecondaryContainer)
            .frame(maxWidth: .infinity)
            .frame(height: 48)   // ← SleepyTheme.Buttons.regularHeight
            .background(colors.secondaryContainer)
            .cornerRadius(SleepyShapes.large)
        }
        .buttonStyle(SleepyButtonStyle())
        .accessibilityIdentifier("widget_settings_refresh")
    }
}

// ← HorizontalDivider(hairline) — 卡内开关行分隔(GeneralSettingsScreen 同款私有件)
private struct SubDivider: View {
    @Environment(\.localWakeUpColors) private var colors
    var body: some View {
        Rectangle()
            .fill(colors.outlineVariant.opacity(SleepyTheme.Alpha.hairline))
            .frame(height: 1)
    }
}
