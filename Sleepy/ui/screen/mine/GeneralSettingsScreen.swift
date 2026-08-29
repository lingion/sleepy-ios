// GeneralSettingsScreen.swift — ← ui/screen/mine/GeneralSettingsScreen.kt
// 通用设置页(决策 D1 L1 ⑤): 课程显示 / 小组件 / 语言 三组。
// 显示项变更后即时刷新小组件;语言切换 → LocaleHelper.applyLanguage(无 Activity.recreate,
// 等价适配:iOS 由窗口重建语言环境)。
// 分组②③与各折叠卡抽为子视图 — SwiftUI ViewBuilder 单闭包 10 子视图上限。

import SwiftUI
import WidgetKit

struct GeneralSettingsScreen: View {
    @Environment(\.localWakeUpColors) private var colors
    let onBack: () -> Void

    private let prefs = AppPrefs.shared

    @State private var expandedSections: Set<String> = []
    @State private var displayMode: String = AppPrefs.shared.getDisplayMode()
    @State private var gridSubInfo: String = AppPrefs.shared.getGridSubInfo()
    @State private var showDate: Bool = AppPrefs.shared.isShowDate()
    @State private var visibleDays: Set<Int> = AppPrefs.shared.getVisibleDays()
    @State private var courseColorless: Bool = AppPrefs.shared.isCourseColorless()

    private func toggleSection(_ key: String) {
        if expandedSections.contains(key) { expandedSections.remove(key) }
        else { expandedSections.insert(key) }
    }

    // ★ 显示项变更后立即刷小组件
    private func refreshWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    var body: some View {
        VStack(spacing: 0) {
            SettingsTopBar(title: L10n.format("mine_general"), onBack: onBack)
            ScrollView {
                VStack(spacing: 16) {
                    // ── 分组① 课程显示 ──
                    SectionHeader(title: L10n.format("appearance_section_display"))

                    displayModeCard
                    gridSubInfoCard
                    visibleDaysCard
                    showDateCard
                    courseColorlessCard

                    MajorDivider()

                    // ── 分组② 小组件 ──
                    WidgetSection(expandedSections: $expandedSections,
                                  refreshWidgets: refreshWidgets)

                    MajorDivider()

                    // ── 分组③ 语言 ──
                    LanguageSection()
                }
                .padding(16)
            }
        }
        .background(colors.background)
    }

    // 课程时间显示: 节次 / 时间
    private var displayModeCard: some View {
        SettingsCard(title: L10n.format("settings_display_mode"),
                     expanded: expandedSections.contains("displayMode"),
                     onToggle: { toggleSection("displayMode") }) {
            DisplayModeOption(label: L10n.format("settings_display_node"),
                              subtitle: L10n.format("settings_display_node_sub"),
                              selected: displayMode == "node") {
                displayMode = "node"
                prefs.setDisplayMode("node")
                refreshWidgets()
            }
            SubDivider()
            DisplayModeOption(label: L10n.format("settings_display_time"),
                              subtitle: L10n.format("settings_display_time_sub"),
                              selected: displayMode == "time") {
                displayMode = "time"
                prefs.setDisplayMode("time")
                refreshWidgets()
            }
        }
    }

    // 网格卡片副信息: 教室 / 教师 / 无
    private var gridSubInfoCard: some View {
        SettingsCard(title: L10n.format("settings_grid_sub_info"),
                     expanded: expandedSections.contains("gridSubInfo"),
                     onToggle: { toggleSection("gridSubInfo") }) {
            DisplayModeOption(label: L10n.format("settings_grid_sub_room"),
                              subtitle: L10n.format("settings_grid_sub_room_sub"),
                              selected: gridSubInfo == "room") {
                gridSubInfo = "room"
                prefs.setGridSubInfo("room")
                refreshWidgets()
            }
            SubDivider()
            DisplayModeOption(label: L10n.format("settings_grid_sub_teacher"),
                              subtitle: L10n.format("settings_grid_sub_teacher_sub"),
                              selected: gridSubInfo == "teacher") {
                gridSubInfo = "teacher"
                prefs.setGridSubInfo("teacher")
                refreshWidgets()
            }
            SubDivider()
            DisplayModeOption(label: L10n.format("settings_grid_sub_none"),
                              subtitle: L10n.format("settings_grid_sub_none_sub"),
                              selected: gridSubInfo == "none") {
                gridSubInfo = "none"
                prefs.setGridSubInfo("none")
                refreshWidgets()
            }
        }
    }

    // 显示星期: 周一~周日多选(至少留 1 天)
    private var visibleDaysCard: some View {
        SettingsCard(title: L10n.format("settings_visible_days"),
                     expanded: expandedSections.contains("visibleDays"),
                     onToggle: { toggleSection("visibleDays") }) {
            Text(L10n.format("settings_visible_days_sub"))
                .font(.system(size: 12))
                .foregroundColor(colors.onSurfaceVariant)
                .padding(.bottom, 8)
            ForEach(1...7, id: \.self) { day in
                VisibleDayRow(day: day, visibleDays: $visibleDays, onChange: { n in
                    visibleDays = n
                    prefs.setVisibleDays(n)
                    refreshWidgets()
                })
                if day != 7 { SubDivider() }
            }
        }
    }

