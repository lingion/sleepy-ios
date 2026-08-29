// ReminderScreen.swift — ← ui/screen/mine/ReminderScreen.kt
// 提醒设置: master 开关(通知权限)+每日提醒(时间)+课前提醒(分钟/横幅/流体云字段)。
// 平台映射: POST_NOTIFICATIONS 权限 → UNUserNotificationCenter.requestAuthorization;
// 流体云(Fluid Cloud)行为 Android 独有(平台差异表#3), iOS 保留开关落 prefs
// (banner 通道承担实际通知), 字段选择影响 banner 内容行文。

import SwiftUI
import UserNotifications

struct ReminderScreen: View {
    @Environment(\.localWakeUpColors) private var colors
    let onBack: () -> Void

    private let prefs = AppPrefs.shared

    @State private var masterEnabled = AppPrefs.shared.isReminderEnabled()
    @State private var dailyEnabled = AppPrefs.shared.isDailyReminderEnabled()
    @State private var dailyTime = AppPrefs.shared.getDailyReminderTime()
    @State private var beforeClassEnabled = AppPrefs.shared.isBeforeClassEnabled()
    @State private var minutesInput = "\(AppPrefs.shared.getBeforeClassMinutes())"
    @State private var bannerEnabled = AppPrefs.shared.isBeforeClassBannerEnabled()
    @State private var fluidEnabled = AppPrefs.shared.isBeforeClassFluidEnabled()
    @State private var fluidPrimary = AppPrefs.shared.getBeforeClassFluidPrimary()
    @State private var showTimePicker = false
    @State private var pickerTime = Date()

