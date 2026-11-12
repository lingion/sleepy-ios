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
    @Published var isDragging = false
    @Published var edgeFeedback = CourseDragEdgeFeedback()
    var isHolding = false
    var awaitingConfirmation = false
    var onConfirmation: ((Bool) -> Void)?
    var sessionToken: NSObject?
    private var courseTouchDuration: TimeInterval?
    var grids: [Int: CourseDropGrid] = [:]
    var scrollViews: [Int: CourseDragScrollReference] = [:]
    struct Card {
        let course: CourseEntity
        let week: Int
        let frame: CGRect
        var isGrey = false
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
        isDragging = false
        awaitingConfirmation = false
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
        isDragging = false
        edgeFeedback = .init()
        awaitingConfirmation = false
        onConfirmation = nil
    }

    func resolveConfirmation(saved: Bool) { onConfirmation?(saved) }
}

final class CourseDragScrollReference {
    weak var view: UIScrollView?
    init(_ view: UIScrollView) { self.view = view }
}

struct CourseDragScrollProbe: UIViewRepresentable {
    @Environment(\.courseDragContext) private var drag
    @Environment(\.courseDragWeek) private var week

    func makeUIView(context: Context) -> Probe { Probe() }
    func updateUIView(_ view: Probe, context: Context) {
        view.drag = drag
        view.week = week
        view.registerScrollView()
    }

    final class Probe: UIView {
        weak var drag: CourseDragContext?
        var week = 1
        override func didMoveToWindow() { super.didMoveToWindow(); registerScrollView() }
        override func didMoveToSuperview() { super.didMoveToSuperview(); registerScrollView() }
        func registerScrollView() {
            var ancestor = superview
            while let view = ancestor {
                if let scroll = view as? UIScrollView {
                    drag?.scrollViews[week] = CourseDragScrollReference(scroll)
                    return
                }
                ancestor = view.superview
            }
        }
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
    var isGrey = false
    @State private var identity = UUID()

    @ViewBuilder func body(content: Content) -> some View {
        if let drag {
            content
                .modifier(CourseDragSourceDim(drag: drag, course: course, week: week))
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
        drag.cards[identity] = .init(course: course, week: week, frame: frame, isGrey: isGrey)
    }
}

private struct CourseDragSourceDim: ViewModifier {
    @ObservedObject var drag: CourseDragContext
    let course: CourseEntity
    let week: Int

    func body(content: Content) -> some View {
        content.opacity(drag.isDragging && drag.source?.course.id == course.id
            && drag.source?.displayWeek == week ? 0.38 : 1)
    }
}

struct CourseDragEdgePeek: View {
    @ObservedObject var drag: CourseDragContext
    @Environment(\.localWakeUpColors) private var colors

    var body: some View {
        let edge = drag.edgeFeedback
        HStack(spacing: 0) {
            if edge.direction > 0 { Spacer(minLength: 0) }
            VStack(spacing: 6) {
                Text(L10n.format("schedule_week_prefix", edge.targetWeek))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(edge.blocked ? colors.onSurfaceVariant : colors.primary)
                ForEach([0.9, 0.6, 0.75], id: \.self) { width in
                    Capsule().fill(colors.primary.opacity(0.25)).frame(width: 30 * width, height: 4)
                }
            }
            .frame(width: 56).frame(maxHeight: .infinity)
            .background(colors.surfaceContainerHigh.opacity(0.94))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .scaleEffect(edge.scale, anchor: edge.direction < 0 ? .leading : .trailing)
            .opacity(edge.opacity)
            if edge.direction <= 0 { Spacer(minLength: 0) }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
        .accessibilityIdentifier(edge.direction < 0 ? "course_peek_left" : "course_peek_right")
    }
}

struct CourseDragBackdrop: ViewModifier {
    @ObservedObject var drag: CourseDragContext

