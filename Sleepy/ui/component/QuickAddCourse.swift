import SwiftUI
import UIKit

/// 展示周由 ScheduleScreen 在确认时传递；这里仅保存网格选择，不写入课程库。
struct QuickAddRange: Equatable {
    let day: Int
    var startNode: Int
    var endNode: Int
    var step: Int { endNode - startNode + 1 }
}

struct QuickAddRow: Equatable {
    let node: Int
    let top: CGFloat
    let bottom: CGFloat
}

enum QuickAddCoursePolicy {
    /// 与 Android 相同：标准节次只能跨连续节点，边缘节次锁单节；占位行不在 rows 中。
    static func resized(_ selection: QuickAddRange, top: Bool, position: CGFloat,
                        rows: [QuickAddRow], maxStandard: Int) -> QuickAddRange {
        let nodes = Set(rows.map(\.node))
        guard nodes.contains(selection.startNode), nodes.contains(selection.endNode) else { return selection }
        var first = selection.startNode
        var last = selection.endNode
        if selection.startNode >= 1 && selection.startNode <= maxStandard {
            while first > 1 && nodes.contains(first - 1) { first -= 1 }
            while last < maxStandard && nodes.contains(last + 1) { last += 1 }
        }
        let lower = top ? first : selection.startNode
        let upper = top ? selection.endNode : last
        let candidates = rows.filter { $0.node >= lower && $0.node <= upper }
        guard let nearest = candidates.min(by: {
            abs((top ? $0.top : $0.bottom) - position) < abs((top ? $1.top : $1.bottom) - position)
        }) else { return selection }
        var result = selection
        if top { result.startNode = nearest.node } else { result.endNode = nearest.node }
        return result
    }
}

@MainActor
final class QuickAddCourseState: ObservableObject {
    @Published var selection: QuickAddRange?
    var capsuleBounds: CGRect?

    func select(day: Int, node: Int) {
        capsuleBounds = nil
        selection = QuickAddRange(day: day, startNode: node, endNode: node)
    }

    func dismiss() {
        capsuleBounds = nil
        selection = nil
    }

    /// 先清选择再调路由，防止返回编辑页后仍留胶囊。
    func confirm(_ action: (QuickAddRange) -> Void) {
        guard let selection else { return }
        dismiss()
        action(selection)
    }
}

/// 位于真实课程层下方，卡片/冲突簇照常优先命中。
struct QuickAddCourseCells: View {
    let state: QuickAddCourseState
    let days: [Int]
    let rows: [QuickAddRow]
    let timeWidth: CGFloat
    let columnWidth: CGFloat
    let gap: CGFloat
    var canSelect: () -> Bool = { true }

    var body: some View {
        let addTitle = L10n.t("schedule_add_course")
        let dayLabels = Dictionary(uniqueKeysWithValues: days.map { ($0, DateUtils.localizedDay($0)) })
        let nodeLabels = Dictionary(uniqueKeysWithValues: rows.map { ($0.node, L10n.format("period_format_node", "\($0.node)")) })
        ZStack(alignment: .topLeading) {
            ForEach(Array(days.enumerated()), id: \.element) { index, day in
                let x = timeWidth + gap + CGFloat(index) * (columnWidth + gap)
                let dayLabel = dayLabels[day] ?? ""
                ForEach(rows, id: \.node) { row in
                    let nodeLabel = nodeLabels[row.node] ?? ""
                    QuickAddCourseCell(state: state, day: day, node: row.node, canSelect: canSelect)
                    .frame(width: columnWidth, height: max(0, row.bottom - row.top))
                    .offset(x: x, y: row.top)
                    .accessibilityLabel("\(addTitle), \(dayLabel), \(nodeLabel)")
                    .accessibilityIdentifier("add-course-\(day)-\(row.node)")
                }
            }
        }
    }
}

@MainActor
private struct QuickAddCourseCell: View {
    let state: QuickAddCourseState
    let day: Int
    let node: Int
    let canSelect: () -> Bool
    @State private var eligibleAtPressStart = false

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 0.5, maximumDistance: 10,
                pressing: { pressing in
                    if pressing {
                        // A press that starts by dismissing a lifted course must
                        // not become quick-add after that same touch clears it.
                        eligibleAtPressStart = canSelect() && state.selection == nil
                    }
                }, perform: {
                    guard eligibleAtPressStart else { return }
                    selectIfAllowed()
                })
            .allowsHitTesting(canSelect())
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { selectIfAllowed() }
    }

    private func selectIfAllowed() {
        guard canSelect(), state.selection == nil else { return }
        state.select(day: day, node: node)
    }
}

