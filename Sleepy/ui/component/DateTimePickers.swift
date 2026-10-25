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
    // ← Android fillMaxWidth() 调用方传 true, 字段吃满可用宽
    var fillsWidth: Bool = false

    @State private var showPicker = false
    @State private var pickerDate = Date()
    // ← Android rememberDatePickerState().selectedDateMillis 在用户点选日期前恒为 null;
    //   未选日期点确定不回调 onValueChange。iOS graphical DatePicker 总有选中值,
    //   用 hasSelection 记录用户是否在本弹窗内实际改选过。
    @State private var hasSelection = false

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            // ← Android M3 TextField 浮动 label: 空值 = label 占位; 有值 = label 浮到值上方
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
                // ← Android M3 TextField 默认 bodyLarge 16sp
                .font(.system(size: 16))
                // ← Android TextField(isError = isError) — M3 错误态 label/文字/error 色
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
            // ← Android filled TextField 默认无描边; isError 时底边 error 指示线 (M3 active indicator)
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
            // ← Android Icon contentDescription = select_date
            .accessibilityLabel(L10n.format("select_date"))
        }
        .sheet(isPresented: $showPicker) {
            // ← Android DatePickerDialog: 内容列 = DatePicker 本体(无 arrangedBy/Spacer),
            //   确认/取消在框架 confirm/dismiss 槽 → 内容区 spacing:0, 按钮行独立。
            VStack(spacing: 0) {
                DatePicker("",
                           selection: Binding(
                            get: { pickerDate },
                            set: { pickerDate = $0; hasSelection = true }
                           ),
                           displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding()
                // ← Android 色块按钮行 (DatePickerDialog confirm/dismiss = M3 填充按钮:
                //   确定 primary, 取消 secondaryContainer) — 2026-09-16 用户「裸 TextButton
                //   无边界无色块 — 色块按钮」修复镜像; DialogActionButtons 同语言同配色。
                DialogActionButtons(
                    confirmText: L10n.format("ok"),
                    onConfirm: {
                        // ← Android selectedDateMillis?.let: 未点选日期 → 确定不回调
                        if hasSelection {
                            onValueChange(formatISO(pickerDate))
                        }
                        showPicker = false
                    },
                    dismissText: L10n.format("cancel"),
                    onDismiss: { showPicker = false }
                )
                .padding(.horizontal)
                .padding(.bottom)
            }
            .sheetDetents([.height(420)])
        }
    }

    // Android: Instant.atZone(ZoneId.of("Asia/Shanghai")) — iOS 用同目标时区格式化
    private var shanghaiTZ: TimeZone { TimeZone(identifier: "Asia/Shanghai") ?? .current }

    private func formatISO(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = shanghaiTZ
        // ← Android DateTimeFormatter.ISO_LOCAL_DATE 恒公历拉丁数字; 不设 POSIX 时
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
    // ← Android weight(1f)/fillMaxWidth 调用方传 true, 字段吃满可用宽
    var fillsWidth: Bool = false

    @State private var showPicker = false
    @State private var pickerTime = Date()

    var body: some View {
        Button {
            let comps = parseHHMM(value) ?? (8, 0)
            var cal = DateUtils.isoCalendar
            pickerTime = cal.date(bySettingHour: comps.0, minute: comps.1, second: 0, of: Date()) ?? Date()
            showPicker = true
        } label: {
            // ← Android readOnly TextField 形态: 空值 = label 占位; 有值 = label 浮到值上方
            VStack(alignment: .leading, spacing: 2) {
                if value.isEmpty {
                    Text(label)
                        .font(.system(size: 16))
                        .foregroundColor(colors.onSurfaceVariant)
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
            // ← Android filled TextField, 无描边
        }
        .buttonStyle(SleepyButtonStyle())
        .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
        .sheet(isPresented: $showPicker) {
            // ← Android text = Column(verticalArrangement = spacedBy(8.dp)) { TimePicker;
            //   Spacer(12.dp); DialogActionButtons } — 8/12 pt 间距镜像
            VStack(spacing: 8) {
                Text(L10n.format("select_time"))
                    // ← Android AlertDialog title = headlineSmall 24sp Normal
                    .font(.system(size: 24))
                    .foregroundColor(colors.onSurface)
                    .padding(.horizontal)
                    .padding(.top, 20)
                    .padding(.bottom, 4)
                // 24h 转盘(← M3 TimePicker is24Hour=true;en_GB 强制 24h,不随系统 12h 设置)
                DatePicker("", selection: $pickerTime, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .environment(\.locale, Locale(identifier: "en_GB"))
                Spacer().frame(height: 12)
                // ← Android DialogActionButtons 色块按钮行 (2026-09-16 用户: 裸 TextButton
                //   无边界无色块 — 统一色块按钮行)
                DialogActionButtons(
                    confirmText: L10n.format("ok"),
                    onConfirm: {
                        let f = DateFormatter()
                        f.dateFormat = "HH:mm"
                        // ← Android padStart 恒拉丁数字 24h; POSIX locale 防非拉丁数字系统 locale
                        f.locale = Locale(identifier: "en_US_POSIX")
                        onValueChange(f.string(from: pickerTime))
                        showPicker = false
                    },
                    dismissText: L10n.format("cancel"),
                    onDismiss: { showPicker = false }
                )
                .padding(.horizontal)
            }
            .sheetDetents([.height(400)])
        }
    }

    private func parseHHMM(_ s: String) -> (Int, Int)? {
        let parts = s.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        return (h, m)
    }
}
