import SwiftUI
import UIKit

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
    }
    var source: Source?
    @Published var projection: CGRect?
    var provider: NSItemProvider?
    var sessionToken: NSObject?
    var grids: [Int: CourseDropGrid] = [:]
    struct Card {
        let course: CourseEntity
        let week: Int
        let frame: CGRect
    }
    var cards: [UUID: Card] = [:]

    func begin(_ course: CourseEntity, week: Int, frame: CGRect, touch: CGPoint?,
               table: TimeTableEntity, allCourses: [CourseEntity],
               transfers: [HolidayTransferEntry]) -> NSItemProvider? {
        guard course.tableId == table.id,
               let original = allCourses.first(where: { $0.id == course.id && $0.tableId == table.id }),
               let occurrence = CourseOccurrenceIdentity.resolve(course: original, startDate: table.startDate, maxWeek: table.maxWeek,
                   displayWeek: week, displayDay: course.day, transfers: transfers),
               occurrence.matches(original, startDate: table.startDate) else { return nil }
        let started = ProcessInfo.processInfo.systemUptime
        // 本地身份由 localContext 校验；惰性数据表示避免起拖时同步初始化文本转换服务。
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: "public.data", visibility: .ownProcess) { completion in
            completion(Data(), nil)
            return nil
        }
        traceCourseDrag("provider elapsed=\(ProcessInfo.processInfo.systemUptime - started)")
        self.provider = provider
        sessionToken = NSObject()
        let origin = touch ?? CGPoint(x: frame.midX, y: frame.midY)
        let sourceRowTop = grids[week].flatMap { grid in
            grid.rows.first(where: { $0.node == course.startNode }).map { grid.frame.minY + $0.top }
        } ?? frame.minY
        source = Source(course: original, renderedCourse: course, displayWeek: week, displayDay: course.day,
                        occurrence: occurrence, origin: origin,
                        grabOffsetY: max(0, min(frame.height, origin.y - frame.minY)),
                        snapOffsetY: origin.y - sourceRowTop)
        if projection != nil { projection = nil }
        traceCourseDrag("begin frame=\(frame) touch=\(String(describing: touch)) elapsed=\(ProcessInfo.processInfo.systemUptime - started)")
        return provider
    }

    func end() {
        traceCourseDrag("context end")
        source = nil
        if projection != nil { projection = nil }
        provider = nil
        sessionToken = nil
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
        let endIndex = Int(span.1.rounded())
        let subtract = span.1 == Double(endIndex) && endIndex > 0
            ? timeRows[endIndex - 1].gapAfter : rowGap
        return CGRect(x: column.minX, y: frame.minY + y(span.0), width: column.width,
                      height: max(y(span.1) - y(span.0), rowHeight * 0.3) - subtract)
    }
}

/// 背景探针只安装 drop interaction，不吃点击、滚动或系统长按拖动手势。
struct NativeCourseDropTarget: UIViewRepresentable {
    let drag: CourseDragContext
    let week: Int
    let maxWeek: Int
    let table: TimeTableEntity?
    let allCourses: [CourseEntity]
    let transfers: [HolidayTransferEntry]
    let enabled: Bool
    let onChangeWeek: (Int) -> Void
    let onMove: (CourseDragContext.Source, Int, Int, Int, String?) -> Bool

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
        view.enabled = enabled
        view.onChangeWeek = onChangeWeek
        view.onMove = onMove
        view.attach()
    }

    static func dismantleUIView(_ view: CourseDropTargetView, coordinator: ()) {
        view.detach()
    }
}

