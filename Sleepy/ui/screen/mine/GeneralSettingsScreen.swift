// General settings, schedule display and backup share their existing preference and migration actions.
import SwiftUI
import WidgetKit
import UniformTypeIdentifiers

@MainActor
struct GeneralSettingsScreen: View {
    enum Section { case general, display, backup }
    @Environment(\.localWakeUpColors) private var colors
    // ★ v7.10.18 原生化: onBack → onDismiss(由 fullScreenCover / sheet 关闭)
    //   holiday 子页由本屏内 NavigationView + NavigationLink 承载, 不再走 AppRoot enum
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
        case .display: return L10n.format("appearance_section_schedule_display")
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
    // ★ v7.10.18: HolidaySettings 在本屏内 sheet 弹出,无需走 root enum
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

    /// 原 prefs store: context.getSharedPreferences(name) →
    /// iOS 同名 suite(AppPrefs.standardUserDefaults() 的 sleepy_prefs 主文件按
    /// suiteName "sleepy_prefs" 打开即同一存储; 二级文件走各自 suiteName —
    /// 与 MigrationExecutorTests 的 FakeMigrationPrefsStore 同构)。
    private struct RuntimeMigrationPrefsStore: MigrationPrefsStoreProtocol {
        func open(fileName: String) -> UserDefaults {
            if fileName == AppPrefs.FILE { return AppPrefs.shared.sharedBackedStore }
            return UserDefaults(suiteName: fileName) ?? .standard
        }
    }

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
                    // migrationBusy 保持 true 直到保存面板出结果(busy 锁到
                    // exportLauncher 回调; iOS 对「用户取消」额外解锁, 防卡死)
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
        // ★ v7.10.18 原生化: NavigationView 内嵌 + NavigationLink 跳 HolidaySettings
        //   - iOS 16+: NavigationLink 推入栈,免费 swipe-back 手势
        //   - iOS 15: NavigationView stack 风格 + NavigationLink 正常工作,带原生 back 按钮
        //   - 6sp 空白: NavigationView 在此内嵌(非 root),子屏 navbar 是合法 UX 预期
        NavigationView {
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
                .navigationBarTitleDisplayMode(.inline)
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
                        // 用户取消面板 = CancellationError(静默, ← 原版本 uri==null 早退)
                        if error is CancellationError { return }
                        NSLog("SleepyMigration: export failed: %@", String(describing: error))
                        migrationToast = L10n.format("settings_migration_export_fail")
                    }
                }
                // ← 原版本 OpenDocument(["application/zip","application/octet-stream"])
                //   = UTType.zip + UTType.data(octet-stream); .sleepybackup 内容即 zip,
                //   动态 extension UTType 不进 allowedContentTypes(未声明类型有崩溃风险)
                .fileImporter(isPresented: $showImportPicker,
                              allowedContentTypes: [.zip, .data],
                              allowsMultipleSelection: false,
                              onCompletion: onImportFileResult)
        }
        .navigationViewStyle(.stack)
        .sheet(isPresented: $showPeriodHeaders) {
            PeriodHeaderSettingsScreen(onBack: { showPeriodHeaders = false })
        }
    }

    private var displaySettings: some View {
        VStack(spacing: SettingsLayout.cardGap) {
            ScheduleSettingsPreview(viewModel: viewModel)
            SettingsSection(title: L10n.format("settings_appearance_common"), first: true) {
                startViewCard
                displayModeCard
                visibleDaysCard
                commonDisplayToggles
            }
            SettingsSection(title: L10n.format("settings_start_view_full")) {
                pillCard
                ScheduleDisplayContent(section: .week)
            }
            SettingsSection(title: L10n.format("settings_start_view_cards")) {
                gridSubInfoCard
                gridAliasCard
                LabSection(refreshWidgets: refreshWidgets)
                ScheduleDisplayContent(section: .grid)
                AppearanceNavigationRow(title: L10n.format("appearance_period_header"),
                                        onClick: { showPeriodHeaders = true })
                    .accessibilityIdentifier("settings_period_header")
            }
            SettingsSection(title: L10n.format("settings_conflict_style")) {
                ScheduleDisplayContent(section: .conflict)
            }
            SettingsSection(title: L10n.format("settings_appearance_holidays")) {
                holidayEntryCard
            }
        }
    }

    private var startViewCard: some View {
        SettingsFlatCard(title: L10n.format("settings_start_view"),
                         options: [L10n.format("settings_start_view_full"), L10n.format("settings_start_view_cards")],
                         selectedIndex: Binding(get: { startView == "cards" ? 1 : 0 }, set: {
                             startView = $0 == 1 ? "cards" : "full"
                             prefs.setStartView(startView)
                         }))
    }

    private var commonDisplayToggles: some View {
        VStack(spacing: 8) {
            SettingToggleRow(label: L10n.format("settings_nearest_busy_day"),
                             subtitle: L10n.format("settings_nearest_busy_day_sub"), checked: nearestBusyDay) {
                nearestBusyDay = $0; prefs.setNearestBusyDay($0); refreshWidgets()
            }
            SettingToggleRow(label: L10n.format("settings_show_date"), checked: showDate) {
                showDate = $0; prefs.setShowDate($0); refreshWidgets()
            }
            SettingToggleRow(label: L10n.format("settings_show_view_switcher"), checked: showViewSwitcher) {
                showViewSwitcher = $0; prefs.setShowViewSwitcher($0)
            }
        }
        .padding(16).background(colors.surfaceContainer).cornerRadius(SleepyShapes.large)
    }

    private var gridAliasCard: some View {
        SettingToggleRow(label: L10n.format("settings_grid_alias"), checked: gridUseAlias) {
            gridUseAlias = $0; prefs.setGridUseAlias($0)
        }
        .padding(16).background(colors.surfaceContainer).cornerRadius(SleepyShapes.large)
    }

    // 课程时间显示: 节次 / 时间 — ← 原版本 SettingsFlatCard(标题行右侧 tab)
    private var displayModeCard: some View {
        SettingsFlatCard(
            title: L10n.format("settings_display_mode"),
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

    // 网格卡片副信息: 教室 / 教师 / 无 — ← 原版本 SettingsFlatCard
    private var gridSubInfoCard: some View {
        SettingsFlatCard(
            title: L10n.format("settings_grid_sub_info"),
            options: [
                L10n.format("settings_grid_sub_room"),
                L10n.format("settings_grid_sub_teacher"),
                L10n.format("settings_grid_sub_none")
            ],
            selectedIndex: Binding(
                get: {
                    switch gridSubInfo {
                    case "room": return 0
                    case "teacher": return 1
                    default: return 2
                    }
                },
                set: { idx in
                    let v = ["room", "teacher", "none"][idx]
                    guard v != gridSubInfo else { return }
                    gridSubInfo = v
                    prefs.setGridSubInfo(v)
                    refreshWidgets()
                }
            ),
            onSelect: { _ in }
        )
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

    // 主页显示(SettingsCard "settings_pill" 2026-09-21 定稿):
    // 样式参数(缩放/圆角)已迁外观与主题页(ScheduleDisplayScreen), 这里只保留内容/可见性参数 —
    // 两栏 → 分栏标准(条件) → 隐藏无课日 → 周/网格别名 → 表头日期 → 视图切换栏。
    private var pillCard: some View {
        SettingsCard(title: L10n.format("settings_start_view_full"),
                     expanded: expandedSections.contains("gridScale"),
                     onToggle: { toggleSection("gridScale") }) {
            // 内容 14 条 — 拆两 Group(ViewBuilder 10 项上限)
            Group {
                SubDivider()
                SettingToggleRow(label: L10n.format("settings_week_two_column"),
                                 subtitle: "",
                                 checked: weekTwoColumn) {
                    weekTwoColumn = $0
                    prefs.setWeekTwoColumn($0)
                }
                // 分栏标准 — 两栏开启时才需要选
                if weekTwoColumn {
                    SubDivider()
                    DisplayModeOption(label: L10n.format("settings_week_two_column_days"),
                                      subtitle: "",
                                      selected: weekTwoColumnMode == "days") {
                        weekTwoColumnMode = "days"
                        prefs.setWeekTwoColumnMode("days")
                    }
                    SubDivider()
                    DisplayModeOption(label: L10n.format("settings_week_two_column_balance"),
                                      subtitle: "",
                                      selected: weekTwoColumnMode == "balance") {
                        weekTwoColumnMode = "balance"
                        prefs.setWeekTwoColumnMode("balance")
                    }
                }
                // 隐藏无课日 — 与两栏无关, 单栏/两栏都生效(单栏按安卓语义不分栏不过滤)
                SubDivider()
                SettingToggleRow(label: L10n.format("settings_week_hide_empty"),
                                 subtitle: "",
                                 checked: weekHideEmptyDays) {
                    weekHideEmptyDays = $0
                    prefs.setWeekHideEmptyDays($0)
                }
                // issue#26 课程别名: 周视图/网格场景 原名/别名 二选一, 关=原名 开=别名(自独立卡挪入, 行为零变化)
                SubDivider()
                SettingToggleRow(label: L10n.format("settings_week_alias"),
                                 subtitle: "",
                                 checked: weekUseAlias) {
                    weekUseAlias = $0
                    prefs.setWeekUseAlias($0)
                }
            }
        }
    }

    // ← 节假日课程灰显: 点击进入二级页 — ← 原版本 GeneralSettingsScreen.kt: titleSmall 单行, 无副标题
    private var holidayEntryCard: some View {
        Button { holidaySettingsItem = HolidaySettingsItem() } label: {
            HStack {
                Text(L10n.format("settings_holiday_title"))
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
        .sheet(item: $holidaySettingsItem) { _ in
            // issue#44 接线(F095): 传当前选中课表 id + 映射刷新回调 ← 原实现
            // SleepyNavHost.kt:299-303 `tableId = currentTableId, viewModel = mainVm`。
            // 不传则 HolidaySettingsScreen 的 tableId 恒 nil → 调休卡显示
            // holiday_makeup_no_table 且 saveTransfer 在 guard let id = activeTableId 早退。
            HolidaySettingsScreen(
                onDismiss: { holidaySettingsItem = nil },
                tableId: viewModel?.state.selectedTableId,
                refreshTransfer: { viewModel?.refreshTransfer() })
        }
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

// ← 分组④ 语言 (v1.0.56 T4: 折叠卡 — 收起只显当前语言值 + 展开箭头, 点开展开 5 项;
//   2026-09-21: 组标题已示「语言」, 卡标题禁两遍, 改显当前值)
private struct LanguageSection: View {
    @Environment(\.localWakeUpColors) private var colors
    @Environment(\.sleepyUIStyle) private var style
    @State private var language: String = AppPrefs.shared.getLanguage()
    // ← 原 languageExpanded 默认 false(会话态足够: 选择语言即重建)
    @State private var expanded = false

    private let languages: [(String, String)] = [
        ("zh-CN", "简体中文"),
        ("zh-TW", "繁體中文"),
        ("en", "English"),
        ("ja", "日本語"),
        ("es", "Español")
    ]

    // ← 原版本 AnimatedVisibility expandVertically+fadeIn 默认 spec → 同 SettingsCards.swift
    //   sleepySettingsExpand(NoBouncy, response≈0.31)
    private let expandAnimation = Animation.spring(response: 0.31, dampingFraction: 1.0)

    var body: some View {
        let currentLabel = languages.first { $0.0 == language }?.1 ?? language
        SettingsSection(title: L10n.format("settings_language"), first: true) {
            if style == .liquidGlass {
                nativeLanguageMenu(currentLabel: currentLabel)
            } else {
                classicLanguageCard(currentLabel: currentLabel)
            }
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

    private func classicLanguageCard(currentLabel: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // 折叠头: 当前语言值 + 展开箭头 — padding(16)
            Button {
                withAnimation(expandAnimation) { expanded.toggle() }
            } label: {
                HStack {
                    Text(currentLabel)
                        .font(.system(size: 16, weight: .semibold)) // ← titleMedium(16) SemiBold
                        .foregroundColor(colors.onSurface)
                    Spacer()
                    AndroidSettingsIcon(name: .expandMore, size: 20)
                        .foregroundColor(colors.onSurfaceVariant)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(SleepyButtonStyle())
            .accessibilityIdentifier("card_language")
            // 展开体: 5 项列表, spacedBy 4, padding(start/end/bottom 16)
            if expanded {
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
                                    AndroidMaterialIcon(name: .check, size: 20)
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
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.surfaceContainer)
        .cornerRadius(SleepyShapes.large)
        .animation(expandAnimation, value: expanded)
    }
}

// ← 分组⑤ 实验室 (2026-09-16 用户令): 实验性功能默认全关, 可能随版本调整。
// 非折叠平铺卡(Column clip+surfaceContainer padding horizontal 16):
// 自适应行高 / 双指捏放 / 自动收起空白晚间(+晚间起始时间条件行) / 竖排标点 /
// 网格分隔线 / 长课间留白。
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
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                // 内容 12 条 — 拆两 Group(ViewBuilder 10 项上限)
                Group {
                    SettingToggleRow(label: L10n.format("settings_grid_adaptive_height"),
                                     subtitle: L10n.format("settings_grid_adaptive_height_sub"),
                                     checked: gridAdaptiveHeight) {
                        gridAdaptiveHeight = $0
                        prefs.setGridAdaptiveHeight($0)
                    }
                    SubDivider()
                    // v1.0.56 T3: 双指捏放行高 — 默认关, 关=网格视图捏不动
                    SettingToggleRow(label: L10n.format("settings_grid_pinch_zoom"),
                                     subtitle: L10n.format("settings_grid_pinch_zoom_sub"),
                                     checked: gridPinchZoom) {
                        gridPinchZoom = $0
                        prefs.setGridPinchZoom($0)
                    }
                    SubDivider()
                    SettingToggleRow(label: L10n.format("settings_grid_auto_hide_evening"),
                                     subtitle: L10n.format("settings_grid_auto_hide_evening_sub"),
                                     checked: autoHideEmptyEvening) {
                        autoHideEmptyEvening = $0
                        prefs.setGridAutoHideEmptyEvening($0)
                    }
                    if autoHideEmptyEvening {
                        SubDivider()
                        HStack(spacing: 12) {
                            Text(L10n.format("settings_grid_evening_start"))
                                .font(.system(size: 16))
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
                            .frame(width: 150) // ← 原 modifier=width(150.dp)
                        }
                        .padding(.vertical, 10)
                    }
                }
                Group {
                    SubDivider()
                    SettingToggleRow(label: L10n.format("settings_grid_show_separators"),
                                     subtitle: L10n.format("settings_grid_show_separators_sub"),
                                     checked: gridShowSeparators) {
                        gridShowSeparators = $0
                        prefs.setGridShowSeparators($0)
                        refreshWidgets()
                    }
                    SubDivider()
                    SettingToggleRow(label: L10n.format("settings_grid_long_break_spacing"),
                                     subtitle: L10n.format("settings_grid_long_break_spacing_sub"),
                                     checked: gridLongBreakSpacing) {
                        gridLongBreakSpacing = $0
                        prefs.setGridLongBreakSpacing($0)
                        refreshWidgets()
                    }
                }
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(colors.surfaceContainer)
            .cornerRadius(SleepyShapes.large)
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
