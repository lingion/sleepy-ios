import SwiftUI
import UIKit
import Combine

private func traceCourseDrag(_ message: String) {
    #if DEBUG
    NSLog("[CourseDrag] %@", message)
    #endif
}

/// 会话归翻页容器持有；源页销毁不丢失课程身份和原周。
@MainActor
final class CourseDragContext: ObservableObject {
    struct Source {
        let course: CourseEntity
        let renderedCourse: CourseEntity
        let displayWeek: Int
        let displayDay: Int
        let occurrence: CourseOccurrenceIdentity
        let origin: CGPoint
        let grabOffsetY: CGFloat
        let snapOffsetY: CGFloat
        var cardCenterX: CGFloat? = nil
    }
    @Published var source: Source?
    @Published var projection: CGRect?
    var isHolding = false
    var sessionToken: NSObject?
    private var courseTouchDuration: TimeInterval?
    var grids: [Int: CourseDropGrid] = [:]
    struct Card {
        let course: CourseEntity
        let week: Int
        let frame: CGRect
    }
    var cards: [UUID: Card] = [:]

    func begin(_ course: CourseEntity, week: Int, frame: CGRect, touch: CGPoint?,
               table: TimeTableEntity, allCourses: [CourseEntity],
               transfers: [HolidayTransferEntry]) -> NSObject? {
        guard course.tableId == table.id,
               let original = allCourses.first(where: { $0.id == course.id && $0.tableId == table.id }),
               let occurrence = CourseOccurrenceIdentity.resolve(course: original, startDate: table.startDate, maxWeek: table.maxWeek,
                   displayWeek: week, displayDay: course.day, transfers: transfers),
               occurrence.matches(original, startDate: table.startDate) else { return nil }
        let started = ProcessInfo.processInfo.systemUptime
        let token = NSObject()
        sessionToken = token
        let origin = touch ?? CGPoint(x: frame.midX, y: frame.midY)
        let sourceRowTop = grids[week].flatMap { grid in
            grid.rows.first(where: { $0.node == course.startNode }).map { grid.frame.minY + $0.top }
        } ?? frame.minY
        source = Source(course: original, renderedCourse: course, displayWeek: week, displayDay: course.day,
                        occurrence: occurrence, origin: origin,
                        grabOffsetY: max(0, min(frame.height, origin.y - frame.minY)),
                        snapOffsetY: origin.y - sourceRowTop, cardCenterX: frame.midX)
        isHolding = true
        if projection != nil { projection = nil }
        traceCourseDrag("begin frame=\(frame) touch=\(String(describing: touch)) elapsed=\(ProcessInfo.processInfo.systemUptime - started)")
        return token
    }

    func recordCourseTouchDuration(_ duration: TimeInterval?) {
        courseTouchDuration = duration
    }

    var permitsCourseTap: Bool {
        // A recognized hold stays consumed through either release callback
        // order. The next course touch resets this gate; AX uses its own gate.
        permitsCourseActivation && (courseTouchDuration ?? 0) < 0.5
    }

    var permitsCourseActivation: Bool { source == nil }

    func end() {
        traceCourseDrag("context end")
        source = nil
        if projection != nil { projection = nil }
        sessionToken = nil
        isHolding = false
    }
}

/// 高频落点更新只重绘投影，不让整套周分页重新计算课程及布局。
struct CourseDragProjection: View {
    @ObservedObject var drag: CourseDragContext
    @Environment(\.localWakeUpColors) private var colors

    var body: some View {
        GeometryReader { geometry in
            if let projection = drag.projection {
                RoundedRectangle(cornerRadius: 10)
                    .fill(colors.primary.opacity(0.16))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(colors.primary, lineWidth: 2))
                    .frame(width: projection.width, height: projection.height)
                    .offset(x: projection.minX - geometry.frame(in: .global).minX,
                            y: projection.minY - geometry.frame(in: .global).minY)
                    .accessibilityIdentifier("course_drop_projection")
            }
        }.allowsHitTesting(false)
    }
}

private struct CourseDragContextKey: EnvironmentKey {
    static let defaultValue: CourseDragContext? = nil
}
private struct CourseDragWeekKey: EnvironmentKey {
    static let defaultValue = 1
}
extension EnvironmentValues {
    var courseDragContext: CourseDragContext? {
        get { self[CourseDragContextKey.self] }
        set { self[CourseDragContextKey.self] = newValue }
    }
    var courseDragWeek: Int {
        get { self[CourseDragWeekKey.self] }
        set { self[CourseDragWeekKey.self] = newValue }
    }
}

