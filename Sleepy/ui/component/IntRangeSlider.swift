import SwiftUI
import UIKit

/// Integer, inclusive endpoints shared by rendering, dragging and accessibility.
struct IntSliderRange: Equatable {
    enum Thumb: Equatable { case start, end }
    let start: Int
    let end: Int

    init(start: Int, end: Int, minimum: Int, maximum: Int) {
        let upper = max(minimum, maximum)
        self.start = min(upper, max(minimum, start))
        self.end = min(upper, max(self.start, end))
    }

    func movingStart(to value: Int, minimum: Int) -> Self {
        Self(start: min(end, max(minimum, value)), end: end, minimum: minimum, maximum: end)
    }

    func movingEnd(to value: Int, maximum: Int) -> Self {
        Self(start: start, end: max(start, min(maximum, value)), minimum: start, maximum: maximum)
    }

    static func ghost(current: Self, initialStart: Int?, initialEnd: Int?, minimum: Int, maximum: Int) -> Self? {
        guard let initialStart, let initialEnd else { return nil }
        let original = Self(start: initialStart, end: initialEnd, minimum: minimum, maximum: maximum)
        return original == current ? nil : original
    }

    static func thumb(at x: CGFloat, startX: CGFloat, endX: CGFloat, translation: CGFloat, rightToLeft: Bool) -> Thumb? {
        // Coincident thumbs wait for motion, so either endpoint can be expanded from any touch position.
        if startX != endX, abs(x - startX) != abs(x - endX) {
            return abs(x - startX) < abs(x - endX) ? .start : .end
        }
        let logical = rightToLeft ? -translation : translation
        guard logical != 0 else { return nil }
        return logical < 0 ? .start : .end
    }
}

/// Two independently adjustable thumbs. The original range is decoration only.
struct IntRangeSlider: View {
    @Environment(\.localWakeUpColors) private var colors
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let summary: String
    let minValue: Int
    let maxValue: Int
    let startValue: Int
    let endValue: Int
    let onValueChange: (Int, Int) -> Void
    var initialStart: Int? = nil
    var initialEnd: Int? = nil
    var startLabel = L10n.format("start_node")
    var endLabel = L10n.format("occurrence_end_node")
    var identifier = "int_range"

    private typealias Thumb = IntSliderRange.Thumb
    @State private var dragOrigin: IntSliderRange?
    @State private var draggedThumb: Thumb?

    private var upper: Int { max(minValue, maxValue) }
    private var range: IntSliderRange {
        IntSliderRange(start: startValue, end: endValue, minimum: minValue, maximum: upper)
    }
    private var ghost: IntSliderRange? {
        IntSliderRange.ghost(current: range, initialStart: initialStart, initialEnd: initialEnd,
                             minimum: minValue, maximum: upper)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(summary)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(colors.onSurface)
                .accessibilityIdentifier(identifier + "_summary")
            if upper > minValue {
                rangeSlider
            }
        }
        .opacity(isEnabled ? 1 : 0.45)
        .onChange(of: isEnabled) { enabled in if !enabled { resetDrag() } }
        .onDisappear(perform: resetDrag)
    }

    // A range is one shared track in both themes. Two stacked UISliders hide
    // the selected interval and turn the range into unrelated endpoint fields.
    private var rangeSlider: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width - 44)
            let first = position(range.start, width: width)
            let last = position(range.end, width: width)
            ZStack {
                Capsule().fill(colors.surfaceContainerHighest).frame(width: width, height: 6)
                    .position(x: 22 + width / 2, y: 22)
                segment(from: first, to: last, color: colors.primary, height: 6)
                if let ghost {
                    let oldStart = position(ghost.start, width: width)
                    let oldEnd = position(ghost.end, width: width)
                    ZStack {
                        segment(from: oldStart, to: oldEnd, color: colors.primary.opacity(0.25), height: 12)
                        marker(at: oldStart)
                        marker(at: oldEnd)
                    }
                    .frame(width: geometry.size.width, height: 44)
                    .allowsHitTesting(false).accessibilityHidden(true)
                    .transition(.opacity)
                }
                thumb(.start, at: first)
                thumb(.end, at: last)
            }
            .frame(height: 44)
            .contentShape(Rectangle())
            .overlay(IntRangeSliderTouchSurface(
                onDrag: { startX, translation in updateDrag(startX: startX, translation: translation, width: width) },
                onEnd: resetDrag,
                onTap: { applyTap(at: $0, width: width) }).allowsHitTesting(isEnabled))
            .background(SleepyControlScrollLock(locked: dragOrigin != nil))
        }
        .frame(height: 44)
        .animation(SleepyMotionPolicy(reduceMotion: reduceMotion).fastEffects, value: ghost)
    }

    private func resetDrag() {
        dragOrigin = nil
        draggedThumb = nil
    }

    private func position(_ value: Int, width: CGFloat) -> CGFloat {
        let fraction = CGFloat(value - minValue) / CGFloat(max(1, upper - minValue))
        return 22 + (layoutDirection == .rightToLeft ? 1 - fraction : fraction) * width
    }

    private func segment(from start: CGFloat, to end: CGFloat, color: Color, height: CGFloat) -> some View {
        Capsule().fill(color).frame(width: max(2, abs(end - start)), height: height)
            .position(x: (start + end) / 2, y: 22)
    }

    private func marker(at x: CGFloat) -> some View {
        Capsule().fill(colors.primary.opacity(0.45)).frame(width: 3, height: 20).position(x: x, y: 22)
    }

    private func thumb(_ thumb: Thumb, at x: CGFloat) -> some View {
        Circle().fill(colors.primary).frame(width: 22, height: 22).allowsHitTesting(false)
            .frame(width: 44, height: 44)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(thumb == .start ? startLabel : endLabel)
            .accessibilityValue(String(thumb == .start ? range.start : range.end))
            .accessibilityIdentifier(identifier + (thumb == .start ? "_start" : "_end"))
            .accessibilityAdjustableAction { direction in
                guard isEnabled else { return }
                let delta: Int
                switch direction { case .increment: delta = 1; case .decrement: delta = -1; @unknown default: return }
                let updated = thumb == .start
                    ? range.movingStart(to: range.start + delta, minimum: minValue)
                    : range.movingEnd(to: range.end + delta, maximum: upper)
                onValueChange(updated.start, updated.end)
            }
            .position(x: x, y: 22)
    }

    private func nearestThumb(at x: CGFloat, origin: IntSliderRange, translation: CGFloat, width: CGFloat) -> Thumb? {
        IntSliderRange.thumb(at: x, startX: position(origin.start, width: width), endX: position(origin.end, width: width),
                             translation: translation, rightToLeft: layoutDirection == .rightToLeft)
    }

    private func updateDrag(startX: CGFloat, translation: CGFloat, width: CGFloat) {
        guard isEnabled else { return }
        let origin = dragOrigin ?? range
        dragOrigin = origin
        let selected = draggedThumb ?? nearestThumb(at: startX, origin: origin,
                                                     translation: translation, width: width)
        guard let selected else { return }
        draggedThumb = selected
        let sign: CGFloat = layoutDirection == .rightToLeft ? -1 : 1
        let delta = Int((sign * translation / width * CGFloat(upper - minValue)).rounded())
        let updated = selected == .start
            ? origin.movingStart(to: origin.start + delta, minimum: minValue)
            : origin.movingEnd(to: origin.end + delta, maximum: upper)
        onValueChange(updated.start, updated.end)
    }

    private func applyTap(at x: CGFloat, width: CGFloat) {
        guard isEnabled else { return }
        let fraction = min(1, max(0, (x - 22) / width))
        let logical = layoutDirection == .rightToLeft ? 1 - fraction : fraction
        let value = minValue + Int((logical * CGFloat(upper - minValue)).rounded())
        let selected: Thumb = range.start == range.end ? (value < range.start ? .start : .end)
            : (nearestThumb(at: x, origin: range, translation: 0, width: width) ?? .end)
        let updated = selected == .start ? range.movingStart(to: value, minimum: minValue)
            : range.movingEnd(to: value, maximum: upper)
        onValueChange(updated.start, updated.end)
    }
}


