// CourseDetailSheet.swift — ← ui/component/CourseDetailSheet.kt
// 课程详情 Bottom Sheet — 仿 switchable.html .modal-backdrop
// 结构: Header(课程名) → TimeChip(secondaryContainer pill) → 字段行 → 编辑按钮。

import SwiftUI

/// Kotlin `String.isBlank()` 语义: 纯空白(含换行/制表符)也算空 — iOS 侧 .isEmpty 会把
/// "  " 当非空, 与 原版本 ifBlank/isNotBlank 分叉 (← CourseDetailSheet.kt:98/112/113/192)。
private func isNotBlank(_ text: String) -> Bool {
    !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}

private func orBlank(_ text: String, _ fallback: String) -> String {
    isNotBlank(text) ? text : fallback
}

struct CourseDetailSheet: View {
    @Environment(\.localWakeUpColors) private var colors
    @Environment(\.sleepyUIStyle) private var style
    @Environment(\.dismiss) private var dismiss
    let course: CourseEntity?
    var timeString: String? = nil
    var allCourses: [CourseEntity] = []
    var onEdit: ((CourseEntity) -> Void)? = nil
    /// 用户报障 2026-09-10: 非网格面(详情页)聚簇必须与网格同一时间域 —
    /// ownTime 课落库的 startNode/step 是表单占位值, 节点域聚簇会把时间零交集的
    /// 两门 ownTime 课(节点区间恰好相同)误判成冲突簇。nil = 旧行为(节点域)。
    var timeJson: String? = nil
    var displayDate: Date? = nil
    var occurrenceTable: TimeTableEntity? = nil
    var occurrenceRepository: ScheduleRepository? = nil
    var onOccurrenceSaved: () -> Void = {}

    @ObservedObject private var defaultTopStore = ConflictDefaultTopStore.shared

