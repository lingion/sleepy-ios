// TimeSlotEditor.swift — ← ui/component/TimeSlotEditor.kt
// 节次编辑器 v1.0.16+ / v1.0.56 三 Tab: 手动(逐节 start/end) / 自动(智慧节次) / 作息表(绑定现成表)。
// Bug 2 fix 对齐: 自动模式下 smartConfig 变化立刻 mergeAutoRows 同步上层(保留 edge 行)。
// issue#23 Task 4 对齐: resolveAutoPeriodConfig — 手动→自动切换时 stored 配置若能 derive
// 出当前标准行则原样保留, 否则从当前行重推断(以 stored 为 previous 承接分组标签)。

import SwiftUI
import UIKit

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
    let lastStandard = derivedStandardRows.map(\.node).max() ?? 0
    let afterNodes = existingRows.filter { $0.edgeClass == .after }.map(\.node)
    let collides = afterNodes.contains { $0 > 0 && $0 <= lastStandard }
    let afterShift = collides ? lastStandard + 1 - (afterNodes.min() ?? 0) : 0
    var nextStandard = 0
    var merged = existingRows.compactMap { row -> TimeTableUtils.TimeSlotRow? in
        if row.edgeClass != nil {
            var edge = row
            if edge.edgeClass == .after { edge.node += afterShift }
            return edge
        }
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

/// Persist a valid config only when it describes the standard rows being saved.
func encodeMatchingSmartPeriodConfig(rows: [TimeTableUtils.TimeSlotRow], stored: SmartPeriodConfig?) -> String {
    guard let config = resolveAutoPeriodConfig(rows: rows, stored: stored), config.validationError() == nil,
          let data = try? JSONEncoder().encode(config), let json = String(data: data, encoding: .utf8) else { return "" }
    return json
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
    // Read the live rows when a sheet callback fires, not a captured array snapshot.
    @Binding var rows: [TimeTableUtils.TimeSlotRow]
    let onRowsChange: ([TimeTableUtils.TimeSlotRow]) -> Void
    var usedDefaultTimes = false
    var smartConfig: SmartPeriodConfig = SmartPeriodConfig()
    var onSmartConfigChange: (SmartPeriodConfig) -> Void = { _ in }
    var reorderEnabled = false
    var courses: [CourseEntity] = []
    var periodTableOptions: [PeriodTableOption] = []
    var selectedPeriodTableId: Int64? = nil
    var onSelectPeriodTable: (Int64?) -> Void = { _ in }
    var excludePeriodTableId: Int64? = nil

    @State private var mode: TimeSlotEditorMode = .manual

    var body: some View {
        VStack(spacing: 0) {
            if usedDefaultTimes {
                Text(L10n.format("slot_defaults_notice"))
                    .font(SleepyTypography.bodySmall)
                    .foregroundColor(colors.onSurfaceVariant)
                    .padding(.bottom, 8)
            }
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
                ManualTimeSlotEditor(rows: $rows, onRowsChange: onRowsChange,
                                     reorderEnabled: reorderEnabled, courses: courses)
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
        guard smartConfig.validationError() == nil else { return }
        onRowsChange(mergeAutoRows(existingRows: rows, derivedStandardRows: smartConfig.derive()))
    }

    private func switchToAuto() {
        let resolved = resolveAutoPeriodConfig(rows: rows, stored: smartConfig)
            ?? (smartConfig.validationError() == nil ? smartConfig : SmartPeriodConfig())
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
        // ← 原版本 Column .heightIn(max = 240.dp) + verticalScroll + spacedBy(6.dp)
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
                    AndroidMaterialIcon(name: .check, size: 18)
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
    @Environment(\.sleepyUIStyle) private var style
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Read the live rows when a sheet callback fires, not a captured array snapshot.
    @Binding var rows: [TimeTableUtils.TimeSlotRow]
    let onRowsChange: ([TimeTableUtils.TimeSlotRow]) -> Void
    let reorderEnabled: Bool
    let courses: [CourseEntity]

    @GestureState private var dragGestureActive = false
    @State private var draggingNode: Int? = nil
    @State private var sourceIndex: Int? = nil
    @State private var targetIndex: Int? = nil
    @State private var sourceRows: [TimeTableUtils.TimeSlotRow] = []
    @State private var dragOffset: CGFloat = 0
    @State private var invalidTarget = false
    @State private var rowHeights: [Int: CGFloat] = [:]
    @State private var showInvalidDrop = false

    var body: some View {
        VStack(spacing: 0) {
            if rows.contains(where: { $0.start.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0.end.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                Text(L10n.format("slot_missing_notice"))
                    .font(SleepyTypography.bodySmall)
                    .foregroundColor(colors.error)
                    .padding(.bottom, 8)
            }
            // Header
            HStack {
                Text(L10n.format("n_periods", rows.count))
                    .font(SleepyTypography.bodySmall)
                    .foregroundColor(colors.onSurfaceVariant)
                Spacer()
                // 2026-09-16 用户: 裸 TextButton 无边界无色块 — 小号色块按钮
                // (原版本 Button containerColor=secondaryContainer / contentColor=onSecondaryContainer /
                //  shape=medium / labelMedium 12sp, 图标 18dp + 4dp 间距)
                Button {
                    onRowsChange(TimeTableUtils.appendEmptyRow(rows))
                } label: {
                    HStack(spacing: 4) {
                        AndroidMaterialIcon(name: .add, size: 18)
                        Text(L10n.format("add_period"))
                            .font(SleepyTypography.labelMedium)
                    }
                    .foregroundColor(colors.onSecondaryContainer)
                    .padding(.horizontal, style == .liquidGlass ? 0 : 24)   // ← M3 Button 默认水平 contentPadding 24dp
                    .frame(minHeight: style == .liquidGlass ? nil : 40)       // ← M3 Button 最小高 40dp
                    .sleepyControlSurface(cornerRadius: SleepyShapes.medium, tint: colors.secondaryContainer, prominent: true)
                }
                .buttonStyle(SleepyPlatformButtonStyle(prominent: true, cornerRadius: SleepyShapes.medium))
                .frame(minHeight: style == .liquidGlass ? 44 : nil)
                .tint(colors.secondaryContainer)
                .accessibilityIdentifier("slot_add")
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6)

            if reorderEnabled {
                Text(L10n.t("timeslot_longpress_to_reorder"))
                    .font(SleepyTypography.bodyMedium)
                    .foregroundColor(colors.onSurface)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
                if rows.contains(where: { $0.edgeClass != nil || $0.node <= 0 }) {
                    Text(L10n.t("timeslot_reorder_standard_only"))
                        .font(SleepyTypography.bodySmall)
                        .foregroundColor(colors.onSurfaceVariant)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 6)
                }
            }

            // Rows
            VStack(spacing: 10) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    let dragging = draggingNode == row.node
                    let target = targetIndex == index && !dragging
                    TimeSlotRowItem(
                        row: row,
                        canDelete: rows.count > 1,
                        isDragging: dragging,
                        isDropTarget: target,
                        dropInvalid: dragging && invalidTarget,
                        conflict: TimeTableUtils.findConflictForSlot(rows, targetNode: row.node),
                        onStartChange: { newStart in
                            guard rows.indices.contains(index) else { return }
                            onRowsChange(TimeTableUtils.updateManualRowTime(rows, node: rows[index].node, start: newStart))
                        },
                        onEndChange: { newEnd in
                            guard rows.indices.contains(index) else { return }
                            onRowsChange(TimeTableUtils.updateManualRowTime(rows, node: rows[index].node, end: newEnd))
                        },
                        onDelete: {
                            guard rows.indices.contains(index) else { return }
                            onRowsChange(TimeTableUtils.removeAndRenumber(rows, node: rows[index].node))
                        })
                        .background(GeometryReader { geometry in
                            Color.clear.preference(key: TimeSlotRowHeightKey.self,
                                                   value: [row.node: geometry.size.height])
                        })
                        .offset(y: dragging ? dragOffset : 0)
                        .zIndex(dragging ? 1 : 0)
                        // Keep time-field/delete Button taps ahead of row reordering.
                        // The sequence still recognizes a held drag on the row's free area.
                        .gesture(reorderGesture(row: row, index: index),
                                 including: reorderEnabled && row.edgeClass == nil && row.node > 0 ? .all : .subviews)
                        .accessibilityElement(children: .contain)
                        .accessibilityValue(dragging ? L10n.t(invalidTarget ? "timeslot_drop_invalid" : "timeslot_reorder_in_progress")
                                                    : target ? L10n.t("timeslot_row_drop_target") : "")
                        .accessibilityIdentifier("slot_row_\(row.node)")
                        .transition(SleepyMotionPolicy(reduceMotion: reduceMotion).expand)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(colors.surfaceContainerLow)
            .cornerRadius(SleepyShapes.large)
            // 只增删行触发空间变化；时间编辑不重建行身份或驱动整行位移。
            .animation(SleepyMotionPolicy(reduceMotion: reduceMotion).defaultSpatial, value: rows.count)
        }
        .onPreferenceChange(TimeSlotRowHeightKey.self) { rowHeights = $0 }
        .onChange(of: dragGestureActive) { active in
            if !active && draggingNode != nil { cancelReorder() }
        }
        .onChange(of: rows) { newRows in
            if draggingNode != nil && newRows != sourceRows { cancelReorder() }
        }
        .onDisappear { cancelReorder() }
        .overlay(alignment: .bottom) {
            if showInvalidDrop {
                Text(L10n.t("timeslot_drop_invalid"))
                    .font(SleepyTypography.bodySmall)
                    .foregroundColor(colors.onErrorContainer)
                    .padding(12)
                    .background(colors.errorContainer)
                    .cornerRadius(SleepyShapes.medium)
                    .accessibilityIdentifier("slot_reorder_invalid")
                    .task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        if !Task.isCancelled { showInvalidDrop = false }
                    }
            }
        }
    }

    private func reorderGesture(row: TimeTableUtils.TimeSlotRow, index: Int) -> some Gesture {
        LongPressGesture(minimumDuration: 0.35, maximumDistance: 12)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .updating($dragGestureActive) { value, active, _ in
                if case .second(true, _) = value { active = true }
            }
            .onChanged { value in
                guard reorderEnabled, row.edgeClass == nil, row.node > 0,
                      case .second(true, let drag) = value else { return }
                if draggingNode == nil {
                    sourceRows = rows
                    sourceIndex = index
                    targetIndex = index
                    draggingNode = row.node
                    invalidTarget = false
                    showInvalidDrop = false
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
                guard draggingNode == row.node, !invalidTarget, let drag else { return }
                let pitch = max((rowHeights[row.node] ?? 44) + 10, 1)
                dragOffset = max(-1_000_000, min(1_000_000, drag.translation.height))
                let destination = min(max(index + Int(dragOffset / pitch), 0), sourceRows.count - 1)
                targetIndex = destination
                invalidTarget = !TimeTableUtils.canReorderTimeSlot(sourceRows, fromIndex: index,
                                                                  toIndex: destination, courses: courses)
                if invalidTarget {
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    withAnimation(SleepyMotionPolicy(reduceMotion: reduceMotion).defaultSpatial) {
                        dragOffset = CGFloat(destination - index) * pitch
                    }
                }
            }
            .onEnded { _ in
                guard let from = sourceIndex, let to = targetIndex, rows == sourceRows else {
                    cancelReorder()
                    return
                }
                let valid = !invalidTarget && TimeTableUtils.canReorderTimeSlot(sourceRows, fromIndex: from,
                                                                               toIndex: to, courses: courses)
                let reordered = valid ? TimeTableUtils.reorderTimeSlotRows(sourceRows, fromIndex: from, toIndex: to) : rows
                withAnimation(SleepyMotionPolicy(reduceMotion: reduceMotion).fastSpatial) {
                    resetReorder()
                    if valid && from != to { onRowsChange(reordered) }
                }
                if !valid { showInvalidDrop = true }
            }
    }

    private func cancelReorder() {
        withAnimation(SleepyMotionPolicy(reduceMotion: reduceMotion).fastSpatial) { resetReorder() }
    }

    private func resetReorder() {
        draggingNode = nil
        sourceIndex = nil
        targetIndex = nil
        sourceRows = []
        dragOffset = 0
        invalidTarget = false
    }
}

private struct TimeSlotRowHeightKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private struct TimeSlotRowWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// ← TimeSlotRowItem
private struct TimeSlotRowItem: View {
    @Environment(\.localWakeUpColors) private var colors
    @Environment(\.sleepyUIStyle) private var style
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var regularMinimumWidth: CGFloat = 240
    @State private var availableWidth: CGFloat = 0
    let row: TimeTableUtils.TimeSlotRow
    let canDelete: Bool
    var isDragging = false
    var isDropTarget = false
    var dropInvalid = false
    var conflict: TimeTableUtils.PeriodValidationResult? = nil
    let onStartChange: (String) -> Void
    let onEndChange: (String) -> Void
    let onDelete: () -> Void

    private var isBlank: Bool {
        row.start.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && row.end.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            fields(compact: availableWidth > 0 && availableWidth < regularMinimumWidth)
            .background(
            RoundedRectangle(cornerRadius: SleepyShapes.medium)
                .fill(dropInvalid ? colors.errorContainer : conflict != nil ? colors.errorContainer.opacity(0.4)
                      : isDragging ? colors.primaryContainer
                      : isBlank ? colors.secondaryContainer : colors.surface)
                // effects 仅作用于底色，避免时间字段/删除按钮继承空间动画。
                .animation(SleepyMotionPolicy(reduceMotion: reduceMotion).defaultEffects, value: isBlank)
                .animation(SleepyMotionPolicy(reduceMotion: reduceMotion).defaultEffects, value: isDragging)
                .animation(SleepyMotionPolicy(reduceMotion: reduceMotion).defaultEffects, value: dropInvalid)
                .animation(SleepyMotionPolicy(reduceMotion: reduceMotion).defaultEffects, value: conflict)
            )
            if isBlank {
                Text(L10n.t("timeslot_row_blank_hint"))
                    .font(SleepyTypography.bodySmall)
                    .foregroundColor(colors.onSurfaceVariant)
                    .padding(.horizontal, 12)
            }
            if let conflict = conflict {
                Text(conflict.errorMessage)
                    .font(SleepyTypography.bodySmall)
                    .foregroundColor(colors.error)
                    .padding(.horizontal, 12)
                    .accessibilityIdentifier("slot_error_\(row.node)")
            }
        }
        .background(GeometryReader { geometry in
            Color.clear.preference(key: TimeSlotRowWidthKey.self, value: geometry.size.width)
        })
        .onPreferenceChange(TimeSlotRowWidthKey.self) { availableWidth = $0 }
        .overlay(alignment: .top) {
            if isDropTarget {
                Rectangle().fill(colors.primary).frame(height: 2)
                    .accessibilityHidden(true)
            }
        }
        .shadow(color: Color.black.opacity(isDragging ? 0.15 : 0), radius: isDragging ? 6 : 0, y: isDragging ? 3 : 0)
        .animation(SleepyMotionPolicy(reduceMotion: reduceMotion).defaultSpatial, value: isDragging)
    }

    private func fields(compact: Bool) -> some View {
        HStack(spacing: compact ? 4 : 8) {
            Text(compact ? "\(row.node)" : L10n.format("course_node_format", "\(row.node)"))
                .font(compact ? SleepyTypography.labelSmall : SleepyTypography.bodyMedium)
                .foregroundColor(colors.onSurface)
                .frame(width: compact ? 20 : 44, alignment: .leading)
                .accessibilityLabel(L10n.format("course_node_format", "\(row.node)"))
            TimePickerField(value: row.start, onValueChange: onStartChange,
                            label: L10n.format("start_label"), fillsWidth: true,
                            showsPendingHint: true)
                .accessibilityIdentifier("slot_start_\(row.node)")
            TimePickerField(value: row.end, onValueChange: onEndChange,
                            label: L10n.format("end_label"), fillsWidth: true,
                            showsPendingHint: true)
                .accessibilityIdentifier("slot_end_\(row.node)")
            if canDelete {
                Button(action: onDelete) {
                    AndroidSettingsIcon(name: .removeCircleOutline, size: 20)
                        .foregroundColor(colors.error)
                        .frame(width: style == .liquidGlass ? 20 : 48,
                               height: style == .liquidGlass ? 20 : 48)
                        .contentShape(Circle())
                }
                .buttonStyle(SleepyPlatformButtonStyle(cornerRadius: 22, compact: true, shape: .circle))
                .tint(colors.error)
                .frame(width: 48, height: 48)
                .contentShape(Circle())
                .accessibilityIdentifier("slot_row_delete_\(row.node)")
                .accessibilityLabel(L10n.format("delete_period"))
            } else { Spacer().frame(width: 48) }
        }
        .padding(.horizontal, compact ? 4 : 10)
        .padding(.vertical, 8)
    }
}
