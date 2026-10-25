// PeriodTableEditScreen.swift — ← ui/screen/mine/PeriodTableEditScreen.kt
// 独立时间节次表编辑页(issue#40 设计 §4.2) — 复用 TimeSlotEditor:
// 手动/智慧节次、保存前预览(§5.2 决策 3)、保存写 period_tables + 全部兼容列同步。
// 编辑保存走 ScheduleViewModel.updatePeriodTableContent(→ repo.savePeriodTable,
// 课程行零改动); 取消预览则数据库零改动。
//
// 2026-09-20 用户拍板(issue#40 反馈, aa23a443): 编辑页不再有「作息表」第三 Tab。
// 绑定只存在于课表→作息表单向; 作息表之间禁绑定/取入, 防循环改写。
// v1.0.56 T7: 删除入口迁入本页 — 确认弹窗 + 绑定拦截提示(从管理页列表行整体搬迁)
// v1.0.56 T8: 复制先命名, 确认后才建; 成功后回管理页
// v1.0.56 T11: 分享底部弹窗(原生格式/JSON 二选一)

import Combine
import SwiftUI

struct PeriodTableEditScreen: View {
    @Environment(\.localWakeUpColors) private var colors
    @ObservedObject var viewModel: ScheduleViewModel
    /// 目标时间表 id(管理页保证已存在; 找不到时显示 not-found 后返回)
    let periodTableId: Int64
    /// issue#40: 本表是否为"新建后直接进入"的未保存表 — 返回(未保存)时整行丢弃, 管理页不留空壳
    var isNewUnsaved: Bool = false
    let onBack: () -> Void

    // ← Android remember 键控三段式:
    //   name/unsavedNew   ← remember(periodTable.id)                (ktl L107/L114)
    //   slotRows          ← remember(id, updatedAt, timeJson)       (ktl L126)
    //   smartConfig       ← remember(id, smartConfigJson)           (ktl L133)
    // 同 id 表的行/配置被外部更新(timeJson/smartConfigJson/updatedAt 任一变化)时随重载种子,
    // 对齐 Android collectAsState 流刷新; 未保存的本地编辑因键未变而保留。
    @State private var seededTableId: Int64? = nil
    @State private var seededRowsKey: String? = nil
    @State private var seededSmartKey: String? = nil
    @State private var name = ""
    @State private var timeSlotsExpanded = true
    @State private var error: String? = nil
    // 预览态: 非 nil = 显示确认弹窗; 确认才落库, 取消只清 state(§5.2 用户取消权)
    @State private var pendingPreview: TimeTableUtils.PeriodTablePreview? = nil
    @State private var pendingSave: PeriodTableEntity? = nil
    // issue#40: 新建未保存表的丢弃标记 — 用户确认保存后翻 false, 返回不再删行
    @State private var unsavedNew = false
    // v1.0.56 T7: 删除确认 + 绑定拦截
    @State private var showDeleteConfirm = false
    @State private var deleteBlockedMsg: String? = nil
    // v1.0.56 T8: 复制先命名, 确认后才建; 成功后回管理页
    @State private var showCopyDialog = false
    @State private var copyName = ""
    // v1.0.56 T11: 分享底部弹窗(原生格式/JSON 二选一)
    @State private var showShareSheet = false

    @State private var slotRows: [TimeTableUtils.TimeSlotRow] = []
    @State private var smartConfig = SmartPeriodConfig()

    /// 全部作息表(名字查重 / 源表查找)
    @State private var allPeriodTables: [PeriodTableEntity] = []

    /// ← Android viewModel.allPeriodTables.collectAsState() — GRDB 观察流(订阅即发当前值,
    /// 之后 period_tables 每次写库自动 emit; onReceive 随视图下屏自动取消订阅)。
    /// 同 id 外部更新(他页保存/复制/删除)时本屏行数据与表列表随之刷新。
    private static let periodTableUpdates = ScheduleRepository(AppDatabase.getShared())
        .observeAllPeriodTables()
        .catch { _ in Empty<[PeriodTableEntity], Never>() }   // ← ScheduleViewModel.loadTables 同法吞流错误
        .receive(on: DispatchQueue.main)
        .eraseToAnyPublisher()

