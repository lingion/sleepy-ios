// PlatformParityNotes.swift — ← util/HighRefreshRate.kt + MainActivity.kt + NoRippleClickable.kt
// 平台差异说明文件 (无 原版本 等价物 — 文件级记录, 不产出功能类型)
//
// 本文件集中记录 3 个 原版本 源文件在 iOS 端的等价适配决策, 便于移植审计回查。

import Foundation

enum PlatformParityNotes {

    // MARK: - HighRefreshRate.kt → iOS 无对应 API (系统自管)

    /**
     * 原平台: 高刷新率(流畅优先) — 用户 2026-09-04 指令: 能上高刷就上高刷。
     * 背景: app 不表态时 SurfaceFlinger 默认投 60Hz 票(FrameRateCompatibility 省电逻辑),
     * 120Hz 屏上动画只有 60 帧。原平台用窗口级 preferredDisplayModeId 把刷率钉到
     * 屏幕支持的最高档。
     *
     * iOS: ProMotion (iPhone 13 Pro+) 由 Core Animation 自动调度 — CADisplayLink
     * 按帧需求自适应 10-120Hz, 无公开 API 钉刷率 (private API 包括
     * CAPreferredFrameRateRange 仅限 Metal/游戏场景且 App Store 拒审)。
     * SwiftUI 动画在 ProMotion 设备上自动跑满 120Hz, 无 app 侧动作。
     *
     * 落点: SleepyApp.swift AppDelegate.didFinishLaunchingWithOptions 内注释
     * (2026-09-10 原生化审计时已写) — "高刷新率:iOS 无公开刷率 API,ProMotion 上
     * 系统自动调度 120Hz,无需 app 侧动作"。
     * 结论: 原 isHighRefresh 开关在 iOS 端无对应设置项 (无刷率可钉), 不移植。
     */

    // MARK: - MainActivity.kt → SleepyApp.swift + AppRootViewModel (壳不动)

    /**
     * 原 MainActivity v1.0.60 增量审计 (v1.0.59..v1.0.60 diff = 空, 壳无变化):
     *
     * 可移植逻辑已在 iOS 落地的部分:
     *   1. handleDeepLinkIntent(EXTRA_COURSE_ID) → AppRootViewModel.handleDeepLinkCourse(id)
     *      + AppRoot.handleDeepLink(url) 的 sleepy://course/<id> 路由 (平台差异表#4)
     *   2. pendingImportText / incomingImportText → PendingImportText + sleepy://import?text=
     *   3. UpdateNotifier.loadDismissedVersion + maybeCheckOnStart → iOS UpdateNotifier.shared
     *      + AboutScreen.task 触发 (iOS 入口不可改, 平台差异)
     *   4. HighRefreshRate.apply → 见上节 (iOS 无对应)
     *   5. UpdateManager.cleanOldApk → UpdateManager.cleanOldIpa() (iOS 命名对齐)
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
