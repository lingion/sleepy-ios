// WatchPalette.swift — 手表视图配色入口 (2026-10 watch 伴侣 App)
// prefs 快照镜像 themeKey/themeMode → resolveWidgetScheme 同源配色;
// isDark: themeMode=system 时按手表系统深浅, 锁定 light/dark 用镜像值 (widget 同规则)。

import SwiftUI

enum WatchPalette {
    static func scheme(envDark: Bool) -> WidgetScheme {
        let prefs = AppPrefs.shared
        let mode = prefs.getThemeMode()
        let isDark = mode == AppPrefs.THEME_MODE_SYSTEM
            ? envDark
            : prefs.isDarkMode(isSystemDark: envDark)
        return resolveWidgetScheme(themeKey: prefs.getThemeKey(), isDark: isDark)
    }
}
