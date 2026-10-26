// GeneralSettingsScreen.swift — ← ui/screen/mine/GeneralSettingsScreen.kt
// 通用设置页(决策 D1 L1 ⑤): 六组 — ①课表显示 / ②小组件 / ③画面与导航 / ④语言 /
// ⑤实验室 / ⑥数据迁移 (2026-09-21 Android 定稿分组与顺序, 本文件 v1.0.61 对齐重排)。
// 显示项变更后即时刷新小组件;语言切换 → LocaleHelper.applyLanguage(无 Activity.recreate,
// 等价适配:iOS 由窗口重建语言环境)。
// 分组②③④⑤⑥与各折叠卡抽为子视图 — SwiftUI ViewBuilder 单闭包 10 子视图上限。
// 平台适配说明:
// - 高刷新率行: iOS 无公开刷率 API(ProMotion 系统调度), 不移植 — 已载于
//   PlatformParityNotes.swift; ③组仅 启动默认页 + 底栏样式。
// - 数据迁移: Android CreateDocument/OpenDocument → fileExporter(临时 .sleepybackup
//   文件分享落盘) + fileImporter; Toast → 底部胶囊浮层(仓库同款模式)。

import SwiftUI
import WidgetKit
import UniformTypeIdentifiers

@MainActor
struct GeneralSettingsScreen: View {
    @Environment(\.localWakeUpColors) private var colors
    // ★ v7.10.18 原生化: onBack → onDismiss(由 fullScreenCover / sheet 关闭)
    //   holiday 子页由本屏内 NavigationView + NavigationLink 承载, 不再走 AppRoot enum
    let onDismiss: () -> Void

    /// issue#44 调休映射接线 ← Android SleepyNavHost.kt:299-303(`tableId = currentTableId,
    /// viewModel = mainVm`): 节假日子页需要「当前选中课表 id」与「映射变更后的课表页刷新回调」。
    /// 选中表 id 在 iOS 侧唯一真源 = ScheduleViewModel.state.selectedTableId(AppPrefs 不持久化),
    /// 故本屏须能读到 VM。可选(nil = 调用方尚未接线 → tableId 退化为 nil、refreshTransfer 不触发,
    /// 与本页现状行为一致且不崩);集成者需在 SleepyApp.swift `.general` overlay case 传入
    /// `viewModel: scheduleViewModel`(scheduleViewModel 已在 PresentOverlay 内, 见 SleepyApp.swift:545)。
    /// { viewModel?.refreshTransfer() } 的 Void? 闭包在 () -> Void 槽位写法同 JwWebViewLoginScreen:191 先例。
    var viewModel: ScheduleViewModel? = nil

    private let prefs = AppPrefs.shared

    @State private var expandedSections: Set<String> = SettingsExpandedSectionsStore.load()
    @State private var displayMode: String = AppPrefs.shared.getDisplayMode()
    @State private var gridSubInfo: String = AppPrefs.shared.getGridSubInfo()
    @State private var showDate: Bool = AppPrefs.shared.isShowDate()
    @State private var showViewSwitcher: Bool = AppPrefs.shared.isShowViewSwitcher()
    /// 启动默认视图 — ← AppPrefs.getStartView Android (默认 "full")。仅通用设置里设置,
    /// 手动切换课表顶部视图不写入(Android 注释硬规则, iOS 一致遵循)。
    @State private var startView: String = AppPrefs.shared.getStartView()
    @State private var visibleDays: Set<Int> = AppPrefs.shared.getVisibleDays()
    @State private var courseColorless: Bool = AppPrefs.shared.isCourseColorless()
    // ★ issue#8 主页显示 pill 组(← Android GeneralSettingsScreen)
    @State private var weekUseAlias: Bool = AppPrefs.shared.isWeekUseAlias()
    @State private var gridUseAlias: Bool = AppPrefs.shared.isGridUseAlias()
    @State private var weekTwoColumn: Bool = AppPrefs.shared.isWeekTwoColumn()
    @State private var weekTwoColumnMode: String = AppPrefs.shared.getWeekTwoColumnMode()
    @State private var weekHideEmptyDays: Bool = AppPrefs.shared.isWeekHideEmptyDays()
    /// 底栏样式三档(2026-10-26 设备自适应): 0=自动(prefs 无键) / 1=贴底 / 2=悬浮。
    /// 初值从 AppPrefs 读存在性 — 未写入即自动(缺省 false 不是用户意志)。
    @State private var navStyleIdx: Int = DisplayNavigationSection.initialNavStyleIndex()
    // ★ v1.0.61 数据迁移组(← Android GeneralSettingsScreen.kt 分组⑥)
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

