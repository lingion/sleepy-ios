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

    @State private var showPicker = false
    @State private var pickerDate = Date()

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            TextField(label, text: Binding(
                get: { value },
                set: { onValueChange($0) }
            ))
            .textFieldStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(colors.surfaceContainer)
            .cornerRadius(SleepyTheme.fieldShape)
            .overlay(
                RoundedRectangle(cornerRadius: SleepyTheme.fieldShape)
                    .strokeBorder(isError ? colors.error : colors.outline.opacity(SleepyTheme.Alpha.hairline),
                                  lineWidth: 1)
            )
            Button {
                // 初始值 = 当前输入日期(解析失败回退今天)
                pickerDate = parseISO(value) ?? Date()
                showPicker = true
            } label: {
                Image(systemName: "calendar")
                    .font(.system(size: 24))
                    .foregroundColor(colors.primary)
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $showPicker) {
            VStack(spacing: 0) {
                DatePicker("", selection: $pickerDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding()
                HStack {
                    Button(L10n.format("cancel")) { showPicker = false }
                        .frame(maxWidth: .infinity)
                    Button(L10n.format("ok")) {
                        onValueChange(formatISO(pickerDate))
                        showPicker = false
                    }
                    .foregroundColor(colors.primary)
                    .frame(maxWidth: .infinity)
                }
                .padding()
            }
            .presentationDetents([.height(420)])
        }
    }

    // Android: Instant.atZone(ZoneId.of("Asia/Shanghai")) — iOS 用同目标时区格式化
    private var shanghaiTZ: TimeZone { TimeZone(identifier: "Asia/Shanghai") ?? .current }

    private func formatISO(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = shanghaiTZ
        return f.string(from: date)
    }

    private func parseISO(_ s: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = shanghaiTZ
        return f.date(from: s)
    }
}

// ← TimePickerField: 点击弹时间选择器, 输入框只读
struct TimePickerField: View {
    @Environment(\.localWakeUpColors) private var colors
    let value: String                  // HH:mm
    let onValueChange: (String) -> Void
    let label: String

    @State private var showPicker = false
    @State private var pickerTime = Date()

    var body: some View {
        Button {
            let comps = parseHHMM(value) ?? (8, 0)
            var cal = DateUtils.isoCalendar
            pickerTime = cal.date(bySettingHour: comps.0, minute: comps.1, second: 0, of: Date()) ?? Date()
            showPicker = true
        } label: {
            HStack {
                Text(value.isEmpty ? label : value)
                    .font(.system(size: 16))
                    .foregroundColor(colors.onSurface)
                Spacer()
                if !value.isEmpty {
                    Text(label)
                        .font(.system(size: 12))
                        .foregroundColor(colors.onSurfaceVariant)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(colors.surfaceContainer)
            .cornerRadius(SleepyTheme.fieldShape)
            .overlay(
                RoundedRectangle(cornerRadius: SleepyTheme.fieldShape)
                    .strokeBorder(colors.outline.opacity(SleepyTheme.Alpha.hairline), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showPicker) {
            VStack(spacing: 0) {
                Text(L10n.format("select_time"))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(colors.onSurface)
                    .padding()
                // 24h 转盘(← M3 TimePicker is24Hour=true)
                DatePicker("", selection: $pickerTime, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                HStack {
                    Button(L10n.format("cancel")) { showPicker = false }
                        .frame(maxWidth: .infinity)
                    Button(L10n.format("ok")) {
                        let f = DateFormatter()
                        f.dateFormat = "HH:mm"
                        onValueChange(f.string(from: pickerTime))
                        showPicker = false
                    }
                    .foregroundColor(colors.primary)
                    .frame(maxWidth: .infinity)
                }
                .padding()
            }
            .presentationDetents([.height(400)])
        }
    }

    private func parseHHMM(_ s: String) -> (Int, Int)? {
        let parts = s.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        return (h, m)
    }
}
