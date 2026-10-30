// AppearanceScreen.swift — ← ui/screen/mine/AppearanceScreen.kt
// 外观页(决策 D2 合并页): 仅主题色彩组(SystemThemeCard + 2列预设网格 + 深浅色三态)
// + Section③ 课表显示(内嵌 ScheduleDisplayContent) + Section④ 节次表头入口(2026-10 对齐补全)。
// 选主题/模式后立即刷小组件(refreshWidgets 管线保留)。

import SwiftUI
import UIKit
import WidgetKit
import Combine

struct AppearanceScreen: View {
    @Environment(\.localWakeUpColors) private var colors
    let onDismiss: () -> Void
    var themeMode: String = AppPrefs.THEME_MODE_SYSTEM
    var onThemeModeChange: (String) -> Void = { _ in }
    // ← Android themeKeyFlow.collectAsState: 选色即时生效,经 AppRoot 回写 themeKey
    var onThemeKeyChange: () -> Void = {}
    // ← Android onOpenPeriodHeaderSettings(Section④ 节次表头入口, 默认 no-op 保持 API 兼容,
    //   接线 .periodHeaderSettings 路由归共享文件 SleepyApp/SleepyNavigator, 见 needs_shared_wiring)
    var onOpenPeriodHeaderSettings: () -> Void = {}

    @State private var currentKey: String
    // 自定义主题列表(编辑器保存/删除后重载)← Android customListVersion
    @State private var customThemes: [CustomTheme] = CustomThemeStore.getAll()
    @State private var showEditor = false
    @State private var editingTheme: CustomTheme?
    private let prefs = AppPrefs.shared

