import SwiftUI
import UIKit

/// Independent icon actions are discs; text actions keep fully rounded ends.
enum SleepyButtonShape {
    case circle
    case capsule

    var nativeBorder: ButtonBorderShape {
        if #available(iOS 17.0, *), self == .circle { return .circle }
        return .capsule
    }
}

/// Small glass actions delegate behavior and rendering to the platform button style.
struct SleepyActionButtonStyle: PrimitiveButtonStyle {
    @Environment(\.sleepyUIStyle) private var style
    @Environment(\.isEnabled) private var isEnabled
    var prominent = false
    var cornerRadius: CGFloat = 12
    var compact = false
    var shape: SleepyButtonShape = .capsule

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        if style == .liquidGlass {
            #if compiler(>=6.2)
            if #available(iOS 26.0, *) {
                if prominent {
                    Button(role: configuration.role, action: configuration.trigger) { nativeLabel(configuration) }
                        .buttonStyle(GlassProminentButtonStyle())
                        .buttonBorderShape(shape.nativeBorder)
                        .modifier(SleepyNativeButtonSizing(compact: compact || shape == .circle))
                        .environment(\.sleepyNativeButtonSurface, true)
                } else {
                    Button(role: configuration.role, action: configuration.trigger) { nativeLabel(configuration) }
                        .buttonStyle(GlassButtonStyle())
                        .buttonBorderShape(shape.nativeBorder)
                        .modifier(SleepyNativeButtonSizing(compact: compact || shape == .circle))
                        .environment(\.sleepyNativeButtonSurface, true)
                }
            } else {
                nativeFallback(configuration: configuration)
            }
            #else
            nativeFallback(configuration: configuration)
            #endif
        } else {
            Button(role: configuration.role, action: configuration.trigger) { configuration.label }
                .buttonStyle(ClassicSleepyActionButtonStyle(prominent: prominent, cornerRadius: cornerRadius))
        }
    }

    @ViewBuilder
    private func nativeLabel(_ configuration: Configuration) -> some View {
        if shape == .circle {
            // Small system glass adds 5pt vertically. A 34pt label produces a
            // 44pt disc and a real accessible/tappable button inside the 48pt slot.
            configuration.label.frame(minWidth: 34, minHeight: 34)
        } else {
            configuration.label
        }
    }

    @ViewBuilder
    private func nativeFallback(configuration: Configuration) -> some View {
        if #unavailable(iOS 17.0), shape == .circle {
            // Circular button borders are unavailable before iOS 17. Draw an
            // explicit disc so system insets cannot stretch this shape.
            Button(role: configuration.role, action: configuration.trigger) {
                configuration.label
                    .frame(width: 44, height: 44)
                    .background {
                        if prominent {
                            Circle().fill(.tint)
                        } else {
                            Circle().fill(.ultraThinMaterial)
                        }
                    }
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .opacity(isEnabled ? 1 : 0.45)
            .environment(\.sleepyNativeButtonSurface, true)
        } else if prominent {
            Button(role: configuration.role, action: configuration.trigger) { nativeLabel(configuration) }
                .buttonStyle(BorderedProminentButtonStyle())
                .buttonBorderShape(shape.nativeBorder)
                .modifier(SleepyNativeButtonSizing(compact: compact || shape == .circle))
                .environment(\.sleepyNativeButtonSurface, true)
        } else {
            Button(role: configuration.role, action: configuration.trigger) { nativeLabel(configuration) }
                .buttonStyle(BorderedButtonStyle())
                .buttonBorderShape(shape.nativeBorder)
                .modifier(SleepyNativeButtonSizing(compact: compact || shape == .circle))
                .environment(\.sleepyNativeButtonSurface, true)
        }
    }
}

/// Preserve existing Material labels while letting native glass buttons own their surface.
struct SleepyPlatformButtonStyle: PrimitiveButtonStyle {
    @Environment(\.sleepyUIStyle) private var style
    var prominent = false
    var cornerRadius: CGFloat = 20
    var compact = false
    var shape: SleepyButtonShape = .capsule

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        if style == .liquidGlass {
            Button(role: configuration.role, action: configuration.trigger) { configuration.label }
                .buttonStyle(SleepyActionButtonStyle(prominent: prominent, cornerRadius: cornerRadius, compact: compact, shape: shape))
        } else {
            Button(role: configuration.role, action: configuration.trigger) { configuration.label }
                .buttonStyle(SleepyButtonStyle())
        }
    }
}

/// Toolbar slots keep their existing bounds while the platform draws the button.
private struct SleepyNativeButtonSizing: ViewModifier {
    let compact: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if compact {
            #if compiler(>=6.2)
            if #available(iOS 26.0, *) {
                content.buttonSizing(.fitted).controlSize(.small)
            } else {
                content.controlSize(.small)
            }
            #else
            content.controlSize(.small)
            #endif
        } else {
            content
        }
    }
}

private struct ClassicSleepyActionButtonStyle: ButtonStyle {
    @Environment(\.localWakeUpColors) private var colors
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let prominent: Bool
    let cornerRadius: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .sleepyControlSurface(cornerRadius: cornerRadius,
                                  tint: prominent ? colors.primary : nil, prominent: prominent)
            .scaleEffect(configuration.isPressed && isEnabled && !reduceMotion ? 0.96 : 1)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(SleepyMotionPolicy(reduceMotion: reduceMotion).fastSpatial, value: configuration.isPressed)
    }
}

