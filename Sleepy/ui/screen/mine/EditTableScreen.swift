// EditTableScreen.swift — ← ui/screen/mine/EditTableScreen.kt
// 编辑课表: 基础信息(名称/开始日期/周数)+节次时间表折叠(TimeSlotEditor 手动/自动/作息表三 Tab,
// 含 issue#40 换绑选择器)+保存(校验 → loading 闸 → 换绑确认 → 甲案三选项 → 解绑/双写/remap 四分支链)
// +删除(确认弹窗;新建未保存表不显示)。

import SwiftUI

struct EditTableScreen: View {
    @Environment(\.localWakeUpColors) private var colors
    @ObservedObject var viewModel: ScheduleViewModel
    var tableId: Int64? = nil
    var pendingNewTableId: Int64? = nil
    let onDismiss: () -> Void
    var onDiscardPending: () -> Void
    let onSaved: () -> Void
    let onDeleted: () -> Void

    init(viewModel: ScheduleViewModel,
         tableId: Int64? = nil,
         pendingNewTableId: Int64? = nil,
         onDismiss: @escaping () -> Void,
         onDiscardPending: (() -> Void)? = nil,
         onSaved: @escaping () -> Void,
         onDeleted: @escaping () -> Void) {
        self.viewModel = viewModel
        self.tableId = tableId
        self.pendingNewTableId = pendingNewTableId
        self.onDismiss = onDismiss
        self.onDiscardPending = onDiscardPending ?? onDismiss
        self.onSaved = onSaved
        self.onDeleted = onDeleted
    }

    @State private var loadedTableId: Int64? = nil
    @State private var loadedScheduleKey: String? = nil
    @State private var name = ""
    @State private var startDate = ""
    // ← Android maxWeekText: 数字文本(可输任意值, toIntOrNull ?: 20 兜底), 非 Stepper 硬顶 60
    @State private var maxWeekText = ""
    @State private var timeSlotsExpanded = false
    @State private var error: String? = nil
    @State private var showDeleteConfirm = false
    @State private var slotRows: [TimeTableUtils.TimeSlotRow] = []
    @State private var smartConfig = SmartPeriodConfig()

    // issue#40: 换绑选择(§5.3) — 初始 = table.periodTableId; 确认时才写 periodTableId。
    // pendingBind != table.periodTableId 时保存流程走换绑分支。
    @State private var pendingBind: Int64? = nil
    // issue#40 §5.3: 换绑确认弹窗 — 非 nil 时弹「确认换绑」, 确认才真正写 periodTableId
    @State private var pendingRebind: Int64? = nil
    // 弹窗显隐与数据解耦: Android AlertDialog(pendingRebind != null) 且确认回调先取
    // targetId 后置 null — iOS alert 关闭会先复位 Binding, 故单独持有显示态防竞态。
    @State private var showRebindConfirm = false
    // 换绑确认跨越保存按钮与弹窗回调, 暂存待写回的课程表元数据。
    @State private var pendingRebindTable: TimeTableEntity? = nil
    // 用户在编辑区对目标作息表的节次/智慧配置编辑也一并暂存, 确认时落 target period。
    @State private var pendingRebindPeriod: PeriodTableEntity? = nil

    // 甲案 (设计文档 §2.2): 作息冲突三选项 — 绑定共享作息表时改了作息内容, 保存先弹三选项。
    // 会话状态每次进入编辑页(按 table.id)重建: original = 本次进入时刻的实际生效作息快照。
    @State private var editState: ScheduleEditPolicyState? = nil
    // editState.pendingSchedulePolicy 的视图镜像(本屏是唯一写入方, 每次变更后同步)
    @State private var pendingPolicy: SchedulePolicy = .none
    @State private var showConflictSheet = false
    // .sheet 拖拽关闭走 onDismiss: 区分「已在弹窗内处置」与「弹窗外点按=取消」
    @State private var conflictSheetResolved = false
    @State private var boundCount = 0
    // 取消撤销作息改动后自增 → slotRows/smartConfig 的重建键变化 → 用库中真值重建
    @State private var scheduleEpoch = 0