    func body(content: Content) -> some View {
        let lifted = drag.source != nil && !drag.isDragging
        content
            .blur(radius: lifted ? 20 : 0)
            .overlay(Color.black.opacity(lifted ? 0.12 : 0).allowsHitTesting(false))
            .animation(drag.isDragging ? nil : .easeOut(duration: 0.15), value: lifted)
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
    @Environment(\.colorScheme) private var colorScheme
    let drag: CourseDragContext
    let week: Int
    let maxWeek: Int
    let table: TimeTableEntity?
    let allCourses: [CourseEntity]
    let transfers: [HolidayTransferEntry]
    let enabled: Bool
    let onChangeWeek: (Int) -> Void
    let onMove: (CourseDragContext.Source, Int, Int, Int, String?, Int?, Bool) -> Bool
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
        view.surfaceColor = UIColor(colors.surfaceContainerHigh)
        view.outlineColor = UIColor(colors.outlineVariant)
        view.errorColor = UIColor(colors.error)
        view.makeCardContent = { course, height, isGrey in
            AnyView(CourseOverlayCard(course: course, cardHeight: height, isDark: colorScheme == .dark,
                isGrey: isGrey,
                groupRows: allCourses.filter { $0.groupId == course.groupId },
                scale: AppPrefs.shared.getGridScale(), cornerRatio: AppPrefs.shared.getGridCornerRatio(),
                onClick: {})
                .environment(\.localWakeUpColors, colors).environment(\.colorScheme, colorScheme)
                .allowsHitTesting(false))
        }
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
    private let contentController: UIHostingController<AnyView>
    let topHandle = CourseFloatingRangeHandle()
    let bottomHandle = CourseFloatingRangeHandle()

    init(content: AnyView, primary: UIColor) {
        let controller = UIHostingController(rootView: content)
        contentController = controller
        snapshot = controller.view
        super.init(frame: .zero)
        accessibilityIdentifier = "course_float_card"
        snapshot.isUserInteractionEnabled = false
        snapshot.backgroundColor = .clear
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

    func updateContent(_ content: AnyView) { contentController.rootView = content }

    override func layoutSubviews() {
        super.layoutSubviews()
        snapshot.frame = bounds
        let handleHeight = min(14, bounds.height / 3)
        topHandle.frame = CGRect(x: 0, y: 0, width: bounds.width, height: handleHeight)
        bottomHandle.frame = CGRect(x: 0, y: bounds.height - handleHeight, width: bounds.width, height: handleHeight)
        topHandle.subviews.first?.center = CGPoint(x: bounds.width / 2, y: handleHeight / 2)
        bottomHandle.subviews.first?.center = CGPoint(x: bounds.width / 2, y: handleHeight / 2)
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
            // SwiftUI assigns this during updateUIView. Disabling a recognizer
            // can cancel a lift and publish the session's end synchronously.
            let expected = enabled
            DispatchQueue.main.async { [weak self] in
                guard let self, self.enabled == expected else { return }
                self.longPress?.isEnabled = expected
                if !expected && self.drag?.awaitingConfirmation != true { self.finishDrag(commit: false) }
            }
        }
    }
    var onChangeWeek: (Int) -> Void = { _ in }
    var onMove: (CourseDragContext.Source, Int, Int, Int, String?, Int?, Bool) -> Bool = { _, _, _, _, _, _, _ in false }
    var onOccurrenceAction: (CourseDragContext.Source, Bool) -> Void = { _, _ in }
    var primaryColor: UIColor = .systemBlue {
        didSet { updateFloatingColors() }
    }
    var onPrimaryColor: UIColor = .white {
        didSet { updateFloatingColors() }
    }
    var surfaceColor: UIColor = .secondarySystemBackground
    var outlineColor: UIColor = .separator
    var errorColor: UIColor = .systemRed
    var makeCardContent: (CourseEntity, CGFloat, Bool) -> AnyView = { _, _, _ in AnyView(Color.clear) }
    private weak var host: UIView?
    private var longPress: UILongPressGestureRecognizer?
    private var outsideTap: UITapGestureRecognizer?
    private var sourceSubscription: AnyCancellable?
    private var activeToken: NSObject?
    private var sourceFrame: CGRect?
    private var latestPoint: CGPoint?
    private var preview: CourseFloatingPreviewView?
    private var actions: UIStackView?
    private var movementAnchor: (point: CGPoint, frame: CGRect, snapOffsetY: CGFloat)?
    private var resizeOrigin: (range: QuickAddRange, edge: CGFloat)?
    private var currentRange: QuickAddRange?
    private var movedSincePickup = false
    private var confirmationIsResize = false
    private var snapAnimator: UIViewPropertyAnimator?
    private var previewTargetFrame: CGRect?
    private var lastVerticalDirection = 0
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
            return activeToken != nil && drag?.awaitingConfirmation != true && !inPreview
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
        if gestureRecognizer === outsideTap { return activeToken != nil && drag?.awaitingConfirmation != true }
        if gestureRecognizer.view === preview { return activeToken != nil && drag?.awaitingConfirmation != true }
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
        guard drag?.awaitingConfirmation != true else { return }
        guard let window else { finishDrag(commit: false); return }
        let point = recognizer.location(in: window)
        switch recognizer.state {
        case .began:
            beginDrag(at: point, in: window)
        case .changed:
            guard activeToken != nil else { return }
            if !movedSincePickup {
                guard let origin = drag?.source?.origin,
                      // Android uses twice its touch slop after a lift. The 8pt
                      // edge-paging threshold is separate from this jitter gate.
                      hypot(point.x - origin.x, point.y - origin.y) >= 16 else { return }
                beginMovement()
            }
            if let previous = latestPoint, abs(point.y - previous.y) > 0.5 {
                lastVerticalDirection = point.y > previous.y ? 1 : -1
            }
            latestPoint = point
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
        guard let token = drag.begin(card.course, week: card.week, frame: card.frame, touch: point,
                                     table: table, allCourses: allCourses, transfers: transfers) else { return }
        activeToken = token
        var liftedFrame = card.frame
        if let grid = drag.grids[card.week], let column = grid.days.firstIndex(of: card.course.day),
           let first = grid.rows.first(where: { $0.node == card.course.startNode }),
           let last = grid.rows.first(where: { $0.node == card.course.startNode + card.course.step - 1 }) {
            liftedFrame = CGRect(x: grid.frame.minX + grid.timeWidth + grid.gap
                + CGFloat(column) * (grid.columnWidth + grid.gap),
                y: grid.frame.minY + first.top, width: grid.columnWidth, height: last.bottom - first.top)
        }
        sourceFrame = liftedFrame
        latestPoint = point
        movementAnchor = (point, liftedFrame, point.y - liftedFrame.minY)
        currentRange = QuickAddRange(day: card.course.day, startNode: card.course.startNode,
            endNode: card.course.startNode + card.course.step - 1)
        movedSincePickup = false
        lastVerticalDirection = 0
        lockScrolling(at: point, in: window)
        let floating = CourseFloatingPreviewView(content: makeCardContent(card.course, liftedFrame.height, card.isGrey), primary: primaryColor)
        floating.topHandle.accessibilityValue = String(card.course.startNode)
        floating.bottomHandle.accessibilityValue = String(card.course.startNode + card.course.step - 1)
        floating.topHandle.onAdjust = { [weak self] in self?.adjustFloating(top: true, by: $0) }
        floating.bottomHandle.onAdjust = { [weak self] in self?.adjustFloating(top: false, by: $0) }
        floating.frame = liftedFrame
        floating.topHandle.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(resizeFloating(_:))))
        floating.bottomHandle.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(resizeFloating(_:))))
        let pan = UIPanGestureRecognizer(target: self, action: #selector(moveFloating(_:)))
        pan.delegate = self
        floating.addGestureRecognizer(pan)
        window.addSubview(floating)
        preview = floating
        previewTargetFrame = liftedFrame
        drag.onConfirmation = { [weak self] saved in self?.resolveConfirmation(saved: saved) }
        makeFloatingActions(in: window)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        traceCourseDrag("long press began point=\(point) frame=\(card.frame)")
    }

