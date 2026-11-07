import SwiftUI
import UIKit

/// 两个同配置的原生滑杆共用几何：底层仅显示半透明基线拇指，方向和轨道随系统变化。
struct NativeBaselineSlider: UIViewRepresentable {
    let value: Double
    let range: ClosedRange<Double>
    let baseline: Double?
    let label: String
    let valueText: String
    let onValueChange: (Double) -> Void
    let onFinished: () -> Void
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> BaselineSliderView {
        let view = BaselineSliderView()
        view.slider.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        view.slider.addTarget(context.coordinator, action: #selector(Coordinator.finished),
                              for: [.touchUpInside, .touchUpOutside, .touchCancel])
        return view
    }

    func updateUIView(_ view: BaselineSliderView, context: Context) {
        context.coordinator.parent = self
        let direction: UISemanticContentAttribute = layoutDirection == .rightToLeft
            ? .forceRightToLeft : .forceLeftToRight
        for slider in [view.slider, view.ghost] {
            slider.minimumValue = Float(range.lowerBound)
            slider.maximumValue = Float(range.upperBound)
            slider.semanticContentAttribute = direction
            slider.tintColor = UIColor(Color.accentColor)
        }
        view.slider.value = Float(value)
        view.slider.accessibilityLabel = label
        view.slider.accessibilityValue = valueText
        view.ghost.thumbTintColor = UIColor(Color.accentColor)
        let visible = baseline.map { abs(value - $0) > (range.upperBound - range.lowerBound) * 0.025 } ?? false
        view.updateGhost(baseline: baseline.map { Float($0) }, visible: visible, reduceMotion: reduceMotion)
    }

    final class Coordinator: NSObject {
        var parent: NativeBaselineSlider
        init(_ parent: NativeBaselineSlider) { self.parent = parent }
        @objc func changed(_ slider: UISlider) {
            // 去掉 Float 桥接噪声，避免 0.70 被父层 5% 量化误截成 0.65。
            let value = (Double(slider.value) * 1_000_000).rounded() / 1_000_000
            parent.onValueChange(min(parent.range.upperBound, max(parent.range.lowerBound, value)))
            // VoiceOver/键盘调整没有 touchUp，同样需要落盘。
            if !slider.isTracking { parent.onFinished() }
        }
        @objc func finished() { parent.onFinished() }
    }
}

final class BaselineSliderView: UIView {
    let slider = UISlider()
    let ghost = UISlider()
    private(set) var ghostVisible = false
    private var ghostGeneration = 0
    private var lastReduceMotion = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        ghost.minimumTrackTintColor = .clear
        ghost.maximumTrackTintColor = .clear
        ghost.alpha = 0
        ghost.isHidden = true
        ghost.isUserInteractionEnabled = false
        ghost.isAccessibilityElement = false
        ghost.accessibilityElementsHidden = true
        addSubview(ghost)
        addSubview(slider)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// nil 基线退场时保留最后的 value；新显隐使旧 completion 失效，避免快速恢复后被隐藏。
    func updateGhost(baseline: Float?, visible: Bool, reduceMotion: Bool) {
        if visible, let baseline { ghost.value = baseline }
        guard visible != ghostVisible || reduceMotion != lastReduceMotion else { return }
        ghostGeneration += 1
        let generation = ghostGeneration
        ghostVisible = visible
        lastReduceMotion = reduceMotion
        let policy = SleepyMotionPolicy(reduceMotion: reduceMotion)
        if window == nil || reduceMotion {
            ghost.layer.removeAllAnimations()
            ghost.transform = .identity
            ghost.alpha = visible ? 0.35 : 0
            ghost.isHidden = !visible
            return
        }
        layoutIfNeeded()
        if ghost.isHidden {
            ghost.transform = ghostTransform(scale: policy.popupScale)
            ghost.alpha = 0
        }
        ghost.isHidden = false
        UIView.animate(withDuration: policy.fastEffectsDuration, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.ghost.alpha = visible ? 0.35 : 0
        }
        UIView.animate(withDuration: SleepyMotionPolicy.fastSpatialResponse, delay: 0,
                       usingSpringWithDamping: CGFloat(SleepyMotionPolicy.fastSpatialDamping), initialSpringVelocity: 0,
                       options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.ghost.transform = visible ? .identity : self.ghostTransform(scale: policy.popupScale)
        } completion: { [weak self] _ in
            guard let self, self.ghostGeneration == generation else { return }
            self.ghost.isHidden = !visible
        }
    }

    private func ghostTransform(scale: CGFloat) -> CGAffineTransform {
        let track = ghost.trackRect(forBounds: ghost.bounds)
        let thumb = ghost.thumbRect(forBounds: ghost.bounds, trackRect: track, value: ghost.value)
        // 以基线拇指中心缩放，不能以整条 slider 中心缩放导致基线横移。
        return CGAffineTransform(a: scale, b: 0, c: 0, d: scale,
            tx: (thumb.midX - ghost.bounds.midX) * (1 - scale),
            ty: (thumb.midY - ghost.bounds.midY) * (1 - scale))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        slider.frame = bounds
        ghost.bounds = CGRect(origin: .zero, size: bounds.size)
        ghost.center = CGPoint(x: bounds.midX, y: bounds.midY)
    }
}