    // issue#40: 全部时间节次表(换绑选择器数据源 §4.3) — 直读 VM 观察流。
    // ← Android viewModel.allPeriodTables.collectAsState(): GRDB ValueObservation 订阅即推
    //   最新值, 屏外改了作息表(管理页/编辑页)本屏选项随之更新;
    //   旧实现进会话时 loadAllPeriodTables() 拍快照 → 会话期陈旧, 已改为实时源。
    private var allPeriodTables: [PeriodTableEntity] { viewModel.allPeriodTables }

    /// issue#40: 有效作息表跟随 pendingBind(用户在下拉里改选时立即切换编辑区来源),
    /// 否则已绑定的表恒非空, 保存永远走"写回旧表"分支, 换绑成死代码。
    /// ← Android state.effectivePeriodTable?.takeIf { pendingBind != null && it.id == pendingBind }
    ///   ?: allPeriodTables.find { it.id == pendingBind } — 先取 VM 水合源(本课表绑定的
    ///   observeEffectivePeriodTable 最新 emit), 命中条件同 Android; 未命中再回落全表列表。
    ///   pendingBind == nil 两支皆 nil(表 id 恒非 nil) = 未绑定, 编辑区读本表兼容列。
    ///   body 与 enterSession 两处同源(命名不与局部量重名, 免「自身初始值」歧义)。
    private func resolveEffectivePeriodTable(from state: ScheduleState) -> PeriodTableEntity? {
        // Swift 无 Kotlin 扩展 takeIf —— flatMap 表达「命中条件才取值, 否则 nil」
        let bound = state.effectivePeriodTable.flatMap {
            (pendingBind != nil && $0.id == pendingBind) ? $0 : nil
        }
        return bound ?? allPeriodTables.first { $0.id == pendingBind }
    }