struct CourseDragSource: ViewModifier {
    @Environment(\.courseDragContext) private var drag
    @Environment(\.courseDragWeek) private var week
    let course: CourseEntity
    @State private var identity = UUID()

    @ViewBuilder func body(content: Content) -> some View {
        if let drag {
            content
                .background(GeometryReader { geometry in
                    Color.clear
                        .onAppear { register(geometry.frame(in: .global), in: drag) }
                        .onChange(of: geometry.frame(in: .global)) { register($0, in: drag) }
                        .onChange(of: try? JSONEncoder().encode(course)) { _ in
                            register(geometry.frame(in: .global), in: drag)
                        }
                })
                .onDisappear { drag.cards.removeValue(forKey: identity) }
                .accessibilityHint(L10n.t("schedule_drag_hint"))
        } else {
            content
        }
    }

    private func register(_ frame: CGRect, in drag: CourseDragContext) {
        drag.cards[identity] = .init(course: course, week: week, frame: frame)
    }
}

struct CourseDropGridKey: PreferenceKey {
    static var defaultValue: [Int: CourseDropGrid] = [:]
    static func reduce(value: inout [Int: CourseDropGrid], nextValue: () -> [Int: CourseDropGrid]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension CourseDropGrid {
    /// 与课程卡共用分钟映射；实测高度包含占位行和长课间。
    func timedProjection(start: String, end: String, column: CGRect) -> CGRect? {
        let slots = timeRows.map { row in
            TimeSlot(label: "\(row.node)", startHour: row.startMinute / 60,
                     startMinute: row.startMinute % 60, endHour: row.endMinute / 60,
                     endMinute: row.endMinute % 60, nodeStart: row.node)
        }
        guard let first = timeRows.first, let last = timeRows.last,
              let startSeconds = TimeTableUtils.hmToSeconds(start),
              let endSeconds = TimeTableUtils.hmToSeconds(end),
              startSeconds >= first.startMinute * 60, endSeconds <= last.endMinute * 60,
              let span = TimeTableUtils.timeToFractionalRows(start, end, slots: slots) else { return nil }
        func y(_ fraction: Double) -> CGFloat {
            let index = Int(fraction)
            guard index < timeRows.count else { return frame.height }
            return timeRows[index].top + timeRows[index].height * CGFloat(fraction - Double(index))
        }
        let bounds = CourseGridRowLayout.timedCardBounds(fraction: span,
            rowHeight: rowHeight, rowGap: rowGap, yOfRows: y,
            gapAfterRow: { timeRows[$0].gapAfter })
        return CGRect(x: column.minX, y: frame.minY + bounds.top, width: column.width,
                      height: bounds.height)
    }
}

/// 背景探针只在课程卡内识别长按；轻点和普通滚动由原视图处理。
struct NativeCourseDropTarget: UIViewRepresentable {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.localWakeUpColors) private var colors
    let drag: CourseDragContext
    let week: Int
    let maxWeek: Int
    let table: TimeTableEntity?
    let allCourses: [CourseEntity]
    let transfers: [HolidayTransferEntry]
    let enabled: Bool
    let onChangeWeek: (Int) -> Void
    let onMove: (CourseDragContext.Source, Int, Int, Int, String?, Int?) -> Bool
    let onOccurrenceAction: (CourseDragContext.Source, Bool) -> Void

    func makeUIView(context: Context) -> CourseDropTargetView {
        let view = CourseDropTargetView()
        updateUIView(view, context: context)
        return view
    }

    func updateUIView(_ view: CourseDropTargetView, context: Context) {
        view.drag = drag
        view.week = week
        view.maxWeek = maxWeek
        view.table = table
        view.allCourses = allCourses
        view.transfers = transfers
        view.enabled = enabled && isEnabled
        view.onChangeWeek = onChangeWeek
        view.onMove = onMove
        view.onOccurrenceAction = onOccurrenceAction
        view.primaryColor = UIColor(colors.primary)
        view.onPrimaryColor = UIColor(colors.onPrimary)
        view.releaseFinishedScrollLock()
        view.attach()
    }

    static func dismantleUIView(_ view: CourseDropTargetView, coordinator: ()) {
        view.detach()
    }
}

private final class CourseFloatingRangeHandle: UIView {
    var onAdjust: ((Int) -> Void)?
    override func accessibilityIncrement() { onAdjust?(1) }
    override func accessibilityDecrement() { onAdjust?(-1) }
}

private final class CourseFloatingPreviewView: UIView {
    let snapshot: UIView
    let topHandle = CourseFloatingRangeHandle()
    let bottomHandle = CourseFloatingRangeHandle()

