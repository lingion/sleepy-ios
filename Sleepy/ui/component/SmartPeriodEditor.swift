// SmartPeriodEditor.swift — ← ui/component/SmartPeriodEditor.kt
// 智慧节次编辑器(自动模式): 每 break 模板一行位置卡片(1.5, 2.5, ..., (N-1).5),
// 点选表示该位置使用这个 break。同组内多选 / 跨组互斥 / 未选中=0 分钟连续。

import SwiftUI

struct SmartPeriodEditor: View {
    @Environment(\.localWakeUpColors) private var colors
    let config: SmartPeriodConfig
    let onConfigChange: (SmartPeriodConfig) -> Void

    var body: some View {
        let assigns = config.effectiveAssignments()

        VStack(spacing: 0) {
            // ===== 输入区 =====
            Text(L10n.format("edit_period_input"))
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(colors.onSurface)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 4)
                .padding(.bottom, 6)

            // 每节时长 + 总节数
            HStack(spacing: 8) {
                NumberField(label: L10n.format("edit_period_duration_label"),
                            unit: L10n.format("unit_minutes"),
                            value: config.periodMinutes) { newVal in
                    onConfigChange({ var c = config; c.periodMinutes = max(newVal, 1); return c }())
                }
                NumberField(label: L10n.format("edit_period_total_label"),
                            unit: L10n.format("unit_periods"),
                            value: config.totalPeriods) { newN in
                    onConfigChange({ var c = config; c.totalPeriods = max(newN, 1); return c }())
                }
            }
            .padding(.bottom, 6)

            // 第一节开始时间
            TimePickerField(value: config.startTime,
                            onValueChange: { newTime in onConfigChange({ var c = config; c.startTime = newTime; return c }()) },
                            label: L10n.format("edit_period_first_start"))
                .padding(.bottom, 12)

            // 添加 break
            HStack(spacing: 8) {
                AddBreakChip(label: L10n.format("short_break"), color: colors.tertiary) {
                    onConfigChange({ var c = config; c.breaks = config.breaks + [BreakOption(minutes: 10, isLong: false)]; return c }())
                }
                AddBreakChip(label: L10n.format("long_break"), color: colors.primary) {
                    onConfigChange({ var c = config; c.breaks = config.breaks + [BreakOption(minutes: 30, isLong: true)]; return c }())
                }
            }
            .padding(.bottom, 12)

            // ===== Break 分组区 =====
            if !config.breaks.isEmpty {
                Text(L10n.format("break_assign_hint"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(colors.onSurface)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 4)
                    .padding(.bottom, 6)

                ForEach(Array(config.breaks.enumerated()), id: \.offset) { groupIdx, br in
                    BreakGroupSection(
                        breakOption: br,
                        groupIdx: groupIdx,
                        totalPeriods: config.totalPeriods,
                        assigns: assigns,
                        onMinuteChange: { newMin in
                            var breaks = config.breaks
                            breaks[groupIdx].minutes = newMin
                            onConfigChange({ var c = config; c.breaks = breaks; return c }())
                        },
                        onToggle: { posIdx in
                            var newAssigns = assigns
                            let currentlySelected = newAssigns[posIdx] == groupIdx
                            newAssigns[posIdx] = currentlySelected ? nil : groupIdx
                            onConfigChange({ var c = config; c.transitionAssignments = newAssigns; return c }())
                        },
                        onDelete: {
                            // ★ 删除组后索引重映射: 被删组清空 + 大于被删索引的全部减 1
                            let newAssigns = assigns.map { v -> Int? in
                                if v == groupIdx { return nil }
                                if let v = v, v > groupIdx { return v - 1 }
                                return v
                            }
                            var breaks = config.breaks
                            breaks.remove(at: groupIdx)
                            onConfigChange({ var c = config; c.breaks = breaks; c.transitionAssignments = newAssigns; return c }())
                        })
                }
            }

            // ===== 预览 =====
            Spacer().frame(height: 16)
            Text(L10n.format("preview"))
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(colors.onSurface)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 4)
                .padding(.bottom, 6)
            PreviewList(config: config, assigns: assigns)
        }
    }
}

// ← BreakGroupSection
private struct BreakGroupSection: View {
    @Environment(\.localWakeUpColors) private var colors
    let breakOption: BreakOption
    let groupIdx: Int
    let totalPeriods: Int
    let assigns: [Int?]
    let onMinuteChange: (Int) -> Void
    let onToggle: (Int) -> Void
    let onDelete: () -> Void

