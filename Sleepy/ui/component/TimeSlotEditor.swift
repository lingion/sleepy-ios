// TimeSlotEditor.swift — ← ui/component/TimeSlotEditor.kt
// 节次编辑器 v1.0.16+ / v1.0.56 三 Tab: 手动(逐节 start/end) / 自动(智慧节次) / 作息表(绑定现成表)。
// Bug 2 fix 对齐: 自动模式下 smartConfig 变化立刻 mergeAutoRows 同步上层(保留 edge 行)。
// issue#23 Task 4 对齐: resolveAutoPeriodConfig — 手动→自动切换时 stored 配置若能 derive
// 出当前标准行则原样保留, 否则从当前行重推断(以 stored 为 previous 承接分组标签)。

import SwiftUI

enum TimeSlotEditorMode { case manual, auto, periodTable }

// MARK: - issue#23 Task 4 纯逻辑 ← Kotlin 顶层函数 resolveAutoPeriodConfig / mergeAutoRows / decodeSmartPeriodConfig

/// issue#23 Task 4: 进自动模式的配置归一 —— 手动行与智慧节次配置双向同步的纯逻辑。
///
/// 1) stored 配置仍能 derive 出当前标准行(节点/起止逐行相等) → 原样保留
///    (保住用户已调好的分组、标签; edge 行不参与比对, 永远留在手动模式);
/// 2) 否则从当前行重新推断(edge 行被排除), stored 作为 previous 传入以按分钟
///    承接既有分组标签;
/// 3) 行不可推断(畸形/倒序/断号) → 返回 nil, 调用方回退最简默认或维持原配置。
func resolveAutoPeriodConfig(rows: [TimeTableUtils.TimeSlotRow],
                             stored: SmartPeriodConfig?) -> SmartPeriodConfig? {
    let standard = rows.filter { $0.edgeClass == nil }.sorted { $0.node < $1.node }
    if standard.isEmpty || standard.first!.node != 1 ||
        standard.map(\.node) != Array(1...standard.count) {
        return TimeTableUtils.inferSmartPeriodConfig(standard, previous: stored)
    }
    if let stored = stored {
        let derived = stored.derive()
        let matches = derived.count == standard.count &&
            zip(derived, standard).allSatisfy { d, s in
                d.node == s.node && d.start == s.start && d.end == s.end
            }
        if matches { return stored }
    }
    return TimeTableUtils.inferSmartPeriodConfig(standard, previous: stored)
}

/// Replace standard rows with automatic output while retaining manual edge rows.
func mergeAutoRows(existingRows: [TimeTableUtils.TimeSlotRow],
                   derivedStandardRows: [TimeTableUtils.TimeSlotRow]) -> [TimeTableUtils.TimeSlotRow] {
    var nextStandard = 0
    var merged = existingRows.compactMap { row -> TimeTableUtils.TimeSlotRow? in
        if row.edgeClass != nil { return row }
        defer { nextStandard += 1 }
        guard nextStandard < derivedStandardRows.count else { return nil }
        return derivedStandardRows[nextStandard]
    }
    if nextStandard < derivedStandardRows.count {
        merged += Array(derivedStandardRows.dropFirst(nextStandard))
    }
    return merged
}

/// smartConfigJson -> config(nil = 空串/损坏); 两处编辑页 seed 共用
func decodeSmartPeriodConfig(_ json: String?) -> SmartPeriodConfig? {
    guard let json = json,
          !json.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          let data = json.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(SmartPeriodConfig.self, from: data)
}

/// v1.0.56 作息表 Tab 选项 — 调用方从 VM 流映射, 组件不触库
struct PeriodTableOption {
    let id: Int64
    let name: String
    let nodesPerDay: Int
}

/// 调用方持有 rows(手动模式), config(自动模式), 切换模式时通过
/// onRowsChange/onSmartConfigChange 通知。
///
/// v1.0.56 作息表 Tab 语义:
///  - selectedPeriodTableId nil = 未绑定(用解析出的/本表的内置节次), 非 nil = 绑定该表;
///    选中态完全由调用方持有(确认时才落库/落 preview 值), 组件内零写库。
///  - onSelectPeriodTable 点选项行回调(nil = 选"未绑定")。
///  - excludePeriodTableId 作息表编辑页用: 列表中排除自己(禁自引用)。
///  - 仅当调用方传入 periodTableOptions 时第三 Tab 出现(不传 = 旧两 Tab, 兼容既有调用)。
struct TimeSlotEditor: View {
    @Environment(\.localWakeUpColors) private var colors
    let rows: [TimeTableUtils.TimeSlotRow]
    let onRowsChange: ([TimeTableUtils.TimeSlotRow]) -> Void
    var smartConfig: SmartPeriodConfig = SmartPeriodConfig()
    var onSmartConfigChange: (SmartPeriodConfig) -> Void = { _ in }
    var periodTableOptions: [PeriodTableOption] = []
    var selectedPeriodTableId: Int64? = nil
    var onSelectPeriodTable: (Int64?) -> Void = { _ in }
    var excludePeriodTableId: Int64? = nil

