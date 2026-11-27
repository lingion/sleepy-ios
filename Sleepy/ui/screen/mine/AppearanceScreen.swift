// Appearance groups palette, interface material, navigation shape and course colors.
import SwiftUI
import UIKit
import WidgetKit
import Combine

struct AppearanceScreen: View {
    @Environment(\.localWakeUpColors) private var colors
    @Environment(\.sizeCategory) private var sizeCategory
    let onDismiss: () -> Void
    var themeMode: String = AppPrefs.THEME_MODE_SYSTEM
    var onThemeModeChange: (String) -> Void = { _ in }
    // ← 原版本 themeKeyFlow.collectAsState: 选色即时生效,经 AppRoot 回写 themeKey
    var onThemeKeyChange: () -> Void = {}
    // ← 原版本 onOpenPeriodHeaderSettings(Section④ 节次表头入口, 默认 no-op 保持 API 兼容,
    //   接线 .periodHeaderSettings 路由归共享文件 SleepyApp/SleepyNavigator, 见 needs_shared_wiring)
    var onOpenPeriodHeaderSettings: () -> Void = {}
    @State private var uiStyle = AppPrefs.shared.getUiStyle()
    @State private var navStyleIndex = NavStyleResolver.isFloatingRequested() ? 1 : 0

    @State private var currentKey: String
    // 自定义主题列表(编辑器保存/删除后重载)← 原版本 customListVersion
    @State private var customThemes: [CustomTheme] = CustomThemeStore.getAll()
    @SleepyNavigationState private var showEditor = false
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
         onOpenPeriodHeaderSettings: @escaping () -> Void = {}) {
        self.onDismiss = onDismiss
        self.themeMode = themeMode
        self.onThemeModeChange = onThemeModeChange
        self.onThemeKeyChange = onThemeKeyChange
        self.onOpenPeriodHeaderSettings = onOpenPeriodHeaderSettings
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

    private var selectedKey: String {
        if currentKey == ThemePresets.KEY_SYSTEM || customThemes.contains(where: {
            ThemePresets.CUSTOM_KEY_PREFIX + $0.id == currentKey
        }) {
            return currentKey
        }
        return ThemePresets.byKey(currentKey).key
    }

    private var themePicker: some View {
        let columns = sizeCategory.isAccessibilityCategory ? 1 : 2
        let cells = Self.gridCells(presets: ThemePresets.all, customs: customThemes)
        let selection = selectedKey
        let isDarkBg = isDarkBackgroundByRedChannel(colors.background)
        return SettingsSection(title: L10n.format("appearance_section_theme")) {
            SystemThemeCard(selected: selection == ThemePresets.KEY_SYSTEM) {
                selectThemeKey(ThemePresets.KEY_SYSTEM)
            }
            VStack(spacing: 12) {
                ForEach(Array(cells.chunked(into: columns).enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 12) {
                        ForEach(row) { cell in
                            ThemeGridCellView(cell: cell, currentKey: selection,
                                              isDarkBackground: isDarkBg,
                                              onSelect: selectThemeKey, onEdit: openEditor)
                        }
                        if row.count < columns {
                            Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
        }
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
                    themePicker
                    SettingsSection(title: L10n.format("settings_appearance_navigation")) {
                    SettingsFlatCard(title: L10n.format("settings_nav_style"),
                                     options: [L10n.format("settings_nav_style_docked"),
                                               L10n.format("settings_nav_style_floating")],
                                     selectedIndex: Binding(get: { navStyleIndex }, set: {
                                         navStyleIndex = $0; prefs.setNavDocked($0 == 1)
                                     }))
                        .accessibilityIdentifier("appearance_navigation_shape")
                    }
                    if SleepyUIStyle.supportsLiquidGlass {
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
                }
                .padding(16)
            }
        }
        .background(colors.background)
        .onReceive(prefs.themeKeyPublisher.receive(on: DispatchQueue.main)) { _ in
            let stored = prefs.getThemeKey()
            guard currentKey != stored else { return }
            currentKey = stored
            onThemeKeyChange()
        }
        .onReceive(prefs.uiStylePublisher) { uiStyle = $0 }
        .sleepyNavigationPage(isPresented: $showEditor, changes: _showEditor.changes,
                             onDismiss: { editingTheme = nil }, canvas: {
            colors.background.ignoresSafeArea()
        }) {
            CustomThemeEditorScreen(
                editing: editingTheme,
                nextThemeNumber: customThemes.count + 1,
                onBack: { showEditor = false },
                onSaved: saveTheme,
                onDeleted: deleteTheme
            )
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
        Task.detached(priority: .userInitiated) {
            let courses = (try? AppDatabase.getShared().courseDao.getAllCourses()) ?? []
            let groups = CourseColorPreview.groups(from: courses)
            await MainActor.run {
                previewGroups = groups
            }
        }
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
        applyThemeKey(key, refreshOnReselect: false)
    }

    private func applyThemeKey(_ key: String, refreshOnReselect: Bool) {
        guard key != prefs.getThemeKey() || refreshOnReselect else { return }
        currentKey = key
        prefs.setThemeKey(key)
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
        customThemes = CustomThemeStore.getAll()
        applyThemeKey(ThemePresets.CUSTOM_KEY_PREFIX + saved.id, refreshOnReselect: true)
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
    let isDarkBackground: Bool
    let onSelect: (String) -> Void
    let onEdit: (CustomTheme?) -> Void

    var body: some View {
        switch cell {
        case .preset(let preset):
            PresetThemeCard(preset: preset, selected: currentKey == preset.key,
                            isDarkBackground: isDarkBackground) {
                onSelect(preset.key)
            }
        case .custom(let theme):
            CustomThemeCard(theme: theme, selected: currentKey == ThemePresets.CUSTOM_KEY_PREFIX + theme.id,
                            isDarkBackground: isDarkBackground) {
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
                        .font(.body.weight(.medium))
                        .foregroundColor(colors.onSurface)
                    Text(systemSourceDescription)
                        .font(.caption)
                        .foregroundColor(colors.onSurfaceVariant)
                        .accessibilityIdentifier("system_color_source")
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer()
                CheckmarkSlot(selected: selected, size: 24)
            }
            .padding(16)
            .background(selected ? colors.primaryContainer : colors.surfaceContainer)
            .cornerRadius(SleepyShapes.large)
        }
        .buttonStyle(SleepyButtonStyle())
        .accessibilityLabel(L10n.format("theme_system"))
        .accessibilityValue(systemSourceDescription)
        .accessibilityAddTraits(selected ? .isSelected : [])
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
    let preset: ThemePreset
    let selected: Bool
    let isDarkBackground: Bool
    let onClick: () -> Void

    var body: some View {
        // ← 原版本: if (colors.background.red < 0.5f) preset.light else preset.dark
        //   探针是红通道(非亮度), 且分支方向: 深色底展示 light 预览板
        let scheme = isDarkBackground ? preset.light : preset.dark
        let name = L10n.format(preset.nameKey)
        Button(action: onClick) {
            ThemePaletteCardLabel(name: name, scheme: scheme, selected: selected)
        }
        .buttonStyle(SleepyButtonStyle())
        .accessibilityLabel(Text(name))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("theme_preset_\(preset.key)")
    }
}

/// 固定 20×20 对勾槽位(Box(Modifier.size(20.dp)) + 条件 Icon)
private struct CheckmarkSlot: View {
    @Environment(\.localWakeUpColors) private var colors
    let selected: Bool
    var size: CGFloat = 20

    var body: some View {
        ZStack {
            if selected {
                AndroidMaterialIcon(name: .check, size: size)
                    .foregroundColor(colors.primary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
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

private struct ThemePaletteCardLabel: View {
    @Environment(\.localWakeUpColors) private var colors
    let name: String
    let scheme: WakeUpColorScheme
    let selected: Bool
    var reservesEditSlot = false

    static let inset: CGFloat = 16
    static let actionSize: CGFloat = 48

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 4) {
                ForEach(Array([scheme.primary, scheme.secondary, scheme.tertiary].enumerated()), id: \.offset) { _, color in
                    RoundedRectangle(cornerRadius: SleepyShapes.small)
                        .fill(color)
                        .frame(minWidth: 0, maxWidth: 28)
                        .frame(height: 28)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, reservesEditSlot ? Self.actionSize + 8 : 0)
            .frame(height: Self.actionSize)
            .accessibilityHidden(true)

            HStack(spacing: 4) {
                Text(name)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(colors.onSurface)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                CheckmarkSlot(selected: selected)
            }
        }
        .padding(Self.inset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? colors.primaryContainer : colors.surfaceContainer)
        .cornerRadius(SleepyShapes.large)
    }
}

private struct CustomThemeCard: View {
    @Environment(\.localWakeUpColors) private var colors
    @Environment(\.sleepyUIStyle) private var uiStyle
    let theme: CustomTheme
    let selected: Bool
    let isDarkBackground: Bool
    let onClick: () -> Void
    let onEdit: () -> Void

    var body: some View {
        let scheme = CustomSchemeDeriver.derive(theme: theme, isDark: isDarkBackground)
        let name = theme.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? L10n.format("theme_new") : theme.name
        // Keep the two actions as sibling buttons: tapping the selection surface and editing have separate targets.
        ZStack(alignment: .topTrailing) {
            Button(action: onClick) {
                ThemePaletteCardLabel(name: name, scheme: scheme, selected: selected, reservesEditSlot: true)
            }
            .buttonStyle(SleepyButtonStyle())
            .accessibilityIdentifier("theme_custom_\(theme.id)")
            .accessibilityLabel(Text(name))
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityActivationPoint(UnitPoint(x: 0.25, y: 0.75))

            Button(action: onEdit) {
                AndroidSettingsIcon(name: .edit, size: 18)
                    .foregroundColor(colors.onSurfaceVariant)
                    .frame(width: uiStyle == .liquidGlass ? nil : 36,
                           height: uiStyle == .liquidGlass ? nil : 36)
                    .background(uiStyle == .liquidGlass ? Color.clear : colors.surfaceContainerHighest, in: Circle())
                    .frame(width: ThemePaletteCardLabel.actionSize, height: ThemePaletteCardLabel.actionSize)
                    .contentShape(Rectangle())
            }
            .sleepyPlatformButtonStyle(compact: true, shape: .circle)
            .accessibilityIdentifier("theme_custom_edit_\(theme.id)")
            .accessibilityLabel(L10n.format("theme_custom_edit"))
            .accessibilityHint(Text(name))
            .padding(ThemePaletteCardLabel.inset)
        }
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
        .sleepyAccessibleShapeAnchor()
    }
}