    // ── v1.0.62 Section②·5 课程配色(← Android CourseColorSection) ──
    // ★ 初始值必须从 prefs getter 取, 不能读 publisher.value: AppPrefs 的
    //   CurrentValueSubject 用硬编码缺省播种(不读持久值), 与 Android
    //   callbackFlow「订阅即 trySend 当前持久值」语义不等价。
    @State private var courseColorMode: Int
    @State private var courseColorSeed: Float
    /// 滑条本地值(拖动中; 未提交) — Android sliderHue remember
    @State private var sliderHue: Float
    /// 预览胶囊数据源: gid → 课名(前 5 组)
    @State private var previewCourseGroups: [(gid: String, name: String)] = []
    @State private var toastMessage: String?
    @State private var toastToken: Int = 0
    /// 持久色相快照订阅(Android CourseHueStore.hueMapFlow.collectAsState)
    @ObservedObject private var hueStore = CourseHueStore.shared

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
        let mode = AppPrefs.shared.getCourseColorMode()
        let seed = AppPrefs.shared.getCourseColorSeedHue()
        _courseColorMode = State(initialValue: mode)
        _courseColorSeed = State(initialValue: seed)
        // Android: sliderHue by remember { mutableFloatStateOf(seed.coerceAtLeast(0f)) }
        _sliderHue = State(initialValue: max(seed, 0))
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
                VStack(spacing: 12) {
                    // ── 分组① 主题色彩 ──
                    SectionHeader(title: L10n.format("appearance_section_theme"))

                    SystemThemeCard(selected: currentKey == ThemePresets.KEY_SYSTEM) {
                        prefs.setThemeKey(ThemePresets.KEY_SYSTEM)
                        currentKey = ThemePresets.KEY_SYSTEM
                        onThemeKeyChange()
                        refreshWidgets()
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
                                // (与 Android Box(Modifier.weight(1f)) 等价)
                                if row.count == 1 {
                                    Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
                                }
                            }
                        }
                    }

                    // ── 分组② 外观深浅 ──
                    // ← Android: SectionHeader(theme_appearance) 独立 item +
                    //   外层 clip(shapes.large)+surfaceContainer+padding(4)+spacedBy(4),
                    //   未选中段 background=surfaceContainerHigh(与容器拉开层级)
                    SectionHeader(title: L10n.format("theme_appearance"))
                    let modes: [(String, String)] = [
                        (AppPrefs.THEME_MODE_SYSTEM, L10n.format("theme_mode_system")),
                        (AppPrefs.THEME_MODE_LIGHT, L10n.format("theme_mode_light")),
                        (AppPrefs.THEME_MODE_DARK, L10n.format("theme_mode_dark"))
                    ]
                    HStack(spacing: 4) {
                        ForEach(modes, id: \.0) { mode, label in
                            let sel = mode == themeMode
                            Button {
                                guard mode != themeMode else { return }
                                prefs.setThemeMode(mode)
                                onThemeModeChange(mode)
                                refreshWidgets()
                                // ← Android: 深浅切换后 FOLLOW_THEME 档需重算
                                //   (锚点随主题 primary 变)
                                if courseColorMode == AppPrefs.COURSE_COLOR_MODE_FOLLOW_THEME {
                                    recalcAllCourses()
                                }
                            } label: {
                                Text(label)
                                    .font(.system(size: 14, weight: sel ? .semibold : .medium))
                                    .foregroundColor(sel ? colors.onPrimary : colors.onSurfaceVariant)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(sel ? colors.primary : colors.surfaceContainerHigh)
                                    .cornerRadius(SleepyShapes.medium)
                            }
                            .buttonStyle(SleepyButtonStyle())
                            .accessibilityIdentifier("theme_mode_\(mode)")
                        }
                    }
                    .padding(4)
                    .background(colors.surfaceContainer)
                    .cornerRadius(SleepyShapes.large)

                    // ── 分组②·5 课程配色(v1.0.62) ──
                    // ← Android SectionHeader(appearance_section_course_color) +
                    //   CourseColorSection(Surface shapes.large surfaceContainer, padding 16)
                    SectionHeader(title: L10n.format("appearance_section_course_color"))
                    CourseColorSection(
                        mode: courseColorMode,
                        seed: courseColorSeed,
                        sliderHue: sliderHue,
                        hueMap: hueStore.hueMap,
                        previewGroups: previewCourseGroups,
                        onModeChange: onCourseColorModeChange,
                        onSliderChange: { sliderHue = $0 },
                        onSeedCommit: onCourseColorSeedCommit,
                        onRecalc: onCourseColorRecalc
                    )

                    // ── 分组③ 课表显示: 冲突样式及参数仍属于本组 ──
                    // ← Android SectionHeader(appearance_section_schedule_display) +
                    //   Surface(shapes.large, surfaceContainer) 内嵌 ScheduleDisplayContent(padding 16)
                    SectionHeader(title: L10n.format("appearance_section_schedule_display"))
                    ScheduleDisplayContent()
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(colors.surfaceContainer)
                        .cornerRadius(SleepyShapes.large)

                    // ── 分组④ 节次表头 ──
                    // ← Android SectionHeader(appearance_period_header) +
                    //   AppearanceNavigationRow(onClick = onOpenPeriodHeaderSettings)
                    SectionHeader(title: L10n.format("appearance_period_header"))
                    AppearanceNavigationRow(
                        title: L10n.format("appearance_period_header"),
                        onClick: onOpenPeriodHeaderSettings
                    )
                }
                .padding(16)
            }
        }
        .background(colors.background)
        // 自定义主题编辑器 ← Android 全屏 overlay;iOS 用 sheet 承载,
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
        // ← Android Toast(course_color_recalc_done) — 重排完成提示
        .overlay(alignment: .bottom) {
            if let toastMessage {
                Text(toastMessage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(colors.onSurface)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(colors.surfaceContainerHigh)
                    .cornerRadius(SleepyShapes.large)
                    .padding(.bottom, 24)
                    .transition(.opacity)
                    .task(id: toastToken) {
                        try? await Task.sleep(nanoseconds: 1_800_000_000)
                        guard !Task.isCancelled else { return }
                        withAnimation { self.toastMessage = nil }
                    }
            }
        }
        // 预览胶囊数据源 ← Android LaunchedEffect(Unit) 读默认表课程
        .task { loadPreviewCourseGroups() }
    }

    // MARK: - v1.0.62 课程配色

    /// 预览胶囊: 默认表课程(无默认表 → 全表), 按 id 升序, groupId 非空去重, 取前 5 组。
    /// ← Android AppearanceScreen.kt LaunchedEffect(Unit) previewCourseGroups。
    private func loadPreviewCourseGroups() {
        let db = AppDatabase.getShared()
        let repo = ScheduleRepository(db)
        let courses: [CourseEntity]
        if let tid = try? repo.getDefaultTable()?.id {
            courses = (try? repo.getCourses(tid)) ?? []
        } else {
            courses = (try? repo.getAllCourses()) ?? []
        }
        var seen = Set<String>()
        var out: [(gid: String, name: String)] = []
        for c in courses.sorted(by: { $0.id < $1.id }) {
            guard CourseColorUtil.isNotBlank(c.groupId), seen.insert(c.groupId).inserted else { continue }
            out.append((gid: c.groupId, name: c.courseName))
            if out.count >= 5 { break }
        }
        previewCourseGroups = out
    }

    /// 换档 → 落盘 + 重排 + 刷小组件。
    /// ← Android onModeChange: CUSTOM 且种子未设 → 先按主题 primary 落种子,
    ///   再 setCourseColorMode, 然后 recalcAllCourses + refreshWidgets。
    private func onCourseColorModeChange(_ newMode: Int) {
        guard newMode != courseColorMode else { return }
        if newMode == AppPrefs.COURSE_COLOR_MODE_CUSTOM,
           prefs.getCourseColorSeedHue() == AppPrefs.COURSE_COLOR_SEED_UNSET {
            let seedHue = CourseColorUtil.hueOf(colors.primary)
            prefs.setCourseColorSeedHue(seedHue)
            courseColorSeed = seedHue
            sliderHue = seedHue
        }
        prefs.setCourseColorMode(newMode)
        courseColorMode = newMode
        recalcAllCourses()
        refreshWidgets()
    }

    /// 种子色相提交(滑条松手) → 落盘 + 重排 + 刷小组件。
    /// ← Android onSeedCommit。
    private func onCourseColorSeedCommit(_ hue: Float) {
        let v = hue.rounded()
        prefs.setCourseColorSeedHue(v)
        courseColorSeed = v
        sliderHue = v
        recalcAllCourses()
        refreshWidgets()
    }

    /// 手动重排全部课程颜色 → 全量重算 + Toast 报组数 + 刷小组件。
    /// ← Android onRecalc: 后台 recalcAll → 主线程 Toast「已重排 N 组」。
    private func onCourseColorRecalc() {
        let db = AppDatabase.getShared()
        let repo = ScheduleRepository(db)
        let gids: [String] = {
            let all = (try? repo.getAllCourses()) ?? []
            return all.sorted(by: { $0.id < $1.id }).map { $0.groupId }
        }()
        DispatchQueue.global(qos: .userInitiated).async {
            let n = CourseColorWriteGlue.recalcAll(dao: db.courseColorDao, gids: gids, prefs: AppPrefs.shared)
            DispatchQueue.main.async {
                self.showToast(L10n.format("course_color_recalc_done", n))
                self.refreshWidgets()
            }
        }
    }

    /// 全量重算(后台) — FOLLOW_THEME / CUSTOM 档锚点变化时重排全部组。
    /// ← Android recalcAllCourses(): gids 来自全库课程, 调 CourseColorWriteGlue.recalcAll。
    private func recalcAllCourses() {
        let db = AppDatabase.getShared()
        let repo = ScheduleRepository(db)
        let gids: [String] = {
            let all = (try? repo.getAllCourses()) ?? []
            return all.sorted(by: { $0.id < $1.id }).map { $0.groupId }
        }()
        DispatchQueue.global(qos: .userInitiated).async {
            CourseColorWriteGlue.recalcAll(dao: db.courseColorDao, gids: gids, prefs: AppPrefs.shared)
        }
    }

    private func showToast(_ message: String) {
        toastMessage = message
        toastToken += 1
    }

    // ★ 选主题/模式后立即刷小组件(← WidgetUpdater.notifyDataChanged)
    private func refreshWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func selectThemeKey(_ key: String) {
        prefs.setThemeKey(key)
        currentKey = key
        onThemeKeyChange()
        refreshWidgets()
        // ← Android LaunchedEffect(currentKey): 主题键变化后 FOLLOW_THEME 档需重排
        if courseColorMode == AppPrefs.COURSE_COLOR_MODE_FOLLOW_THEME {
            recalcAllCourses()
        }
    }

    private func openEditor(_ theme: CustomTheme?) {
        editingTheme = theme
        showEditor = true
    }

    /// 编辑器保存 → 落库 + 重排网格;保存即应用(2026-09-21 用户反馈): 无条件把 theme_key
    /// 落到本次保存的主题 —— 此前 iOS 只在「改的正是当前主题」时才刷新, 新建主题保存后
    /// 从不生效, 正是 Android 明确修掉的「保存了但从没被应用过」行为。
    private func saveTheme(_ saved: CustomTheme) {
        CustomThemeStore.save(saved)
        let savedKey = ThemePresets.CUSTOM_KEY_PREFIX + saved.id
        prefs.setThemeKey(savedKey)
        currentKey = savedKey
        customThemes = CustomThemeStore.getAll()
        onThemeKeyChange()
        refreshWidgets()
        if courseColorMode == AppPrefs.COURSE_COLOR_MODE_FOLLOW_THEME {
            recalcAllCourses()
        }
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
    let selected: Bool
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            HStack(spacing: 16) {
                Image(systemName: "sparkles")
                    .font(.system(size: 28))
                    .foregroundColor(colors.onPrimaryContainer)
                    .frame(width: 56, height: 56)
                    .background(colors.primaryContainer)
                    .cornerRadius(SleepyShapes.large)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.format("theme_system"))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(colors.onSurface)
                    Text(L10n.format("theme_system_desc"))
                        .font(.system(size: 12))
                        .foregroundColor(colors.onSurfaceVariant)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 24))
                        .foregroundColor(colors.primary)
                }
            }
            .padding(16)
            .background(selected ? colors.primaryContainer : colors.surfaceContainer)
            .cornerRadius(SleepyShapes.large)
        }
        .buttonStyle(SleepyButtonStyle())
        .accessibilityIdentifier("theme_system_card")
    }
}

