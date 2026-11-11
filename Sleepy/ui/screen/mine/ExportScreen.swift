// ExportScreen.swift — ← ui/screen/mine/ExportScreen.kt
// 导出课表/作息表页 — Android 1.0.64:
// 顶部展开框上半列全部课表、横向分隔线、下半列全部作息表(课表优先展开完)。
// 选中课表 → 文件与分享(原生/分享文本/JSON)、日历与助手(系统日历/ICS/小爱);
// 选中作息表 → 自动只剩两项(Sleepy 原生 + JSON), 其余格式对纯作息无意义。
// 平台映射: MediaStore Downloads + ACTION_SEND → ShareLink/UIActivityViewController +
// 写临时文件(tmp)经 UIActivityViewController 分享(等价适配:iOS 沙箱无公共 Downloads)。
// RequestMultiplePermissions(READ/WRITE_CALENDAR) → EventKit requestAccess(状态机在
// SystemCalendarManager.ensureCalendarPermissions)。

import SwiftUI
import UIKit

struct ExportScreen: View {
    @Environment(\.localWakeUpColors) private var colors
    @ObservedObject var viewModel: ScheduleViewModel
    let onDismiss: () -> Void

    @State private var shareSheet: ShareItem? = nil
    @State private var snackMessage: String? = nil
    // ← 导出目标 — 本地选择, 不污染主页 selectedTableId/widget 默认表。
    //   二元选择: courseTableId(课表) / periodTableId(作息表); null,null = 未选(跟随当前课表)。
    @State private var exportTableId: Int64? = nil
    @State private var exportPeriodTableId: Int64? = nil
    // 全部作息表(展开框下半 + P 区块绑定 + 顶卡作息态)— ← 原版本 viewModel.allPeriodTables
    @State private var allPeriodTables: [PeriodTableEntity] = []
    // 选中表的课程: 当前表直接用 state.courses(已观察), 其他表选中时本地加载一次
    @State private var loadedCourses: [CourseEntity]? = nil
    @State private var showTablePicker = false
    @State private var showCalendarImport = false