    // ── 数据迁移(← Android runMigrationImport / onMigrationExportClick / launchers) ──

    /// Android prefs store: context.getSharedPreferences(name) →
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
                    // ← Android Toast settings_migration_import_done(课表数, 课程数)
                    migrationToast = L10n.format("settings_migration_import_done",
                                                 report.counts.timeTables, report.counts.courses)
                    // 偏好与小组件配置可能被替换, 迁移后统一刷新小组件
                    WidgetCenter.shared.reloadAllTimelines()
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
                // ← Android modules = {DATABASE, PREFERENCES, WIDGETS}(依赖闭包
                //   由 MigrationModuleDeps.resolve 自动补 PERSISTED_STATE, 两端同)
                let result = try MigrationExecutor.export(
                    selected: [.DATABASE, .PREFERENCES, .WIDGETS],
                    prefsStore: store,
                    courseDao: db.courseDao, timeTableDao: db.timeTableDao,
                    periodTableDao: db.periodTableDao, importDraftDao: db.importDraftDao,
                    dbQueue: db.dbQueue
                )
                // ← Android stamp = SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US)
                let f = DateFormatter()
                f.dateFormat = "yyyyMMdd-HHmmss"
                f.locale = Locale(identifier: "en_US_POSIX")
                let fileName = "sleepy-backup-\(f.string(from: Date())).sleepybackup"
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent(fileName)
                try result.bytes.write(to: url)
                await MainActor.run {
                    // migrationBusy 保持 true 直到保存面板出结果(← Android busy 锁到
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
        // ← Android uri == null 静默取消(OpenDocument 取消路径)
        guard case .success(let urls) = result, let url = urls.first else { return }
        migrationBusy = true
        Task.detached(priority: .userInitiated) {
            let secured = url.startAccessingSecurityScopedResource()
            defer { if secured { url.stopAccessingSecurityScopedResource() } }
            let bytes = try? Data(contentsOf: url)
            await MainActor.run {
                migrationBusy = false
                if let bytes {
                    // ← Android: 读成功 → 弹模式选择对话框
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
                    SettingsTopBar(title: L10n.format("mine_general"), onBack: onDismiss)
                    ScrollView {
                        VStack(spacing: 16) {
                            // ── 分组① 课表显示 (2026-09-21 Android 改名: 与③「画面与导航」拉开边界) ──
                            Group {
                                Group {
                                    SectionHeader(title: L10n.format("appearance_section_schedule_display"))

                                    displayModeCard
                                    gridSubInfoCard
                                    pillCard
                                    visibleDaysCard
                                }
                                Group {
                                    courseColorlessCard
                                    holidayEntryCard
                                }

                                MajorDivider()
                            }

                            // ── 分组② 小组件 + 分组③ 画面与导航 ──
                            Group {
                                WidgetSection(expandedSections: $expandedSections,
                                              refreshWidgets: refreshWidgets)

                                MajorDivider()

                                // 分组③ (启动默认页 + 底栏样式;
                                //    高刷新率 = Android 专有, iOS 无公开刷率 API, 不移植)
                                DisplayNavigationSection(
                                    startView: $startView,
                                    navStyleIdx: $navStyleIdx,
                                    onNavStyleChange: { idx in
                                        // 单源真值:AppRoot 监听 prefs 后即刻重渲底栏。
                                        // 0=自动 → 清盘回自适应;1/2=显式写盘永久优先。
                                        switch idx {
                                        case 0: prefs.clearNavStyle()
                                        case 1: prefs.setNavDocked(false)
                                        default: prefs.setNavDocked(true)
                                        }
                                    })

                                MajorDivider()
                            }

                            // ── 分组④ 语言 (v1.0.56 T4: 折叠卡) ──
                            LanguageSection()

                            MajorDivider()

                            // ── 分组⑤ 实验室 (2026-09-16 用户令: 实验性功能默认全关) ──
                            LabSection(refreshWidgets: refreshWidgets)

                            MajorDivider()

                            // ── 分组⑥ 数据迁移 ──
                            MigrationSection(busy: migrationBusy,
                                             onExport: onMigrationExportClick,
                                             onImport: {
                                                 // ← Android: if (!migrationBusy) importLauncher.launch(...)
                                                 if !migrationBusy { showImportPicker = true }
                                             })
                        }
                        .padding(16)
                    }
                }
                .background(colors.background)
                // ← Android rememberSaveable(expandedSections): AppRoot 状态恢复时折叠
                //   展开集保真。iOS 等价 = 变更即落 sleepy_prefs, 页面重建(load())回填。
                //   单一收口挂在父级 State 上 — WidgetSection 经 $expandedSections 改动
                //   同样触发。
                .onChange(of: expandedSections) { SettingsExpandedSectionsStore.save($0) }
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarHidden(true)
                // ← Android Toast(迁移结果) → 底部胶囊浮层(仓库同款, 1.8s 自动消失)
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
                // ← Android AlertDialog(导入模式选择): 标题/正文/覆盖·合并/取消
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
                // ← Android CreateDocument("application/zip") 保存对话框 → fileExporter。
                //   完成回调对齐 Android exportLauncher: 写成功 export_ok toast,
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
                        // 用户取消面板 = CancellationError(静默, ← Android uri==null 早退)
                        if error is CancellationError { return }
                        NSLog("SleepyMigration: export failed: %@", String(describing: error))
                        migrationToast = L10n.format("settings_migration_export_fail")
                    }
                }
                // ← Android OpenDocument(["application/zip","application/octet-stream"])
                //   = UTType.zip + UTType.data(octet-stream); .sleepybackup 内容即 zip,
                //   动态 extension UTType 不进 allowedContentTypes(未声明类型有崩溃风险)
                .fileImporter(isPresented: $showImportPicker,
                              allowedContentTypes: [.zip, .data],
                              allowsMultipleSelection: false,
                              onCompletion: onImportFileResult)
        }
        .navigationViewStyle(.stack)
    }

    // 课程时间显示: 节次 / 时间 — ← Android SettingsFlatCard(标题行右侧 tab)
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

    // 网格卡片副信息: 教室 / 教师 / 无 — ← Android SettingsFlatCard
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

    // 主页显示(← Android SettingsCard "settings_pill" 2026-09-21 定稿):
    // 样式参数(缩放/圆角)已迁外观与主题页(ScheduleDisplayScreen), 这里只保留内容/可见性参数 —
    // 两栏 → 分栏标准(条件) → 隐藏无课日 → 周/网格别名 → 表头日期 → 视图切换栏。
    private var pillCard: some View {
        SettingsCard(title: L10n.format("settings_pill"),
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
            Group {
                SubDivider()
                SettingToggleRow(label: L10n.format("settings_grid_alias"),
                                 subtitle: "",
                                 checked: gridUseAlias) {
                    gridUseAlias = $0
                    prefs.setGridUseAlias($0)
                }
                // 表头日期 — 网格视图列头 + 小组件列头共用的开关
                SubDivider()
                SettingToggleRow(label: L10n.format("settings_show_date"),
                                 subtitle: "",
                                 checked: showDate) {
                    showDate = $0
                    prefs.setShowDate($0)
                    refreshWidgets()
                }
                // 视图切换栏属于课表显示设置, 与主页显示参数放在同一子选项内
                SubDivider()
                SettingToggleRow(label: L10n.format("settings_show_view_switcher"),
                                 subtitle: "",
                                 checked: showViewSwitcher) {
                    showViewSwitcher = $0
                    prefs.setShowViewSwitcher($0)
                }
            }
        }
    }

    // 课程胶囊统一底色: 标题行开关 — ← Android flat title-plus-switch row
    // (2026-09-21 Android 标签补主语「App 内」— 文案随 L10n 键更新, 结构不变)
    private var courseColorlessCard: some View {
        HStack {
            Text(L10n.format("settings_course_colorless"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(colors.onSurface)
            Spacer()
            Toggle("", isOn: Binding(
                get: { courseColorless },
                set: {
                    courseColorless = $0
                    prefs.setCourseColorless($0)
                }
            ))
            .toggleStyle(.switch)
            .tint(colors.primary)
            .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(colors.surfaceContainer)
        .cornerRadius(SleepyShapes.large)
        .accessibilityLabel(Text(L10n.format("settings_course_colorless")))
    }

    // ← 节假日课程灰显: 点击进入二级页 — ← Android GeneralSettingsScreen.kt: titleSmall 单行, 无副标题
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
            // issue#44 接线(F095): 传当前选中课表 id + 映射刷新回调 ← Android
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

// 单行星期开关(整行可点 + 独立 Switch 双通路, ← Android Row.noRippleClickable + Switch;
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
        // ← Android n.isNotEmpty() 守卫: 至少留 1 天
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
            .toggleStyle(.switch)
            .tint(colors.primary)
            .labelsHidden()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        // ← Android 整行 noRippleClickable 通路(文本区点击 = 切换)
        .contentShape(Rectangle())
        .onTapGesture { commit(!checked) }
        // 不做 .accessibilityElement(children: .combine): 合并后整行变合成 button 叶,
        // 吞掉 switch 可命中性(XCUITest taps[Mon] 落合成体, switch 永不触发 —
        // 2026-10 全量 run「点可见日行应翻转状态」失败根因)。
        // 不合并 = 文本+switch 皆可达, 与 Android 整行可点语义等价。
    }
}

// ← 分组② 小组件 (2026-09-21 定稿: colorless / separator / 没课时显示最近有课的一天;
//   竖排标点优化已迁实验室组 — 实验功能唯一家门=「实验室」组, 禁第三形态)
private struct WidgetSection: View {
    @Environment(\.localWakeUpColors) private var colors
    @Binding var expandedSections: Set<String>
    let refreshWidgets: () -> Void

    // ← onOpenWidgetManagement: 跳二级页列出已放置的小组件
    @State private var showManage = false

    @State private var widgetColorless: Bool = AppPrefs.shared.isWidgetColorless()
    @State private var widgetSeparator: Bool = AppPrefs.shared.isWidgetSeparator()
    @State private var nearestBusyDay: Bool = AppPrefs.shared.isNearestBusyDay()
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
                SettingToggleRow(label: L10n.format("settings_nearest_busy_day"),
                                 subtitle: L10n.format("settings_nearest_busy_day_sub"),
                                 checked: nearestBusyDay) {
                    nearestBusyDay = $0
                    // Android setNearestBusyDay + refreshWidgets; iOS setter 内部已
                    // reloadAllTimelines(AppPrefs.swift:461), 再显式刷一次与 Android 同构无害
                    prefs.setNearestBusyDay($0)
                    refreshWidgets()
                }
            }

            // 管理桌面小组件: 跳二级页列出已放置的小组件(模板: 节假日课程灰显入口行)
            // ← GeneralSettingsScreen.kt item{ Row{...} }: titleSmall + ChevronRight 20dp
            Button { showManage = true } label: {
                HStack {
                    Text(L10n.format("widget_manage_entry"))
                        .font(.system(size: 14, weight: .medium)) // ← Android titleSmall 14sp Medium
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
            .accessibilityIdentifier("settings_widget_manage_entry")
        }
        .fullScreenCover(isPresented: $showManage) {
            WidgetManagementScreen(onDismiss: { showManage = false })
        }
    }
}