/// Reject vertical pans before recognition so the enclosing scroll view owns
/// them. A zero-distance SwiftUI drag can otherwise win before direction is known.
private struct IntRangeSliderTouchSurface: UIViewRepresentable {
    let onDrag: (CGFloat, CGFloat) -> Void
    let onEnd: () -> Void
    let onTap: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isAccessibilityElement = false
        let pan = IntRangeSliderPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:)))
        tap.require(toFail: pan)
        view.addGestureRecognizer(pan)
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) { context.coordinator.parent = self }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: IntRangeSliderTouchSurface
        init(_ parent: IntRangeSliderTouchSurface) { self.parent = parent }

        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? IntRangeSliderPanGestureRecognizer else { return true }
            let motion = pan.touchDownDisplacement
            return abs(motion.x) > abs(motion.y)
        }

        @objc func pan(_ recognizer: UIPanGestureRecognizer) {
            guard let pan = recognizer as? IntRangeSliderPanGestureRecognizer else { return }
            let displacement = pan.touchDownDisplacement
            let startX = pan.touchDownLocation?.x ?? pan.location(in: pan.view).x - displacement.x
            let translation = displacement.x
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-SLEEPY_UI_TEST_SEED"),
               recognizer.state == .began || recognizer.state == .ended {
                let recognized = pan.translation(in: pan.view)
                NSLog("INT_RANGE_PAN %@ recognized=(%.2f,%.2f) touchDown=(%.2f,%.2f)",
                      recognizer.state == .began ? "began" : "ended",
                      Double(recognized.x), Double(recognized.y),
                      Double(displacement.x), Double(displacement.y))
            }
            #endif
            switch recognizer.state {
            case .began:
                parent.onEnd()
                parent.onDrag(startX, translation)
            case .changed:
                parent.onDrag(startX, translation)
            case .ended:
                parent.onDrag(startX, translation)
                parent.onEnd()
            case .cancelled, .failed:
                parent.onEnd()
            default: break
            }
        }

        @objc func tap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            parent.onTap(recognizer.location(in: recognizer.view).x)
        }
    }
}

/// Keep the touch-down origin because a pan may recognize after some movement.
/// Measuring the full displacement also preserves where the finger held a thumb.
private final class IntRangeSliderPanGestureRecognizer: UIPanGestureRecognizer {
    private(set) var touchDownLocation: CGPoint?

    var touchDownDisplacement: CGPoint {
        guard let touchDownLocation else { return translation(in: view) }
        let current = location(in: view)
        return CGPoint(x: current.x - touchDownLocation.x, y: current.y - touchDownLocation.y)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if touchDownLocation == nil, let touch = touches.first {
            touchDownLocation = touch.location(in: view)
        }
        super.touchesBegan(touches, with: event)
    }

    override func reset() {
        super.reset()
        touchDownLocation = nil
    }
}
