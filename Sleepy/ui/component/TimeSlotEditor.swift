// TimeSlotEditor.swift — ← ui/component/TimeSlotEditor.kt
// 节次编辑器 v1.0.16+: 手动模式(逐节 start/end) / 自动模式(智慧节次)。
// Bug 2 fix 对齐: 自动模式下 smartConfig 变化立刻 derive rows 同步上层。

import SwiftUI

enum TimeSlotEditorMode { case manual, auto }

struct TimeSlotEditor: View {
    @Environment(\.localWakeUpColors) private var colors
    let rows: [TimeTableUtils.TimeSlotRow]
    let onRowsChange: ([TimeTableUtils.TimeSlotRow]) -> Void
    var smartConfig: SmartPeriodConfig = SmartPeriodConfig()
    var onSmartConfigChange: (SmartPeriodConfig) -> Void = { _ in }

    @State private var mode: TimeSlotEditorMode = .manual

    var body: some View {
        VStack(spacing: 0) {
            // ===== Tab 切换 =====
            SegmentedSwitcher(
                options: [(TimeSlotEditorMode.manual, L10n.format("mode_manual")),
                          (TimeSlotEditorMode.auto, L10n.format("mode_auto"))],
                selected: mode) { mode = $0 }
            Spacer().frame(height: 8)

            switch mode {
            case .manual:
                ManualTimeSlotEditor(rows: rows, onRowsChange: onRowsChange)
            case .auto:
                // Bug 2 fix: config 变化立即 derive 同步(对齐 LaunchedEffect(mode, smartConfig))
                SmartPeriodEditor(config: smartConfig) { newConfig in
                    onSmartConfigChange(newConfig)
                    onRowsChange(newConfig.derive())
                }
            }
        }
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
                    .font(.system(size: 12))
                    .foregroundColor(colors.onSurfaceVariant)
                Spacer()
                Button {
                    onRowsChange(TimeTableUtils.appendEmptyRow(rows))
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 18))
                        Text(L10n.format("add_period"))
                    }
                    .foregroundColor(colors.primary)
                }
                .buttonStyle(.plain)
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
                            label: L10n.format("start_label"))
            TimePickerField(value: row.end, onValueChange: onEndChange,
                            label: L10n.format("end_label"))
            if canDelete {
                Button(action: onDelete) {
                    Image(systemName: "minus.circle")
                        .font(.system(size: 20))
                        .foregroundColor(colors.error)
                }
                .buttonStyle(.plain)
                .frame(width: 32)
            } else {
                Spacer().frame(width: 32)
            }
        }
    }
}
