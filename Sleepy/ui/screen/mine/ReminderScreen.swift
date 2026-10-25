// ReminderScreen.swift — ← ui/screen/mine/ReminderScreen.kt
// 提醒设置: master 开关(通知权限) + 日期规则卡 + 每日提醒(当日/次日分闸+动态示例)
// + 课前提醒(分钟/横幅/流体云字段+可靠性诊断) + 上课自动勿扰。
// 平台映射: POST_NOTIFICATIONS 权限 → UNUserNotificationCenter.requestAuthorization;
// 流体云(Fluid Cloud)行为 Android 独有(平台差异表#3), iOS 保留开关落 prefs
// (banner 通道承担实际通知), 字段选择影响 banner 内容行文。
// 可靠性诊断 5 行 → iOS 快照仅 3 个可观测事实(通知权限/时效性/低电量),
// widget/vendor/promoted 为 no-analog(见 BackgroundReliabilitySnapshot.swift 头部映射表),
// 对应行不渲染(不是 silent skip: 映射决策已记录)。
// 所有状态变更统一走 ReminderRescheduler.shared.request()(← Android 同名枢纽;
// init_ 接线在 SleepyApp.swift, 见集成清单)。

import SwiftUI
import UserNotifications
import UIKit
import Combine

/// ← private enum class DailyReminderTimeTarget { Today, Tomorrow }
/// Identifiable: 供 .sheet(item:) 单弹窗复用(pickerTarget 非 nil 即弹)。
private enum DailyReminderTimeTarget: Identifiable {
    case today, tomorrow
    var id: Int { self == .today ? 0 : 1 }
}

@MainActor
struct ReminderScreen: View {
    @Environment(\.localWakeUpColors) private var colors
    let onDismiss: () -> Void
    /// ← Android onOpenHoliday: 打开节假日高级设置。宿主接了导航就交出去;
    /// nil(当前 iOS 调用方 SleepyApp.swift 只传 onDismiss)→ 本页自带 HolidaySettings
    /// sheet(GeneralSettings 同款组件同语义), 无需共享导航接线。
    var onOpenHoliday: (() -> Void)? = nil
    /// issue#44 接线(F095-C): 课表页 VM 提供真实 selectedTableId 与 refreshTransfer
    /// 通道(← Android SleepyNavHost.kt:299-303 的 tableId + viewModel)。
    /// VM 在 SleepyApp.scheduleViewModel 已在作用域内, 但调用点传参归共享文件集成清单;
    /// nil 时 tableId 回退 WidgetTableResolver.resolveCurrentTable —— 与本页动态示例
    /// (loadReminderSchedulePreview)同源口径, 调休映射仍可落盘, 仅缺课表页即时刷新。
    var viewModel: ScheduleViewModel? = nil

    private let prefs = AppPrefs.shared

    @State private var masterEnabled = AppPrefs.shared.isReminderEnabled()
    @State private var dateRulesEnabled = AppPrefs.shared.isHolidayReminderRulesEnabled()
    @State private var publicHolidayReminder = AppPrefs.shared.isHolidayReminderPublicHolidayEnabled()
    @State private var transferHolidayReminder = AppPrefs.shared.isHolidayReminderTransferHolidayEnabled()
    @State private var makeupWorkdayReminder = AppPrefs.shared.isHolidayReminderMakeupWorkdayEnabled()
    @State private var ordinaryWeekendReminder = AppPrefs.shared.isHolidayReminderOrdinaryWeekendEnabled()
    @State private var dailyEnabled = AppPrefs.shared.isDailyReminderEnabled()
    @State private var todayEnabled = AppPrefs.shared.isTodayReminderEnabled()
    @State private var dailyTime = AppPrefs.shared.getDailyReminderTime()
    @State private var tomorrowEnabled = AppPrefs.shared.isTomorrowReminderEnabled()
    @State private var tomorrowTime = AppPrefs.shared.getTomorrowReminderTime()
    @State private var beforeClassEnabled = AppPrefs.shared.isBeforeClassEnabled()
    @State private var minutesInput = "\(AppPrefs.shared.getBeforeClassMinutes())"
    @State private var bannerEnabled = AppPrefs.shared.isBeforeClassBannerEnabled()
    @State private var fluidEnabled = AppPrefs.shared.isBeforeClassFluidEnabled()
    @State private var fluidPrimary = AppPrefs.shared.getBeforeClassFluidPrimary()
    @State private var classDndEnabled = AppPrefs.shared.isClassDndEnabled()
    @State private var pickerTarget: DailyReminderTimeTarget? = nil
    @State private var pickerTime = Date()
    @State private var showHolidaySettings = false

    // ← reliabilitySnapshot: 诊断快照, ON_RESUME + fluidEnabled 变化时刷新
    @State private var reliabilitySnapshot: BackgroundReliabilitySnapshot? = nil
    // ← schedulePreview: 示例只读当前课表, 不参与调度; 无课表时保留通用示例文案
    @State private var schedulePreview: ReminderSchedulePreview? = nil