struct QuickAddCourseLayer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var state: QuickAddCourseState
    let days: [Int]
    let rows: [QuickAddRow]
    let maxStandard: Int
    let timeWidth: CGFloat
    let columnWidth: CGFloat
    let gap: CGFloat
    var canDisplayCapsule: () -> Bool = { true }
    let onConfirm: (QuickAddRange) -> Void

    var body: some View {
        let activeSelection = canDisplayCapsule() ? state.selection : nil
        ZStack(alignment: .topLeading) {
            if let selection = activeSelection,
               let day = days.firstIndex(of: selection.day),
               let start = rows.first(where: { $0.node == selection.startNode }),
               let end = rows.first(where: { $0.node == selection.endNode }) {
                QuickAddCourseCapsule(state: state, selection: selection, rows: rows,
                                      maxStandard: maxStandard, onConfirm: onConfirm)
                    .frame(width: columnWidth, height: max(0, end.bottom - start.top))
                    .transition(SleepyMotionPolicy(reduceMotion: reduceMotion).popup)
                    .offset(x: timeWidth + gap + CGFloat(day) * (columnWidth + gap), y: start.top)
            }
        }
        // 仅可见性触发，拖动手柄改变范围时不补间网格几何。
        .animation(SleepyMotionPolicy(reduceMotion: reduceMotion).fastEffects, value: activeSelection != nil)
        .allowsHitTesting(activeSelection != nil)
        .accessibilityHidden(activeSelection == nil)
    }
}

private struct QuickAddCourseCapsule: View {
    @Environment(\.localWakeUpColors) private var colors
    @Environment(\.sleepyUIStyle) private var style
    @ObservedObject var state: QuickAddCourseState
    let selection: QuickAddRange
    let rows: [QuickAddRow]
    let maxStandard: Int
    let onConfirm: (QuickAddRange) -> Void

    var body: some View {
        ZStack {
            capsuleSurface
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            QuickAddCapsuleInteractiveOverlay(
                state: state,
                selection: selection,
                rows: rows,
                maxStandard: maxStandard,
                confirmLabel: "\(L10n.t("schedule_add_course")), \(L10n.format("course_period_range", selection.startNode, selection.endNode))",
                topLabel: L10n.t("start_node"),
                bottomLabel: "\(L10n.t("end_label")) \(L10n.t("step_count"))",
                primaryColor: UIColor(colors.primary),
                onConfirm: onConfirm
            )
        }
        .foregroundColor(colors.onPrimaryContainer)
        .background(GeometryReader { geometry in
            Color.clear
                .onAppear { state.capsuleBounds = geometry.frame(in: .global) }
                .onChange(of: geometry.frame(in: .global)) { state.capsuleBounds = $0 }
        })
        .accessibilityAction(named: Text(L10n.t("cancel"))) { state.dismiss() }
    }

    @ViewBuilder
    private var capsuleSurface: some View {
        if style == .liquidGlass {
            Text("+").font(.system(size: 24))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .sleepyControlSurface(cornerRadius: 14, tint: colors.primaryContainer, prominent: true)
        } else {
            Text("+").font(.system(size: 24))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 14).fill(colors.primaryContainer))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(colors.primary, lineWidth: 1))
        }
    }
}

/// Separate UIKit hit-test/AX layer so 1-slot 48pt capsules never let top/bottom
/// resize handles eclipse `quick-add-capsule` center hit testing in XCTest/VoiceOver.
private struct QuickAddCapsuleInteractiveOverlay: UIViewRepresentable {
    let state: QuickAddCourseState
    let selection: QuickAddRange
    let rows: [QuickAddRow]
    let maxStandard: Int
    let confirmLabel: String
    let topLabel: String
    let bottomLabel: String
    let primaryColor: UIColor
    let onConfirm: (QuickAddRange) -> Void

    func makeUIView(context: Context) -> QuickAddCapsuleOverlayView {
        QuickAddCapsuleOverlayView()
    }

    func updateUIView(_ view: QuickAddCapsuleOverlayView, context: Context) {
        view.state = state
        view.selection = selection
        view.rows = rows
        view.maxStandard = maxStandard
        view.onConfirm = onConfirm
        view.confirmButton.accessibilityLabel = confirmLabel
        view.topHandle.accessibilityLabel = topLabel
        view.topHandle.accessibilityValue = "\(selection.startNode)"
        view.bottomHandle.accessibilityLabel = bottomLabel
        view.bottomHandle.accessibilityValue = "\(selection.endNode)"
        view.updateHandleColors(primaryColor)
    }
}