    var body: some View {
        let state = viewModel.state
        // ← 原版本: effectiveId = if (exportPeriodTableId != null) null else (exportTableId ?: selectedTableId)
        let effectiveId = exportPeriodTableId != nil ? nil : (exportTableId ?? state.selectedTableId)
        let table = state.tables.first { $0.id == effectiveId } ?? state.currentTable
        let selectedPeriodTable = allPeriodTables.first { $0.id == exportPeriodTableId }
        let courses = loadedCourses ?? state.courses

        VStack(spacing: 0) {
            SettingsTopBar(title: L10n.format("export_title"), onBack: onDismiss)
            // 空态只在课表与作息表都不存在时成立; 无课表但有作息表时正常渲染,
            // 用户经顶部展开框选作息表导出(原生 + JSON) — 用户反馈 bug, 见契约测试(L184)。
            if table == nil && selectedPeriodTable == nil && allPeriodTables.isEmpty {
                Text(L10n.format("export_no_table"))
                    .font(.system(size: 16)) // ← 原默认 bodyLarge 16(未显式指定 style)
                    .foregroundColor(colors.onSurfaceVariant)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        // 顶部信息卡 — 点击拉出「课表/作息表」展开框(上半课表+分隔线+下半作息表)
                        Button {
                            allPeriodTables = viewModel.loadAllPeriodTables()
                            showTablePicker = true
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(selectedPeriodTable?.name ?? table?.name ?? "")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(colors.onPrimaryContainer)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    AndroidSettingsIcon(name: .expandMore, size: 24) // ← 原默认 Icon 24dp(ExpandMore 无 size 修饰)
                                        .foregroundColor(colors.onPrimaryContainer)
                                        // ← 原 contentDescription = export_pick_table
                                        .accessibilityLabel(L10n.format("export_pick_table"))
                                        .accessibilityHidden(false)
                                }
                                Text(periodSubtitle(pt: selectedPeriodTable, table: table, courses: courses))
                                    .font(.system(size: 14))
                                    .foregroundColor(colors.onPrimaryContainer)
                            }
                            .padding(20)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(colors.primaryContainer)
                            .cornerRadius(SleepyShapes.large)
                        }
                        .buttonStyle(SleepyButtonStyle())
                        .accessibilityIdentifier("export_table_card")

                        // 作息表保留原生与 JSON；课表按文件分享、日历与助手分组。
                        if let pt = selectedPeriodTable {
                            VStack(spacing: 0) {
                                ExportItem(icon: "star",
                                           title: L10n.format("period_table_share_native_title"),
                                           subtitle: L10n.format("period_table_share_native_sub"),
                                           id: "export_period_native_row") {
                                    exportFile(displayName: pt.name,
                                               ext: "sleepy", mime: "text/plain",
                                               content: SleepyNativeExporter.exportPeriodTableShareText(pt))
                                }
                                RowDivider()
                                ExportItem(icon: "curlybraces",
                                           title: L10n.format("period_table_share_json_title"),
                                           subtitle: L10n.format("period_table_share_json_sub"),
                                           id: "export_period_json_row") {
                                    exportFile(displayName: pt.name,
                                               ext: "json", mime: "application/json",
                                               content: SleepyNativeExporter.exportPeriodTableJson(pt))
                                }
                            }
                            .background(colors.surfaceContainer)
                            .cornerRadius(SleepyShapes.large)
                        } else if let table = table {
                            SettingsSection(title: L10n.format("settings_export_sharing")) {
                                VStack(spacing: 0) {
                                    ExportItem(icon: "star",
                                               title: L10n.format("settings_export_native_file_title"),
                                               subtitle: L10n.format("settings_export_native_file_sub"),
                                               id: "export_native_row") {
                                        // MIME 用 text/plain 规避 ImportReceiverActivity MIME 收窄问题(调查报告 P3)
                                        exportFile(displayName: table.name,
                                                   ext: "sleepy", mime: "text/plain",
                                                   content: SleepyNativeExporter.exportFile(
                                                       tableName: table.name, startDate: table.startDate,
                                                       maxWeek: table.maxWeek, nodesPerDay: table.nodesPerDay,
                                                       timeJson: table.timeJson, courses: courses,
                                                       // issue#40 §6: 绑定了独立时间节次表时携带 P 区块(共享关系可往返)
                                                       periodTable: boundPeriodTable(table).map {
                                                           SleepyNativeExporter.PeriodTableExport(
                                                               id: $0.id, name: $0.name,
                                                               nodesPerDay: $0.nodesPerDay, timeJson: $0.timeJson)
                                                       }, importSourceJson: table.importSourceJson))
                                    }
                                    RowDivider()
                                    ExportItem(icon: "square.and.arrow.up",
                                               title: L10n.format("export_share_title"),
                                               subtitle: L10n.format("export_share_subtitle"),
                                               id: "export_share_row") {
                                        // ← shareText: sleepy-v1 文本(【来自Sleepy】包裹), 与原实现
                                        //   SleepyNativeExporter.exportShareText 同构(不再用 WakeUp URL JSON)
                                        let period = boundPeriodTable(table)
                                        let effective = table.hydratedWith(period)
                                        shareSheet = ShareItem(text: SleepyNativeExporter.exportShareText(
                                                    tableName: effective.name, startDate: effective.startDate,
                                                    maxWeek: effective.maxWeek, nodesPerDay: effective.nodesPerDay,
                                                    timeJson: effective.timeJson, courses: courses,
                                                    periodTable: period.map { .init(id: $0.id, name: $0.name,
                                                        nodesPerDay: $0.nodesPerDay, timeJson: $0.timeJson) }, importSourceJson: table.importSourceJson),
                                                    subject: table.name, url: nil)
                                        snackMessage = L10n.format("export_copied_hint")
                                    }
                                    RowDivider()
                                    ExportItem(icon: "curlybraces",
                                               title: L10n.format("export_json_title"),
                                               subtitle: L10n.format("export_json_subtitle"),
                                               id: "export_json_row") {
                                        exportFile(displayName: table.name,
                                                   ext: "json", mime: "application/json",
                                                   content: ScheduleExporter.exportWakeUpJson(table.hydratedWith(boundPeriodTable(table)), courses))
                                    }
                                }
                                .background(colors.surfaceContainer)
                                .cornerRadius(SleepyShapes.large)
                            }
                            SettingsSection(title: L10n.format("settings_export_calendar_assistants")) {
                                VStack(spacing: 0) {
                                    ExportItem(icon: "calendar",
                                               title: L10n.format("calendar_import_title"),
                                               subtitle: (effectiveId != state.selectedTableId && loadedCourses == nil)
                                                   ? L10n.format("calendar_import_loading")
                                                   : L10n.format("calendar_import_subtitle"),
                                               id: "export_calendar_import_row") {
                                        if SystemCalendarManager.shared.hasCalendarPermissions() {
                                            openCalendarImportForCurrentTarget()
                                        } else {
                                            Task { @MainActor in
                                                if await SystemCalendarManager.shared.ensureCalendarPermissions() {
                                                    openCalendarImportForCurrentTarget()
                                                } else {
                                                    showCalendarImport = false
                                                }
                                            }
                                        }
                                    }
                                    RowDivider()
                                    ExportItem(icon: "calendar",
                                               title: L10n.format("export_ics_title"),
                                               subtitle: L10n.format("export_ics_subtitle"),
                                               id: "export_ics_row") {
                                        // ← 原 `LocalDate.parse` 对非法 startDate 抛异常、不产出文件;
                                        //   iOS 等价: 走 exportIcsOrThrow, catch 报 export_failed —
                                        //   不再用 exportIcs 包装器静默分享空 ICS(用户会看到「已保存」假成功)。
                                        do {
                                            exportFile(displayName: table.name,
                                                       ext: "ics", mime: "text/calendar",
                                                       content: try ScheduleExporter.exportIcsOrThrow(table.hydratedWith(boundPeriodTable(table)), courses,
                                                           transfers: AppPrefs.shared.getHolidayTransfers(table.id)))
                                        } catch {
                                            snackMessage = L10n.format("export_failed")
                                        }
                                    }
                                    RowDivider()
                                    ExportItem(icon: "sparkles",
                                               title: L10n.format("export_xiaoai_title"),
                                               subtitle: L10n.format("export_xiaoai_subtitle"),
                                               id: "export_xiaoai_row") {
                                        launchXiaoaiImport(table: table,
                                                           courses: courses,
                                                           boundPeriodTable: boundPeriodTable(table))
                                    }
                                }
                                .background(colors.surfaceContainer)
                                .cornerRadius(SleepyShapes.large)
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .background(colors.background)
        // ← snackbar 等价
        .overlay(alignment: .bottom) {
            if let msg = snackMessage {
                Text(msg)
                    .font(.system(size: 14)) // ← 原 Snackbar bodyMedium 14
                    .accessibilityIdentifier("export_snackbar")
                    .foregroundColor(colors.onSurface)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(colors.surfaceContainerHighest)
                    .cornerRadius(8)
                    .padding(.bottom, 12)
                    .task(id: msg) {
                        // snackbar 2s(LENGTH_SHORT)。UI 测试态延到 6s:
                        // 批量跑套件时模拟器负载高, 单次 XCUITest 快照可能 >2s,
                        // 负载尖峰会错过 snackbar 存活窗口造成批量 flake(单跑全绿)。
                        let life: Double = ProcessInfo.processInfo.arguments
                            .contains("-SLEEPY_UI_TEST_SEED") ? 6 : 2
                        try? await Task.sleep(nanoseconds: UInt64(life * 1_000_000_000))
                        guard !Task.isCancelled else { return }
                        withAnimation { snackMessage = nil }
                    }
            }
        }
        .sheet(item: $shareSheet) { item in
            ShareSheet(text: item.text, subject: item.subject, url: item.url)
        }
        .onAppear {
            allPeriodTables = viewModel.loadAllPeriodTables()
            reloadPinnedCourses(viewModel.state)
        }
        .onChange(of: exportTableId) { _ in reloadPinnedCourses(viewModel.state) }
        .onChange(of: exportPeriodTableId) { _ in reloadPinnedCourses(viewModel.state) }
        // ← 导出目标课表/作息表选择弹层 — 行样式对齐 ScheduleScreen TableSwitcherSheet(用户定版视觉)
        .centeredDialog(isPresented: $showTablePicker) {
            ExportTablePickerSheet(
                tables: state.tables,
                periodTables: allPeriodTables,
                selectedTableId: effectiveId,
                selectedPeriodTableId: exportPeriodTableId,
                mainSelectedId: state.selectedTableId,
                onSelectTable: { id in
                    exportPeriodTableId = nil
                    exportTableId = id
                    showTablePicker = false
                },
                onSelectPeriod: { id in
                    exportPeriodTableId = id
                    exportTableId = nil
                    showTablePicker = false
                },
                onDismiss: { showTablePicker = false })
        }
        // ← 系统日历导入配置弹窗(CalendarImportDialog):
        // 仅已授权 + hydratedTable 非空时呈现; 传入绑定作息水合后的表 + 目标表课程。
        .centeredDialog(isPresented: $showCalendarImport) {
            let state = viewModel.state
            let effectiveId = exportPeriodTableId != nil ? nil : (exportTableId ?? state.selectedTableId)
            let table = state.tables.first { $0.id == effectiveId } ?? state.currentTable
            if let table = table, SystemCalendarManager.shared.hasCalendarPermissions() {
                CalendarImportDialog(
                    table: table.hydratedWith(boundPeriodTable(table)),
                    courses: loadedCourses ?? state.courses,
                    onDismiss: { showCalendarImport = false })
            }
        }
    }

    // 顶卡副标题 — ← 原版本: 作息态「作息表 · N 节/天」; 课表态「N 门课程 · 起始日期」
    private func periodSubtitle(pt: PeriodTableEntity?, table: TimeTableEntity?, courses: [CourseEntity]) -> String {
        if let pt = pt {
            return L10n.format("period_tables_title") + " · " + L10n.format("period_table_nodes_count", pt.nodesPerDay)
        }
        return "\(L10n.format("export_course_count", courses.count)) · \(L10n.format("export_start_date", table?.startDate ?? ""))"
    }

    // 课表绑定的作息表(issue#40) — ← 原版本 allPeriodTables.find { it.id == table.periodTableId }
    private func boundPeriodTable(_ table: TimeTableEntity) -> PeriodTableEntity? {
        guard let pid = table.periodTableId else { return nil }
        return allPeriodTables.first { $0.id == pid }
    }

    // 日历导入入口(openCalendarImportForCurrentTarget):
    // 载入目标表课程后打开配置弹窗
    private func openCalendarImportForCurrentTarget() {
        reloadPinnedCourses(viewModel.state)
        showCalendarImport = true
    }

    // 选中表的课程: 当前表直接用 state.courses(已观察), 其他表选中时本地加载一次
    private func reloadPinnedCourses(_ state: ScheduleState) {
        let effectiveId = exportPeriodTableId != nil ? nil : (exportTableId ?? state.selectedTableId)
        if let tid = effectiveId, tid != state.selectedTableId {
            loadedCourses = try? ScheduleRepository(AppDatabase.getShared()).getCourses(tid)
        } else {
            loadedCourses = nil
        }
    }

    // v1.0.62 B6 ← 原版本 launchXiaoaiImport: 小爱课程表一键导入。
    // 深链 voiceassist://aiweb/?url=&presetData= 唤起小爱(或小爱课程表独立 App),
    // H5 /import 路由读 presetData.importData 进预览, 用户确认后才写入小米云。
    // Sleepy 本地准备数据后打开链接; 小爱接收后的联网和数据处理由其负责。
    // 未安装小爱 → open 失败回调提示安装(iOS open 无需 LSApplicationQueriesSchemes,
    // canOpenURL 才需要 — 原版本 SecurityException 在 iOS 无等价物, 不设分支)。
    private func launchXiaoaiImport(table: TimeTableEntity, courses: [CourseEntity], boundPeriodTable: PeriodTableEntity?) {
        if courses.isEmpty {
            snackMessage = L10n.format("export_xiaoai_empty")
            return
        }
        let presetData: String
        do {
            presetData = try XiaoaiPresetData.build(table: table, courses: courses, periodTable: boundPeriodTable)
        } catch {
            // ← 原版本 IllegalArgumentException → export_xiaoai_invalid
            snackMessage = L10n.format("export_xiaoai_invalid")
            return
        }
        guard let url = URL(string: XiaoaiPresetData.deepLink(presetData)) else {
            snackMessage = L10n.format("export_failed")
            return
        }
        UIApplication.shared.open(url) { ok in
            // ← 原版本 ActivityNotFoundException → Toast(not_installed); 成功 → onResult(launched)
            snackMessage = ok ? L10n.format("export_xiaoai_launched")
                              : L10n.format("export_xiaoai_not_installed")
        }
    }

    // ← exportAndShare: 写临时文件 + 分享(课表/作息表共用, 文件名 sleepy_<目标名>_<stamp>_<ext>)
    private func exportFile(displayName: String, ext: String, mime: String, content: String) {
        let url = Self.temporaryExportURL(displayName: displayName, ext: ext)
        let fileName = url.lastPathComponent
        do {
            try content.data(using: .utf8)?.write(to: url)
            shareSheet = ShareItem(text: nil, subject: displayName, url: url)
            snackMessage = L10n.format("export_saved_to", fileName)
            // 成就：导出备份
            AchievementTracker.shared.checkExportBackup()
        } catch {
            snackMessage = L10n.format("export_failed")
        }
    }

    static func temporaryExportURL(displayName: String, ext: String,
                                   directory: URL = FileManager.default.temporaryDirectory) -> URL {
        directory.appendingPathComponent("sleepy_\(displayName)_\(stamp()).\(ext)")
    }

    private static func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }
}

// ← 导出目标「课表/作息表」展开框(AlertDialog) — 2026-09-16 重构对齐:
// 上半 = 全部课表展开, 横向分隔线(仅存在作息表时), 下半 = 全部作息表(课表优先展开完, 用户指定顺序)。
// 行样式对齐 ScheduleScreen TableSwitcherSheet(用户定版视觉):
// 选中行 primaryContainer + 对勾; 主页当前课表挂 export_current_table_badge; 作息行副标题「作息表」;
// 上限 480 高滚动(heightIn(max = 480.dp))。
private struct ExportTablePickerSheet: View {
    @Environment(\.localWakeUpColors) private var colors
    let tables: [TimeTableEntity]
    let periodTables: [PeriodTableEntity]
    let selectedTableId: Int64?
    let selectedPeriodTableId: Int64?
    let mainSelectedId: Int64?
    let onSelectTable: (Int64) -> Void
    let onSelectPeriod: (Int64) -> Void
    let onDismiss: () -> Void

