import Foundation
import CoreGraphics

enum CourseDragMovePrompt: Equatable { case change, destination, hidden, outgoing, conflicts }
enum CourseDragMoveChoice { case confirm, direct, cancel }
enum CourseDragMoveAdvance: Equatable { case awaitingApproval, saved, failed, canceled }

struct CourseDragMoveRequest: Identifiable {
    let id = UUID()
    let source: CourseDragContext.Source
    let targetWeek: Int
    let displayDay: Int
    let targetNode: Int
    let targetStep: Int?
    let table: TimeTableEntity
    let courses: [CourseEntity]
    let transfers: [HolidayTransferEntry]
    var resizeOnly = false
    var prompt: CourseDragMovePrompt = .change
    var replacement: CourseEntity?
    var conflicts: [String] = []

    var confirmationTitle: String {
        switch prompt {
        case .change: return L10n.t(isResizeOnly ? "occurrence_span_confirm_title" : "occurrence_move_confirm_title")
        case .destination: return L10n.t("occurrence_destination_title")
        case .hidden: return L10n.t("occurrence_hidden_title")
        case .outgoing: return L10n.t("occurrence_outgoing_title")
        case .conflicts: return L10n.t("conflict_detail_title")
        }
    }

    var isResizeOnly: Bool {
        resizeOnly
    }

    var confirmationMessage: String {
        let selectedDate = targetDate.map(HolidayTransferOps.dayKey) ?? ""
        switch prompt {
        case .destination, .hidden:
            let sourceDate = transfers.last { HolidayTransferOps.dayKey($0.targetDate) == selectedDate }?.sourceDate
            return L10n.format(prompt == .destination ? "occurrence_destination_message" : "occurrence_hidden_message",
                               source.course.courseName, selectedDate, sourceDate.map(HolidayTransferOps.dayKey) ?? "")
        case .outgoing:
            let target = transfers.last { HolidayTransferOps.dayKey($0.sourceDate) == selectedDate }?.targetDate
            return L10n.format("occurrence_outgoing_message", source.course.courseName, selectedDate,
                               target.map(HolidayTransferOps.dayKey) ?? L10n.t("occurrence_transfer_day"))
        case .conflicts: return conflicts.joined(separator: "\n")
        case .change: break
        }
        let crossWeek = source.displayWeek != targetWeek
        func label(week: Int, day: Int, node: Int, step: Int) -> String {
            let span = "\(DateUtils.localizedDay(day)) \(L10n.format("course_node_format", "\(node)-\(node + step - 1)"))"
            return crossWeek ? "\(L10n.format("schedule_current_week", week)) · \(span)" : span
        }
        return L10n.format("occurrence_change_confirm_message", source.course.courseName,
            label(week: source.displayWeek, day: source.displayDay,
                  node: source.renderedCourse.startNode, step: source.renderedCourse.step),
            label(week: targetWeek, day: displayDay, node: targetNode,
                  step: targetStep ?? source.renderedCourse.step))
    }

    var targetDate: Date? {
        CourseOccurrences.date(startDate: table.startDate, week: targetWeek, day: displayDay)
    }

    var confirmationAction: String {
        switch prompt {
        case .change: return L10n.t("ok")
        case .destination: return L10n.t("occurrence_follow_transfer")
        case .hidden: return L10n.t("occurrence_direct_anyway")
        case .outgoing: return L10n.t("occurrence_continue")
        case .conflicts: return L10n.t("conflict_detail_save_anyway")
        }
    }

    var confirmationIsDestructive: Bool { prompt == .hidden || prompt == .conflicts }
}

/// 单调时钟驱动的边缘驻留；每满 500ms 翻一周，换边/离开重新计时。
struct CourseDragEdgePaging {
    private var heldDirection = 0
    private var startedAt: TimeInterval = 0

    func feedback(direction: Int, now: TimeInterval, week: Int, maxWeek: Int) -> CourseDragEdgeFeedback {
        guard direction != 0 else { return .init() }
        let target = min(max(week + direction, 1), max(1, maxWeek))
        let blocked = target == week
        let progress = blocked ? 1 : (heldDirection == direction ? min(max((now - startedAt) / 0.5, 0), 1) : 0)
        return .init(direction: direction, progress: progress, blocked: blocked, targetWeek: target)
    }

