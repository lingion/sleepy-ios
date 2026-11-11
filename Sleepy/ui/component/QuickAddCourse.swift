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

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(days.enumerated()), id: \.element) { index, day in
                ForEach(rows, id: \.node) { row in
                    Button { state.select(day: day, node: row.node) } label: {
                        Color.clear.contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(width: columnWidth, height: max(0, row.bottom - row.top))
                    .offset(x: timeWidth + gap + CGFloat(index) * (columnWidth + gap), y: row.top)
                    .accessibilityLabel("\(L10n.t("schedule_add_course")), \(DateUtils.localizedDay(day)), \(L10n.format("period_format_node", "\(row.node)"))")
                    .accessibilityIdentifier("add-course-\(day)-\(row.node)")
                }
            }
        }
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
    let onConfirm: (QuickAddRange) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let selection = state.selection,
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
        .animation(SleepyMotionPolicy(reduceMotion: reduceMotion).fastEffects, value: state.selection != nil)
        .allowsHitTesting(state.selection != nil)
        .accessibilityHidden(state.selection == nil)
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
    @State private var resizeOrigin: CGFloat?

    var body: some View {
        ZStack {
            if style == .liquidGlass {
                confirmButton
                    .buttonStyle(SleepyPlatformButtonStyle(prominent: true, cornerRadius: 14, compact: true))
                    .tint(colors.primaryContainer)
            } else {
                confirmButton.buttonStyle(.plain)
            }
            VStack(spacing: 0) {
                handle(top: true)
                Spacer(minLength: 0).allowsHitTesting(false)
                handle(top: false)
            }
        }
        .foregroundColor(colors.onPrimaryContainer)
        .background(RoundedRectangle(cornerRadius: 14).fill(style == .classic ? colors.primaryContainer : .clear))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(style == .classic ? colors.primary : .clear, lineWidth: 1).allowsHitTesting(false))
        .background(GeometryReader { geometry in
            Color.clear
                .onAppear { state.capsuleBounds = geometry.frame(in: .global) }
                .onChange(of: geometry.frame(in: .global)) { state.capsuleBounds = $0 }
        })
        .accessibilityAction(named: Text(L10n.t("cancel"))) { state.dismiss() }
    }

    private var confirmButton: some View {
        Button { state.confirm(onConfirm) } label: {
            Text("+").font(.system(size: 24))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("\(L10n.t("schedule_add_course")), \(L10n.format("course_period_range", selection.startNode, selection.endNode))")
        .accessibilityIdentifier("quick-add-capsule")
    }

    private func handle(top: Bool) -> some View {
        Capsule().fill(colors.primary).frame(width: 16, height: 3)
            .frame(maxWidth: .infinity).frame(height: 14)
            .contentShape(Rectangle())
            .highPriorityGesture(DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { value in
                    if resizeOrigin == nil {
                        resizeOrigin = rows.first(where: {
                            $0.node == (top ? selection.startNode : selection.endNode)
                        }).map { top ? $0.top : $0.bottom }
                    }
                    guard let resizeOrigin, let current = state.selection else { return }
                    state.selection = QuickAddCoursePolicy.resized(current, top: top,
                        position: resizeOrigin + value.translation.height, rows: rows, maxStandard: maxStandard)
                }
                .onEnded { _ in resizeOrigin = nil })
            .accessibilityElement()
            .accessibilityLabel(top ? L10n.t("start_node") : "\(L10n.t("end_label")) \(L10n.t("step_count"))")
            .accessibilityValue("\(top ? selection.startNode : selection.endNode)")
            .accessibilityIdentifier(top ? "quick-add-top" : "quick-add-bottom")
            .accessibilityAdjustableAction { direction in
                let node = top ? selection.startNode : selection.endNode
                let next = node + (direction == .increment ? 1 : -1)
                guard let row = rows.first(where: { $0.node == next }) else { return }
                state.selection = QuickAddCoursePolicy.resized(selection, top: top,
                    position: top ? row.top : row.bottom, rows: rows, maxStandard: maxStandard)
            }
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
        var vcView: UIView?
        var highestHosting: UIView?
        while let view = cur, view !== window {
            if view.next is UIViewController, vcView == nil {
                vcView = view
            }
            if String(describing: type(of: view)).contains("HostingView") {
                highestHosting = view
            }
            cur = view.superview
        }
        if let vcView, let container = vcView.superview, container.isUserInteractionEnabled {
            return (container, vcView)
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