    var body: some View {
        VStack(spacing: 0) {
            SettingsTopBar(title: L10n.format("reminder_title"), onBack: onDismiss)
            ScrollView {
                VStack(spacing: 16) {
                    // Master toggle card
                    ReminderCard {
                        MasterToggleRow(masterEnabled: $masterEnabled) { on in
                            onMasterToggle(on)
                        }
                    }

                    // Date-based reminder rules remain independent from the general reminder master.
                    dateRulesCard

                    // Sub-settings — only visible when master is on
                    if masterEnabled {
                        dailyCard
                        beforeClassCard
                        classDndCard
                    }
                }
                .padding(16)
            }
        }
        .background(colors.background)
        .task {
            // ← LaunchedEffect(fluidEnabled): 进入页面即取一次快照
            await refreshReliabilitySnapshot()
        }
        .onChange(of: fluidEnabled) { _ in
            Task { await refreshReliabilitySnapshot() }
        }
        // ← DisposableEffect ON_RESUME: 回前台重取诊断快照
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task { await refreshReliabilitySnapshot() }
        }
        .task {
            // ← LaunchedEffect(Unit): 示例数据后台装载
            schedulePreview = await loadReminderSchedulePreview()
        }
        .sheet(item: $pickerTarget) { target in
            timePickerSheet(target)
        }
        // 节假日高级设置(本页内嵌 sheet — GeneralSettings 同款组件)
        // ← F095-B: 传当前课表 id + 刷新回调(对应 Android SleepyNavHost 的 tableId+viewModel),
        // 否则 tableId=nil → 调休卡渲染 holiday_makeup_no_table 且 saveTransfer 短路, issue#44 非持久。
        .sheet(isPresented: $showHolidaySettings) {
            HolidaySettingsScreen(onDismiss: { showHolidaySettings = false },
                                  tableId: currentSelectedTableId,
                                  refreshTransfer: { viewModel?.refreshTransfer() })
        }
    }

    /// 当前选中课表 id ← Android currentTableId(VM state)。VM 未接线时回退
    /// WidgetTableResolver.resolveCurrentTable(默认表→课程最多表), 与本页动态示例同源。
    private var currentSelectedTableId: Int64? {
        if let id = viewModel?.state.selectedTableId { return id }
        let repo = ScheduleRepository(AppDatabase.getShared())
        return WidgetTableResolver.resolveCurrentTable(repo)?.id
    }

    private func refreshReliabilitySnapshot() async {
        reliabilitySnapshot = await BackgroundReliabilityProbe.shared.snapshot()
    }

    // MARK: - 日期规则卡 ← Android 第 2 张卡

    private var dateRulesCard: some View {
        ReminderCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.format("reminder_date_rules_title"))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(colors.onSurface)
                        Text(L10n.format("reminder_date_rules_subtitle"))
                            .font(.system(size: 12))
                            .foregroundColor(colors.onSurfaceVariant)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { dateRulesEnabled },
                        set: { on in
                            dateRulesEnabled = on
                            prefs.setHolidayReminderRulesEnabled(on)
                            ReminderRescheduler.shared.request()
                        }
                    ))
                    .toggleStyle(.switch)
                    .tint(colors.primary)
                    .labelsHidden()
                    .accessibilityIdentifier("reminder_date_rules_toggle")
                }
                .padding(4)
                if !dateRulesEnabled {
                    Text(L10n.format("reminder_date_rules_inactive"))
                        .font(.system(size: 12))
                        .foregroundColor(colors.onSurfaceVariant)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    SubDivider()
                    ReminderToggleRow(title: L10n.format("reminder_date_rules_public_holiday"),
                                      subtitle: L10n.format("reminder_date_rules_advanced_subtitle"),
                                      checked: $publicHolidayReminder) {
                        publicHolidayReminder = $0
                        prefs.setHolidayReminderPublicHolidayEnabled($0)
                        ReminderRescheduler.shared.request()
                    }
                    ReminderToggleRow(title: L10n.format("reminder_date_rules_transfer_holiday"),
                                      subtitle: L10n.format("reminder_date_rules_advanced_subtitle"),
                                      checked: $transferHolidayReminder) {
                        transferHolidayReminder = $0
                        prefs.setHolidayReminderTransferHolidayEnabled($0)
                        ReminderRescheduler.shared.request()
                    }
                    ReminderToggleRow(title: L10n.format("reminder_date_rules_makeup_workday"),
                                      subtitle: L10n.format("reminder_date_rules_advanced_subtitle"),
                                      checked: $makeupWorkdayReminder) {
                        makeupWorkdayReminder = $0
                        prefs.setHolidayReminderMakeupWorkdayEnabled($0)
                        ReminderRescheduler.shared.request()
                    }
                    ReminderToggleRow(title: L10n.format("reminder_date_rules_ordinary_weekend"),
                                      subtitle: L10n.format("reminder_date_rules_advanced_subtitle"),
                                      checked: $ordinaryWeekendReminder) {
                        ordinaryWeekendReminder = $0
                        prefs.setHolidayReminderOrdinaryWeekendEnabled($0)
                        ReminderRescheduler.shared.request()
                    }
                    // ← FilledTonalButton(全宽, top 4dp)
                    Button(action: openHolidayAdvanced) {
                        Text(L10n.format("reminder_date_rules_advanced_button"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(colors.onSecondaryContainer)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)   // ← iOS FilledTonalButton 惯例(AllTablesScreen 同语言)
                            .background(colors.secondaryContainer)
                            .cornerRadius(SleepyShapes.large)
                    }
                    .buttonStyle(SleepyButtonStyle())
                    .padding(.top, 4)
                    .accessibilityIdentifier("reminder_date_rules_advanced_button")
                }
            }
        }
    }

    private func openHolidayAdvanced() {
        // 宿主给了回调(接导航)就交出去; 否则走本页内嵌 sheet(iOS 无路由表映射)
        if let onOpenHoliday = onOpenHoliday {
            onOpenHoliday()
        } else {
            showHolidaySettings = true
        }
    }

    // MARK: - 每日提醒卡(当日 + 次日)

    private var dailyCard: some View {
        ReminderCard {
            SubToggleRow(icon: "clock",
                         title: L10n.format("reminder_daily_title"),
                         subtitle: L10n.format("reminder_daily_sub"),
                         checked: $dailyEnabled,
                         toggleId: "reminder_daily_toggle") { on in
                dailyEnabled = on
                prefs.setDailyReminderEnabled(on)
                ReminderRescheduler.shared.request()
            }
            if dailyEnabled {
                SubDivider()
                ReminderToggleRow(title: L10n.format("reminder_daily_today_toggle_title"),
                                  subtitle: L10n.format("reminder_daily_today_toggle_sub"),
                                  checked: $todayEnabled) {
                    todayEnabled = $0
                    prefs.setTodayReminderEnabled($0)
                    ReminderRescheduler.shared.request()
                }
                ReminderTimeRow(label: L10n.format("reminder_daily_time_label"),
                                time: dailyTime,
                                rowId: "reminder_time_row") {
                    pickerTarget = .today
                }
                Text(todayPreviewText)
                    .font(.system(size: 12))
                    .foregroundColor(colors.onSurfaceVariant)
                    .padding(.leading, 4)
                    .padding(.top, 4)
                    .padding(.bottom, 8)
                    .padding(.trailing, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                SubDivider()
                ReminderToggleRow(title: L10n.format("reminder_tomorrow_toggle_title"),
                                  subtitle: L10n.format("reminder_tomorrow_toggle_sub"),
                                  checked: $tomorrowEnabled) {
                    tomorrowEnabled = $0
                    prefs.setTomorrowReminderEnabled($0)
                    ReminderRescheduler.shared.request()
                }
                ReminderTimeRow(label: L10n.format("reminder_tomorrow_time_label"),
                                time: tomorrowTime,
                                rowId: "reminder_tomorrow_time_row") {
                    pickerTarget = .tomorrow
                }
                Text(tomorrowPreviewText)
                    .font(.system(size: 12))
                    .foregroundColor(colors.onSurfaceVariant)
                    .padding(.leading, 4)
                    .padding(.top, 4)
                    .padding(.bottom, 8)
                    .padding(.trailing, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // ← Android todayPreviewText: 有课表示例用动态文案, 否则回退通用示例
    private var todayPreviewText: String {
        if let p = schedulePreview {
            return buildDailyPreviewText(day: p.today, dateLabelKey: "reminder_preview_today_date")
        }
        return L10n.format("reminder_daily_preview")
    }
    private var tomorrowPreviewText: String {
        if let p = schedulePreview {
            return buildDailyPreviewText(day: p.tomorrow, dateLabelKey: "reminder_preview_tomorrow_date")
        }
        return L10n.format("reminder_tomorrow_preview")
    }
    private var beforeClassPreviewText: String {
        if let p = schedulePreview {
            return buildBeforeClassPreviewText(preview: p)
        }
        return L10n.format("reminder_before_class_preview")
    }

    // MARK: - 课前提醒卡

    private var beforeClassCard: some View {
        ReminderCard {
            SubToggleRow(icon: "graduationcap",
                         title: L10n.format("reminder_before_class_title"),
                         subtitle: L10n.format("reminder_before_class_sub"),
                         checked: $beforeClassEnabled,
                         toggleId: "reminder_before_class_toggle") { on in
                beforeClassEnabled = on
                prefs.setBeforeClassEnabled(on)
                ReminderRescheduler.shared.request()
            }
            if beforeClassEnabled {
                SubDivider()
                // Free-input minutes field(★ debounce 500ms 持久化 — onChange 中经 debounce Task)
                HStack {
                    Text(L10n.format("reminder_before_minutes_label"))
                        .font(.system(size: 14))
                        .foregroundColor(colors.onSurface)
                    Spacer()
                    // ← Android TextField 120dp 宽 + suffix: 单位在框内, 不再外挂
                    HStack(spacing: 0) {
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
                        Text(L10n.format("reminder_before_minutes_unit"))
                            .font(.system(size: 14))
                            .foregroundColor(colors.onSurfaceVariant)
                            .padding(.trailing, 16) // ← Android TextField end padding 16dp(suffix 位置)
                    }
                    .frame(width: 120)
                    .padding(.vertical, 8)
                    .background(colors.surfaceContainerLowest)
                    .cornerRadius(SleepyTheme.fieldShape)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
                SubDivider()
                Text(beforeClassPreviewText)
                    .font(.system(size: 12))
                    .foregroundColor(colors.onSurfaceVariant)
                    .padding(.leading, 52)   // ← Android 课前示例唯一用 52dp 起缩进
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                    .padding(.trailing, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                SubDivider()
                ReminderToggleRow(title: L10n.format("reminder_banner_title"),
                                  subtitle: L10n.format("reminder_banner_sub"),
                                  checked: $bannerEnabled) {
                    bannerEnabled = $0
                    prefs.setBeforeClassBannerEnabled($0)
                    ReminderRescheduler.shared.request()
                }
                SubDivider()
                ReminderToggleRow(title: L10n.format("reminder_fluid_title"),
                                  subtitle: L10n.format("reminder_fluid_sub"),
                                  tag: L10n.format("reminder_experimental_tag"),
                                  checked: $fluidEnabled) {
                    fluidEnabled = $0
                    prefs.setBeforeClassFluidEnabled($0)
                    ReminderRescheduler.shared.request()
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
                                     ("room", L10n.format("reminder_fluid_field_room")),
                                     ("countdown", L10n.format("reminder_fluid_field_countdown"))], id: \.0) { key, label in
                                Button {
                                    fluidPrimary = key
                                    prefs.setBeforeClassFluidPrimary(key)
                                    ReminderRescheduler.shared.request()
                                } label: {
                                    if key == fluidPrimary {
                                        Label(label, systemImage: "circlebadge.2.fill")
                                    } else {
                                        Text(label)
                                    }
                                }
                            }
                        } label: {
                            // ← Android readOnly TextField 形态: hint 作 label 在值上方, 尾随 ExpandMore
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.format("reminder_fluid_fields_hint"))
                                    .font(.system(size: 12))
                                    .foregroundColor(colors.onSurfaceVariant)
                                HStack {
                                    Text(fluidPrimaryLabel)
                                        .font(.system(size: 16))
                                        .foregroundColor(colors.onSurface)
                                    Spacer()
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 24)) // ← Android trailingIcon ExpandMore 默认 24dp
                                        .foregroundColor(colors.onSurfaceVariant)
                                }
                            }
                            .padding(.horizontal, 16) // ← M3 TextField content padding 16dp
                            .padding(.vertical, 8)
                            .background(colors.surfaceContainerLowest)
                            .cornerRadius(SleepyTheme.fieldShape)
                        }
                        Text(L10n.format("reminder_fluid_note"))
                            .font(.system(size: 12))
                            .foregroundColor(colors.onSurfaceVariant)
                            .padding(.top, 6)
                        // ★ 流体云测试入口 / 厂商设置入口 / vendor+promoted 诊断行 = Android
                        // 平台专有(FluidCloudService 前台服务 + 厂商实况窗), iOS 无对应物 —
                        // 见文件头平台映射注释。
                        reliabilityBlock
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 8)
                }
            }
        }
    }

    // MARK: - 可靠性诊断块 ← Android reliabilitySnapshot 块(iOS 可观测子集 3 行)

    @ViewBuilder
    private var reliabilityBlock: some View {
        if let snapshot = reliabilitySnapshot {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.format("reminder_reliability_title"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(colors.onSurface)
                    .padding(.top, 10)
                // 通知权限 ← snapshot.notificationPermissionGranted
                Text(L10n.format("reminder_reliability_notification",
                                 snapshot.notificationPermissionGranted
                                     ? L10n.format("reminder_reliability_ready")
                                     : L10n.format("reminder_reliability_missing")))
                    .font(.system(size: 12))
                    .foregroundColor(snapshot.notificationPermissionGranted ? colors.onSurfaceVariant : colors.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if !snapshot.notificationPermissionGranted {
                            requestNotificationPermission()
                        }
                    }
                    .accessibilityIdentifier("reminder_reliability_notification")
                // 精确提醒 ← snapshot.reminderTransportState()/timeSensitiveAllowed
                //   (Android exactAlarmAllowed ≙ iOS 时效性通知, 见 Snapshot 头部映射表)
                Text(L10n.format("reminder_reliability_exact_alarm",
                                 exactAlarmStatusText(snapshot)))
                    .font(.system(size: 12))
                    .foregroundColor(snapshot.timeSensitiveAllowed ? colors.onSurfaceVariant : colors.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // ← Android openExactAlarmSettings: 未授权时跳系统通知设置
                        if !snapshot.timeSensitiveAllowed,
                           let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .accessibilityIdentifier("reminder_reliability_exact_alarm")
                // 电池优化 ← snapshot.lowPowerModeActive(取反语义: Android 白名单 ≙ iOS 低电量未开)
                Text(L10n.format("reminder_reliability_battery",
                                 snapshot.lowPowerModeActive
                                     ? L10n.format("reminder_reliability_missing")
                                     : L10n.format("reminder_reliability_ready")))
                    .font(.system(size: 12))
                    .foregroundColor(snapshot.lowPowerModeActive ? colors.primary : colors.onSurfaceVariant)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if snapshot.lowPowerModeActive,
                           let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .accessibilityIdentifier("reminder_reliability_battery")
                // widgetBound/liveCardState/promotedOngoingAllowed: no-analog 行不渲染
            }
        }
    }

    /// ← Android exact-alarm 行状态映射: DEGRADED_INEXACT_ALARM → degraded,
    /// 否则 allowed ? ready : missing。iOS: transport=degradedInexactAlarm(时效性不可用)
    /// 与 exactAlarmAllowed=false(timeSensitive!=.enabled)同源同值 → 统一 missing/degraded
    /// 分支保留结构一致。
    private func exactAlarmStatusText(_ snapshot: BackgroundReliabilitySnapshot) -> String {
        switch snapshot.reminderTransportState() {
        case .degradedInexactAlarm:
            return L10n.format("reminder_reliability_degraded")
        default:
            return snapshot.timeSensitiveAllowed
                ? L10n.format("reminder_reliability_ready")
                : L10n.format("reminder_reliability_missing")
        }
    }

    // MARK: - 上课自动勿扰卡 ← Android 第 4 张卡(仅 master 开时可见)

    private var classDndCard: some View {
        ReminderCard {
            ReminderToggleRow(title: L10n.format("reminder_class_dnd_title"),
                              subtitle: L10n.format("reminder_class_dnd_sub"),
                              checked: $classDndEnabled) { on in
                onClassDndToggle(on)
            }
        }
    }

    /// ← Android: 开 → 检查权限(未授权跳系统设置回读; 无系统级 DND 写 API, iOS 以
    /// 通知抑制闸实现 — 开关只需落 prefs + syncFromPrefs); 关 → prefs + syncFromPrefs。
    private func onClassDndToggle(_ on: Bool) {
        classDndEnabled = on
        prefs.setClassDndEnabled(on)
        ClassDndScheduler.shared.syncFromPrefs()
    }

    // ← fluidPrimaryLabel(含 countdown)
    private var fluidPrimaryLabel: String {
        switch fluidPrimary {
        case "name": return L10n.format("reminder_fluid_field_name")
        case "time": return L10n.format("reminder_fluid_field_time")
        case "countdown": return L10n.format("reminder_fluid_field_countdown")
        default: return L10n.format("reminder_fluid_field_room")
        }
    }

    // ★ debounce 500ms: 分钟输入停止后持久化 + 重排(避免每键 cancelAll+scheduleAll)
    // ← Android LaunchedEffect(minutesInput): 经 ReminderRescheduler 枢纽合并重排
    @State private var minutesDebounce: Task<Void, Never>? = nil
    private func scheduleMinutesPersist() {
        minutesDebounce?.cancel()
        minutesDebounce = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            guard let v = Int(minutesInput) else { return }
            let clamped = min(max(v, 1), 999)   // ← coerceIn(1, 999)
            prefs.setBeforeClassMinutes(clamped)
            ReminderRescheduler.shared.request()
        }
    }

    // MARK: - 时间选择弹窗 ← Android AlertDialog + DialogActionButtons

    private func timePickerSheet(_ target: DailyReminderTimeTarget) -> some View {
        let selectedTime = target == .today ? dailyTime : tomorrowTime
        let parts = selectedTime.split(separator: ":").compactMap { Int($0) }
        let defaultHour = target == .today ? 7 : 22   // ← Android initialHour fallback (默认 07:00/22:00)
        return VStack(spacing: 0) {
            Text(L10n.format("reminder_pick_time"))
                .font(.system(size: 24)) // ← Android AlertDialog title headlineSmall 24sp Normal
                .foregroundColor(colors.onSurface)
                .padding()
            DatePicker("", selection: $pickerTime, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
            // 2026-09-16 用户: 裸 TextButton 无边界无色块 — 统一色块按钮行
            DialogActionButtons(
                confirmText: L10n.format("action_confirm"),
                onConfirm: {
                    let f = DateFormatter()
                    f.dateFormat = "HH:mm"
                    let newTime = f.string(from: pickerTime)
                    switch target {
                    case .today:
                        dailyTime = newTime
                        prefs.setDailyReminderTime(newTime)
                    case .tomorrow:
                        tomorrowTime = newTime
                        prefs.setTomorrowReminderTime(newTime)
                    }
                    ReminderRescheduler.shared.request()
                    pickerTarget = nil
                },
                dismissText: L10n.format("action_cancel"),
                onDismiss: { pickerTarget = nil },
                // ← G5 锚点回归: HEAD 裸 HStack 按钮时代的 identifier
                //   (ReminderPermissionUITests test02/03 依赖), 色块重写后随参数穿入
                confirmIdentifier: "reminder_time_confirm",
                dismissIdentifier: "reminder_time_cancel"
            )
            .padding()
        }
        .sheetDetents([.height(400)])
        .onAppear {
            var cal = DateUtils.isoCalendar
            pickerTime = cal.date(bySettingHour: parts.first ?? defaultHour,
                                  minute: parts.count > 1 ? parts[1] : 0,
                                  second: 0, of: Date()) ?? Date()
        }
    }

    // MARK: - Master 开关(通知权限)

    private func onMasterToggle(_ on: Bool) {
        if on {
            let center = UNUserNotificationCenter.current()
            center.getNotificationSettings { settings in
                DispatchQueue.main.async {
                    switch settings.authorizationStatus {
                    case .authorized, .provisional, .ephemeral:
                        masterEnabled = true
                        prefs.setReminderEnabled(true)
                        ReminderRescheduler.shared.request()
                    case .notDetermined:
                        // ← requestNotificationPermission
                        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                            DispatchQueue.main.async {
                                if granted {
                                    masterEnabled = true
                                    prefs.setReminderEnabled(true)
                                    ReminderRescheduler.shared.request()
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
            // 关闭 master 只设 reminder_master=false + cancelAll(); scheduleAll 与各接收路径
            // 均双重检查 isReminderEnabled, 无需覆写子开关(否则重开 master 后配置全丢)。
            masterEnabled = false
            prefs.setReminderEnabled(false)
            // cancelAll 为 suspend, 后台执行避免主线程阻塞(← Android IO 协程)
            Task.detached(priority: .background) {
                await NotificationScheduler.shared.cancelAll()
            }
        }
    }

    /// ← Android requestNotificationPermission(): 可靠性诊断行「通知权限未满足」的直达入口
    private func requestNotificationPermission() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
            Task { await refreshReliabilitySnapshot() }
        }
    }

    // MARK: - 动态示例(只读当前课表, 不参与调度)← loadReminderSchedulePreview

    private func loadReminderSchedulePreview() async -> ReminderSchedulePreview? {
        await ReminderPreviewLoader.load()
    }

    private func buildDailyPreviewText(day: ReminderDayPreview, dateLabelKey: String) -> String {
        ReminderPreviewLoader.buildDailyPreviewText(day: day, dateLabelKey: dateLabelKey)
    }

    private func buildBeforeClassPreviewText(preview: ReminderSchedulePreview) -> String {
        ReminderPreviewLoader.buildBeforeClassPreviewText(preview: preview)
    }
}

// MARK: - 动态示例数据模型 ← Android private data classes

/// ← private data class ReminderCoursePreview
struct ReminderCoursePreview {
    let date: Date
    let course: CourseEntity
    let startTime: String   // "HH:mm" 或 "--:--"
}

/// ← private data class ReminderDayPreview
struct ReminderDayPreview {
    let date: Date
    let courses: [CourseEntity]
    let firstCourse: ReminderCoursePreview?
}

/// ← private data class ReminderSchedulePreview
struct ReminderSchedulePreview {
    let today: ReminderDayPreview
    let tomorrow: ReminderDayPreview
    let nextClass: ReminderCoursePreview?
}

/// ← loadReminderSchedulePreview + buildDailyPreviewText + buildBeforeClassPreviewText
/// (ReminderScreen.kt 顶层私有函数; 提为 internal 供 SleepyTests/ReminderSchedulePreviewTests 直测)
enum ReminderPreviewLoader {

    /// ← courseStartTime(course, nodes): ownTime 且 startTime 可解析("H:mm")优先,
    /// 否则按 startNode 查节点表; 都拿不到 → nil(排序时落最后 / 预览显示 "--:--")。
    static func courseStartTime(_ course: CourseEntity, nodes: [TimeTableUtils.NodeTime]) -> Date? {
        let cal = DateUtils.isoCalendar
        let today = cal.startOfDay(for: Date())
        if course.ownTime {
            let trimmed = course.startTime.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                // ← DateTimeFormatter.ofPattern("H:mm"): 小时 1-2 位、分钟恰 2 位、范围双闸
                if let secs = Self.hmmSeconds(course.startTime) {
                    return today.addingTimeInterval(TimeInterval(secs))
                }
                return nil
            }
        }
        return nodes.first { $0.node == course.startNode }?.start
    }

    /// "H:mm" → 当日秒数; 非法 → nil。(TimeTableUtils.hmToSeconds 要求两位小时,
    /// 不匹配 Android "H:mm" 模式 —— 与 ClassDndScheduler.courseInterval 的 Int 拆分同语义)
    static func hmmSeconds(_ s: String) -> Int? {
        let parts = s.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        guard parts[0].count == 1 || parts[0].count == 2, parts[1].count == 2,
              let h = Int(parts[0]), let m = Int(parts[1]),
              (0...23).contains(h), (0...59).contains(m) else { return nil }
        return h * 3600 + m * 60
    }

    /// ← loadReminderSchedulePreview(): 只读当前表; 任何失败 → nil(回退通用示例)。
    static func load() async -> ReminderSchedulePreview? {
        let repo = ScheduleRepository(AppDatabase.getShared())
        guard let table = WidgetTableResolver.resolveCurrentTable(repo) else { return nil }
        // ← runCatching + takeIf { isNotEmpty() }: 查询失败/无课 → nil(回退通用示例)
        guard let courses = try? repo.getCourses(table.id), !courses.isEmpty else { return nil }
        let nodes = TimeTableUtils.parseNodes(table.timeJson)
        let cal = DateUtils.isoCalendar
        let now = Date()
        let todayDay = cal.startOfDay(for: now)

        func coursesOn(_ date: Date) -> [CourseEntity] {
            if DateUtils.semesterStatus(startDate: table.startDate, maxWeek: table.maxWeek, today: date) != .inRange {
                return []
            }
            let week = DateUtils.currentWeek(startDate: table.startDate, today: date)
            let dow = DateUtils.todayDayOfWeek(today: date)
            return courses
                .filter { $0.day == dow && $0.inWeek(week) }
                .sorted { a, b in
                    let sa = courseStartTime(a, nodes: nodes)
                    let sb = courseStartTime(b, nodes: nodes)
                    switch (sa, sb) {
                    case (nil, nil): return a.startNode < b.startNode
                    case (nil, .some): return false   // ← ?: LocalTime.MAX 落最后
                    case (.some, nil): return true
                    case let (.some(x), .some(y)) where x == y: return a.startNode < b.startNode
                    case let (.some(x), .some(y)): return x < y
                    }
                }
        }

        func dayPreview(_ date: Date) -> ReminderDayPreview {
            let dayCourses = coursesOn(date)
            let first = dayCourses.first.map { course in
                ReminderCoursePreview(
                    date: date,
                    course: course,
                    startTime: Self.timeText(courseStartTime(course, nodes: nodes))
                )
            }
            return ReminderDayPreview(date: date, courses: dayCourses, firstCourse: first)
        }

        // ← nextClass: 搜索窗口 maxWeek.coerceAtLeast(1)*7+7 天
        var nextClass: ReminderCoursePreview? = nil
        let searchDays = max(table.maxWeek, 1) * 7 + 7
        for offset in 0...searchDays {
            guard let date = cal.date(byAdding: .day, value: offset, to: todayDay) else { continue }
            let candidate = coursesOn(date)
                .compactMap { course -> ReminderCoursePreview? in
                    guard let start = courseStartTime(course, nodes: nodes) else { return nil }
                    if offset == 0 && start <= now { return nil }      // ← !start.isAfter(LocalTime.now())
                    return ReminderCoursePreview(date: date, course: course, startTime: Self.timeText(start))
                }
                .min(by: { $0.startTime < $1.startTime })
            if let candidate = candidate {
                nextClass = candidate
                break
            }
        }

        return ReminderSchedulePreview(
            today: dayPreview(todayDay),
            tomorrow: dayPreview(cal.date(byAdding: .day, value: 1, to: todayDay) ?? todayDay),
            nextClass: nextClass
        )
    }

    /// ← start.format(PREVIEW_TIME_FORMAT) ?: "--:--" (HH:mm)
    static func timeText(_ start: Date?) -> String {
        guard let start = start else { return "--:--" }
        return TimeTableUtils.formatTime(start)
    }

    /// ← buildDailyPreviewText(context, day, dateLabelRes)
    static func buildDailyPreviewText(day: ReminderDayPreview, dateLabelKey: String) -> String {
        let dateLabel = L10n.format(dateLabelKey,
                                    DateUtils.shortDateSlash(day.date),
                                    DateUtils.localizedDay(DateUtils.todayDayOfWeek(today: day.date)))
        guard let first = day.firstCourse else {
            return L10n.format("reminder_daily_preview_dynamic_no_course", dateLabel)
        }
        // ← Android ifBlank: 纯空白也算空 → 落默认文案(与 isEmpty 不同)
        let courseName = first.course.courseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? L10n.format("default_course_name") : first.course.courseName
        let room = first.course.room.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? L10n.format("notif_room_unknown") : first.course.room
        // ← Android trim().takeIf{…}.let{ getString(…, it) }: 传入的是 trim 后的名字
        let teacherTrimmed = first.course.teacher.trimmingCharacters(in: .whitespacesAndNewlines)
        let teacherText = teacherTrimmed.isEmpty
            ? "" : L10n.format("reminder_preview_teacher", teacherTrimmed)
        // 模板含混合位置符(%@…%lld…%4$s): Darwin String(format:) 会崩溃(实测), 走 resolveFormat
        let tmpl = L10n.t("reminder_daily_preview_dynamic")
        return Self.resolveFormat(tmpl, [dateLabel, String(day.courses.count), courseName,
                                         first.startTime, room, teacherText])
    }

    /// ← buildBeforeClassPreviewText(context, preview)
    static func buildBeforeClassPreviewText(preview: ReminderSchedulePreview) -> String {
        guard let next = preview.nextClass else {
            return L10n.format("reminder_before_class_preview_dynamic_no_course")
        }
        let dateLabel = L10n.format("reminder_preview_date",
                                    DateUtils.shortDateSlash(next.date),
                                    DateUtils.localizedDay(DateUtils.todayDayOfWeek(today: next.date)))
        // ← Android ifBlank(空白视为空) + teacher 传 trim 后的名字(与 daily 构建函数同语义)
        let courseName = next.course.courseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? L10n.format("default_course_name") : next.course.courseName
        let room = next.course.room.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? L10n.format("notif_room_unknown") : next.course.room
        let teacherTrimmed = next.course.teacher.trimmingCharacters(in: .whitespacesAndNewlines)
        let teacherText = teacherTrimmed.isEmpty
            ? "" : L10n.format("reminder_preview_teacher", teacherTrimmed)
        let tmpl = L10n.t("reminder_before_class_preview_dynamic")
        return Self.resolveFormat(tmpl, [dateLabel, courseName, next.startTime, room, teacherText])
    }

    /// Android 位置参数语义(%1$s..%N$s / %N$lld / 顺序 %@ %lld)在 Darwin 上的等价实现:
    /// 顺序 %@/%lld 依序消耗实参, %N$xx 显式取第 N 个(1-based)。
    /// 仅 reminder_daily_preview_dynamic / reminder_before_class_preview_dynamic 两模板需要
    /// (它们混用顺序与显式位置符); 其余键走 L10n.format。纯函数, 单测锁定。
    static func resolveFormat(_ template: String, _ args: [String]) -> String {
        var out = ""
        var seq = 0   // 顺序占位符消费指针
        var i = template.startIndex
        while i < template.endIndex {
            guard template[i] == "%" else {
                out.append(template[i]); i = template.index(after: i); continue
            }
            // 解析 %% / %N$x / %@ / %lld
            let next = template.index(after: i)
            if next < template.endIndex && template[next] == "%" {
                out.append("%"); i = template.index(after: next); continue
            }
            var j = next
            var numStr = ""
            while j < template.endIndex, template[j].isNumber {
                numStr.append(template[j]); j = template.index(after: j)
            }
            let positional = j < template.endIndex && template[j] == "$"
            if positional { j = template.index(after: j) }
            // 读类型字符(可能多字符: lld / s / d, 仅 ASCII —— isLetter 是 Unicode
            // 感知的, 会把紧随其后的 CJK 正文吞进 spec)。'@'(Darwin 顺序占位符)
            // 是单字符转换符, 消费一个即停。
            var spec = ""
            while j < template.endIndex, template[j].isASCII, template[j].isLetter {
                spec.append(template[j]); j = template.index(after: j)
            }
            if spec.isEmpty, j < template.endIndex, template[j] == "@" {
                j = template.index(after: j)
            }
            let idx: Int
            if positional, let n = Int(numStr) {
                idx = n - 1
            } else {
                idx = seq; seq += 1
            }
            out.append((idx >= 0 && idx < args.count) ? args[idx] : "")
            i = j
        }
        return out
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

// ← ReminderTimeRow(可点时间行, label 左 + 值右 primary)
private struct ReminderTimeRow: View {
    @Environment(\.localWakeUpColors) private var colors
    let label: String
    let time: String
    var rowId: String? = nil
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            HStack {
                Text(label)
                    .font(.system(size: 14))
                    .foregroundColor(colors.onSurface)
                Spacer()
                Text(time)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(colors.primary)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(SleepyButtonStyle())
        .modifier(OptionalToggleId(id: rowId))
    }
}

// ← ReminderToggleRow(无图标, 课前子项/日期规则子开关)
// tag = Android 同名参数: 尾随「实验」pill(labelSmall 11 primary, 胶囊底 primary α0.12,
// padding 6×2)。enabled 参数 Android 仅在 dateRulesEnabled==true 分支传 false 不可达, iOS 省略。
private struct ReminderToggleRow: View {
    @Environment(\.localWakeUpColors) private var colors
    let title: String
    let subtitle: String
    var tag: String? = nil
    @Binding var checked: Bool
    let onCheckedChange: (Bool) -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {   // ← Android Spacer(6.dp) 标题与 tag 间距
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(colors.onSurface)
                    if let tag = tag {
                        Text(tag)
                            .font(.system(size: 11, weight: .medium))
                            .tracking(0.5)   // ← M3 labelSmall letterSpacing 0.5
                            .foregroundColor(colors.primary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(colors.primary.opacity(0.12))
                            .clipShape(Capsule())   // ← RoundedCornerShape(50)
                    }
                }
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
