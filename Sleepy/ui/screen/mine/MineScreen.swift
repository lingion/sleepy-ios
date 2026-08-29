// MineScreen.swift — ← ui/screen/mine/MineScreen.kt
// 我的页: 标题 + 数据统计卡(表/课/周) + 6 设置导航项 + 刷新小组件按钮(snackbar 反馈)。

import SwiftUI
import WidgetKit

struct MineScreen: View {
    @Environment(\.localWakeUpColors) private var colors
    @ObservedObject var viewModel: ScheduleViewModel
    var onOpenAllTables: () -> Void = {}
    var onOpenAppearance: () -> Void = {}
    var onOpenGeneral: () -> Void = {}
    var onOpenExport: () -> Void = {}
    var onOpenReminder: () -> Void = {}
    var onOpenAbout: () -> Void = {}

    @State private var snackMessage: String? = nil

    var body: some View {
        let state = viewModel.state
        ScrollView {
            VStack(spacing: 16) {
                // Header: "我的" + 副标题
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.format("tab_mine"))
                        .font(.system(size: 22))
                        .foregroundColor(colors.onBackground)
                    Text(L10n.format("mine_subtitle"))
                        .font(.system(size: 14))
                        .foregroundColor(colors.onSurfaceVariant)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // 数据统计卡
                StatsCard(tableCount: state.tables.count,
                          courseCount: Set(state.courses.map { $0.courseName }).count,
                          week: state.currentWeek)

                // 设置项 (6 个导航项扁平列表) — 抽出子视图(类型推断上限 workaround)
                SettingsNavList(onOpenAllTables: onOpenAllTables, onOpenExport: onOpenExport,
                                onOpenReminder: onOpenReminder, onOpenAppearance: onOpenAppearance,
                                onOpenGeneral: onOpenGeneral, onOpenAbout: onOpenAbout)

                // 动作区: 刷新所有小组件
                Button {
                    // ← WidgetUpdater.notifyDataChanged → WidgetCenter.reloadAllTimelines
                    WidgetCenter.shared.reloadAllTimelines()
                    snackMessage = L10n.format("mine_refresh_widgets_done")
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                        Text(L10n.format("mine_refresh_widgets"))
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(colors.onSecondaryContainer)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(colors.secondaryContainer)
                    .cornerRadius(SleepyShapes.large)
                }
                .buttonStyle(SleepyButtonStyle())
                .accessibilityIdentifier("mine_refresh_widgets")

                // Widget 归档诊断钩子: UI 测试 runner 无 App Group 权限读
                // widget_archive.log, 由 app 进程(有权限)把日志内容透出到
                // 无障碍 label 供 XCUITest 断言(仅 -SLEEPY_WIDGET_LOG_HOOK 时渲染)。
                if ProcessInfo.processInfo.arguments.contains("-SLEEPY_WIDGET_LOG_HOOK") {
                    Text(Self.widgetArchiveLogText())
                        .font(.system(size: 9))
                        .foregroundColor(colors.onSurfaceVariant)
                        .accessibilityIdentifier("widget_archive_log")
                }
            }
            .padding(16)
        }
        .background(colors.background)
        .overlay(alignment: .bottom) {
            if let msg = snackMessage {
                Text(msg)
                    .font(.system(size: 13))
                    .foregroundColor(colors.onSurface)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(colors.surfaceContainerHighest)
                    .cornerRadius(8)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation { snackMessage = nil }
                        }
                    }
            }
        }
    }

    /// 读 App Group 内 widget 归档日志(WidgetArchiveLog 的 app 侧读取端;
    /// runner 沙箱读不了 group 容器, 此钩子代读后经 label 暴露给 XCUITest)。
    private static func widgetArchiveLogText() -> String {
        let url = AppGroupResolver.sharedDirectory().appendingPathComponent("widget_archive.log")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? "ARCHIVE_LOG_EMPTY"
    }
}

// ← StatsCard
private struct StatsCard: View {
    @Environment(\.localWakeUpColors) private var colors
    let tableCount: Int
    let courseCount: Int
    let week: Int