    private func beginMovement() {
        movedSincePickup = true
        drag?.isHolding = true
        drag?.isDragging = true
        actions?.isHidden = true
        preview?.topHandle.isHidden = true
        preview?.bottomHandle.isHidden = true
        startTracking()
    }

    private func updatePreview() {
        guard let point = latestPoint, let anchor = movementAnchor else { return }
        let frame = anchor.frame
        let free = CGRect(x: frame.minX + point.x - anchor.point.x,
            y: frame.minY + point.y - anchor.point.y, width: frame.width, height: frame.height)
        placePreview(at: target?.rect ?? free, animated: target != nil)
    }

    private func placePreview(at frame: CGRect, animated: Bool) {
        guard let preview, previewTargetFrame != frame else { return }
        freezePreview()
        previewTargetFrame = frame
        let changes = { [weak self, weak preview] in
            preview?.frame = frame
            preview?.layoutIfNeeded()
            self?.positionActions()
        }
        guard animated && !UIAccessibility.isReduceMotionEnabled else { changes(); return }
        let animator = UIViewPropertyAnimator(duration: 0.15,
            timingParameters: UICubicTimingParameters(controlPoint1: CGPoint(x: 0.1, y: 0.1),
                controlPoint2: CGPoint(x: 0, y: 1)))
        animator.addAnimations(changes)
        snapAnimator = animator
        animator.startAnimation()
    }