    init(snapshot: UIView, primary: UIColor) {
        self.snapshot = snapshot
        super.init(frame: .zero)
        accessibilityIdentifier = "course_float_card"
        snapshot.isUserInteractionEnabled = false
        snapshot.accessibilityElementsHidden = true
        addSubview(snapshot)
        for (top, handle) in [(true, topHandle), (false, bottomHandle)] {
            handle.tag = top ? 0 : 1
            handle.isAccessibilityElement = true
            handle.accessibilityIdentifier = top ? "course_float_top" : "course_float_bottom"
            handle.accessibilityLabel = top ? L10n.t("start_node")
                : "\(L10n.t("end_label")) · \(L10n.t("step_count"))"
            handle.accessibilityTraits = .adjustable
            let pill = UIView()
            pill.backgroundColor = primary
            pill.layer.cornerRadius = 1.5
            pill.frame = CGRect(x: 0, y: 0, width: 16, height: 3)
            handle.addSubview(pill)
            addSubview(handle)
        }
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.2
        layer.shadowRadius = 8
        layer.shadowOffset = CGSize(width: 0, height: 5)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        snapshot.frame = bounds
        // Keep the handles outside the card and narrow enough that even a short
        // custom-time course still has a body area for moving it after pickup.
        let handleWidth = min(28, bounds.width)
        let handleX = (bounds.width - handleWidth) / 2
        topHandle.frame = CGRect(x: handleX, y: -18, width: handleWidth, height: 24)
        bottomHandle.frame = CGRect(x: handleX, y: bounds.height - 6, width: handleWidth, height: 24)
        topHandle.subviews.first?.center = CGPoint(x: handleWidth / 2, y: 12)
        bottomHandle.subviews.first?.center = CGPoint(x: handleWidth / 2, y: 12)
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.contains(point) || topHandle.frame.contains(point) || bottomHandle.frame.contains(point)
    }
}

final class CourseDropTargetView: UIView, UIGestureRecognizerDelegate {
    var drag: CourseDragContext? {
        willSet {
            if drag !== newValue { finishDrag(commit: false) }
        }
        didSet {
            guard oldValue !== drag else { return }
            sourceSubscription?.cancel()
            sourceSubscription = drag?.$source.sink { [weak self] source in
                guard source == nil else { return }
                // @Published emits before end() has cleared its session token.
                DispatchQueue.main.async { [weak self] in self?.releaseFinishedScrollLock() }
            }
        }
    }
    var week = 1
    var maxWeek = 20
    var table: TimeTableEntity?
    var allCourses: [CourseEntity] = []
    var transfers: [HolidayTransferEntry] = []
    var enabled = true {
        didSet {
            guard oldValue != enabled else { return }
            longPress?.isEnabled = enabled
            if !enabled { finishDrag(commit: false) }
        }
    }
    var onChangeWeek: (Int) -> Void = { _ in }
    var onMove: (CourseDragContext.Source, Int, Int, Int, String?, Int?) -> Bool = { _, _, _, _, _, _ in false }
    var onOccurrenceAction: (CourseDragContext.Source, Bool) -> Void = { _, _ in }
    var primaryColor: UIColor = .systemBlue {
        didSet { updateFloatingColors() }
    }
    var onPrimaryColor: UIColor = .white {
        didSet { updateFloatingColors() }
    }
    private weak var host: UIView?
    private var longPress: UILongPressGestureRecognizer?
    private var outsideTap: UITapGestureRecognizer?
    private var sourceSubscription: AnyCancellable?
    private var activeToken: NSObject?
    private var sourceFrame: CGRect?
    private var latestPoint: CGPoint?
    private var preview: CourseFloatingPreviewView?
    private var actions: UIStackView?
    private var panOrigin: CGPoint?
    private var resizeOrigin: (range: QuickAddRange, edge: CGFloat)?
    private var timer: Timer?
    private var paging = CourseDragEdgePaging()
    private var target: (day: Int, node: Int, rect: CGRect)?
    private var targetStartTime: String?
    private var previousWindowSize = CGSize.zero
    private var lockedScrollViews: [(UIScrollView, Bool)] = []

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = window?.bounds.size ?? .zero
        if previousWindowSize != .zero, size != previousWindowSize {
            finishDrag(commit: false)
        }
        previousWindowSize = size
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { detach() } else { attach() }
    }