// ← 分组③ 画面与导航: 启动默认页 + 底栏样式(高刷新率 = Android 专有, 见 PlatformParityNotes)
private struct DisplayNavigationSection: View {
    // 卡片样式由 SettingsFlatCard 自带(surfaceContainer + 内嵌 tab), 本组无需直读 colors
    @Binding var startView: String
    // ★ 2026-10-26 三档化(设备自适应): 自动 / 贴底 / 悬浮。
    //   navStyleIdx: 0=自动(prefs 无键), 1=贴底(显式存 false), 2=悬浮(显式存 true)。
    //   「自动」档 subtitle 显示当前实际生效形态(NavStyleResolver.currentModeLabel)。
    @Binding var navStyleIdx: Int
    let onNavStyleChange: (Int) -> Void

    private let prefs = AppPrefs.shared

    var body: some View {
        VStack(spacing: 16) {
            SectionHeader(title: L10n.format("settings_section_display_navigation"))
            // 启动默认页: App 级启动偏好, 与课程/小组件渲染参数分组 — ← Android SettingsFlatCard
            SettingsFlatCard(
                title: L10n.format("settings_start_view"),
                options: [
                    L10n.format("settings_start_view_full"),
                    L10n.format("settings_start_view_cards")
                ],
                selectedIndex: Binding(
                    get: { startView == "cards" ? 1 : 0 },
                    set: { idx in
                        let v = idx == 1 ? "cards" : "full"
                        guard v != startView else { return }
                        startView = v
                        prefs.setStartView(v)
                    }
                ),
                onSelect: { _ in }
            )
            // 底栏样式: 自动 / 贴底 / 悬浮三档(用户 2026-09-04: 放「画面与导航」分组)。
            //   ★ 2026-10-26 设备自适应改造: 双档(贴底/悬浮)升级为三档, 「自动」= 清盘
            //   回 NavStyleResolver 按设备形态/系统能力自判, subtitle 展示当前生效形态。
            //   布局变更: 由「标题+贴右双 tab」行内式改为「标题+全宽三 tab」独立行 —
            //   贴右行内式在 320pt(SE)下 三档+日/西长标签(下部に固定/Flotante)必爆宽
            //   (行内 tab 可用宽仅 ~176pt); 全宽独立行 ~256pt, 段宽 82pt, SegmentedSwitcher
            //   自带 minimumScaleFactor 0.75 + allowsTightening 兜最宽标签, 5 语言全稳。
            //   同款先例 = AppearanceView「显示模式」深色三档卡(标题下全宽 tab)。
            //   状态由 AppRoot 持有下传: 底栏与设置页同一真值, 切换即生效。
            SettingsFlatCard(
                title: L10n.format("settings_nav_style"),
                subtitle: navStyleIdx == 0
                    ? L10n.format("settings_nav_style_auto_subtitle",
                                  NavStyleResolver.currentModeLabel())
                    : nil,
                options: [
                    L10n.format("settings_nav_style_auto"),
                    L10n.format("settings_nav_style_docked"),
                    L10n.format("settings_nav_style_floating")
                ],
                selectedIndex: Binding(
                    get: { navStyleIdx },
                    set: { idx in
                        // ← Android if (navDock != on) 守卫精神: 同值不回写、不重渲底栏
                        guard idx != navStyleIdx else { return }
                        navStyleIdx = idx
                        onNavStyleChange(idx)
                    }
                ),
                onSelect: { _ in }
            )
            .accessibilityIdentifier("settings_nav_style")
        }
    }

