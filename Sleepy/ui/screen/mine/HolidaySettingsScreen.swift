// HolidaySettingsScreen.swift — ← ui/screen/mine/HolidaySettingsScreen.kt
// 节假日与补班日设置页: 年份切换 / 数据源卡片(加载·失败·重试·刷新) /
// 三个灰显开关 / issue#44 调休说明卡(卡内课表切换用局部 activeTableId, 不动全局选中) /
// 灰显样式 chips / 每个放假日段一张 HolidayTransferCard(逐日→补班日下拉) /
// 失效映射 HolidayOrphanCard / 已删除区(可恢复) / 添加自定义日期。
// 网络段+用户覆盖段合并逻辑在 HolidayRangeOps(纯函数, ← HolidayRange.kt)。

import SwiftUI
import WidgetKit

private enum HolidayUiState {
    case loading
    case failed
    case empty
    case loaded([HolidayEntry])
}

/// 弹窗编辑目标: isNew=true 添加模式; 网络段派生目标会预填 sourceKey ← EditingTarget
private struct EditingTarget: Identifiable {
    let range: HolidayRange
    let isNew: Bool
    var id: String { (isNew ? "new:" : "edit:") + range.id }
}

private let MIN_YEAR = 2005
private let MAX_YEAR = 2049

struct HolidaySettingsScreen: View {
    @Environment(\.localWakeUpColors) private var colors
    let onDismiss: () -> Void
    /// 进入本页时全局选中的课表 id ← Android tableId: Long? = null;
    /// nil = 无课表(调休映射不落盘, 说明卡提示"请先创建课表")。
    var tableId: Int64? = nil
    /// 当前选中表映射变化后的课表页刷新回调 ← viewModel.refreshTransfer(); 接线归集成者。
    var refreshTransfer: (() -> Void)? = nil

    private let prefs = AppPrefs.shared

    @State private var year: Int = Calendar.gregorianCST.component(.year, from: Date())
    @State private var holidayGrey: Bool = AppPrefs.shared.isHolidayGreyHoliday()
    @State private var weekendGrey: Bool = AppPrefs.shared.isHolidayGreyWeekend()
    @State private var ignoreWorkday: Bool = AppPrefs.shared.isHolidayIgnoreWorkday()
    @State private var style: String = AppPrefs.shared.getHolidayStyle()
    @State private var state: HolidayUiState = .loading
    @State private var overrides: [HolidayRange] = AppPrefs.shared.getHolidayRanges()
    @State private var editing: EditingTarget? = nil
    @State private var loadTask: Task<Void, Never>? = nil
    // issue#44 调休映射(按课表, 放假日→补班日): 空 = 该放假日按自然星期取课。
    // 卡内课表切换用局部 activeTableId — 只切"正在编辑哪张表", 不动全局选中课表。
    @State private var activeTableId: Int64? = nil
    @State private var transfers: [HolidayTransferEntry] = []
    @State private var tables: [TimeTableEntity] = []

    private func reload() { overrides = prefs.getHolidayRanges() }

    /// activeTableId 变化 → 重拉该表映射 ← remember(activeTableId)
    private func reloadTransfers() {
        if let id = activeTableId {
            transfers = prefs.getHolidayTransfers(id)
        } else {
            transfers = []
        }
    }

    private func loadTablesOnce() {
        if !tables.isEmpty { return }
        tables = ((try? ScheduleRepository(AppDatabase.getShared()).getAllTables()) ?? [])
    }

    /// 设/清某放假日的"调到哪天上课"; 表 id 为空不落盘(卡已隐藏, 此为双保险) ← saveTransfer
    private func saveTransfer(sourceDate: Date, targetDate: Date?, segmentId: String) {
        guard let id = activeTableId else { return }
        prefs.updateHolidayTransfer(id, sourceDate: sourceDate, targetDate: targetDate, segmentId: segmentId)
        transfers = prefs.getHolidayTransfers(id)
        // issue#44: 映射是按表存的, 只有改到当前选中的那张表才需要刷新课表页/widget/闹钟
        if id == tableId {
            refreshTransfer?()
            Task.detached(priority: .background) {
                WidgetCenter.shared.reloadAllTimelines() // ← WidgetUpdater.notifyDataChanged
                ReminderRescheduler.shared.request()
            }
        }
    }

