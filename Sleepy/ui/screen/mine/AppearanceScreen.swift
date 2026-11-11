// Appearance groups palette, interface material, navigation shape and the schedule display entry.
import SwiftUI
import UIKit
import WidgetKit
import Combine

struct AppearanceScreen: View {
    @Environment(\.localWakeUpColors) private var colors
    let onDismiss: () -> Void
    var themeMode: String = AppPrefs.THEME_MODE_SYSTEM
    var onThemeModeChange: (String) -> Void = { _ in }
    // ← 原版本 themeKeyFlow.collectAsState: 选色即时生效,经 AppRoot 回写 themeKey
    var onThemeKeyChange: () -> Void = {}
    // ← 原版本 onOpenPeriodHeaderSettings(Section④ 节次表头入口, 默认 no-op 保持 API 兼容,
    //   接线 .periodHeaderSettings 路由归共享文件 SleepyApp/SleepyNavigator, 见 needs_shared_wiring)
    var onOpenPeriodHeaderSettings: () -> Void = {}
    var onOpenScheduleDisplay: () -> Void = {}
    @State private var uiStyle = AppPrefs.shared.getUiStyle()
    @State private var navStyleIndex = NavStyleResolver.isFloatingRequested() ? 1 : 0

    @State private var currentKey: String
    // 自定义主题列表(编辑器保存/删除后重载)← 原版本 customListVersion
    @State private var customThemes: [CustomTheme] = CustomThemeStore.getAll()
    @State private var showEditor = false
    @State private var editingTheme: CustomTheme?
    @ObservedObject private var hueStore = CourseHueStore.shared
    @State private var courseColorless = AppPrefs.shared.isCourseColorless()
    @State private var courseColorMode = AppPrefs.shared.getCourseColorMode()
    @State private var hueSession = HueEditingSession(initialHue: AppPrefs.shared.getCourseColorSeedHue())
    @State private var previewGroups: [CourseColorPreview] = []
    private let prefs = AppPrefs.shared

    init(onDismiss: @escaping () -> Void,
         themeMode: String = AppPrefs.THEME_MODE_SYSTEM,
         onThemeModeChange: @escaping (String) -> Void = { _ in },
         onThemeKeyChange: @escaping () -> Void = {},
         onOpenPeriodHeaderSettings: @escaping () -> Void = {},
         onOpenScheduleDisplay: @escaping () -> Void = {}) {
        self.onDismiss = onDismiss
        self.themeMode = themeMode
        self.onThemeModeChange = onThemeModeChange
        self.onThemeKeyChange = onThemeKeyChange
        self.onOpenPeriodHeaderSettings = onOpenPeriodHeaderSettings
        self.onOpenScheduleDisplay = onOpenScheduleDisplay
        _currentKey = State(initialValue: AppPrefs.shared.getThemeKey())
    }

    /// 网格顺序不变量(d87eade3 + c1c166f9):预设 → 自定义 → 新建入口,加号永远在整网格
    /// 末尾且与自定义主题数量无关。抽成纯函数是为了让「顺序本身」被契约测试锁死
    /// (SleepyTests/CustomThemeTests.swift 的 CustomThemeGridTests),而不是只靠肉眼看 UI。
    static func gridCells(presets: [ThemePreset], customs: [CustomTheme]) -> [ThemeGridCell] {
        presets.map { ThemeGridCell.preset($0) }
            + customs.map { ThemeGridCell.custom($0) }
            + [ThemeGridCell.newTheme]
    }

