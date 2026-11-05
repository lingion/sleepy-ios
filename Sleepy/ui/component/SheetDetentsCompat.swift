// SheetDetentsCompat.swift — presentationDetents 的 iOS 15 兼容层
// 6s Plus 真机 = iOS 15.8.8;presentationDetents 是 iOS16+ API,iOS 15 上
// 硬错误(条件分支内)/静默无效(sheet 闭包上)。此 modifier:
//   iOS 16+ → 原样转发 presentationDetents(行为与原代码 1:1)
//   iOS 15  → 回退 .frame 固定高度(iOS15 无 partial detent,全高 sheet
//             内固定内容高度是官方前推荐做法,视觉接近原意图)
// Detent 枚举按原代码用到的三档建模(height/medium/large;多档取首档)

import SwiftUI

enum SheetDetent: Equatable {
    case height(CGFloat)
    case medium
    case large
}

struct SheetDetentsModifier: ViewModifier {
    let detents: [SheetDetent]

    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.presentationDetents(Self.resolve(detents))
        } else {
            // iOS 15 真·半屏:UISheetPresentationController 是 iOS 15.0 API
            // (SwiftUI presentationDetents 才是 16+)。旧回退 .frame 固定高会让
            // 全高 sheet 里飘一个内容框(全屏滑上+底部大片空白)。medium/large
            // 直接设 detents;height 档 iOS 15 无自定义 detent,保留 frame 方案。
            let h = Self.preferredHeight(detents)
            if let h = h {
                content.frame(height: h)
                    .background(IOS15DetentIntrospector(detents: [.large]))
            } else {
                content.background(IOS15DetentIntrospector(detents: detents))
            }
        }
    }

    @available(iOS 16.0, *)
    private static func resolve(_ detents: [SheetDetent]) -> Set<PresentationDetent> {
        var out = Set<PresentationDetent>()
        for d in detents {
            switch d {
            case .height(let h): out.insert(.height(h))
            case .medium: out.insert(.medium)
            case .large: out.insert(.large)
            }
        }
        return out
    }

    private static func preferredHeight(_ detents: [SheetDetent]) -> CGFloat? {
        for d in detents {
            switch d {
            case .height(let h): return h
            case .medium: return 400 // iOS15 无 medium 语义,取近似固定高
            case .large: return nil
            }
        }
        return nil
    }
}

extension View {
    /// 与 .presentationDetents([...]) 等价的 iOS15 兼容调用
    func sheetDetents(_ detents: [SheetDetent]) -> some View {
        modifier(SheetDetentsModifier(detents: detents))
    }
}

// iOS 15:后台 1×1 透明 VC introspect — 沿 parent 链上溯到带 sheetPresentationController
// 的宿主(即被 present 的 sheet 根 VC),把 detents 设成真半屏。parent 走完兜底
// presentingViewController 以防宿主层级被系统私有 VC 隔断。
private struct IOS15DetentIntrospector: UIViewControllerRepresentable {
    let detents: [SheetDetent]

    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        vc.view.backgroundColor = .clear
        vc.view.isUserInteractionEnabled = false
        return vc
    }

    func updateUIViewController(_ vc: UIViewController, context: Context) {
        let wanted = Self.resolve(detents)
        let grabber = detents.contains(.medium)
        // 首次 update 可能早于 sheet present(presentationController 尚未挂上),
        // 有界重试兜底时序(每 100ms,最多 ~2s)。
        var attempts = 0
        func apply() {
            var node: UIViewController? = vc
            while let cur = node {
                if let sheet = cur.sheetPresentationController {
                    sheet.detents = wanted
                    sheet.prefersGrabberVisible = grabber
                    return
                }
                node = cur.parent ?? cur.presentingViewController
            }
            attempts += 1
            if attempts < 20 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: apply) }
        }
        DispatchQueue.main.async(execute: apply)
    }

    // iOS 15 只有 medium/large 两档(自定义 detent 是 16+)
    private static func resolve(_ detents: [SheetDetent])
        -> [UISheetPresentationController.Detent] {
        detents.contains(.large) ? [.large()] : [.medium()]
    }
}

// presentationDragIndicator(.hidden) 的 iOS15 兼容(iOS15 无此 API 也无把手,无需动作)
struct HideDragIndicatorIfAvailable: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.presentationDragIndicator(.hidden)
        } else {
            content
        }
    }
}

