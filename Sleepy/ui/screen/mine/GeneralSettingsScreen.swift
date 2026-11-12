// General settings, schedule display and backup share their existing preference and migration actions.
import SwiftUI
import WidgetKit
import UniformTypeIdentifiers

@MainActor
struct GeneralSettingsScreen: View {
    enum Section { case general, display, backup }
    @Environment(\.localWakeUpColors) private var colors
    let onDismiss: () -> Void

    /// issue#44 调休映射接线 ← 原版本 SleepyNavHost.kt:299-303(`tableId = currentTableId,
    /// viewModel = mainVm`): 节假日子页需要「当前选中课表 id」与「映射变更后的课表页刷新回调」。
    /// 选中表 id 在 iOS 侧唯一真源 = ScheduleViewModel.state.selectedTableId(AppPrefs 不持久化),
    /// 故本屏须能读到 VM。可选(nil = 调用方尚未接线 → tableId 退化为 nil、refreshTransfer 不触发,
    /// 与本页现状行为一致且不崩);集成者需在 SleepyApp.swift `.general` overlay case 传入
    /// `viewModel: scheduleViewModel`(scheduleViewModel 已在 PresentOverlay 内, 见 SleepyApp.swift:545)。
    /// { viewModel?.refreshTransfer() } 的 Void? 闭包在 () -> Void 槽位写法同 JwWebViewLoginScreen:191 先例。
    var viewModel: ScheduleViewModel? = nil
    var section: Section = .general
    @State private var showPeriodHeaders = false

    private var pageTitle: String {
        switch section {
        case .general: return L10n.format("mine_general")
        case .display: return L10n.format("mine_schedule_settings")
        case .backup: return L10n.format("settings_backup")
        }
    }

    private let prefs = AppPrefs.shared

    @State private var expandedSections: Set<String> = SettingsExpandedSectionsStore.load()
    @State private var displayMode: String = AppPrefs.shared.getDisplayMode()
    @State private var gridSubInfo: String = AppPrefs.shared.getGridSubInfo()
    @State private var showDate: Bool = AppPrefs.shared.isShowDate()
    @State private var nearestBusyDay = AppPrefs.shared.isNearestBusyDay()
    @State private var showViewSwitcher: Bool = AppPrefs.shared.isShowViewSwitcher()
    /// 启动默认视图 — ← AppPrefs.getStartView 原版本 (默认 "full")。仅通用设置里设置,
    /// 手动切换课表顶部视图不写入(原版本 注释硬规则, iOS 一致遵循)。
    @State private var startView: String = AppPrefs.shared.getStartView()
    @State private var visibleDays: Set<Int> = AppPrefs.shared.getVisibleDays()
    // ★ issue#8 主页显示 pill 组(GeneralSettingsScreen)
    @State private var weekUseAlias: Bool = AppPrefs.shared.isWeekUseAlias()
    @State private var gridUseAlias: Bool = AppPrefs.shared.isGridUseAlias()
    @State private var weekTwoColumn: Bool = AppPrefs.shared.isWeekTwoColumn()
    @State private var weekTwoColumnMode: String = AppPrefs.shared.getWeekTwoColumnMode()
    @State private var weekHideEmptyDays: Bool = AppPrefs.shared.isWeekHideEmptyDays()
    // ★ v1.0.61 数据迁移组(GeneralSettingsScreen.kt 分组⑥)
    @State private var migrationBusy = false
    @State private var pendingImportBytes: Data? = nil
    @State private var showImportDialog = false
    @State private var showExportPicker = false
    @State private var showImportPicker = false
    @State private var exportURL: URL? = nil
    @State private var migrationToast: String? = nil
    @State private var holidaySettingsItem: HolidaySettingsItem? = nil
    private struct HolidaySettingsItem: Identifiable { let id = UUID() }

    private func toggleSection(_ key: String) {
        if expandedSections.contains(key) { expandedSections.remove(key) }
        else { expandedSections.insert(key) }
    }

    // ★ 显示项变更后立即刷小组件
    private func refreshWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    // ── 数据迁移(runMigrationImport / onMigrationExportClick / launchers) ──