final class CourseDropTargetView: UIView, UIDropInteractionDelegate, UIDragInteractionDelegate {
    var drag: CourseDragContext?
    var week = 1
    var maxWeek = 20
    var table: TimeTableEntity?
    var allCourses: [CourseEntity] = []
    var transfers: [HolidayTransferEntry] = []
    var enabled = true {
        didSet {
            if oldValue != enabled { sourceInteraction?.isEnabled = enabled }
        }
    }
    var onChangeWeek: (Int) -> Void = { _ in }
    var onMove: (CourseDragContext.Source, Int, Int, Int, String?) -> Bool = { _, _, _, _, _ in false }
    private weak var host: UIView?
    private var interaction: UIDropInteraction?
    private var sourceInteraction: UIDragInteraction?
    private var sourceFrame: CGRect?
    private weak var session: UIDropSession?
    private var timer: Timer?
    private var paging = CourseDragEdgePaging()
    private var target: (day: Int, node: Int, rect: CGRect)?
    private var targetStartTime: String?
    private var previousWindowSize = CGSize.zero

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = window?.bounds.size ?? .zero
        if previousWindowSize != .zero, size != previousWindowSize {
            stopTracking()
            drag?.end()
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
        let interaction = UIDropInteraction(delegate: self)
        parent.addInteraction(interaction)
        self.interaction = interaction
        let sourceInteraction = UIDragInteraction(delegate: self)
        sourceInteraction.isEnabled = enabled
        parent.addInteraction(sourceInteraction)
        self.sourceInteraction = sourceInteraction
        host = parent
        var ancestors: [String] = []
        var ancestor: UIView? = parent
        while let view = ancestor {
            ancestors.append("\(type(of: view)) \(view.frame)")
            ancestor = view.superview
        }
        traceCourseDrag("attach \(ancestors.joined(separator: " > "))")
    }

    func detach() {
        traceCourseDrag("detach")
        stopTracking()
        if let interaction { host?.removeInteraction(interaction) }
        if let sourceInteraction { host?.removeInteraction(sourceInteraction) }
        interaction = nil
        sourceInteraction = nil
        host = nil
    }

    func dragInteraction(_ interaction: UIDragInteraction, itemsForBeginning session: UIDragSession) -> [UIDragItem] {
        guard let window else { return [] }
        traceCourseDrag("source requested enabled=\(enabled) cards=\(drag?.cards.count ?? 0) point=\(session.location(in: self)) windowPoint=\(session.location(in: window)) bounds=\(bounds) modal=\(String(describing: window.rootViewController?.presentedViewController)) cardFrames=\(drag?.cards.values.map { $0.frame } ?? [])")
        guard enabled, let drag,
               window.rootViewController?.presentedViewController == nil,
               bounds.contains(session.location(in: self)) else { return [] }
        // Interaction 挂在 hosting view 后，UIKit 已提供正确的窗口坐标。
        let point = session.location(in: window)
        guard let table,
              let card = drag.cards.values.first(where: { $0.week == week && $0.frame.contains(point) }),
              let provider = drag.begin(card.course, week: card.week, frame: card.frame, touch: point,
                  table: table, allCourses: allCourses, transfers: transfers) else { return [] }
        sourceFrame = card.frame
        session.localContext = drag.sessionToken
        return [UIDragItem(itemProvider: provider)]
    }

    func dragInteraction(_ interaction: UIDragInteraction, previewForLifting item: UIDragItem,
                         session: UIDragSession) -> UITargetedDragPreview? {
        traceCourseDrag("preview requested")
        let started = ProcessInfo.processInfo.systemUptime
        defer { traceCourseDrag("preview elapsed=\(ProcessInfo.processInfo.systemUptime - started)") }
        guard let window, let frame = sourceFrame,
              let snapshot = window.resizableSnapshotView(from: frame, afterScreenUpdates: false,
                                                          withCapInsets: .zero) else { return nil }
        let parameters = UIDragPreviewParameters()
        parameters.backgroundColor = .clear
        parameters.visiblePath = UIBezierPath(roundedRect: CGRect(origin: .zero, size: frame.size), cornerRadius: 10)
        return UITargetedDragPreview(view: snapshot, parameters: parameters,
            target: UIDragPreviewTarget(container: window, center: CGPoint(x: frame.midX, y: frame.midY)))
    }

    func dragInteraction(_ interaction: UIDragInteraction, sessionIsRestrictedToDraggingApplication session: UIDragSession) -> Bool { true }

    func dragInteraction(_ interaction: UIDragInteraction, sessionWillBegin session: UIDragSession) {
        traceCourseDrag("session will begin")
    }