    mutating func update(direction: Int, now: TimeInterval, week: Int, maxWeek: Int,
                         destinationReady: Bool = true) -> Int? {
        guard direction != 0, (1...max(1, maxWeek)).contains(week + direction) else {
            heldDirection = 0
            return nil
        }
        guard heldDirection == direction else {
            heldDirection = direction
            startedAt = now
            return nil
        }
        // Missing layout must not consume a page or reset the stationary dwell.
        guard now - startedAt >= 0.5, destinationReady else { return nil }
        startedAt = now
        return week + direction
    }

    static func direction(at point: CGPoint, origin: CGPoint, bounds: CGRect) -> Int {
        guard bounds.contains(point) else { return 0 }
        return direction(centerX: point.x, fingerX: point.x, originX: origin.x,
                         width: bounds.width, minimumX: bounds.minX)
    }

    /// The farther-out pointer or card center activates paging; card boundaries do not.
    static func direction(centerX: CGFloat, fingerX: CGFloat?, originX: CGFloat,
                          width: CGFloat, minimumX: CGFloat = 0) -> Int {
        guard abs(centerX - originX) >= 8 else { return 0 }
        let pointer = fingerX ?? centerX
        if min(pointer, centerX) < minimumX + 10 { return -1 }
        if max(pointer, centerX) > minimumX + width - 10 { return 1 }
        return 0
    }
}

struct CourseDragEdgeFeedback: Equatable {
    var direction = 0
    var progress: Double = 0
    var blocked = false
    var targetWeek = 1

    var opacity: Double {
        guard progress > 0 else { return 0 }
        return blocked ? 0.35 : max(0, (progress - 0.35) / 0.65)
    }
    var scale: CGFloat { blocked ? 1 : 1.1 - 0.1 * progress }
}

enum CourseFloatResizePolicy {
    /// Floating existing courses may span every consecutive visible node,
    /// including edge periods. Quick-add's edge-period single-slot rule is separate.
    static func resized(_ range: QuickAddRange, top: Bool, position: CGFloat,
                        rows: [QuickAddRow]) -> QuickAddRange {
        let nodes = Set(rows.map(\.node))
        guard nodes.contains(range.startNode), nodes.contains(range.endNode) else { return range }
        var first = range.startNode
        var last = range.endNode
        while first > 1 && nodes.contains(first - 1) { first -= 1 }
        while last < (nodes.max() ?? last) && nodes.contains(last + 1) { last += 1 }
        let candidates = rows.filter {
            $0.node >= (top ? first : range.startNode) && $0.node <= (top ? range.endNode : last)
        }
        guard let nearest = candidates.min(by: {
            abs((top ? $0.top : $0.bottom) - position) < abs((top ? $1.top : $1.bottom) - position)
        }) else { return range }
        return QuickAddRange(day: range.day, startNode: top ? nearest.node : range.startNode,
            endNode: top ? range.endNode : nearest.node)
    }
}

struct CourseDropGrid: Equatable {
    struct Row: Equatable {
        let node: Int
        let top: CGFloat
        let bottom: CGFloat
    }
    struct TimeRow: Equatable {
        let node: Int
        let startMinute: Int
        let endMinute: Int
        let top: CGFloat
        let height: CGFloat
        let gapAfter: CGFloat
    }
    var frame: CGRect
    let days: [Int]
    let timeWidth: CGFloat
    let columnWidth: CGFloat
    let gap: CGFloat
    let rows: [Row]
    var timeRows: [TimeRow] = []
    var rowHeight: CGFloat = 52
    var rowGap: CGFloat = 4
    var candidateLayout: CourseDropCandidateLayout? = nil

    /// CardsGridView 的水平 padding 对称；TabView 过渡只影响 X，保留该周实测 Y/行高。
    /// 不借用源周的网格，否则不同周的自定义时间占位行会被误当作目标节次。
    func positioned(in viewport: CGRect) -> CourseDropGrid {
        var positioned = self
        positioned.frame.origin.x = viewport.midX - frame.width / 2
        return positioned
    }

