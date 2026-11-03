// DailyAgendaScreen.swift — ← ui/screen/today/DailyAgendaActivity.kt + DailyAgendaRoute.kt (v1.0.62 B5)
// 通知落地页: 所有开启提醒课表在指定日历日的合并议程 (← DailyAgendaActivity 类注释)。
// app-only (ui/ 层不进 widget/watch target); 议程数据经 DailyAgendaLoader 现读现算。
//
// 平台映射:
//   - DailyAgendaActivity(pendingIntent + EXTRA_DATE) → 通知点击走
//     SleepyNotificationDelegate.didReceive → pendingAgendaDateRaw → AppRoot 打开本页;
//     深链 sleepy://daily-agenda/<date> → onOpenURL 同一入口。
//   - DailyAgendaRoute.parse (Java LocalDate.parse 严格语义) → iOS DateUtils.parseDate
//     是宽松解析(2026-02-30 会滚动成 3 月), 必须 round-trip 校验: 回格式化 == 原文才认。

import SwiftUI

/// ← DailyAgendaRoute: 绝对日历日期(而非相对天数偏移)让旧通知点击保持稳定。
enum DailyAgendaRoute {
    static func identity(_ date: Date) -> String {
        "sleepy://daily-agenda/\(DateUtils.fullDate(date))"
    }

    /// 严格回读解析 ← LocalDate.parse: 非法/欠宽/越界日期一律 nil,
    /// 绝不静默回落到今天 (round-trip 校验挡住 DateUtils.parseDate 的宽松滚动)。
    static func parse(_ date: String?) -> Date? {
        guard let date, let parsed = DateUtils.parseDate(date),
              DateUtils.fullDate(parsed) == date else { return nil }
        return parsed
    }
}

/// 通知点击通道 — 真源在 SleepyNotificationDelegate.pendingAgendaDateRaw
/// (delegate 三 target 共源编译, 不能反向引用 ui/ 层; 本 enum 是 app 侧门面)。
/// 值为 raw "yyyy-MM-dd" 原文, 消费方经 DailyAgendaRoute.parse 严格解析。
enum PendingAgendaDate {
    static var value: String? {
        get { SleepyNotificationDelegate.pendingAgendaDateRaw }
        set { SleepyNotificationDelegate.pendingAgendaDateRaw = newValue }
    }
}

/// ← DailyAgendaScreen composable: 议程页 (Scaffold + TopAppBar + LazyColumn)。
struct DailyAgendaScreen: View {
    @Environment(\.localWakeUpColors) private var colors
    let date: Date
    let onBack: () -> Void

    // ← Activity 侧 mutableStateOf: agenda=null 加载中 / failed 出错可重试
    @State private var agenda: DailyAgenda? = nil
    @State private var failed = false
    @State private var reloadToken = 0

    /// ← DateTimeFormatter.ofLocalizedDate(FormatStyle.FULL) — 跟随 app 内语言
    /// (LocaleHelper.locale(for:)), 日期锚定 Asia/Shanghai (DateUtils 同口径)。
    private static let fullDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .none
        f.locale = LocaleHelper.locale(for: AppPrefs.shared.getLanguage())
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            SettingsTopBar(title: L10n.t("agenda_title"), onBack: onBack)
            ScrollView {
                LazyVStack(spacing: 12) {
                    Text(Self.fullDateFormatter.string(from: date))
                        .font(.system(size: 16, weight: .medium)) // ← titleMedium
                        .foregroundColor(colors.onSurface)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if failed {
                        Text(L10n.t("agenda_load_error"))
                            .font(.system(size: 16))
                            .foregroundColor(colors.onSurfaceVariant)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button(L10n.t("holiday_data_retry")) { reloadToken += 1 }
                            .buttonStyle(.plain)
                            .foregroundColor(colors.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if let agenda {
                        if agenda.items.isEmpty {
                            Text(L10n.t("agenda_empty"))
                                .font(.system(size: 16))
                                .foregroundColor(colors.onSurfaceVariant)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Text(L10n.format("agenda_count", agenda.items.count, agenda.tableCount))
                                .font(.system(size: 16))
                                .foregroundColor(colors.onSurface)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            ForEach(Array(agenda.items.enumerated()), id: \.offset) { _, item in
                                AgendaItemCard(item: item)
                            }
                        }
                    } else {
                        Text(L10n.t("loading"))
                            .font(.system(size: 16))
                            .foregroundColor(colors.onSurfaceVariant)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .background(colors.background) // ← 原 Scaffold containerColor
        .navigationBarHidden(true)
        .task(id: reloadToken) { await refresh() }
    }

    /// ← Activity.refresh(): failed 复位 → IO 现读 → agenda 就位; 异常记 failed。
    private func refresh() async {
        failed = false
        do {
            let repo = ScheduleRepository(AppDatabase.getShared())
            agenda = try await loadDailyAgenda(repository: repo, targetDate: date).agenda
        } catch {
            failed = true
        }
    }
}

/// ← LazyColumn item 内的 Card: 时间 / 课程名 / 教室 / 来源课表名 四行。
private struct AgendaItemCard: View {
    @Environment(\.localWakeUpColors) private var colors
    let item: DailyAgendaItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.timeText(unknownTime: L10n.t("agenda_time_unknown")))
                .font(.system(size: 12, weight: .medium)) // ← labelLarge
                .foregroundColor(colors.onSurfaceVariant)
            Text(item.first.course.courseName)
                .font(.system(size: 16, weight: .medium)) // ← titleMedium
                .foregroundColor(colors.onSurface)
            Text(item.first.course.room.isBlank ? L10n.t("notif_room_unknown") : item.first.course.room)
                .font(.system(size: 14))
                .foregroundColor(colors.onSurfaceVariant)
            Text(item.sourceNames(unknownTable: L10n.t("agenda_table_unknown")))
                .font(.system(size: 12)) // ← bodySmall
                .foregroundColor(colors.onSurfaceVariant)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colors.surfaceContainerLow)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