private final class QuickAddCapsuleHandleView: UIView {
    var onAdjust: (Int) -> Void = { _ in }
    let pill = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isAccessibilityElement = true
        accessibilityTraits = .adjustable
        pill.layer.cornerRadius = 1.5
        pill.isUserInteractionEnabled = false
        addSubview(pill)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        pill.frame = CGRect(x: (bounds.width - 16) / 2, y: (bounds.height - 3) / 2, width: 16, height: 3)
    }

    override func accessibilityIncrement() { onAdjust(1) }
    override func accessibilityDecrement() { onAdjust(-1) }
}

private final class QuickAddCapsuleOverlayView: UIView {
    weak var state: QuickAddCourseState?
    var selection = QuickAddRange(day: 1, startNode: 1, endNode: 1)
    var rows: [QuickAddRow] = []
    var maxStandard = 12
    var onConfirm: (QuickAddRange) -> Void = { _ in }

    let confirmButton = UIButton(type: .custom)
    let topHandle = QuickAddCapsuleHandleView()
    let bottomHandle = QuickAddCapsuleHandleView()
    private var topResizeOrigin: CGFloat?
    private var bottomResizeOrigin: CGFloat?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isAccessibilityElement = false

        confirmButton.backgroundColor = .clear
        confirmButton.accessibilityIdentifier = "quick-add-capsule"
        confirmButton.addAction(UIAction { [weak self] _ in
            guard let self, let state = self.state else { return }
            state.confirm(self.onConfirm)
        }, for: .touchUpInside)
        addSubview(confirmButton)

        topHandle.accessibilityIdentifier = "quick-add-top"
        topHandle.onAdjust = { [weak self] delta in self?.adjust(top: true, by: delta) }
        topHandle.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(dragTop(_:))))
        addSubview(topHandle)

        bottomHandle.accessibilityIdentifier = "quick-add-bottom"
        bottomHandle.onAdjust = { [weak self] delta in self?.adjust(top: false, by: delta) }
        bottomHandle.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(dragBottom(_:))))
        addSubview(bottomHandle)

        accessibilityElements = [topHandle, bottomHandle, confirmButton]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func updateHandleColors(_ color: UIColor) {
        topHandle.pill.backgroundColor = color
        bottomHandle.pill.backgroundColor = color
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        confirmButton.frame = bounds
        let handleHeight = min(12, max(8, floor(bounds.height / 4)))
        topHandle.frame = CGRect(x: 0, y: 0, width: bounds.width, height: handleHeight)
        bottomHandle.frame = CGRect(x: 0, y: bounds.height - handleHeight, width: bounds.width, height: handleHeight)
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, isUserInteractionEnabled, bounds.contains(point) else { return nil }
        if topHandle.frame.contains(point) { return topHandle }
        if bottomHandle.frame.contains(point) { return bottomHandle }
        return confirmButton
    }

    @objc private func dragTop(_ recognizer: UIPanGestureRecognizer) {
        handleDrag(recognizer, top: true, origin: &topResizeOrigin)
    }

    @objc private func dragBottom(_ recognizer: UIPanGestureRecognizer) {
        handleDrag(recognizer, top: false, origin: &bottomResizeOrigin)
    }

    private func handleDrag(_ recognizer: UIPanGestureRecognizer, top: Bool, origin: inout CGFloat?) {
        switch recognizer.state {
        case .began, .changed:
            if origin == nil {
                origin = rows.first(where: {
                    $0.node == (top ? selection.startNode : selection.endNode)
                }).map { top ? $0.top : $0.bottom }
            }
            guard let base = origin, let state, let current = state.selection else { return }
            let dy = recognizer.translation(in: nil).y
            state.selection = QuickAddCoursePolicy.resized(current, top: top,
                position: base + dy, rows: rows, maxStandard: maxStandard)
        case .ended, .cancelled, .failed:
            origin = nil
        default:
            break
        }
    }

    private func adjust(top: Bool, by delta: Int) {
        let node = (top ? selection.startNode : selection.endNode) + delta
        guard let state, let row = rows.first(where: { $0.node == node }) else { return }
        state.selection = QuickAddCoursePolicy.resized(selection, top: top,
            position: top ? row.top : row.bottom, rows: rows, maxStandard: maxStandard)
    }
}

