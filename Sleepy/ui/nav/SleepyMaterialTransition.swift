import SwiftUI
import UIKit

/// v1.0.63：forward/pop/predictive 三路同属 content 家族。
/// 保留 PresentOverlay 已使用的入口；属性每次读取系统 Reduce Motion，不缓存启动时的值。
enum SleepyMaterialTransition {
    private static var motion: SleepyMotionPolicy {
        SleepyMotionPolicy(reduceMotion: UIAccessibility.isReduceMotionEnabled)
    }

    /// 旧消费者用来延迟 dismiss 回调的收尾窗口，不是新的固定 tween 时长。
    static var forwardDuration: Double { motion.reduceMotion ? motion.defaultEffectsDuration : SleepyMotionPolicy.defaultSpatialResponse }
    static var forwardFadeIn: Double { motion.defaultEffectsDuration }
    static var predictiveDuration: Double { forwardDuration }
    static var scaleFrom: Double { Double(motion.contentScale) }
    static var forwardAnimation: Animation { motion.defaultSpatial ?? motion.defaultEffects }
    static var forwardFadeInAnimation: Animation { motion.defaultEffects }
    static var forwardEnter: AnyTransition { motion.content }
    static var forwardExit: AnyTransition { motion.content }
    static var forwardTransform: AnyTransition { motion.content }
    static var popEnter: AnyTransition { motion.content }
    static var popTransform: AnyTransition { motion.content }
    static var predictiveEnter: AnyTransition { motion.content }
    static var predictiveExit: AnyTransition { motion.content }
    static var predictivePopTransform: AnyTransition { motion.content }
    static var predictiveCommitAnimation: Animation { forwardAnimation }
    static var predictiveCancelAnimation: Animation { forwardAnimation }
}
