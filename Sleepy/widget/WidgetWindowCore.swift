// WidgetWindowCore.swift — ← widget/core/FixedWindowCore.kt + TodayRowGeometry.kt
//   + 各 Receiver.compute*Window 的「固定窗口」纯计算 (无 UI, 可单测)。
//
// 平台差异 (对齐任务项 1): Android 用 RemoteViews + 固定高度窗口 + 底部真实导航条,
// iOS 用 WidgetKit SwiftUI 自适应布局 —— 但「同一屏只放得下 N 行, 溢出折成 +N」是
// **行为语义**, 与平台无关, 故窗口数学原样移植, 渲染换成 SwiftUI。
//
// 档位 (对齐任务项 9 / Android 74140535 十三变体三档): Android 的 S/M/L 由
// res/xml 的 minWidth/minHeight 决定 (S=2×2 minHeight 110dp · Wide/M=4×2 160dp ·
// L=4×4 250dp); iOS 对应 systemSmall / systemMedium / systemLarge。基准高沿用 Android
// 真机档位, 保证两端「同一档能显示几节课」一致。

import Foundation
import WidgetKit

// MARK: - 档位

/// 小组件排版档位 S/M/L ← Android 13-variant 三档收敛 (74140535)
enum WidgetLayoutTier: Int, CaseIterable {
    case small
    case medium
    case large

    /// Android 各档基准容器高 (dp) ← res/xml 放置尺寸 (74140535): S=2×2 110 · M=4×2 160 · L=4×4 250。
    /// 仅作兜底: 真机上容器高由 GeometryReader 实测 (等价 Android 从 launcher 拿到的 hDp)。
    var baseHeightDp: CGFloat {
        switch self {
        case .small: return 110
        case .medium: return 160
        case .large: return 250
        }
    }

    /// iOS family → 档位。Android 的 "Wide"(4×2) 在 iOS 即 systemMedium;
    /// systemExtraLarge 归入 L (与 Android 4×4 同档语义)。
    init(family: WidgetFamily) {
        if family == .systemSmall {
            self = .small
        } else if family == .systemMedium {
            self = .medium
        } else {
            self = .large
        }
    }
}

// MARK: - 行几何 (← TodayRowGeometry.kt v8 + 2026-09-14d 密度回调)

struct WidgetRowSpan {
    let rowIndex: Int
    let row: ConflictLayoutEngine.WeekLaneRow
    let topDp: CGFloat
    let bottomDp: CGFloat
}

enum WidgetRowGeometry {
    static let rowH: CGFloat = 30
    static let rowGap: CGFloat = 4
    static let stackGap: CGFloat = 3
    static let padTop: CGFloat = 10
    static let headerAdvance: CGFloat = 20
    static let padBottom: CGFloat = 14
    /// 底部条高 ← NAV_BAR_H_DP (iOS 上这条只承载「+N」胶囊, 无导航按钮)
    static let navBarH: CGFloat = 28

    // TwoDay 列内行几何 (← renderTwoDayRegular: 行 36 / 行距 6 / 同栏堆叠距 3)
    static let twoDayRowH: CGFloat = 36
    static let twoDayRowGap: CGFloat = 6
    /// 列可用高扣减 ← pad 12 + 列标题 20 + pad 12 (顶部标签行已由 2dbad515 删除)
    static let twoDayColumnDeduction: CGFloat = 44

    // WeekList 列内行几何 (← renderWeekListRegular: 行 19 / 行距 0 / 页脚 19)
    static let weekListRowH: CGFloat = 19
    static let weekListRowGap: CGFloat = 0
    static let weekListFooterH: CGFloat = 19
    /// 列可用高扣减 ← pad 12 + 列标题 16 + pad 12 + 底部 18
    static let weekListDeduction: CGFloat = 58

    /// 内容顶: 位图内已画表头 → 只留 padTop; 表头是真实视图 → 额外让出表头高
    static func contentTopDp(headerSpace: Bool) -> CGFloat {
        headerSpace ? padTop : padTop + headerAdvance
    }