/// 顶层透明命中面：胶囊内穿透，外侧按下由本 UIView 持有整次触摸。
/// 不能用父级 onTapGesture，否则课程按钮/空格会在取消的同一次 tap 中响应；
/// 也不能直接把拦截型 UIViewRepresentable 覆在整屏之上（iOS 15 PlatformViewHost
/// 在子视图 hitTest 返回 nil 时仍会返回自身，导致课表滚动与点击全部被吞）。
/// 改为不吃触摸的锚点，仅在胶囊激活时向宿主页容器挂载独立 UIView 拦截外侧按下。
struct QuickAddOutsidePressShield: View {
    @ObservedObject var state: QuickAddCourseState

    var body: some View {
        QuickAddOutsidePressAnchor(state: state, isActive: state.selection != nil)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct QuickAddOutsidePressAnchor: UIViewRepresentable {
    let state: QuickAddCourseState
    let isActive: Bool

    func makeUIView(context: Context) -> QuickAddOutsidePressAnchorView {
        QuickAddOutsidePressAnchorView()
    }

    func updateUIView(_ view: QuickAddOutsidePressAnchorView, context: Context) {
        view.state = state
        view.syncShield(isActive: isActive)
    }

    static func dismantleUIView(_ view: QuickAddOutsidePressAnchorView, coordinator: ()) {
        view.detachShield()
    }
}

private final class QuickAddOutsidePressAnchorView: UIView {
    weak var state: QuickAddCourseState?
    private var active = false
    private let shieldView: QuickAddOutsidePressView = {
        let view = QuickAddOutsidePressView()
        view.backgroundColor = .clear
        view.isAccessibilityElement = false
        view.accessibilityElementsHidden = true
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        syncShield(isActive: active)
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        syncShield(isActive: active)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        syncShield(isActive: active)
    }

    func detachShield() {
        active = false
        shieldView.state = nil
        shieldView.removeFromSuperview()
    }

    func syncShield(isActive: Bool) {
        active = isActive
        shieldView.state = state
        guard isActive, let window, let state, state.selection != nil, !bounds.isEmpty else {
            shieldView.state = nil
            shieldView.removeFromSuperview()
            return
        }
        let (container, hostRoot) = resolveShieldHost(in: window)
        let targetFrame = container.convert(bounds, from: self)
        guard !targetFrame.isEmpty else {
            shieldView.removeFromSuperview()
            return
        }
        if shieldView.superview !== container {
            shieldView.removeFromSuperview()
            if let hostRoot, hostRoot.superview === container {
                container.insertSubview(shieldView, aboveSubview: hostRoot)
            } else {
                container.addSubview(shieldView)
            }
        } else if let hostRoot, hostRoot.superview === container,
                  let hostIndex = container.subviews.firstIndex(of: hostRoot),
                  let shieldIndex = container.subviews.firstIndex(of: shieldView),
                  shieldIndex < hostIndex {
            container.insertSubview(shieldView, aboveSubview: hostRoot)
        }
        if shieldView.frame != targetFrame {
            shieldView.frame = targetFrame
        }
        shieldView.isHidden = false
        shieldView.isUserInteractionEnabled = true
    }

    private func resolveShieldHost(in window: UIWindow) -> (container: UIView, above: UIView?) {
        var cur = superview
        var navChildView: UIView?
        var vcView: UIView?
        var highestHosting: UIView?
        while let view = cur, view !== window {
            if let vc = view.next as? UIViewController {
                if vcView == nil { vcView = view }
                if vc.parent is UINavigationController { navChildView = view }
            }
            if String(describing: type(of: view)).contains("HostingView") {
                highestHosting = view
            }
            cur = view.superview
        }
        if let targetVCView = navChildView ?? vcView,
           let container = targetVCView.superview, container.isUserInteractionEnabled {
            return (container, targetVCView)
        }
        if let highestHosting, let container = highestHosting.superview, container.isUserInteractionEnabled {
            return (container, highestHosting)
        }
        return (window, nil)
    }
}

final class QuickAddOutsidePressView: UIView {
    weak var state: QuickAddCourseState?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, isUserInteractionEnabled, let state, state.selection != nil,
              bounds.contains(point),
              state.capsuleBounds?.contains(convert(point, to: nil)) != true else { return nil }
        return self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        state?.dismiss()
    }
}
