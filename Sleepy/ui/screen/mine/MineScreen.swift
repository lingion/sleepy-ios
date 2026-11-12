// MineScreen.swift — ← ui/screen/mine/MineScreen.kt
// 我的页: 标题 + 数据统计卡(课表/课程/作息表) + 设置导航项。
// v1.0.62 B4 (+36 对齐): 新增「小组件」入口行(→ WidgetSettingsScreen 独立页);
//   「刷新所有小组件」按钮 + snackbar 自本页迁出(动作随 widget 块移入设置页)。

import SwiftUI

struct MineScreen: View {
    @Environment(\.localWakeUpColors) private var colors
    @Environment(\.localNavExtraBottomPadding) private var navExtra
    @ObservedObject var viewModel: ScheduleViewModel
    var onOpenAllTables: () -> Void = {}
    var onOpenCourseList: () -> Void = {}
    var onOpenPeriodTables: () -> Void = {}
    var onOpenScheduleDisplay: () -> Void = {}
    var onOpenAppearance: () -> Void = {}
    var onOpenGeneral: () -> Void = {}
    var onOpenReminder: () -> Void = {}
    var onOpenAbout: () -> Void = {}

    // Complete settings pages share the app's native navigation stack.
    @SleepyNavigationState private var showWidgetSettings = false
    @SleepyNavigationState private var settingsSheet: SettingsSheet? = nil
    private enum SettingsSheet: String, Identifiable {
        case holiday, backup
        var id: String { rawValue }
    }