    /// 拖动时只在真实列带吸附；松手时横向无条件钳到可见首/末列。
    /// 卡中心可在屏外（偏边抓取），纵向越出网格或跨度越末节仍不接受。
    func target(at point: CGPoint, step: Int, grabOffsetY: CGFloat = 0,
                viewport: CGRect, edgeDirection: Int,
                clampHorizontal: Bool = false) -> (day: Int, node: Int, rect: CGRect)? {
        guard !days.isEmpty, point.y >= viewport.minY, point.y < viewport.maxY else { return nil }
        var point = point
        if clampHorizontal {
            let firstCenter = frame.minX + timeWidth + gap + columnWidth / 2
            let lastCenter = firstCenter + CGFloat(days.count - 1) * (columnWidth + gap)
            point.x = min(max(point.x, firstCenter), lastCenter)
        } else if !viewport.contains(point) {
            return nil
        } else if edgeDirection == -1, point.x < viewport.minX + 10 {
            point.x = frame.minX + timeWidth + gap + columnWidth / 2
        } else if edgeDirection == 1, point.x > viewport.maxX - 10 {
            point.x = frame.minX + timeWidth + gap
                + CGFloat(days.count - 1) * (columnWidth + gap) + columnWidth / 2
        }
        return target(at: point, step: step, grabOffsetY: grabOffsetY)
    }

    func candidateTimedProjection(source: CourseEntity, sourceOccurrence: CourseOccurrenceIdentity, day: Int,
                                  destination: CourseOccurrenceDestination, column: CGRect) -> CGRect? {
        guard let candidateLayout,
              let layout = candidateLayout.layout(source: source, sourceOccurrence: sourceOccurrence,
                                                   day: day, destination: destination),
              let first = layout.renderPlan.slots.first, let last = layout.renderPlan.slots.last,
              let start = TimeTableUtils.hmToSeconds(destination.startTime),
              let end = TimeTableUtils.hmToSeconds(destination.endTime),
              start >= first.startMinutes * 60, end <= last.endMinutes * 60,
              let bounds = layout.timedCardBounds(start: destination.startTime, end: destination.endTime)
        else { return nil }
        return CGRect(x: column.minX, y: frame.minY + bounds.top,
                      width: column.width, height: bounds.height)
    }

    func target(at point: CGPoint, step: Int, grabOffsetY: CGFloat = 0) -> (day: Int, node: Int, rect: CGRect)? {
        let local = CGPoint(x: point.x - frame.minX, y: point.y - frame.minY)
        let firstX = timeWidth + gap
        guard step > 0, frame.contains(point), columnWidth > 0,
              local.x >= firstX,
              local.x < firstX + CGFloat(days.count) * (columnWidth + gap) else { return nil }
        let index = Int((local.x - firstX) / (columnWidth + gap))
        guard days.indices.contains(index),
              let start = rows.min(by: { abs($0.top - (local.y - grabOffsetY)) < abs($1.top - (local.y - grabOffsetY)) }),
              start.node <= Int.max - (step - 1),
              let end = rows.first(where: { $0.node == start.node + step - 1 }),
              (start.node...end.node).allSatisfy(Set(rows.map(\.node)).contains) else { return nil }
        let rect = CGRect(x: frame.minX + firstX + CGFloat(index) * (columnWidth + gap),
                          y: frame.minY + start.top, width: columnWidth,
                          height: end.bottom - start.top)
        return (days[index], start.node, rect)
    }
}

/// 真实网格和候选共用纵向几何，包含占位展开、自适应/手动行高和长课间。
struct CourseGridRowLayout {
    struct Configuration: Equatable {
        var contentScale: CGFloat = 1
        var verticalScale: CGFloat = 1
        var adaptive = false
        var availableGridHeight: CGFloat = 0
        var longBreakSpacing = false
        var fontScale: CGFloat = 1
        var expandedPlaceholders: Set<String> = []
        var placeholderTextHeight: CGFloat = 19
    }
    let renderPlan: TimeTableUtils.RenderSlotPlan
    let baseRowHeight: CGFloat
    let rowHeight: CGFloat
    let rowGap: CGFloat
    let weights: [CGFloat]
    let mealBreakAfterRows: Set<Int>
    let mealGapExtra: CGFloat