    /// 初值映射: prefs 无键→0(自动); 存 false→1(贴底); 存 true→2(悬浮)。
    /// 语义锚 = AppPrefs: isNavDocked() true=悬浮(2026-09-08 方向校正后),
    /// hasExplicitNavStyle() = 键存在性(缺省 false ≠ 用户意志)。
    static func initialNavStyleIndex() -> Int {
        guard AppPrefs.shared.hasExplicitNavStyle() else { return 0 }
        return AppPrefs.shared.isNavDocked() ? 2 : 1
    }
}

// ← 分组④ 语言 (v1.0.56 T4: 折叠卡 — 收起只显当前语言值 + 展开箭头, 点开展开 5 项;
//   2026-09-21: 组标题已示「语言」, 卡标题禁两遍, 改显当前值)
private struct LanguageSection: View {
    @Environment(\.localWakeUpColors) private var colors
    @State private var language: String = AppPrefs.shared.getLanguage()
    // ← Android languageExpanded 默认 false(会话态足够: 选择语言即重建)
    @State private var expanded = false

    private let languages: [(String, String)] = [
        ("zh-CN", "简体中文"),
        ("zh-TW", "繁體中文"),
        ("en", "English"),
        ("ja", "日本語"),
        ("es", "Español")
    ]

    // ← Android AnimatedVisibility expandVertically+fadeIn 默认 spec → 同 SettingsCards.swift
    //   sleepySettingsExpand(NoBouncy, response≈0.31)
    private let expandAnimation = Animation.spring(response: 0.31, dampingFraction: 1.0)