    var body: some View {
        let state = viewModel.state
        ScrollView {
            VStack(spacing: 16) {
                // Header: "我的" + 副标题
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.format("tab_mine"))
                        // ← Material 3 headlineMedium = 28sp (MineScreen.kt)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(colors.onBackground)
                    Text(L10n.format("mine_subtitle"))
                        .font(.system(size: 14))
                        .foregroundColor(colors.onSurfaceVariant)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // 数据统计卡 — ← 原版本 StatsCard(onOpenTables/onOpenCourses 可点)
                StatsCard(tableCount: state.tables.count,
                          // 与 CourseListScreen 同口径: 同名课程一组, 空名按 groupId 区分
                          courseCount: Set(state.courses.map { $0.courseName.isBlank ? "#\($0.groupId)" : $0.courseName }).count,
                          periodTableCount: viewModel.allPeriodTables.count,
                          onOpenTables: onOpenAllTables,
                          onOpenCourses: onOpenCourseList,
                          onOpenPeriodTables: onOpenPeriodTables)

                // 设置项 (导航项扁平列表) — 抽出子视图(类型推断上限 workaround)
                SettingsNavList(onOpenAllTables: onOpenAllTables, onOpenPeriodTables: onOpenPeriodTables,
                                onOpenReminder: onOpenReminder, onOpenScheduleDisplay: onOpenScheduleDisplay,
                                onOpenAppearance: onOpenAppearance,
                                onOpenGeneral: onOpenGeneral, onOpenAbout: onOpenAbout,
                                onOpenWidgetSettings: { showWidgetSettings = true },
                                onOpenHoliday: { settingsSheet = .holiday },
                                onOpenBackup: { settingsSheet = .backup })

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
            // 悬浮底栏额外余量(→ 原版本 LocalNavExtraBottomPadding): 镜像原实现
            //   padding(bottom = 16.dp + navExtra) 让列表最后一行不被悬浮药丸遮住。
            .padding(.bottom, navExtra)
        }
        .background(colors.background)
        .sleepyNavigationPage(item: $settingsSheet, changes: _settingsSheet.changes, canvas: {
            colors.background.ignoresSafeArea()
        }) { sheet in
            switch sheet {
            case .holiday:
                HolidaySettingsScreen(onDismiss: { settingsSheet = nil },
                                      tableId: viewModel.state.selectedTableId,
                                      refreshTransfer: { viewModel.refreshTransfer() })
            case .backup:
                GeneralSettingsScreen(onDismiss: { settingsSheet = nil }, viewModel: viewModel, section: .backup)
            }
        }
        .sleepyNavigationPage(isPresented: $showWidgetSettings, changes: _showWidgetSettings.changes, canvas: {
            colors.background.ignoresSafeArea()
        }) {
            WidgetSettingsScreen(onDismiss: { showWidgetSettings = false }, viewModel: viewModel)
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
    let periodTableCount: Int
    var onOpenTables: () -> Void = {}
    var onOpenCourses: () -> Void = {}
    var onOpenPeriodTables: () -> Void = {}

    var body: some View {
        // ← Arrangement.SpaceEvenly: 三项中心均匀分布(1/6, 1/2, 5/6) = 两边靠边中间居中。
        //   等宽 frame → StatItem 各占 1/3 且内容居中, 中心位置与 SpaceEvenly 一致。
        HStack(spacing: 0) {
            Button(action: onOpenTables) {
                StatItem(value: "\(tableCount)", label: L10n.format("mine_stat_tables"),
                         identifier: "mine_stat_tables")
            }
            .buttonStyle(SleepyButtonStyle())
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("mine_stat_tables")
            VDivider()
            Button(action: onOpenCourses) {
                StatItem(value: "\(courseCount)", label: L10n.format("mine_stat_courses"),
                         identifier: "mine_stat_courses")
            }
            .buttonStyle(SleepyButtonStyle())
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("mine_stat_courses")
            VDivider()
            Button(action: onOpenPeriodTables) {
                StatItem(value: "\(periodTableCount)", label: L10n.format("mine_stat_period_tables"),
                         identifier: "mine_stat_period_tables")
            }
            .buttonStyle(SleepyButtonStyle())
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("mine_stat_period_tables")
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
        // ← 原版本 Column 默认无间距(0)
        VStack(spacing: 0) {
            Text(value)
                .font(.system(size: 28, weight: .bold))   // ← 原 headlineMedium
                .foregroundColor(colors.primary)
                .accessibilityIdentifier("\(identifier)_value")
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(colors.onSurfaceVariant)
                .accessibilityIdentifier("\(identifier)_label")
        }
        // ← 原版本 StatItem 两分支同 padding(horizontal = 12.dp, vertical = 4.dp)
        //   (MineScreen.kt:201-202): 可点/静态均扩大点击区并抬高 StatsCard 约 8pt。
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}

// ← SettingsItem
private struct SettingsItem: View {
    @Environment(\.localWakeUpColors) private var colors
    let icon: AndroidSettingsIcon.Name
    let label: String
    let identifier: String       // ← G5: UI 测试稳定锚点
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            HStack(spacing: 16) {
                AndroidSettingsIcon(name: icon, size: 20)
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
            .frame(maxWidth: .infinity)
            // (v1.0.60 关于行更新高亮随「获取更新」切片 1.0.64 移除)
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

// ← 设置项列表(导航项 + 分隔线)
private struct SettingsNavList: View {
    @Environment(\.localWakeUpColors) private var colors
    let onOpenAllTables: () -> Void
    let onOpenPeriodTables: () -> Void
    let onOpenReminder: () -> Void
    let onOpenScheduleDisplay: () -> Void
    let onOpenAppearance: () -> Void
    let onOpenGeneral: () -> Void
    let onOpenAbout: () -> Void
    let onOpenWidgetSettings: () -> Void
    let onOpenHoliday: () -> Void
    let onOpenBackup: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            SectionHeader(title: L10n.format("settings_schedule_management"))
            group {
                SettingsItem(icon: .edit, label: L10n.format("all_tables"),
                             identifier: "mine_all_tables", onClick: onOpenAllTables)
                HDivider()
                SettingsItem(icon: .schedule, label: L10n.format("mine_period_tables"),
                             identifier: "mine_period_tables", onClick: onOpenPeriodTables)
                HDivider()
                SettingsItem(icon: .dateRange, label: L10n.format("settings_holidays"),
                             identifier: "mine_holiday", onClick: onOpenHoliday)
            }
            SectionHeader(title: L10n.format("settings_application"))
            group {
                SettingsItem(icon: .notifications, label: L10n.format("reminder_title"),
                             identifier: "mine_reminder", onClick: onOpenReminder)
                HDivider()
                SettingsItem(icon: .palette, label: L10n.format("mine_appearance"),
                             identifier: "mine_appearance", onClick: onOpenAppearance)
                HDivider()
                SettingsItem(icon: .dateRange, label: L10n.format("mine_schedule_settings"),
                             identifier: "mine_schedule_settings", onClick: onOpenScheduleDisplay)
                HDivider()
                SettingsItem(icon: .tune, label: L10n.format("mine_general"),
                             identifier: "mine_general", onClick: onOpenGeneral)
                HDivider()
                SettingsItem(icon: .widgets, label: L10n.format("mine_widget"),
                             identifier: "mine_widget", onClick: onOpenWidgetSettings)
            }
            SectionHeader(title: L10n.format("settings_data"))
            group {
                SettingsItem(icon: .saveAlt, label: L10n.format("settings_backup"),
                             identifier: "mine_backup", onClick: onOpenBackup)
            }
            group {
                SettingsItem(icon: .info, label: L10n.format("about_title"),
                             identifier: "mine_about", onClick: onOpenAbout)
            }
        }
    }
    private func group<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0, content: content).background(colors.surfaceContainer).cornerRadius(SleepyShapes.large)
    }
}
