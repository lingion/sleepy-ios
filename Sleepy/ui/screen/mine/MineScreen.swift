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
    var onOpenAppearance: () -> Void = {}
    var onOpenGeneral: () -> Void = {}
    var onOpenReminder: () -> Void = {}
    var onOpenAbout: () -> Void = {}

    // v1.0.62 B4: 「小组件」入口 → WidgetSettingsScreen(内嵌 cover 链,
    //   与 holiday/widgetManagement 同款惯例, 无根 overlay 承载)
    @State private var showWidgetSettings = false

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
                                onOpenReminder: onOpenReminder, onOpenAppearance: onOpenAppearance,
                                onOpenGeneral: onOpenGeneral, onOpenAbout: onOpenAbout,
                                onOpenWidgetSettings: { showWidgetSettings = true })

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
        // v1.0.62 B4: 小组件设置页 cover(与 GeneralSettings→WidgetManagement 链同款惯例)
        .fullScreenCover(isPresented: $showWidgetSettings) {
            WidgetSettingsScreen(onDismiss: { showWidgetSettings = false })
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
            VDivider()
            Button(action: onOpenCourses) {
                StatItem(value: "\(courseCount)", label: L10n.format("mine_stat_courses"),
                         identifier: "mine_stat_courses")
            }
            .buttonStyle(SleepyButtonStyle())
            .frame(maxWidth: .infinity)
            VDivider()
            Button(action: onOpenPeriodTables) {
                StatItem(value: "\(periodTableCount)", label: L10n.format("mine_stat_period_tables"),
                         identifier: "mine_stat_period_tables")
            }
            .buttonStyle(SleepyButtonStyle())
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
    let onOpenAppearance: () -> Void
    let onOpenGeneral: () -> Void
    let onOpenAbout: () -> Void
    // v1.0.62 B4: 「小组件」入口行(原版本 MineScreen +36: Widgets 图标项,
    //   插在「通用」与「关于」之间)
    let onOpenWidgetSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            SettingsItem(icon: "square.and.pencil", label: L10n.format("all_tables"),
                         identifier: "mine_all_tables", onClick: onOpenAllTables)
            HDivider()
            // issue#40: 时间节次表入口 — 与课表管理并列(设计 §4.1)
            SettingsItem(icon: "clock.badge.checkmark", label: L10n.format("mine_period_tables"),
                         identifier: "mine_period_tables", onClick: onOpenPeriodTables)
            HDivider()
            SettingsItem(icon: "bell", label: L10n.format("reminder_title"),
                         identifier: "mine_reminder", onClick: onOpenReminder)
            HDivider()
            SettingsNavListB(onOpenAppearance: onOpenAppearance, onOpenGeneral: onOpenGeneral,
                             onOpenAbout: onOpenAbout, onOpenWidgetSettings: onOpenWidgetSettings)
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
    let onOpenWidgetSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            SettingsItem(icon: "paintpalette", label: L10n.format("mine_appearance"),
                         identifier: "mine_appearance", onClick: onOpenAppearance)
            HDivider()
            SettingsItem(icon: "slider.horizontal.3", label: L10n.format("mine_general"),
                         identifier: "mine_general", onClick: onOpenGeneral)
            HDivider()
            // v1.0.62 B4: 小组件入口(← Icons.Outlined.Widgets; iOS 无同名 SF Symbol,
            //   取同义 2×2 方格网格 — 原版本 Widgets 图标即 2×2 方块)
            SettingsItem(icon: "square.grid.2x2", label: L10n.format("mine_widget"),
                         identifier: "mine_widget", onClick: onOpenWidgetSettings)
            HDivider()
            SettingsItem(icon: "info.circle", label: L10n.format("about_title"),
                         identifier: "mine_about", onClick: onOpenAbout)
        }
    }
}
