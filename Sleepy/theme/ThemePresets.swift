// ThemePresets.swift — ← ThemePresets.kt (占位:D4 主题任务全量移植前,先立 KEY_DEFAULT 契约)
// Android: ui/theme/ThemePresets.kt 5 预设+HSV。此处仅 KEY_DEFAULT 供 AppPrefs 引用;
// 全量移植在 D4(主题)任务,届时逐函数替换本占位。

import Foundation

enum ThemePresets {
    static let KEY_DEFAULT = "default" // ← 与 Android ThemePresets.kt:22 对齐(已核)
}
