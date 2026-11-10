// PlatformParityNotes.swift — ← util/HighRefreshRate.kt + MainActivity.kt + NoRippleClickable.kt
// 平台差异说明文件 (无 原版本 等价物 — 文件级记录, 不产出功能类型)
//
// 本文件集中记录 3 个 原版本 源文件在 iOS 端的等价适配决策, 便于移植审计回查。

import Foundation

enum PlatformParityNotes {

    // MARK: - HighRefreshRate.kt → iOS 按需调度（无窗口固定刷新率开关）

    /**
     * 原平台: 高刷新率(流畅优先) — 用户 2026-09-04 指令: 能上高刷就上高刷。
     * 背景: app 不表态时 SurfaceFlinger 默认投 60Hz 票(FrameRateCompatibility 省电逻辑),
     * 120Hz 屏上动画只有 60 帧。原平台用窗口级 preferredDisplayModeId 把刷率钉到
     * 屏幕支持的最高档。
     *
     * iOS: CADisplayLink.preferredFrameRateRange 是公开的刷新率范围提示 API，
     * CADisableMinimumFrameDurationOnPhone 可允许相应设备使用更高帧率；两者
     * 都不能强制屏幕固定刷新率。SwiftUI / Core Animation 按内容、功耗和系统
     * 条件调度，不保证每段动画都达到 120Hz。
     *
     * 本 App 未移植 Android 的窗口固定高刷开关；这是当前产品与渲染策略，
     * 并非 iOS 不存在公开 API 或使用公开 API 会被拒审。
     * 官方依据: Apple《Optimizing iPhone and iPad apps to support ProMotion displays》
     * https://developer.apple.com/documentation/quartzcore/optimizing-iphone-and-ipad-apps-to-support-promotion-displays
     */

    // MARK: - MainActivity.kt → SleepyApp.swift + AppRootViewModel (壳不动)

    /**
     * 原 MainActivity v1.0.60 增量审计 (v1.0.59..v1.0.60 diff = 空, 壳无变化):
     *
     * 可移植逻辑已在 iOS 落地的部分:
     *   1. handleDeepLinkIntent(EXTRA_COURSE_ID) → AppRootViewModel.handleDeepLinkCourse(id)
     *      + AppRoot.handleDeepLink(url) 的 sleepy://course/<id> 路由 (平台差异表#4)
     *   2. pendingImportText / incomingImportText → PendingImportText + sleepy://import?text=
     *   3. UpdateNotifier(冷启动检查更新) → 1.0.64 随「获取更新」切片整体移除
     *      (分发收敛 App Store/TestFlight, GitHub 仅源码公开)
     *   4. HighRefreshRate.apply → 见上节（未移植窗口固定刷新率开关）
     *   5. UpdateManager.cleanOldApk → 同随更新切片移除
     *   6. 深链路由表 (sleepy://open | sleepy://course/<id> | sleepy://import?text=)
     *      已在 SleepyApp.swift AppRoot.handleDeepLink 集中定义 — 即 原平台侧
     *      handleDeepLinkIntent 的路由表抽出, 壳本身不动。
     */

    // MARK: - NoRippleClickable.kt → iOS 无 ripple (系统默认行为即无涟漪)

    /**
     * 原平台: 无涟漪点击 — 全 app 自定义可点面(Box/Row/Text 上的 clickable)唯一入口。
     * 视觉策略: 自定义表面不渲染涟漪, 涟漪反馈只保留给 M3 标准组件。
     *
     * iOS: SwiftUI Button 默认无涟漪/高亮扩散效果 (只有 opacity 变化, 见
     * SleepyButtonStyle), UIKit 默认也无 ripple。原平台需要显式禁用, iOS 默认即
     * "无涟漪" — Modifier.noRippleClickable 的 iOS 等价 = 普通 Button +
     * SleepyButtonStyle (全 app 已统一使用)。
     * 结论: 不产出 Swift 文件, 本说明即为交付。
     */
}