    @State private var mode: TimeSlotEditorMode = .manual

    var body: some View {
        VStack(spacing: 0) {
            // ===== Tab 切换 =====
            ModeTabSwitch(
                current: mode,
                onChange: { next in
                    // issue#23 Task 4: 手动→自动切换先归一配置, 禁进自动即重置为全新默认
                    if next == .auto { switchToAuto() } else { mode = next }
                },
                hasPeriodTableTab: !periodTableOptions.isEmpty || selectedPeriodTableId != nil)
            Spacer().frame(height: 8)

            switch mode {
            case .manual:
                ManualTimeSlotEditor(rows: rows, onRowsChange: onRowsChange)
            case .auto:
                // Bug 2 fix: config 变化立即 merge 同步(保留 edge 行)。调用方不一定回传
                // smartConfig(ImportSheet 旧接线), 故回调内直接同步; 回传方由 onChange 兜底。
                SmartPeriodEditor(config: smartConfig) { newConfig in
                    onSmartConfigChange(newConfig)
                    onRowsChange(mergeAutoRows(existingRows: rows,
                                               derivedStandardRows: newConfig.derive()))
                }
            case .periodTable:
                PeriodTableBindTab(
                    options: periodTableOptions.filter { $0.id != excludePeriodTableId },
                    selectedId: selectedPeriodTableId,
                    onSelect: onSelectPeriodTable)
            }
        }
        // ← LaunchedEffect(mode, smartConfig): 进入 Auto 即同步(修"进自动没编辑配置就保存
        // 的仍是旧手动行"), config 每次变化也同步 — Bug 2 fix 的完整语义。
        .onChange(of: mode) { newMode in
            if newMode == .auto { syncAutoRows() }
        }
        .onChange(of: smartConfig) { _ in
            if mode == .auto { syncAutoRows() }
        }
    }

    private func syncAutoRows() {
        onRowsChange(mergeAutoRows(existingRows: rows, derivedStandardRows: smartConfig.derive()))
    }

    private func switchToAuto() {
        let resolved = resolveAutoPeriodConfig(rows: rows, stored: smartConfig) ?? smartConfig
        onSmartConfigChange(resolved)
        mode = .auto
    }
}

// ← ModeTabSwitch (2026-08-25 用户指令: 全 app 统一色块禁描线 — SegmentedSwitcher 同款)
private struct ModeTabSwitch: View {
    let current: TimeSlotEditorMode
    let onChange: (TimeSlotEditorMode) -> Void
    let hasPeriodTableTab: Bool

    var body: some View {
        SegmentedSwitcher(
            options: modes.map { ($0, label(for: $0)) },
            selected: current,
            onSelect: { onChange($0) })
    }

    private var modes: [TimeSlotEditorMode] {
        hasPeriodTableTab ? [.manual, .auto, .periodTable] : [.manual, .auto]
    }

    private func label(for mode: TimeSlotEditorMode) -> String {
        switch mode {
        case .manual: return L10n.format("mode_manual")
        case .auto: return L10n.format("mode_auto")
        case .periodTable: return L10n.format("period_tables_tab")
        }
    }
}

// ← PeriodTableBindTab
/// v1.0.56 作息表 Tab 内容: 未绑定选项 + 全部作息表列表。
/// 选中态=primaryContainer 色块+对勾(与 EditTableScreen 换绑卡同构, 禁描边规则)。
/// maxHeight 限制防弹窗内挤爆; 列表可滚动。
private struct PeriodTableBindTab: View {
    @Environment(\.localWakeUpColors) private var colors
    let options: [PeriodTableOption]
    let selectedId: Int64?
    let onSelect: (Int64?) -> Void

    var body: some View {
        // ← Android Column .heightIn(max = 240.dp) + verticalScroll + spacedBy(6.dp)
        ScrollView {
            VStack(spacing: 6) {
                // 未绑定 = 不绑, 用解析出的/本表内置节次
                BindChoiceRow(title: L10n.format("period_table_unbound"),
                              selected: selectedId == nil,
                              onClick: { onSelect(nil) })
                ForEach(options, id: \.id) { opt in
                    BindChoiceRow(title: opt.name,
                                  subtitle: L10n.format("period_table_nodes_count", opt.nodesPerDay),
                                  selected: selectedId == opt.id,
                                  onClick: { onSelect(opt.id) })
                }
            }
        }
        .frame(maxHeight: 240)
    }
}

