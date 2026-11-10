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
        let durationAssigns = config.effectivePeriodAssignments()

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
                            label: L10n.format("edit_period_first_start"), fillsWidth: true)
                .padding(.bottom, 12)

            // 添加 duration ← 原版本 L116-133(短课时 tertiary / 长课时 primary)
            HStack(spacing: 8) {
                AddBreakChip(id: "duration_short", label: L10n.format("short_duration"), color: colors.tertiary) {
                    onConfigChange({ var c = config; c.durations = config.durations + [DurationOption(minutes: 30, isLong: false)]; return c }())
                }
                AddBreakChip(id: "duration_long", label: L10n.format("long_duration"), color: colors.primary) {
                    onConfigChange({ var c = config; c.durations = config.durations + [DurationOption(minutes: 60, isLong: true)]; return c }())
                }
            }
            .padding(.bottom, 12)

            // ===== Duration 分组区 ===== ← 原版本 L135-175
            if !config.durations.isEmpty {
                Text(L10n.format("duration_assign_hint"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(colors.onSurface)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 4)
                    .padding(.bottom, 6)

                ForEach(Array(config.durations.enumerated()), id: \.offset) { groupIdx, dur in
                    DurationGroupSection(
                        durationOption: dur,
                        groupIdx: groupIdx,
                        totalPeriods: config.totalPeriods,
                        assigns: durationAssigns,
                        onMinuteChange: { newMin in
                            var durations = config.durations
                            durations[groupIdx].minutes = newMin
                            onConfigChange({ var c = config; c.durations = durations; return c }())
                        },
                        onToggle: { posIdx in
                            var newAssigns = durationAssigns
                            let currentlySelected = newAssigns[posIdx] == groupIdx
                            newAssigns[posIdx] = currentlySelected ? nil : groupIdx
                            onConfigChange({ var c = config; c.periodAssignments = newAssigns; return c }())
                        },
                        onDelete: {
                            // ← 原版本 L166-172: 删除组后索引重映射
                            let newAssigns = remapDurationAssignmentsAfterDeletion(assignments: durationAssigns, deletedIndex: groupIdx)
                            var durations = config.durations
                            durations.remove(at: groupIdx)
                            onConfigChange({ var c = config; c.durations = durations; c.periodAssignments = newAssigns; return c }())
                        })
                }
            }

            // 添加 break
            HStack(spacing: 8) {
                AddBreakChip(id: "break_short", label: L10n.format("short_break"), color: colors.tertiary) {
                    onConfigChange({ var c = config; c.breaks = config.breaks + [BreakOption(minutes: 10, isLong: false)]; return c }())
                }
                AddBreakChip(id: "break_long", label: L10n.format("long_break"), color: colors.primary) {
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

// ← BreakGroupSection(薄壳: 只负责 break 侧的 label/槽数/空提示)
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
        AssignmentGroupSection(
            headerText: breakOption.displayLabel(index: groupIdx),
            groupColor: breakOption.isLong ? colors.primary : colors.tertiary,
            slotCount: max(totalPeriods - 1, 0),
            assigns: assigns,
            groupIdx: groupIdx,
            labelFor: { posIdx in "\(posIdx + 1).5" },
            emptyHintKey: "break_min_two_periods",
            minuteValue: breakOption.minutes,
            onMinuteChange: onMinuteChange,
            onToggle: onToggle,
            onDelete: onDelete)
    }
}

// ← DurationGroupSection(薄壳: slotCount = totalPeriods、label "n"、hint duration_min_one_period)
private struct DurationGroupSection: View {
    @Environment(\.localWakeUpColors) private var colors
    let durationOption: DurationOption
    let groupIdx: Int
    let totalPeriods: Int
    let assigns: [Int?]
    let onMinuteChange: (Int) -> Void
    let onToggle: (Int) -> Void
    let onDelete: () -> Void

    var body: some View {
        AssignmentGroupSection(
            headerText: durationOption.displayLabel(index: groupIdx),
            groupColor: durationOption.isLong ? colors.primary : colors.tertiary,
            slotCount: max(totalPeriods, 0),
            assigns: assigns,
            groupIdx: groupIdx,
            labelFor: { posIdx in "\(posIdx + 1)" },
            emptyHintKey: "duration_min_one_period",
            minuteValue: durationOption.minutes,
            onMinuteChange: onMinuteChange,
            onToggle: onToggle,
            onDelete: onDelete)
    }
}

/// ← AssignmentGroupSection: 共享的"分组赋值"编辑器
/// 卡片布局、分钟数字段、删除按钮全部共用，调用方只传 label 渲染器和业务事件。
private struct AssignmentGroupSection: View {
    @Environment(\.localWakeUpColors) private var colors
    @Environment(\.sleepyUIStyle) private var style
    @ScaledMetric(relativeTo: .caption) private var scaledCellWidth: CGFloat = 32
    @State private var positionGridWidth: CGFloat = 0
    let headerText: String
    let groupColor: Color
    let slotCount: Int
    let assigns: [Int?]
    let groupIdx: Int
    let labelFor: (Int) -> String
    let emptyHintKey: String
    let minuteValue: Int
    let onMinuteChange: (Int) -> Void
    let onToggle: (Int) -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header ← 原版本 Row(无 spacedBy,间距0): color chip + 名称(weight(1f)) + 显式 8dp Spacer + 分钟数 + 删除
            HStack(spacing: 0) {
                // 颜色 chip
                Circle()
                    .fill(groupColor)
                    .frame(width: 10, height: 10)
                Text(headerText)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(colors.onSurface)
                    .padding(.leading, 8)                          // ← 原 chip 后显式 Spacer(8.dp)
                    .frame(maxWidth: .infinity, alignment: .leading) // ← 原 名称 weight(1f) 吃满剩余宽度
                // ← 原版本 Text 与 NumberField 之间无 spacer(weight 1f 吸收全部 slack),不另加间距
                NumberField(label: "", unit: L10n.format("unit_minutes"),
                            value: minuteValue, onValueChange: onMinuteChange)
                    .frame(width: 110)
                Button(action: onDelete) {
                    AndroidSettingsIcon(name: .close, size: 18)
                        .foregroundColor(colors.onSurfaceVariant)
                        .frame(width: style == .classic ? 48 : nil,
                               height: style == .classic ? 48 : nil)
                        .contentShape(Circle())
                }
                .buttonStyle(SleepyPlatformButtonStyle(cornerRadius: 14, shape: .circle))
                .frame(width: 48, height: 48)
                .contentShape(Circle())
                // ← 原 contentDescription = delete
                .accessibilityLabel(L10n.format("delete"))
            }

            // Match Android: at least 48pt cells with 8pt gaps, up to eight per row.
            if slotCount > 0 {
                positionGrid
            } else {
                Text(L10n.format(emptyHintKey))
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

    private var positionGrid: some View {
        let gap: CGFloat = 8
        let minimumCell = max(48, scaledCellWidth)
        let cardsPerRow = min(8, max(1, Int((positionGridWidth + gap) / (minimumCell + gap))))
        let rows = Array(Array(0..<slotCount).chunked(into: cardsPerRow))
        return VStack(spacing: gap) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, rowIndices in
                HStack(spacing: gap) {
                    ForEach(rowIndices, id: \.self) { posIdx in
                        PositionCard(label: labelFor(posIdx),
                                     selected: assigns.indices.contains(posIdx) && assigns[posIdx] == groupIdx,
                                     groupColor: groupColor) { onToggle(posIdx) }
                    }
                    ForEach(0..<(cardsPerRow - rowIndices.count), id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity, minHeight: 48)
                    }
                }
            }
        }
        .background(GeometryReader { geometry in
            Color.clear
                .onAppear { positionGridWidth = geometry.size.width }
                .onChange(of: geometry.size.width) { positionGridWidth = $0 }
        })
    }
}