// 多行文本输入兼容层:TextField(axis: .vertical) + lineLimit(range) 是 iOS16+ API。
// iOS 15 → TextEditor(原生多行);iOS 16+ → 原生 axis API。
// 视觉差异点:TextEditor 自带内边距,用 padding(-4) 补偿对齐;无 placeholder,
// 用 ZStack overlay 实现与 TextField 一致的占位行为。
struct MultilineFieldCompat: View {
    let placeholder: String
    @Binding var text: String
    let minLines: Int
    let maxLines: Int

    var body: some View {
        if #available(iOS 16.0, *) {
            TextField(placeholder, text: $text, axis: .vertical)
                .lineLimit(minLines...maxLines)
        } else {
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .foregroundColor(Color(.placeholderText))
                        .padding(.top, 8)
                        .padding(.leading, 4)
                }
                TextEditor(text: $text)
                    .padding(-4) // 抵消 TextEditor 内建 inset,对齐 TextField 基线
            }
        }
    }
}

// MARK: - Presentation Drag Indicator & Dismiss Attempt Interceptor (iOS 15 / 16+)

#if canImport(UIKit)
import UIKit

/// UIViewControllerRepresentable 宿主内省器:
/// 1. 沿 VC 树向上查找 UISheetPresentationController 并配置 prefersGrabberVisible (iOS 15/16 兜底)
/// 2. 挂接 UIAdaptivePresentationControllerDelegate 拦截 presentationControllerDidAttemptToDismiss
/// 3. 保留并转发宿主原生已有 delegate 方法, 杜绝破坏 SwiftUI sheet 内部生命周期
private struct SheetPresentationCompatIntrospector: UIViewControllerRepresentable {
    let prefersGrabberVisible: Bool
    let onDismissAttempt: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onDismissAttempt: onDismissAttempt)
    }

    func makeUIViewController(context: Context) -> SheetIntrospectViewController {
        let vc = SheetIntrospectViewController()
        vc.onResolve = { sheet in
            sheet.prefersGrabberVisible = prefersGrabberVisible
            context.coordinator.attach(to: sheet)
        }
        return vc
    }

    func updateUIViewController(_ vc: SheetIntrospectViewController, context: Context) {
        context.coordinator.onDismissAttempt = onDismissAttempt
        vc.onResolve = { sheet in
            sheet.prefersGrabberVisible = prefersGrabberVisible
            context.coordinator.attach(to: sheet)
        }
        vc.resolveAndNotify()
    }

    final class Coordinator: NSObject, UIAdaptivePresentationControllerDelegate {
        var onDismissAttempt: (() -> Void)?
        weak var originalDelegate: UIAdaptivePresentationControllerDelegate?
        private weak var attachedController: UIPresentationController?

        init(onDismissAttempt: (() -> Void)?) {
            self.onDismissAttempt = onDismissAttempt
        }

        func attach(to pc: UIPresentationController) {
            guard attachedController !== pc || pc.delegate !== self else { return }
            attachedController = pc
            if let existing = pc.delegate, existing !== self {
                // 同一 sheet 内可有多个内省器(嵌套子视图)轮流 attach。若现任 delegate
                // 的转发链已经回到 self, 再把它记为 originalDelegate 会形成 A→B→A 环,
                // responds(to:) 无限递归直至栈溢出(SIGSEGV)。self 已在链上则保持现状。
                if Self.chain(from: existing, reaches: self) { return }
                originalDelegate = existing
            }
            pc.delegate = self
        }

        private static func chain(from start: UIAdaptivePresentationControllerDelegate,
                                  reaches target: Coordinator) -> Bool {
            var node: UIAdaptivePresentationControllerDelegate? = start
            var hops = 0
            while let current = node as? Coordinator, hops < 32 {
                if current === target { return true }
                node = current.originalDelegate
                hops += 1
            }
            return node === target
        }

        // MARK: - UIAdaptivePresentationControllerDelegate 拦截与转发

        func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
            onDismissAttempt?()
            originalDelegate?.presentationControllerDidAttemptToDismiss?(presentationController)
        }

        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            originalDelegate?.presentationControllerDidDismiss?(presentationController)
        }

        func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool {
            return originalDelegate?.presentationControllerShouldDismiss?(presentationController) ?? true
        }

        func presentationControllerWillDismiss(_ presentationController: UIPresentationController) {
            originalDelegate?.presentationControllerWillDismiss?(presentationController)
        }

        func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
            return originalDelegate?.adaptivePresentationStyle?(for: controller) ?? .none
        }

        func adaptivePresentationStyle(
            for controller: UIPresentationController,
            traitCollection: UITraitCollection
        ) -> UIModalPresentationStyle {
            return originalDelegate?.adaptivePresentationStyle?(for: controller, traitCollection: traitCollection) ?? .none
        }

        override func responds(to aSelector: Selector!) -> Bool {
            if super.responds(to: aSelector) { return true }
            return originalDelegate?.responds(to: aSelector) ?? false
        }

        override func forwardingTarget(for aSelector: Selector!) -> Any? {
            if let orig = originalDelegate, orig.responds(to: aSelector) {
                return orig
            }
            return super.forwardingTarget(for: aSelector)
        }
    }
}