    var body: some View {
        VStack(spacing: 0) {
            SettingsTopBar(title: L10n.format("mine_appearance"), onBack: onDismiss)
            ScrollView {
                VStack(spacing: SettingsLayout.cardGap) {
                    SettingsSection(title: L10n.format("theme_appearance"), first: true) {
                        SegmentedSwitcher(
                            options: [(AppPrefs.THEME_MODE_SYSTEM, L10n.format("theme_mode_system")),
                                      (AppPrefs.THEME_MODE_LIGHT, L10n.format("theme_mode_light")),
                                      (AppPrefs.THEME_MODE_DARK, L10n.format("theme_mode_dark"))],
                            selected: themeMode,
                            onSelect: { mode in
                                guard mode != themeMode else { return }
                                prefs.setThemeMode(mode)
                                onThemeModeChange(mode)
                                refreshThemeCourseColors()
                                refreshWidgets()
                            }, containerColor: colors.surfaceContainerHighest)
                            .accessibilityIdentifier("settings_mode_segment")
                    }
                    SettingsSection(title: L10n.format("appearance_section_theme")) {
                    SystemThemeCard(selected: currentKey == ThemePresets.KEY_SYSTEM) {
                        selectThemeKey(ThemePresets.KEY_SYSTEM)
                    }

                    // 2 列网格:5 套预设 → 各自定义卡 → 新建入口(加号)
                    // ★ 顺序不变量(d87eade3 + c1c166f9):预设 → 自定义 → 加号,加号永远
                    //   排在整网格末尾,与自定义主题数量无关;自定义卡与预设卡同尺寸同构。
                    let cells: [ThemeGridCell] = Self.gridCells(presets: ThemePresets.all, customs: customThemes)
                    VStack(spacing: 12) {
                        ForEach(Array(cells.chunked(into: 2).enumerated()), id: \.offset) { _, row in
                            HStack(spacing: 12) {
                                ForEach(row) { cell in
                                    ThemeGridCellView(
                                        cell: cell,
                                        currentKey: currentKey,
                                        onSelect: selectThemeKey,
                                        onEdit: openEditor
                                    )
                                }
                                // 奇数行补空位:用等弹性占位而非 Spacer,保证单卡也严格半宽
                                // (与 原版本 Box(Modifier.weight(1f)) 等价)
                                if row.count == 1 {
                                    Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
                                }
                            }
                        }
                    }

                    }
                    SettingsSection(title: L10n.format("settings_appearance_navigation")) {
                    SettingsFlatCard(title: L10n.format("settings_nav_style"),
                                     options: [L10n.format("settings_nav_style_docked"),
                                               L10n.format("settings_nav_style_floating")],
                                     selectedIndex: Binding(get: { navStyleIndex }, set: {
                                         navStyleIndex = $0; prefs.setNavDocked($0 == 1)
                                     }))
                        .accessibilityIdentifier("appearance_navigation_shape")
                    }
                    VStack(alignment: .leading, spacing: SettingsLayout.headerGap) {
                        Text(L10n.format("appearance_section_dock_theme")).font(SettingsLayout.headingStyle).foregroundColor(colors.onSurface)
                    SettingsFlatCard(title: L10n.format("appearance_section_dock_theme")) {
                        SegmentedSwitcher(options: [("classic", L10n.format("dock_theme_classic")),
                                                    ("liquid_glass", L10n.format("dock_theme_liquid_glass"))],
                                          selected: uiStyle, onSelect: { value in
                                              uiStyle = value; prefs.setUiStyle(value)
                                          }, containerColor: colors.surfaceContainerHighest)
                            .accessibilityIdentifier("appearance_ui_style")
                    }
                    }
                    SettingsSection(title: L10n.format("appearance_section_course_color")) {
                    CourseColorSection(
                        mode: courseColorMode,
                        colorless: courseColorless,
                        seed: prefs.getCourseColorSeedHue(),
                        sliderHue: hueSession.current,
                        initialHue: hueSession.baseline,
                        hueMap: hueStore.hueMap,
                        previewGroups: previewGroups,
                        onModeChange: selectCourseColorMode,
                        onSliderChange: { hueSession.current = $0 },
                        onSeedCommit: commitCourseHue,
                        onRecalc: recalcAllCourses
                    )
                        .onAppear {
                            loadCourseColorState()
                            Task { await refreshHueStore() }
                        }
                        .onDisappear {
                            Task { await refreshHueStore() }
                        }

                    }
                    AppearanceNavigationRow(
                        title: L10n.format("appearance_section_schedule_display"),
                        onClick: onOpenScheduleDisplay)
                        .accessibilityIdentifier("appearance_schedule_display")
                }
                .padding(16)
            }
        }
        .background(colors.background)
        .onReceive(prefs.uiStylePublisher) { uiStyle = $0 }
        // 自定义主题编辑器 ← 原版本 全屏 overlay;iOS 用 sheet 承载,
        // 这样编辑器内部的 .interactiveDismissDisabled(dirty) 才真正挡住下滑手势。
        .sheet(isPresented: $showEditor, onDismiss: { editingTheme = nil }) {
            CustomThemeEditorScreen(
                editing: editingTheme,
                nextThemeNumber: customThemes.count + 1,
                onBack: { showEditor = false },
                onSaved: saveTheme,
                onDeleted: deleteTheme
            )
            // sheet 内容不保证继承宿主 environment,显式把当前主题色带进去
            .environment(\.localWakeUpColors, colors)
        }
    }

