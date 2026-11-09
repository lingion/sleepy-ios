// DateTimePickers.swift — ← ui/component/DateTimePickers.kt
// DatePickerField: 手动输入 + 点击图标弹原生日期选择器(Asia/Shanghai 时区换算)。
// TimePickerField: 点击输入框直接弹时间选择器(24h), 无 clock 图标。
// M3 DatePicker/TimePicker → SwiftUI DatePicker(.graphical)/自定义 24h 转盘。

import SwiftUI

// ← DatePickerField
struct DatePickerField: View {
    @Environment(\.localWakeUpColors) private var colors
    let value: String                  // yyyy-MM-dd
    let onValueChange: (String) -> Void
    let label: String
    var isError: Bool = false
    // ← 原版本 fillMaxWidth() 调用方传 true, 字段吃满可用宽
    var fillsWidth: Bool = false

    @State private var showPicker = false
    @State private var pickerDate = Date()
    // ← 原版本 rememberDatePickerState().selectedDateMillis 在用户点选日期前恒为 null;
    //   未选日期点确定不回调 onValueChange。iOS graphical DatePicker 总有选中值,
    //   用 hasSelection 记录用户是否在本弹窗内实际改选过。
    @State private var hasSelection = false

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            // ← 原版本 M3 TextField 浮动 label: 空值 = label 占位; 有值 = label 浮到值上方
            //   与 TimePickerField 同一处理 (修 P3: 同文件两套 label 表现)
            VStack(alignment: .leading, spacing: 2) {
                if !value.isEmpty {
                    Text(label)
                        .font(.system(size: 12))
                        .foregroundColor(isError ? colors.error : colors.onSurfaceVariant)
                }
                TextField(value.isEmpty ? label : "", text: Binding(
                    get: { value },
                    set: { onValueChange($0) }
                ))
                .textFieldStyle(.plain)
                // ← 原版本 M3 TextField 默认 bodyLarge 16sp
                .font(.system(size: 16))
                // ← 原版本 TextField(isError = isError) — M3 错误态 label/文字/error 色
                .foregroundColor(isError ? colors.error : colors.onSurface)
                // ← G5: 字段锚点(label 原文) — 镜像 HEAD EditTableScreen.FieldTextField
                //   的 "field_\(label)"; 本组件替换 FieldTextField 后锚点随组件内移,
                //   挂在可编辑 TextField 上(XCUITest tap+typeText 直接命中输入框)
                .accessibilityIdentifier("field_\(label)")
            }
            .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(colors.surfaceContainer)
            .cornerRadius(SleepyTheme.fieldShape)
            // ← 原 filled TextField 默认无描边; isError 时底边 error 指示线 (M3 active indicator)
            .overlay(alignment: .bottom) {
                if isError {
                    Rectangle()
                        .fill(colors.error)
                        .frame(height: 1)
                        .padding(.horizontal, 12)
                }
            }
            .accessibilityLabel(label)
            Button {
                // 初始值 = 当前输入日期(解析失败回退今天); 每次打开重置选中标记
                pickerDate = parseISO(value) ?? Date()
                hasSelection = false
                showPicker = true
            } label: {
                Image(systemName: "calendar")
                    .font(.system(size: 24))
                    .foregroundColor(colors.primary)
            }
            .buttonStyle(SleepyButtonStyle())
            // ← 原版本 Icon contentDescription = select_date
            .accessibilityLabel(L10n.format("select_date"))
        }
        .sheet(isPresented: $showPicker) {
            // ← 原版本 DatePickerDialog: 内容列 = DatePicker 本体(无 arrangedBy/Spacer),
            //   确认/取消在框架 confirm/dismiss 槽 → 内容区 spacing:0, 按钮行独立。
            ScrollView {
                VStack(spacing: 0) {
                    DatePicker("",
                               selection: Binding(
                                get: { pickerDate },
                                set: { pickerDate = $0; hasSelection = true }
                               ),
                               displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .fixedSize(horizontal: false, vertical: true)
                        .padding()
                    // ← 原版本 色块按钮行 (DatePickerDialog confirm/dismiss = M3 填充按钮:
                    //   确定 primary, 取消 secondaryContainer) — 2026-09-16 用户「裸 TextButton
                    //   无边界无色块 — 色块按钮」修复镜像; DialogActionButtons 同语言同配色。
                    DialogActionButtons(
                        confirmText: L10n.format("ok"),
                        onConfirm: {
                            // ← 原版本 selectedDateMillis?.let: 未点选日期 → 确定不回调
                            if hasSelection {
                                onValueChange(formatISO(pickerDate))
                            }
                            showPicker = false
                        },
                        dismissText: L10n.format("cancel"),
                        onDismiss: { showPicker = false },
                        confirmIdentifier: "date_picker_confirm",
                        dismissIdentifier: "date_picker_cancel"
                    )
                    .padding(.horizontal)
                    .padding(.bottom)
                }
            }
            .sheetDetents([.height(420), .large])
        }
    }

    // 原版本: Instant.atZone(ZoneId.of("Asia/Shanghai")) — iOS 用同目标时区格式化
    private var shanghaiTZ: TimeZone { TimeZone(identifier: "Asia/Shanghai") ?? .current }

    private func formatISO(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = shanghaiTZ
        // ← 原版本 DateTimeFormatter.ISO_LOCAL_DATE 恒公历拉丁数字; 不设 POSIX 时
        //   泰区等系统 locale 会把 yyyy 输出佛历纪年(2569)/非拉丁数字 → 存储值漂移
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }

    private func parseISO(_ s: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = shanghaiTZ
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: s)
    }
}