    func attach() {
        guard let parent = window?.rootViewController?.view, host !== parent else { return }
        detach()
        let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        recognizer.name = "sleepy.courseDrag"
        recognizer.minimumPressDuration = 0.5
        recognizer.numberOfTouchesRequired = 1
        recognizer.allowableMovement = 10
        recognizer.cancelsTouchesInView = true
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        recognizer.delegate = self
        recognizer.isEnabled = enabled
        parent.addGestureRecognizer(recognizer)
        longPress = recognizer
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissFloating(_:)))
        tap.cancelsTouchesInView = true
        tap.delegate = self
        parent.addGestureRecognizer(tap)
        outsideTap = tap
        host = parent
    }

    func detach() {
        finishDrag(commit: false)
        if let longPress { host?.removeGestureRecognizer(longPress) }
        if let outsideTap { host?.removeGestureRecognizer(outsideTap) }
        longPress = nil
        outsideTap = nil
        host = nil
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let window else { return false }
        let point = touch.location(in: window)
        if gestureRecognizer === outsideTap {
            let inPreview = preview.map { $0.point(inside: $0.convert(point, from: window), with: nil) } ?? false
            return activeToken != nil && !inPreview
                && actions?.frame.contains(point) != true
        }
        if gestureRecognizer.view === preview {
            guard let preview else { return false }
            let local = touch.location(in: preview)
            return !preview.topHandle.frame.contains(local) && !preview.bottomHandle.frame.contains(local)
        }
        guard gestureRecognizer === longPress else { return false }
        let eligible = eligibleCard(at: point) != nil
        if eligible { drag?.recordCourseTouchDuration(nil) }
        return eligible
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === outsideTap { return activeToken != nil }
        if gestureRecognizer.view === preview { return activeToken != nil }
        guard gestureRecognizer === longPress, let window else { return false }
        let eligible = eligibleCard(at: gestureRecognizer.location(in: window)) != nil
        return eligible
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // SwiftUI's UIKitResponderGestureRecognizer begins on touch down and
        // otherwise prevents this hold from reaching began. Only course touches
        // enter this recognizer; the duration gate consumes their release.
        gestureRecognizer === longPress
    }

    private func eligibleCard(at point: CGPoint) -> CourseDragContext.Card? {
        guard enabled, let window, let drag, drag.source == nil, let table,
              window.rootViewController?.presentedViewController == nil,
              bounds.contains(convert(point, from: window)) else { return nil }
        return drag.cards.values.first {
            $0.week == week && $0.course.tableId == table.id && !$0.frame.isEmpty && $0.frame.contains(point)
        }
    }

    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard let window else { finishDrag(commit: false); return }
        let point = recognizer.location(in: window)
        switch recognizer.state {
        case .began:
            beginDrag(at: point, in: window)
        case .changed:
            guard activeToken != nil else { return }
            latestPoint = point
            updatePreview()
            updateLocation()
        case .ended:
            latestPoint = point
            releaseFloating()
        case .cancelled, .failed:
            finishDrag(commit: false)
        case .possible:
            break
        @unknown default:
            finishDrag(commit: false)
        }
    }

    private func beginDrag(at point: CGPoint, in window: UIWindow) {
        guard let card = eligibleCard(at: point), let drag, let table else { return }
        // Keep a recognized hold consumed through either recognizer's release
        // callback order. The next course touch resets this gate in shouldReceive.
        drag.recordCourseTouchDuration(0.5)
        let snapshot = window.resizableSnapshotView(from: card.frame, afterScreenUpdates: false,
                                                     withCapInsets: .zero) ?? UIView()
        guard let token = drag.begin(card.course, week: card.week, frame: card.frame, touch: point,
                                     table: table, allCourses: allCourses, transfers: transfers) else { return }
        activeToken = token
        sourceFrame = card.frame
        latestPoint = point
        lockScrolling(at: point, in: window)
        let floating = CourseFloatingPreviewView(snapshot: snapshot, primary: primaryColor)
        floating.topHandle.accessibilityValue = String(card.course.startNode)
        floating.bottomHandle.accessibilityValue = String(card.course.startNode + card.course.step - 1)
        floating.topHandle.onAdjust = { [weak self] in self?.adjustFloating(top: true, by: $0) }
        floating.bottomHandle.onAdjust = { [weak self] in self?.adjustFloating(top: false, by: $0) }
        floating.frame = card.frame
        floating.topHandle.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(resizeFloating(_:))))
        floating.bottomHandle.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(resizeFloating(_:))))
        let pan = UIPanGestureRecognizer(target: self, action: #selector(moveFloating(_:)))
        pan.delegate = self
        floating.addGestureRecognizer(pan)
        window.addSubview(floating)
        preview = floating
        makeFloatingActions(in: window)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        traceCourseDrag("long press began point=\(point) frame=\(card.frame)")
        startTracking()
        updateLocation()
    }

    private func updatePreview() {
        guard let point = latestPoint, let frame = sourceFrame, let source = drag?.source else { return }
        preview?.center = CGPoint(x: frame.midX + point.x - source.origin.x,
                                  y: frame.midY + point.y - source.origin.y)
        positionActions()
    }

    private func makeFloatingActions(in window: UIWindow) {
        let bar = UIStackView()
        bar.axis = .horizontal
        bar.spacing = 8
        bar.distribution = .fillEqually
        for (editing, key) in [(true, "occurrence_adjust"), (false, "occurrence_delete")] {
            let button = UIButton(type: .system)
            var configuration = UIButton.Configuration.filled()
            configuration.title = L10n.t(key)
            configuration.cornerStyle = .capsule
            configuration.baseBackgroundColor = primaryColor
            configuration.baseForegroundColor = onPrimaryColor
            button.configuration = configuration
            button.accessibilityIdentifier = editing ? "course_float_edit" : "course_float_delete"
            button.addAction(UIAction { [weak self] _ in
                guard let self, let source = self.drag?.source else { return }
                self.finishDrag(commit: false)
                self.onOccurrenceAction(source, editing)
            }, for: .touchUpInside)
            bar.addArrangedSubview(button)
        }
        window.addSubview(bar)
        actions = bar
        bar.isHidden = true
        positionActions()
    }

    private func updateFloatingColors() {
        preview?.topHandle.subviews.first?.backgroundColor = primaryColor
        preview?.bottomHandle.subviews.first?.backgroundColor = primaryColor
        for case let button as UIButton in actions?.arrangedSubviews ?? [] {
            var configuration = button.configuration
            configuration?.baseBackgroundColor = primaryColor
            configuration?.baseForegroundColor = onPrimaryColor
            button.configuration = configuration
        }
    }

    private func positionActions() {
        guard let window, let preview, let actions else { return }
        let width = min(max(preview.bounds.width * 2, 240), window.bounds.width - 32)
        actions.frame = CGRect(x: min(max(preview.frame.midX - width / 2, 16), window.bounds.width - width - 16),
            y: max(window.safeAreaInsets.top, preview.frame.minY - 54), width: width, height: 44)
    }

    private func releaseFloating() {
        guard let source = drag?.source else { finishDrag(commit: false); return }
        updateLocation(allowPaging: false)
        guard let destination = target else { finishDrag(commit: false); return }
        if week != source.displayWeek || destination.day != source.displayDay
            || destination.node != source.renderedCourse.startNode {
            finishDrag(commit: true)
        } else {
            timer?.invalidate()
            timer = nil
            drag?.projection = nil
            drag?.isHolding = false
            actions?.isHidden = false
        }
    }

    @objc private func dismissFloating(_ recognizer: UITapGestureRecognizer) {
        if recognizer.state == .ended { finishDrag(commit: false) }
    }

    @objc private func moveFloating(_ recognizer: UIPanGestureRecognizer) {
        guard let source = drag?.source, let preview else { return }
        switch recognizer.state {
        case .began:
            drag?.isHolding = true
            panOrigin = CGPoint(x: source.origin.x + preview.frame.midX - (sourceFrame?.midX ?? preview.frame.midX),
                                y: source.origin.y + preview.frame.midY - (sourceFrame?.midY ?? preview.frame.midY))
            actions?.isHidden = true
            if let window { lockScrolling(at: recognizer.location(in: window), in: window) }
            startTracking()
        case .changed, .ended:
            guard let panOrigin else { return }
            let delta = recognizer.translation(in: window)
            latestPoint = CGPoint(x: panOrigin.x + delta.x, y: panOrigin.y + delta.y)
            updatePreview()
            updateLocation()
            if recognizer.state == .ended { releaseFloating(); self.panOrigin = nil }
        case .cancelled, .failed: finishDrag(commit: false)
        default: break
        }
    }

    @objc private func resizeFloating(_ recognizer: UIPanGestureRecognizer) {
        guard let source = drag?.source, let grid = drag?.grids[source.displayWeek],
              let preview, let table else { return }
        let top = recognizer.view?.tag == 0
        switch recognizer.state {
        case .began:
            drag?.isHolding = true
            let range = QuickAddRange(day: source.displayDay, startNode: source.renderedCourse.startNode,
                endNode: source.renderedCourse.startNode + source.renderedCourse.step - 1)
            resizeOrigin = (range, top ? preview.frame.minY : preview.frame.maxY)
            actions?.isHidden = true
            timer?.invalidate()
            timer = nil
        case .changed, .ended:
            guard let origin = resizeOrigin else { return }
            let rows = grid.rows.map { QuickAddRow(node: $0.node,
                top: grid.frame.minY + $0.top, bottom: grid.frame.minY + $0.bottom) }
            let position = origin.edge + recognizer.translation(in: window).y
            let range = QuickAddCoursePolicy.resized(origin.range, top: top, position: position,
                rows: rows, maxStandard: table.nodesPerDay)
            guard let first = rows.first(where: { $0.node == range.startNode }),
                  let last = rows.first(where: { $0.node == range.endNode }) else { return }
            preview.frame = CGRect(x: preview.frame.minX, y: first.top, width: preview.frame.width,
                height: max(last.bottom - first.top, 12))
            positionActions()
            if recognizer.state == .ended {
                if range == origin.range {
                    actions?.isHidden = false
                    resizeOrigin = nil
                    drag?.isHolding = false
                    return
                }
                finishDrag(commit: true, resized: range)
            }
        case .cancelled, .failed: finishDrag(commit: false)
        default: break
        }
    }

    private func adjustFloating(top: Bool, by delta: Int) {
        guard let source = drag?.source, let grid = drag?.grids[source.displayWeek], let table else { return }
        let original = QuickAddRange(day: source.displayDay, startNode: source.renderedCourse.startNode,
            endNode: source.renderedCourse.startNode + source.renderedCourse.step - 1)
        let node = (top ? original.startNode : original.endNode) + delta
        let rows = grid.rows.map { QuickAddRow(node: $0.node, top: $0.top, bottom: $0.bottom) }
        guard let row = rows.first(where: { $0.node == node }) else { return }
        let range = QuickAddCoursePolicy.resized(original, top: top,
            position: top ? row.top : row.bottom, rows: rows, maxStandard: table.nodesPerDay)
        if range != original { finishDrag(commit: true, resized: range) }
    }

    private func lockScrolling(at point: CGPoint, in window: UIWindow) {
        guard lockedScrollViews.isEmpty, let host else { return }
        func visit(_ view: UIView) {
            if let scroll = view as? UIScrollView,
               scroll.convert(scroll.bounds, to: window).contains(point) {
                lockedScrollViews.append((scroll, scroll.isScrollEnabled))
                scroll.isScrollEnabled = false
            }
            for child in view.subviews { visit(child) }
        }
        visit(host)
    }

    func releaseFinishedScrollLock() {
        if let token = activeToken, drag?.sessionToken !== token { finishDrag(commit: false) }
    }

    private func restoreScrolling() {
        for (scroll, enabled) in lockedScrollViews { scroll.isScrollEnabled = enabled }
        lockedScrollViews.removeAll()
    }

    private func startTracking() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in self?.updateLocation() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func updateLocation(allowPaging: Bool = true) {
        guard enabled, let token = activeToken, let point = latestPoint, let window,
              let drag, drag.sessionToken === token, let source = drag.source else {
            finishDrag(commit: false)
            return
        }
        let local = convert(point, from: window)
        let global = convert(local, to: nil)
        let viewport = convert(bounds, to: nil)
        let origin = convert(source.origin, from: nil)
        let initialCenter = source.cardCenterX.map { convert(CGPoint(x: $0, y: source.origin.y), from: nil).x } ?? origin.x
        let centerX = initialCenter + local.x - origin.x
        let direction = CourseDragEdgePaging.direction(centerX: centerX, fingerX: local.x,
                                                       originX: initialCenter, width: bounds.width,
                                                       minimumX: bounds.minX)
        if allowPaging, let next = paging.update(direction: direction, now: ProcessInfo.processInfo.systemUptime,
                                    week: week, maxWeek: maxWeek,
                                    destinationReady: drag.grids[week + direction] != nil) {
            traceCourseDrag("page from=\(week) to=\(next) direction=\(direction)")
            week = next
            target = nil
            drag.projection = nil
            onChangeWeek(next)
            UISelectionFeedbackGenerator().selectionChanged()
        }
        target = nil
        targetStartTime = nil
        if bounds.contains(local), let measuredGrid = drag.grids[week], let table,
           table.id == source.course.tableId {
            let grid = measuredGrid.positioned(in: viewport)
            let isTimed = source.course.ownTime || source.course.isIrregularTime
            if let candidate = grid.target(at: global, step: isTimed ? 1 : max(source.course.step, 1),
                                            grabOffsetY: source.snapOffsetY,
                                            viewport: viewport, edgeDirection: direction) {
                let explicitStart = isTimed && candidate.node == source.renderedCourse.startNode ? source.course.startTime : nil
                guard CourseOccurrenceIdentity.destination(course: source.course, startDate: table.startDate, maxWeek: table.maxWeek,
                          displayWeek: week, displayDay: candidate.day, transfers: transfers) != nil,
                      let destination = try? CourseOccurrenceDestination.resolve(source: source.course,
                    targetNode: candidate.node, table: table, targetStartTime: explicitStart) else {
                    traceCourseDrag("destination rejected node=\(candidate.node) time=\(String(describing: explicitStart))")
                    drag.projection = nil
                    return
                }
                targetStartTime = explicitStart
                if isTimed {
                    if let rect = grid.candidateTimedProjection(source: source.course, sourceOccurrence: source.occurrence,
                        day: candidate.day, destination: destination, column: candidate.rect) {
                        target = (candidate.day, candidate.node, rect)
                    }
                } else {
                    target = candidate
                }
            }
        }
        if drag.projection != target?.rect { drag.projection = target?.rect }
    }

    private func finishDrag(commit: Bool, resized: QuickAddRange? = nil) {
        guard let token = activeToken else { return }
        timer?.invalidate()
        timer = nil
        if commit && resized == nil { updateLocation(allowPaging: false) }
        guard activeToken === token else { return }
        let context = drag
        let source = context?.source
        let destination = target
        let destinationWeek = week
        let startTime = targetStartTime
        activeToken = nil
        stopTracking()
        restoreScrolling()
        preview?.removeFromSuperview()
        preview = nil
        actions?.removeFromSuperview()
        actions = nil
        resizeOrigin = nil
        panOrigin = nil
        sourceFrame = nil
        guard context?.sessionToken === token else { return }
        if commit, let source, let destination {
            let success = onMove(source, resized == nil ? destinationWeek : source.displayWeek,
                resized?.day ?? destination.day, resized?.startNode ?? destination.node,
                resized == nil ? startTime : nil, resized?.step)
            traceCourseDrag("move sourceWeek=\(source.occurrence.week) targetWeek=\(destinationWeek) day=\(destination.day) node=\(destination.node) success=\(success)")
            UINotificationFeedbackGenerator().notificationOccurred(success ? .success : .error)
        }
        traceCourseDrag("long press ended commit=\(commit) target=\(String(describing: destination))")
        if context?.sessionToken === token { context?.end() }
    }

    private func stopTracking() {
        timer?.invalidate()
        timer = nil
        latestPoint = nil
        paging = CourseDragEdgePaging()
        target = nil
        targetStartTime = nil
        if drag?.projection != nil { drag?.projection = nil }
    }
}