    init(courses: [CourseEntity], timeJson: String, baseSlots: [TimeSlot], configuration: Configuration) {
        let plan = timeJson.isEmpty ? TimeTableUtils.RenderSlotPlan(slots: baseSlots)
            : TimeTableUtils.buildRenderSlotPlan(courses: courses, timeJson: timeJson, baseSlots: baseSlots)
        self.init(renderPlan: plan, courses: courses, timeJson: timeJson, configuration: configuration)
    }

    init(renderPlan: TimeTableUtils.RenderSlotPlan, courses: [CourseEntity], timeJson: String,
         configuration c: Configuration) {
        self.renderPlan = renderPlan
        let base = TimetableViewportPolicy.baseRowHeightDp(adaptive: c.adaptive,
            fitRowHeightDp: TimetableViewportPolicy.fitRowHeightDp(
                availableGridHeightDp: c.availableGridHeight,
                slotWeights: renderPlan.slotWeights.map { $0.map { CGFloat($0) } },
                slotCount: renderPlan.slots.count, contentScale: c.contentScale),
            contentScale: c.contentScale)
        baseRowHeight = base
        let clampedScale = min(max(c.contentScale, 0.7), 1.3)
        let height = TimetableViewportPolicy.manualRowHeightDp(baseRowHeightDp: base,
            verticalScale: c.verticalScale,
            minRowHeightDp: TimetableViewportPolicy.MIN_ROW_DP * clampedScale,
            maxRowHeightDp: TimetableViewportPolicy.MAX_ROW_DP * clampedScale)
        rowHeight = height
        rowGap = TimetableViewportPolicy.ROW_GAP_DP * c.contentScale
        weights = renderPlan.slotWeights.map { baseWeights in
            baseWeights.enumerated().map { index, weight in
                let slot = renderPlan.slots[index]
                if slot.isPlaceholder, c.expandedPlaceholders.contains(slot.timeString) {
                    return max(CGFloat(weight), TimeTableUtils.placeholderExpandedWeight(
                        rowHeightDp: height, gapDp: TimetableViewportPolicy.ROW_GAP_DP,
                        requiredTextHeightDp: c.placeholderTextHeight))
                }
                return CGFloat(weight)
            }
        } ?? Array(repeating: 1, count: renderPlan.slots.count)
        mealBreakAfterRows = c.longBreakSpacing && !timeJson.isEmpty
            ? MealBreakDetector.detectDisplayRowIndexes(timeJson: timeJson, courses: courses,
                displayedNodeEnds: renderPlan.slots.map(\.nodeEnd)) : []
        mealGapExtra = c.longBreakSpacing ? 24 * c.contentScale * c.fontScale : 0
    }

    func yOfRows(_ row: Double) -> CGFloat {
        let full = Int(min(max(row, 0), Double(weights.count)))
        var total = weights.prefix(full).reduce(0, +)
        if full < weights.count && row > Double(full) { total += weights[full] * CGFloat(row - Double(full)) }
        let crossedBreaks = mealBreakAfterRows.filter { Double($0 + 1) <= row }.count
        return rowHeight * total + mealGapExtra * CGFloat(crossedBreaks)
    }
    func rowHeightAt(_ index: Int) -> CGFloat {
        rowHeight * (weights.indices.contains(index) ? weights[index] : 1)
    }
    func gapAfterRow(_ index: Int) -> CGFloat {
        rowGap + (mealBreakAfterRows.contains(index) ? mealGapExtra : 0)
    }
    /// Placeholder rows affect geometry, but never count as course periods.
    static func standardRowRange(startNode: Int, step: Int, slots: [TimeSlot]) -> Range<Int>? {
        guard let first = slots.firstIndex(where: { !$0.isPlaceholder && $0.nodeStart == startNode }) else { return nil }
        let (endNode, overflow) = startNode.addingReportingOverflow(max(step, 1) - 1)
        guard !overflow else { return nil }
        let last = slots.indices.last(where: {
            $0 >= first && !slots[$0].isPlaceholder && slots[$0].nodeStart <= endNode
        }) ?? first
        return first..<(last + 1)
    }