    /// 行高: 单行 = rowH; 冲突行 = 同栏最多张数 × rowH + (张数−1) × stackGap
    /// (Today rowH 30 / TwoDay 36 / WeekList 19 — 同一段数学,只是基数不同)
    static func rowHeightDp(_ row: ConflictLayoutEngine.WeekLaneRow,
                            rowH: CGFloat = WidgetRowGeometry.rowH,
                            stackGap: CGFloat = WidgetRowGeometry.stackGap) -> CGFloat {
        guard row.laneCount > 1 else { return rowH }
        var byLane: [Int: Int] = [:]
        for course in row.courses {
            let lane = row.laneOf[course.id] ?? 0
            byLane[lane, default: 0] += 1
        }
        let maxStack = byLane.values.max() ?? 1
        return CGFloat(maxStack) * rowH + CGFloat(max(maxStack - 1, 0)) * stackGap
    }

    /// 行序列 + 纵向占位 ← rowSpans (重叠链分簇用 timeJson, 对齐 Android 25c943f0)
    static func rowSpans(courses: [CourseEntity], headerSpace: Bool, timeJson: String?) -> [WidgetRowSpan] {
        let rows = ConflictLayoutEngine.weekLaneRows(courses, timeJson: timeJson)
        guard !rows.isEmpty else { return [] }
        var y = contentTopDp(headerSpace: headerSpace)
        var out: [WidgetRowSpan] = []
        for (i, row) in rows.enumerated() {
            let h = rowHeightDp(row)
            out.append(WidgetRowSpan(rowIndex: i, row: row, topDp: y, bottomDp: y + h))
            y += h + rowGap
        }
        return out
    }

    /// 整块内容高: 末行底 + 下内边距; 空内容 = 内容顶 + 下内边距
    static func contentHeightDp(courses: [CourseEntity], headerSpace: Bool, timeJson: String?) -> CGFloat {
        guard let last = rowSpans(courses: courses, headerSpace: headerSpace, timeJson: timeJson).last else {
            return contentTopDp(headerSpace: headerSpace) + padBottom
        }
        return last.bottomDp + padBottom
    }
}

// MARK: - 固定窗口 (← FixedWindowCore.kt)

enum WidgetWindowCore {
    /// 页脚预留高 ← FOOTER_H_DP (行高 30 + 行距 10 的一半)
    static let footerHDp: CGFloat = 20

    enum Mode {
        /// 时间窗: 锚定当前进行中的行, 已过窗口顶 (今天列)
        case timeWindow
        /// 从头截断 (明天列 / 非今天)
        case head
    }

    enum Status {
        case none
        /// 今天全部上完: 正文空, 只由底部「+0」胶囊标记结束 (← ab27230c)
        case allDone
    }

    struct WindowEntry {
        let row: ConflictLayoutEngine.WeekLaneRow
        let heightDp: CGFloat
        let startMin: Int?
        let endMin: Int?
    }

    struct WindowResult {
        let visible: [WindowEntry]
        /// 是否给底部「+N」胶囊留位
        let footer: Bool
        /// 窗口之后被折起的课程总节数
        let hiddenAheadCourses: Int
        let status: Status
    }

    /// 课程真实起止分钟 ← courseStartEndMin: 节次课按 timeJson 反解真实时间
    static func courseStartEndMin(_ course: CourseEntity, _ timeJson: String?) -> (start: Int, end: Int)? {
        guard let eff = TimeTableUtils.effectiveCourseTime(
            isIrregularTime: course.isIrregularTime || course.ownTime,
            startTime: course.startTime,
            endTime: course.endTime,
            startNode: course.startNode,
            step: course.step,
            timeJson: timeJson ?? ""
        ) else { return nil }
        guard let s = TimeTableUtils.hmMinutes(eff.0),
              let e = TimeTableUtils.hmMinutes(eff.1), e > s else { return nil }
        return (s, e)
    }

    /// 行 → 窗口条目: 行时间 = 行内最早开始 / 最晚结束
    static func entriesOf(
        rows: [ConflictLayoutEngine.WeekLaneRow],
        timeJson: String?,
        heightOf: (ConflictLayoutEngine.WeekLaneRow) -> CGFloat
    ) -> [WindowEntry] {
        rows.map { row in
            var start: Int?
            var end: Int?
            for course in row.courses {
                guard let se = courseStartEndMin(course, timeJson) else { continue }
                start = min(start ?? se.start, se.start)
                end = max(end ?? se.end, se.end)
            }
            return WindowEntry(row: row, heightDp: heightOf(row), startMin: start, endMin: end)
        }
    }

