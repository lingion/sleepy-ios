// CalendarImportDialog.swift — ← ui/screen/mine/CalendarImportDialog.kt
// 系统日历导入弹窗 — 目标日历/范围/调休/提醒/早课闹钟 + 预览 + 二次确认 + 增量同步结果。

import SwiftUI

struct CalendarImportDialog: View {
    @Environment(\.localWakeUpColors) private var colors
    let table: TimeTableEntity
    let courses: [CourseEntity]
    let onDismiss: () -> Void

    @State private var calendars: [SystemCalendarInfo] = []
    @State private var selectedCalendarId: String = ""
    @State private var range: CalendarImportRange = .NEXT_WEEK
    @State private var transfersEnabled: Bool = false
    @State private var reminderEnabled: Bool = false
    @State private var reminderMinutes: String = "15"
    @State private var alarmEnabled: Bool = false
    @State private var alarmMinutes: String = "60"
    @State private var calendarMenu: Bool = false
    @State private var preview: CalendarImportPreview?
    @State private var result: CalendarImportResult?
    @State private var managedCount: Int = 0
    @State private var showFinalConfirm: Bool = false
    @State private var showDeleteConfirm: Bool = false
    @State private var deleteResultText: String?
    @State private var busy: Bool = false
    @State private var hasTransfers: Bool = false