    static func standardCardBounds(startNode: Int, step: Int, slots: [TimeSlot],
                                   yOfRows: (Double) -> CGFloat, gapAfterRow: (Int) -> CGFloat)
        -> (top: CGFloat, height: CGFloat)? {
        guard let rows = standardRowRange(startNode: startNode, step: step, slots: slots) else { return nil }
        let top = yOfRows(Double(rows.lowerBound))
        return (top, yOfRows(Double(rows.upperBound)) - top - gapAfterRow(rows.upperBound - 1))
    }

    static func timedCardBounds(fraction: (Double, Double), rowHeight: CGFloat, rowGap: CGFloat,
                               yOfRows: (Double) -> CGFloat, gapAfterRow: (Int) -> CGFloat)
        -> (top: CGFloat, height: CGFloat) {
        let endRow = Int(fraction.1.rounded())
        let trailingGap = fraction.1 == Double(endRow) && fraction.1 > 0 ? gapAfterRow(endRow - 1) : rowGap
        let naturalSpan = yOfRows(fraction.1) - yOfRows(fraction.0) - (trailingGap - rowGap)
        return (yOfRows(fraction.0), max(naturalSpan, rowHeight * 0.3) - rowGap)
    }
    func timedCardBounds(start: String, end: String) -> (top: CGFloat, height: CGFloat)? {
        guard let fraction = TimeTableUtils.timeToFractionalRows(start, end, slots: renderPlan.slots) else { return nil }
        return Self.timedCardBounds(fraction: fraction, rowHeight: rowHeight, rowGap: rowGap,
                                   yOfRows: yOfRows, gapAfterRow: gapAfterRow)
    }
}

/// 候选先在原始课程上模拟一次移动，再走真实逐日渲染；不按投影 id 删除整页。
struct CourseDropCandidateLayout: Equatable {
    let week: Int
    let courses: [CourseEntity]
    let timeJson: String
    let baseSlots: [TimeSlot]
    let configuration: CourseGridRowLayout.Configuration
    let startDate: String
    let maxWeek: Int
    var transfers: [HolidayTransferEntry] = []
    var allCourses: [CourseEntity] = []
    var timeSlots: [TimeSlot]? = nil
    var visibleDays: Set<Int> = Set(1...7)
    var autoHideEmptyEvening = false
    var eveningStartMinutes = TimetableViewportPolicy.EVENING_START_MINUTES

    struct Snapshot {
        let allCourses: [CourseEntity]
        let courses: [CourseEntity]
        let targetOccurrence: CourseOccurrenceIdentity
    }

    func snapshot(source: CourseEntity, sourceOccurrence: CourseOccurrenceIdentity, day: Int,
                  destination: CourseOccurrenceDestination) -> Snapshot? {
        guard maxWeek > 0, sourceOccurrence.week >= 1, sourceOccurrence.week <= maxWeek,
              let original = allCourses.first(where: { $0.id == source.id && $0.tableId == source.tableId }),
              original.startWeek >= 1, original.endWeek >= original.startWeek,
              (0...3).contains(original.type), original.step > 0,
               sourceOccurrence.matches(original, startDate: startDate),
               let target = CourseOccurrenceIdentity.destination(course: original, startDate: startDate, maxWeek: maxWeek,
                  displayWeek: week, displayDay: day, transfers: transfers) else { return nil }
        var semester = allCourses.filter { !($0.id == original.id && $0.tableId == original.tableId) }
        // 保留两侧的真实区间；原周只去掉一次，单双周仍由 inWeek 判定。
        for (first, last) in [(original.startWeek, sourceOccurrence.week - 1),
                              (sourceOccurrence.week + 1, original.endWeek)] where original.fixedDate == nil && first <= last {
            var remaining = original
            remaining.startWeek = first
            remaining.endWeek = last
            if remaining.inWeek(first) || (first < last && remaining.inWeek(first + 1)) {
                semester.append(remaining)
            }
        }
        var moved = original
        moved.startWeek = target.week
        moved.endWeek = target.week
        moved.type = 0
        moved.day = target.day
        if original.fixedDate != nil {
            guard let date = CourseOccurrences.date(startDate: startDate, week: target.week, day: target.day) else { return nil }
            moved.fixedDate = HolidayTransferOps.dayKey(date)
        }
        moved.startNode = destination.startNode
        moved.isIrregularNode = false
        if destination.usesOwnTime {
            moved.startTime = destination.startTime
            moved.endTime = destination.endTime
        }
        semester.append(moved)
        let table = TimeTableEntity(name: "", startDate: startDate, maxWeek: maxWeek)
        return Snapshot(allCourses: semester,
            courses: renderCoursesForWeek(table, week: week, courses: semester,
                                           transfers: transfers, timeJson: timeJson), targetOccurrence: target)
    }

