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
    @ObservedObject var state: QuickAddCourseState
    let days: [Int]
    let rows: [QuickAddRow]
    let maxStandard: Int
    let timeWidth: CGFloat
    let columnWidth: CGFloat
    let gap: CGFloat
    let onConfirm: (QuickAddRange) -> Void

    var body: some View {
        if let selection = state.selection,
           let day = days.firstIndex(of: selection.day),
           let start = rows.first(where: { $0.node == selection.startNode }),
           let end = rows.first(where: { $0.node == selection.endNode }) {
            QuickAddCourseCapsule(state: state, selection: selection, rows: rows,
                                  maxStandard: maxStandard, onConfirm: onConfirm)
                .frame(width: columnWidth, height: max(0, end.bottom - start.top))
                .offset(x: timeWidth + gap + CGFloat(day) * (columnWidth + gap), y: start.top)
        }
    }
}

private struct QuickAddCourseCapsule: View {
    @Environment(\.localWakeUpColors) private var colors
    @ObservedObject var state: QuickAddCourseState
    let selection: QuickAddRange
    let rows: [QuickAddRow]
    let maxStandard: Int
    let onConfirm: (QuickAddRange) -> Void
    @State private var resizeOrigin: CGFloat?

    var body: some View {
        ZStack {
            Button { state.confirm(onConfirm) } label: {
                Text("+").font(.system(size: 24))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(L10n.t("schedule_add_course")), \(L10n.format("course_period_range", selection.startNode, selection.endNode))")
            .accessibilityIdentifier("quick-add-capsule")
            VStack(spacing: 0) {
                handle(top: true)
                Spacer(minLength: 0).allowsHitTesting(false)
                handle(top: false)
            }
        }
        .foregroundColor(colors.onPrimaryContainer)
        .background(RoundedRectangle(cornerRadius: 14).fill(colors.primaryContainer))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(colors.primary, lineWidth: 1).allowsHitTesting(false))
        .background(GeometryReader { geometry in
            Color.clear
                .onAppear { state.capsuleBounds = geometry.frame(in: .global) }
                .onChange(of: geometry.frame(in: .global)) { state.capsuleBounds = $0 }
        })
        .accessibilityAction(named: Text(L10n.t("cancel"))) { state.dismiss() }
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
/// 不能用父级 onTapGesture，否则课程按钮/空格会在取消的同一次 tap 中响应。
struct QuickAddOutsidePressShield: UIViewRepresentable {
    @ObservedObject var state: QuickAddCourseState

    func makeUIView(context: Context) -> QuickAddOutsidePressView { QuickAddOutsidePressView() }
    func updateUIView(_ view: QuickAddOutsidePressView, context: Context) { view.state = state }
}

final class QuickAddOutsidePressView: UIView {
    weak var state: QuickAddCourseState?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let state, state.selection != nil, bounds.contains(point),
              state.capsuleBounds?.contains(convert(point, to: nil)) != true else { return nil }
        return self
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        state?.dismiss()
    }
}
