// MineScreen.swift — ← ui/screen/mine/MineScreen.kt
// 我的页: 标题 + 数据统计卡(表/课/周) + 6 设置导航项 + 刷新小组件按钮(snackbar 反馈)。

import SwiftUI
import WidgetKit

struct MineScreen: View {
    @Environment(\.localWakeUpColors) private var colors
    @Environment(\.localNavExtraBottomPadding) private var navExtra
    @ObservedObject var viewModel: ScheduleViewModel
    var onOpenAllTables: () -> Void = {}
    var onOpenCourseList: () -> Void = {}
    var onOpenPeriodTables: () -> Void = {}
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
                        // ← Material 3 headlineMedium = 28sp (MineScreen.kt)
                        .font(.system(size: 28))
                        .foregroundColor(colors.onBackground)
                    Text(L10n.format("mine_subtitle"))
                        .font(.system(size: 14))
                        .foregroundColor(colors.onSurfaceVariant)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // 数据统计卡 — ← Android StatsCard(onOpenTables/onOpenCourses 可点)
                StatsCard(tableCount: state.tables.count,
                          // 与 CourseListScreen 同口径: 同名课程一组, 空名按 groupId 区分
                          courseCount: Set(state.courses.map { $0.courseName.isBlank ? "#\($0.groupId)" : $0.courseName }).count,
                          week: state.currentWeek,
                          onOpenTables: onOpenAllTables,
                          onOpenCourses: onOpenCourseList)

                // 设置项 (导航项扁平列表) — 抽出子视图(类型推断上限 workaround)
                SettingsNavList(onOpenAllTables: onOpenAllTables, onOpenPeriodTables: onOpenPeriodTables,
                                onOpenExport: onOpenExport,
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
                            .font(.system(size: 24))   // ← Android Icon 默认 24dp
                        Text(L10n.format("mine_refresh_widgets"))
                            .font(.system(size: 14, weight: .medium))   // ← labelLarge 14 Medium
                    }
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
            // 悬浮底栏额外余量(→ Android LocalNavExtraBottomPadding): 镜像 Android
            //   padding(bottom = 16.dp + navExtra) 让列表最后一行不被悬浮药丸遮住。
            .padding(.bottom, navExtra)
        }
        .background(colors.background)
        .overlay(alignment: .bottom) {
            if let msg = snackMessage {
                Text(msg)
                    .font(.system(size: 14)) // ← Android Snackbar bodyMedium 14
                    .accessibilityIdentifier("mine_snackbar")   // ← G5: 镜像 ExportScreen export_snackbar
                    .foregroundColor(colors.onSurface)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(colors.surfaceContainerHighest)
                    .cornerRadius(8)
                    // 避让悬浮药丸导航栏: 本 overlay 挂在 ScrollView 上, 而
                    // localNavExtraBottomPadding 只注入 floating 分支的 ZStack —
                    // docked 模式 env 默认 0 → padding 12 会落进贴底 bar 区
                    // (y742-806) 被吞, mine_snackbar 永不可达(2026-10-24 串行
                    // run + probe 实证)。与 ExportScreen/AboutScreen 同式读
                    // DockSpec 常量, 两模式都不遮挡。
                    .padding(.bottom, DockSpec.capsuleHeight + DockSpec.bottomFloat + 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: msg) {
                        // ← 2.5s: 与 iOS 镜像同族页(AboutScreen/ExportScreen 等)的统一停留时长。
                        // UI 测试态延到 6s(← ExportScreen 同款): 串行套件下快照延迟
                        // 会错过 2.5s 存活窗口(2026-10-24 probe 实证 tap→首查 >4s)。
                        let life: Double = ProcessInfo.processInfo.arguments
                            .contains("-SLEEPY_UI_TEST_SEED") ? 6 : 2.5
                        try? await Task.sleep(nanoseconds: UInt64(life * 1_000_000_000))
                        guard !Task.isCancelled else { return }
                        withAnimation { snackMessage = nil }
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
    // ← v1.0.60: 表数/课数两项可点进入管理页/课程清单(week 项不可点)
    var onOpenTables: () -> Void = {}
    var onOpenCourses: () -> Void = {}

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
        // ← Android Column 默认无间距(0)
        VStack(spacing: 0) {
            Text(value)
                .font(.system(size: 28, weight: .bold))   // ← Android headlineMedium
                .foregroundColor(colors.primary)
                .accessibilityIdentifier("\(identifier)_value")
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(colors.onSurfaceVariant)
                .accessibilityIdentifier("\(identifier)_label")
        }
        // ← Android StatItem 两分支同 padding(horizontal = 12.dp, vertical = 4.dp)
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
    /// ← Android highlighted: 更新提醒可见时关于行底色 primary 10% (v1.0.60 差量)
    var highlighted: Bool = false

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
            // ← Android: if (highlighted) primary.copy(alpha=0.10f) else surfaceContainer
            .background(highlighted ? colors.primary.opacity(0.10) : Color.clear)
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
            // issue#40: 时间节次表入口 — 与课表管理并列(设计 §4.1)
            SettingsItem(icon: "clock.badge.checkmark", label: L10n.format("mine_period_tables"),
                         identifier: "mine_period_tables", onClick: onOpenPeriodTables)
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
    // ← v1.0.60 差量: 关于行 highlighted = updateNoticeVisible (UpdateNotifier.noticeVisible)
    @ObservedObject private var updateNotifier = UpdateNotifier.shared
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
                         identifier: "mine_about", onClick: onOpenAbout,
                         highlighted: updateNotifier.noticeVisible)
        }
    }
}