// ← TimePickerField: 点击弹时间选择器, 输入框只读
struct TimePickerField: View {
    @Environment(\.localWakeUpColors) private var colors
    let value: String                  // HH:mm
    let onValueChange: (String) -> Void
    let label: String
    // ← 原版本 weight(1f)/fillMaxWidth 调用方传 true, 字段吃满可用宽
    var fillsWidth: Bool = false
    // 「待设置」副行仅限手动作息编辑(需求侧空态提示); 其余调用方(加课/自动节次/
    // 提醒时间)保持 原版本 原形态: 空值 = label 单独占位。
    var showsPendingHint: Bool = false

    // One presentation owns one draft. Do not share the wheel's state with the
    // presenting row: the sheet can outlive a render of that row.
    @State private var selection: TimePickerSession?

    var body: some View {
        Button {
            // The name/date field may still be first responder when this is tapped.
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                            to: nil, from: nil, for: nil)
            selection = TimePickerSession(value: value)
        } label: {
            // ← 原 readOnly TextField 形态: 空值 = label 占位; 有值 = label 浮到值上方
            VStack(alignment: .leading, spacing: 2) {
                if value.isEmpty {
                    Text(label)
                        .font(.system(size: 16))
                        .foregroundColor(colors.onSurfaceVariant)
                    if showsPendingHint {
                        Text(L10n.format("slot_pending"))
                            .font(.system(size: 12))
                            .foregroundColor(colors.onSurfaceVariant)
                    }
                } else {
                    Text(label)
                        .font(.system(size: 12))
                        .foregroundColor(colors.onSurfaceVariant)
                    Text(value)
                        .font(.system(size: 16))
                        .foregroundColor(colors.onSurface)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(colors.surfaceContainer)
            .cornerRadius(SleepyTheme.fieldShape)
            // ← 原 filled TextField, 无描边
        }
        .buttonStyle(SleepyButtonStyle())
        .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
        .sheet(item: $selection) { session in
            TimePickerDialog(initialTime: session.time) { newValue in
                onValueChange(newValue)
            }
            .id(session.id)
        }
    }
}

private struct TimePickerSession: Identifiable {
    let id = UUID()
    let time: Date

    init(value: String) {
        let parts = value.split(separator: ":")
        let hour = parts.count == 2 ? Int(parts[0]) : nil
        let minute = parts.count == 2 ? Int(parts[1]) : nil
        let valid = hour.map { (0...23).contains($0) } == true
            && minute.map { (0...59).contains($0) } == true
        time = Calendar.current.date(bySettingHour: valid ? hour! : 8,
                                     minute: valid ? minute! : 0, second: 0,
                                     of: Date()) ?? Date()
    }
}

// The wheel and Confirm read the same sheet-local state. Cancel/swipe dismiss
// discard it; only Confirm publishes a value to the field.
private struct TimePickerDialog: View {
    @Environment(\.localWakeUpColors) private var colors
    @Environment(\.dismiss) private var dismiss
    @State private var pickerTime: Date
    let onConfirm: (String) -> Void

    init(initialTime: Date, onConfirm: @escaping (String) -> Void) {
        _pickerTime = State(initialValue: initialTime)
        self.onConfirm = onConfirm
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text(L10n.format("select_time"))
                    .font(.system(size: 24))
                    .foregroundColor(colors.onSurface)
                    .padding(.horizontal)
                    .padding(.top, 20)
                    .padding(.bottom, 4)
                DatePicker("", selection: $pickerTime, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .fixedSize(horizontal: false, vertical: true)
                    .environment(\.locale, Locale(identifier: "en_GB"))
                    .environment(\.calendar, Calendar.current)
                    .environment(\.timeZone, TimeZone.current)
                Spacer().frame(height: 12)
                DialogActionButtons(
                    confirmText: L10n.format("ok"),
                    onConfirm: {
                        let components = Calendar.current.dateComponents([.hour, .minute], from: pickerTime)
                        onConfirm(String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0))
                        dismiss()
                    },
                    dismissText: L10n.format("cancel"),
                    onDismiss: { dismiss() },
                    confirmIdentifier: "time_picker_confirm",
                    dismissIdentifier: "time_picker_cancel"
                )
                .padding(.horizontal)
                .padding(.bottom, 16)
            }
        }
        .sheetDetents([.height(400), .large])
    }
}