    // ★ 选主题/模式后立即刷小组件(← WidgetUpdater.notifyDataChanged)
    private func refreshWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// 刷新 CourseHueStore 快照 — 进入/离开外观页、主题/配色模式切换时调用。
    private func refreshHueStore() async {
        let db = AppDatabase.getShared()
        await CourseHueStore.shared.refresh(
            mode: prefs.getCourseColorMode(), dao: db.courseColorDao
        )
    }

    private func loadCourseColorState() {
        courseColorless = prefs.isCourseColorless()
        courseColorMode = prefs.getCourseColorMode()
        // 同一视图身份的会话基线不在 onAppear/提交时重置。
        let courses = (try? AppDatabase.getShared().courseDao.getAllCourses()) ?? []
        previewGroups = CourseColorPreview.groups(from: courses)
    }

    private func selectCourseColorMode(_ raw: Int) {
        let db = AppDatabase.getShared()
        AppearanceColorActions.selectMode(raw, primary: colors.primary, prefs: prefs,
                                         dao: db.courseColorDao,
                                         gids: ScheduleRepository(db).getAllGroupIds())
        courseColorless = prefs.isCourseColorless()
        courseColorMode = prefs.getCourseColorMode()
        if raw == AppPrefs.COURSE_COLOR_MODE_CUSTOM { hueSession.current = prefs.getCourseColorSeedHue() }
        Task { await refreshHueStore() }
        refreshWidgets()
    }

    private func commitCourseHue(_ hue: Float) {
        hueSession.current = hue
        prefs.setCourseColorSeedHue(hue)
        recalcAllCourses()
    }

    /// 全量重算课程配色(手动重排/提交种子调用) — 走 CourseColorWriteGlue.recalcAll。
    private func recalcAllCourses() {
        let db = AppDatabase.getShared()
        let repo = ScheduleRepository(db)
        let gids = repo.getAllGroupIds()
        Task {
            _ = await CourseColorWriteGlue.recalcAll(
                mode: prefs.getCourseColorMode(), dao: db.courseColorDao, gids: gids
            )
            await refreshHueStore()
            refreshWidgets()
        }
    }

    private func selectThemeKey(_ key: String) {
        guard key != currentKey else { return }
        prefs.setThemeKey(key)
        currentKey = key
        onThemeKeyChange()
        refreshThemeCourseColors()
        refreshWidgets()
    }

    private func refreshThemeCourseColors() {
        let db = AppDatabase.getShared()
        AppearanceColorActions.themeDidChange(prefs: prefs, dao: db.courseColorDao,
                                              gids: ScheduleRepository(db).getAllGroupIds())
        Task { await refreshHueStore() }
    }

    private func openEditor(_ theme: CustomTheme?) {
        editingTheme = theme
        showEditor = true
    }

    /// 编辑器保存 → 落库 + 重排网格;保存即应用(2026-09-21 用户反馈): 无条件把 theme_key
    /// 落到本次保存的主题 —— 此前 iOS 只在「改的正是当前主题」时才刷新, 新建主题保存后
    /// 从不生效, 正是 原版本 明确修掉的「保存了但从没被应用过」行为。
    private func saveTheme(_ saved: CustomTheme) {
        CustomThemeStore.save(saved)
        let savedKey = ThemePresets.CUSTOM_KEY_PREFIX + saved.id
        prefs.setThemeKey(savedKey)
        currentKey = savedKey
        customThemes = CustomThemeStore.getAll()
        onThemeKeyChange()
        refreshThemeCourseColors()
        refreshWidgets()
        showEditor = false
        editingTheme = nil
    }

    /// 编辑器删除 → 落库;删的正是当前应用主题则写回 default(与 unknown-key 回落语义一致)
    private func deleteTheme(_ id: String) {
        CustomThemeStore.delete(id)
        customThemes = CustomThemeStore.getAll()
        showEditor = false
        editingTheme = nil
        if currentKey == ThemePresets.CUSTOM_KEY_PREFIX + id {
            selectThemeKey(ThemePresets.KEY_DEFAULT)
        }
    }
}

// ← ThemeGridCell(预设卡 / 自定义卡 / 新建卡 混排单元)
enum ThemeGridCell: Identifiable {
    case preset(ThemePreset)
    case custom(CustomTheme)
    case newTheme

    var id: String {
        switch self {
        case .preset(let p): return "preset:" + p.key
        case .custom(let t): return "custom:" + t.id
        case .newTheme: return "new-theme"
        }
    }
}

/// 网格单元分发 — 三种卡都撑满半宽,保证同尺寸
private struct ThemeGridCellView: View {
    let cell: ThemeGridCell
    let currentKey: String
    let onSelect: (String) -> Void
    let onEdit: (CustomTheme?) -> Void