    var body: some View {
        let groupColor = breakOption.isLong ? colors.primary : colors.tertiary
        let n = max(totalPeriods - 1, 0)

        VStack(alignment: .leading, spacing: 8) {
            // Header: 名称 + 分钟数 + 删除
            HStack(spacing: 8) {
                // 颜色 chip
                Circle()
                    .fill(groupColor)
                    .frame(width: 10, height: 10)
                Text(breakOption.displayLabel(index: groupIdx))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(colors.onSurface)
                Spacer()
                NumberField(label: "", unit: L10n.format("unit_minutes"),
                            value: breakOption.minutes, onValueChange: onMinuteChange)
                    .frame(width: 110)
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 18))
                        .foregroundColor(colors.onSurfaceVariant)
                }
                .buttonStyle(.plain)
            }

            // 位置卡片网格(每行 8 个)
            if n > 0 {
                let cardsPerRow = 8
                let rows = Array(Array(0..<n).chunked(into: cardsPerRow))
                VStack(spacing: 6) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, rowIndices in
                        HStack(spacing: 6) {
                            ForEach(rowIndices, id: \.self) { posIdx in
                                PositionCard(label: "\(posIdx + 1).5",
                                             selected: assigns.indices.contains(posIdx) && assigns[posIdx] == groupIdx,
                                             groupColor: groupColor) {
                                    onToggle(posIdx)
                                }
                            }
                            // 填满空位
                            ForEach(0..<(cardsPerRow - rowIndices.count), id: \.self) { _ in
                                Spacer()
                            }
                        }
                    }
                }
            } else {
                Text(L10n.format("break_min_two_periods"))
                    .font(.system(size: 12))
                    .foregroundColor(colors.onSurfaceVariant)
                    .padding(.vertical, 4)
            }
        }
        .padding(12)
        .background(colors.surfaceContainerLow)
        .cornerRadius(SleepyShapes.medium)
        .padding(.vertical, 6)
    }
}

// ← PositionCard
private struct PositionCard: View {
    @Environment(\.localWakeUpColors) private var colors
    let label: String
    let selected: Bool
    let groupColor: Color
    let onClick: () -> Void

    var body: some View {
        let bg = selected ? groupColor : colors.surfaceContainerHigh
        let fg = selected ? colors.onPrimary : colors.onSurfaceVariant

        Button(action: onClick) {
            Text(label)
                .font(.system(size: 12, weight: selected ? .bold : .regular))
                .foregroundColor(fg)
                .frame(maxWidth: .infinity, minHeight: 36)
        }
        .buttonStyle(.plain)
        .background(bg)
        .cornerRadius(SleepyShapes.small)
    }
}

// ← PreviewList
private struct PreviewList: View {
    @Environment(\.localWakeUpColors) private var colors
    let config: SmartPeriodConfig
    let assigns: [Int?]

    var body: some View {
        let rows = config.derive()
        let transMins = config.effectiveTransitionMinutes()

        if rows.isEmpty {
            Text(L10n.format("empty_placeholder"))
                .font(.system(size: 12))
                .foregroundColor(colors.onSurfaceVariant)
        } else {
            VStack(spacing: 2) {
                ForEach(Array(rows.enumerated()), id: \.offset) { i, slot in
                    Text(L10n.format("period_time_range", slot.node, slot.start, slot.end))
                        .font(.system(size: 12))
                        .foregroundColor(colors.onSurface)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if i < transMins.count {
                        let mins = transMins[i]
                        // break 标签: 分配到的组 isLong → 大课间, 否则小课间
                        let breakLabel: String = {
                            if let idx = assigns[i], config.breaks.indices.contains(idx),
                               config.breaks[idx].isLong {
                                return L10n.format("long_break")
                            }
                            return L10n.format("short_break")
                        }()
                        let text = mins == 0
                            ? L10n.format("break_continuous_0")
                            : L10n.format("break_continuous_n", mins, breakLabel)
                        Text(text)
                            .font(.system(size: 12, weight: mins > 0 ? .medium : .regular))
                            .foregroundColor(colors.onSurfaceVariant)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(12)
            .background(colors.surfaceContainerLow)
            .cornerRadius(SleepyShapes.medium)
        }
    }
}

// ← NumberField: 纯数字输入 + 单位后缀
private struct NumberField: View {
    @Environment(\.localWakeUpColors) private var colors
    let label: String
    let unit: String
    let value: Int
    let onValueChange: (Int) -> Void

    @State private var text: String = ""

    var body: some View {
        HStack(spacing: 4) {
            TextField(label.isEmpty ? " " : label, text: Binding(
                get: { text.isEmpty ? "\(value)" : text },
                set: { newText in
                    // 纯数字 + 最多 4 位(对齐 Android)
                    if newText.allSatisfy({ $0.isNumber }) && newText.count <= 4 {
                        text = newText
                        if let parsed = Int(newText) { onValueChange(parsed) }
                    }
                }
            ))
            .keyboardType(.numberPad)
            .font(.system(size: 16))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(colors.surfaceContainer)
            .cornerRadius(SleepyTheme.fieldShape)
            .overlay(
                RoundedRectangle(cornerRadius: SleepyTheme.fieldShape)
                    .strokeBorder(colors.outline.opacity(SleepyTheme.Alpha.hairline), lineWidth: 1)
            )
            if !unit.isEmpty {
                Text(unit)
                    .font(.system(size: 12))
                    .foregroundColor(colors.onSurfaceVariant)
            }
        }
        .onAppear { text = "\(value)" }
        .onChange(of: value) { newValue in text = "\(newValue)" }
    }
}

// ← AddBreakChip
private struct AddBreakChip: View {
    let label: String
    let color: Color
    let onAdd: () -> Void

    var body: some View {
        Button(action: onAdd) {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 16))
                    .foregroundColor(color)
                Text(L10n.format("add_label", label))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(color)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(SleepyTheme.Alpha.tinted))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}

// chunked 辅助(← Kotlin stdlib chunked)
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