    /// 从锚点起贪心连续装填; forceFirst = 锚点行永远保留 (底部裁切)
    private static func greedy(_ tail: [WindowEntry], _ budget: CGFloat, _ gapDp: CGFloat,
                               forceFirst: Bool) -> [WindowEntry] {
        guard !tail.isEmpty else { return [] }
        if !forceFirst && tail[0].heightDp > budget + 0.01 { return [] }
        var out: [WindowEntry] = []
        var used: CGFloat = 0
        for entry in tail {
            let add = out.isEmpty ? entry.heightDp : gapDp + entry.heightDp
            if out.isEmpty || used + add <= budget + 0.01 {
                out.append(entry)
                used += add
            } else {
                break
            }
        }
        return out
    }

    /// 折起点之后所有行的课程节数之和
    private static func hiddenCourses(_ entries: [WindowEntry], _ fromIndex: Int) -> Int {
        guard fromIndex < entries.count else { return 0 }
        return entries[fromIndex...].reduce(0) { $0 + $1.row.courses.count }
    }

    /// 固定窗口计算 ← FixedWindowCore.window (语义逐条对齐)
    static func window(entries: [WindowEntry], availH: CGFloat, mode: Mode, nowMin: Int?,
                       gapDp: CGFloat = 0, footerH: CGFloat = footerHDp) -> WindowResult {
        guard !entries.isEmpty else {
            return WindowResult(visible: [], footer: false, hiddenAheadCourses: 0, status: .none)
        }

        var anchorIdx = 0
        if mode == .timeWindow, let now = nowMin {
            // 全部结束 → ALL_DONE (即使装得下也成立)
            if entries.allSatisfy({ $0.endMin != nil }),
               let maxEnd = entries.map({ $0.endMin! }).max(), maxEnd < now {
                return WindowResult(visible: [], footer: false, hiddenAheadCourses: 0, status: .allDone)
            }
            if let inProgress = entries.firstIndex(where: {
                guard let s = $0.startMin, let e = $0.endMin else { return false }
                return s <= now && now < e
            }) {
                anchorIdx = inProgress
            } else {
                var best = -1
                var bestStart = Int.max
                for (i, entry) in entries.enumerated() {
                    if let s = entry.startMin, s > now, s < bestStart {
                        bestStart = s
                        best = i
                    }
                }
                anchorIdx = max(best, 0)
            }
        }

        let tail = Array(entries.dropFirst(anchorIdx))
        let full = greedy(tail, availH, gapDp, forceFirst: true)
        if full.count == tail.count {
            return WindowResult(visible: full, footer: false, hiddenAheadCourses: 0, status: .none)
        }
        // footerH<=0 → 填满模式: 底部条不占正文高, 溢出仍报节数
        if footerH <= 0 {
            return WindowResult(visible: full, footer: true,
                                hiddenAheadCourses: hiddenCourses(entries, anchorIdx + full.count), status: .none)
        }
        let withFooter = greedy(tail, availH - footerH, gapDp, forceFirst: false)
        if withFooter.isEmpty {
            return WindowResult(visible: full, footer: false,
                                hiddenAheadCourses: hiddenCourses(entries, anchorIdx + full.count), status: .none)
        }
        return WindowResult(visible: withFooter, footer: true,
                            hiddenAheadCourses: hiddenCourses(entries, anchorIdx + withFooter.count), status: .none)
    }

    /// 「+N」胶囊文案 ← 8c0fcbea 恒画 + ab27230c 结束态画「+0」
    static func capsuleText(hidden: Int) -> String {
        hidden > 0 ? "+\(hidden)" : "+0"
    }
}

// MARK: - 各 widget 的窗口计算 (← Today/TwoDay/WeekList Receiver.compute*Window)
//
// 容器高口径: Android 从 launcher 拿 hDp,iOS 用 GeometryReader 实测同一件事;
// 拿不到实测高 (预览/快照) 时回落 Android res/xml 档高,保证容量口径仍按同档换算。