    var body: some View {
        let currentLabel = languages.first { $0.0 == language }?.1 ?? language
        VStack(spacing: 16) {
            SectionHeader(title: L10n.format("settings_language"))
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
                        Image(systemName: "chevron.down")
                            .font(.system(size: 20))
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
}

// ← 分组⑤ 实验室 (2026-09-16 用户令): 实验性功能默认全关, 可能随版本调整。
// 非折叠平铺卡(← Android Column clip+surfaceContainer padding horizontal 16):
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
            SectionHeader(title: L10n.format("settings_lab"))
            // ← Android labelSmall(11sp) + bottom padding 8
            Text(L10n.format("settings_lab_sub"))
                .font(.system(size: 11))
                .foregroundColor(colors.onSurfaceVariant)
                .padding(.bottom, 8)
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
                            .frame(width: 150) // ← Android modifier=width(150.dp)
                        }
                        .padding(.vertical, 10)
                    }
                    SubDivider()
                    // 竖排标点优化: 自 widget 卡迁入实验室组(2026-09-21)
                    SettingToggleRow(label: L10n.format("settings_vert_punct"),
                                     subtitle: L10n.format("settings_vert_punct_sub"),
                                     checked: vertPunct) {
                        vertPunct = $0
                        AppPrefs.shared.setVertPunctReplace($0)
                        refreshWidgets()
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

// ← 分组⑥ 数据迁移 (.sleepybackup 全量迁移): 导出行 / 导入行
//   busy 时两行内容半透明(alpha 0.5), 重复点击由回调自身的 busy 守卫挡掉(同 Android)。
private struct MigrationSection: View {
    @Environment(\.localWakeUpColors) private var colors
    let busy: Bool
    let onExport: () -> Void
    let onImport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: L10n.format("settings_migration"))
            // ← Android labelSmall(11sp) + bottom padding 8
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
                        Image(systemName: "chevron.right")
                            .font(.system(size: 20)) // ← 全 app chevron 惯例 20pt(本页节假日/管理入口同值)
                            .foregroundColor(colors.onSurfaceVariant)
                    }
                    .padding(16)
                    // ← Android Row.modifier .alpha(if (migrationBusy) 0.5f else 1f) 挂在**每行**
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
                        Image(systemName: "chevron.right")
                            .font(.system(size: 20)) // ← 全 app chevron 惯例 20pt(本页节假日/管理入口同值)
                            .foregroundColor(colors.onSurfaceVariant)
                    }
                    .padding(16)
                    // ← 同上行: Android 840 也是每行 .alpha, 不加在卡容器上
                    .opacity(busy ? 0.5 : 1)
                    .contentShape(Rectangle())
                }
                .buttonStyle(SleepyButtonStyle())
                .accessibilityIdentifier("settings_migration_import_row")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(colors.surfaceContainer)
            .cornerRadius(SleepyShapes.large)
            // busy 时不挂 allowsHitTesting(false): Android 也没禁命中——
            // 两行的点击回调各自早退(onMigrationExportClick 的 if (migrationBusy) return /
            // 导入行 if (!migrationBusy) importLauncher.launch), iOS 同构由
            // onMigrationExportClick 的 guard 与 MigrationSection.onImport 的 if 守卫承担。
        }
    }
}

// fileExporter 载体: 字节已在临时目录落盘(导出编排里写完), 这里只做 URL 搬运 —
// ← Android exportLauncher 写 contentResolver 输出流。fileExporter 会把该文件拷到
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

// 折叠展开集跨页恢复(← Android rememberSaveable + Saver<Set<String>, ArrayList<String>>):
// AppRoot 状态恢复回到本页时, 折叠卡展开集按原样回来。iOS 等价 = 变更写 sleepy_prefs
// 主文件(Set ↔ 排序 [String]), 页面重建 load() 回填 — 比 Android Bundle 更强(跨启动
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
