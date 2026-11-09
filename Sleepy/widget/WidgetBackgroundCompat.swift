// WidgetBackgroundCompat.swift — containerBackground API 兼容封装
//
// iOS 17 起(Xcode 15+ SDK 构建时强制)WidgetKit 要求 widget 顶层视图用
// containerBackground(for: .widget) 声明背景,供 StandBy / 锁屏 / 智能堆栈等
// 场景剥离背景。仍用旧 .background() 的 widget 在 iOS 17+ 上会被系统直接渲染成
// 「Please adopt containerBackground API」错误占位。
//
// 部署目标 15.6,故 iOS 16 及以下回退旧 .background()。全部 5 个 widget 的
// EntryView 顶层背景统一走 sleepyWidgetBackground { ... }。

import SwiftUI
import WidgetKit

private struct WidgetGalleryFamilyKey: EnvironmentKey {
    static let defaultValue: WidgetFamily? = nil
}

private struct WidgetGalleryDateKey: EnvironmentKey {
    static let defaultValue: Date? = nil
}

extension EnvironmentValues {
    /// App gallery reuses the production renderer at a fixed representative family.
    /// A nil value retains the WidgetKit host's family and container background.
    var sleepyWidgetGalleryFamily: WidgetFamily? {
        get { self[WidgetGalleryFamilyKey.self] }
        set { self[WidgetGalleryFamilyKey.self] = newValue }
    }
    var sleepyWidgetGalleryDate: Date? {
        get { self[WidgetGalleryDateKey.self] }
        set { self[WidgetGalleryDateKey.self] = newValue }
    }
}

private struct SleepyWidgetBackgroundModifier<BG: View>: ViewModifier {
    @Environment(\.sleepyWidgetGalleryFamily) private var galleryFamily
    let backgroundView: BG

    @ViewBuilder
    func body(content: Content) -> some View {
        if galleryFamily != nil {
            content.background(backgroundView)
        } else if #available(iOS 17.0, *) {
            content.containerBackground(for: .widget) { backgroundView }
        } else {
            content.background(backgroundView)
        }
    }
}

extension View {
    /// widget 顶层背景: iOS 17+ 用 containerBackground, 更早回退 .background()。
    /// (本文件 App/Extension 双 target 共编, 闸门用 iOS 而非 iOSApplicationExtension)
    @ViewBuilder
    func sleepyWidgetBackground<BG: View>(@ViewBuilder backgroundView: () -> BG) -> some View {
        modifier(SleepyWidgetBackgroundModifier(backgroundView: backgroundView()))
    }
}

// contentMarginsDisabled() 本身 iOS 15.0+ 即可直接调用 — SDK 里它内嵌
// iOS 17 版本闸门(iOS 16 及以下返回 self), 无需再包一层。

// MARK: - 系统渲染模式（模式不是颜色，不能回写 seed）
// iOS 18 已支持主屏幕着色；iOS 26 clear/tinted 使用 accented。
// vibrant 是锁屏等上下文的单色处理，不等于 Liquid Glass。

extension SleepyWidgetRenderingMode {
    @available(iOS 16.0, *)
    init(_ mode: WidgetRenderingMode) {
        switch mode {
        case .accented: self = .accented
        case .vibrant: self = .vibrant
        default: self = .fullColor
        }
    }
}

struct WidgetGlassModeContent<Content: View>: View {
    let build: (SleepyWidgetRenderingMode) -> Content
    init(@ViewBuilder build: @escaping (SleepyWidgetRenderingMode) -> Content) { self.build = build }

    @available(iOS 16.0, *)
    private struct Reader: View {
        @Environment(\.widgetRenderingMode) private var mode
        let build: (SleepyWidgetRenderingMode) -> Content
        var body: some View {
            build(SleepyWidgetRenderingMode(mode))
        }
    }

    var body: some View {
        if #available(iOS 16.0, *) {
            Reader(build: build)
        } else {
            build(.fullColor)
        }
    }
}
