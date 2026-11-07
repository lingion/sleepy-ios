#if os(iOS) && !WIDGET_EXT && !WATCH_APP
import SwiftUI
import UIKit
import WidgetKit

/// 必须放在生成主题的 .tint 外。颜色始终来自所属 UIWindow，而不是承载 SwiftUI 的 view。
struct SystemColorProbe: UIViewRepresentable {
    @Binding var snapshot: SystemColorSnapshot

    func makeUIView(context: Context) -> SystemColorProbeView {
        let view = SystemColorProbeView()
        view.onSnapshot = { snapshot = $0 }
        return view
    }

    func updateUIView(_ view: SystemColorProbeView, context: Context) {
        view.onSnapshot = { snapshot = $0 }
        view.scheduleRefresh()
    }

    static func dismantleUIView(_ view: SystemColorProbeView, coordinator: ()) {
        view.stop()
    }
}

final class SystemColorProbeView: UIView {
    var onSnapshot: ((SystemColorSnapshot) -> Void)?
    var publishShared: (SystemColorSnapshot) -> Void = { value in
        if SystemColorSeedStore.write(value) { WidgetCenter.shared.reloadAllTimelines() }
    }
    private(set) var lastSnapshot: SystemColorSnapshot?
    private var sensor: WindowTintSensor?
    private var notifications: [NSObjectProtocol] = []
    private var refreshPending = false
    private var forceSharedPublication = false
    private var stopped = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        let names: [Notification.Name] = [
            UIScene.didActivateNotification,
            UIWindow.didBecomeKeyNotification, UIWindow.didBecomeVisibleNotification
        ]
        for name in names {
            notifications.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] notification in
                guard let self, let window = self.window else { return }
                if let source = notification.object as? UIWindow, source !== window { return }
                if let source = notification.object as? UIScene, source !== window.windowScene { return }
                self.forceSharedPublication = true
                self.scheduleRefresh()
            })
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        sensor?.removeFromSuperview()
        sensor = nil
        if let window {
            // 直接挂在 UIWindow 下，只观察上游；不受 hosting view/生成 tint 的覆盖。
            let sensor = WindowTintSensor()
            sensor.changed = { [weak self] in self?.scheduleRefresh() }
            self.sensor = sensor
            window.addSubview(sensor)
        }
        // 换窗口时清除旧窗口的稳定样本；新窗口若正 dimmed，明确显示无信号回落。
        lastSnapshot = nil
        forceSharedPublication = true
        scheduleRefresh()
    }

    func scheduleRefresh() {
        guard !stopped, !refreshPending else { return }
        refreshPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.stopped else { return }
            self.refreshPending = false
            self.refresh()
        }
    }

    /// 内部入口可由线上 UIKit 测试直接驱动，不需要改变进程全局 appearance。
    func refresh() {
        guard !stopped else { return }
        guard let window else {
            deliver(.fallback(.noWindow))
            return
        }
        // 系统 modal dimming 是瞬态。保留同窗口最后的稳定值，不保存变暗后的色。
        guard let value = Self.sample(window: window) else {
            if lastSnapshot == nil { deliver(.fallback(.noWindow)) }
            return
        }
        let changed = value != lastSnapshot
        deliver(value)
        if (changed || forceSharedPublication), window.isKeyWindow,
           window.windowScene?.activationState == .foregroundActive {
            // 即使本窗口局部值没变，重新成为 active key 后也要争取共享快照所有权。
            publishShared(value)
            forceSharedPublication = false
        }
    }

    private func deliver(_ value: SystemColorSnapshot) {
        guard value != lastSnapshot else { return }
        lastSnapshot = value
        onSnapshot?(value)
    }

    static func sample(window: UIWindow) -> SystemColorSnapshot? {
        guard window.tintAdjustmentMode != .dimmed else { return nil }
        let traits = window.traitCollection
        let dark = traits.userInterfaceStyle == .dark
        let increased = traits.accessibilityContrast == .high
        let id = "\(window.windowScene?.session.persistentIdentifier ?? "window"):\(ObjectIdentifier(window))"
        guard let color = window.tintColor,
              let seed = rgb(color.resolvedColor(with: traits)) else {
            return .fallback(.invalidColor, systemDark: dark, increasedContrast: increased, windowID: id)
        }
        return SystemColorSnapshot(seed: seed, systemDark: dark, increasedContrast: increased, windowID: id)
    }

    /// 显式转换到 sRGB；拒绝 pattern/透明/不支持的色空间，不把失败当成黑色。
    static func rgb(_ color: UIColor) -> SystemSeedRGB? {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard color.getRed(&r, green: &g, blue: &b, alpha: &a),
              [r, g, b, a].allSatisfy({ $0.isFinite }), a >= 0.999,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let converted = color.cgColor.converted(to: space, intent: .relativeColorimetric, options: nil),
              let c = converted.components, c.count == 4 else { return nil }
        return SystemSeedRGB(red: Double(c[0]), green: Double(c[1]), blue: Double(c[2]), alpha: Double(c[3]))
    }

    func stop() {
        stopped = true
        sensor?.changed = nil
        sensor?.removeFromSuperview()
        sensor = nil
        notifications.forEach(NotificationCenter.default.removeObserver)
        notifications.removeAll()
        onSnapshot = nil
    }

    deinit { notifications.forEach(NotificationCenter.default.removeObserver) }
}

private final class WindowTintSensor: UIView {
    var changed: (() -> Void)?

    init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        if #available(iOS 17.0, *) {
            registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitAccessibilityContrast.self]) {
                (self: Self, _: UITraitCollection) in self.changed?()
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func tintColorDidChange() { super.tintColorDidChange(); changed?() }
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if #available(iOS 17.0, *) { return }
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) { changed?() }
    }
}
#endif