// ← BindChoiceRow
/// 选中态=primaryContainer 色块+对勾(UI 纯色块禁描边规则, 与换绑卡 BindOptionRow 同构)
private struct BindChoiceRow: View {
    @Environment(\.localWakeUpColors) private var colors
    let title: String
    var subtitle: String? = nil
    let selected: Bool
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(SleepyTypography.bodyMedium)
                        .foregroundColor(selected ? colors.onPrimaryContainer : colors.onSurface)
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(SleepyTypography.bodySmall)
                            .foregroundColor(colors.onSurfaceVariant)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if selected {
                    Spacer().frame(width: 8)
                    Image(systemName: "checkmark")
                        .font(.system(size: 18))
                        .foregroundColor(colors.onPrimaryContainer)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? colors.primaryContainer : colors.surface)
            .cornerRadius(SleepyShapes.medium)
        }
        .buttonStyle(SleepyButtonStyle())
    }
}

// ← ManualTimeSlotEditor
private struct ManualTimeSlotEditor: View {
    @Environment(\.localWakeUpColors) private var colors
    let rows: [TimeTableUtils.TimeSlotRow]
    let onRowsChange: ([TimeTableUtils.TimeSlotRow]) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(L10n.format("n_periods", rows.count))
                    .font(SleepyTypography.bodySmall)
                    .foregroundColor(colors.onSurfaceVariant)
                Spacer()
                // 2026-09-16 用户: 裸 TextButton 无边界无色块 — 小号色块按钮
                // (Android Button containerColor=secondaryContainer / contentColor=onSecondaryContainer /
                //  shape=medium / labelMedium 12sp, 图标 18dp + 4dp 间距)
                Button {
                    onRowsChange(TimeTableUtils.appendEmptyRow(rows))
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 18))
                        Text(L10n.format("add_period"))
                            .font(SleepyTypography.labelMedium)
                    }
                    .foregroundColor(colors.onSecondaryContainer)
                    .padding(.horizontal, 24)   // ← M3 Button 默认水平 contentPadding 24dp
                    .frame(minHeight: 40)       // ← M3 Button 最小高 40dp
                    .background(colors.secondaryContainer)
                    .cornerRadius(SleepyShapes.medium)
                }
                .buttonStyle(SleepyButtonStyle())
                .accessibilityIdentifier("slot_add")
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6)

            // Rows
            VStack(spacing: 10) {
                ForEach(rows, id: \.node) { row in
                    TimeSlotRowItem(
                        row: row,
                        canDelete: rows.count > 1,
                        onStartChange: { newStart in
                            onRowsChange(rows.map { item in
                                if item.node == row.node { var r = item; r.start = newStart; return r }
                                return item
                            })
                        },
                        onEndChange: { newEnd in
                            onRowsChange(rows.map { item in
                                if item.node == row.node { var r = item; r.end = newEnd; return r }
                                return item
                            })
                        },
                        onDelete: {
                            onRowsChange(TimeTableUtils.removeAndRenumber(rows, node: row.node))
                        })
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(colors.surfaceContainerLow)
            .cornerRadius(SleepyShapes.large)
        }
    }
}

// ← TimeSlotRowItem
private struct TimeSlotRowItem: View {
    @Environment(\.localWakeUpColors) private var colors
    let row: TimeTableUtils.TimeSlotRow
    let canDelete: Bool
    let onStartChange: (String) -> Void
    let onEndChange: (String) -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(L10n.format("course_node_format", "\(row.node)"))
                .font(.system(size: 14))
                .foregroundColor(colors.onSurface)
                .frame(width: 44, alignment: .leading)
            TimePickerField(value: row.start, onValueChange: onStartChange,
                            label: L10n.format("start_label"), fillsWidth: true)
            TimePickerField(value: row.end, onValueChange: onEndChange,
                            label: L10n.format("end_label"), fillsWidth: true)
            if canDelete {
                Button(action: onDelete) {
                    Image(systemName: "minus.circle")
                        .font(.system(size: 20))
                        .foregroundColor(colors.error)
                }
                .buttonStyle(SleepyButtonStyle())
                .accessibilityIdentifier("slot_row_delete_\(row.node)")
                // ← Android contentDescription = delete_period
                .accessibilityLabel(L10n.format("delete_period"))
                .frame(width: 32, height: 32)   // ← Android IconButton 32dp 方形
            } else {
                Spacer().frame(width: 32)
            }
        }
    }
}