    // 课表显示日期: 开关
    private var showDateCard: some View {
        SettingsCard(title: L10n.format("settings_show_date"),
                     expanded: expandedSections.contains("showDate"),
                     onToggle: { toggleSection("showDate") }) {
            SettingToggleRow(label: L10n.format("settings_show_date"),
                             subtitle: L10n.format("settings_show_date_sub"),
                             checked: showDate) {
                showDate = $0
                prefs.setShowDate($0)
                refreshWidgets()
            }
        }
    }

    // 课程胶囊统一底色: 开关(App 侧独立, 不刷新小组件)
    private var courseColorlessCard: some View {
        SettingsCard(title: L10n.format("settings_course_colorless"),
                     expanded: expandedSections.contains("courseColorless"),
                     onToggle: { toggleSection("courseColorless") }) {
            SettingToggleRow(label: L10n.format("settings_course_colorless"),
                             subtitle: L10n.format("settings_course_colorless_sub"),
                             checked: courseColorless) {
                courseColorless = $0
                prefs.setCourseColorless($0)
            }
        }
    }
}

// 单行星期开关(抽行: 类型推断上限)
private struct VisibleDayRow: View {
    @Environment(\.localWakeUpColors) private var colors
    let day: Int
    @Binding var visibleDays: Set<Int>
    let onChange: (Set<Int>) -> Void

    var body: some View {
        let checked = visibleDays.contains(day)
        HStack {
            Text(DateUtils.localizedDay(day))
                .font(.system(size: 16))
                .foregroundColor(colors.onSurface)
            Spacer()
            Toggle("", isOn: Binding(
                get: { checked },
                set: { on in
                    let n = on ? visibleDays.union([day]) : visibleDays.subtracting([day])
                    guard !n.isEmpty else { return }
                    onChange(n)
                }
            ))
            .toggleStyle(.switch)
            .tint(colors.primary)
            .labelsHidden()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            let n = checked ? visibleDays.subtracting([day]) : visibleDays.union([day])
            guard !n.isEmpty else { return }
            onChange(n)
        }
    }
}

// ← 分组② 小组件
private struct WidgetSection: View {
    @Environment(\.localWakeUpColors) private var colors
    @Binding var expandedSections: Set<String>
    let refreshWidgets: () -> Void

    @State private var widgetColorless: Bool = AppPrefs.shared.isWidgetColorless()
    @State private var widgetSeparator: Bool = AppPrefs.shared.isWidgetSeparator()
    @State private var vertPunct: Bool = AppPrefs.shared.isVertPunctReplace()
    private let prefs = AppPrefs.shared

    private func toggleSection(_ key: String) {
        if expandedSections.contains(key) { expandedSections.remove(key) }
        else { expandedSections.insert(key) }
    }

    var body: some View {
        VStack(spacing: 16) {
            SectionHeader(title: L10n.format("appearance_section_widget"))
            SettingsCard(title: L10n.format("settings_widget"),
                         expanded: expandedSections.contains("widget"),
                         onToggle: { toggleSection("widget") }) {
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
                SettingToggleRow(label: L10n.format("settings_vert_punct"),
                                 subtitle: L10n.format("settings_vert_punct_sub"),
                                 checked: vertPunct) {
                    vertPunct = $0
                    prefs.setVertPunctReplace($0)
                    refreshWidgets()
                }
            }
        }
    }
}

// ← 分组③ 语言
private struct LanguageSection: View {
    @Environment(\.localWakeUpColors) private var colors
    @State private var language: String = AppPrefs.shared.getLanguage()

    private let languages: [(String, String)] = [
        ("zh-CN", "简体中文"),
        ("zh-TW", "繁體中文"),
        ("en", "English"),
        ("ja", "日本語"),
        ("es", "Español")
    ]

    var body: some View {
        VStack(spacing: 16) {
            SectionHeader(title: L10n.format("settings_language"))
            VStack(spacing: 4) {
                ForEach(languages, id: \.0) { code, label in
                    let selected = language == code
                    Button {
                        language = code
                        AppPrefs.shared.setLanguage(code)
                        // Activity.recreate() → applyLanguage(重设 bundle + AppleLanguages)
                        LocaleHelper.applyLanguage(code)
                    } label: {
                        HStack {
                            Text(label)
                                .font(.system(size: 16))
                                .foregroundColor(selected ? colors.primary : colors.onSurface)
                            Spacer()
                            if selected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 20))
                                    .foregroundColor(colors.primary)
                            }
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 4)
                    }
                    .buttonStyle(SleepyButtonStyle())
                    if code != languages.last!.0 { SubDivider() }
                }
            }
            .padding(16)
            .background(colors.surfaceContainer)
            .cornerRadius(SleepyShapes.large)
        }
    }
}

// 分隔线(卡内细线 / 组间粗线 — ← HorizontalDivider outlineVariant@hairline)
private struct SubDivider: View {
    @Environment(\.localWakeUpColors) private var colors
    var body: some View {
        Rectangle()
            .fill(colors.outlineVariant.opacity(SleepyTheme.Alpha.hairline))
            .frame(height: 1)
    }
}

private struct MajorDivider: View {
    @Environment(\.localWakeUpColors) private var colors
    var body: some View {
        Rectangle()
            .fill(colors.outlineVariant.opacity(SleepyTheme.Alpha.hairline))
            .frame(height: 1)
    }
}