    func dragInteraction(_ interaction: UIDragInteraction, previewForCancelling item: UIDragItem,
                         withDefault defaultPreview: UITargetedDragPreview) -> UITargetedDragPreview? {
        guard let window, let drag, let source = drag.source, source.displayWeek == week,
               let card = drag.cards.values.first(where: {
                   $0.week == week && $0.course.id == source.course.id
                       && $0.course.tableId == source.course.tableId && $0.course.day == source.displayDay
               })
        else { return nil }
        return defaultPreview.retargetedPreview(with: UIDragPreviewTarget(container: window,
            center: CGPoint(x: card.frame.midX, y: card.frame.midY)))
    }

    func dragInteraction(_ interaction: UIDragInteraction, session: UIDragSession, didEndWith operation: UIDropOperation) {
        traceCourseDrag("session ended operation=\(operation.rawValue)")
        stopTracking()
        sourceFrame = nil
        drag?.end()
    }

    func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
        traceCourseDrag("drop offered local=\(session.localDragSession != nil) items=\(session.items.count)")
        // UIKit 可复制 itemProvider；localContext 保留本进程本会话的不可伪造身份。
        guard session.items.count == 1, let token = drag?.sessionToken,
              let localToken = session.localDragSession?.localContext as? NSObject else { return false }
        let accepted = localToken === token
        traceCourseDrag("canHandle identity=\(accepted)")
        return accepted
    }

    func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnter session: UIDropSession) {
        traceCourseDrag("enter bounds=\(bounds)")
        guard dropInteraction(interaction, canHandle: session) else { return }
        startTracking(session)
        updateLocation()
    }

    func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
        traceCourseDrag("update entered moveAllowed=\(session.allowsMoveOperation)")
        guard dropInteraction(interaction, canHandle: session) else { return UIDropProposal(operation: .cancel) }
        startTracking(session)
        updateLocation()
        let operation: UIDropOperation = target == nil ? .forbidden : .move
        traceCourseDrag("proposal=\(operation.rawValue)")
        return UIDropProposal(operation: operation)
    }

    private func startTracking(_ session: UIDropSession) {
        self.session = session
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in self?.updateLocation() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func updateLocation(allowPaging: Bool = true) {
        guard enabled, let session, let drag, let source = drag.source, window != nil else {
            traceCourseDrag("location unavailable session=\(session != nil) drag=\(drag != nil) source=\(drag?.source != nil) window=\(window != nil)")
            stopTracking()
            return
        }
        let local = session.location(in: self)
        let global = convert(local, to: nil)
        let viewport = convert(bounds, to: nil)
        let origin = convert(source.origin, from: nil)
        let direction = CourseDragEdgePaging.direction(at: local, origin: origin, bounds: bounds)
        if allowPaging, let next = paging.update(direction: direction, now: ProcessInfo.processInfo.systemUptime,
                                    week: week, maxWeek: maxWeek) {
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
        traceCourseDrag("location local=\(local) global=\(global) grids=\(drag.grids.mapValues { $0.frame }) target=\(String(describing: target))")
    }

    func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
        guard dropInteraction(interaction, canHandle: session) else { return }
        timer?.invalidate()
        timer = nil
        // 立即松手也使用本次 performDrop 的 session，不依赖前一轮 timer/update 的弱引用。
        self.session = session
        updateLocation(allowPaging: false)
        traceCourseDrag("drop week=\(week) target=\(String(describing: target)) grids=\(drag?.grids.keys.sorted() ?? [])")
        if let source = drag?.source, let target {
            let success = onMove(source, week, target.day, target.node, targetStartTime)
            traceCourseDrag("move sourceWeek=\(source.occurrence.week) targetWeek=\(week) day=\(target.day) node=\(target.node) success=\(success)")
            UINotificationFeedbackGenerator().notificationOccurred(success ? .success : .error)
        }
        stopTracking()
        drag?.end()
    }

    func dropInteraction(_ interaction: UIDropInteraction, sessionDidExit session: UIDropSession) {
        traceCourseDrag("drop exit")
        stopTracking()
    }

    func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnd session: UIDropSession) {
        traceCourseDrag("drop end")
        stopTracking()
        drag?.end()
    }

    private func stopTracking() {
        timer?.invalidate()
        timer = nil
        session = nil
        paging = CourseDragEdgePaging()
        target = nil
        targetStartTime = nil
        if drag?.projection != nil { drag?.projection = nil }
    }
}