    func layout(source: CourseEntity, sourceOccurrence: CourseOccurrenceIdentity, day: Int,
                destination: CourseOccurrenceDestination) -> CourseGridRowLayout? {
        guard let next = snapshot(source: source, sourceOccurrence: sourceOccurrence, day: day,
                                  destination: destination) else { return nil }
        let slots = Self.visibleBaseSlots(allCourses: next.allCourses, timeSlots: timeSlots ?? baseSlots,
            visibleDays: visibleDays, timeJson: timeJson, autoHideEmptyEvening: autoHideEmptyEvening,
            eveningStartMinutes: eveningStartMinutes)
        return CourseGridRowLayout(courses: next.courses, timeJson: timeJson, baseSlots: slots, configuration: configuration)
    }

    static func visibleBaseSlots(allCourses: [CourseEntity], timeSlots: [TimeSlot], visibleDays: Set<Int>,
                                 timeJson: String, autoHideEmptyEvening: Bool,
                                 eveningStartMinutes: Int) -> [TimeSlot] {
        guard autoHideEmptyEvening else { return timeSlots }
        let selected = TimetableViewportPolicy.selectVisibleSlots(allCourses: allCourses,
            timeSlots: timeSlots.map(TimetableViewportPolicy.SlotRef.init), visibleDays: visibleDays,
            timeJson: timeJson.isEmpty ? nil : timeJson, autoHideEmptyEvening: true,
            eveningStartMinutes: eveningStartMinutes)
        return selected.slots.compactMap { ref in timeSlots.first { $0.nodeStart == ref.nodeStart } }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.week == rhs.week && lhs.startDate == rhs.startDate && lhs.maxWeek == rhs.maxWeek
            && lhs.transfers == rhs.transfers && lhs.timeJson == rhs.timeJson && lhs.configuration == rhs.configuration
            && lhs.visibleDays == rhs.visibleDays && lhs.autoHideEmptyEvening == rhs.autoHideEmptyEvening
            && lhs.eveningStartMinutes == rhs.eveningStartMinutes
            && equalSlots(lhs.baseSlots, rhs.baseSlots)
            && equalSlots(lhs.timeSlots ?? lhs.baseSlots, rhs.timeSlots ?? rhs.baseSlots)
            && equalCourses(lhs.courses, rhs.courses) && equalCourses(lhs.allCourses, rhs.allCourses)
    }
    private static func equalSlots(_ lhs: [TimeSlot], _ rhs: [TimeSlot]) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy {
            $0.label == $1.label && $0.nodeStart == $1.nodeStart
                && $0.startMinutes == $1.startMinutes && $0.endMinutes == $1.endMinutes
        }
    }
    private static func equalCourses(_ lhs: [CourseEntity], _ rhs: [CourseEntity]) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy {
            $0.id == $1.id && $0.tableId == $1.tableId && $0.day == $1.day && $0.startNode == $1.startNode && $0.step == $1.step
                && $0.startWeek == $1.startWeek && $0.endWeek == $1.endWeek && $0.type == $1.type
                && $0.ownTime == $1.ownTime && $0.isIrregularTime == $1.isIrregularTime
                && $0.isIrregularNode == $1.isIrregularNode
                && $0.startTime == $1.startTime && $0.endTime == $1.endTime
        }
    }
}
