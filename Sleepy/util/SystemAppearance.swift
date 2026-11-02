// SystemAppearance.swift — 宿主系统深浅探针(跨 target 共享)
// ← Android: (context.resources.configuration.uiMode and UI_MODE_NIGHT_MASK)
//   == Configuration.UI_MODE_NIGHT_YES
//
// 为什么需要它(Android 侧每个 widget loader 都显式算这一行):
//   AppPrefs.isDarkMode(isSystemDark:) 在 themeMode == system 时才看 isSystemDark,
//   而 iOS 侧的调用点历史上省略了该参数 → 默认 false → system 主题下宿主处于
//   深色时仍取浅色调色板。Android 的 TodayWidget.kt:464 / WeekGridWidgetProvider.kt:1015
//   / WeekListWidget.kt:170 / TwoDayWidget.kt:183 / WeekViewWidget.kt:195
//   五处一律先算 isSystemDark 再传入, iOS 必须同口径。
//
// 放在 util/ 而非 widget/: 消费方跨层(widget 装载器 + util 写侧胶水),
// widget/ 下的文件不进 watchOS 主 target 的部分组合, util/ 全 target 可编。

import Foundation
#if !os(watchOS)
import UIKit
#endif

/// 宿主当前系统深浅(等价 Android 的 uiMode 夜间标志)。
///
/// watchOS: 无 `UITraitCollection.current`(watchOS 端深浅由渲染期
/// `@Environment(\.colorScheme)` / 快照决定) → 取缺省 false。
func currentSystemDark() -> Bool {
    #if os(watchOS)
    return false
    #else
    return UITraitCollection.current.userInterfaceStyle == .dark
    #endif
}