    var body: some View {
        // ← Arrangement.SpaceEvenly: 三项中心均匀分布(1/6, 1/2, 5/6) = 两边靠边中间居中。
        //   等宽 frame → StatItem 各占 1/3 且内容居中, 中心位置与 SpaceEvenly 一致。
        HStack(spacing: 0) {
            StatItem(value: "\(tableCount)", label: L10n.format("mine_stat_tables"),
                     identifier: "mine_stat_tables")
                .frame(maxWidth: .infinity)
            VDivider()
            StatItem(value: "\(courseCount)", label: L10n.format("mine_stat_courses"),
                     identifier: "mine_stat_courses")
                .frame(maxWidth: .infinity)
            VDivider()
            StatItem(value: "\(week)", label: L10n.format("mine_stat_week"),
                     identifier: "mine_stat_week")
                .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .background(colors.surfaceContainer)
        .cornerRadius(SleepyShapes.large)
    }
}

// ← StatItem
private struct StatItem: View {
    @Environment(\.localWakeUpColors) private var colors
    let value: String
    let label: String
    let identifier: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(colors.primary)
                .accessibilityIdentifier("\(identifier)_value")
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(colors.onSurfaceVariant)
                .accessibilityIdentifier("\(identifier)_label")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}

// ← SettingsItem
private struct SettingsItem: View {
    @Environment(\.localWakeUpColors) private var colors
    let icon: String
    let label: String
    let identifier: String       // ← G5: UI 测试稳定锚点
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(colors.onPrimaryContainer)
                    .frame(width: 40, height: 40)
                    .background(colors.primaryContainer)
                    .cornerRadius(SleepyShapes.medium)
                Text(label)
                    .font(.system(size: 16))
                    .foregroundColor(colors.onSurface)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .buttonStyle(SleepyButtonStyle())
        .accessibilityIdentifier(identifier)
    }
}

// ← Divider(横/竖)
private struct HDivider: View {
    @Environment(\.localWakeUpColors) private var colors
    var body: some View {
        Rectangle()
            .fill(colors.outline.opacity(SleepyTheme.Alpha.hairline))
            .frame(height: 1)
            .padding(.leading, 72)
    }
}

private struct VDivider: View {
    @Environment(\.localWakeUpColors) private var colors
    var body: some View {
        Rectangle()
            .fill(colors.outline.opacity(SleepyTheme.Alpha.hairline))
            .frame(width: 1, height: 36)
    }
}

// ← 设置项列表(6 项 + 分隔线)
private struct SettingsNavList: View {
    @Environment(\.localWakeUpColors) private var colors
    let onOpenAllTables: () -> Void
    let onOpenExport: () -> Void
    let onOpenReminder: () -> Void
    let onOpenAppearance: () -> Void
    let onOpenGeneral: () -> Void
    let onOpenAbout: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            SettingsItem(icon: "square.and.pencil", label: L10n.format("all_tables"),
                         identifier: "mine_all_tables", onClick: onOpenAllTables)
            HDivider()
            SettingsItem(icon: "square.and.arrow.up", label: L10n.format("mine_export"),
                         identifier: "mine_export", onClick: onOpenExport)
            HDivider()
            SettingsItem(icon: "bell", label: L10n.format("reminder_title"),
                         identifier: "mine_reminder", onClick: onOpenReminder)
            HDivider()
            SettingsNavListB(onOpenAppearance: onOpenAppearance, onOpenGeneral: onOpenGeneral,
                             onOpenAbout: onOpenAbout)
        }
        .background(colors.surfaceContainer)
        .cornerRadius(SleepyShapes.large)
    }
}

private struct SettingsNavListB: View {
    @Environment(\.localWakeUpColors) private var colors
    let onOpenAppearance: () -> Void
    let onOpenGeneral: () -> Void
    let onOpenAbout: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            SettingsItem(icon: "paintpalette", label: L10n.format("mine_appearance"),
                         identifier: "mine_appearance", onClick: onOpenAppearance)
            HDivider()
            SettingsItem(icon: "slider.horizontal.3", label: L10n.format("mine_general"),
                         identifier: "mine_general", onClick: onOpenGeneral)
            HDivider()
            SettingsItem(icon: "info.circle", label: L10n.format("about_title"),
                         identifier: "mine_about", onClick: onOpenAbout)
        }
    }
}
