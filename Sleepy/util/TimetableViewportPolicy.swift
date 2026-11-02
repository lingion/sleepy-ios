// TimetableViewportPolicy.swift — ← util/TimetableViewportPolicy.kt 逐行翻译 (GPL-3.0)
// 卡片课程表的纯布局策略。刻意不依赖 SwiftUI/Kotlin-Compose,
// 让自适应行高最关键的部分可用单测验证。
// 平台适配: Android 直接引用 ui.component.TimeSlot; iOS 端 CourseTableView.TimeSlot
// 定义在 app-only 文件(widget extension 不编译 ui/), 本策略自带同构 SlotRef
// (node + 起止分钟), 调用方用 TimeTableUtils.renderSlots(timeJson).map(Self.ref) 映射。

import Foundation

enum TimetableViewportPolicy {
    static let DEFAULT_ROW_DP: CGFloat = 56
    /// 原固定行高 (issue#8 时代 d(52f)) — 实验室自适应关闭时的基座
    static let FIXED_ROW_DP: CGFloat = 52
    static let MIN_ROW_DP: CGFloat = 36
    static let MAX_ROW_DP: CGFloat = 96
    /// 网格行间 gap(与 CourseTableView gapH = 4dp×scale 同值), 占位行几何检测用。
    static let ROW_GAP_DP: CGFloat = 4
    static let VERTICAL_GESTURE_THRESHOLD_DP: CGFloat = 8
    static let VERTICAL_DOMINANCE_RATIO: CGFloat = 1.25
    /// 18:00 当日分钟数(Kotlin LocalTime.of(18,0) 比较域)
    static let EVENING_START_MINUTES = 18 * 60

    /// 策略自有槽位引用(node + 起止分钟) ← TimeSlot 同构投影
    struct SlotRef {
        let nodeStart: Int
        let startMinutes: Int
        let endMinutes: Int
    }

    /// TimeSlot → SlotRef 映射(UI 层调用; app target 有 TimeSlot 定义处可直接用)
    static func ref(from slot: SlotRef) -> SlotRef { slot }

    /// 用户自定义晚间起始 "HH:mm"; 解析失败回退 18:00 (2026-09-16: 不再机械 18:00)
    static func parseEveningStart(_ raw: String?) -> Int {
        raw.flatMap { TimeTableUtils.hmMinutes($0) } ?? EVENING_START_MINUTES
    }

    struct VisibleSlots {
        var slots: [SlotRef]
        var hiddenEveningCount: Int = 0
    }

    /**
     * 仅当整学期没有与晚间相交的课时, 隐藏 18:00 及之后开始的尾部槽位。
     * 畸形/不可解析的课程保留完整课表(安全回退)。
     */
    static func selectVisibleSlots(
        allCourses: [CourseEntity],
        timeSlots: [SlotRef],
        visibleDays: Set<Int>,
        timeJson: String?,
        autoHideEmptyEvening: Bool,
        eveningStartMinutes: Int = EVENING_START_MINUTES
    ) -> VisibleSlots {
        if !autoHideEmptyEvening || timeSlots.isEmpty { return VisibleSlots(slots: timeSlots) }

        let firstEvening = timeSlots.firstIndex { $0.startMinutes >= eveningStartMinutes }
        guard let firstEvening else { return VisibleSlots(slots: timeSlots) }

        let relevantCourses = allCourses.filter { visibleDays.contains($0.day) }
        let hasUnknownCourse = relevantCourses.contains { courseInterval($0, timeSlots, timeJson) == nil }
        if hasUnknownCourse { return VisibleSlots(slots: timeSlots) }

        let hasEveningCourse = relevantCourses.contains { course in
            guard let interval = courseInterval(course, timeSlots, timeJson) else { return false }
            return interval.1 > eveningStartMinutes
        }
        if hasEveningCourse { return VisibleSlots(slots: timeSlots) }

        return VisibleSlots(
            slots: Array(timeSlots.prefix(firstEvening)),
            hiddenEveningCount: timeSlots.count - firstEvening
        )
    }

    /// 计算可读的拟合行高, 不允许短课表过度膨胀。
    static func fitRowHeightDp(
        availableGridHeightDp: CGFloat,
        slotWeights: [CGFloat]?,
        slotCount: Int,
        contentScale: CGFloat
    ) -> CGFloat {
        let safeScale = min(max(contentScale, 0.7), 1.3)
        let minRow = MIN_ROW_DP * safeScale
        let defaultRow = DEFAULT_ROW_DP * safeScale
        let totalWeight: CGFloat
        if let w = slotWeights, !w.isEmpty {
            totalWeight = max(w.reduce(0, +), 1)
        } else {
            totalWeight = CGFloat(max(slotCount, 1))
        }
        return min(max(availableGridHeightDp / totalWeight, minRow), defaultRow)
    }

