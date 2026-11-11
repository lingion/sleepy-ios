import SwiftUI
import UIKit

/// Liquid Glass uses the system segmented control; Classic keeps the Material track.
struct SegmentedSwitcher<T: Hashable>: View {
    @Environment(\.localWakeUpColors) private var colors
    @Environment(\.sleepyUIStyle) private var style
    @Environment(\.layoutDirection) private var direction
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let options: [(T, String)]
    let selected: T
    let onSelect: (T) -> Void
    var containerColor: Color? = nil
    var height: CGFloat = 42
    var accessibilityTitle: String = ""

    private var selectedIndex: Int { options.firstIndex(where: { $0.0 == selected }) ?? 0 }

    var body: some View {
        Group {
            if style == .liquidGlass {
                NativeSegmentedSwitcher(options: options, selected: selected, onSelect: onSelect,
                                        colors: colors, direction: direction, isEnabled: isEnabled,
                                        accessibilityTitle: accessibilityTitle)
                .frame(minHeight: height)
            } else {
                materialSwitcher
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var materialSwitcher: some View {
        GeometryReader { geo in
            let count = max(options.count, 1)
            let width = max(0, geo.size.width - 8)
            let slot = width / CGFloat(count)
            let trackHeight = max(0, height - 8)
            let physicalIndex = direction == .rightToLeft ? count - 1 - selectedIndex : selectedIndex
            let center = (CGFloat(physicalIndex) + 0.5) * slot
            ZStack(alignment: .leading) {
                Color.clear
                    .frame(width: slot, height: trackHeight)
                    .sleepyControlSurface(cornerRadius: 12, tint: colors.secondaryContainer)
                    .offset(x: center - slot / 2)
                    .animation(SleepyMotionPolicy(reduceMotion: reduceMotion).thumb, value: selectedIndex)
                    .allowsHitTesting(false)
                HStack(spacing: 0) {
                    ForEach(Array(options.enumerated()), id: \.offset) { index, pair in
                        Button {
                            guard isEnabled else { return }
                            onSelect(pair.0)
                        } label: {
                            Text(pair.1)
                                .font(.system(size: 14, weight: index == selectedIndex ? .semibold : .medium))
                                .tracking(0.1)
                                .foregroundColor(index == selectedIndex ? colors.onSecondaryContainer : colors.onSurfaceVariant)
                                .lineLimit(1).minimumScaleFactor(0.75).allowsTightening(true)
                                .frame(width: slot, height: trackHeight)
                        }
                        .buttonStyle(SleepyButtonStyle())
                        .accessibilityIdentifier("seg_\(pair.1)")
                        .accessibilityLabel(pair.1)
                        .accessibilityAddTraits(index == selectedIndex ? .isSelected : [])
                    }
                }
            }
            .frame(width: width, height: trackHeight)
            .padding(4)
            .frame(width: geo.size.width, height: height)
            .background(RoundedRectangle(cornerRadius: 14).fill(containerColor ?? colors.surfaceContainer))
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.45)
        }
        .frame(height: height)
    }
}

/// UIKit owns segment layout, tracking, selection animation, and accessibility traits.
private struct NativeSegmentedSwitcher<T: Hashable>: UIViewRepresentable {
    let options: [(T, String)]
    let selected: T
    let onSelect: (T) -> Void
    let colors: WakeUpColorScheme
    let direction: LayoutDirection
    let isEnabled: Bool
    let accessibilityTitle: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> NativeThemedSegmentedControl {
        let control = NativeThemedSegmentedControl(items: options.map { $0.1 })
        control.addTarget(context.coordinator, action: #selector(Coordinator.selectionChanged(_:)),
                          for: .valueChanged)
        return control
    }

    func updateUIView(_ control: NativeThemedSegmentedControl, context: Context) {
        context.coordinator.parent = self
        if control.numberOfSegments != options.count {
            control.removeAllSegments()
            for (index, pair) in options.enumerated() {
                control.insertSegment(withTitle: pair.1, at: index, animated: false)
            }
        } else {
            for (index, pair) in options.enumerated() where control.titleForSegment(at: index) != pair.1 {
                control.setTitle(pair.1, forSegmentAt: index)
            }
        }
        control.segmentTitles = options.map { $0.1 }
        control.selectedSegmentIndex = options.firstIndex(where: { $0.0 == selected }) ?? UISegmentedControl.noSegment
        control.isEnabled = isEnabled
        control.semanticContentAttribute = direction == .rightToLeft ? .forceRightToLeft : .forceLeftToRight
        control.selectedSegmentTintColor = UIColor(colors.secondaryContainer)
        control.setTitleTextAttributes([.foregroundColor: UIColor(colors.onSecondaryContainer)], for: .selected)
        control.setTitleTextAttributes([.foregroundColor: UIColor(colors.onSurfaceVariant)], for: .normal)
        control.accessibilityLabel = accessibilityTitle.isEmpty ? nil : accessibilityTitle
        control.refreshSegmentIdentifiers()
    }

    final class Coordinator: NSObject {
        var parent: NativeSegmentedSwitcher

        init(_ parent: NativeSegmentedSwitcher) { self.parent = parent }

        @objc func selectionChanged(_ control: UISegmentedControl) {
            guard control.isEnabled, parent.options.indices.contains(control.selectedSegmentIndex) else { return }
            parent.onSelect(parent.options[control.selectedSegmentIndex].0)
        }
    }
}

/// Public accessibility elements provide stable logical identities in every UIKit version.
private final class NativeThemedSegmentedControl: UISegmentedControl {
    var segmentTitles: [String] = []
    private var segments: [NativeSegmentAccessibilityElement] = []

    override func layoutSubviews() {
        super.layoutSubviews()
        refreshSegmentIdentifiers()
    }

    override func accessibilityElementCount() -> Int { segments.count }
    override func accessibilityElement(at index: Int) -> Any? {
        guard segments.indices.contains(index) else { return nil }
        return segments[index]
    }
    override func index(ofAccessibilityElement element: Any) -> Int {
        segments.firstIndex { $0 === (element as AnyObject) } ?? NSNotFound
    }

    func refreshSegmentIdentifiers() {
        isAccessibilityElement = false
        if segments.count != segmentTitles.count {
            segments = segmentTitles.indices.map { NativeSegmentAccessibilityElement(control: self, index: $0) }
        }
        let width = bounds.width / CGFloat(max(numberOfSegments, 1))
        let rtl = effectiveUserInterfaceLayoutDirection == .rightToLeft
        for (index, segment) in segments.enumerated() {
            segment.accessibilityLabel = segmentTitles[index]
            segment.accessibilityIdentifier = "seg_\(segmentTitles[index])"
            segment.accessibilityTraits = [.button]
            if index == selectedSegmentIndex { segment.accessibilityTraits.insert(.selected) }
            if !isEnabled { segment.accessibilityTraits.insert(.notEnabled) }
            let physicalIndex = rtl ? numberOfSegments - index - 1 : index
            segment.accessibilityFrameInContainerSpace = CGRect(x: CGFloat(physicalIndex) * width,
                y: 0, width: width, height: bounds.height)
        }
        accessibilityElements = segments
    }
}

private final class NativeSegmentAccessibilityElement: UIAccessibilityElement {
    weak var control: UISegmentedControl?
    let index: Int

    init(control: UISegmentedControl, index: Int) {
        self.control = control
        self.index = index
        super.init(accessibilityContainer: control)
    }

    override func accessibilityActivate() -> Bool {
        guard let control, control.isEnabled else { return false }
        control.selectedSegmentIndex = index
        control.sendActions(for: .valueChanged)
        return true
    }
}