    private func freezePreview() {
        let visible = preview?.layer.presentation()?.frame
        snapAnimator?.stopAnimation(true)
        snapAnimator = nil
        if let visible {
            preview?.frame = visible
            previewTargetFrame = visible
        }
    }

    private func makeFloatingActions(in window: UIWindow) {
        let bar = UIStackView()
        bar.axis = .horizontal
        bar.spacing = 0
        bar.distribution = .fillEqually
        bar.backgroundColor = surfaceColor
        bar.layer.cornerRadius = 10
        bar.layer.borderWidth = 1
        bar.layer.borderColor = outlineColor.cgColor
        bar.layer.shadowColor = UIColor.black.cgColor
        bar.layer.shadowOpacity = 0.15
        bar.layer.shadowRadius = 4
        bar.layer.shadowOffset = CGSize(width: 0, height: 2)
        for (editing, key) in [(true, "occurrence_adjust"), (false, "occurrence_delete")] {
            let button = UIButton(type: .system)
            var configuration = UIButton.Configuration.plain()
            configuration.title = L10n.t(key)
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14)
            configuration.baseForegroundColor = editing ? primaryColor : errorColor
            configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                var result = attributes
                result.font = .systemFont(ofSize: 12, weight: .semibold)
                return result
            }
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
        bar.isHidden = false
        positionActions()
        bar.alpha = 0
        bar.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0.15 : 0.3,
            delay: 0, usingSpringWithDamping: 0.86, initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction], animations: {
                bar.alpha = 1
                bar.transform = .identity
            })
    }

    private func updateFloatingColors() {
        preview?.topHandle.subviews.first?.backgroundColor = primaryColor
        preview?.bottomHandle.subviews.first?.backgroundColor = primaryColor
        for case let button as UIButton in actions?.arrangedSubviews ?? [] {
            var configuration = button.configuration
            configuration?.baseForegroundColor = button.accessibilityIdentifier == "course_float_edit" ? primaryColor : errorColor
            button.configuration = configuration
        }
    }

    private func positionActions() {
        guard let window, let preview, let actions else { return }
        let width = min(max(actions.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).width, 180), window.bounds.width - 32)
        actions.frame = CGRect(x: min(max(preview.frame.midX - width / 2, 16), window.bounds.width - width - 16),
            y: max(window.safeAreaInsets.top, preview.frame.minY - 38), width: width, height: 34)
    }

    private func releaseFloating() {
        guard let source = drag?.source else { finishDrag(commit: false); return }
        guard movedSincePickup else { settleFloating(); return }
        updateLocation(allowPaging: false)
        guard let destination = target else { returnToOrigin(); return }
        if week != source.displayWeek || destination.day != source.displayDay
            || destination.node != source.renderedCourse.startNode
            || currentRange?.step != source.renderedCourse.step {
            finishDrag(commit: true)
        } else {
            finishDrag(commit: false)
        }
    }

    private func settleFloating() {
        timer?.invalidate()
        timer = nil
        paging = .init()
        drag?.projection = nil
        drag?.edgeFeedback = .init()
        drag?.isHolding = false
        drag?.isDragging = false
        movedSincePickup = false
        actions?.isHidden = false
        preview?.topHandle.isHidden = false
        preview?.bottomHandle.isHidden = false
    }

    @objc private func dismissFloating(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended, drag?.awaitingConfirmation != true else { return }
        if spanChanged, let range = currentRange { finishDrag(commit: true, resized: range) }
        else { finishDrag(commit: false) }
    }

    @objc private func moveFloating(_ recognizer: UIPanGestureRecognizer) {
        guard drag?.source != nil, let preview, drag?.awaitingConfirmation != true else { return }
        switch recognizer.state {
        case .began:
            freezePreview()
            let translation = recognizer.translation(in: window)
            let point = recognizer.location(in: window)
            let down = CGPoint(x: point.x - translation.x, y: point.y - translation.y)
            movementAnchor = (down, preview.frame, down.y - preview.frame.minY)
            latestPoint = point
            beginMovement()
            if let window { lockScrolling(at: recognizer.location(in: window), in: window) }
        case .changed, .ended:
            let point = recognizer.location(in: window)
            if let previous = latestPoint, abs(point.y - previous.y) > 0.5 {
                lastVerticalDirection = point.y > previous.y ? 1 : -1
            }
            latestPoint = point
            updateLocation()
            if recognizer.state == .ended { releaseFloating() }
        case .cancelled, .failed: returnToOrigin()
        default: break
        }
    }

    @objc private func resizeFloating(_ recognizer: UIPanGestureRecognizer) {
        guard let grid = drag?.grids[week], let currentRange,
              let preview, drag?.awaitingConfirmation != true else { return }
        let top = recognizer.view?.tag == 0
        switch recognizer.state {
        case .began:
            freezePreview()
            drag?.isHolding = true
            resizeOrigin = (currentRange, top ? preview.frame.minY : preview.frame.maxY)
            actions?.isHidden = true
            timer?.invalidate()
            timer = nil
        case .changed, .ended:
            guard let origin = resizeOrigin else { return }
            let rows = grid.rows.map { QuickAddRow(node: $0.node,
                top: grid.frame.minY + $0.top, bottom: grid.frame.minY + $0.bottom) }
            let position = origin.edge + recognizer.translation(in: window).y
            let range = CourseFloatResizePolicy.resized(origin.range, top: top, position: position, rows: rows)
            guard let first = rows.first(where: { $0.node == range.startNode }),
                  let last = rows.first(where: { $0.node == range.endNode }) else { return }
            self.currentRange = range
            let frame = CGRect(x: preview.frame.minX, y: first.top, width: preview.frame.width,
                height: max(last.bottom - first.top, 12))
            placePreview(at: frame, animated: true)
            preview.topHandle.accessibilityValue = String(range.startNode)
            preview.bottomHandle.accessibilityValue = String(range.endNode)
            if recognizer.state == .ended {
                resizeOrigin = nil
                settleFloating()
            }
        case .cancelled, .failed:
            if let origin = resizeOrigin { self.currentRange = origin.range }
            resizeOrigin = nil
            returnToOrigin()
        default: break
        }
    }

    private func adjustFloating(top: Bool, by delta: Int) {
        guard let original = currentRange, let grid = drag?.grids[week] else { return }
        let node = (top ? original.startNode : original.endNode) + delta
        let rows = grid.rows.map { QuickAddRow(node: $0.node, top: $0.top, bottom: $0.bottom) }
        guard let row = rows.first(where: { $0.node == node }) else { return }
        let range = CourseFloatResizePolicy.resized(original, top: top,
            position: top ? row.top : row.bottom, rows: rows)
        guard range != original, let preview,
              let first = rows.first(where: { $0.node == range.startNode }),
              let last = rows.first(where: { $0.node == range.endNode }) else { return }
        currentRange = range
        placePreview(at: CGRect(x: preview.frame.minX, y: grid.frame.minY + first.top,
            width: preview.frame.width, height: last.bottom - first.top), animated: true)
        preview.topHandle.accessibilityValue = String(range.startNode)
        preview.bottomHandle.accessibilityValue = String(range.endNode)
    }

    private var spanChanged: Bool {
        guard let source = drag?.source, let range = currentRange else { return false }
        return range.startNode != source.renderedCourse.startNode
            || range.step != source.renderedCourse.step
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
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in self?.updateLocation(scrollAutomatically: true) }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func updateLocation(allowPaging: Bool = true, scrollAutomatically: Bool = false) {
        guard enabled, let token = activeToken, let point = latestPoint, let window,
              let drag, drag.sessionToken === token, let source = drag.source else {
            finishDrag(commit: false)
            return
        }
        let local = convert(point, from: window)
        let global = convert(local, to: nil)
        let viewport = convert(bounds, to: nil)
        guard let anchor = movementAnchor else { return }
        let origin = convert(anchor.point, from: nil)
        let initialCenter = convert(CGPoint(x: anchor.frame.midX, y: anchor.point.y), from: nil).x
        let centerX = initialCenter + local.x - origin.x
        let direction = CourseDragEdgePaging.direction(centerX: centerX, fingerX: local.x,
                                                       originX: initialCenter, width: bounds.width,
                                                       minimumX: bounds.minX)
        let now = ProcessInfo.processInfo.systemUptime
        if allowPaging, let next = paging.update(direction: direction, now: now,
                                    week: week, maxWeek: maxWeek,
                                    destinationReady: drag.grids[week + direction] != nil) {
            traceCourseDrag("page from=\(week) to=\(next) direction=\(direction)")
            if let new = drag.scrollViews[next]?.view {
                if !lockedScrollViews.contains(where: { $0.0 === new }) {
                    lockedScrollViews.append((new, new.isScrollEnabled))
                    new.isScrollEnabled = false
                }
                let priorOffset = drag.scrollViews[week]?.view?.contentOffset.y ?? new.contentOffset.y
                let offset = min(max(priorOffset, -new.adjustedContentInset.top),
                    max(-new.adjustedContentInset.top, new.contentSize.height - new.bounds.height + new.adjustedContentInset.bottom))
                let delta = offset - new.contentOffset.y
                new.setContentOffset(CGPoint(x: new.contentOffset.x, y: offset), animated: false)
                if var grid = drag.grids[next] { grid.frame.origin.y -= delta; drag.grids[next] = grid }
            }
            week = next
            target = nil
            drag.projection = nil
            onChangeWeek(next)
            UISelectionFeedbackGenerator().selectionChanged()
        }
        let feedback = paging.feedback(direction: direction, now: now, week: week, maxWeek: maxWeek)
        if drag.edgeFeedback != feedback { drag.edgeFeedback = feedback }
        if scrollAutomatically { autoScroll(at: point) }
        target = nil
        targetStartTime = nil
        let pointerInViewport = allowPaging ? bounds.contains(local)
            : local.y >= bounds.minY && local.y < bounds.maxY
        if (direction == 0 || !allowPaging), pointerInViewport, let measuredGrid = drag.grids[week], let table,
           table.id == source.course.tableId {
            let grid = measuredGrid.positioned(in: viewport)
            let targetPoint = CGPoint(x: convert(CGPoint(x: centerX, y: local.y), to: nil).x, y: global.y)
            if let candidate = grid.target(at: targetPoint, step: max(currentRange?.step ?? source.renderedCourse.step, 1),
                grabOffsetY: anchor.snapOffsetY, viewport: viewport, edgeDirection: direction,
                clampHorizontal: !allowPaging) {
                target = candidate
            }
        }
        if drag.projection != target?.rect { drag.projection = target?.rect }
        updatePreview()
    }

    private func autoScroll(at point: CGPoint) {
        guard let scroll = drag?.scrollViews[week]?.view, let window, let preview else { return }
        let viewport = scroll.convert(scroll.bounds, to: window).intersection(convert(bounds, to: window))
        guard viewport.height > 0 else { return }
        let zone = min(48, viewport.height / 3)
        guard let anchor = movementAnchor else { return }
        let freeTop = anchor.frame.minY + point.y - anchor.point.y
        let topOverflow = max(0, viewport.minY + zone - freeTop)
        let bottomOverflow = max(0, freeTop + (previewTargetFrame?.height ?? preview.bounds.height) - viewport.maxY + zone)
        let direction: Int
        if topOverflow > 0 && bottomOverflow > 0 {
            direction = lastVerticalDirection != 0 ? lastVerticalDirection
                : (bottomOverflow == topOverflow ? 0 : (bottomOverflow > topOverflow ? 1 : -1))
        } else { direction = topOverflow > 0 ? -1 : (bottomOverflow > 0 ? 1 : 0) }
        guard direction != 0 else { return }
        let overflow = direction < 0 ? topOverflow : bottomOverflow
        let delta = CGFloat(direction) * (3 + 11 * min(1, overflow / max(zone, 1)))
        let minimum = -scroll.adjustedContentInset.top
        let maximum = max(minimum, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
        let offset = min(max(scroll.contentOffset.y + delta, minimum), maximum)
        let consumed = offset - scroll.contentOffset.y
        guard consumed != 0 else { return }
        scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: offset), animated: false)
        if var grid = drag?.grids[week] { grid.frame.origin.y -= consumed; drag?.grids[week] = grid }
    }

    private func finishDrag(commit: Bool, resized: QuickAddRange? = nil) {
        guard let token = activeToken else { return }
        if commit {
            guard let context = drag, context.sessionToken === token,
                  let source = context.source, !context.awaitingConfirmation else { return }
            if resized == nil { updateLocation(allowPaging: false) }
            guard let day = resized?.day ?? target?.day,
                  let node = resized?.startNode ?? target?.node else { returnToOrigin(); return }
            confirmationIsResize = resized != nil
            // Keep the card at the proposed slot until the user decides. A failed
            // or cancelled write returns the same session to its lifted state.
            if let destination = target?.rect, resized == nil { placePreview(at: destination, animated: true) }
            settleFloating()
            actions?.isHidden = true
            preview?.isUserInteractionEnabled = false
            context.awaitingConfirmation = true
            let accepted = onMove(source, week, day, node, resized == nil ? targetStartTime : nil,
                resized?.step ?? currentRange?.step, resized != nil)
            if !accepted { resolveConfirmation(saved: false) }
            return
        }
        activeToken = nil
        stopTracking()
        freezePreview()
        restoreScrolling()
        let oldPreview = preview
        let oldActions = actions
        preview = nil
        actions = nil
        resizeOrigin = nil
        movementAnchor = nil
        currentRange = nil
        sourceFrame = nil
        previewTargetFrame = nil
        if drag?.sessionToken === token { drag?.end() }
        UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.15,
            animations: { oldPreview?.alpha = 0; oldActions?.alpha = 0 },
            completion: { _ in oldPreview?.removeFromSuperview(); oldActions?.removeFromSuperview() })
    }

    private func resolveConfirmation(saved: Bool) {
        guard drag?.awaitingConfirmation == true else { return }
        drag?.awaitingConfirmation = false
        preview?.isUserInteractionEnabled = true
        if saved {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            finishDrag(commit: false)
        } else {
            returnToOrigin(revertSpan: confirmationIsResize)
        }
    }

    private func returnToOrigin(revertSpan: Bool = false) {
        guard let source = drag?.source, let original = sourceFrame else { finishDrag(commit: false); return }
        if revertSpan {
            currentRange = QuickAddRange(day: source.displayDay, startNode: source.renderedCourse.startNode,
                endNode: source.renderedCourse.startNode + source.renderedCourse.step - 1)
        }
        settleFloating()
        target = nil
        var destination = original
        if let range = currentRange, let grid = drag?.grids[week]?.positioned(in: convert(bounds, to: nil)),
           let column = grid.days.firstIndex(of: source.displayDay),
           let first = grid.rows.first(where: { $0.node == range.startNode }),
           let last = grid.rows.first(where: { $0.node == range.endNode }) {
            destination = CGRect(x: grid.frame.minX + grid.timeWidth + grid.gap
                + CGFloat(column) * (grid.columnWidth + grid.gap),
                y: grid.frame.minY + first.top, width: grid.columnWidth, height: last.bottom - first.top)
        }
        freezePreview()
        previewTargetFrame = destination
        let animator = UIViewPropertyAnimator(duration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.35,
            dampingRatio: 0.86) { [weak self] in
                self?.preview?.frame = destination
                self?.preview?.layoutIfNeeded()
                self?.positionActions()
            }
        snapAnimator = animator
        animator.startAnimation()
        preview?.topHandle.accessibilityValue = currentRange.map { String($0.startNode) }
        preview?.bottomHandle.accessibilityValue = currentRange.map { String($0.endNode) }
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
