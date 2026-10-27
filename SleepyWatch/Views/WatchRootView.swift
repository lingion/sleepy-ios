// WatchRootView.swift — 手表根视图: TabView 分页 (今日 · 本周 · 设置)。
// 外观: prefs 快照已镜像 themeKey/themeMode → resolveWidgetScheme 同源配色
// (手表 UI 复用 widget scheme 值类型, 不引 iOS 渲染层)。

import SwiftUI

struct WatchRootView: View {
    @EnvironmentObject private var store: WatchStore
    @Environment(\.colorScheme) private var envScheme
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        // watchOS 26+ 新导航要求内容内嵌 NavigationStack — 每个 tab 各自包一层
        // (List→详情 push)。TabView 在 watchOS 10 可用 (page-style 是默认)。
        TabView {
            NavigationStack { TodayView() }
                .tabItem { Label(L10n.t("tab_today"), systemImage: "sun.max") }
            NavigationStack { WeekView() }
                .tabItem { Label(L10n.t("tab_schedule"), systemImage: "calendar") }
            NavigationStack { SettingsView() }
                .tabItem { Label(L10n.t("tab_mine"), systemImage: "gearshape") }
        }
        .environmentObject(store)
        .onChange(of: scenePhase) { phase in
            // 回前台补拉一次 (iPhone 离线期间的改动追平)
            if phase == .active { store.requestSync() }
        }
    }

    /// 当前快照 scheme (themeKey/themeMode 镜像自手机; isDark 手表按系统深浅)
    var scheme: WidgetScheme {
        let prefs = AppPrefs.shared
        let mode = prefs.getThemeMode()
        let isDark = mode == AppPrefs.THEME_MODE_SYSTEM
            ? envScheme == .dark
            : prefs.isDarkMode(isSystemDark: envScheme == .dark)
        return resolveWidgetScheme(themeKey: prefs.getThemeKey(), isDark: isDark)
    }
}
