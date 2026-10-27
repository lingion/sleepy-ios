// SettingsView.swift — 手表设置页 (2026-10 watch 伴侣 App)
// 只读镜像: 提醒开关状态来自 prefs 快照 (真源在 iPhone, 避免双向同步);
// 手动重新同步 = requestContents 补拉。

import SwiftUI
import WatchConnectivity

struct SettingsView: View {
    @EnvironmentObject private var store: WatchStore
    @Environment(\.colorScheme) private var envScheme

    var body: some View {
        let scheme = WatchPalette.scheme(envDark: envScheme == .dark)
        let prefs = AppPrefs.shared
        List {
            Section {
                ToggleRow(title: L10n.t("reminder_daily_title"), on: prefs.isReminderEnabled() && prefs.isDailyReminderEnabled(), scheme: scheme)
                ToggleRow(title: L10n.t("reminder_before_class_title"), on: prefs.isReminderEnabled() && prefs.isBeforeClassEnabled(), scheme: scheme)
                ToggleRow(title: L10n.t("reminder_tomorrow_toggle_title"), on: prefs.isReminderEnabled() && prefs.isTomorrowReminderEnabled(), scheme: scheme)
            } header: {
                Text(L10n.t("watch_settings_reminders_header"))
            } footer: {
                Text(L10n.t("watch_settings_readonly_hint"))
                    .font(.system(size: 10))
            }

            Section {
                HStack {
                    Text(L10n.t("watch_last_sync"))
                    Spacer()
                    Text(store.lastSyncDate.map(Self.fmt) ?? L10n.t("watch_never_sync"))
                        .foregroundColor(scheme.onSurfaceVariant)
                }
                Button {
                    store.requestSync()
                } label: {
                    Text(L10n.t("watch_resync_now"))
                }
                .disabled(!isSessionReady())
            }

            Section {
                if let table = store.currentTable() {
                    HStack {
                        Text(L10n.t("manage_current_table"))
                        Spacer()
                        Text(table.name).foregroundColor(scheme.onSurfaceVariant).lineLimit(1)
                    }
                }
            }
        }
        .navigationTitle(Text(L10n.t("tab_mine")))
    }

    private func isSessionReady() -> Bool {
        WCSession.isSupported() && WCSession.default.isReachable
    }

    private static func fmt(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: d)
    }
}

/// 只读开关行 — Toggle 禁用态呈现镜像值 (改在 iPhone)
private struct ToggleRow: View {
    let title: String
    let on: Bool
    let scheme: WidgetScheme
    var body: some View {
        HStack {
            Text(title)
            Spacer()
            // 手表上 Toggle 是交互控件, 用静态圆点表达状态避免「可点」误导
            Circle()
                .fill(on ? scheme.primary : scheme.surfaceVariant)
                .frame(width: 10, height: 10)
                .accessibilityLabel(on ? L10n.t("watch_mark_on") : L10n.t("watch_mark_off"))
        }
    }
}
