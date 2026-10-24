import SwiftUI

// SleepyMaterialTransition — Android ui/nav/SleepyMaterialTransition.kt →
// iOS 参数表等价. Android 侧官方 predictive-back 由 NavDisplay 三槽位消费
// (transitionSpec/popTransitionSpec/predictivePopTransitionSpec);
// iOS 侧 overlay 转场由 PresentOverlay 的 .transition + .animation 承担,
// 本文件集中导出"改时长改一处"的常量表 + 消费指引.
//
// 物理 (Android 原文 1:1 翻译):
//   forward (push):  入页 fadeIn(110ms) + scaleIn(0.92→1, Center) 220ms FastOutSlowIn
//                    (新页从中心浮起, 不从边缘滑入)
//                    出页 fadeOut + scaleOut(1→0.92, Center) 220ms
//   pop:             入页 None (目标页原地不动); 出页 fadeOut + scaleOut(→0.92) 220ms
//   predictive commit: tween(200ms, CubicBezier(0.2,0,0,1)) scale 0.92 + fade
//   predictive cancel: spring(NoBouncy, StiffnessMediumLow) — 拉回弹
//
// 分相实现: AnyTransition.animation() 为 iOS 13+ API, combined 的 opacity 段与
// scale 段可分别挂曲线 — 与 Android sleepyForwardEnter() 的
// fadeIn(forwardFadeInTween 110ms) + scaleIn(forwardTween 220ms) 逐段对齐,
// 不再依赖消费点分段驱动。转场自带曲线优先于环境 withAnimation。
// FastOutSlowIn(0.4,0.0,0.2,1) 是 Material 标准曲线;
// predictive commit 的 (0.2,0,0,1) 即 SwiftUI .easeIn 同族曲线.

enum SleepyMaterialTransition {
    static let forwardDuration: Double = 0.220
    static let forwardFadeIn: Double = 0.110
    static let predictiveDuration: Double = 0.200
    static let scaleFrom: Double = 0.92

    /// forward 入页: fadeIn(110ms) + scaleIn(0.92→1, Center)(220ms) 分相 —
    /// 对应 Android `sleepyForwardEnter()` = fadeIn(forwardFadeInTween) +
    /// scaleIn(forwardTween, 0.92, Center)。opacity 段挂 `forwardFadeInAnimation`,
    /// scale 段挂 `forwardAnimation`; 消费点只需
    /// `.transition(SleepyMaterialTransition.forwardEnter)` 即获得同款分相视感。
    static let forwardEnter: AnyTransition =
        AnyTransition.opacity.animation(forwardFadeInAnimation)
            .combined(with: AnyTransition
                .scale(scale: scaleFrom, anchor: .center)
                .animation(forwardAnimation))

    /// forward 出页 / pop 出页: 淡出 + 缩向 0.92 —
    /// 对应 Android `sleepyForwardExit()` / `sleepyPopExit()` =
    /// fadeOut(forwardTween) + scaleOut(forwardTween, 0.92, Center),
    /// 两段都 220ms FastOutSlowIn, 显式挂曲线, 不依赖消费点环境动画。
    static let forwardExit: AnyTransition =
        AnyTransition.opacity.animation(forwardAnimation)
            .combined(with: AnyTransition
                .scale(scale: scaleFrom, anchor: .center)
                .animation(forwardAnimation))

    /// forward (push) 完整转场 = Android `sleepyForwardTransform`
    /// (ContentTransform(sleepyForwardEnter(), sleepyForwardExit(), zIndex 1)) 等价:
    /// insertion = forwardEnter (110ms 淡入 + 220ms 中心浮起),
    /// removal   = forwardExit (淡出 + 缩向 0.92, 220ms)。
    /// 单一浮层容器的消费点用它即可一次拿到入/出两侧, 与 popTransform/predictivePopTransform
    /// 构成与 Android 三槽位 (transitionSpec / popTransitionSpec /
    /// predictivePopTransitionSpec) 一一对应的符号组。
    static let forwardTransform: AnyTransition =
        .asymmetric(insertion: forwardEnter, removal: forwardExit)

    /// forward 推入的驱动曲线 (Android FastOutSlowIn 220ms tween).
    static var forwardAnimation: Animation {
        .timingCurve(0.4, 0.0, 0.2, 1.0, duration: forwardDuration)
    }

    /// Android `sleepyForwardEnter()` 入页 fadeIn 的 110ms 快速分相
    /// (`forwardFadeInTween`)。已直接挂进 `forwardEnter` 的 opacity 段 —
    /// 分相在单一消费点即生效, `forwardFadeIn` 不再只是无人应用的死常量。
    static var forwardFadeInAnimation: Animation {
        .timingCurve(0.4, 0.0, 0.2, 1.0, duration: forwardFadeIn)
    }

    /// pop (程序化返回) 入页 = None 等价: 目标页原地不动、零入场动画
    /// (Android `sleepyPopEnter(): EnterTransition.None` ⇄ `AnyTransition.identity`).
    static let popEnter: AnyTransition = .identity

    /// NavDisplay popTransitionSpec 等价: 入页 identity + 出页 fadeOut+scaleOut(→0.92)
    /// (Android `sleepyPopTransform = ContentTransform(sleepyPopEnter(), sleepyPopExit())`).
    static let popTransform: AnyTransition =
        .asymmetric(insertion: popEnter, removal: forwardExit)