    var body: some View {
        let state = viewModel.state
        // ← Android: tableId == null 编辑当前表; 显式 tableId 未命中 → edit_table_not_found 空态。
        // 新建场景不兜底到首张表(createEmptyTable 已同步补入 state.tables, 按 id 必命中),
        // 显式 id 查不到就是查不到 — 编辑错表(首张表)比短暂 not-found 严重。
        let resolved: TimeTableEntity? = {
            if let tableId = tableId {
                return state.tables.first { $0.id == tableId }
            }
            return state.currentTable
        }()

        let effectivePeriodTable = resolveEffectivePeriodTable(from: state)

        if let table = resolved {
            content(table: table, effective: effectivePeriodTable)
        } else {
            VStack {
                Text(L10n.format("edit_table_not_found"))
                    .foregroundColor(colors.onBackground)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func content(table: TimeTableEntity, effective: PeriodTableEntity?) -> some View {
        // ← remember(table.id, effective?.id, timeJson, scheduleEpoch) 的重建键:
        //   绑定切换/会话重建/取消撤销都会换键 → slotRows/smartConfig 从新来源重建。
        //   timeJson 取实体来源(effective/table)的列值, 用户编辑 slotRows 不改动它,
        //   故编辑期键稳定(与 Android 一致: 编辑只动 mutableStateListOf, 不换 remember 键)。
        let timeJson = effective?.timeJson ?? table.timeJson
        let scheduleKey = "\(table.id)|\(effective?.id ?? -1)|\(timeJson)|\(scheduleEpoch)"

        return VStack(spacing: 0) {
            SettingsTopBar(title: L10n.format("edit_table_title"), onBack: handleBack)
            ScrollView {
                VStack(spacing: 14) {
                    Spacer().frame(height: 2)

                    // 基础信息
                    CardSection(title: L10n.format("edit_table_basic_info")) {
                        VStack(spacing: 12) {
                            FieldTextField(text: $name, label: L10n.format("edit_table_name"))
                            // 学期开始日期: 文本 + 日历图标弹原生 DatePicker(与导入确认弹窗同款组件)。
                            //   ← Android DatePickerField(value, onValueChange, label, isError)
                            DatePickerField(
                                value: startDate,
                                onValueChange: { startDate = $0 },
                                label: L10n.format("edit_table_start_date"),
                                isError: error != nil,
                                fillsWidth: true)
                            // 周数 ← Android 数字 TextField: 过滤非数字、任意值, 保存 toIntOrNull ?: 20
                            // (原 Stepper 1...60 硬顶 — 超出 60 的课表在 iOS 无法保存, 已对齐语义)
                            FieldTextField(text: $maxWeekText,
                                           label: L10n.format("edit_table_max_week"),
                                           keyboardType: .numberPad)
                                .onChange(of: maxWeekText) { newValue in
                                    // ← Android onValueChange = it.filter { ch.isDigit() }
                                    //   isDigit() = Unicode Nd(十进制数字); Swift isNumber 含
                                    //   No/Nl(² ½ 之类), 会让这类字符混进文本 → Int() 解析失败
                                    //   → 静默回落 20。按 unicodeScalars 过 decimalDigits
                                    //   (Nd) 精确对齐; Nd 全在 BMP, 标量级过滤 == Char 级过滤。
                                    maxWeekText = String(newValue.unicodeScalars
                                        .filter { CharacterSet.decimalDigits.contains($0) })
                                }
                        }
                    }
                    .onAppear { enterSession(table: table) }

                    // 节次时间表(可折叠)
                    VStack(spacing: 0) {
                        Button {
                            withAnimation { timeSlotsExpanded.toggle() }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 0) {   // ← Android Column 默认无间距
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
                                    .font(.system(size: 24))   // ← Android ExpandMore Icon 默认 24dp
                                    .foregroundColor(colors.onSurfaceVariant)
                                    .rotationEffect(.degrees(timeSlotsExpanded ? 180 : 0))
                            }
                            .padding(16)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(SleepyButtonStyle())
                        .accessibilityIdentifier("edit_table_slots_header")

                        if timeSlotsExpanded {
                            // v1.0.56 T6: 第三 Tab「作息表」= 原独立换绑卡收编于此(卡已拆,
                            // 未绑定/选中语义零变化, pendingBind 保存链原样)
                            TimeSlotEditor(
                                rows: slotRows,
                                onRowsChange: { newRows in
                                    slotRows = newRows
                                    // 甲案 §2.1: 节次编辑即草稿变化 — 同步进会话状态;
                                    // 策略已登记时会自动作废(invariant ⑤, 下次保存重弹)
                                    if let effective = effective {
                                        var draft = effective
                                        draft.timeJson = TimeTableUtils.buildTimeJsonFromRows(newRows)
                                        draft.nodesPerDay = max(newRows.count, 1)
                                        editState?.updateDraft(draft)
                                        syncPendingPolicy()
                                    }
                                },
                                smartConfig: smartConfig,
                                onSmartConfigChange: { newCfg in
                                    smartConfig = newCfg
                                    // 甲案 §2.1: 自动模式配置也属作息草稿 — 变化即同步+旧策略作废
                                    if let effective = effective {
                                        var draft = effective
                                        draft.smartConfigJson = encodeSmartConfig(newCfg)
                                        draft.nodesPerDay = max(slotRows.count, 1)
                                        editState?.updateDraft(draft)
                                        syncPendingPolicy()
                                    }
                                },
                                periodTableOptions: allPeriodTables.map {
                                    PeriodTableOption(id: $0.id, name: $0.name, nodesPerDay: $0.nodesPerDay)
                                },
                                selectedPeriodTableId: pendingBind,
                                onSelectPeriodTable: { pendingBind = $0 })
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

                    // 甲案 §4.2: 待执行提醒 — 登记策略后常驻; 「修改」重弹三选项(草稿不丢);
                    // 作息草稿再变 → 策略自动作废(updateDraft 内), Banner 随 NONE 消失。
                    if pendingPolicy != .none {
                        PendingPolicyBanner(policy: pendingPolicy, onModify: {
                            // ← Android: showConflictSheet && effectivePeriodTable != null 才渲染弹窗
                            guard let effective = effective else { return }
                            boundCount = tablesBoundToCount(effective.id)
                            showConflictSheet = true
                        })
                    }

                    // 保存
                    Button(action: { save(table: table, effective: effective) }) {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 24))   // ← Android Check Icon 默认 24dp
                            Text(L10n.format("edit_table_save"))
                                .font(.system(size: 14, weight: .medium))   // ← labelLarge 14 Medium
                        }
                        .foregroundColor(colors.onPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(colors.primary)
                        .cornerRadius(SleepyShapes.large)
                    }
                    .buttonStyle(SleepyButtonStyle())
                    .accessibilityIdentifier("edit_table_save")

                    // 删除(新建未保存的表不显示)
                    if pendingNewTableId == nil {
                        Button(action: { showDeleteConfirm = true }) {
                            HStack(spacing: 8) {
                                Image(systemName: "trash")
                                    .font(.system(size: 24))   // ← Android Delete Icon 默认 24dp
                                Text(L10n.format("edit_table_delete"))
                                    .font(.system(size: 14, weight: .medium))   // ← labelLarge 14 Medium
                            }
                            .foregroundColor(colors.onErrorContainer)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(colors.errorContainer)
                            .cornerRadius(SleepyShapes.large)
                        }
                        .buttonStyle(SleepyButtonStyle())
                        .accessibilityIdentifier("edit_table_delete")
                    }

                    Spacer().frame(height: 28)
                }
                .padding(.horizontal, 16)
            }
        }
        .background(colors.background)
        .onChange(of: table.id) { _ in enterSession(table: table) }
        // ← Android remember(table.id, table.periodTableId): 绑定列被外部改动(如撤回)
        //   时仅重播选择器初值 pendingBind, 不重建整个会话
        .onChange(of: table.periodTableId) { _ in pendingBind = table.periodTableId }
        .onChange(of: scheduleKey) { _ in reloadSchedule(table: table, effective: effective) }
        .alert(L10n.format("edit_table_delete_confirm"), isPresented: $showDeleteConfirm) {
            Button(L10n.format("delete"), role: .destructive) {
                showDeleteConfirm = false
                viewModel.deleteTable(table.id)
                onDeleted()
            }
            Button(L10n.format("cancel"), role: .cancel) {}
        } message: {
            // 防呆: 删表=连带删全部课程, 明示数量让用户知道要失去多少数据
            let courseCount = viewModel.state.courses.count
            Text(courseCount == 0
                 ? L10n.format("edit_table_delete_msg", table.name)
                 : L10n.format("edit_table_delete_msg_count", table.name, courseCount))
        }
        // issue#40 §5.3: 换绑确认 — 换绑后本课表按新节次表解释节次时间, 自定义时间课程不受影响
        .alert(L10n.format("period_table_bind_preview_title"), isPresented: $showRebindConfirm) {
            Button(L10n.format("period_table_preview_confirm")) { confirmRebind(table: table) }
            Button(L10n.format("cancel"), role: .cancel) { pendingRebind = nil }
        } message: {
            Text(L10n.format("period_table_bind_preview_body"))
        }
        // 甲案 §4.1: 三选项 BottomSheet — onSelect 只登记策略不写库(§2.2 invariant ③);
        // 「取消」/点外部 = 撤销本次作息改动, 其他字段草稿保留(§2.2 invariant ⑥):
        // 恢复草稿 + 作废策略 + scheduleEpoch 自增让 slotRows/smartConfig 回到库中真值。
        // ← Material3 ModalBottomSheet(skipPartiallyExpanded=true, onDismissRequest=onCancel):
        //   iOS sheet 本就全高展开; 下拉/点外部关闭走 onDismiss = 同一取消语义。
        .sheet(isPresented: $showConflictSheet, onDismiss: {
            if !conflictSheetResolved {
                editState?.cancelPolicy()
                pendingPolicy = .none
                scheduleEpoch += 1
            }
            conflictSheetResolved = false
        }) {
            if let effective = effective {
                ScheduleConflictBottomSheet(
                    periodTableName: effective.name,
                    boundTableCount: boundCount,
                    onSelect: { policy in
                        conflictSheetResolved = true
                        showConflictSheet = false
                        editState?.selectPolicy(policy)
                        pendingPolicy = policy
                    },
                    onCancel: {
                        conflictSheetResolved = true
                        showConflictSheet = false
                        editState?.cancelPolicy()
                        pendingPolicy = .none
                        scheduleEpoch += 1
                    })
            }
        }
    }

    private func handleBack() {
        if pendingNewTableId != nil { onDiscardPending() } else { onDismiss() }
    }

    // MARK: - 会话状态 (← Android remember(table.id) 族)

    /// 进入/切换课表时重建整套会话状态(← Android remember(table.id) + startEditSession)。
    private func enterSession(table: TimeTableEntity) {
        guard loadedTableId != table.id || editState == nil else { return }
        loadedTableId = table.id
        name = table.name
        startDate = table.startDate
        maxWeekText = String(table.maxWeek)
        error = nil
        // issue#40: pendingBind 初始 = table.periodTableId
        // (全部作息表 = viewModel.allPeriodTables 实时源, 见 allPeriodTables 计算属性,
        //  不再进会话拍快照)
        pendingBind = table.periodTableId
        pendingRebind = nil
        showRebindConfirm = false
        // 程序化关 sheet: 先置 resolved 抑制 onDismiss 的取消语义(onDismiss 在关闭动画
        // 完成后才回调, 那时会话已重建 — 不能让旧 sheet 的关闭动新会话的策略/epoch)
        conflictSheetResolved = true
        pendingRebindTable = nil
        pendingRebindPeriod = nil
        showConflictSheet = false
        boundCount = 0
        scheduleEpoch = 0
        // 甲案: 会话重建 — ← Android remember(table.id) { viewModel.startEditSession(...) }:
        // 走 VM 注册(返回对象入 editStates[tableId]), 执行策略的
        // viewModel.executePolicyAndSave 按 tableId 取回同一对象 — 屏外(如撤回页)查
        // hasPendingPolicy 也读到同一会话。original = 进入时刻实际生效作息快照
        // (绑定 → VM 水合结果; 未绑定 → null)。旧会话残留策略一并作废。
        editState = viewModel.startEditSession(
            tableId: table.id,
            originalEffectiveSchedule: table.periodTableId != nil
                ? viewModel.state.effectivePeriodTable : nil)
        pendingPolicy = .none
        // schedule 域(slotRows/smartConfig)按新键重载 — 有效表与 body 同一解析口径
        loadedScheduleKey = nil
        reloadSchedule(table: table,
                       effective: resolveEffectivePeriodTable(from: viewModel.state))
    }

    /// ← Android remember(table.id, effective?.id, timeJson, scheduleEpoch):
    ///   键变即从有效来源重建 slotRows + smartConfig。
    private func reloadSchedule(table: TimeTableEntity, effective: PeriodTableEntity?) {
        let timeJson = effective?.timeJson ?? table.timeJson
        let key = "\(table.id)|\(effective?.id ?? -1)|\(timeJson)|\(scheduleEpoch)"
        guard loadedScheduleKey != key else { return }
        loadedScheduleKey = key
        slotRows = TimeTableUtils.parseTimeSlotRows(timeJson)
        // issue#23 Task 4: 已存配置仍能 derive 出当前行 → 原样保留; 否则从当前行重推断;
        // 行不可推断 → 最简默认兜底(旧行为)。
        let stored = decodeSmartPeriodConfig(effective?.smartConfigJson ?? table.smartConfigJson)
        smartConfig = resolveAutoPeriodConfig(rows: slotRows, stored: stored)
            ?? SmartPeriodConfig(
                startTime: (slotRows.first?.start).flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 } ?? "08:00",
                totalPeriods: max(slotRows.count, 1))
    }

    private func syncPendingPolicy() {
        pendingPolicy = editState?.pendingSchedulePolicy ?? .none
    }

    // MARK: - 保存四分支链 (← Android 保存按钮 onClick 全链)

    /// ← Kotlin String.matches(Regex): 全串匹配。.anchored 从左端起, 再校验命中区间
    ///   == 整串尾端 —— 比 `^…$` + range(of:) 严格: ICU 的 `$` 允许串尾换行(实测
    ///   "2026-09-01\n" 旧写法判 true), Kotlin matches() 判 false。
    private func matchesFull(_ s: String, _ pattern: String) -> Bool {
        s.range(of: pattern, options: [.regularExpression, .anchored]) == s.startIndex..<s.endIndex
    }

    private func save(table: TimeTableEntity, effective: PeriodTableEntity?) {
        let maxWeek = Int(maxWeekText) ?? 20
        // ← Android startDate.matches(Regex("\\d{4}-\\d{2}-\\d{2}")) 全串匹配
        let dateOK = matchesFull(startDate, #"\d{4}-\d{2}-\d{2}"#)
        let timeFmtOK = slotRows.allSatisfy {
            matchesFull($0.start, #"\d{2}:\d{2}"#) && matchesFull($0.end, #"\d{2}:\d{2}"#)
        }
        let orderOK = slotRows.allSatisfy { $0.start < $0.end }
        guard dateOK && timeFmtOK && orderOK else {
            error = L10n.format("edit_table_validation_error")
            return
        }
        // 绑定保持不变时, 有效作息数据尚未加载 = 流还在初始化, 禁止把过期
        // 兼容列当真值写回共享作息表; 用户主动改绑(含解绑)时编辑区已切到
        // 目标表/本表数据, 不受此闸限制。
        let bindChanged = pendingBind != table.periodTableId
        if !bindChanged && table.periodTableId != nil && effective == nil {
            error = L10n.format("edit_table_period_loading")
            return
        }
        error = nil
        let smartConfigJson = encodeSmartConfig(smartConfig)
        let newTimeJson = TimeTableUtils.buildTimeJsonFromRows(slotRows)
        var updated = table
        // ← Android name.ifBlank { table.name }: isBlank 含换行(工程 String 扩展),
        //   原 trimmingCharacters(in: .whitespaces) 漏 newline → "\n" 名会写库
        updated.name = name.isBlank ? table.name : name
        // ← Android DateUtils.normalizeStartDate(startDate)(同类实现, 取工程通用
        //   DateUtils 源, 与本屏其余工具调用同域; 原引 JwImportViewModel 副本跨域)
        updated.startDate = DateUtils.normalizeStartDate(startDate)
        updated.maxWeek = maxWeek
        updated.timeJson = newTimeJson
        updated.smartConfigJson = smartConfigJson

        if bindChanged && pendingBind != nil {
            // issue#40 §5.3: 换绑须先预览确认 — 弹换绑确认框, 确认才写;
            // 用户在编辑区对目标表的节次编辑一并暂存(确认时落 target period)
            pendingRebind = pendingBind
            showRebindConfirm = true
            pendingRebindTable = updated
            if let effective = effective {
                var period = effective
                period.timeJson = newTimeJson
                period.smartConfigJson = smartConfigJson
                period.nodesPerDay = max(slotRows.count, 1)
                pendingRebindPeriod = period
            } else {
                pendingRebindPeriod = nil
            }
            return
        }
        // 甲案 §2.2: 绑定共享作息表时改了作息 → 保存先过三选项闸门。
        // ①改了作息+无策略 → 弹窗(invariant ②; 选择后再改的策略已被
        //   updateDraft 自动作废, 自然落回此分支 = invariant ⑤ 重弹)
        // ②有策略(=选择后未再动作息) → 执行策略(invariant ④)
        if !bindChanged, let effective = effective, editState != nil {
            if editState!.hasScheduleChanged() && pendingPolicy == .none {
                boundCount = tablesBoundToCount(effective.id)
                showConflictSheet = true
                return
            }
            if pendingPolicy != .none {
                // ← Android: viewModel.executePolicyAndSave(tableId:editedTable:newTimeJson:
                //   smartConfigJson:nodesPerDay:onFinish) — 会话从 VM editStates 取回,
                //   全程 UndoManager 批内(§7 单撤回单元), 执行完清策略(invariant ④)
                viewModel.executePolicyAndSave(
                    tableId: table.id,
                    editedTable: updated,
                    newTimeJson: newTimeJson,
                    smartConfigJson: smartConfigJson,
                    nodesPerDay: max(slotRows.count, 1),
                    onFinish: onSaved)
                return
            }
        }
        // ← Android scope.launch { viewModel.updateTableMetadataAndBind / ...WithPeriodTable /
        //   updateTableRemappingCourses; onSaved() } — 写库统一经 VM(内部单事务触 repo)
        if bindChanged {
            // 解绑: 元数据+时间域(解绑后兼容列是真值)+periodTableId=null,
            // 单事务原子完成 — 课程行零改动(issue#40 §5.3)
            viewModel.updateTableMetadataAndBind(table: updated, periodTableId: nil)
        } else if let effective = effective {
            // 未改作息时保留元数据 + 共享作息表的单事务原子双写。
            // 改了作息的路径已在上面的三选项闸门处理; 走到这里的
            // hasScheduleChanged()==false, 内容与 X 等值, 等值写无差别。
            var period = effective
            period.timeJson = newTimeJson
            period.smartConfigJson = smartConfigJson
            period.nodesPerDay = max(slotRows.count, 1)
            viewModel.updateTableMetadataWithPeriodTable(table: updated, periodTable: period)
        } else {
            // issue#28 P3: timeJson 变了课程节次必须自适应(16→12 节后
            // 课程不能再停在 13-16 节)
            viewModel.updateTableRemappingCourses(updated)
        }
        onSaved()
    }

    /// ← Android viewModel.executePolicyAndSave 对应实现已收敛到 ScheduleViewModel
    ///   (startEditSession 注册会话 + editStates 取回 + UndoManager 批 + 三分支写库),
    ///   本屏只负责触发, 不再重复一份写库逻辑。

    /// issue#40 §5.3: 换绑确认弹窗「确认」= 元数据+换绑(+目标作息内容)单事务写回;
    /// 无暂存元数据时退化为纯 bindPeriodTable(只写 periodTableId, 课程行零改动)。
    private func confirmRebind(table: TimeTableEntity) {
        let targetId = pendingRebind
        pendingRebind = nil
        showRebindConfirm = false
        let metadata = pendingRebindTable
        let periodContent = pendingRebindPeriod
        pendingRebindTable = nil
        pendingRebindPeriod = nil
        guard let targetId = targetId else { return }
        if let metadata = metadata {
            viewModel.updateTableMetadataAndBind(table: metadata,
                                                 periodTableId: targetId,
                                                 periodContent: periodContent)
        } else {
            viewModel.bindPeriodTable(timeTableId: table.id, periodTableId: targetId)
        }
        onSaved()
    }

    /// 甲案 §4.1: 弹窗「另有 N 张课表绑定」提示 — 绑定到指定作息表的课表数。
    /// ← Android viewModel.repoTablesBoundToCount(同语义, 经 VM 触库)。
    private func tablesBoundToCount(_ periodTableId: Int64) -> Int {
        return viewModel.repoTablesBoundToCount(periodTableId: periodTableId)
    }

    /// ← Android runCatching { Json.encodeToString(cfg) }.getOrDefault("")
    private func encodeSmartConfig(_ cfg: SmartPeriodConfig) -> String {
        guard let data = try? JSONEncoder().encode(cfg),
              let json = String(data: data, encoding: .utf8) else { return "" }
        return json
    }
}

// ← CardSection
private struct CardSection<Content: View>: View {
    @Environment(\.localWakeUpColors) private var colors
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(colors.onSurface)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.surfaceContainer)
        .cornerRadius(SleepyShapes.extraLarge)
    }
}

// M3 OutlinedTextField 等价
struct FieldTextField: View {
    @Environment(\.localWakeUpColors) private var colors
    @Binding var text: String
    let label: String
    var placeholder: String = ""
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        TextField(placeholder.isEmpty ? label : placeholder, text: $text)
            .keyboardType(keyboardType)
            .font(.system(size: 16))
            .padding(.horizontal, 16)   // ← M3 filled TextField 内边距 16dp(原 12)
            .padding(.vertical, 10)
            .frame(minHeight: 56, alignment: .bottom)   // ← M3 TextField MinHeight 56dp, 文字贴底(原约 40)
            .background(colors.surfaceContainerLowest)
            .cornerRadius(SleepyTheme.fieldShape)
            // ← Android filled TextField, 无描边
            .accessibilityIdentifier("field_\(label)")   // ← G5: 字段锚点(label 原文)
            .overlay(alignment: .leading) {
                if !placeholder.isEmpty {
                    // label 浮动到左上(M3 风格近似: 前缀标签)
                    Text(label)
                        .font(.system(size: 12)) // ← M3 floating label ≈ bodySmall 12
                        .foregroundColor(colors.onSurfaceVariant)
                        .padding(.leading, 12)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .offset(y: -22)
                }
            }
    }
}