    var body: some View {
        CenteredPickerDialog(title: L10n.format("export_pick_table"), maxContentHeight: 480, onDismiss: onDismiss) {
                VStack(spacing: 4) {
                    // ---- 上半: 全部课表 ----
                    ForEach(tables) { table in
                        // ← 原版本: exportPeriodTableId == null && t.id == effectiveId
                        let isSelected = selectedPeriodTableId == nil && table.id == selectedTableId
                        PickerRow(
                            title: table.name,
                            subtitle: table.id == mainSelectedId
                                ? L10n.format("export_current_table_badge") : nil,
                            isSelected: isSelected,
                            rowId: "export_table_row_\(table.id)") {
                            onSelectTable(table.id)
                        }
                    }
                    // ---- 横向分隔线(仅存在作息表时) ----
                    if !periodTables.isEmpty {
                        Rectangle()
                            .fill(colors.outlineVariant)
                            .frame(height: 0.5) // ← 原 HorizontalDivider thickness 0.5dp
                            .padding(.vertical, 8)
                    }
                    // ---- 下半: 全部作息表 ----
                    ForEach(periodTables) { pt in
                        PickerRow(
                            title: pt.name,
                            subtitle: L10n.format("period_tables_title"),
                            isSelected: pt.id == selectedPeriodTableId,
                            rowId: "export_period_row_\(pt.id)") {
                            onSelectPeriod(pt.id)
                        }
                    }
                }
        }
    }
}

// ← 原版本 PickerRow: 课表/作息表共用行视觉(选中态 primaryContainer 色块+对勾, 禁描边规则)
private struct PickerRow: View {
    @Environment(\.localWakeUpColors) private var colors
    let title: String
    let subtitle: String?
    let isSelected: Bool
    let rowId: String
    let onClick: () -> Void