    var body: some View {
        let periodTable = resolvePeriodTable()
        // 数据装载修饰符挂在总根(而非 content): 表列表首次为空时本屏走 not-found 分支,
        // 但 .onAppear/.onReceive 仍须随视图一存在即订阅 + 同步查库 — 若挂在 content 上,
        // content 不渲染 → 装载永不触发 → allPeriodTables 无种子 → 永久 not-found(引导死锁)。
        // ← Android viewModel.allPeriodTables.collectAsState() 首帧即订阅, 数据到位自动重组。
        Group {
            if let periodTable = periodTable {
                content(periodTable: periodTable)
            } else {
                VStack {
                    Text(L10n.format("edit_table_not_found"))
                        .foregroundColor(colors.onBackground)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { reloadTables() }
        // ← allPeriodTables collectAsState(ktl L91): 表列表实时刷新(同 id timeJson 外部更新
        // 时 rows/smartConfig 也经 loadIfNeeded 键控重载)。not-found 阶段尚无本表 → 只播种列表,
        // 待 resolvePeriodTable 命中后由 content 名卡 onAppear 触发首次 loadIfNeeded。
        .onReceive(Self.periodTableUpdates) { tables in
            allPeriodTables = tables
            if let fresh = tables.first(where: { $0.id == periodTableId }) {
                loadIfNeeded(periodTable: fresh)
            }
        }
    }

    // 1) state/DB 已有: 直接命中
    // 2) DB 有但 state.tables 未同步: 手动查(管理页新建→编辑路径)
    private func resolvePeriodTable() -> PeriodTableEntity? {
        allPeriodTables.first { $0.id == periodTableId }
    }

    // MARK: - 主内容

    private func content(periodTable: PeriodTableEntity) -> some View {
        VStack(spacing: 0) {
            headerBar(periodTable: periodTable)
            ScrollView {
                VStack(spacing: 14) {
                    Spacer().frame(height: 2)

                    // 名称卡片
                    VStack(spacing: 12) {
                        FieldTextField(text: $name, label: L10n.format("period_table_name_label"))
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(colors.surfaceContainer)
                    .cornerRadius(SleepyShapes.extraLarge)
                    .onAppear { loadIfNeeded(periodTable: periodTable) }

                    // 节次时间表(可折叠, 与 EditTableScreen 同款交互)
                    VStack(spacing: 0) {
                        Button {
                            withAnimation { timeSlotsExpanded.toggle() }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(L10n.format("edit_table_time_slots"))
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(colors.onSurface)
                                    Text(L10n.format("n_periods", slotRows.count) + " · " +
                                         (timeSlotsExpanded ? L10n.format("collapse") : L10n.format("expand")))
                                        .font(.system(size: 12))
                                        .foregroundColor(colors.onSurfaceVariant)
                                }
                                Spacer()
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 24))
                                    .foregroundColor(colors.onSurfaceVariant)
                                    .rotationEffect(.degrees(timeSlotsExpanded ? 180 : 0))
                            }
                            .padding(16)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(SleepyButtonStyle())

                        if timeSlotsExpanded {
                            TimeSlotEditor(rows: slotRows,
                                           onRowsChange: { slotRows = $0 },
                                           smartConfig: smartConfig,
                                           onSmartConfigChange: { smartConfig = $0 })
                                // 作息表编辑页只允许编辑本表内容; 活绑定仅由课程表→作息表入口提供。
                                .padding(.leading, 16)
                                .padding(.trailing, 16)
                                .padding(.bottom, 16)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .background(colors.surfaceContainer)
                    .cornerRadius(SleepyShapes.extraLarge)

                    if let error = error {
                        Text(error)
                            .font(.system(size: 14))
                            .foregroundColor(colors.error)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // 保存 — 先预览后确认(§5.2)
                    Button(action: { prepareSave(periodTable: periodTable) }) {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 24))
                            Text(L10n.format("edit_table_save"))
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundColor(colors.onPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)   // ← SleepyTheme.Buttons.ctaHeight
                        .background(colors.primary)
                        .cornerRadius(SleepyShapes.large)
                    }
                    .buttonStyle(SleepyButtonStyle())

                    // v1.0.56 T7: 删除键(新建未保存的表不显示 — 退出即丢弃, 无"已存在的东西"可删)
                    if !unsavedNew {
                        Button(action: { showDeleteConfirm = true }) {
                            HStack(spacing: 8) {
                                Image(systemName: "trash")
                                    .font(.system(size: 24))
                                Text(L10n.format("period_table_delete_confirm"))
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .foregroundColor(colors.onErrorContainer)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)   // ← SleepyTheme.Buttons.regularHeight
                            .background(colors.errorContainer)
                            .cornerRadius(SleepyShapes.large)
                        }
                        .buttonStyle(SleepyButtonStyle())
                    }

                    Spacer().frame(height: 28)
                }
                .padding(.horizontal, 16)
            }
        }
        .background(colors.background)
        // 数据装载(.onAppear reloadTables + .onReceive 观察流)改挂 body 总根, 见 body 注释 —
        // 挂此处会随 not-found 分支不渲染而永不触发, 引导死锁。本函数只管渲染已解析的表。
        // 保存前预览确认弹窗(§9 决策 3): 取消 = 零写库零快照
        .sheet(isPresented: Binding(
            get: { pendingPreview != nil && pendingSave != nil },
            set: { if !$0 { pendingPreview = nil; pendingSave = nil } }
        )) {
            if let preview = pendingPreview, let toSave = pendingSave {
                previewDialog(periodTable: periodTable, preview: preview, toSave: toSave)
            }
        }
        // v1.0.56 T7: 删除确认弹窗
        .sheet(isPresented: $showDeleteConfirm) {
            deleteConfirmDialog(periodTable: periodTable)
        }
        // v1.0.56 T7: 绑定拦截提示(删不掉 = 仍有课表绑着本表)
        .sheet(isPresented: Binding(
            get: { deleteBlockedMsg != nil },
            set: { if !$0 { deleteBlockedMsg = nil } }
        )) {
            if let msg = deleteBlockedMsg {
                deleteBlockedDialog(msg: msg)
            }
        }
        // v1.0.56 T11: 分享格式选择底部弹窗
        .sheet(isPresented: $showShareSheet) {
            PeriodTableShareSheet(periodTable: periodTable, onDismiss: { showShareSheet = false })
        }
        // v1.0.56 T8: 复制命名弹窗
        .sheet(isPresented: $showCopyDialog) {
            copyDialog(periodTable: periodTable)
        }
    }

    private func headerBar(periodTable: PeriodTableEntity) -> some View {
        HStack {
            Button(action: handleBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .medium))
            }
            .accessibilityLabel(Text(L10n.t("back")))
            Spacer()
            Text(L10n.t("period_tables_title"))
                .font(.headline)
            Spacer()
            HStack(spacing: 0) {
                // v1.0.56 T11: 分享作息表(原生格式 / JSON 二选一)
                Button(action: { showShareSheet = true }) {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundColor(colors.onBackground)
                }
                .accessibilityLabel(Text(L10n.t("period_table_share_sheet_title")))
                Spacer().frame(width: 16)
                // v1.0.56 T8: 复制先弹命名框, 确认后才落库; 成功回管理页
                Button {
                    if let suggested = viewModel.suggestPeriodTableCopyName(sourceId: periodTable.id) {
                        copyName = suggested
                        showCopyDialog = true
                    }
                } label: {
                    Image(systemName: "doc.on.doc")
                        .foregroundColor(colors.onBackground)
                }
                .accessibilityLabel(Text(L10n.t("period_table_copy")))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // issue#40: 未保存的新表返回 = 放弃 — 清掉建表残留行, 与课表侧 discardNewTable 同语义
    private func handleBack() {
        if unsavedNew { viewModel.discardNewPeriodTable(id: periodTableId) }
        onBack()
    }

    private func reloadTables() {
        allPeriodTables = viewModel.loadAllPeriodTables()
    }

    // ← Android remember 键控初始化(表切换/同 id 外部更新时重载; 未保存本地编辑因键不变而保留)
    private func loadIfNeeded(periodTable: PeriodTableEntity) {
        let rowsKey = "\(periodTable.id)|\(periodTable.updatedAt)|\(periodTable.timeJson)"
        let smartKey = "\(periodTable.id)|\(periodTable.smartConfigJson)"
        let tableSwitched = seededTableId != periodTable.id
        if seededTableId != periodTable.id || seededRowsKey != rowsKey {
            seededTableId = periodTable.id
            seededRowsKey = rowsKey
            if tableSwitched { name = periodTable.name }   // ← remember(periodTable.id)
            slotRows = TimeTableUtils.parseTimeSlotRows(periodTable.timeJson)
        }
        if tableSwitched || seededSmartKey != smartKey {
            seededSmartKey = smartKey
            // issue#23 Task 4(← ktl L133-142): 已存配置仍能 derive 出当前行 → 原样保留;
            // 否则从当前行重推断(infer 以 stored 为 previous 承接分组标签);
            // 行不可推断 → 最简默认兜底(旧行为)。
            let stored = decodeSmartPeriodConfig(periodTable.smartConfigJson)
            smartConfig = resolveAutoPeriodConfig(rows: slotRows, stored: stored)
                ?? SmartPeriodConfig(
                    startTime: slotRows.first.flatMap {
                        $0.start.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0.start
                    } ?? "08:00",
                    totalPeriods: max(slotRows.count, 1))
        }
        if tableSwitched { unsavedNew = isNewUnsaved }
    }

    // MARK: - 保存(先预览)

    private func prepareSave(periodTable: PeriodTableEntity) {
        let valid = !slotRows.isEmpty
            && slotRows.allSatisfy {
                $0.start.range(of: "^\\d{2}:\\d{2}$", options: .regularExpression) != nil &&
                $0.end.range(of: "^\\d{2}:\\d{2}$", options: .regularExpression) != nil
            }
            && slotRows.allSatisfy { $0.start < $0.end }
        guard valid else {
            error = L10n.format("edit_table_validation_error")
            return
        }
        error = nil
        let smartConfigJson = (try? JSONEncoder().encode(smartConfig))
            .flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let newTimeJson = TimeTableUtils.buildTimeJsonFromRows(slotRows)
        var updated = periodTable
        // ← ktl L299 name.ifBlank: Kotlin isBlank 覆盖 \n/\r 等全部空白符, .whitespacesAndNewlines 等价
        updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? periodTable.name : name
        updated.timeJson = newTimeJson
        updated.smartConfigJson = smartConfigJson
        updated.nodesPerDay = max(slotRows.count, 1)
        pendingSave = updated
        // 预览: 全库范围内所有绑定本表的课程(§5.2 受影响课表列表)。
        // state.courses 只装当前选中表的课 — 从 repo 拉全库课程再按绑定表过滤。
        let boundIds = Set(viewModel.state.tables
            .filter { $0.periodTableId == periodTable.id }
            .map { $0.id })
        let allCourses = viewModel.getAllCoursesOnce().filter { boundIds.contains($0.tableId) }
        pendingPreview = TimeTableUtils.previewPeriodTableChange(
            oldTimeJson: periodTable.timeJson,
            newTimeJson: newTimeJson,
            courses: allCourses)
    }

    // MARK: - 弹窗

    /// 保存前预览确认弹窗(§9 决策 3): 逐课旧时间→新时间(§5.2) + 变化节次标注, 最多列 8 行防溢出。
    private func previewDialog(periodTable: PeriodTableEntity,
                               preview: TimeTableUtils.PeriodTablePreview,
                               toSave: PeriodTableEntity) -> some View {
        let boundCount = viewModel.state.tables
            .filter { $0.periodTableId == periodTable.id }.count
        return VStack(alignment: .leading, spacing: 8) {
            Text(L10n.t("period_table_save_preview_title"))
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(colors.onSurface)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.format("period_table_preview_summary",
                                     boundCount, preview.changedCourses.count, preview.unchangedCount))
                        .font(.system(size: 14))
                        .foregroundColor(colors.onSurfaceVariant)
                    // 2026-09-16 用户要求: 改早八必须列出所有第一节课的课程名+几点到几点。
                    ForEach(Array(preview.changedCourses.prefix(8).enumerated()), id: \.offset) { _, change in
                        let oldT = change.oldTime ?? "?"
                        let newT = change.newTime ?? "?"
                        let nodesTag: String = change.changedNodes.count == 1
                            ? L10n.format("course_node_format", String(change.changedNodes.first!))
                            : "\(change.changedNodes.first!)-\(change.changedNodes.last!)"
                        Text("\(change.courseName)(\(nodesTag)): \(oldT) → \(newT)")
                            .font(.system(size: 12))
                            .foregroundColor(colors.onSurface)
                    }
                    if preview.changedCourses.count > 8 {
                        Text(L10n.format("period_table_preview_more", preview.changedCourses.count - 8))
                            .font(.system(size: 12))
                            .foregroundColor(colors.onSurfaceVariant)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer().frame(height: 12)
            // 2026-09-16 用户: 裸 TextButton 无边界无色块 — 统一色块按钮行
            DialogActionButtons(
                confirmText: L10n.t("period_table_preview_confirm"),
                onConfirm: {
                    pendingPreview = nil
                    pendingSave = nil
                    // issue#40: 已确认保存 — 新建行的丢弃标记解除, 返回不再清行
                    unsavedNew = false
                    viewModel.updatePeriodTableContent(toSave)
                    onBack()
                },
                dismissText: L10n.t("cancel"),
                onDismiss: {
                    pendingPreview = nil
                    pendingSave = nil
                })
        }
        .padding(24)
        .background(colors.surface)
    }

    // v1.0.56 T7: 删除确认弹窗(原管理页逻辑整体迁移, 语义不变)
    private func deleteConfirmDialog(periodTable: PeriodTableEntity) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.t("period_table_delete_confirm"))
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(colors.onSurface)
            Text(L10n.format("period_table_delete_msg_body", periodTable.name))
                .font(.system(size: 14))
                .foregroundColor(colors.onSurfaceVariant)
            Spacer().frame(height: 12)
            DialogActionButtons(
                confirmText: L10n.t("delete"),
                onConfirm: {
                    showDeleteConfirm = false
                    let ok = viewModel.deletePeriodTable(id: periodTable.id)
                    if ok {
                        onBack()
                    } else {
                        let bound = viewModel.state.tables
                            .filter { $0.periodTableId == periodTable.id }.count
                        deleteBlockedMsg = L10n.format("period_table_delete_blocked", bound)
                    }
                },
                dismissText: L10n.t("cancel"),
                onDismiss: { showDeleteConfirm = false },
                destructive: true)
        }
        .padding(24)
        .background(colors.surface)
    }

