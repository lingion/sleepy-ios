import SwiftUI

/// Resting geometry from Material3 1.5.0-beta02 RadioButton/Checkbox.
/// The enclosing control owns interaction and accessibility; this is only its indicator.
struct MaterialSelectionIndicator: View {
    enum Kind { case radio, checkbox }

    @Environment(\.localWakeUpColors) private var colors
    @Environment(\.isEnabled) private var isEnabled
    let kind: Kind
    let selected: Bool

    private var indicatorColor: Color {
        isEnabled ? (selected ? colors.primary : colors.onSurfaceVariant)
            : colors.onSurface.opacity(0.38)
    }

    var body: some View {
        Canvas { context, _ in
            switch kind {
            case .radio:
                // 20-unit outer diameter, 2-unit stroke and 10-unit selected dot.
                context.stroke(Path(ellipseIn: CGRect(x: 3, y: 3, width: 18, height: 18)),
                               with: .color(indicatorColor), lineWidth: 2)
                if selected {
                    context.fill(Path(ellipseIn: CGRect(x: 7, y: 7, width: 10, height: 10)),
                                 with: .color(indicatorColor))
                }
            case .checkbox:
                // Android's styling-fix flag is false in 1.0.64: 20-unit canvas + 2 padding.
                if selected {
                    context.fill(Path(roundedRect: CGRect(x: 2, y: 2, width: 20, height: 20),
                                      cornerRadius: 2, style: .circular), with: .color(indicatorColor))
                    var check = Path()
                    check.move(to: CGPoint(x: 6, y: 12))
                    check.addLine(to: CGPoint(x: 10, y: 16))
                    check.addLine(to: CGPoint(x: 18, y: 8))
                    context.stroke(check, with: .color(isEnabled ? colors.onPrimary : colors.surface),
                                   style: StrokeStyle(lineWidth: 2, lineCap: .square))
                } else {
                    context.stroke(Path(roundedRect: CGRect(x: 3, y: 3, width: 18, height: 18),
                                        cornerRadius: 1, style: .circular), with: .color(indicatorColor), lineWidth: 2)
                }
            }
        }
        .frame(width: 24, height: 24)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