    /// 行高基座 (2026-09-16 用户令): 实验室自适应开=拟合高度; 默认关=原固定 52dp×scale
    static func baseRowHeightDp(adaptive: Bool, fitRowHeightDp: CGFloat, contentScale: CGFloat) -> CGFloat {
        adaptive ? fitRowHeightDp : FIXED_ROW_DP * min(max(contentScale, 0.7), 1.3)
    }

    /// 手动行高 = 基座×手势缩放, 夹在可读上下限内 (缩放可 <1: 允许捏小)
    static func manualRowHeightDp(
        baseRowHeightDp: CGFloat, verticalScale: CGFloat,
        minRowHeightDp: CGFloat, maxRowHeightDp: CGFloat
    ) -> CGFloat {
        min(max(baseRowHeightDp * verticalScale, minRowHeightDp), maxRowHeightDp)
    }

    /**
     * 长课间薄带卡高 (2026-10-17 #105→#183 回归定位): 卡片高度 = natural 跨度 − 普通行隙,
     * **带厚永远不进卡高** — 带只存在于 yOfRows 坐标层 (悬浮在锚行卡底与下行卡顶之间)。
     * 旧 bug = cardH 减 gapAfterRow(=gapH+带) 而 cardY 走 yOfRows(已加带), 同一带厚双扣,
     * 锚行胶囊回缩一个带厚。签名无带参数 = 该错误口径不可表达。
     * minSpanDp: ownTime 比例卡保底 (0.3 标准行, 防过短课塌缩到不可点)。
     * v1.0.62 B5b: ← TimetableViewportPolicy.kt longBreakCardHeightDp
     * (iOS 不折权 — expandWeightsForLongBreaks 不移植, 只需带厚不进卡高口径)。
     */
    static func longBreakCardHeightDp(naturalSpanDp: CGFloat, gapDp: CGFloat, minSpanDp: CGFloat = 0) -> CGFloat {
        max(naturalSpanDp, minSpanDp) - gapDp
    }

    /// 仅当双指手势有明确纵向意图时为 true。
    static func locksVerticalResize(
        startVerticalSpan: CGFloat, currentVerticalSpan: CGFloat,
        startHorizontalSpan: CGFloat, currentHorizontalSpan: CGFloat,
        thresholdDp: CGFloat = VERTICAL_GESTURE_THRESHOLD_DP,
        dominanceRatio: CGFloat = VERTICAL_DOMINANCE_RATIO
    ) -> Bool {
        let verticalDelta = abs(currentVerticalSpan - startVerticalSpan)
        let horizontalDelta = abs(currentHorizontalSpan - startHorizontalSpan)
        return verticalDelta >= thresholdDp && verticalDelta >= horizontalDelta * dominanceRatio
    }

    static func rowHeightFromVerticalSpan(
        startRowHeightDp: CGFloat, startVerticalSpan: CGFloat, currentVerticalSpan: CGFloat,
        minRowHeightDp: CGFloat, maxRowHeightDp: CGFloat
    ) -> CGFloat {
        if startVerticalSpan <= 0 { return min(max(startRowHeightDp, minRowHeightDp), maxRowHeightDp) }
        let ratio = max(currentVerticalSpan / startVerticalSpan, 0.1)
        return min(max(startRowHeightDp * ratio, minRowHeightDp), maxRowHeightDp)
    }

    private static func courseInterval(
        _ course: CourseEntity,
        _ timeSlots: [SlotRef],
        _ timeJson: String?
    ) -> (Int, Int)? {  // (startMinutes, endMinutes)
        let mapped = timeJson.flatMap {
            TimeTableUtils.courseTimeParts(
                courseStartNode: course.startNode, courseStep: course.step, timeJson: $0,
                ownTime: course.ownTime, startTime: course.startTime, endTime: course.endTime)
        }
        let parts: (String, String)?
        if let mapped {
            parts = mapped
        } else {
            let endNode = course.startNode + max(course.step, 1) - 1
            guard let first = timeSlots.first(where: { $0.nodeStart == course.startNode }),
                  let last = timeSlots.first(where: { $0.nodeStart == endNode }) else { return nil }
            parts = (String(format: "%02d:%02d", first.startMinutes / 60, first.startMinutes % 60),
                     String(format: "%02d:%02d", last.endMinutes / 60, last.endMinutes % 60))
        }
        guard let p = parts, let start = TimeTableUtils.hmMinutes(p.0), let end = TimeTableUtils.hmMinutes(p.1),
              end > start else { return nil }
        return (start, end)
    }
}