private final class SheetIntrospectViewController: UIViewController {
    var onResolve: ((UISheetPresentationController) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
    }

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        resolveAndNotify()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        resolveAndNotify()
    }

    func resolveAndNotify() {
        var attempts = 0
        func findSheet() {
            var node: UIViewController? = self
            while let cur = node {
                if let sheet = cur.sheetPresentationController {
                    onResolve?(sheet)
                    return
                }
                node = cur.parent ?? cur.presentingViewController
            }
            attempts += 1
            if attempts < 20 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: findSheet)
            }
        }
        findSheet()
    }
}

public struct SheetPresentationCompatModifier: ViewModifier {
    let dragIndicator: Visibility
    let onDismissAttempt: (() -> Void)?

    public func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content
                .presentationDragIndicator(dragIndicator)
                .background(
                    SheetPresentationCompatIntrospector(
                        prefersGrabberVisible: dragIndicator == .visible,
                        onDismissAttempt: onDismissAttempt
                    )
                )
        } else {
            content
                .background(
                    SheetPresentationCompatIntrospector(
                        prefersGrabberVisible: dragIndicator == .visible,
                        onDismissAttempt: onDismissAttempt
                    )
                )
        }
    }
}

public extension View {
    /// 兼容 iOS 15/16+ 的 sheet 拖拽指示条与下滑拦截统一配置
    func sheetPresentationCompat(
        dragIndicator: Visibility = .visible,
        onDismissAttempt: (() -> Void)? = nil
    ) -> some View {
        modifier(SheetPresentationCompatModifier(dragIndicator: dragIndicator, onDismissAttempt: onDismissAttempt))
    }

    /// 兼容 iOS 15/16+ 的 sheet 拖拽指示条展示控制
    func sheetDragIndicator(_ visibility: Visibility = .visible) -> some View {
        sheetPresentationCompat(dragIndicator: visibility, onDismissAttempt: nil)
    }

    /// 拦截 sheet 下滑关闭尝试 (当 interactiveDismissDisabled(true) 时触发, 桥接至退出确认)
    func onSheetDismissAttempt(perform action: @escaping () -> Void) -> some View {
        sheetPresentationCompat(dragIndicator: .visible, onDismissAttempt: action)
    }

    /// 别名：拦截 sheet 下滑关闭尝试
    func onDismissAttempt(perform action: @escaping () -> Void) -> some View {
        sheetPresentationCompat(dragIndicator: .visible, onDismissAttempt: action)
    }
}

// MARK: - Keyboard Dismissal on Scroll Compatibility (iOS 15/16)

public struct ScrollDismissesKeyboardImmediatelyModifier: ViewModifier {
    public func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.scrollDismissesKeyboard(.immediately)
        } else {
            content.simultaneousGesture(
                DragGesture(minimumDistance: 8).onChanged { _ in
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil, from: nil, for: nil
                    )
                }
            )
        }
    }
}

public extension View {
    /// Dismisses keyboard immediately when user drags/scrolls the view, compatible with iOS 15 & 16+
    func scrollDismissesKeyboardImmediatelyCompat() -> some View {
        modifier(ScrollDismissesKeyboardImmediatelyModifier())
    }
}
#endif