    private func runMigrationImport(_ mode: MigrationExecutor.ImportMode) {
        guard let bytes = pendingImportBytes else { return }
        pendingImportBytes = nil
        migrationBusy = true
        Task.detached(priority: .userInitiated) {
            let db = AppDatabase.getShared()
            let store = RuntimeMigrationPrefsStore()
            do {
                let report = try MigrationExecutor.import(
                    bytes: bytes, mode: mode, prefsStore: store,
                    courseDao: db.courseDao, timeTableDao: db.timeTableDao,
                    periodTableDao: db.periodTableDao, importDraftDao: db.importDraftDao,
                    dbQueue: db.dbQueue
                )
                await MainActor.run {
                    migrationBusy = false
                    // ← 原版本 Toast settings_migration_import_done(课表数, 课程数)
                    migrationToast = L10n.format("settings_migration_import_done",
                                                 report.counts.timeTables, report.counts.courses)
                    // 偏好与小组件配置可能被替换, 迁移后统一刷新小组件
                    WidgetCenter.shared.reloadAllTimelines()
                    // 成就：导入备份
                    AchievementTracker.shared.checkImportBackup()
                }
            } catch {
                NSLog("SleepyMigration: import failed: %@", String(describing: error))
                await MainActor.run {
                    migrationBusy = false
                    migrationToast = L10n.format("settings_migration_import_fail")
                }
            }
        }
    }

    private func onMigrationExportClick() {
        guard !migrationBusy else { return }
        migrationBusy = true
        Task.detached(priority: .userInitiated) {
            let db = AppDatabase.getShared()
            let store = RuntimeMigrationPrefsStore()
            do {
                // ← 原 modules = {DATABASE, PREFERENCES, WIDGETS}(依赖闭包
                //   由 MigrationModuleDeps.resolve 自动补 PERSISTED_STATE, 两端同)
                let result = try MigrationExecutor.export(
                    selected: [.DATABASE, .PREFERENCES, .WIDGETS],
                    prefsStore: store,
                    courseDao: db.courseDao, timeTableDao: db.timeTableDao,
                    periodTableDao: db.periodTableDao, importDraftDao: db.importDraftDao,
                    dbQueue: db.dbQueue
                )
                // ← 原 stamp = SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US)
                let f = DateFormatter()
                f.dateFormat = "yyyyMMdd-HHmmss"
                f.locale = Locale(identifier: "en_US_POSIX")
                let fileName = "sleepy-backup-\(f.string(from: Date())).sleepybackup"
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent(fileName)
                try result.bytes.write(to: url)
                await MainActor.run {
                    // Keep the lock until the save panel finishes or is dismissed.
                    exportURL = url
                    showExportPicker = true
                }
            } catch {
                NSLog("SleepyMigration: collect failed: %@", String(describing: error))
                await MainActor.run {
                    migrationBusy = false
                    migrationToast = L10n.format("settings_migration_export_fail")
                }
            }
        }
    }

