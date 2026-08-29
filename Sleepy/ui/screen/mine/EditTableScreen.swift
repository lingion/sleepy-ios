// EditTableScreen.swift — ← ui/screen/mine/EditTableScreen.kt
// 编辑课表: 基础信息(名称/开始日期/周数)+节次时间表折叠(TimeSlotEditor 手动/自动双模式)+
// 保存(校验)+删除(确认弹窗;新建未保存表不显示)。

import SwiftUI

struct EditTableScreen: View {
    @Environment(\.localWakeUpColors) private var colors
    @ObservedObject var viewModel: ScheduleViewModel
    var tableId: Int64? = nil
    var pendingNewTableId: Int64? = nil
    let onBack: () -> Void
    var onDiscardPending: () -> Void
    let onSaved: () -> Void
    let onDeleted: () -> Void

    init(viewModel: ScheduleViewModel,
         tableId: Int64? = nil,
         pendingNewTableId: Int64? = nil,
         onBack: @escaping () -> Void,
         onDiscardPending: (() -> Void)? = nil,
         onSaved: @escaping () -> Void,
         onDeleted: @escaping () -> Void) {
        self.viewModel = viewModel
        self.tableId = tableId
        self.pendingNewTableId = pendingNewTableId
        self.onBack = onBack
        self.onDiscardPending = onDiscardPending ?? onBack
        self.onSaved = onSaved
        self.onDeleted = onDeleted
    }

    @State private var loadedTableId: Int64? = nil
    @State private var name = ""
    @State private var startDate = ""
    @State private var maxWeekText = ""
    @State private var timeSlotsExpanded = false
    @State private var error: String? = nil
    @State private var showDeleteConfirm = false
    @State private var slotRows: [TimeTableUtils.TimeSlotRow] = []
    @State private var smartConfig = SmartPeriodConfig()

    var body: some View {
        let state = viewModel.state
        // tableId == nil means edit current table
        let table = tableId != nil ? state.tables.first { $0.id == tableId } : state.currentTable

        if let table = table {
            content(table: table)
        } else {
            VStack {
                Text(L10n.format("edit_table_not_found"))
                    .foregroundColor(colors.onBackground)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func content(table: TimeTableEntity) -> some View {
        VStack(spacing: 0) {
            SettingsTopBar(title: L10n.format("edit_table_title"), onBack: handleBack)
            ScrollView {
                VStack(spacing: 14) {
                    Spacer().frame(height: 2)

                    // 基础信息
                    CardSection(title: L10n.format("edit_table_basic_info")) {
                        VStack(spacing: 12) {
                            FieldTextField(text: $name, label: L10n.format("edit_table_name"))
                            FieldTextField(text: $startDate, label: L10n.format("edit_table_start_date"),
                                           placeholder: L10n.format("edit_table_start_date_hint"))
                            FieldTextField(text: Binding(
                                get: { maxWeekText },
                                set: { maxWeekText = String($0.filter { $0.isNumber }) }
                            ), label: L10n.format("edit_table_max_week"))
                        }
                    }
                    .onAppear { loadIfNeeded(table: table) }

                    // 节次时间表(可折叠)
                    VStack(spacing: 0) {
                        Button {
                            withAnimation { timeSlotsExpanded.toggle() }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
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
                                    .foregroundColor(colors.onSurfaceVariant)
                                    .rotationEffect(.degrees(timeSlotsExpanded ? 180 : 0))
                            }
                            .padding(16)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(SleepyButtonStyle())
                        .accessibilityIdentifier("edit_table_slots_header")

                        if timeSlotsExpanded {
                            TimeSlotEditor(rows: slotRows, onRowsChange: { newRows in
                                slotRows = newRows
                            }, smartConfig: smartConfig, onSmartConfigChange: { smartConfig = $0 })
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

                    // 保存
                    Button(action: { save(table: table) }) {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark")
                            Text(L10n.format("edit_table_save"))
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colors.onPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
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
                                Text(L10n.format("edit_table_delete"))
                            }
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(colors.onErrorContainer)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
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
        .alert(L10n.format("edit_table_delete_confirm"), isPresented: $showDeleteConfirm) {
            Button(L10n.format("delete"), role: .destructive) {
                showDeleteConfirm = false
                viewModel.deleteTable(table.id)
                onDeleted()
            }
            Button(L10n.format("cancel"), role: .cancel) {}
        } message: {
            Text(L10n.format("edit_table_delete_msg", table.name))
        }
    }

    private func handleBack() {
        if pendingNewTableId != nil { onDiscardPending() } else { onBack() }
    }

    // ← remember(table.id) 状态初始化(表切换时重载)
    private func loadIfNeeded(table: TimeTableEntity) {
        guard loadedTableId != table.id else { return }
        loadedTableId = table.id
        name = table.name
        startDate = table.startDate
        maxWeekText = "\(table.maxWeek)"
        slotRows = TimeTableUtils.parseTimeSlotRows(table.timeJson)
        // smartConfig: 已存 JSON 反序列化; 否则从 slotRows 推断
        if !table.smartConfigJson.isEmpty,
           let data = table.smartConfigJson.data(using: .utf8),
           let cfg = try? JSONDecoder().decode(SmartPeriodConfig.self, from: data) {
            smartConfig = cfg
        } else {
            smartConfig = SmartPeriodConfig(
                startTime: slotRows.first.flatMap { $0.start.isEmpty ? nil : $0.start } ?? "08:00",
                totalPeriods: max(slotRows.count, 1))
        }
    }

    // ← 保存: 校验日期/时间格式 + start<end
    private func save(table: TimeTableEntity) {
        let maxWeek = Int(maxWeekText) ?? 20
        let dateOK = startDate.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
        let timeFmtOK = slotRows.allSatisfy {
            $0.start.range(of: #"^\d{2}:\d{2}$"#, options: .regularExpression) != nil &&
            $0.end.range(of: #"^\d{2}:\d{2}$"#, options: .regularExpression) != nil
        }
        let orderOK = slotRows.allSatisfy { $0.start < $0.end }
        guard dateOK && timeFmtOK && orderOK else {
            error = L10n.format("edit_table_validation_error")
            return
        }
        error = nil
        var updated = table
        updated.name = name.trimmingCharacters(in: .whitespaces).isEmpty ? table.name : name
        updated.startDate = startDate
        updated.maxWeek = maxWeek
        updated.timeJson = TimeTableUtils.buildTimeJsonFromRows(slotRows)
        if let data = try? JSONEncoder().encode(smartConfig),
           let json = String(data: data, encoding: .utf8) {
            updated.smartConfigJson = json
        } else {
            updated.smartConfigJson = ""
        }
        viewModel.updateTable(updated)
        onSaved()
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
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(colors.surfaceContainerLowest)
            .cornerRadius(SleepyTheme.fieldShape)
            .overlay(
                RoundedRectangle(cornerRadius: SleepyTheme.fieldShape)
                    .strokeBorder(colors.outline.opacity(SleepyTheme.Alpha.hairline), lineWidth: 1)
            )
            .accessibilityIdentifier("field_\(label)")   // ← G5: 字段锚点(label 原文)
            .overlay(alignment: .leading) {
                if !placeholder.isEmpty {
                    // label 浮动到左上(M3 风格近似: 前缀标签)
                    Text(label)
                        .font(.system(size: 10))
                        .foregroundColor(colors.onSurfaceVariant)
                        .padding(.leading, 12)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .offset(y: -22)
                }
            }
    }
}
