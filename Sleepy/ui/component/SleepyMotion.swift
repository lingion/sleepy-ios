import SwiftUI

// SleepyMotion — 原版本 ui/component/SleepyMotion.kt → iOS 等价常量.
//
// 原版本 侧: SleepyThumbSpring = spring(dampingRatio=NoBouncy, stiffness=High)
// 官方 MotionScheme.expressive() 已是全局默认(MD3E), 但其空间类 spring 带回弹
// (MediumBouncy) — thumb 类「跟手不弹」交互是用户实测定参 (高硬度+无回弹,
// MediumLow 拖沓不跟手), 官方 motionScheme 无对应档位.
//
// iOS 等价: 线性参数 spring(response:) 的无回弹 = dampingFraction 1.0;
// "High stiffness + 不拖" = 短 response 0.18. 三处使用点共用同一常量 —
// 注释里的「同款」即指此常量; 改参数三处同步生效.
//
// 使用处 (原版本: SegmentedSwitcher thumb / PillNavigationBar 贴底+Dock thumb):
//   • SegmentedSwitcher.swift   (selectedIndex 跟随)
//   • PillNavigationBar.swift   ×2 (thumbCenterX 贴底 + Dock 药丸)
let sleepyThumbSpring = Animation.spring(response: 0.18, dampingFraction: 1.0)

/// Android v1.0.63 SleepyMotion 家族的原生映射；不是 Compose 弹簧时长的逐毫秒复制。
/// 空间允许轻回弹，透明度/颜色使用无回弹 effects；减少动态效果时不缩放、不位移。
struct SleepyMotionPolicy: Equatable {
    let reduceMotion: Bool
    static let fastSpatialResponse: Double = 0.3
    static let defaultSpatialResponse: Double = 0.42
    static let fastSpatialDamping: Double = 0.7
    var fastEffectsDuration: Double { reduceMotion ? 0.1 : 0.15 }
    var defaultEffectsDuration: Double { reduceMotion ? 0.1 : 0.22 }

    var popupScale: CGFloat { reduceMotion ? 1 : 0.8 }
    var contentScale: CGFloat { reduceMotion ? 1 : 0.92 }
    func pressScale(pressed: Bool, enabled: Bool = true, dragSource: Bool = false) -> CGFloat {
        pressed && enabled && !dragSource && !reduceMotion ? 0.98 : 1
    }

    var fastSpatial: Animation? { reduceMotion ? nil : .spring(response: Self.fastSpatialResponse, dampingFraction: Self.fastSpatialDamping) }
    var defaultSpatial: Animation? { reduceMotion ? nil : .spring(response: Self.defaultSpatialResponse, dampingFraction: 0.8) }
    var fastEffects: Animation { .easeOut(duration: fastEffectsDuration) }
    var defaultEffects: Animation { .easeInOut(duration: defaultEffectsDuration) }
    var thumb: Animation? { reduceMotion ? nil : sleepyThumbSpring }

    var popup: AnyTransition {
        .scale(scale: popupScale).animation(fastSpatial)
            .combined(with: .opacity.animation(fastEffects))
    }
    var content: AnyTransition {
        .scale(scale: contentScale).animation(defaultSpatial)
            .combined(with: .opacity.animation(defaultEffects))
    }
    var expand: AnyTransition {
        if reduceMotion { return .opacity.animation(fastEffects) }
        let space = AnyTransition.modifier(
            active: SleepyVerticalReveal(fraction: 0), identity: SleepyVerticalReveal(fraction: 1))
            .animation(fastSpatial)
        return .asymmetric(
            insertion: space.combined(with: .opacity.animation(defaultEffects)),
            removal: space.combined(with: .opacity.animation(fastEffects)))
    }
}

/// 改变实际占用高度而非 move(top)：相邻行随展开让出空间。
private struct SleepyVerticalReveal: AnimatableModifier {
    var fraction: CGFloat
    var animatableData: CGFloat {
        get { fraction }
        set { fraction = newValue }
    }
    func body(content: Content) -> some View {
        content.fixedSize(horizontal: false, vertical: true)
            .modifier(SleepyRevealHeight(fraction: fraction))
    }
}

private struct SleepyRevealHeight: ViewModifier {
    let fraction: CGFloat
    @State private var height: CGFloat = 0
    func body(content: Content) -> some View {
        content
            .background(GeometryReader { geometry in
                Color.clear.preference(key: SleepyRevealHeightKey.self, value: geometry.size.height)
            })
            .frame(height: height > 0 ? height * max(0, min(1, fraction)) : nil, alignment: .top)
            .clipped()
            .onPreferenceChange(SleepyRevealHeightKey.self) { height = $0 }
    }
}

private struct SleepyRevealHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// 消费方须保留此宿主，通过 visible 切换子视图，离场期间 SwiftUI 才能保留快照。
struct SleepyPopup<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let visible: Bool
    @ViewBuilder var content: () -> Content

    var body: some View {
        let motion = SleepyMotionPolicy(reduceMotion: reduceMotion)
        ZStack {
            if visible { content().transition(motion.popup) }
        }
        .animation(motion.fastEffects, value: visible)
        .allowsHitTesting(visible)
        .accessibilityHidden(!visible)
    }
}

/// 挂到普通 Button；长按拖动起点显式 opt out，不注册额外手势识别器。
struct SleepyMotionButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    var dragSource = false

    func makeBody(configuration: Configuration) -> some View {
        let motion = SleepyMotionPolicy(reduceMotion: reduceMotion)
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(motion.pressScale(pressed: configuration.isPressed, enabled: isEnabled, dragSource: dragSource))
            .opacity(configuration.isPressed && isEnabled && !dragSource ? 0.7 : 1)
            .animation(motion.fastEffects, value: configuration.isPressed)
    }
}