    private var prefs: AppPrefs { AppPrefs.shared }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 10) {
                    if calendars.isEmpty {
                        Text(L10n.t("calendar_no_writable_calendar"))
                            .font(.subheadline)
                            .foregroundColor(colors.onSurfaceVariant)
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(colors.surfaceContainer)
                            .cornerRadius(12)
                    } else {
                        Group {
                            targetPicker
                            rangePicker
                            if hasTransfers { transferToggle }
                            reminderToggle
                            if reminderEnabled { reminderField }
                            alarmToggle
                            if alarmEnabled {
                                alarmScope
                                alarmField
                                alarmDisclaimer
                            }
                            previewButton
                        }
                        previewSection
                        resultSection
                        deleteManagedButton
                    }
                    if busy { ProgressView() }
                    doneButtons
                }
                .padding(20)
            }
            .navigationTitle(L10n.t("calendar_import_title"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(.stack)
        .onAppear(perform: loadState)
        .confirmationDialog(L10n.t("calendar_choose_target"), isPresented: $calendarMenu, titleVisibility: .visible) {
            ForEach(calendars) { cal in
                Button("\(cal.displayName) · \(cal.accountName)") {
                    selectedCalendarId = cal.id
                    prefs.setCalendarTargetId(cal.id)
                    preview = nil
                }
            }
        }
        .alert(L10n.t("calendar_final_confirm_title"), isPresented: $showFinalConfirm) {
            // ← Android TextButton(enabled = !busy): iOS 15 alert 按钮无 disabled API,
            //   busy 屏蔽下沉到动作本体 (runImport/runDelete 首行 guard !busy)。
            Button(L10n.t("calendar_final_import_action")) { runImport() }
            Button(L10n.t("cancel"), role: .cancel) {}
        } message: {
            Text(L10n.format("calendar_final_confirm_body", preview?.rows.count ?? 0))
        }
        .alert(L10n.t("calendar_delete_confirm_title"), isPresented: $showDeleteConfirm) {
            Button(L10n.t("calendar_delete_action"), role: .destructive) { runDelete() }
            Button(L10n.t("cancel"), role: .cancel) {}
        } message: {
            Text(L10n.format("calendar_delete_confirm_body", managedCount))
        }
    }

    // MARK: - 段落

    // ← Android SettingsFlatCard(title = calendar_target_label, subtitle = calendar_choose_target):
    //   副标题恒可见; 按钮标签 = 已选日历或占位文案(↔ TextButton 双写)。
    //   options 为空 = 单开关卡, 控件由 content 露出(↔ Android content 尾槽)。
    private var targetPicker: some View {
        SettingsFlatCard(
            title: L10n.t("calendar_target_label"),
            subtitle: L10n.t("calendar_choose_target"),
            options: [],
            selectedIndex: .constant(0)
        ) {
            Button {
                calendarMenu = true
            } label: {
                HStack {
                    Text(calendars.first(where: { $0.id == selectedCalendarId })
                        .map { "\($0.displayName) · \($0.accountName)" }
                        ?? L10n.t("calendar_choose_target"))
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundColor(colors.onSurfaceVariant)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var rangePicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.t("calendar_range_label"))
                .font(.subheadline.weight(.semibold))
            ForEach([CalendarImportRange.NEXT_WEEK, .NEXT_MONTH, .SEMESTER], id: \.self) { candidate in
                Button {
                    range = candidate
                    prefs.setCalendarImportRange(candidate.rawValue)
                    preview = nil
                } label: {
                    HStack {
                        Image(systemName: range == candidate ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(range == candidate ? .accentColor : .secondary)
                        Text(rangeLabel(candidate))
                            .foregroundColor(.primary)
                        Spacer()
                    }
                }
            }
        }
        .padding(12)
        .background(colors.surfaceContainer)
        .cornerRadius(12)
    }

    private func rangeLabel(_ r: CalendarImportRange) -> String {
        switch r {
        case .NEXT_WEEK: return L10n.t("calendar_range_week")
        case .NEXT_MONTH: return L10n.t("calendar_range_month")
        case .SEMESTER: return L10n.t("calendar_range_semester")
        }
    }

    private var transferToggle: some View {
        Toggle(L10n.t("calendar_apply_transfers"), isOn: $transfersEnabled)
            .onChange(of: transfersEnabled) { v in
                prefs.setCalendarApplyTransfers(v)
                preview = nil
            }
            .padding(12)
            .background(colors.surfaceContainer)
            .cornerRadius(12)
    }

    private var reminderToggle: some View {
        Toggle(L10n.t("calendar_normal_reminder"), isOn: $reminderEnabled)
            .onChange(of: reminderEnabled) { v in
                prefs.setCalendarReminderMinutes(v ? (Int(reminderMinutes) ?? 15) : nil)
                preview = nil
            }
            .padding(12)
            .background(colors.surfaceContainer)
            .cornerRadius(12)
    }

    private var reminderField: some View {
        HStack {
            TextField(L10n.t("calendar_minutes_before"), text: $reminderMinutes)
                .keyboardType(.numberPad)
                .onChange(of: reminderMinutes) { v in
                    let filtered = String(v.filter { $0.isNumber }.prefix(3))
                    if filtered != v { reminderMinutes = filtered }
                    prefs.setCalendarReminderMinutes(Int(filtered) ?? 15)
                    preview = nil
                }
            Text(L10n.t("reminder_before_minutes_unit"))
                .foregroundColor(colors.onSurfaceVariant)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(colors.surfaceContainer)
        .cornerRadius(10)
    }

    private var alarmToggle: some View {
        Toggle(L10n.t("calendar_first_period_alarm"), isOn: $alarmEnabled)
            .onChange(of: alarmEnabled) { v in
                prefs.setCalendarFirstAlarmEnabled(v)
                preview = nil
            }
            .padding(12)
            .background(colors.surfaceContainer)
            .cornerRadius(12)
    }

    private var alarmScope: some View {
        Text(L10n.t("calendar_first_period_scope"))
            .font(.caption)
            .foregroundColor(colors.onSurfaceVariant)
    }

    private var alarmField: some View {
        HStack {
            TextField(L10n.t("calendar_alarm_minutes_before"), text: $alarmMinutes)
                .keyboardType(.numberPad)
                .onChange(of: alarmMinutes) { v in
                    let filtered = String(v.filter { $0.isNumber }.prefix(3))
                    if filtered != v { alarmMinutes = filtered }
                    prefs.setCalendarFirstAlarmMinutes(Int(filtered) ?? 60)
                    preview = nil
                }
            Text(L10n.t("reminder_before_minutes_unit"))
                .foregroundColor(colors.onSurfaceVariant)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(colors.surfaceContainer)
        .cornerRadius(10)
    }

    private var alarmDisclaimer: some View {
        Text(L10n.t("calendar_alarm_disclaimer"))
            .font(.caption)
            .foregroundColor(colors.error)
    }

    private var previewButton: some View {
        Button {
            runPreview()
        } label: {
            Text(L10n.t("calendar_preview_action"))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .buttonStyle(.borderedProminent)
        .disabled(busy || selectedCalendarId.isEmpty)
    }

    private static let previewDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static func marks(for row: CalendarImportPreviewRow) -> String {
        var parts: [String] = []
        if row.transferred { parts.append(L10n.t("calendar_transfer_mark")) }
        if row.firstPeriodAlarm { parts.append(L10n.t("calendar_alarm_mark")) }
        return parts.isEmpty ? "" : " · " + parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var previewSection: some View {
        if let p = preview {
            VStack(alignment: .leading, spacing: 5) {
                Text(L10n.format("calendar_preview_count", p.rows.count))
                    .font(.subheadline.weight(.semibold))
                if p.skippedInvalidTime > 0 {
                    Text(L10n.format("calendar_invalid_skipped", p.skippedInvalidTime))
                        .font(.caption)
                        .foregroundColor(colors.onSurfaceVariant)
                }
                // ← Android p.rows.take(8).forEach 位置迭代。date 可重复(同日多课=常态),
                //   id: \.date 会因重复 id 产生 SwiftUI 未定义行为(丢行/错行更新),
                //   用 enumerated offset 作位置 id。
                ForEach(Array(p.rows.prefix(8).enumerated()), id: \.offset) { _, row in
                    Text("\(Self.previewDateFormatter.string(from: row.date))  \(row.start)–\(row.end)  \(row.courseName)\(Self.marks(for: row))")
                        .font(.caption)
                }
                if p.rows.count > 8 {
                    Text(L10n.format("calendar_more_rows", p.rows.count - 8))
                        .font(.caption)
                        .foregroundColor(colors.onSurfaceVariant)
                }
                Text(L10n.t("calendar_second_confirm_warning"))
                    .font(.caption)
                    .foregroundColor(colors.error)
                Button {
                    showFinalConfirm = true
                } label: {
                    Text(L10n.t("calendar_confirm_import"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .disabled(p.rows.isEmpty || busy)
            }
            .padding(12)
            .background(colors.surfaceContainer)
            .cornerRadius(12)
        }
    }

    @ViewBuilder
    private var resultSection: some View {
        if let outcome = result {
            Text(L10n.format("calendar_result_summary",
                             outcome.inserted, outcome.updated, outcome.unchanged,
                             outcome.skippedEdited, outcome.skippedInvalidTime,
                             outcome.alarmFallback, outcome.errors))
                .font(.caption)
                .foregroundColor(colors.onSurfaceVariant)
        }
        if let dr = deleteResultText {
            Text(dr)
                .font(.caption)
                .foregroundColor(colors.onSurfaceVariant)
        }
    }

    @ViewBuilder
    private var deleteManagedButton: some View {
        if managedCount > 0 {
            Button {
                showDeleteConfirm = true
            } label: {
                Text(L10n.format("calendar_delete_managed", managedCount))
                    .foregroundColor(colors.error)
            }
            .disabled(busy)
        }
    }

    // ← Android DialogActionButtons(ok/cancel): 全 app 弹窗动作行唯一入口,
    //   替代手写 .bordered/.borderedProminent(视觉语言不一致 + 无换行布局策略)。
    private var doneButtons: some View {
        DialogActionButtons(
            confirmText: L10n.t("ok"),
            onConfirm: onDismiss,
            dismissText: L10n.t("cancel"),
            onDismiss: onDismiss
        )
    }

    // MARK: - 动作

    private func currentOptions() -> CalendarImportOptions {
        return CalendarImportOptions(
            calendarId: selectedCalendarId,
            range: range,
            applyHolidayTransfers: transfersEnabled,
            reminderMinutes: reminderEnabled ? min(max(Int(reminderMinutes) ?? 15, 0), 999) : nil,
            firstPeriodAlarmEnabled: alarmEnabled,
            firstPeriodAlarmMinutes: min(max(Int(alarmMinutes) ?? 60, 0), 999)
        )
    }

    private func loadState() {
        selectedCalendarId = prefs.getCalendarTargetId() ?? ""
        range = CalendarImportRange(rawValue: prefs.getCalendarImportRange()) ?? .NEXT_WEEK
        // ← Android AppPrefs.isCalendarApplyTransfers 默认 true (AppPrefs.kt getBoolean(KEY, true))。
        //   iOS UserDefaults.bool(forKey:) 未设置恒 false → 首运行开关状态漂移, 此处直读原始键补 true 默认。
        //   根修在 AppPrefs.isCalendarApplyTransfers()(共享文件, 本任务禁改, 已报 needs_shared_wiring)。
        transfersEnabled = (prefs.sharedBackedStore.object(forKey: AppPrefs.KEY_CALENDAR_APPLY_TRANSFERS) as? Bool) ?? true
        reminderEnabled = prefs.getCalendarReminderMinutes() != nil
        reminderMinutes = String(prefs.getCalendarReminderMinutes() ?? 15)
        alarmEnabled = prefs.isCalendarFirstAlarmEnabled()
        alarmMinutes = String(prefs.getCalendarFirstAlarmMinutes())
        hasTransfers = !prefs.getHolidayTransfers(table.id).isEmpty

        Task {
            calendars = SystemCalendarManager.writableCalendars()
            if !calendars.contains(where: { $0.id == selectedCalendarId }) {
                selectedCalendarId = calendars.first?.id ?? ""
                if !selectedCalendarId.isEmpty {
                    prefs.setCalendarTargetId(selectedCalendarId)
                }
            }
            let dao = CalendarImportRecordDao(db: AppDatabase.getShared().dbQueue)
            managedCount = (try? dao.forTable(table.id))?.count ?? 0
        }
    }

    private func runPreview() {
        busy = true
        let options = currentOptions()
        prefs.setCalendarTargetId(options.calendarId)
        Task {
            let p = await Task.detached(priority: .userInitiated) {
                SystemCalendarManager.buildPreview(table: table, courses: courses, options: options)
            }.value
            await MainActor.run {
                preview = p
                result = nil
                busy = false
            }
        }
    }

    private func runImport() {
        // ← Android TextButton(enabled = !busy): iOS 15 alert 按钮无法置灰,
        //   busy 屏蔽落在动作入口 — busy 期间再次确认直接忽略。
        guard !busy else { return }
        busy = true
        let options = currentOptions()
        Task {
            let r = await SystemCalendarManager.import(table: table, courses: courses, options: options, batchId: UUID().uuidString)
            let dao = CalendarImportRecordDao(db: AppDatabase.getShared().dbQueue)
            let count = (try? dao.forTable(table.id))?.count ?? 0
            await MainActor.run {
                result = r
                managedCount = count
                busy = false
            }
        }
    }

    private func runDelete() {
        // ← Android TextButton(enabled = !busy): 同上, busy 期间再次确认直接忽略。
        guard !busy else { return }
        busy = true
        Task {
            let deleted = await SystemCalendarManager.deleteManagedForTable(tableId: table.id)
            let dao = CalendarImportRecordDao(db: AppDatabase.getShared().dbQueue)
            let count = (try? dao.forTable(table.id))?.count ?? 0
            await MainActor.run {
                deleteResultText = L10n.format("calendar_delete_result",
                                                deleted.deleted, deleted.skippedEdited, deleted.missing)
                managedCount = count
                busy = false
            }
        }
    }
}
