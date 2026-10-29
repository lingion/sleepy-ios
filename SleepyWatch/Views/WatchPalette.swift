// WatchPalette.swift — 手表视图配色入口 (2026-10 watch 伴侣 App)
// prefs 快照镜像 themeKey/themeMode → resolveWidgetScheme 同源配色;
// isDark: themeMode=system 时按手表系统深浅, 锁定 light/dark 用镜像值 (widget 同规则)。
//
// WidgetScheme 无 error token (widget 精简 scheme), 手表侧补 M3 标准 error 色:
// light=#B3261E / dark=#F2B8B5 (← Theme.swift WakeUpColorScheme.error 同源)。

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

    /// M3 error 色 — WidgetScheme 不含此 token, 手表侧补 (节假日标注等场景)
    /// light=#B3261E / dark=#F2B8B5 ← Theme.swift WakeUpColorScheme.error 同源
    static func errorColor(isDark: Bool) -> Color {
        isDark ? Color(0xFFF2B8B5) : Color(0xFFB3261E)
    }
}