    /// predictive commit 入页 (Android sleepyPredictivePopTransform 的 targetContentEnter
    /// = scaleIn(predictiveCommitTween, 0.92) + fadeIn(predictiveCommitTween)):
    /// scale 0.92→1 + 淡入, 两段都挂 200ms CubicBezier(0.2,0,0,1)。
    static let predictiveEnter: AnyTransition =
        AnyTransition.opacity.animation(predictiveCommitAnimation)
            .combined(with: AnyTransition
                .scale(scale: scaleFrom, anchor: .center)
                .animation(predictiveCommitAnimation))

    /// predictive commit 出页 (Android initialContentExit = scaleOut(→0.92) + fadeOut,
    /// 同一 200ms 曲线)。视觉上是入页形态的反向, 同一 AnyTransition 表达式即覆盖
    /// 正反两向, 故与 `predictiveEnter` 同形。
    static let predictiveExit: AnyTransition = predictiveEnter

    /// NavDisplay predictivePopTransitionSpec 等价 (commit 态视觉形态):
    /// 入/出页都 = scale 0.92 + fade, 由 `predictiveCommitAnimation` 驱动
    /// (Android `sleepyPredictivePopTransform`; 手势实时进度 0..1 在 iOS 侧由
    /// PresentOverlay dragX 跟手承担 — 15.6 无 progress-driven transition API)。
    static let predictivePopTransform: AnyTransition =
        .asymmetric(insertion: predictiveEnter, removal: predictiveExit)

    /// predictive commit (手势放行 = 程序化 pop 微弹, 200ms 缓入, Android 曲线 1:1).
    static var predictiveCommitAnimation: Animation {
        .timingCurve(0.2, 0.0, 0.0, 1.0, duration: predictiveDuration)
    }

    /// predictive cancel 拉回 (Android NoBouncy+StiffnessMediumLow spring).
    /// iOS 15.6 无直接档位 — 用临界阻尼短响应近似「无回弹拉回」.
    static var predictiveCancelAnimation: Animation {
        .spring(response: 0.4, dampingFraction: 1.0)
    }
}

// ── 消费点说明 (PresentOverlay, SleepyApp.swift — 共享文件, 由集成者接线) ──
// 现状: overlay 出现/消失统一 .transition(.move(edge: .trailing)) 跟手侧滑,
// 与 Android predictive-back 手势语义同构 (右滑跟手=手势进度, 释放=commit/cancel)。
// Android SleepyNavHost.kt:171-172 已用 sleepyForwardTransform / sleepyPopTransform
// 驱动 NavDisplay, iOS 侧零消费 = drift。接线方法 (贴 Android 视觉: 新页中心浮起):
//   推入:  overlayContent(screen)
//              .transition(SleepyMaterialTransition.forwardTransform)
//          + .animation(SleepyMaterialTransition.forwardAnimation, value: shownScreen)
//          (forwardTransform = asymmetric(forwardEnter, forwardExit), 即 Android
//           sleepyForwardTransform 的 ContentTransform 等价; forwardEnter 的
//           opacity/scale 段已自带 110ms/220ms 分相曲线, 环境 .animation
//           只负责提供转场触发上下文)
//   退出:  pop/dismiss 用 SleepyMaterialTransition.popTransform
//          (入页 identity = Android sleepyPopEnter None; 出页 fadeOut+scaleOut,
//           两段 220ms) — 单一浮层容器内, 出浮层即 Android 出页侧, forwardEnter
//           的反向形态(popTransform 的 removal=forwardExit)与之等价
//   手势预测返回形态: SleepyMaterialTransition.predictivePopTransform
//          (入/出都走 predictiveCommitAnimation 200ms, Android 分相 1:1)
// 跟手侧滑部分保持 dragX 原生拖拽 (PresentOverlay dragX, 无 15.6 API 缺口);
// predictive cancel 弹回若需独立曲线 →
//   .animation(SleepyMaterialTransition.predictiveCancelAnimation, value: dragX)
//
// ⚠ 接线时必须同步处理"出页"通路 (否则转场会双演): 现状 animateOutThen
//   (SleepyApp.swift) 用 withAnimation(spring){ dragX = width + 60 } 把浮层滑出屏外,
//   280ms 后才置 shownScreen = nil。若只把 .transition 换成 forwardTransform 而保留
//   dragX 滑出, removal(forwardExit = 淡出 + 缩向 0.92)会与侧滑叠加 → 页面既滑走又缩放。
//   与 Android pop 出页(纯 fadeOut+scaleOut, 不滑入, sleepyPopExit)一致的两种改法:
//     A) 程序化关闭改走转场: withAnimation(forwardAnimation){ shownScreen = nil },
//        去掉 dragX→屏外那段 (dragX 仅保留手势跟手, 释放 commit/cancel 由 dragX 复位驱动);
//     B) 维持现滑出手感, 则 removal 侧应显式保持 .move(edge: .trailing) 形态,
//        不套 forwardTransform 的 forwardExit。
//   推荐 A(逐段贴 Android forwardTransform/popTransform 视感); 两案都属共享文件
//   SleepyApp.swift, 由集成者统一落地。
