// AppearanceNavigationRow.swift — ← ui/screen/mine/AppearanceNavigationRow.kt
// 外观页二级入口行(节次表头/课表显示等), 单行纯标题 + 右侧 chevron。
// 视觉对齐 M3 ListItem: surfaceContainer 底, 12dp 圆角, 16dp 内外边距。
//
// 调用方现状: 组件本体与 Android 1:1; iOS AppearanceScreen Section④「节次表头」入口
// 已落地(AppearanceScreen.swift 分组④ ← AppearanceScreen.kt:213-222), AppearanceScreen
// 已带 onOpenPeriodHeaderSettings 参数(默认 no-op)。剩余接线均在共享文件(SleepyApp /
// SleepyRoutes / SleepyNavHost / SleepyNavigator): 在 SleepyApp 的 PresentOverlay .theme
// 分支给 AppearanceScreen 传 onOpenPeriodHeaderSettings = { root.overlayScreen =
// .periodHeaderSettings } 并分发该屏(需新增 OverlayScreen/PresentOverlay 承接),
// SleepyRoutes/SleepyNavHost 放行该路由 — 完整清单见交付 needs_shared_wiring。

import SwiftUI

struct AppearanceNavigationRow: View {
    @Environment(\.localWakeUpColors) private var colors
    let title: String
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            HStack(spacing: 0) {
                Text(title)
                    .font(.system(size: 16))    // ← Android bodyLarge 16sp
                    .foregroundColor(colors.onSurface)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 20))    // ← ChevronRight 默认 24dp, 20pt 为全 app chevron 惯例(General/HolidaySettingsScreen 同值)
                    .foregroundColor(colors.onSurfaceVariant)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .buttonStyle(SleepyButtonStyle())
        .frame(maxWidth: .infinity)
        .background(colors.surfaceContainer)
        .cornerRadius(SleepyShapes.medium)
    }
}