    private func onImportFileResult(_ result: Result<[URL], Error>) {
        // ← 原 uri == null 静默取消(OpenDocument 取消路径)
        guard case .success(let urls) = result, let url = urls.first else { return }
        migrationBusy = true
        Task.detached(priority: .userInitiated) {
            let secured = url.startAccessingSecurityScopedResource()
            defer { if secured { url.stopAccessingSecurityScopedResource() } }
            let bytes = try? Data(contentsOf: url)
            await MainActor.run {
                migrationBusy = false
                if let bytes {
                    // ← 原版本: 读成功 → 弹模式选择对话框
                    pendingImportBytes = bytes
                    showImportDialog = true
                } else {
                    migrationToast = L10n.format("settings_migration_import_fail")
                }
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            SettingsTopBar(title: pageTitle, onBack: onDismiss)
            ScrollView {
                VStack(spacing: SettingsLayout.cardGap) {
                    if section == .general {
                        LanguageSection()
                        SettingsSection(title: L10n.format("settings_performance")) {
                            InfoCard {
                                Text(L10n.format("settings_ios_refresh_policy"))
                                    .font(.system(size: 14))
                                    .foregroundColor(colors.onSurfaceVariant)
                            }
                        }
                        SettingsSection(title: L10n.format("settings_editing")) {
                            UndoDepthSettingsRow()
                                .padding(.horizontal, 16)
                                .background(colors.surfaceContainer)
                                .cornerRadius(SleepyShapes.large)
                        }
                    } else if section == .display {
                        displaySettings
                    } else {
                        MigrationSection(busy: migrationBusy,
                                         onExport: onMigrationExportClick,
                                         onImport: { if !migrationBusy { showImportPicker = true } })
                    }
                }
                .padding(16)
            }
        }
        .background(colors.background)
        // ← 原版本 rememberSaveable(expandedSections): AppRoot 状态恢复时折叠
        //   展开集保真。iOS 等价 = 变更即落 sleepy_prefs, 页面重建(load())回填。
        //   单一收口挂在父级 State 上。
        .onChange(of: expandedSections) { SettingsExpandedSectionsStore.save($0) }
        .navigationBarHidden(true)
        // ← 原版本 Toast(迁移结果) → 底部胶囊浮层(仓库同款, 1.8s 自动消失)
        .overlay(alignment: .bottom) {
            if let msg = migrationToast {
                Text(msg)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(colors.onSurface)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(colors.surfaceContainerHigh)
                    .cornerRadius(SleepyShapes.large)
                    .padding(.bottom, 24)
                    .transition(.opacity)
                    .task(id: msg) {
                        try? await Task.sleep(nanoseconds: 2_500_000_000)
                        guard !Task.isCancelled else { return }
                        withAnimation { migrationToast = nil }
                    }
                    .accessibilityIdentifier("settings_migration_toast")
            }
        }
        // ← 原版本 AlertDialog(导入模式选择): 标题/正文/覆盖·合并/取消
        .alert(L10n.format("settings_migration_import_dialog_title"),
               isPresented: $showImportDialog) {
            Button(L10n.format("settings_migration_import_overwrite")) {
                runMigrationImport(.OVERWRITE)
            }
            Button(L10n.format("settings_migration_import_merge")) {
                runMigrationImport(.MERGE)
            }
            Button(L10n.format("cancel"), role: .cancel) {
                pendingImportBytes = nil
            }
        } message: {
            Text(L10n.format("settings_migration_import_dialog_text"))
        }
        // ← 原版本 CreateDocument("application/zip") 保存对话框 → fileExporter。
        //   完成回调对齐 原版本 exportLauncher: 写成功 export_ok toast,
        //   失败 export_fail toast, 取消(uri==null)静默。
        .fileExporter(isPresented: $showExportPicker,
                      document: ExportedBackupFile(url: exportURL),
                      contentType: UTType.data,
                      defaultFilename: exportURL.map { $0.deletingPathExtension().lastPathComponent } ?? "sleepy-backup") { result in
            migrationBusy = false
            switch result {
            case .success:
                migrationToast = L10n.format("settings_migration_export_ok")
            case .failure(let error):
                // Reported cancellation errors are also silent.
                if error is CancellationError { return }
                NSLog("SleepyMigration: export failed: %@", String(describing: error))
                migrationToast = L10n.format("settings_migration_export_fail")
            }
        }
        .onChange(of: showExportPicker) { presented in
            // fileExporter dismisses on cancellation without invoking
            // its completion handler. Release the lock in both paths.
            if !presented { migrationBusy = false }
        }
        // ← 原版本 OpenDocument(["application/zip","application/octet-stream"])
        //   = UTType.zip + UTType.data(octet-stream); .sleepybackup 内容即 zip,
        //   动态 extension UTType 不进 allowedContentTypes(未声明类型有崩溃风险)
        .fileImporter(isPresented: $showImportPicker,
                      allowedContentTypes: [.zip, .data],
                      allowsMultipleSelection: false,
                      onCompletion: onImportFileResult)
        .sleepyNavigationPage(isPresented: $showPeriodHeaders, canvas: {
            colors.background.ignoresSafeArea()
        }) {
            PeriodHeaderSettingsScreen(onBack: { showPeriodHeaders = false })
        }
        .sleepyNavigationPage(item: $holidaySettingsItem, canvas: {
            colors.background.ignoresSafeArea()
        }) { _ in
            HolidaySettingsScreen(
                onDismiss: { holidaySettingsItem = nil },
                tableId: viewModel?.state.selectedTableId,
                refreshTransfer: { viewModel?.refreshTransfer() })
        }
    }

    private var displaySettings: some View {
        VStack(spacing: SettingsLayout.cardGap) {
            SettingsSection(title: L10n.format("settings_appearance_common"), first: true) {
                VStack(spacing: SettingsLayout.cardGap) {
                    startViewCard
                    commonDisplayToggles
                }
            }
            SettingsSection(title: L10n.format("settings_start_view_full")) {
                pillCard
            }
            SettingsSection(title: L10n.format("settings_start_view_cards")) {
                ScheduleDisplayGroup {
                    ScheduleDisplayContent(section: .grid)
                    gridSubInfoCard
                    gridAliasCard
                    Divider()
                    Text(L10n.format("settings_appearance_advanced_experimental"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colors.onSurface)
                    LabSection(refreshWidgets: refreshWidgets)
                }
            }
            AppearanceNavigationRow(title: L10n.format("appearance_period_header"),
                                    onClick: { showPeriodHeaders = true })
                .accessibilityIdentifier("settings_period_header")
            SettingsSection(title: L10n.format("settings_conflict_style")) {
                ScheduleDisplayGroup {
                    ScheduleDisplayContent(section: .conflict)
                }
            }
            SettingsSection(title: L10n.format("settings_appearance_holidays")) {
                HolidayDisplaySettings()
                holidayEntryCard
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("schedule_display_settings")
    }

    private var startViewCard: some View {
        SettingsFlatCard(title: L10n.format("settings_appearance_default_view"),
                         subtitle: L10n.format("settings_appearance_default_view_sub"),
                         options: [L10n.format("settings_start_view_full"), L10n.format("settings_start_view_cards")],
                         selectedIndex: Binding(get: { startView == "cards" ? 1 : 0 }, set: {
                             startView = $0 == 1 ? "cards" : "full"
                             prefs.setStartView(startView)
                         }))
    }

    private var commonDisplayToggles: some View {
        VStack(spacing: SettingsLayout.cardGap) {
            ScheduleDisplayGroup {
                SettingToggleRow(label: L10n.format("settings_show_view_switcher"), checked: showViewSwitcher) {
                    showViewSwitcher = $0; prefs.setShowViewSwitcher($0)
                }
            }
            visibleDaysCard
            ScheduleDisplayGroup {
                SettingToggleRow(label: L10n.format("settings_appearance_header_date"),
                                 subtitle: L10n.format("settings_appearance_header_date_sub"), checked: showDate) {
                    showDate = $0; prefs.setShowDate($0); refreshWidgets()
                }
            }
            displayModeCard
            ScheduleDisplayGroup {
                SettingToggleRow(label: L10n.format("settings_nearest_busy_day"),
                                 subtitle: L10n.format("settings_nearest_busy_day_sub"), checked: nearestBusyDay) {
                    nearestBusyDay = $0; prefs.setNearestBusyDay($0); refreshWidgets()
                }
            }
        }
    }

    private var gridAliasCard: some View {
        SettingToggleRow(label: L10n.format("settings_grid_alias"), checked: gridUseAlias) {
            gridUseAlias = $0; prefs.setGridUseAlias($0)
        }
    }

    // 课程时间显示: 节次 / 时间 — ← 原版本 SettingsFlatCard(标题行右侧 tab)
    private var displayModeCard: some View {
        SettingsFlatCard(
            title: L10n.format("settings_display_mode"),
            subtitle: L10n.format("settings_appearance_time_scope"),
            options: [
                L10n.format("settings_display_node"),
                L10n.format("settings_display_time")
            ],
            selectedIndex: Binding(
                get: { displayMode == "time" ? 1 : 0 },
                set: { idx in
                    let v = idx == 1 ? "time" : "node"
                    guard v != displayMode else { return }
                    displayMode = v
                    prefs.setDisplayMode(v)
                    refreshWidgets()
                }
            ),
            onSelect: { _ in }
        )
    }

    // Grid display group embeds its subtitle selector without another card.
    private var gridSubInfoCard: some View {
        VStack(alignment: .leading, spacing: SettingsLayout.controlGap) {
            Text(L10n.format("settings_grid_sub_info"))
                .font(SettingsLayout.itemStyle)
                .foregroundColor(colors.onSurface)
            SegmentedSwitcher(
                options: [("room", L10n.format("settings_grid_sub_room")),
                          ("teacher", L10n.format("settings_grid_sub_teacher")),
                          ("none", L10n.format("settings_grid_sub_none"))],
                selected: gridSubInfo,
                onSelect: { v in
                    guard v != gridSubInfo else { return }
                    gridSubInfo = v
                    prefs.setGridSubInfo(v)
                    refreshWidgets()
                },
                containerColor: colors.surfaceContainerHighest,
                accessibilityTitle: L10n.format("settings_grid_sub_info"))
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
                VisibleDayRow(day: day, visibleDays: visibleDays, onChange: { n in
                    visibleDays = n
                    prefs.setVisibleDays(n)
                    refreshWidgets()
                })
                if day != 7 { SubDivider() }
            }
        }
    }

    // Week scale and content settings share one noncollapsible surface.
    private var pillCard: some View {
        ScheduleDisplayGroup {
            ScheduleDisplayContent(section: .week)
            SettingToggleRow(label: L10n.format("settings_week_two_column"), checked: weekTwoColumn) {
                weekTwoColumn = $0
                prefs.setWeekTwoColumn($0)
            }
            if weekTwoColumn {
                DisplayModeOption(label: L10n.format("settings_week_two_column_days"),
                                  subtitle: "", selected: weekTwoColumnMode == "days") {
                    weekTwoColumnMode = "days"
                    prefs.setWeekTwoColumnMode("days")
                }
                DisplayModeOption(label: L10n.format("settings_week_two_column_balance"),
                                  subtitle: "", selected: weekTwoColumnMode == "balance") {
                    weekTwoColumnMode = "balance"
                    prefs.setWeekTwoColumnMode("balance")
                }
            }
            SettingToggleRow(label: L10n.format("settings_week_hide_empty"), checked: weekHideEmptyDays) {
                weekHideEmptyDays = $0
                prefs.setWeekHideEmptyDays($0)
            }
            SettingToggleRow(label: L10n.format("settings_week_alias"), checked: weekUseAlias) {
                weekUseAlias = $0
                prefs.setWeekUseAlias($0)
            }
        }
    }

    // ← 节假日课程灰显: 点击进入二级页 — ← 原版本 GeneralSettingsScreen.kt: titleSmall 单行, 无副标题
    private var holidayEntryCard: some View {
        Button { holidaySettingsItem = HolidaySettingsItem() } label: {
            HStack {
                Text(L10n.format("settings_holiday_title_rules"))
                    .font(.system(size: 14, weight: .medium))
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
        .accessibilityIdentifier("settings_holiday_entry")
    }
}

// 单行星期开关(整行可点 + 独立 Switch 双通路, ← 原版本 Row.noRippleClickable + Switch;
// 抽行: 类型推断上限)
private struct VisibleDayRow: View {
    @Environment(\.localWakeUpColors) private var colors
    let day: Int
    let visibleDays: Set<Int>
    let onChange: (Set<Int>) -> Void

    private func toggled(_ on: Bool) -> Set<Int> {
        on ? visibleDays.union([day]) : visibleDays.subtracting([day])
    }

    private func commit(_ on: Bool) {
        let n = toggled(on)
        // ← 原版本 n.isNotEmpty() 守卫: 至少留 1 天
        guard !n.isEmpty else { return }
        onChange(n)
    }

    var body: some View {
        let checked = visibleDays.contains(day)
        HStack {
            Text(DateUtils.localizedDay(day))
                .font(.system(size: 16))
                .foregroundColor(colors.onSurface)
            Spacer()
            Toggle("", isOn: Binding(
                get: { checked },
                set: { commit($0) }
            ))
            .toggleStyle(SleepyToggleStyle())
            .tint(colors.primary)
            .labelsHidden()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        // ← 原版本 整行 noRippleClickable 通路(文本区点击 = 切换)
        .contentShape(Rectangle())
        .onTapGesture { commit(!checked) }
        // 不做 .accessibilityElement(children: .combine): 合并后整行变合成 button 叶,
        // 吞掉 switch 可命中性(XCUITest taps[Mon] 落合成体, switch 永不触发 —
        // 2026-10 全量 run「点可见日行应翻转状态」失败根因)。
        // 不合并 = 文本+switch 皆可达, 与 原版本 整行可点语义等价。
    }
}

// ← 分组② 小组件 — v1.0.62 B4 整块移出至 WidgetSettingsScreen(独立页, 「我的」页进入;
//   原版本 GeneralSettingsScreen.kt −78 同口径: widget 块自通用页移出)。
//   偏好键零迁移: settings_widget_colorless / separator / nearest_busy_day 三开关
//   与「管理桌面小组件」入口行现宿主于 ui/screen/mine/WidgetSettingsScreen.swift。

// Language choices open an anchored native menu in both appearances.
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
        let currentLabel = languages.first { $0.0 == language }?.1 ?? language
        SettingsSection(title: L10n.format("settings_language"), first: true) {
            nativeLanguageMenu(currentLabel: currentLabel)
        }
    }

    private func nativeLanguageMenu(currentLabel: String) -> some View {
        Menu {
            Picker(L10n.format("settings_language"), selection: Binding(
                get: { language },
                set: { code in
                    guard code != language else { return }
                    // Let the native menu finish its selection before rebuilding the locale.
                    DispatchQueue.main.async {
                        language = code
                        AppPrefs.shared.setLanguage(code)
                        LocaleHelper.applyLanguage(code)
                    }
                }
            )) {
                ForEach(languages, id: \.0) { code, label in
                    Text(label).tag(code)
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 12) {
                Text(L10n.format("settings_language"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(colors.onSurface)
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Text(currentLabel)
                        .font(.system(size: 16))
                        .lineLimit(1)
                    AndroidSettingsIcon(name: .expandMore, size: 16)
                }
                .foregroundColor(colors.onSurfaceVariant)
                .frame(maxWidth: 180, alignment: .trailing)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(colors.surfaceContainer)
            .cornerRadius(SleepyShapes.large)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .accessibilityIdentifier("card_language")
        .accessibilityValue(currentLabel)
    }

}

// Display groups share Android's surface treatment without another card header.
private struct ScheduleDisplayGroup<Content: View>: View {
    @Environment(\.localWakeUpColors) private var colors
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsLayout.controlGap) {
            content()
        }
        .padding(SettingsLayout.cardInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.surfaceContainer)
        .cornerRadius(SleepyShapes.large)
    }
}

// Advanced grid preferences remain inside the grid display group.
private struct LabSection: View {
    @Environment(\.localWakeUpColors) private var colors
    let refreshWidgets: () -> Void

    @State private var gridAdaptiveHeight: Bool = AppPrefs.shared.isGridAdaptiveHeight()
    @State private var gridPinchZoom: Bool = AppPrefs.shared.isGridPinchZoom()
    @State private var autoHideEmptyEvening: Bool = AppPrefs.shared.isGridAutoHideEmptyEvening()
    @State private var eveningStart: String = AppPrefs.shared.getGridEveningStart()
    @State private var vertPunct: Bool = AppPrefs.shared.isVertPunctReplace()
    @State private var gridShowSeparators: Bool = AppPrefs.shared.isGridShowSeparators()
    @State private var gridLongBreakSpacing: Bool = AppPrefs.shared.isGridLongBreakSpacing()

    private let prefs = AppPrefs.shared

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsLayout.controlGap) {
            SettingToggleRow(label: L10n.format("settings_grid_adaptive_height"),
                             subtitle: L10n.format("settings_grid_adaptive_height_sub"),
                             checked: gridAdaptiveHeight) {
                gridAdaptiveHeight = $0
                prefs.setGridAdaptiveHeight($0)
            }
            SettingToggleRow(label: L10n.format("settings_grid_pinch_zoom"),
                             subtitle: L10n.format("settings_grid_pinch_zoom_sub"),
                             checked: gridPinchZoom) {
                gridPinchZoom = $0
                prefs.setGridPinchZoom($0)
            }
            SettingToggleRow(label: L10n.format("settings_grid_auto_hide_evening"),
                             subtitle: L10n.format("settings_grid_auto_hide_evening_sub"),
                             checked: autoHideEmptyEvening) {
                autoHideEmptyEvening = $0
                prefs.setGridAutoHideEmptyEvening($0)
            }
            if autoHideEmptyEvening {
                HStack(spacing: 12) {
                    Text(L10n.format("settings_grid_evening_start"))
                        .font(SettingsLayout.itemStyle)
                        .foregroundColor(colors.onSurface)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    TimePickerField(
                        value: eveningStart,
                        onValueChange: {
                            eveningStart = $0
                            prefs.setGridEveningStart($0)
                        },
                        label: ""
                    )
                    .frame(width: 150)
                }
            }
            SettingToggleRow(label: L10n.format("settings_grid_show_separators"),
                             subtitle: L10n.format("settings_appearance_separator_scope"),
                             checked: gridShowSeparators) {
                gridShowSeparators = $0
                prefs.setGridShowSeparators($0)
                refreshWidgets()
            }
            SettingToggleRow(label: L10n.format("settings_grid_long_break_spacing"),
                             subtitle: L10n.format("settings_appearance_break_scope"),
                             checked: gridLongBreakSpacing) {
                gridLongBreakSpacing = $0
                prefs.setGridLongBreakSpacing($0)
                refreshWidgets()
            }
        }
    }
}

/// 与 Android 的 ^-?\d{0,6}$ 一致: 允许编辑中的空串/负号, 仅完整整数落库。
enum UndoDepthInput {
    static func accepts(_ text: String) -> Bool {
        let digits = text.hasPrefix("-") ? text.dropFirst() : text[...]
        return digits.count <= 6 && digits.utf8.allSatisfy { (48...57).contains($0) }
    }

    static func value(_ text: String) -> Int? {
        guard accepts(text) else { return nil }
        return Int(text)
    }
}

private struct UndoDepthSettingsRow: View {
    @Environment(\.localWakeUpColors) private var colors
    @State private var input = String(AppPrefs.shared.getUndoDepth())

    // 临时 fallback 随全局 strings 补齐自动退出, 使用现有的语言 Bundle。
    private func localized(_ key: String, defaultValue: String) -> String {
        NSLocalizedString(key, bundle: LocaleHelper.currentBundle(), value: defaultValue, comment: "")
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(localized("settings_undo_depth", defaultValue: "撤回保留步数"))
                    .font(.system(size: 16))
                    .foregroundColor(colors.onSurface)
                Text(localized("settings_undo_depth_sub", defaultValue: "-1 为无限，0 为关闭撤回，其他数字保留相应步数。默认 5。历史仅存于内存，结束进程即清空。"))
                    .font(.system(size: 11))
                    .foregroundColor(colors.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            TextField("", text: Binding(
                get: { input },
                set: { text in
                    guard UndoDepthInput.accepts(text) else { return }
                    input = text
                    guard let value = UndoDepthInput.value(text) else { return }
                    AppPrefs.shared.setUndoDepth(value)
                    UndoManager.shared.applyMaxDepth(value)
                }
            ))
            // numberPad 没有负号, 无法输入合法的无限深度。
            .keyboardType(.numbersAndPunctuation)
            .textInputAutocapitalization(.never)
            .disableAutocorrection(true)
            .submitLabel(.done)
            .onSubmit { input = String(AppPrefs.shared.getUndoDepth()) }
            .multilineTextAlignment(.trailing)
            .padding(12)
            .frame(width: 110)
            .background(colors.surfaceContainerHigh)
            .cornerRadius(SleepyShapes.large)
            .accessibilityLabel(localized("settings_undo_depth_label", defaultValue: "撤回保留步数输入框"))
            .accessibilityIdentifier("general_undo_depth_field")
        }
        .padding(.vertical, 10)
    }
}

// ← 分组⑥ 数据迁移 (.sleepybackup 全量迁移): 导出行 / 导入行
//   busy 时两行内容半透明(alpha 0.5), 重复点击由回调自身的 busy 守卫挡掉(同 原版本)。
private struct MigrationSection: View {
    @Environment(\.localWakeUpColors) private var colors
    let busy: Bool
    let onExport: () -> Void
    let onImport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: L10n.format("settings_migration"))
            // ← 原版本 labelSmall(11sp) + bottom padding 8
            Text(L10n.format("settings_migration_sub"))
                .font(.system(size: 11))
                .foregroundColor(colors.onSurfaceVariant)
                .padding(.bottom, 8)
            VStack(spacing: 0) {
                Button(action: onExport) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.format("settings_migration_export"))
                                .font(.system(size: 16, weight: .semibold)) // ← titleMedium(16) SemiBold
                                .foregroundColor(colors.onSurface)
                            Text(L10n.format("settings_migration_export_sub"))
                                .font(.system(size: 12)) // ← bodySmall 12sp
                                .foregroundColor(colors.onSurfaceVariant)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        AndroidMaterialIcon(name: .chevronRight, size: 20) // ← 全 app chevron 惯例 20pt(本页节假日/管理入口同值)
                            .foregroundColor(colors.onSurfaceVariant)
                    }
                    .padding(16)
                    // ← 原版本 Row.modifier .alpha(if (migrationBusy) 0.5f else 1f) 挂在**每行**
                    //   的 modifier 链上(812), 不在外层 Column(807 只有 clip+background)——
                    //   因此 busy 时卡底色与行分隔线保持全不透明, 只有行内容半透明。
                    //   早先实现把 opacity 加在整卡上, 会让底色/分隔线一起变灰 = 视觉漂移。
                    .opacity(busy ? 0.5 : 1)
                    .contentShape(Rectangle())
                }
                .buttonStyle(SleepyButtonStyle())
                .accessibilityIdentifier("settings_migration_export_row")
                SubDivider()
                Button(action: onImport) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.format("settings_migration_import"))
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(colors.onSurface)
                            Text(L10n.format("settings_migration_import_sub"))
                                .font(.system(size: 12))
                                .foregroundColor(colors.onSurfaceVariant)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        AndroidMaterialIcon(name: .chevronRight, size: 20) // ← 全 app chevron 惯例 20pt(本页节假日/管理入口同值)
                            .foregroundColor(colors.onSurfaceVariant)
                    }
                    .padding(16)
                    // ← 同上行: 原版本 840 也是每行 .alpha, 不加在卡容器上
                    .opacity(busy ? 0.5 : 1)
                    .contentShape(Rectangle())
                }
                .buttonStyle(SleepyButtonStyle())
                .accessibilityIdentifier("settings_migration_import_row")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(colors.surfaceContainer)
            .cornerRadius(SleepyShapes.large)
            // busy 时不挂 allowsHitTesting(false): 原版本 也没禁命中——
            // 两行的点击回调各自早退(onMigrationExportClick 的 if (migrationBusy) return /
            // 导入行 if (!migrationBusy) importLauncher.launch), iOS 同构由
            // onMigrationExportClick 的 guard 与 MigrationSection.onImport 的 if 守卫承担。
        }
    }
}