    var body: some View {
        switch cell {
        case .preset(let preset):
            PresetThemeCard(preset: preset, selected: currentKey == preset.key) {
                onSelect(preset.key)
            }
        case .custom(let theme):
            CustomThemeCard(theme: theme, selected: currentKey == ThemePresets.CUSTOM_KEY_PREFIX + theme.id) {
                onSelect(ThemePresets.CUSTOM_KEY_PREFIX + theme.id)
            } onEdit: {
                onEdit(theme)
            }
        case .newTheme:
            NewThemeEntry { onEdit(nil) }
        }
    }
}

// ← SystemThemeCard
private struct SystemThemeCard: View {
    @Environment(\.localWakeUpColors) private var colors
    @Environment(\.systemColorSnapshot) private var systemSnapshot
    let selected: Bool
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            HStack(spacing: 16) {
                AndroidSettingsIcon(name: .autoAwesome, size: 28)
                    .foregroundColor(colors.onPrimaryContainer)
                    .frame(width: 56, height: 56)
                    .background(colors.primaryContainer)
                    .cornerRadius(SleepyShapes.large)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.format("theme_system"))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(colors.onSurface)
                    Text(systemSourceDescription)
                        .font(.system(size: 12))
                        .foregroundColor(colors.onSurfaceVariant)
                        .accessibilityIdentifier("system_color_source")
                }
                Spacer()
                if selected {
                    AndroidMaterialIcon(name: .check, size: 24)
                        .foregroundColor(colors.primary)
                        .accessibilityLabel(L10n.format("selected"))
                        .accessibilityHidden(false)
                }
            }
            .padding(16)
            .background(selected ? colors.primaryContainer : colors.surfaceContainer)
            .cornerRadius(SleepyShapes.large)
        }
        .buttonStyle(SleepyButtonStyle())
        .accessibilityIdentifier("theme_system_card")
    }

    private var systemSourceDescription: String {
        let value = systemSnapshot ?? .fallback(.noWindow)
        let available = value.isValid && value.source == .windowTint
        let key = available ? "theme_system_source_window_tint" : "theme_system_source_fallback"
        let translated = L10n.t(key)
        // 全局 strings 由主会话接入；未到货时也不能显示旧“壁纸取色”说明或原始 key。
        if translated != key { return translated }
        return available ? "配色来源：当前窗口强调色（非主屏幕或壁纸颜色）"
            : "未取得有效窗口颜色，使用默认配色；深浅外观按外观设置跟随"
    }
}

// ← PresetThemeCard
private struct PresetThemeCard: View {
    @Environment(\.localWakeUpColors) private var colors
    let preset: ThemePreset
    let selected: Bool
    let onClick: () -> Void

    var body: some View {
        // ← 原版本: if (colors.background.red < 0.5f) preset.light else preset.dark
        //   探针是红通道(非亮度), 且分支方向: 深色底展示 light 预览板
        let scheme = isDarkBackgroundByRedChannel(colors.background) ? preset.light : preset.dark
        Button(action: onClick) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    ColorSwatch(color: scheme.primary)
                    ColorSwatch(color: scheme.secondary)
                    ColorSwatch(color: scheme.tertiary)
                }
                HStack(spacing: 0) {
                    Text(L10n.format(preset.nameKey))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colors.onSurface)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    // ✓槽位恒定 20pt 占位,图标仅在选中时渲染进槽位 —— 禁改回 raw
                    // `if selected { Image }`(2026-09-22 用户实测: 条件渲染
                    // =选中那刻凭空多一个决定行高的孩子=选中卡比未选中卡高)。
                    // 不用 opacity(0) 隐藏: 读屏会照常播报"已选中", 占位槽才是布局+a11y 双正确。
                    CheckmarkSlot(selected: selected)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? colors.primaryContainer : colors.surfaceContainer)
            .cornerRadius(SleepyShapes.large)
        }
        .buttonStyle(SleepyButtonStyle())
        .accessibilityIdentifier("theme_preset_\(preset.key)")
    }
}

/// 固定 20×20 对勾槽位(Box(Modifier.size(20.dp)) + 条件 Icon)
private struct CheckmarkSlot: View {
    @Environment(\.localWakeUpColors) private var colors
    let selected: Bool

    var body: some View {
        ZStack {
            Color.clear.frame(width: 20, height: 20)
            if selected {
                AndroidMaterialIcon(name: .check, size: 20)
                    .foregroundColor(colors.primary)
                    .accessibilityLabel(L10n.format("selected"))
                    .accessibilityHidden(false)
            }
        }
        .frame(width: 20, height: 20)
    }
}