    var body: some View {
        if let course = course {
            // 冲突簇上下文(仅当 day 下 ≥2 课区间相交时才存在) — ← ConflictLayoutEngine.findClusters
            let clusterInfo = clusterOf(course)

            // Android's expanded state still wraps short content. Cap long content
            // at the native sheet's available height and keep all actions scrollable.
            ContentFittingSheet {
                VStack(alignment: .leading, spacing: 0) {
                    // Header ← SheetHeader (surface-container) — 原版本 Row verticalAlignment = Top
                    HStack(alignment: .top) {
                        Text(orBlank(course.courseName, L10n.format("course_detail_title")))
                            .font(SleepyTypography.titleLarge)
                            .foregroundColor(colors.onSurface)
                            .lineLimit(3)
                        Spacer()
                        // 有意差异: 原版本 无关闭按钮(下滑手势/点遮罩关闭), iOS 补充 ✕
                        Button {
                            onDismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .foregroundColor(colors.onSurfaceVariant)
                        }
                        .buttonStyle(SleepyPlatformButtonStyle(shape: .circle))
                        .frame(width: style == .liquidGlass ? 48 : nil,
                               height: style == .liquidGlass ? 48 : nil)
                        .accessibilityIdentifier("detail_close")
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(colors.surfaceContainer)

                    // Body
                    VStack(alignment: .leading, spacing: 12) {
                        if let timeString = timeString {
                            TimeChip(text: timeString)
                        }

                        DetailRow(key: L10n.format("course_field_name"),
                                  value: orBlank(course.courseName, "—"))
                        if isNotBlank(course.teacher) {
                            DetailRow(key: L10n.format("course_field_teacher"), value: course.teacher)
                        }
                        if isNotBlank(course.room) {
                            DetailRow(key: L10n.format("course_field_room"), value: course.room)
                        }
                        DetailRow(key: L10n.format("course_field_week"),
                                  value: L10n.format("course_week_range", course.nodeString(isShort: true),
                                                     course.startWeek, course.endWeek))
                        if isNotBlank(course.note) {
                            DetailRow(key: L10n.format("course_field_note"), value: course.note)
                        }
                        if let displayDate {
                            DetailRow(key: "本次日期", value: HolidayTransferOps.dayKey(displayDate))
                        }

                        if let cluster = clusterInfo {
                            DefaultTopPickerSection(cluster: cluster,
                                                    selectedCourseId: course.id)
                        }

                        if let onEdit = onEdit {
                            Button {
                                onEdit(course)
                            } label: {
                                Text(L10n.format("course_detail_edit_course"))
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(colors.onPrimary)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: style == .liquidGlass ? nil : 40)
                                    .sleepyControlSurface(cornerRadius: SleepyShapes.large, tint: colors.primary, prominent: true)
                            }
                            .buttonStyle(SleepyPlatformButtonStyle(prominent: true, cornerRadius: SleepyShapes.large))
                            .frame(maxWidth: .infinity, minHeight: style == .liquidGlass ? 44 : nil)
                            .tint(colors.primary)
                            .accessibilityIdentifier("detail_edit")
                        }
                        if let displayDate, let table = occurrenceTable, let repository = occurrenceRepository {
                            CourseOccurrenceActions(courseId: course.id, displayDate: displayDate, table: table,
                                                    repository: repository, onSaved: onOccurrenceSaved)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .padding(.bottom, 24)   // ← 原 外层 Column padding(bottom = 24.dp),此前 12 少了 12pt
                }
            }
            // The native sheet retains its rounded corners, grabber and swipe dismissal.
        }
    }

    private func onDismiss() {
        dismiss()
    }

    /// 找出 course 所在冲突簇(仅当 day 下 ≥2 课区间相交时才返回)。
    /// 带 timeJson 走分钟域(与网格一致), ownTime 课先归一化。
    private func clusterOf(_ course: CourseEntity) -> ConflictCluster? {
        let sameDay = allCourses.filter { $0.day == course.day }
            .map { timeJson == nil ? $0 : $0.normalizeNode(timeJson: timeJson!) }
        return ConflictLayoutEngine.findClusters(sameDay, timeJson: timeJson)
            .first { $0.courses.contains { $0.id == course.id } }
            .flatMap { $0.courses.count >= 2 ? $0 : nil }
    }
}

// 默认置顶选择区(v7.9 设计):按图层一行,每行 = radio + 该图层全部课程名(顿号/、分隔);
// 默认无勾选(系统按 primaryComparator 自动);选中 → 写 AppPrefs(持久化);再点同一项 = 取消。
private struct DefaultTopPickerSection: View {
    @Environment(\.localWakeUpColors) private var colors
    @Environment(\.sleepyUIStyle) private var style
    @ObservedObject private var defaultTopStore = ConflictDefaultTopStore.shared
    let cluster: ConflictCluster
    let selectedCourseId: Int64

    var body: some View {
        // 簇键:公式唯一真值在引擎 — 与 ConflictClusterCard / topOverrides 同源 (← conflictClusterKey)
        let layers = ConflictLayoutEngine.chainGroups(cluster.courses)
        let clusterKey = ConflictLayoutEngine.conflictClusterKey(cluster)
        let savedRepId: Int64? = defaultTopStore.map[clusterKey]

        // v7.10.16p: 单图层(全部课并排无真重叠, 链组把它们串成一条链而已)没有"谁压谁",
        // 选择置顶无意义 — ← 原 `if (layers.size < 2) return`(用户报障「没有冲突的课也弹默认置顶」)
        Group {
            if layers.count >= 2 {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.format("conflict_default_top_title"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(colors.onSurface)
                        .padding(.top, 4)
                        .padding(.bottom, 4)

                    if style == .liquidGlass {
                        Picker(L10n.format("conflict_default_top_title"), selection: Binding<Int64?>(
                            get: { layers.contains { $0.first?.id == savedRepId } ? savedRepId : nil },
                            set: { AppPrefs.shared.putConflictDefaultTop(clusterKey, $0) }
                        )) {
                            Text(L10n.format("color_auto")).tag(Optional<Int64>.none)
                            ForEach(Array(layers.enumerated()), id: \.offset) { _, layer in
                                Text(layer.map { orBlank($0.courseName, "—") }.joined(separator: "、"))
                                    .tag(Optional(layer.first!.id))
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .tint(colors.primary)
                        .accessibilityIdentifier("conflict_default_top_picker")
                    } else {
                        ForEach(Array(layers.enumerated()), id: \.offset) { _, layer in
                            let layerRepId = layer.first!.id
                            // ← 原版本 kt:192 `it.courseName.ifBlank { "—" }` — 纯空白名同样兜底 "—"
                            let label = layer.map { orBlank($0.courseName, "—") }.joined(separator: "、")
                            let selected = savedRepId == layerRepId
                            Button {
                                AppPrefs.shared.putConflictDefaultTop(clusterKey, selected ? nil : layerRepId)
                            } label: {
                                HStack(spacing: 4) {
                                    MaterialSelectionIndicator(kind: .radio, selected: selected)
                                    Text(label)
                                        .font(.system(size: 14))
                                        .foregroundColor(colors.onSurface)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(SleepyButtonStyle())
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                }
            }
        }
    }
}

// ← TimeChip
private struct TimeChip: View {
    @Environment(\.localWakeUpColors) private var colors
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(colors.onSecondaryContainer)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(colors.secondaryContainer)
            .cornerRadius(SleepyShapes.medium)
    }
}

// ← DetailRow
private struct DetailRow: View {
    @Environment(\.localWakeUpColors) private var colors
    let key: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(key)
                .font(.system(size: 14))
                .foregroundColor(colors.onSurfaceVariant)
                .frame(width: 54, alignment: .leading)
            Text(value)
                .font(.system(size: 14))
                .foregroundColor(colors.onSurface)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