/// Glass uses the platform switch; Classic follows Material3 1.5.0-beta02 SwitchTokens.
struct SleepyToggleStyle: ToggleStyle {
    @Environment(\.sleepyUIStyle) private var style
    var showsLabel = false
    var disabledUncheckedBorderOpacity: Double = 0.38
    var uncheckedTrackColor: Color? = nil

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        if style == .liquidGlass {
            Toggle(isOn: configuration.$isOn) { configuration.label }.toggleStyle(.switch)
        } else {
            Button { configuration.isOn.toggle() } label: { configuration.label }
                .buttonStyle(ClassicSleepyToggleButtonStyle(isOn: configuration.isOn,
                    showsLabel: showsLabel, disabledUncheckedBorderOpacity: disabledUncheckedBorderOpacity,
                    uncheckedTrackColor: uncheckedTrackColor))
                .accessibilityRepresentation {
                    // An explicit system style avoids inheriting SleepyToggleStyle recursively.
                    Toggle(isOn: configuration.$isOn) { configuration.label }.toggleStyle(.switch)
                }
        }
    }
}

private struct ClassicSleepyToggleButtonStyle: ButtonStyle {
    @Environment(\.localWakeUpColors) private var colors
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    let isOn: Bool
    let showsLabel: Bool
    let disabledUncheckedBorderOpacity: Double
    let uncheckedTrackColor: Color?

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            if showsLabel {
                configuration.label
                Spacer(minLength: 8)
            }
            indicator(pressed: configuration.isPressed && isEnabled)
                .frame(width: 52, height: 48)
        }
        .contentShape(Rectangle())
    }

    private func indicator(pressed: Bool) -> some View {
        let diameter: CGFloat = pressed ? 28 : isOn ? 24 : 16
        let logicalCenter: CGFloat = isOn ? 36 : 16
        // Switch.kt uses SnapSpec on press and expressive FastSpatial on release/state changes.
        let animation: Animation? = reduceMotion || pressed ? nil :
            .interpolatingSpring(mass: 1, stiffness: 800, damping: 2 * 0.6 * sqrt(800), initialVelocity: 0)
        return ZStack {
            Capsule().fill(trackColor)
                .overlay(Capsule().strokeBorder(borderColor, lineWidth: 2))
            Circle().fill(thumbColor)
                .animation(nil, value: isOn)
                .animation(nil, value: isEnabled)
                .frame(width: diameter, height: diameter)
                // SwiftUI position mirrors its horizontal coordinate in RTL, like placeRelative.
                .position(x: logicalCenter, y: 16)
                .animation(animation, value: isOn)
                .animation(animation, value: pressed)
        }
        .frame(width: 52, height: 32)
    }

    private var trackColor: Color {
        if isEnabled { return isOn ? colors.primary : uncheckedTrackColor ?? colors.surfaceContainerHighest }
        return compositeOnSurface(isOn ? colors.onSurface : colors.surfaceContainerHighest, opacity: 0.12)
    }

    private var borderColor: Color {
        if isOn { return .clear }
        return isEnabled ? colors.outline : compositeOnSurface(colors.onSurface, opacity: disabledUncheckedBorderOpacity)
    }

    private var thumbColor: Color {
        if isEnabled { return isOn ? colors.onPrimary : colors.outline }
        return isOn ? colors.surface : compositeOnSurface(colors.onSurface, opacity: 0.38)
    }

    /// Material's disabled colors are made opaque over surface before drawing the component.
    private func compositeOnSurface(_ foreground: Color, opacity: Double) -> Color {
        let traits = UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        var sr: CGFloat = 0, sg: CGFloat = 0, sb: CGFloat = 0, sa: CGFloat = 0
        UIColor(foreground).resolvedColor(with: traits).getRed(&r, green: &g, blue: &b, alpha: &a)
        UIColor(colors.surface).resolvedColor(with: traits).getRed(&sr, green: &sg, blue: &sb, alpha: &sa)
        let alpha = CGFloat(opacity)
        return Color(red: Double(r * alpha + sr * (1 - alpha)),
                     green: Double(g * alpha + sg * (1 - alpha)),
                     blue: Double(b * alpha + sb * (1 - alpha)))
    }
}

/// Freeze only the owning scroll views during a horizontal control gesture, then restore their state.
struct SleepyControlScrollLock: UIViewRepresentable {
    let locked: Bool
    func makeUIView(context: Context) -> LockView { LockView() }
    func updateUIView(_ view: LockView, context: Context) { view.setLocked(locked) }
    static func dismantleUIView(_ view: LockView, coordinator: ()) { view.setLocked(false) }

    final class LockView: UIView {
        private var hosts: [(UIScrollView, Bool)] = []
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
        func setLocked(_ locked: Bool) {
            if locked && hosts.isEmpty {
                var ancestor = superview
                while let view = ancestor {
                    if let scroll = view as? UIScrollView {
                        hosts.append((scroll, scroll.isScrollEnabled))
                        scroll.isScrollEnabled = false
                    }
                    ancestor = view.superview
                }
            } else if !locked {
                for (scroll, enabled) in hosts { scroll.isScrollEnabled = enabled }
                hosts.removeAll()
            }
        }
        override func didMoveToWindow() { super.didMoveToWindow(); if window == nil { setLocked(false) } }
    }
}

