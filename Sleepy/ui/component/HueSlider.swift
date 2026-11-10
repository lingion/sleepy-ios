import SwiftUI

struct HueEditingSession {
    let baseline: Float
    var current: Float
    init(initialHue: Float) {
        let value = initialHue.isFinite ? min(max(initialHue, 0), 360) : 0
        baseline = value; current = value
    }
}

/// Physical slider coordinates are independent of SwiftUI's semantic leading edge.
/// Drawing, pointer input and native optical thumbs share the same value mapping.
struct SliderTrackGeometry {
    let range: ClosedRange<Double>
    let rightToLeft: Bool
    let lowerX: CGFloat
    let upperX: CGFloat
    var width: CGFloat { upperX - lowerX }
    var centerX: CGFloat { (lowerX + upperX) / 2 }

    init(range: ClosedRange<Double>, containerWidth: CGFloat, inset: CGFloat = 0,
         rightToLeft: Bool) {
        self.range = range
        self.rightToLeft = rightToLeft
        let width = containerWidth.isFinite ? max(containerWidth, 0) : 0
        let padding = inset.isFinite ? min(max(inset, 0), width / 2) : 0
        lowerX = padding
        upperX = width - padding
    }

    func logicalFraction(_ value: Double) -> CGFloat {
        guard value.isFinite, range.upperBound > range.lowerBound else { return 0 }
        return CGFloat(min(1, max(0, (value - range.lowerBound) /
                                  (range.upperBound - range.lowerBound))))
    }

    func position(_ value: Double) -> CGFloat {
        let logical = logicalFraction(value)
        return lowerX + (rightToLeft ? 1 - logical : logical) * width
    }

    func value(at x: CGFloat) -> Double {
        guard x.isFinite, width > 0 else { return range.lowerBound }
        let physical = min(1, max(0, (x - lowerX) / width))
        let logical = rightToLeft ? 1 - physical : physical
        return range.lowerBound + Double(logical) * (range.upperBound - range.lowerBound)
    }

    func activeRange(to value: Double) -> ClosedRange<CGFloat> {
        let start = position(range.lowerBound)
        let end = position(value)
        return min(start, end)...max(start, end)
    }
}

struct HueSlider: View {
    @Environment(\.sleepyUIStyle) private var style
    @Environment(\.layoutDirection) private var direction
    @Environment(\.isEnabled) private var isEnabled
    let hue: Float
    let onHueChange: (Float) -> Void
    var onHueCommit: (Float) -> Void = { _ in }
    var initialHue: Float? = nil
    @GestureState private var held = false

    private var clamped: Float { hue.isFinite ? min(max(hue, 0), 360) : 0 }
    private func commit(_ value: Float) { onHueChange(value); onHueCommit(value) }

    var body: some View {
        if style == .liquidGlass {
            NativeBaselineSlider(value: Double(clamped), range: 0...360,
                baseline: initialHue.map(Double.init), label: L10n.format("course_color_seed_label"),
                valueText: "\(Int(clamped))°", onValueChange: { onHueChange(Float($0)) },
                onFinished: {}, baselineTolerance: 0.5, onValueCommit: { onHueCommit(Float($0)) })
        } else {
            classicSlider
        }
    }

    private var classicSlider: some View {
        GeometryReader { geo in
            let track = SliderTrackGeometry(range: 0...360, containerWidth: geo.size.width,
                                            rightToLeft: direction == .rightToLeft)
            let rainbow = LinearGradient(stops: stride(from: 0, through: 360, by: 60).map {
                .init(color: Color(hue: Double($0) / 360, saturation: 1, brightness: 1), location: Double($0) / 360)
            }, startPoint: .leading, endPoint: .trailing)
            ZStack {
                Capsule().fill(rainbow)
                    .frame(width: track.width, height: max(4, geo.size.height))
                    .environment(\.layoutDirection, .leftToRight)
                    .scaleEffect(x: direction == .rightToLeft ? -1 : 1)
                    .position(x: track.centerX, y: geo.size.height / 2)
                if let baseline = initialHue, abs(baseline - clamped) > 0.5 {
                    Capsule().fill(Color.white).frame(width: 2, height: 20)
                        .overlay(Capsule().stroke(Color.black.opacity(0.4), lineWidth: 0.5))
                        .position(x: track.position(Double(baseline)), y: geo.size.height / 2)
                }
                Circle().fill(Color(hue: Double(clamped) / 360, saturation: 0.8, brightness: 0.95))
                    .frame(width: 22, height: 22).allowsHitTesting(false)
                    .position(x: track.position(Double(clamped)), y: geo.size.height / 2)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .updating($held) { _, active, _ in active = isEnabled }
                .onChanged { if isEnabled { onHueChange(Float(track.value(at: $0.location.x))) } }
                .onEnded { if isEnabled { commit(Float(track.value(at: $0.location.x))) } })
            .background(SleepyControlScrollLock(locked: held))
        }
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.format("course_color_seed_label"))
        .accessibilityValue("\(Int(clamped))°")
        .accessibilityAdjustableAction { direction in
            guard isEnabled else { return }
            switch direction {
            case .increment: commit(min(360, clamped + 1))
            case .decrement: commit(max(0, clamped - 1))
            @unknown default: break
            }
        }
    }
}