enum WidgetWindows {
    /// 当日分钟数
    static func nowMinutes(_ date: Date = Date()) -> Int {
        let c = DateUtils.isoCalendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// 实测高兜底: 0/负 (GeometryReader 未布局) → 档位基准高
    static func resolveHeightDp(_ measured: CGFloat, _ tier: WidgetLayoutTier) -> CGFloat {
        measured > 0 ? measured : tier.baseHeightDp
    }

    // MARK: Today 系

    /// Today 系正文可用高 = 容器高 − 顶 pad10 − 表头前进 20 − 底部条 28 (← hDp − 58)
    static func todayAvailH(heightDp: CGFloat, tier: WidgetLayoutTier) -> CGFloat {
        resolveHeightDp(heightDp, tier) - WidgetRowGeometry.contentTopDp(headerSpace: false)
            - WidgetRowGeometry.navBarH
    }

    /// nowMin nil = 非今天 (无时间窗语义) → HEAD 模式
    static func today(courses: [CourseEntity], timeJson: String?, heightDp: CGFloat,
                      tier: WidgetLayoutTier, nowMin: Int?) -> WidgetWindowCore.WindowResult {
        let rows = ConflictLayoutEngine.weekLaneRows(courses, timeJson: timeJson)
        let entries = WidgetWindowCore.entriesOf(rows: rows, timeJson: timeJson) {
            WidgetRowGeometry.rowHeightDp($0)
        }
        return WidgetWindowCore.window(
            entries: entries,
            availH: todayAvailH(heightDp: heightDp, tier: tier),
            mode: nowMin != nil ? .timeWindow : .head,
            nowMin: nowMin,
            gapDp: WidgetRowGeometry.rowGap,
            footerH: 0
        )
    }

    // MARK: TwoDay

    /// TwoDay 列可用高 = 容器高 − (pad12 + 列标题 20 + pad12) (← hDp − 44)
    static func twoDayAvailH(heightDp: CGFloat, tier: WidgetLayoutTier) -> CGFloat {
        resolveHeightDp(heightDp, tier) - WidgetRowGeometry.twoDayColumnDeduction
    }

    /// 每列独立窗口: 今天列 TIME_WINDOW / 明天列 HEAD; 行高 36 (← renderTwoDayRegular maxRowH)
    static func twoDay(days: [DayData], heightDp: CGFloat, tier: WidgetLayoutTier,
                       nowMin: Int?) -> [WidgetWindowCore.WindowResult] {
        let availH = twoDayAvailH(heightDp: heightDp, tier: tier)
        return days.map { day in
            let rows = ConflictLayoutEngine.weekLaneRows(day.courses, timeJson: day.timeJson)
            let entries = WidgetWindowCore.entriesOf(rows: rows, timeJson: day.timeJson) {
                WidgetRowGeometry.rowHeightDp($0, rowH: WidgetRowGeometry.twoDayRowH)
            }
            let useTimeWindow = day.isToday && nowMin != nil
            return WidgetWindowCore.window(
                entries: entries,
                availH: availH,
                mode: useTimeWindow ? .timeWindow : .head,
                nowMin: useTimeWindow ? nowMin : nil,
                gapDp: WidgetRowGeometry.twoDayRowGap
            )
        }
    }

    // MARK: WeekList

    /// WeekList 列可用高 = 容器高 − 固定扣减 − 学期外状态行高 (← hDp − 58 − statusH)
    static func weekListAvailH(heightDp: CGFloat, tier: WidgetLayoutTier, statusH: CGFloat = 0) -> CGFloat {
        resolveHeightDp(heightDp, tier) - WidgetRowGeometry.weekListDeduction - statusH
    }

    /// WeekList 列内一天一行课 (无冲突分栏), 行高 19 / 行距 0 / 页脚预留 19
    static func weekList(days: [DayData], heightDp: CGFloat, tier: WidgetLayoutTier,
                         statusH: CGFloat = 0) -> [WidgetWindowCore.WindowResult] {
        days.map { day in
            let entries = day.courses.map { course in
                WidgetWindowCore.WindowEntry(
                    row: ConflictLayoutEngine.WeekLaneRow(courses: [course], laneOf: [:], laneCount: 1),
                    heightDp: WidgetRowGeometry.weekListRowH, startMin: nil, endMin: nil)
            }
            return WidgetWindowCore.window(
                entries: entries,
                availH: weekListAvailH(heightDp: heightDp, tier: tier, statusH: statusH),
                mode: .head,
                nowMin: nil,
                gapDp: WidgetRowGeometry.weekListRowGap,
                footerH: WidgetRowGeometry.weekListFooterH
            )
        }
    }

    /// WeekList 列内可见课程数 (窗口按「一行一门」装填 → 条目数即课程数)
    static func weekListVisibleCounts(days: [DayData], heightDp: CGFloat, tier: WidgetLayoutTier,
                                      statusH: CGFloat = 0) -> [Int] {
        weekList(days: days, heightDp: heightDp, tier: tier, statusH: statusH).map { $0.visible.count }
    }

    // MARK: WeekView

    /// WeekView 列可用高 = 容器高 − 固定扣减 56 − 状态行高 (← computeWeekViewWindows L170:
    /// availH = hDp − 56 − statusH; 56 = 外pad6×2 + 标题12+14 + chip14+4 + 卡底6)
    static func weekViewAvailH(heightDp: CGFloat, tier: WidgetLayoutTier, statusH: CGFloat = 0) -> CGFloat {
        resolveHeightDp(heightDp, tier) - 56 - statusH
    }

    /// WeekView 逐列 FIXED 窗口 (设计 §4.3, ← computeWeekViewWindows L163-183):
    /// HEAD 模式; heightOf = wrapMax2Lines 行数 × lineH + 3dp 尾 gap (与渲染同源),
    /// 页脚 = lineH + 3; gapDp = 0 (3dp 尾 gap 已含进 heightOf)。
    static func weekView(days: [DayData], heightDp: CGFloat, tier: WidgetLayoutTier,
                         statusH: CGFloat, colW: CGFloat) -> [WidgetWindowCore.WindowResult] {
        let lineH = WidgetTextWrap.lineH
        let maxTextWidth = colW - 8  // textPad 4dp ×2 (Android (colW−8)*density px 同式)
        let useAlias = AppPrefs.shared.isWidgetUseAlias()
        return days.map { day in
            let entries = day.courses.map { course -> WidgetWindowCore.WindowEntry in
                let name = CourseDisplayUtil.displayName(course, useAlias)
                let h = CGFloat(WidgetTextWrap.lineCount(name, maxWidth: maxTextWidth)) * lineH + 3
                return WidgetWindowCore.WindowEntry(
                    row: ConflictLayoutEngine.WeekLaneRow(courses: [course], laneOf: [:], laneCount: 1),
                    heightDp: h, startMin: nil, endMin: nil)
            }
            return WidgetWindowCore.window(
                entries: entries,
                availH: weekViewAvailH(heightDp: heightDp, tier: tier, statusH: statusH),
                mode: .head,
                nowMin: nil,
                gapDp: 0,
                footerH: lineH + 3
            )
        }
    }

    // MARK: 课程边界刷新 (← WidgetBoundaryScheduler.f7e80c84)

    /// 下一节课边界 = min(end+1 > now), 无则 nil
    static func nextBoundaryMin(_ endMins: [Int], nowMin: Int) -> Int? {
        endMins.map { $0 + 1 }.filter { $0 > nowMin }.min()
    }

    /// 行 end 分钟集合 ← WidgetBoundaryScheduler.rowEndMins (与 FIXED 锚点同源: 冲突行取 max、不可解析剔除)
    static func rowEndMins(courses: [CourseEntity], timeJson: String?) -> [Int] {
        let rows = ConflictLayoutEngine.weekLaneRows(courses, timeJson: timeJson)
        return WidgetWindowCore.entriesOf(rows: rows, timeJson: timeJson) { _ in 0 }
            .compactMap { $0.endMin }
    }

    /// 一天内后续课程边界时刻 (升序, 已过滤过去) ← 行 end+1 逐颗
    static func boundaryDates(courses: [CourseEntity], timeJson: String?, from date: Date) -> [Date] {
        let endMins = rowEndMins(courses: courses, timeJson: timeJson)
        guard !endMins.isEmpty else { return [] }
        let cal = DateUtils.isoCalendar
        let dayStart = cal.startOfDay(for: date)
        var out: [Date] = []
        var cursor = nowMinutes(date)
        while let next = nextBoundaryMin(endMins, nowMin: cursor) {
            guard let at = cal.date(byAdding: .minute, value: next, to: dayStart) else { break }
            if at > date { out.append(at) }
            cursor = next
            if out.count >= 16 { break }
        }
        return out
    }
}