    // v1.0.56 T7: 绑定拦截提示(删不掉 = 仍有课表绑着本表)
    private func deleteBlockedDialog(msg: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.t("period_table_delete_confirm"))
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(colors.onSurface)
            Text(msg)
                .font(.system(size: 14))
                .foregroundColor(colors.onSurfaceVariant)
            Spacer().frame(height: 12)
            DialogActionButtons(
                confirmText: L10n.t("ok"),
                onConfirm: { deleteBlockedMsg = nil })
        }
        .padding(24)
        .background(colors.surface)
    }

    // v1.0.56 T8: 复制命名弹窗
    private func copyDialog(periodTable: PeriodTableEntity) -> some View {
        let candidate = copyName.trimmingCharacters(in: .whitespacesAndNewlines)
        let nameTaken = !candidate.isEmpty && TimeTableUtils.isTableNameTaken(
            candidate,
            courseTableNames: viewModel.state.tables.map { $0.name },
            periodTableNames: allPeriodTables.map { $0.name })
        return VStack(alignment: .leading, spacing: 8) {
            Text(L10n.t("period_table_copy_dialog_title"))
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(colors.onSurface)
            FieldTextField(text: $copyName, label: L10n.t("period_table_name_label"))
                // ← Android TextField(isError = nameTaken) (ktl L494): 输入框本体错误态。
                //   FieldTextField 在 EditTableScreen.swift(本任务禁改), 按 DatePickerField
                //   同款先例在调用处补 M3 active indicator 底线; supportingText 红色说明行紧随其下。
                .overlay(alignment: .bottom) {
                    if nameTaken {
                        Rectangle()
                            .fill(colors.error)
                            .frame(height: 1)
                            .padding(.horizontal, 12)
                    }
                }
            if nameTaken {
                Text(L10n.t("period_table_name_taken"))
                    .font(.system(size: 12))
                    .foregroundColor(colors.error)
            }
            Spacer().frame(height: 12)
            DialogActionButtons(
                confirmText: L10n.t("ok"),
                onConfirm: {
                    let newId = viewModel.copyPeriodTableAs(sourceId: periodTable.id, newName: candidate)
                    if newId > 0 {
                        showCopyDialog = false
                        onBack()
                    }
                },
                dismissText: L10n.t("cancel"),
                onDismiss: { showCopyDialog = false },
                confirmEnabled: !candidate.isEmpty && !nameTaken)
        }
        .padding(24)
        .background(colors.surface)
    }
}
