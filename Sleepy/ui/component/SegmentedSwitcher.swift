import SwiftUI

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
                Picker(accessibilityTitle, selection: Binding(
                    get: { selected },
                    set: { value in
                        guard isEnabled else { return }
                        onSelect(value)
                    }
                )) {
                    ForEach(Array(options.enumerated()), id: \.offset) { _, pair in
                        Text(pair.1)
                            .tag(pair.0)
                            .accessibilityIdentifier("seg_\(pair.1)")
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .tint(colors.primary)
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