    var body: some View {
        Button {
            onClick()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 0) { // ← 原 Column 默认 spacing 0
                    Text(title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(isSelected ? colors.onPrimaryContainer : colors.onSurface)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: 11)) // ← 原 labelSmall
                            .foregroundColor(isSelected ? colors.onPrimaryContainer : colors.onSurfaceVariant)
                    }
                }
                Spacer()
                if isSelected {
                    AndroidMaterialIcon(name: .check, size: 18) // ← 原 Modifier.size(18.dp)
                        .foregroundColor(colors.primary)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            .background(isSelected ? colors.primaryContainer : colors.surfaceContainer)
            .cornerRadius(SleepyShapes.small)
        }
        .buttonStyle(SleepyButtonStyle())
        .accessibilityIdentifier(rowId)
    }
}

// 分享载荷(Identifiable for sheet(item:))
private struct ShareItem: Identifiable {
    let id = UUID()
    let text: String?
    let subject: String
    let url: URL?
}

// UIActivityViewController 包装(← Intent.createChooser)
private struct ShareSheet: UIViewControllerRepresentable {
    let text: String?
    let subject: String
    let url: URL?

    func makeUIViewController(context: Context) -> UIActivityViewController {
        var items: [Any] = []
        if let text = text { items.append(text) }
        if let url = url { items.append(url) }
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.setValue(subject, forKey: "subject")
        return vc
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// ← ExportItem
private struct ExportItem: View {
    @Environment(\.localWakeUpColors) private var colors
    let icon: String
    let title: String
    let subtitle: String
    var id: String? = nil
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            HStack(spacing: 16) {
                Group {
                    switch icon {
                    case "star": AndroidSettingsIcon(name: .star, size: 24)
                    case "curlybraces": AndroidSettingsIcon(name: .code, size: 24)
                    case "square.and.arrow.up": AndroidSettingsIcon(name: .share, size: 24)
                    case "sparkles": AndroidSettingsIcon(name: .smartToy, size: 24)
                    case "calendar": AndroidMaterialIcon(name: .calendarMonth, size: 24)
                    default: Image(systemName: icon).font(.system(size: 24))
                    }
                } // ← 原默认 Icon 24dp
                    .foregroundColor(colors.onPrimaryContainer)
                    .frame(width: 44, height: 44)
                    .background(colors.primaryContainer)
                    .cornerRadius(SleepyShapes.medium)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colors.onSurface)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(colors.onSurfaceVariant)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .buttonStyle(SleepyButtonStyle())
        .modifier(OptionalIdentifier(id: id))
    }
}

// 可选 identifier(不破坏无 id 调用点)
private struct OptionalIdentifier: ViewModifier {
    let id: String?
    func body(content: Content) -> some View {
        if let id = id {
            content.accessibilityIdentifier(id)
        } else {
            content
        }
    }
}

private struct RowDivider: View {
    @Environment(\.localWakeUpColors) private var colors
    var body: some View {
        Rectangle()
            .fill(colors.outlineVariant.opacity(SleepyTheme.Alpha.hairline))
            .frame(height: 0.5)
            .padding(.horizontal, 16)
    }
}