// fileExporter 载体: 字节已在临时目录落盘(导出编排里写完), 这里只做 URL 搬运 —
// ← 原 exportLauncher 写 contentResolver 输出流。fileExporter 会把该文件拷到
// 用户选定的目标 URL(等价 CreateDocument 保存)。
private struct ExportedBackupFile: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }
    let url: URL?

    init(url: URL?) { self.url = url }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("sleepy-backup-reimport.sleepybackup")
        try data.write(to: tmp)
        url = tmp
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let url else { return FileWrapper(regularFileWithContents: Data()) }
        return FileWrapper(regularFileWithContents: (try? Data(contentsOf: url)) ?? Data())
    }
}

// 折叠展开集跨页恢复(rememberSaveable + Saver<Set<String>, ArrayList<String>>):
// AppRoot 状态恢复回到本页时, 折叠卡展开集按原样回来。iOS 等价 = 变更写 sleepy_prefs
// 主文件(Set ↔ 排序 [String]), 页面重建 load() 回填 — 比 原版本 Bundle 更强(跨启动
// 也保真), 行为方向一致。
private enum SettingsExpandedSectionsStore {
    static let KEY = "settings_expanded_sections"

    static func load() -> Set<String> {
        Set(AppPrefs.shared.sharedBackedStore.stringArray(forKey: KEY) ?? [])
    }

    static func save(_ sections: Set<String>) {
        AppPrefs.shared.sharedBackedStore.set(sections.sorted(), forKey: KEY)
    }
}

// (2026-10-21) 本页原 LabPrefs 临时层已删 —— 实验室开关的正式归属地是 AppPrefs.swift:
//   isGridAdaptiveHeight / isGridPinchZoom / isGridAutoHideEmptyEvening / getGridEveningStart
//   ("18:00") / isGridShowSeparators / isGridLongBreakSpacing (均 default false) 与
//   isShowViewSwitcher (default true), 及各自 set —— key、默认值逐条对齐 AppPrefs.kt
//   KEY_GRID_* / KEY_SHOW_VIEW_SWITCHER。同一批 prefs key 在本 target 里留两套实现,
//   「设置页写的」与「渲染读的」就可能分叉;CourseTableView 的旧 GridLabPrefs 直读层
//   已按同一理由删除(AppPrefs.swift:700-703 注)。默认值契约由
//   SleepyTests/VersionAndUpdateTests.swift 锁住。行为等价: 原 shim 与正式 getter 读写
//   同一 UserDefaults suite(AppPrefs.shared.sharedBackedStore == 其默认 sp())。

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