    var body: some View {
        VStack(spacing: 0) {
            SettingsTopBar(title: L10n.format("reminder_title"), onBack: onBack)
            ScrollView {
                VStack(spacing: 16) {
                    // Master toggle card
                    ReminderCard {
                        MasterToggleRow(masterEnabled: $masterEnabled) { on in
                            onMasterToggle(on)
                        }
                    }

                    // Sub-settings — only visible when master is on
                    if masterEnabled {
                        dailyCard
                        beforeClassCard
                    }
                }
                .padding(16)
            }
        }
        .background(colors.background)
        // Time picker dialog
        .sheet(isPresented: $showTimePicker) {
            VStack(spacing: 0) {
                Text(L10n.format("reminder_pick_time"))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(colors.onSurface)
                    .padding()
                DatePicker("", selection: $pickerTime, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                HStack {
                    Button(L10n.format("action_cancel")) { showTimePicker = false }
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("reminder_time_cancel")
                    Button(L10n.format("action_confirm")) {
                        let f = DateFormatter()
                        f.dateFormat = "HH:mm"
                        dailyTime = f.string(from: pickerTime)
                        prefs.setDailyReminderTime(dailyTime)
                        NotificationScheduler.shared.scheduleAll()
                        showTimePicker = false
                    }
                    .accessibilityIdentifier("reminder_time_confirm")
                    .foregroundColor(colors.primary)
                    .frame(maxWidth: .infinity)
                }
                .padding()
            }
            .presentationDetents([.height(400)])
        }
    }

    // ← Daily reminder card
    private var dailyCard: some View {
        ReminderCard {
            SubToggleRow(icon: "clock",
                         title: L10n.format("reminder_daily_title"),
                         subtitle: L10n.format("reminder_daily_sub"),
                         checked: $dailyEnabled,
                         toggleId: "reminder_daily_toggle") { on in
                dailyEnabled = on
                prefs.setDailyReminderEnabled(on)
                NotificationScheduler.shared.scheduleAll()
            }
            if dailyEnabled {
                SubDivider()
                Button {
                    let parts = dailyTime.split(separator: ":").compactMap { Int($0) }
                    var cal = DateUtils.isoCalendar
                    pickerTime = cal.date(bySettingHour: parts.first ?? 7,
                                          minute: parts.count > 1 ? parts[1] : 0,
                                          second: 0, of: Date()) ?? Date()
                    showTimePicker = true
                } label: {
                    HStack {
                        Text(L10n.format("reminder_daily_time_label"))
                            .font(.system(size: 14))
                            .foregroundColor(colors.onSurface)
                        Spacer()
                        Text(dailyTime)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(colors.primary)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(SleepyButtonStyle())
                .accessibilityIdentifier("reminder_time_row")
                SubDivider()
                Text(L10n.format("reminder_daily_preview"))
                    .font(.system(size: 12))
                    .foregroundColor(colors.onSurfaceVariant)
                    .padding(.leading, 52)
                    .padding(.vertical, 8)
                    .padding(.trailing, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // ← Before-class reminder card
    private var beforeClassCard: some View {
        ReminderCard {
            SubToggleRow(icon: "graduationcap",
                         title: L10n.format("reminder_before_class_title"),
                         subtitle: L10n.format("reminder_before_class_sub"),
                         checked: $beforeClassEnabled,
                         toggleId: "reminder_before_class_toggle") { on in
                beforeClassEnabled = on
                prefs.setBeforeClassEnabled(on)
                NotificationScheduler.shared.scheduleAll()
            }
            if beforeClassEnabled {
                SubDivider()
                // Free-input minutes field(★ debounce 500ms 持久化 — onChange 中经 debounce Task)
                HStack {
                    Text(L10n.format("reminder_before_minutes_label"))
                        .font(.system(size: 14))
                        .foregroundColor(colors.onSurface)
                    Spacer()
                    TextField("10", text: Binding(
                        get: { minutesInput },
                        set: { txt in
                            let digits = String(txt.filter { $0.isNumber })
                            if digits.isEmpty {
                                minutesInput = ""
                            } else if (Int(digits) ?? 0) <= 999 {
                                minutesInput = digits
                                scheduleMinutesPersist()
                            }
                        }
                    ))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .frame(width: 110)
                    .padding(.vertical, 8)
                    .background(colors.surfaceContainerLowest)
                    .cornerRadius(SleepyTheme.fieldShape)
                    .overlay(
                        RoundedRectangle(cornerRadius: SleepyTheme.fieldShape)
                            .strokeBorder(colors.outline.opacity(SleepyTheme.Alpha.hairline), lineWidth: 1)
                    )
                    Text(L10n.format("reminder_before_minutes_unit"))
                        .font(.system(size: 14))
                        .foregroundColor(colors.onSurfaceVariant)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
                SubDivider()
                Text(L10n.format("reminder_before_class_preview"))
                    .font(.system(size: 12))
                    .foregroundColor(colors.onSurfaceVariant)
                    .padding(.leading, 52)
                    .padding(.vertical, 8)
                    .padding(.trailing, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                SubDivider()
                ReminderToggleRow(title: L10n.format("reminder_banner_title"),
                                  subtitle: L10n.format("reminder_banner_sub"),
                                  checked: $bannerEnabled) {
                    bannerEnabled = $0
                    prefs.setBeforeClassBannerEnabled($0)
                    NotificationScheduler.shared.scheduleAll()
                }
                SubDivider()
                ReminderToggleRow(title: L10n.format("reminder_fluid_title"),
                                  subtitle: L10n.format("reminder_fluid_sub"),
                                  checked: $fluidEnabled) {
                    fluidEnabled = $0
                    prefs.setBeforeClassFluidEnabled($0)
                    NotificationScheduler.shared.scheduleAll()
                }
                if fluidEnabled {
                    SubDivider()
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.format("reminder_fluid_fields"))
                            .font(.system(size: 14))
                            .foregroundColor(colors.onSurface)
                        // 字段选择(Menu + 单选标记)
                        Menu {
                            ForEach([("name", L10n.format("reminder_fluid_field_name")),
                                     ("time", L10n.format("reminder_fluid_field_time")),
                                     ("room", L10n.format("reminder_fluid_field_room"))], id: \.0) { key, label in
                                Button {
                                    fluidPrimary = key
                                    prefs.setBeforeClassFluidPrimary(key)
                                    NotificationScheduler.shared.scheduleAll()
                                } label: {
                                    if key == fluidPrimary {
                                        Label(label, systemImage: "circlebadge.2.fill")
                                    } else {
                                        Text(label)
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Text(fluidPrimaryLabel)
                                    .font(.system(size: 16))
                                    .foregroundColor(colors.onSurface)
                                Spacer()
                                Text(L10n.format("reminder_fluid_fields_hint"))
                                    .font(.system(size: 12))
                                    .foregroundColor(colors.onSurfaceVariant)
                                Image(systemName: "chevron.down")
                                    .foregroundColor(colors.onSurfaceVariant)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(colors.surfaceContainerLowest)
                            .cornerRadius(SleepyTheme.fieldShape)
                            .overlay(
                                RoundedRectangle(cornerRadius: SleepyTheme.fieldShape)
                                    .strokeBorder(colors.outline.opacity(SleepyTheme.Alpha.hairline), lineWidth: 1)
                            )
                        }
                        Text(L10n.format("reminder_fluid_note"))
                            .font(.system(size: 12))
                            .foregroundColor(colors.onSurfaceVariant)
                            .padding(.top, 6)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 8)
                }
            }
        }
    }

    // ← fluidPrimaryLabel
    private var fluidPrimaryLabel: String {
        switch fluidPrimary {
        case "name": return L10n.format("reminder_fluid_field_name")
        case "time": return L10n.format("reminder_fluid_field_time")
        default: return L10n.format("reminder_fluid_field_room")
        }
    }

    // ★ debounce 500ms: 分钟输入停止后持久化 + 重排(避免每键 cancelAll+scheduleAll)
    @State private var minutesDebounce: Task<Void, Never>? = nil
    private func scheduleMinutesPersist() {
        minutesDebounce?.cancel()
        minutesDebounce = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            guard let v = Int(minutesInput) else { return }
            let clamped = min(max(v, 1), 999)
            prefs.setBeforeClassMinutes(clamped)
            NotificationScheduler.shared.scheduleAll()
        }
    }

    // ← onMasterToggle: 开=查/请求权限; 关=只关 master + cancelAll(不覆写子开关)
    private func onMasterToggle(_ on: Bool) {
        if on {
            let center = UNUserNotificationCenter.current()
            center.getNotificationSettings { settings in
                DispatchQueue.main.async {
                    switch settings.authorizationStatus {
                    case .authorized, .provisional, .ephemeral:
                        masterEnabled = true
                        prefs.setReminderEnabled(true)
                        NotificationScheduler.shared.scheduleAll()
                    case .notDetermined:
                        // ← requestNotificationPermission
                        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                            DispatchQueue.main.async {
                                if granted {
                                    masterEnabled = true
                                    prefs.setReminderEnabled(true)
                                    NotificationScheduler.shared.scheduleAll()
                                } else {
                                    // Permission denied → revert to off
                                    masterEnabled = false
                                    prefs.setReminderEnabled(false)
                                }
                            }
                        }
                    default:
                        // denied → 引导去系统设置;先回退 off
                        masterEnabled = false
                        prefs.setReminderEnabled(false)
                    }
                }
            }
        } else {
            masterEnabled = false
            prefs.setReminderEnabled(false)
            Task { await NotificationScheduler.shared.cancelAll() }
        }
    }
}

// ← MasterToggleRow(带图标)
private struct MasterToggleRow: View {
    @Environment(\.localWakeUpColors) private var colors
    @Binding var masterEnabled: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            IconBox(icon: "bell")
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.format("reminder_master_title"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(colors.onSurface)
                Text(L10n.format("reminder_master_sub"))
                    .font(.system(size: 12))
                    .foregroundColor(colors.onSurfaceVariant)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { masterEnabled },
                set: { onToggle($0) }
            ))
            .toggleStyle(.switch)
            .tint(colors.primary)
            .labelsHidden()
            .accessibilityIdentifier("reminder_master_toggle")
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
    }
}

// ← SubToggleRow(带图标子开关)
private struct SubToggleRow: View {
    @Environment(\.localWakeUpColors) private var colors
    let icon: String
    let title: String
    let subtitle: String
    @Binding var checked: Bool
    let onCheckedChange: (Bool) -> Void
    var toggleId: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            IconBox(icon: icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(colors.onSurface)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(colors.onSurfaceVariant)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { checked },
                set: { onCheckedChange($0) }
            ))
            .toggleStyle(.switch)
            .tint(colors.primary)
            .labelsHidden()
            .modifier(OptionalToggleId(id: toggleId))
        }
        .padding(4)
    }
}

private struct OptionalToggleId: ViewModifier {
    let id: String?
    func body(content: Content) -> some View {
        if let id = id {
            content.accessibilityIdentifier(id)
        } else {
            content
        }
    }
}

// ← ReminderToggleRow(无图标, 课前子项)
private struct ReminderToggleRow: View {
    @Environment(\.localWakeUpColors) private var colors
    let title: String
    let subtitle: String
    @Binding var checked: Bool
    let onCheckedChange: (Bool) -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(colors.onSurface)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(colors.onSurfaceVariant)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { checked },
                set: { onCheckedChange($0) }
            ))
            .toggleStyle(.switch)
            .tint(colors.primary)
            .labelsHidden()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }
}

// ← IconBox
private struct IconBox: View {
    @Environment(\.localWakeUpColors) private var colors
    let icon: String

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 20))
            .foregroundColor(colors.onPrimaryContainer)
            .frame(width: 36, height: 36)
            .background(colors.primaryContainer)
            .cornerRadius(SleepyShapes.small)
    }
}

// ← ReminderCard
private struct ReminderCard<Content: View>: View {
    @Environment(\.localWakeUpColors) private var colors
    @ViewBuilder let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.surfaceContainer)
        .cornerRadius(SleepyShapes.large)
    }
}

// ← SubDivider
private struct SubDivider: View {
    @Environment(\.localWakeUpColors) private var colors
    var body: some View {
        Rectangle()
            .fill(colors.outline.opacity(SleepyTheme.Alpha.hairline))
            .frame(height: 1)
            .padding(.leading, 52)
    }
}