// ← PresetThemeCard
private struct PresetThemeCard: View {
    @Environment(\.localWakeUpColors) private var colors
    let preset: ThemePreset
    let selected: Bool
    let onClick: () -> Void

    var body: some View {
        // ← Android: if (colors.background.red < 0.5f) preset.light else preset.dark
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
                    // `if selected { Image }`(← Android 2026-09-22 用户实测: 条件渲染
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

/// 固定 20×20 对勾槽位(← Android Box(Modifier.size(20.dp)) + 条件 Icon)
private struct CheckmarkSlot: View {
    @Environment(\.localWakeUpColors) private var colors
    let selected: Bool

    var body: some View {
        ZStack {
            Color.clear.frame(width: 20, height: 20)
            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 20))
                    .foregroundColor(colors.primary)
                    .accessibilityLabel(L10n.format("selected"))
            }
        }
        .frame(width: 20, height: 20)
    }
}

/// ← Android `colors.background.red < 0.5f` 语义探针: 取 SwiftUI Color 的红通道分量。
/// 注意与 CourseColorUtil.luminance(BT.601 加权亮度)不同 —— 红通道值与整体亮度
/// 可在偏暗绿/蓝主题上给出相反判定, 1.0.61 Android 定稿是红通道, iOS 必须同语义。
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
    let theme: CustomTheme
    let selected: Bool
    let onClick: () -> Void
    let onEdit: () -> Void

    var body: some View {
        // 卡片色板预览按当前深浅模式派生(与 PresetThemeCard 的探针逻辑一致:
        // ← Android `colors.background.red < 0.5f` 红通道语义)
        let isDark = isDarkBackgroundByRedChannel(colors.background)
        let scheme = CustomSchemeDeriver.derive(theme: theme, isDark: isDark)
        Button(action: onClick) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    ColorSwatch(color: scheme.primary)
                    ColorSwatch(color: scheme.secondary)
                    ColorSwatch(color: scheme.tertiary)
                    Spacer(minLength: 0)
                    // edit 色块:surfaceContainerHighest 与卡片底色拉开层级;
                    // ← Android 28dp(与色板同高, 内嵌 16dp Edit 图标), 首行结构与
                    // 预设卡严格同构不撑高(24 会差 4pt)
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.system(size: 16))
                            .foregroundColor(colors.onSurfaceVariant)
                            .frame(width: 28, height: 28)
                            .background(colors.surfaceContainerHighest)
                            .cornerRadius(SleepyShapes.small)
                    }
                    .buttonStyle(SleepyButtonStyle())
                    .accessibilityIdentifier("theme_custom_edit_\(theme.id)")
                    .accessibilityLabel(L10n.format("theme_custom_edit"))
                }
                HStack(spacing: 0) {
                    Text(theme.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? L10n.format("theme_new") : theme.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colors.onSurface)
                        .lineLimit(1)
                        // ← Android Text(modifier = Modifier.weight(1f))
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
            Image(systemName: "plus")
                .font(.system(size: size / 2))
                .foregroundColor(colors.onSurface)
        }
        .frame(width: size, height: size)
    }
}