    /// 保存(新增或替换同 id)一段覆盖 ← saveRange
    private func saveRange(_ range: HolidayRange) {
        var next = overrides.filter { $0.id != range.id }
        next.append(range)
        prefs.setHolidayRanges(next)
        reload()
        ReminderRescheduler.shared.request()
    }

    /**
     * 删除一段: 段 id 在 overrides 里 → 直接移除;
     * 是网络段(聚合生成、无对应覆盖) → 写 type=REMOVED + sourceKey 的覆盖挂接该网络段。← deleteRange
     */
    private func deleteRange(_ range: HolidayRange) {
        let known = overrides.contains { $0.id == range.id }
        var next = overrides.filter { $0.id != range.id }
        if !known {
            next.append(HolidayRange(
                id: HolidayRangeOps.newId(), name: range.name,
                startDate: range.startDate, endDate: range.endDate,
                type: HolidayRangeOps.REMOVED,
                sourceKey: networkKeyOf(range.type, range.startDate)
            ))
        }
        prefs.setHolidayRanges(next)
        reload()
        ReminderRescheduler.shared.request()
    }

    /// 恢复默认: 移除该 id 的覆盖(含 REMOVED 型), 网络段随之回来 ← restoreRange
    private func restoreRange(_ range: HolidayRange) {
        prefs.setHolidayRanges(overrides.filter { $0.id != range.id })
        reload()
        ReminderRescheduler.shared.request()
    }

