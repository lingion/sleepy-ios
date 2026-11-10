import SwiftUI

/// Application material is independent of palette, light/dark mode and navigation shape.
enum SleepyUIStyle: String, CaseIterable {
    case classic
    case liquidGlass = "liquid_glass"

    init(preference: String) { self = Self(rawValue: preference) ?? .classic }
}

private struct SleepyUIStyleKey: EnvironmentKey {
    static let defaultValue = SleepyUIStyle.classic
}

private struct SleepyNativeButtonSurfaceKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var sleepyNativeButtonSurface: Bool {
        get { self[SleepyNativeButtonSurfaceKey.self] }
        set { self[SleepyNativeButtonSurfaceKey.self] = newValue }
    }
    var sleepyUIStyle: SleepyUIStyle {
        get { self[SleepyUIStyleKey.self] }
        set { self[SleepyUIStyleKey.self] = newValue }
    }
}

/// Only small actions and editing controls use this surface; content cards keep their hierarchy.
struct SleepyControlSurface: ViewModifier {
    @Environment(\.sleepyNativeButtonSurface) private var nativeButtonSurface
    @Environment(\.sleepyUIStyle) private var style
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.localWakeUpColors) private var colors
    var cornerRadius: CGFloat = 12
    var tint: Color? = nil
    var prominent = false

    @ViewBuilder func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius,
                                     style: style == .classic ? .circular : .continuous)
        if style == .liquidGlass && nativeButtonSurface {
            content
        } else if style == .liquidGlass && !reduceTransparency {
            #if os(iOS) && !WIDGET_EXT && !WATCH_APP
            #if compiler(>=6.2)
            if #available(iOS 26.0, *) {
                // Apple: developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)
                content.glassEffect(.regular.tint(tint).interactive(isEnabled), in: shape)
            } else {
                content.background(.ultraThinMaterial, in: shape)
                    .background(shape.fill((tint ?? colors.surfaceContainer).opacity(prominent ? 0.5 : 0.16)))
                    .overlay(shape.stroke(colors.outline.opacity(0.18), lineWidth: 0.5))
            }
            #else
            content.background(.ultraThinMaterial, in: shape)
                .background(shape.fill((tint ?? colors.surfaceContainer).opacity(prominent ? 0.5 : 0.16)))
                .overlay(shape.stroke(colors.outline.opacity(0.18), lineWidth: 0.5))
            #endif
            #else
            content.background(shape.fill(tint ?? colors.surfaceContainerHigh))
            #endif
        } else {
            content.background(shape.fill(tint ?? colors.surfaceContainerHigh))
        }
    }
}

extension View {
    func sleepyControlSurface(cornerRadius: CGFloat = 12, tint: Color? = nil,
                              prominent: Bool = false) -> some View {
        modifier(SleepyControlSurface(cornerRadius: cornerRadius, tint: tint, prominent: prominent))
    }
}

/// Adds a glass backing to a formerly unfilled small action while preserving
/// the classic control's existing fill and bounds.
private struct SleepyGlassControlSurface: ViewModifier {
    @Environment(\.sleepyUIStyle) private var style
    var cornerRadius: CGFloat
    var tint: Color?

    @ViewBuilder func body(content: Content) -> some View {
        if style == .liquidGlass {
            content.sleepyControlSurface(cornerRadius: cornerRadius, tint: tint)
        } else {
            content
        }
    }
}

extension View {
    func sleepyGlassControlSurface(cornerRadius: CGFloat = 12, tint: Color? = nil) -> some View {
        modifier(SleepyGlassControlSurface(cornerRadius: cornerRadius, tint: tint))
    }
}

/// Navigation shares one system glass surface instead of stacking a separate
/// native button surface behind every item.
struct SleepyNativeGlassGroup<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder var content: () -> Content

    @ViewBuilder var body: some View {
        #if os(iOS) && !WIDGET_EXT && !WATCH_APP
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing, content: content)
        } else {
            content()
        }
        #else
        content()
        #endif
        #else
        content()
        #endif
    }
}

private struct SleepyNativeGlassSurface: ViewModifier {
    var cornerRadius: CGFloat
    var tint: Color?
    var interactive = false

    @ViewBuilder func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        #if os(iOS) && !WIDGET_EXT && !WATCH_APP
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            content.background(.ultraThinMaterial, in: shape)
        }
        #else
        content.background(.ultraThinMaterial, in: shape)
        #endif
        #else
        content.background(.ultraThinMaterial, in: shape)
        #endif
    }
}

private struct SleepyNativeGlassSelection: ViewModifier {
    var selected: Bool
    var cornerRadius: CGFloat
    var tint: Color
    var namespace: Namespace.ID?

    @ViewBuilder func body(content: Content) -> some View {
        if selected {
            let surface = content.modifier(SleepyNativeGlassSurface(cornerRadius: cornerRadius, tint: tint,
                                                                   interactive: true))
            #if os(iOS) && !WIDGET_EXT && !WATCH_APP
            #if compiler(>=6.2)
            if #available(iOS 26.0, *), let namespace {
                surface.glassEffectID("navigation-selection", in: namespace)
            } else {
                surface
            }
            #else
            surface
            #endif
            #else
            surface
            #endif
        } else {
            content
        }
    }
}

extension View {
    func sleepyNativeGlassSurface(cornerRadius: CGFloat, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(SleepyNativeGlassSurface(cornerRadius: cornerRadius, tint: tint, interactive: interactive))
    }

    func sleepyNativeGlassSelection(_ selected: Bool, cornerRadius: CGFloat,
                                   tint: Color, namespace: Namespace.ID? = nil) -> some View {
        modifier(SleepyNativeGlassSelection(selected: selected, cornerRadius: cornerRadius,
                                           tint: tint, namespace: namespace))
    }
}
