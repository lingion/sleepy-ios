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
        view.ghost.value = Float(baseline ?? value)
        view.ghost.thumbTintColor = UIColor(Color.accentColor)
        view.ghost.isHidden = baseline.map { abs(value - $0) <= (range.upperBound - range.lowerBound) * 0.025 } ?? true
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

    override init(frame: CGRect) {
        super.init(frame: frame)
        ghost.minimumTrackTintColor = .clear
        ghost.maximumTrackTintColor = .clear
        ghost.alpha = 0.35
        ghost.isUserInteractionEnabled = false
        ghost.isAccessibilityElement = false
        ghost.accessibilityElementsHidden = true
        addSubview(ghost)
        addSubview(slider)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        slider.frame = bounds
        ghost.frame = bounds
    }
}