    private func load(_ targetYear: Int, force: Bool = false) {
        loadTask?.cancel()
        loadTask = Task {
            state = .loading
            let entries: [HolidayEntry]
            if force {
                entries = await HolidayManager.refreshYearEntries(targetYear)
            } else {
                entries = await HolidayManager.getYearEntries(targetYear)
            }
            if Task.isCancelled { return }
            await MainActor.run {
                overrides = prefs.getHolidayRanges()
                if entries.isEmpty && HolidayManager.isYearFetchFailed(targetYear) {
                    state = .failed
                } else {
                    state = .loaded(entries)
                }
                if force { ReminderRescheduler.shared.request() }
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            SettingsTopBar(title: L10n.format("holiday_page_title"), onBack: onDismiss)
            ScrollView {
                VStack(spacing: 16) {
                    yearSwitcher
                    dataSourceCard
                    togglesCard
                    makeupCard
                    styleCard

                    if case .loaded(let entries) = state {
                        segmentSections(entries)
                    }
                }
                .padding(16)
            }
        }
        .background(colors.background)
        .onAppear {
            loadTablesOnce()
            if activeTableId == nil { activeTableId = tableId }
            reloadTransfers()
            load(year)
        }
        .onChange(of: year) { y in load(y) }
        .onChange(of: activeTableId) { _ in reloadTransfers() }
        .sheet(item: $editing) { t in
            HolidayRangeEditDialog(
                target: t.range,
                isNew: t.isNew,
                onDismiss: { editing = nil },
                onSave: { range in
                    saveRange(range)
                    editing = nil
                },
                onDelete: { range in
                    deleteRange(range)
                    editing = nil
                }
            )
            .sheetDetents([.medium, .large])
        }
    }

    // ← 年份切换行(ChevronLeft / 年份 / ChevronRight)。
    //   Android horizontalArrangement = Arrangement.Center: 两箭头紧贴年份文字两侧
    //   (文字水平 padding 16), 整行居中 — 不顶卡片两边。
    private var yearSwitcher: some View {
        HStack(spacing: 0) {
            Button {
                if year > MIN_YEAR { year -= 1 }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(year > MIN_YEAR ? colors.onSurface : colors.onSurfaceVariant.opacity(0.4))
            }
            .buttonStyle(SleepyButtonStyle())
            .accessibilityLabel(L10n.format("holiday_year_prev"))
            .disabled(year <= MIN_YEAR)

            Text(String(year))
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(colors.onSurface)
                .padding(.horizontal, 16)

            Button {
                if year < MAX_YEAR { year += 1 }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(year < MAX_YEAR ? colors.onSurface : colors.onSurfaceVariant.opacity(0.4))
            }
            .buttonStyle(SleepyButtonStyle())
            .accessibilityLabel(L10n.format("holiday_year_next"))
            .disabled(year >= MAX_YEAR)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .background(colors.surfaceContainer)
        .cornerRadius(SleepyShapes.large)
    }

    // ← 数据源卡(用户 2026-09-04): 标题+URL 同行, 刷新=图标(语言无关, 不随文案伸缩)。
    //   Loading 态图标位转圈占位(行高稳定); Failed/Empty 提示行单独挂卡底(信息行不可省)。
    private var dataSourceCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text(L10n.format("holiday_data_source"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(colors.onSurface)
                Text(L10n.format("holiday_source_label"))
                    .font(.system(size: 12))
                    .foregroundColor(colors.onSurfaceVariant)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if case .loading = state {
                    // 图标位转圈占位 — 行高稳定
                    ProgressView()
                        .tint(colors.primary)
                        .controlSize(.small)
                        .frame(width: 36, height: 36)
                } else {
                    // 刷新=图标(与 Android Icons.Outlined.Refresh 同位): failed/empty/loaded 均可点
                    Button {
                        load(year, force: true)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 20))
                            .foregroundColor(colors.onSurfaceVariant)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(SleepyButtonStyle())
                    .accessibilityIdentifier("holiday_refresh")
                    .accessibilityLabel(L10n.format("holiday_data_refresh"))
                }
            }
            if case .failed = state {
                Text(L10n.format("holiday_data_failed"))
                    .font(.system(size: 12))
                    .foregroundColor(colors.error)
                    .padding(.bottom, 6)
            } else if case .empty = state {
                Text(L10n.format("holiday_data_empty"))
                    .font(.system(size: 12))
                    .foregroundColor(colors.onSurfaceVariant)
                    .padding(.bottom, 6)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.surfaceContainer)
        .cornerRadius(SleepyShapes.large)
    }

    // ← 三个灰显开关卡
    private var togglesCard: some View {
        VStack(spacing: 4) {
            SettingToggleRow(
                label: L10n.format("settings_holiday_holiday"),
                subtitle: L10n.format("settings_holiday_holiday_sub"),
                checked: holidayGrey
            ) {
                holidayGrey = $0
                prefs.setHolidayGreyHoliday($0)
            }
            divider
            SettingToggleRow(
                label: L10n.format("settings_holiday_weekend"),
                subtitle: L10n.format("settings_holiday_weekend_sub"),
                checked: weekendGrey
            ) {
                weekendGrey = $0
                prefs.setHolidayGreyWeekend($0)
            }
            divider
            SettingToggleRow(
                label: L10n.format("settings_holiday_workday"),
                subtitle: L10n.format("settings_holiday_workday_sub"),
                checked: ignoreWorkday
            ) {
                ignoreWorkday = $0
                prefs.setHolidayIgnoreWorkday($0)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(colors.surfaceContainer)
        .cornerRadius(SleepyShapes.large)
    }

    // ← issue#44 调休说明卡: 说明 + 卡内课表切换(局部 activeTableId, 不动全局选中)
    private var makeupCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.format("holiday_makeup_title"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(colors.onSurface)
            Text(L10n.format(tableId == nil ? "holiday_makeup_no_table" : "holiday_makeup_subtitle"))
                .font(.system(size: 12))
                .foregroundColor(colors.onSurfaceVariant)
            Text(L10n.format("holiday_mapping_explanation"))
                .font(.system(size: 12))
                .foregroundColor(colors.onSurfaceVariant)
            // 只有带着已选课表进入且存在多张表才渲染切换器 — 与 Android 条件一致
            if tableId != nil && tables.count > 1 {
                Spacer().frame(height: 4)
                SegmentedSwitcher(
                    options: tables.map { ($0.id, $0.name) },
                    selected: activeTableId ?? tableId ?? 0,
                    onSelect: { activeTableId = $0 },
                    // 嵌进 surfaceContainer 卡片同色隐形 → 降一级(共享组件注释同款)
                    containerColor: colors.surfaceContainerHighest
                )
                .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.surfaceContainer)
        .cornerRadius(SleepyShapes.large)
    }

    // ← 灰显样式卡: 标题行右贴 segmented tabs — 与通用设置页各平铺卡同款(用户 2026-09-04)
    private var styleCard: some View {
        SettingsFlatCard(
            title: L10n.format("settings_holiday_style"),
            options: [
                L10n.format("settings_holiday_style_grey"),
                L10n.format("settings_holiday_style_strikethrough")
            ],
            selectedIndex: Binding(
                get: { style == "strikethrough" ? 1 : 0 },
                set: { idx in
                    let next = idx == 1 ? "strikethrough" : "grey"
                    guard next != style else { return }
                    style = next
                    prefs.setHolidayStyle(next)
                }
            ),
            onSelect: { _ in }
        )
    }

    /// 覆盖变化时基于原始网络数据即时重合并, 不重新走网络 ← Loaded 分支。
    /// Android 1.0.61 不再渲染"法定节假日/补班日"两列清单 — 放假日段直接渲染
    /// HolidayTransferCard(逐日映射行), 补班日数据只作为下拉候选; 无节卡时不显示孤儿卡。
    @ViewBuilder
    private func segmentSections(_ entries: [HolidayEntry]) -> some View {
        let merged = HolidayRangeOps.mergeSegments(entries, overrides)
        let userRangeIds = Set(overrides.map { $0.id })
        let holidaySegments = merged.active.filter { $0.type == HolidayManager.TYPE_PUBLIC_HOLIDAY }
        let workdaySegments = merged.active.filter { $0.type == HolidayManager.TYPE_TRANSFER_WORKDAY }
        // 候选 = 当年全部官方补班日(扁平全量, 升序, 去重) ← workdayDates flatMap…distinct().sorted()
        let workdayDates = Array(Set(workdaySegments.flatMap { datesInRange($0.startDate, $0.endDate) }))
            .sorted()

        if !holidaySegments.isEmpty {
            // issue#44 第二轮: 节卡树状视图 — 每个放假日段一张卡, 每行一个放假日 → 右侧下拉选补班日。
            ForEach(holidaySegments, id: \.id) { seg in
                HolidayTransferCard(
                    segment: seg,
                    transfers: transfers,
                    workdayDates: workdayDates,
                    onPick: { source, target in saveTransfer(sourceDate: source, targetDate: target, segmentId: seg.id) },
                    // 用户 2026-09-18 定稿: 每张节卡标题行最右编辑按钮 —
                    // 国务院数据段只许编辑持续时间(段起止), 走原 HolidayRangeEditDialog
                    onEditSegment: { editing = resolveEditTarget(seg, userRangeIds) }
                )
            }
            // 孤儿映射: sourceDate 已不在今年任何放假日段里(改年份/换数据源后残留)。
            // 不删 — 灰卡列出, 行尾"清除"手动处理 (用户决定 C1)
            let yearDates = Set(holidaySegments.flatMap { datesInRange($0.startDate, $0.endDate) })
            let orphanEntries = transfers
                .filter { HolidayTransferOps.isOrphanFor($0, yearDates) }
                .sorted { $0.sourceDate < $1.sourceDate }
            if !orphanEntries.isEmpty {
                HolidayOrphanCard(
                    entries: orphanEntries,
                    onClear: { source in saveTransfer(sourceDate: source, targetDate: nil, segmentId: "orphan") }
                )
            }
        }
        if !merged.removed.isEmpty {
            SectionHeader(title: L10n.format("holiday_removed_section"))
            HolidayRemovedCard(segments: merged.removed, onRestore: restoreRange)
        }

        Button {
            editing = EditingTarget(
                range: HolidayRange(
                    id: HolidayRangeOps.newId(),
                    name: "",
                    startDate: dateOf(year, 1, 1),
                    endDate: dateOf(year, 1, 1),
                    type: HolidayManager.TYPE_PUBLIC_HOLIDAY,
                    sourceKey: nil
                ),
                isNew: true
            )
        } label: {
            Text(L10n.format("holiday_add_entry"))
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(colors.onSecondaryContainer)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(colors.secondaryContainer)
                .cornerRadius(SleepyShapes.large)
        }
        .buttonStyle(SleepyButtonStyle())
        .accessibilityIdentifier("holiday_add_entry")
    }

    private var divider: some View {
        Rectangle()
            .fill(colors.outlineVariant.opacity(SleepyTheme.Alpha.hairline))
            .frame(height: 1)
    }
}

/// 网络段键: "holiday:<start>"/"workday:<start>", 与 HolidayRangeOps.mergeSegments 的命中规则一致
/// ← networkKeyOf
private func networkKeyOf(_ type: String, _ date: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: "Asia/Shanghai")
    return "\(type == HolidayManager.TYPE_TRANSFER_WORKDAY ? "workday" : "holiday"):\(f.string(from: date))"
}

/// 行点击 → 弹窗编辑目标。网络段(聚合生成的 id 不在 overrides 里)复制一份并
/// 立即补上 sourceKey, 保存/删除时即按该键整段挂接替换/删除, 不产生重复行。← resolveEditTarget
private func resolveEditTarget(_ segment: HolidayRange, _ userRangeIds: Set<String>) -> EditingTarget {
    if userRangeIds.contains(segment.id) {
        return EditingTarget(range: segment, isNew: false)
    }
    return EditingTarget(
        range: HolidayRange(
            id: segment.id, name: segment.name,
            startDate: segment.startDate, endDate: segment.endDate,
            type: segment.type,
            sourceKey: networkKeyOf(segment.type, segment.startDate)
        ),
        isNew: false
    )
}

/// 段日期展示: 单日 M/d, 跨日 M/d – M/d ← segmentDateLabel
private func segmentDateLabel(_ seg: HolidayRange) -> String {
    if seg.startDate == seg.endDate {
        return DateUtils.shortDateSlash(seg.startDate)
    }
    return "\(DateUtils.shortDateSlash(seg.startDate)) – \(DateUtils.shortDateSlash(seg.endDate))"
}

/// [start, end] 逐日序列 ← generateSequence(s) { if (it < end) it.plusDays(1) else null }
private func datesInRange(_ start: Date, _ end: Date) -> [Date] {
    var out: [Date] = []
    var cur = start
    let cal = Calendar.gregorianCST
    while cur <= end {
        out.append(cur)
        guard let nxt = cal.date(byAdding: .day, value: 1, to: cur) else { break }
        cur = nxt
    }
    return out
}

/// 星期几(1=周一 7=周日) ← date.dayOfWeek.value
private func dowOf(_ d: Date) -> Int { DateUtils.todayDayOfWeek(today: d) }

/// "M/d (周X)" ← dayNames[date.dayOfWeek.value - 1]
private func dayLabelSlash(_ d: Date) -> String {
    "\(DateUtils.shortDateSlash(d)) (\(DateUtils.localizedDay(dowOf(d))))"
}

private func dateOf(_ y: Int, _ m: Int, _ d: Int) -> Date {
    var c = DateComponents()
    c.year = y; c.month = m; c.day = d; c.hour = 12
    c.timeZone = TimeZone(identifier: "Asia/Shanghai")
    return Calendar(identifier: .gregorian).date(from: c) ?? Date()
}

/// 同一日(按天键)判等 — Date 锚定正午, 直接 == 也可, 保留 helper 语义 ← lastOrNull { it.sourceDate == date }
private func isSameDay(_ a: Date, _ b: Date) -> Bool {
    let cal = Calendar.gregorianCST
    return cal.isDate(a, inSameDayAs: b)
}

/**
 * issue#44 调休映射卡: 一个放假日段一张卡。每行 = 一个放假日 → 右侧灰圆角格。
 * 右侧下拉菜单固定三项: ① 当年所有官方补班日(扁平全量, 升序, 不分组/不禁用/不猜)
 * ② 无(清除)③ 其他日期…(弹系统 DatePicker)。
 * 同目标日互斥: 已在 AppPrefs.updateHolidayTransfer → withTargetExclusivity 落实。
 * UI 不禁用任何项, 不打扰用户操作。 ← HolidayTransferCard
 */
private struct HolidayTransferCard: View {
    @Environment(\.localWakeUpColors) private var colors
    let segment: HolidayRange
    let transfers: [HolidayTransferEntry]
    let workdayDates: [Date]
    let onPick: (Date, Date?) -> Void
    let onEditSegment: () -> Void

    var body: some View {
        let dates = datesInRange(segment.startDate, segment.endDate)
        VStack(alignment: .leading, spacing: 8) {
            // 标题行: 段名+起止日期 | 最右编辑按钮(编辑本段持续时间)
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(segment.name.isBlank ? DateUtils.shortDateSlash(segment.startDate) : segment.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(colors.onSurface)
                    Text(segmentDateLabel(segment))
                        .font(.system(size: 12))
                        .foregroundColor(colors.onSurfaceVariant)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // 标题行最右编辑按钮 — 底部"+"按钮才是新增自定义段入口
                Button(action: onEditSegment) {
                    Image(systemName: "pencil")
                        .font(.system(size: 16))
                        .foregroundColor(colors.onSurfaceVariant)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(SleepyButtonStyle())
                .accessibilityLabel(L10n.format("holiday_transfer_edit_segment"))
            }
            ForEach(dates, id: \.self) { date in
                HolidayTransferRow(
                    date: date,
                    // 后选覆盖前选 ← transfers.lastOrNull { it.sourceDate == date }
                    targetDate: transfers.last { isSameDay($0.sourceDate, date) }?.targetDate,
                    workdayDates: workdayDates,
                    onPick: { picked in onPick(date, picked) }
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.surfaceContainer)
        .cornerRadius(SleepyShapes.large)
    }
}

/**
 * 失效映射卡: 孤儿 entries 的收纳处 — sourceDate 已不在今年任何放假日段里
 * (用户改年份/删段/数据源变动后残留)。不自动删, 灰色列出 + 行尾"清除"手动处理。
 * ← HolidayOrphanCard
 */
private struct HolidayOrphanCard: View {
    @Environment(\.localWakeUpColors) private var colors
    let entries: [HolidayTransferEntry]
    let onClear: (Date) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.format("holiday_transfer_orphan_title"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(colors.onSurfaceVariant)
            Text(L10n.format("holiday_transfer_orphan_hint"))
                .font(.system(size: 12))
                .foregroundColor(colors.onSurfaceVariant)
            ForEach(entries, id: \.sourceDate) { entry in
                HStack(spacing: 0) {
                    Text("\(DateUtils.shortDateSlash(entry.sourceDate)) → \(dayLabelSlash(entry.targetDate))")
                        .font(.system(size: 14))
                        .foregroundColor(colors.onSurfaceVariant)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    // 清除走 secondaryContainer 色块 — 与恢复/删除同风格
                    Button {
                        onClear(entry.sourceDate)
                    } label: {
                        Text(L10n.format("holiday_transfer_clear"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(colors.onSecondaryContainer)
                            .padding(.horizontal, 14)
                            .frame(height: 48)
                            .background(colors.secondaryContainer)
                            .cornerRadius(SleepyShapes.large)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(SleepyButtonStyle())
                }
                .padding(.vertical, 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.surfaceContainer)
        .cornerRadius(SleepyShapes.large)
    }
}

/**
 * 调休映射行: 左 "M/d (周X)" → 右下拉格。
 * 用户 2026-09-18 五次定稿: 视觉 = Material3 ExposedDropdownMenuBox —
 * 右格即锚(日期不变、原地展开), iOS 用 Menu 呈现同款候选列表:
 * ① 当年全部官方补班日(升序) ② hairline 分隔 ③ 无 ④ 其他日期…(弹系统日期滚轮)。
 * ← HolidayTransferRow
 */
private struct HolidayTransferRow: View {
    @Environment(\.localWakeUpColors) private var colors
    let date: Date
    let targetDate: Date?
    let workdayDates: [Date]
    let onPick: (Date?) -> Void

    @State private var showDatePicker = false
    @State private var pickedOther: Date = Date()

    private var rightLabel: String {
        targetDate == nil ? "—" : dayLabelSlash(targetDate!)
    }

    /// 未设置 = surfaceContainerHighest/onSurfaceVariant; 已映射 = primaryContainer/onPrimaryContainer
    private var chipColor: Color { targetDate == nil ? colors.surfaceContainerHighest : colors.primaryContainer }
    private var chipContentColor: Color { targetDate == nil ? colors.onSurfaceVariant : colors.onPrimaryContainer }

    var body: some View {
        HStack(spacing: 0) {
            Text(dayLabelSlash(date))
                .font(.system(size: 16))
                .foregroundColor(colors.onSurface)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "arrow.right")
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(colors.onSurfaceVariant)
                .frame(width: 18, height: 18)
            Spacer().frame(width: 10)
            Menu {
                // ① 官方补班日(扁平全量, 升序, 不分组/不禁用/不猜)
                ForEach(workdayDates, id: \.self) { wd in
                    Button {
                        onPick(wd)
                    } label: {
                        Text(dayLabelSlash(wd))
                    }
                }
                Divider()
                // ② 无: 清除该日映射
                Button {
                    onPick(nil)
                } label: {
                    Text(L10n.format("holiday_makeup_unset"))
                }
                // ③ 其他日期: 弹系统 DatePicker
                Button {
                    pickedOther = date
                    showDatePicker = true
                } label: {
                    Text(L10n.format("holiday_transfer_pick_other"))
                }
            } label: {
                HStack(spacing: 0) {
                    Text(rightLabel)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(chipContentColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(chipContentColor)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(chipColor)
                .cornerRadius(SleepyShapes.medium)
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .frame(maxWidth: .infinity)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 6)
        // "其他日期…" → 系统日期滚轮确认 ← Android DatePickerDialog(ZoneId Asia/Shanghai)
        .sheet(isPresented: $showDatePicker) {
            makeupDatePicker
        }
    }

    private var makeupDatePicker: some View {
        VStack(spacing: 0) {
            DatePicker(
                "",
                selection: $pickedOther,
                displayedComponents: .date
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            HStack(spacing: 8) {
                Button {
                    showDatePicker = false
                } label: {
                    Text(L10n.format("cancel"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colors.onSecondaryContainer)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(colors.secondaryContainer)
                        .cornerRadius(SleepyShapes.medium)
                        .contentShape(Rectangle())
                }
                .buttonStyle(SleepyButtonStyle())
                Button {
                    showDatePicker = false
                    onPick(pickedOther)
                } label: {
                    Text(L10n.format("ok"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colors.onPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(colors.primary)
                        .cornerRadius(SleepyShapes.medium)
                        .contentShape(Rectangle())
                }
                .buttonStyle(SleepyButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
        .background(colors.surface)
        .cornerRadius(SleepyShapes.large)
        // iOS 15 无自定义 sheet detent, .large 全高 = 系统滚轮弹窗原生形态(兼容层同 GeneralSettingsScreen 用法)
        .sheetDetents([.large])
    }
}

// ← HolidayRemovedCard: 被用户删除的网络段, 行尾"恢复"移除覆盖使网络段回来
private struct HolidayRemovedCard: View {
    @Environment(\.localWakeUpColors) private var colors
    let segments: [HolidayRange]
    let onRestore: (HolidayRange) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                HStack {
                    Text(segment.name.isBlank ? DateUtils.shortDateSlash(segment.startDate) : segment.name)
                        .font(.system(size: 16))
                        .foregroundColor(colors.onSurfaceVariant)
                    Spacer()
                    Text(segmentDateLabel(segment))
                        .font(.system(size: 14))
                        .foregroundColor(colors.onSurfaceVariant)
                    Spacer().frame(width: 12)
                    // 恢复用 secondaryContainer 色块 — 与删除/刷新同风格, 禁悬空文字按钮
                    Button {
                        onRestore(segment)
                    } label: {
                        Text(L10n.format("holiday_restore"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(colors.onSecondaryContainer)
                            .padding(.horizontal, 14)
                            .frame(height: 48)
                            .background(colors.secondaryContainer)
                            .cornerRadius(SleepyShapes.large)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(SleepyButtonStyle())
                }
                .padding(.vertical, 6)
                // ← Android HorizontalDivider: outlineVariant @ hairline
                if index != segments.count - 1 {
                    Rectangle()
                        .fill(colors.outlineVariant.opacity(SleepyTheme.Alpha.hairline))
                        .frame(height: 1)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(colors.surfaceContainer)
        .cornerRadius(SleepyShapes.large)
    }
}

/**
 * 编辑/添加弹窗(起止日期范围段) ← HolidayRangeEditDialog。
 * target 为网络段时, 保存时补 sourceKey="holiday|workday:<首日>" 挂接替换该网络段。
 * 校验: start/end 均有效且 end >= start, 否则禁用保存并提示 holiday_date_invalid。
 *
 * iOS 原生化:
 *   - 起止日期 → native DatePicker(.compact) 双字段, 点击展开滚轮。
 *     Android 用自由文本 DatePickerField, end 可填出早于 start 的值 → 错误行出现;
 *     iOS 端不钳制 end 的范围(去掉 in: startDate...), 否则 endDate >= startDate 恒真,
 *     holiday_date_invalid 分支成为死代码 — 与 Android 校验路径保持等价可达。
 *   - 名称 → TextField (SwiftUI 已是原生, 不变)
 *   - 类型 → SegmentedSwitcher 二选一
 *   - 删除/取消/保存 → 自制色块按钮(与全 app 统一)
 */
private struct HolidayRangeEditDialog: View {
    @Environment(\.localWakeUpColors) private var colors
    let target: HolidayRange
    let isNew: Bool
    let onDismiss: () -> Void
    let onSave: (HolidayRange) -> Void
    let onDelete: (HolidayRange) -> Void

    @State private var name: String
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var type: String

    init(target: HolidayRange, isNew: Bool,
         onDismiss: @escaping () -> Void,
         onSave: @escaping (HolidayRange) -> Void,
         onDelete: @escaping (HolidayRange) -> Void) {
        self.target = target
        self.isNew = isNew
        self.onDismiss = onDismiss
        self.onSave = onSave
        self.onDelete = onDelete
        _name = State(initialValue: target.name)
        _startDate = State(initialValue: target.startDate)
        _endDate = State(initialValue: target.endDate)
        _type = State(initialValue: target.type)
    }

    private var datesValid: Bool { endDate >= startDate }

    var body: some View {
        // ← Android AlertDialog text Column spacedBy(12)
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.format(isNew ? "holiday_add_title" : "holiday_edit_title"))
                .font(.system(size: 24)) // ← Android AlertDialog headlineSmall 24
                .foregroundColor(colors.onSurface)
                .frame(maxWidth: .infinity, alignment: .leading)

            // ← native iOS DatePicker(.compact): 点击展开滚轮, 系统级体验
            //   手动 HStack 替代 LabeledContent (iOS 16+), 保持 iOS 15.6 兼容。
            //   end 不钳制下限 — 允许 end < start, 走下方 holiday_date_invalid 提示
            //   (Android DatePickerField 同样允许填出倒挂区间并报错, 校验路径等价)。
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(L10n.format("holiday_name_label_date"))
                        .font(.system(size: 14))
                        .foregroundColor(colors.onSurfaceVariant)
                    Spacer()
                    DatePicker("", selection: $startDate, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                }
                HStack {
                    Text(L10n.format("holiday_name_label_end"))
                        .font(.system(size: 14))
                        .foregroundColor(datesValid ? colors.onSurfaceVariant : colors.error)
                    Spacer()
                    DatePicker("", selection: $endDate, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                }
            }
            .padding(.vertical, 4)

            if !datesValid {
                Text(L10n.format("holiday_date_invalid"))
                    .font(.system(size: 12))
                    .foregroundColor(colors.error)
            }

            TextField(L10n.format("holiday_name_label"), text: $name)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(colors.surfaceContainer)
                .cornerRadius(SleepyTheme.fieldShape)

            // ← SegmentedSwitcher 全宽(与设置页 Tab 同款, 替代散排 chip) — Android 1.0.51
            SegmentedSwitcher(
                options: [(0, L10n.format("holiday_type_holiday")),
                          (1, L10n.format("holiday_type_workday"))],
                selected: type == HolidayManager.TYPE_PUBLIC_HOLIDAY ? 0 : 1,
                onSelect: { idx in
                    type = idx == 0 ? HolidayManager.TYPE_PUBLIC_HOLIDAY
                                    : HolidayManager.TYPE_TRANSFER_WORKDAY
                }
            )

            if !isNew {
                // 删除走 errorContainer 色块 — 纯色块禁描边规则。
                // 弹窗不设"恢复": 已保存段删除=移除覆盖(可从已删除区恢复), 网络段删除=REMOVED 覆盖(同入口恢复);
                // 弹窗内两个按钮会做同一件事, 恢复入口统一收敛到"已删除"区块。
                Button {
                    onDelete(target)
                } label: {
                    Text(L10n.format("holiday_delete_range"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colors.onErrorContainer)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(colors.errorContainer)
                        .cornerRadius(SleepyShapes.large)
                        .contentShape(Rectangle())
                }
                .buttonStyle(SleepyButtonStyle())
            }

            HStack(spacing: 8) {
                Button(action: onDismiss) {
                    Text(L10n.format("cancel"))
                        .font(.system(size: 14, weight: .medium)) // ← Android TextButton labelLarge 14sp Medium
                        .foregroundColor(colors.onSurfaceVariant)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(SleepyButtonStyle())
                Button {
                    onSave(HolidayRange(id: target.id,
                                        name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                        startDate: startDate, endDate: endDate,
                                        type: type, sourceKey: target.sourceKey))
                } label: {
                    Text(L10n.format("save"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(datesValid ? colors.onPrimary : colors.onPrimary.opacity(0.4))
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(datesValid ? colors.primary : colors.primary.opacity(0.3))
                        .cornerRadius(SleepyShapes.medium)
                        .contentShape(Rectangle())
                }
                .buttonStyle(SleepyButtonStyle())
                .disabled(!datesValid)
            }
        }
        .padding(20)
    }
}