// ← PositionCard
private struct PositionCard: View {
    @Environment(\.localWakeUpColors) private var colors
    @Environment(\.sleepyUIStyle) private var style
    let label: String
    let selected: Bool
    let groupColor: Color
    let onClick: () -> Void

    @ViewBuilder
    var body: some View {
        if style == .liquidGlass {
            Button(action: onClick) {
                Text(label)
                    .font(.system(size: 12, weight: selected ? .bold : .regular))
                    .foregroundColor(selected
                        ? (groupColor == colors.tertiary ? colors.onTertiary : colors.onPrimary)
                        : colors.onSurfaceVariant)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SleepyPlatformButtonStyle(prominent: selected,
                                                   cornerRadius: SleepyShapes.small, compact: true))
            .tint(groupColor)
            .frame(maxWidth: .infinity, minHeight: 48)
            .accessibilityLabel(label)
            .accessibilityAddTraits(selected ? .isSelected : [])
        } else {
            classicButton
        }
    }

    private var classicButton: some View {
        let bg = selected ? groupColor : colors.surfaceContainerHigh
        let fg = selected ? colors.onPrimary : colors.onSurfaceVariant

        return Button(action: onClick) {
            Text(label)
                .font(.system(size: 12, weight: selected ? .bold : .regular))
                .foregroundColor(fg)
                .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(SleepyButtonStyle())
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
        let periodMins = config.effectivePeriodMinutes()
        let durationAssigns = config.effectivePeriodAssignments()

        if rows.isEmpty {
            Text(L10n.format("empty_placeholder"))
                .font(.system(size: 16))   // ← 原 无 style 参数 = bodyLarge 16
                .foregroundColor(colors.onSurfaceVariant)
        } else {
            VStack(spacing: 2) {
                ForEach(Array(rows.enumerated()), id: \.offset) { i, slot in
                    // ← 原版本 L469-476 durationLabel: 已分配 period 追加 " · N 分钟 长/短课时"
                    let durationLabel: String = {
                        guard let mins = periodMins.indices.contains(i) ? periodMins[i] : nil else { return "" }
                        if let idx = durationAssigns.indices.contains(i) ? durationAssigns[i] : nil,
                           config.durations.indices.contains(idx) {
                            let label = config.durations[idx].isLong
                                ? L10n.format("long_duration")
                                : L10n.format("short_duration")
                            return " · " + L10n.format("duration_period_n", mins, label)
                        }
                        return ""
                    }()
                    // ★ 崩溃修复: %1$@ 要求 CVarArg 为对象 — Int 传 %@ 在
                    //   String(format:) 下野指针(SIGSEGV)。显式转 String。
                    Text(L10n.format("period_time_range", "\(slot.node)", slot.start, slot.end) + durationLabel)
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
        // ← M3 filled TextField: label 浮动(有值 = 12pt 在值上方), suffix 在字段内右侧
        HStack(spacing: 4) {
            VStack(alignment: .leading, spacing: 2) {
                if !label.isEmpty {
                    Text(label)
                        .font(.system(size: 12))
                        .foregroundColor(colors.onSurfaceVariant)
                }
                TextField("", text: Binding(
                    get: { text.isEmpty ? "\(value)" : text },
                    set: { newText in
                        // 纯数字 + 最多 4 位(对齐 原版本)
                        if newText.allSatisfy({ $0.isNumber }) && newText.count <= 4 {
                            text = newText
                            if let parsed = Int(newText) { onValueChange(parsed) }
                        }
                    }
                ))
                .keyboardType(.numberPad)
                .accessibilityIdentifier("number_\(label)")   // ← G5: 数字字段锚点
                .font(.system(size: 16))
            }
            if !unit.isEmpty {
                Text(unit)
                    .font(.system(size: 16))
                    .foregroundColor(colors.onSurfaceVariant)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading) // ← 原 TextField weight(1f) 填满 + filled 高 56dp
        .background(colors.surfaceContainer)
        .cornerRadius(SleepyTheme.fieldShape)
        // ← 原版本 NumberField = filled TextField, 无描边(Material3 filled 无 border)
        .onAppear { text = "\(value)" }
        .onChange(of: value) { newValue in text = "\(newValue)" }
    }
}

// ← AddBreakChip
private struct AddBreakChip: View {
    @Environment(\.sleepyUIStyle) private var style
    let id: String
    let label: String
    let color: Color
    let onAdd: () -> Void

    var body: some View {
        Button(action: onAdd) {
            HStack(spacing: 4) {
                AndroidMaterialIcon(name: .add, size: 16)
                    .foregroundColor(color)
                Text(L10n.format("add_label", label))
                    .font(.system(size: 14, weight: .medium))   // ← FilterChip labelLarge 14sp
                    .foregroundColor(color)
            }
            .padding(.horizontal, style == .liquidGlass ? 0 : 10)
            .padding(.vertical, style == .liquidGlass ? 0 : 6)
            .frame(minHeight: style == .liquidGlass ? nil : 32)   // ← M3 FilterChip 标准高 32dp
            .sleepyControlSurface(cornerRadius: 8, tint: color.opacity(SleepyTheme.Alpha.tinted))
        }
        .buttonStyle(SleepyPlatformButtonStyle(cornerRadius: 8))
        .frame(minHeight: style == .liquidGlass ? 44 : nil)
        .tint(color.opacity(SleepyTheme.Alpha.tinted))
        .accessibilityIdentifier(id)
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
