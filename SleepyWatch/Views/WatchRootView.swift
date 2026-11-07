// WatchRootView.swift — 手表根视图: TabView 分页 (今日 · 本周 · 设置)。
// 外观: prefs 快照已镜像 themeKey/themeMode → resolveWidgetScheme 同源配色
// (手表 UI 复用 widget scheme 值类型, 不引 iOS 渲染层)。
// 深链 (PR#16): 表盘复杂功能 widgetURL(sleepy://watch?tab=today|schedule|mine)
// → onOpenURL 解析 tab 参数切到对应页。

import SwiftUI

/// Tab 选择 — 深链可驱动
enum WatchTab: Hashable { case today, schedule, mine }

struct WatchRootView: View {
    @EnvironmentObject private var store: WatchStore
    @Environment(\.colorScheme) private var envScheme
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: WatchTab = {
        // 2026-10-30 截图钩子: -SLEEPY_SHOT_TAB=today|schedule|mine (同 iOS 侧手法;
        // simctl openurl 对 watch 模拟器不通 LS 115, 改启动参数切初始 tab)
        guard let a = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("-SLEEPY_SHOT_TAB=") }) else { return .today }
        switch String(a.dropFirst("-SLEEPY_SHOT_TAB=".count)) {
        case "schedule": return .schedule
        case "mine": return .mine
        default: return .today
        }
    }()

    var body: some View {
        // watchOS 26+ 新导航要求内容内嵌 NavigationStack — 每个 tab 各自包一层
        // (List→详情 push)。TabView 在 watchOS 10 可用 (page-style 是默认)。
        TabView(selection: $selection) {
            NavigationStack { TodayView() }
                .tabItem { Label(L10n.t("tab_today"), systemImage: "sun.max") }
                .tag(WatchTab.today)
            NavigationStack { WeekView() }
                .tabItem { Label(L10n.t("tab_schedule"), systemImage: "calendar") }
                .tag(WatchTab.schedule)
            NavigationStack { SettingsView() }
                .tabItem { Label(L10n.t("tab_mine"), systemImage: "gearshape") }
                .tag(WatchTab.mine)
        }
        .environmentObject(store)
        .onChange(of: scenePhase) { phase in
            // 回前台补拉一次 (iPhone 离线期间的改动追平)
            if phase == .active { store.requestSync() }
        }
        .onOpenURL { url in
            // sleepy://watch?tab=today|schedule|mine ← 表盘 complication 深链
            guard url.host == "watch",
                  let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let tab = comps.queryItems?.first(where: { $0.name == "tab" })?.value
            else { return }
            switch tab {
            case "today": selection = .today
            case "schedule": selection = .schedule
            case "mine": selection = .mine
            default: break
            }
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