/// ← 原 `colors.background.red < 0.5f` 语义探针: 取 SwiftUI Color 的红通道分量。
/// 注意与 CourseColorUtil.luminance(BT.601 加权亮度)不同 —— 红通道值与整体亮度
/// 可在偏暗绿/蓝主题上给出相反判定, 1.0.61 原版本 定稿是红通道, iOS 必须同语义。
private func isDarkBackgroundByRedChannel(_ color: Color) -> Bool {
    let ui = UIColor(color)
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    ui.getRed(&r, green: &g, blue: &b, alpha: &a)
    return r < 0.5
}

// ← ColorSwatch
private struct ColorSwatch: View {
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: SleepyShapes.small)
            .fill(color)
            .frame(width: 28, height: 28)
    }
}

/// 自定义主题卡 — 与 PresetThemeCard 完全同构(三色板 + 名称 + 选中对勾,大小一模一样)。
/// edit 图标在色板行右端:色块包裹(可点性可见)+ 与 3 色块同行,不撑高卡片。
private struct CustomThemeCard: View {
    @Environment(\.localWakeUpColors) private var colors
    @Environment(\.sleepyUIStyle) private var uiStyle
    let theme: CustomTheme
    let selected: Bool
    let onClick: () -> Void
    let onEdit: () -> Void

    var body: some View {
        // 卡片色板预览按当前深浅模式派生(与 PresetThemeCard 的探针逻辑一致:
        // ← 原 `colors.background.red < 0.5f` 红通道语义)
        let isDark = isDarkBackgroundByRedChannel(colors.background)
        let scheme = CustomSchemeDeriver.derive(theme: theme, isDark: isDark)
        Button(action: onClick) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    ColorSwatch(color: scheme.primary)
                    ColorSwatch(color: scheme.secondary)
                    ColorSwatch(color: scheme.tertiary)
                    Spacer(minLength: 0)
                    Button(action: onEdit) {
                        AndroidSettingsIcon(name: .edit, size: 18)
                            .foregroundColor(colors.onSurfaceVariant)
                            .frame(width: uiStyle == .liquidGlass ? nil : 36,
                                   height: uiStyle == .liquidGlass ? nil : 36)
                            .background(uiStyle == .liquidGlass ? Color.clear : colors.surfaceContainerHighest,
                                        in: Circle())
                            .frame(width: uiStyle == .liquidGlass ? nil : 48,
                                   height: uiStyle == .liquidGlass ? nil : 48)
                    }
                    .buttonStyle(SleepyPlatformButtonStyle(compact: true, shape: .circle))
                    .frame(width: 48, height: 48)
                    .accessibilityIdentifier("theme_custom_edit_\(theme.id)")
                    .accessibilityLabel(L10n.format("theme_custom_edit"))
                }
                HStack(spacing: 0) {
                    Text(theme.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? L10n.format("theme_new") : theme.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colors.onSurface)
                        .lineLimit(1)
                        // ← 原版本 Text(modifier = Modifier.weight(1f))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    // 与预设卡相同:固定 20pt 槽位,避免选中态改变标题行高度。
                    CheckmarkSlot(selected: selected)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? colors.primaryContainer : colors.surfaceContainer)
            .cornerRadius(SleepyShapes.large)
        }
        .buttonStyle(SleepyButtonStyle())
        .accessibilityIdentifier("theme_custom_\(theme.id)")
    }
}

/// 「新建主题」入口 — 裸虚线圆圈 + 加号,无卡片无背景无文字(2026-09-11 用户定稿)
private struct NewThemeEntry: View {
    @Environment(\.localWakeUpColors) private var colors
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            DashedCircleWithPlus(size: 40)
                .frame(maxWidth: .infinity)
                .frame(height: 96)
                .contentShape(Rectangle())
        }
        .buttonStyle(SleepyButtonStyle())
        .accessibilityIdentifier("theme_new_entry")
        .accessibilityLabel(L10n.format("theme_new"))
    }
}

/// 虚线圆圈 + 中心加号 — onSurface 描边自动适配深浅
private struct DashedCircleWithPlus: View {
    @Environment(\.localWakeUpColors) private var colors
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    colors.onSurface,
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])
                )
            AndroidMaterialIcon(name: .add, size: size / 2)
                .foregroundColor(colors.onSurface)
        }
        .frame(width: size, height: size)
    }
}
