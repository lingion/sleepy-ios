// CourseTableView.swift — ← ui/component/CourseTableView.kt (1643 行, v1.0.61)
// Cards 网格视图 + FullWeekView(7days) + 公共小组件。
//
// 架构(逐行对齐):
//   BoxWithConstraints → colW(dp) → Column(verticalScroll) → 表头 Row + 固定高 grid Box
//   时间栏/课程卡全用 offset 绝对定位 → 滚动同步。
// 布局常量: headH 52 / gapH 4 / gapW 5; timeW 实测(三行式/老式 dash 轴, 下限 46×scale);
// 行高 = TimetableViewportPolicy (固定基座 52×scale / 实验室自适应拟合 / 双指缩放 36~96)。
// 表头渲染 = PeriodHeaderCellContent(三行式/老式 + 整列统一字号 columnFont + 整列统一
// 中点 columnPlacements + legacy 列级 dash 轴), 与设置页预览同一事实来源。
//
// 平台偏差(有意保留):
//   - Android changeBus 订阅 → iOS 渲染层 body 直读 AppPrefs(兄弟文件同模式)。
//   - Android verticalResizeGesture(pointerInput 双指) → iOS 自定义
//     UIPinchGestureRecognizer 挂到 grid 祖先视图; 手势期间 cancelsTouchesInView=false
//     保点击穿透, 横向主导时与 Pager 并存(Android 直接 consume 屏蔽 pager — 无法 1:1 复刻)。
//   - LocalConfiguration.fontScale → UIFont.body 实测比例近似。
//   - Android selectVisibleSlots 在 List<TimeSlot> 上原位过滤; iOS 策略层用同构
//     SlotRef(无 widget 依赖), 回映按 nodeStart 唯一性取原 TimeSlot。

import SwiftUI
import UIKit

/// 时段定义 — 5 个时段(WakeUp 默认 12 节对应 1-2/3-5/6-7/8-10/11-13) ← TimeSlot
struct TimeSlot {
    let label: String        // "1-2节"
    let startHour: Int
    let startMinute: Int
    let endHour: Int
    let endMinute: Int
    var displayStart: String { String(format: "%02d:%02d", startHour, startMinute) }
    var displayEnd: String { String(format: "%02d:%02d", endHour, endMinute) }
    let nodeStart: Int
    var nodeEnd: Int { nodeStart }  // 派生段(段内多节由调用方展开为单节行)

    var timeString: String { "\(displayStart)-\(displayEnd)" }

    /// 渲染期占位节次(buildRenderSlotPlan 生成的空档): label 空 = 占位行 ← isPlaceholder
    var isPlaceholder: Bool { label.isEmpty }

    var startMinutes: Int { startHour * 60 + startMinute }
    var endMinutes: Int { endHour * 60 + endMinute }
}

// MARK: - TimeTableUtils 渲染槽位扩展(App target 专属 — 依赖 TimeSlot, Widget target 无)
// issue#23 §5: 非常规时间胶囊按真实分钟在网格内按比例定位 + 跨空隙占位节次合成。
extension TimeTableUtils {
    /// timeJson → 渲染槽位表(每节一个 TimeSlot, 按 node 升序) — ← Android timeSlotsFor(timeJson)
    static func renderSlots(timeJson: String) -> [TimeSlot] {
        parseNodes(timeJson).map { n in
            let sc = Calendar.current.dateComponents([.hour, .minute], from: n.start)
            let ec = Calendar.current.dateComponents([.hour, .minute], from: n.end)
            return TimeSlot(label: "\(n.node)", startHour: sc.hour ?? 0, startMinute: sc.minute ?? 0,
                            endHour: ec.hour ?? 0, endMinute: ec.minute ?? 0, nodeStart: n.node)
        }
    }

    /**
     * 把课程起止时间映射到「槽位行坐标」: 1.0 = 一整行, 小数部分 = 该槽位内按时间的比例。
     * 返回 (startFrac, endFrac); 时间不可解析 / 结束≤开始 / 映射退化返回 nil,
     * 调用方应退回整格吸附(timeToNode)。
     *
     * 规则:
     * - 时间落在某槽位 [start, end] 内 → 行下标 + 槽内比例
     * - 落在两槽位空隙 → 归属下一行顶端
     * - 早于首槽位 → 0.0; 晚于末槽位 → 槽位总数(网格底边)
     */
    static func timeToFractionalRows(_ startTime: String, _ endTime: String,
                                     slots: [TimeSlot]) -> (Double, Double)? {
        if slots.isEmpty { return nil }
        guard let st = hmToSeconds(startTime), let et = hmToSeconds(endTime), et > st else { return nil }
        func slotStart(_ s: TimeSlot) -> Int { s.startHour * 3600 + s.startMinute * 60 }
        func slotEnd(_ s: TimeSlot) -> Int { s.endHour * 3600 + s.endMinute * 60 }
        func pos(_ t: Int) -> Double {
            if t <= slotStart(slots[0]) { return 0 }
            if t >= slotEnd(slots[slots.count - 1]) { return Double(slots.count) }
            if let i = slots.firstIndex(where: { t >= slotStart($0) && t <= slotEnd($0) }) {
                let dur = max(slotEnd(slots[i]) - slotStart(slots[i]), 60)
                return Double(i) + Double(t - slotStart(slots[i])) / Double(dur)
            }
            // 空隙: 全部归属下一行顶端
            return Double(slots.firstIndex(where: { slotStart($0) > t }) ?? slots.count)
        }
        let startFrac = pos(st)
        let endFrac = pos(et)
        if endFrac <= startFrac { return nil }
        return (startFrac, endFrac)
    }

    /// 便捷重载: 直接传 timeJson 字符串。
    static func timeToFractionalRows(_ startTime: String, _ endTime: String,
                                     timeJson: String) -> (Double, Double)? {
        timeToFractionalRows(startTime, endTime, slots: renderSlots(timeJson: timeJson))
    }

    // ------------------------------------------------------------------
    // 用户反馈 2026-09-09: 非常规课跨节次空隙的渲染期占位节次合成
    // ------------------------------------------------------------------

    /// 占位行权重可见下限 — 低于它渲染层减 gap/padding 后内容高度 ≤ 0, 时间文字隐形。
    /// 0.36 行 ≈ 56dp × 0.36 = 20dp, 扣 gap 4dp + cell padding 4dp 后剩 ~12dp, 容一行 micro 文字。
    static let PLACEHOLDER_MIN_WEIGHT = 0.36

    /**
     * 用户反馈 2026-09-16: 占位节次**文字适配检测**(纯几何函数, 与 rowHeight/scale 联动)。
     * 行内容区高 = rowHeightDp * rowWeight − gapDp; 放不下 requiredTextHeightDp
     * (= 时间文字行高 11dp + 上下 padding 8dp) → 该占位行渲染为灰块(不显示文字),
     * 点击可展开到正好显示完文字。
     */
    static func placeholderTextFits(rowWeight: CGFloat, rowHeightDp: CGFloat,
                                    gapDp: CGFloat, requiredTextHeightDp: CGFloat) -> Bool {
        rowHeightDp * rowWeight - gapDp >= requiredTextHeightDp
    }

    /**
     * 占位行展开权重 = 正好显示完时间文字((text+gap)/rowHeight)。
     * 展开只增不减(与原权重无关, 调用方保证 max), 且恒 < 1 不占满整行。
     */
    static func placeholderExpandedWeight(rowHeightDp: CGFloat, gapDp: CGFloat,
                                          requiredTextHeightDp: CGFloat) -> CGFloat {
        min((requiredTextHeightDp + gapDp) / max(rowHeightDp, 0.001), 0.99)
    }

    /**
     * 渲染期槽位方案 — 标准槽位 + 按当前课程集合合成的**占位节次**(渲染期产物,
     * 绝不写回 timeJson; 与用户手建边缘节点 insertEdgeNode 机制严格无关)。
     *
     * slotWeights 每行渲染权重 = 该行分钟数 / 左邻标准行分钟数(首行对右邻取基准),
     * nil = 全部标准行(等高)。占位行只有真实分钟占比(如 5/45 ≈ 0.111), 渲染层
     * 按 y = rowH * 加权前缀和 定位 — 用户反馈 2026-09-09: 整行占位把时间轴拉歪。
     */
    struct RenderSlotPlan {
        let slots: [TimeSlot]
        let slotWeights: [Double]?
        init(slots: [TimeSlot], slotWeights: [Double]? = nil) {
            self.slots = slots
            self.slotWeights = slotWeights
        }
    }

    /**
     * 为当前可见课程合成渲染槽位表(纯函数):
     *   1. 非常规课(ownTime)的结束时间**终止在**某节次空隙内(课尾溢出进空隙)时,
     *      该空隙里合成一个占位节次, 范围 = 各溢出课与空隙交集的贪心并包;
     *   2. 无溢出 → 槽位表与 renderSlots(timeJson) 完全一致。
     * 渲染期合成物, 绝不写回 timeJson。
     */
    static func buildRenderSlotPlan(courses: [CourseEntity], timeJson: String) -> RenderSlotPlan {
        buildRenderSlotPlan(courses: courses, timeJson: timeJson,
                            baseSlots: renderSlots(timeJson: timeJson))
    }

    /**
     * Same render-plan construction, but with a caller-selected base slot list.
     * The cards view uses this to apply viewport policies (such as hiding empty
     * evening slots) before synthesising irregular-time placeholder rows.
     * ← Android buildRenderSlotPlan(courses, timeJson, baseSlots)
     */
    static func buildRenderSlotPlan(courses: [CourseEntity], timeJson: String,
                                    baseSlots base: [TimeSlot]) -> RenderSlotPlan {
        if base.isEmpty { return RenderSlotPlan(slots: base) }
        func slotStart(_ s: TimeSlot) -> Int { s.startHour * 3600 + s.startMinute * 60 }
        func slotEnd(_ s: TimeSlot) -> Int { s.endHour * 3600 + s.endMinute * 60 }

        // 空隙下标 → (占位起点, 占位终点)。课的结束时间终止在空隙内 =
        // 课 end ∈ (左节 end, 右节 start] — 无论课从空隙前延伸过来还是整段落在
        // 空隙里, 都需要占位行承载(整段空隙课按比例渲染在占位行内)。
        var placeholderByGap: [Int: (lo: Int, hi: Int)] = [:]
        for c in courses {
            guard c.ownTime else { continue }
            guard let st = hmToSeconds(c.startTime), let et = hmToSeconds(c.endTime), et > st else { continue }
            for gi in 0..<max(base.count - 1, 0) {
                let leftEnd = slotEnd(base[gi])
                let rightStart = slotStart(base[gi + 1])
                if et > leftEnd && et <= rightStart {
                    if let cur = placeholderByGap[gi] {
                        placeholderByGap[gi] = (min(cur.lo, leftEnd), max(cur.hi, et))
                    } else {
                        placeholderByGap[gi] = (leftEnd, et)
                    }
                }
            }
        }
        if placeholderByGap.isEmpty { return RenderSlotPlan(slots: base) }

        var out: [TimeSlot] = []
        var weights: [Double] = []
        for (i, slot) in base.enumerated() {
            out.append(slot)
            weights.append(1)
            if let ph = placeholderByGap[i] {
                out.append(TimeSlot(
                    label: "",
                    startHour: ph.lo / 3600, startMinute: (ph.lo % 3600) / 60,
                    endHour: ph.hi / 3600, endMinute: (ph.hi % 3600) / 60,
                    nodeStart: slot.nodeStart))
                // 占位行权重 = 自身分钟数 / 左邻标准行分钟数 (时间轴按分钟加权, 不占满整行)。
                // 用户报障 2026-09-10: 5 分钟占位 ≈ 0.111 行, 56dp×0.111−gapH−padding ≤ 0,
                // 时间文字挤没 = 时间轴上隐形。下限 = 够渲染一行 micro 时间文字(0.36 行),
                // 行高与 y 前缀和同源, 抬下限后时间轴仍自洽(只是该段略高于真实分钟比例)。
                let gapMin = max(Double(ph.hi - ph.lo) / 60.0, 1)
                let leftMin = max(Double(slotEnd(slot) - slotStart(slot)) / 60.0, 1)
                weights.append(max(gapMin / leftMin, PLACEHOLDER_MIN_WEIGHT))
            }
        }
        return RenderSlotPlan(slots: out, slotWeights: weights)
    }
}

extension TimetableViewportPolicy.SlotRef {
    /// TimeSlot → SlotRef 同构投影 ← Android 策略层直接吃 List<TimeSlot>
    init(_ slot: TimeSlot) {
        self.init(nodeStart: slot.nodeStart, startMinutes: slot.startMinutes, endMinutes: slot.endMinutes)
    }
}

// MARK: - 实验室开关读取(← AppPrefs.swift KEY_GRID_* 正式 getter 组, 已上收)
// 此前 GridLabPrefs 直读 UserDefaults.standard 的临时层已删 — AppPrefs.swift 的
// isGridAdaptiveHeight/isGridAutoHideEmptyEvening/getGridEveningStart/
// isGridShowSeparators/isGridLongBreakSpacing/isGridPinchZoom 即正式归属地。

/// 用户反馈 2026-09-16: 占位行时间文字适配的最小内容区需求 = micro 一行 lineHeight 11dp
/// + SingleTimeHeadCell 上下 padding 8dp。放不下 → 只显示灰块(文字隐藏), 点击展开。
/// ← PLACEHOLDER_TEXT_REQUIRED_DP
let placeholderTextRequiredDp: CGFloat = 19

/// Android LocalConfiguration.fontScale 近似 — UIFontMetrics 动态字号比例。
private var systemFontScaleProxy: CGFloat {
    let base = UIFont.preferredFont(forTextStyle: .body).pointSize
    let standard = UIFont.systemFont(ofSize: 17).pointSize
    guard standard > 0, base.isFinite, base > 0 else { return 1 }
    return max(min(base / standard, 2.0), 0.8)
}

/// 周视图某星期在该页(startDate/currentWeek)的真实日期是否 = 今天
/// ← startDate.isNotBlank() && DateUtils.isDateToday(DateUtils.dateOfWeek(...), todayDate)
private func isDateTodayOfWeek(startDate: String, week: Int, day: Int, todayDate: Date) -> Bool {
    guard !startDate.isEmpty,
          let date = DateUtils.dateOfWeek(startDate: startDate, week: week, dayOfWeek: day) else { return false }
    return DateUtils.isDateToday(date, todayDate)
}

// MARK: - 双指纵向缩放行高 ← Modifier.verticalResizeGesture
// v1.0.56 T3: pinchZoomEnabled=false 时手势不挂(存量缩放值不清)。
// 阈值/主导比/上下限求解全走 TimetableViewportPolicy(与 Android 同一纯函数)。
private final class GridPinchResizeUIView: UIView {
    /// 实验室总开关。开关在页面存活期间被翻成 true(设置页返回/同帧重算)时,
    /// didMoveToWindow 不会再次触发 → 必须即时挂手势, 否则开关"看起来开了但捏不动"。
    /// (← Android `if (pinchZoomEnabled) Modifier.verticalResizeGesture(...) else Modifier`
    ///  每次 recompose 重建 pointerInput, 开关即时生效。)
    var enabled = false { didSet { if oldValue != enabled { syncGesture() } } }
    var baseRowHeightDp: CGFloat = 52
    var currentRowHeightDp: CGFloat = 52
    var contentScale: CGFloat = 1
    var onScaleChange: (CGFloat) -> Void = { _ in }

    private var pinch: UIPinchGestureRecognizer?
    private weak var attachedTo: UIView?
    private var startVerticalSpan: CGFloat?
    private var startHorizontalSpan: CGFloat = 0
    private var startRowHeightDp: CGFloat = 0
    private var locked = false

    override func didMoveToWindow() {
        super.didMoveToWindow()
        syncGesture()
    }

    /// 依据当前 window + enabled 同步识别器挂载状态(幂等)。
    private func syncGesture() {
        if window == nil {
            detachGesture()
            return
        }
        guard enabled, let host = superview else {
            detachGesture()
            return
        }
        if attachedTo === host, pinch != nil { return }
        detachGesture()
        let g = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        g.cancelsTouchesInView = false   // 平台偏差: 不劫持单指点击/滚动
        host.addGestureRecognizer(g)
        attachedTo = host; pinch = g
    }

    private func detachGesture() {
        if let g = pinch { attachedTo?.removeGestureRecognizer(g) }
        pinch = nil; attachedTo = nil
    }

    @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
        guard enabled, g.state == .began || g.state == .changed, g.numberOfTouches >= 2 else {
            startVerticalSpan = nil
            locked = false
            return
        }
        let p0 = g.location(ofTouch: 0, in: self)
        let p1 = g.location(ofTouch: 1, in: self)
        let verticalSpan = abs(p0.y - p1.y)
        let horizontalSpan = abs(p0.x - p1.x)
        if startVerticalSpan == nil {
            startVerticalSpan = max(verticalSpan, 1)
            startHorizontalSpan = horizontalSpan
            startRowHeightDp = currentRowHeightDp
        }
        guard let sv0 = startVerticalSpan else { return }
        if !locked,
           TimetableViewportPolicy.locksVerticalResize(startVerticalSpan: sv0,
                                                       currentVerticalSpan: verticalSpan,
                                                       startHorizontalSpan: startHorizontalSpan,
                                                       currentHorizontalSpan: horizontalSpan) {
            locked = true
        }
        if locked {
            let clampedScale = min(max(contentScale, 0.7), 1.3)
            let next = TimetableViewportPolicy.rowHeightFromVerticalSpan(
                startRowHeightDp: startRowHeightDp,
                startVerticalSpan: sv0,
                currentVerticalSpan: verticalSpan,
                minRowHeightDp: TimetableViewportPolicy.MIN_ROW_DP * clampedScale,
                maxRowHeightDp: TimetableViewportPolicy.MAX_ROW_DP * clampedScale)
            onScaleChange(next / max(baseRowHeightDp, 1))
        }
        // 未锁定且横向明确展开/合拢 → 不改变高度也不接管(Android consume 屏蔽 pager;
        // iOS 靠 Pager 自身手势竞争, 纵向意图未锁定前本识别器不输出)。
    }
}

private struct GridPinchResizer: UIViewRepresentable {
    var enabled: Bool
    var baseRowHeightDp: CGFloat
    var currentRowHeightDp: CGFloat
    var contentScale: CGFloat
    var onScaleChange: (CGFloat) -> Void

    func makeUIView(context: Context) -> GridPinchResizeUIView {
        let v = GridPinchResizeUIView()
        v.backgroundColor = .clear
        v.isUserInteractionEnabled = false   // 本视图不吃触摸, 识别器挂在祖先
        v.enabled = enabled
        v.baseRowHeightDp = baseRowHeightDp
        v.currentRowHeightDp = currentRowHeightDp
        v.contentScale = contentScale
        v.onScaleChange = onScaleChange
        return v
    }

    func updateUIView(_ v: GridPinchResizeUIView, context: Context) {
        v.enabled = enabled
        v.baseRowHeightDp = baseRowHeightDp
        v.currentRowHeightDp = currentRowHeightDp
        v.contentScale = contentScale
        v.onScaleChange = onScaleChange
    }
}

// MARK: - 网格列级表头几何 ← CardsGridView 内 columnFont/columnPlacements/legacyAxis 计算

/// 三行式列级统一字号输入行约束(墨迹包络), UIKit 实测口径与 PeriodHeaderCellContent 渲染同源。
private struct HeaderColumnGeometry {
    let columnFont: PeriodHeaderAdaptiveFont?
    let columnPlacements: [PeriodHeaderPlacement]?
    let legacyAxis: CGFloat?

    /// ← Android CardsGridView BoxWithConstraints 段: columnFont(整列统一字号)/
    /// columnPlacements(整列统一中点)/ legacyAxis(列级 dash 轴)。
    /// headerContentHeightSp = 最矮非占位行内容高(真实行高输入 — 用户令 2026-10-03,
    /// 双指缩行/自适应行高联动;假 52f*scale 输入曾使矮卡字号过大 → 三行行盒互叠)。
    init(renderSlots: [TimeSlot], layout: String, style: String, hanging: CGFloat, showX: Bool,
         scale: CGFloat, rowHeightAt: (Int) -> CGFloat, gapH: CGFloat, rowHeightDp: CGFloat) {
        let padDp = 2 * periodHeaderCardPadDp * scale
        let minRowDp = renderSlots.enumerated()
            .filter { !$0.element.isPlaceholder }
            .map { max(rowHeightAt($0.offset) - gapH, 0) }
            .min() ?? max(rowHeightDp - gapH, 0)
        let headerContentHeightSp = max(minRowDp - padDp, 1)

        let timeFont = UIFont.systemFont(ofSize: 11 * scale)   // ← headerTimeStyle(scale)
        let labelFont = UIFont.systemFont(ofSize: 12 * scale, weight: .semibold) // ← headerLabelStyle(scale)

        func label(of slot: TimeSlot) -> String {
            (showX && slot.nodeStart == slot.nodeEnd)
                ? PeriodHeaderFormatter.fullLabel(slot.nodeStart, style)
                : PeriodHeaderFormatter.range(slot.nodeStart, slot.nodeEnd, style)
        }

        if layout != "three_line" {
            // legacy: 列级 dash 轴 — 几何与 legacyLineWidthDp 同一解(pad 已在列宽, 轴不含 pad)
            columnFont = nil
            columnPlacements = nil
            let rows = renderSlots.filter { !$0.isPlaceholder }.map { slot -> LegacyDashRowInk in
                LegacyDashRowInk(
                    labelPx: textWidth(label(of: slot), font: labelFont),
                    timeLeftPx: textWidth(slot.displayStart, font: timeFont),
                    dashPx: textWidth("-", font: timeFont),
                    timeRightPx: textWidth(slot.displayEnd, font: timeFont))
            }
            legacyAxis = legacyDashColumnPx(rows: rows, padPx: 0).dashCenterX
        } else {
            let metricsRows = renderSlots.filter { !$0.isPlaceholder }.map { slot -> PeriodHeaderMetrics in
                PeriodHeaderMetrics(
                    startWidth: textWidth(slot.displayStart, font: timeFont),
                    endWidth: textWidth(slot.displayEnd, font: timeFont),
                    labelWidth: textWidth(label(of: slot), font: labelFont),
                    showX: showX && slot.nodeStart == slot.nodeEnd)
            }
            // 整列统一字号: 全列行约束由最紧约束算一次(用户 2026-09-29 令: 禁逐行独立自适应)
            let constraints = metricsRows.map { m -> PeriodHeaderAdaptiveFont.RowConstraint in
                let timeMaxW = max(m.startWidth, m.endWidth)
                return PeriodHeaderAdaptiveFont.RowConstraint(
                    inkWidthSp: timeMaxW + m.labelWidth,   // 联合包络(端点异锚中点)
                    timeMaxWidthSp: timeMaxW,
                    labelWidthSp: m.labelWidth)
            }
            columnFont = PeriodHeaderAdaptiveFont.forColumn(
                cardWidthSp: 240, cardHeightSp: headerContentHeightSp, rows: constraints)
            // 整列统一中点: 与渲染自适应字号同一 16sp 投影口径(用户令 2026-09-30: 卡宽恒等, 禁参差)
            let projection = PeriodHeaderAdaptiveFont.MAX_LABEL_SP / PeriodHeaderAdaptiveFont.BASE_LABEL_SP
            let projected = metricsRows.map { m in
                PeriodHeaderMetrics(startWidth: m.startWidth * projection,
                                    endWidth: m.endWidth * projection,
                                    labelWidth: m.labelWidth * projection,
                                    showX: m.showX)
            }
            columnPlacements = solveColumnPlacement(rows: projected, u: hanging)
            legacyAxis = nil
        }
    }
}

// MARK: - CardsGridView ← CardsGridView

struct CardsGridView: View {
    @Environment(\.localWakeUpColors) private var colors
    @Environment(\.localCoursePalette) private var palette
    @Environment(\.localNavExtraBottomPadding) private var navExtra
    let courses: [CourseEntity]
    let timeSlots: [TimeSlot]
    /// issue#23 §5: 非空 → 渲染期合成占位节次 + 按分钟加权行高(非常规课跨空隙落位)
    var timeJson: String = ""
    var visibleDays: Set<Int> = Set(1...7)
    var showDate: Bool = false
    var startDate: String = ""
    var currentWeek: Int = 1
    var today: Int = DateUtils.todayDayOfWeek()
    let onCourseClick: (CourseEntity) -> Void
    var greyDays: Set<Int> = []  // 本周应灰显的星期几 (1-7) — 节假日/周末灰显
    /// 全学期课程(跨周) — 晚间自动收起判据("整学期没有晚间课才收") ← allCourses
    var allCourses: [CourseEntity]? = nil
    var todayDate: Date = Date()
    /// v7.10.5 会话级置顶 override — ScheduleScreen 持有, radio 与网格同真相源 ← topOverrides
    var topOverrides: [String: Int64] = [:]
    var onSetTopOverride: (String, Int64?) -> Void = { _, _ in }
    /// v7.10.16r 轮换态(issue#10): 与 topOverrides 同级持有(ScheduleScreen) —
    /// 页内 remember 会在周翻页时销毁("周切换一次轮换态即丢")。
    var rotationSteps: [String: Int] = [:]
    var onRotationStep: (String, Int) -> Void = { _, _ in }
    /// 双指行高缩放(相对基座; tick 落盘 / 撤回回退由持有方负责) ← rowHeightScale
    var rowHeightScale: CGFloat = 1
    var onRowHeightScaleChange: (CGFloat) -> Void = { _ in }
    /// v1.0.56 T3(实验室): 双指捏放行高总开关, 默认 false = 手势整个不挂 ← pinchZoomEnabled
    var pinchZoomEnabled: Bool = false

    // 用户反馈 2026-09-16: 占位行展开态(会话级, 键=时间串, 周内多天共享同一空隙 → 同键联动)。
    // ← Android remember(mutableStateOf) — 翻周/离开页面复位由持有方视图生命周期承担。
    @State private var expandedPlaceholders: Set<String> = []

    var body: some View {
        let scale = CGFloat(AppPrefs.shared.getGridScale())          // issue#8 0.7~1.3
        let cornerRatio = CGFloat(AppPrefs.shared.getGridCornerRatio())
        let d: (CGFloat) -> CGFloat = { $0 * scale }
        let timeJsonOpt: String? = timeJson.isEmpty ? nil : timeJson

        // 实验室开关(默认全关) — body 直读(AppPrefs 兄弟文件同模式, 无需 changeBus)
        let adaptiveHeight = AppPrefs.shared.isGridAdaptiveHeight()
        let autoHideEmptyEvening = AppPrefs.shared.isGridAutoHideEmptyEvening()
        let eveningStart = TimetableViewportPolicy.parseEveningStart(AppPrefs.shared.getGridEveningStart())
        let showSeparators = AppPrefs.shared.isGridShowSeparators()
        let longBreakSpacing = AppPrefs.shared.isGridLongBreakSpacing()

        // 视口策略: 先裁剪稳定的学期级基础槽位(晚间自动收起), 再为当前周合成占位行
        let baseSlots: [TimeSlot]
        if autoHideEmptyEvening {
            let visible = TimetableViewportPolicy.selectVisibleSlots(
                allCourses: allCourses ?? courses,
                timeSlots: timeSlots.map(TimetableViewportPolicy.SlotRef.init),
                visibleDays: visibleDays,
                timeJson: timeJsonOpt,
                autoHideEmptyEvening: true,
                eveningStartMinutes: eveningStart)
            // 回映: SlotRef 按 nodeStart 唯一性取原 TimeSlot(逐节行 nodeStart 不重复)
            baseSlots = visible.slots.compactMap { ref in
                timeSlots.first { $0.nodeStart == ref.nodeStart }
            }
        } else {
            baseSlots = timeSlots
        }
        let renderPlan: TimeTableUtils.RenderSlotPlan = timeJsonOpt != nil
            ? TimeTableUtils.buildRenderSlotPlan(courses: courses, timeJson: timeJson, baseSlots: baseSlots)
            : TimeTableUtils.RenderSlotPlan(slots: baseSlots)
        let renderSlots = renderPlan.slots
        let maxNode = renderSlots.map { $0.nodeEnd }.max() ?? 12
        let sortedDays = visibleDays.sorted()
        let dayCount = max(sortedDays.count, 1)

        // 布局常量 — timeW 实测(三行式墨迹包络 / 老式 dash 轴, 下限 d(46) 防极窄机型挤压;
        // 上限不死钉 68dp — "第 X 节"长标签交给实测回传) ← Android timeW
        let headerStyle = AppPrefs.shared.getPeriodHeaderStyle()
        let headerLayout = AppPrefs.shared.getPeriodHeaderLayout()
        let headerHanging = CGFloat(AppPrefs.shared.getPeriodHeaderHanging())
        let headerShowX = AppPrefs.shared.isPeriodHeaderShowX()
        let timeW: CGFloat
        if headerLayout == "three_line" {
            timeW = max(threeLineWidthDp(slots: renderSlots, headerStyle: headerStyle, scale: scale,
                                         hangingUnits: headerHanging, showX: headerShowX), d(46))
        } else {
            timeW = max(legacyLineWidthDp(slots: renderSlots, headerStyle: headerStyle, scale: scale,
                                          showX: headerShowX), d(46))
        }
        let headH = d(52)
        let gapH = d(4)
        let gapW = d(5)

        // 长课间留白: 固定薄带(24dp×gridScale×fontScale), 行高保持刚性不缩放
        // — 用户反馈 2026-10: 旧 6dp 带宽+行等比压缩累积成整行空隙(#118 原语再定义)
        let mealBreakAfterRows: Set<Int> = (longBreakSpacing && timeJsonOpt != nil)
            ? MealBreakDetector.detectDisplayRowIndexes(timeJson: timeJson, courses: courses,
                                                        displayedNodeEnds: renderSlots.map { $0.nodeEnd })
            : []
        let mealGapExtra: CGFloat = longBreakSpacing ? d(24) * systemFontScaleProxy : 0

        return GeometryReader { geo in
            // 外层 padding d(8) 每边 — 可用宽/高都已扣除(← BoxWithConstraints maxWidth/maxHeight)
            let boxPad = d(8)
            let availableW = max(geo.size.width - 2 * boxPad, 0)
            // 行高基座: 自适应只改纵向; 长课间带不进可用高度预算(行高刚性, 带悬浮行间)
            let availableGridHeight = max(geo.size.height - 2 * boxPad - headH - gapH - navExtra, 0)
            let weightsForFit = renderPlan.slotWeights.map { $0.map { CGFloat($0) } }
            let baseRowHeight = TimetableViewportPolicy.baseRowHeightDp(
                adaptive: adaptiveHeight,
                fitRowHeightDp: TimetableViewportPolicy.fitRowHeightDp(
                    availableGridHeightDp: availableGridHeight,
                    slotWeights: weightsForFit,
                    slotCount: renderSlots.count,
                    contentScale: scale),
                contentScale: scale)
            let clampedScale = min(max(scale, 0.7), 1.3)
            let rowHeightDp = TimetableViewportPolicy.manualRowHeightDp(
                baseRowHeightDp: baseRowHeight,
                verticalScale: rowHeightScale,
                minRowHeightDp: TimetableViewportPolicy.MIN_ROW_DP * clampedScale,
                maxRowHeightDp: TimetableViewportPolicy.MAX_ROW_DP * clampedScale)
            let rowH = rowHeightDp

            // 展开的占位行权重 = "正好显示完文字"的展开权重 — yOfRows/rowHeightAt/gridH
            // 都读 effectiveWeights 同一张表, 行高与 y 前缀和天然同源(时间轴不破)。
            let effectiveWeights: [CGFloat]? = renderPlan.slotWeights.map { base in
                base.enumerated().map { i, w in
                    let slot = i < renderSlots.count ? renderSlots[i] : nil
                    if let slot, slot.isPlaceholder, expandedPlaceholders.contains(slot.timeString) {
                        return max(CGFloat(w), TimeTableUtils.placeholderExpandedWeight(
                            rowHeightDp: rowHeightDp,
                            gapDp: TimetableViewportPolicy.ROW_GAP_DP,
                            requiredTextHeightDp: placeholderTextRequiredDp))
                    }
                    return CGFloat(w)
                }
            }

            // yOfRows(r) — 加权行坐标 r(0.0=网格顶, 1.0=一标准行) → pt; 穿过的长课间带同帧计入
            let ws = effectiveWeights ?? Array(repeating: CGFloat(1), count: renderSlots.count)
            let yOfRows: (Double) -> CGFloat = { r in
                let full = Int(min(max(r, 0), Double(ws.count)))
                var acc: CGFloat = 0
                for i in 0..<full { acc += ws[i] }
                if full < ws.count && r > Double(full) { acc += ws[full] * CGFloat(r - Double(full)) }
                let crossedBreaks = mealBreakAfterRows.filter { Double($0 + 1) <= r }.count
                return rowH * acc + mealGapExtra * CGFloat(crossedBreaks)
            }
            let rowHeightAt: (Int) -> CGFloat = { i in
                rowH * (i >= 0 && i < ws.count ? ws[i] : 1)
            }
            let gapAfterRow: (Int) -> CGFloat = { i in
                gapH + (mealBreakAfterRows.contains(i) ? mealGapExtra : 0)
            }

            // 整列统一字号/中点/dash 轴 — 真实行高输入(双指缩行/自适应联动)
            let headerGeo = HeaderColumnGeometry(
                renderSlots: renderSlots, layout: headerLayout, style: headerStyle,
                hanging: headerHanging, showX: headerShowX, scale: scale,
                rowHeightAt: rowHeightAt, gapH: gapH, rowHeightDp: rowHeightDp)

            // 列宽: (可用宽 − timeW − gapW*(dayCount+1)) / dayCount ← colW
            let colW = max((availableW - timeW - gapW * CGFloat(dayCount + 1)) / CGFloat(dayCount), 28)
            // grid 高按 renderSlots 行数算(边缘/占位行按分钟加权计入) ← gridH
            let gridH = yOfRows(Double(max(renderSlots.count, 1)))

            // 行 → sharedPlacement 索引 = 该行之前(含本行前缀)非占位行数 ← subList(0,i).count{!isPlaceholder}
            let placementIndexOf: (Int) -> Int = { i in
                renderSlots[0..<max(min(i, renderSlots.count), 0)].filter { !$0.isPlaceholder }.count
            }

            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    // ---- 表头: 自然排布 Row(高 headH, spacedBy gapW) ----
                    HStack(spacing: gapW) {
                        Spacer().frame(width: timeW)
                        ForEach(sortedDays, id: \.self) { day in
                            let dateStr: String? = {
                                guard showDate, !startDate.isEmpty,
                                      let dd = DateUtils.dateOfWeek(startDate: startDate, week: currentWeek, dayOfWeek: day) else { return nil }
                                return DateUtils.shortDate(dd)
                            }()
                            DayHeadCell(day: day,
                                        isToday: isDateTodayOfWeek(startDate: startDate, week: currentWeek,
                                                                   day: day, todayDate: todayDate),
                                        isGrey: greyDays.contains(day),
                                        courseCount: courses.filter { $0.day == day }.count,
                                        dateStr: dateStr,
                                        scale: scale, cornerRatio: cornerRatio)
                                .frame(width: colW)
                                .frame(maxHeight: .infinity)
                        }
                    }
                    .frame(width: availableW, height: headH, alignment: .leading)

                    Spacer().frame(height: gapH)

                    // ---- Grid 主体: 固定高度, 内部绝对定位 + drawBehind 分隔线 ----
                    ZStack(alignment: .topLeading) {
                        if showSeparators {
                            // ← drawBehind: outlineVariant α0.42, stroke 0.7; 长课间带断开竖线
                            Canvas { ctx, size in
                                let lineColor = colors.outlineVariant.opacity(0.42)
                                let stroke: CGFloat = 0.7
                                let firstColumn = timeW + gapW / 2
                                var breakBands: [GridSeparatorGeometry.Span] = []
                                for row in mealBreakAfterRows.sorted() {
                                    guard renderSlots.indices.contains(row), row + 1 < renderSlots.count else { continue }
                                    let bandBottom = yOfRows(Double(row + 1))
                                    let bandTop = bandBottom - gapAfterRow(row)
                                    breakBands.append(GridSeparatorGeometry.Span(start: bandTop, end: bandBottom))
                                }
                                for column in 0...dayCount {
                                    let x = firstColumn + CGFloat(column) * (colW + gapW)
                                    for seg in GridSeparatorGeometry.verticalSegments(
                                        start: 0, end: size.height, excluded: breakBands) {
                                        var p = Path()
                                        p.move(to: CGPoint(x: x, y: seg.start))
                                        p.addLine(to: CGPoint(x: x, y: seg.end))
                                        ctx.stroke(p, with: .color(lineColor), lineWidth: stroke)
                                    }
                                }
                                for boundary in 0...renderSlots.count {
                                    let y = yOfRows(Double(boundary))
                                    var p = Path()
                                    p.move(to: CGPoint(x: timeW, y: y))
                                    p.addLine(to: CGPoint(x: size.width, y: y))
                                    ctx.stroke(p, with: .color(lineColor), lineWidth: stroke)
                                }
                                for band in breakBands {
                                    var p = Path()
                                    p.move(to: CGPoint(x: timeW, y: band.start))
                                    p.addLine(to: CGPoint(x: size.width, y: band.start))
                                    ctx.stroke(p, with: .color(lineColor), lineWidth: stroke)
                                }
                            }
                            .frame(width: availableW, height: gridH)
                        }

                        // 时间栏: 每节一行, offset 定位(分钟加权)
                        ForEach(Array(renderSlots.enumerated()), id: \.offset) { i, slot in
                            let phFitsText = !slot.isPlaceholder || TimeTableUtils.placeholderTextFits(
                                rowWeight: (i < ws.count ? ws[i] : 1),
                                rowHeightDp: rowHeightDp,
                                gapDp: TimetableViewportPolicy.ROW_GAP_DP,
                                requiredTextHeightDp: placeholderTextRequiredDp)
                            SingleTimeHeadCell(
                                slot: slot,
                                scale: scale,
                                cornerRatio: cornerRatio,
                                textFits: phFitsText,
                                onToggleExpand: (slot.isPlaceholder && !phFitsText)
                                    ? { togglePlaceholder(slot.timeString) } : nil,
                                sharedFont: headerGeo.columnFont,
                                sharedPlacement: headerGeo.columnPlacements.map {
                                    $0.indices.contains(placementIndexOf(i)) ? $0[placementIndexOf(i)] : nil
                                } ?? nil,
                                sharedLegacyAxis: headerGeo.legacyAxis)
                                .frame(width: timeW, height: max(rowHeightAt(i) - gapH, 0))
                                .offset(y: yOfRows(Double(i)))
                        }

                        // 课程卡片: 冲突簇整簇 ConflictClusterCard, 非簇课单卡路径(回归保护)
                        GridConflictLayer(
                            courses: courses, visibleDays: visibleDays, sortedDays: sortedDays,
                            maxNode: maxNode, timeSlots: renderSlots,
                            timeJson: timeJson,
                            spanDpOf: { f, t in Double(yOfRows(t) - yOfRows(f)) },
                            timeW: timeW, colW: colW, rowH: rowH,
                            gapW: gapW, gapH: gapH, greyDays: greyDays,
                            scale: scale, cornerRatio: cornerRatio,
                            isDark: CourseColorUtil.isPaletteDark(palette),
                            onCourseClick: onCourseClick,
                            topOverrides: topOverrides,
                            onSetTopOverride: onSetTopOverride,
                            rotationSteps: rotationSteps,
                            onRotationStep: onRotationStep,
                            yOfRows: yOfRows,
                            gapAfterRow: gapAfterRow)
                    }
                    .frame(width: availableW, height: gridH, alignment: .topLeading)
                    // 双指纵向缩放行高(实验室开关默认关 = 手势不挂) ← verticalResizeGesture
                    .background(GridPinchResizer(
                        enabled: pinchZoomEnabled,
                        baseRowHeightDp: baseRowHeight,
                        currentRowHeightDp: rowHeightDp,
                        contentScale: scale,
                        onScaleChange: onRowHeightScaleChange)
                        .allowsHitTesting(false))

                    // Dock 悬浮底栏余量(同 FullWeekView)
                    if navExtra > 0 { Spacer().frame(height: navExtra) }
                }
                .frame(width: availableW, alignment: .topLeading)
            }
            .padding(boxPad)
        }
        .background(colors.surfaceContainerHigh)
        .cornerRadius(SleepyShapes.large)
    }

    /// 占位行展开/折叠: 键=时间串(周内多天共享同一空隙 → 同键联动展开) ← togglePlaceholder
    private func togglePlaceholder(_ key: String) {
        if expandedPlaceholders.contains(key) { expandedPlaceholders.remove(key) }
        else { expandedPlaceholders.insert(key) }
    }
}

// MARK: - GridConflictLayer ← CourseTableView.kt Grid 主体内联簇/单卡绘制(v7.10.16r 终态)

/// 冲突簇渲染层: 引擎聚簇后 簇 → ConflictClusterCard(轮换/置顶 override 通道),
/// 非簇课 → CourseOverlayCard 单卡路径。
/// topOverrides/rotationSteps = ScheduleScreen 持有(v7.10.16r: 页内态翻页即丢),
/// defaultTopMap = 持久偏好(radio), 作 topOverride fallback。
struct GridConflictLayer: View {
    @Environment(\.localWakeUpColors) private var colors
    @ObservedObject private var defaultTopStore = AppPrefs.sharedConflictDefaultTopStore
    let courses: [CourseEntity]
    let visibleDays: Set<Int>
    let sortedDays: [Int]
    let maxNode: Int
    /// issue#23: 边缘节点行号/步长按 renderSlots 真实行序; 空 = 旧 startNode ∈ [1,maxNode] 行为
    let timeSlots: [TimeSlot]
    /// issue#23 §5: 非空 → 时间域聚簇 + ownTime 课分数行落位
    var timeJson: String = ""
    /// 行跨度(分数行) → 像素高(加权); 网格恒传(含占位行/长课间带的同源映射)
    var spanDpOf: ((Double, Double) -> Double)? = nil
    let timeW: CGFloat
    let colW: CGFloat
    let rowH: CGFloat
    let gapW: CGFloat
    let gapH: CGFloat
    let greyDays: Set<Int>
    /// issue#8: 网格缩放/圆角比例 — 透传给单卡路径
    var scale: Double = 1.0
    var cornerRatio: Double = 1.0
    /// 深色判定(本层无 palette 环境注入,由 CardsGridView 传入)
    let isDark: Bool
    let onCourseClick: (CourseEntity) -> Void
    /// v7.10.5: 置顶 override 通道上提 — 网格 onPickTop 与详情 radio 写同一真相源
    var topOverrides: [String: Int64] = [:]
    var onSetTopOverride: (String, Int64?) -> Void = { _, _ in }
    /// v7.10.16r 轮换态: 簇键 → 步数,同持有方(翻页不丢)
    var rotationSteps: [String: Int] = [:]
    var onRotationStep: (String, Int) -> Void = { _, _ in }
    /// 加权行坐标 → y(锚点/单卡同一前缀和) ← yOfRows
    var yOfRows: (Double) -> CGFloat = { _ in 0 }
    /// 行后间距(含长课间带) ← gapAfterRow
    var gapAfterRow: (Int) -> CGFloat = { _ in 4 }

    var body: some View {
        let conflictStyle = AppPrefs.shared.getConflictStyle()
        let defaultTopMap = defaultTopStore.map
        let clusters = ConflictLayoutEngine.findClusters(
            courses, timeJson: timeJson.isEmpty ? nil : timeJson)
        let clusteredIds = Set(clusters.flatMap { $0.courses.map { $0.id } })
        // issue#23: 边缘节点用 slotIndexOf 兜底, 数据脏返回 -1 直接过滤
        let slotIndexOf: (Int) -> Int = timeSlots.isEmpty
            ? { node in (1...max(maxNode, 1)).contains(node) ? node - 1 : -1 }
            : { node in timeSlots.firstIndex { $0.nodeStart == node } ?? -1 }

        ZStack(alignment: .topLeading) {
            ForEach(Array(clusters.enumerated()), id: \.offset) { item in
                let cluster = item.element
                // 簇内课若因 visibleDays 过滤或节点不在 renderSlots 则整簇跳过
                if visibleDays.contains(cluster.day) {
                    let inGrid = cluster.courses.filter { slotIndexOf($0.startNode) >= 0 }
                    if !inGrid.isEmpty {
                        let anchor = cluster.courses.first! // 主课判定序首位,决定簇基点
                        let dayIdx = sortedDays.firstIndex(of: cluster.day) ?? 0
                        let cardX = timeW + gapW + (colW + gapW) * CGFloat(dayIdx)
                        // 用户报障 2026-09-10: 簇锚点用锚课小数行坐标(ownTime 锚课不再
                        // 被 slotIndexOf 整格吸附丢掉本体偏移);加权 dp 与簇内 spanDpOf 同一真值。
                        let anchorFrac = (anchor.ownTime && !anchor.startTime.isEmpty && !anchor.endTime.isEmpty)
                            ? TimeTableUtils.timeToFractionalRows(anchor.startTime, anchor.endTime, slots: timeSlots)
                            : nil
                        let anchorRow = anchorFrac?.0 ?? Double(max(slotIndexOf(anchor.startNode), 0))
                        let cardY = yOfRows(anchorRow)
                        let clusterKey = ConflictLayoutEngine.conflictClusterKey(cluster)
                        ConflictClusterCard(
                            cluster: cluster,
                            style: conflictStyle,
                            topOverrideId: topOverrides[clusterKey] ?? defaultTopMap[clusterKey],
                            onPickTop: { id in onSetTopOverride(clusterKey, id) },
                            onCourseClick: onCourseClick,
                            colW: colW, rowH: rowH, maxNode: maxNode,
                            gapW: gapW, gapH: gapH,
                            timeSlots: timeSlots,
                            spanDpOf: spanDpOf,
                            isGrey: greyDays.contains(cluster.day),
                            rotationStep: rotationSteps[clusterKey],
                            onRotate: {
                                onRotationStep(clusterKey, (rotationSteps[clusterKey] ?? 0) + 1)
                            },
                            onPickFromBadge: { layerPos in
                                // 气泡选课 = 换来看: 步数使目标层转到基准序首位(会话态)
                                onRotationStep(clusterKey, layerPos)
                            })
                            .offset(x: cardX, y: cardY)
                    }
                }
            }
            ForEach(courses) { course in
                if visibleDays.contains(course.day),
                   slotIndexOf(course.startNode) >= 0,
                   !clusteredIds.contains(course.id) { // 簇内课已由 ConflictClusterCard 绘制
                    let dayIdx = sortedDays.firstIndex(of: course.day) ?? 0
                    let nodeIdx = slotIndexOf(course.startNode)
                    // 步长上限按剩余行数算(边缘节点也按 renderSlots 总行数取模)
                    let steps = min(max(course.step, 1), timeSlots.count - nodeIdx)
                    let cardX = timeW + gapW + (colW + gapW) * CGFloat(dayIdx)
                    // issue#23 §5: ownTime 单卡按真实分钟比例落位(可落在占位行内),
                    // 时间不可解析 → 回落整格吸附
                    let frac = (course.ownTime && !course.startTime.isEmpty && !course.endTime.isEmpty)
                        ? TimeTableUtils.timeToFractionalRows(course.startTime, course.endTime, slots: timeSlots)
                        : nil
                    // ViewBuilder 不接受「先声明后分支赋值」(let 赋值语句不是 View) — 用即时闭包算出 (cardY, cardH)
                    let (cardY, cardH): (CGFloat, CGFloat) = {
                        guard let frac else {
                            return (yOfRows(Double(nodeIdx)),
                                    yOfRows(Double(nodeIdx + steps)) - yOfRows(Double(nodeIdx)) - gapAfterRow(nodeIdx + steps - 1))
                        }
                        // 按比例(分钟加权), 保底 0.3 标准行避免过短课胶囊塌缩到不可点;
                        // 整行结束(frac.1 为整数且 >0)→ 扣该行 gapAfterRow, 否则扣 gapH
                        let span = max(yOfRows(frac.1) - yOfRows(frac.0), rowH * 0.3)
                        let r2 = Int(frac.1.rounded())
                        let subtract = (frac.1 == Double(r2) && frac.1 > 0)
                            ? gapAfterRow(r2 - 1) : gapH
                        return (yOfRows(frac.0), span - subtract)
                    }()
                    CourseOverlayCard(course: course, cardHeight: cardH,
                                      isDark: isDark,
                                      isGrey: greyDays.contains(course.day),
                                      groupRows: courses.filter { $0.groupId == course.groupId },
                                      scale: scale, cornerRatio: cornerRatio) {
                        onCourseClick(course)
                    }
                    .frame(width: colW, height: cardH)
                    .offset(x: cardX, y: cardY)
                }
            }
        }
        // v7.10.16r(评审#4): 详情 radio 落盘 → 会话态跟随(持有方负责):
        // 显式选默认置顶 = 会话 override 同步(radio 通道) + 同簇临时轮换让位。
        // ← Android ScheduleScreen.onDefaultTopChanged: rotationSteps -= key; setTopOverride(key, repId)
        .onChange(of: defaultTopStore.map) { newMap in
            for (k, v) in newMap where lastDefaultTopMap[k] != v {
                onSetTopOverride(k, v)
                onRotationStep(k, 0)
            }
            for k in lastDefaultTopMap.keys where newMap[k] == nil {
                onSetTopOverride(k, nil)
                onRotationStep(k, 0)
            }
            lastDefaultTopMap = newMap
        }
    }

    /// onChange 需要旧值对比 — 只处理真正被 radio 触碰的簇键
    @State private var lastDefaultTopMap: [String: Int64] = [:]
}

// MARK: - SingleTimeHeadCell ← SingleTimeHeadCell

/// 时间栏单元: 三行式/老式表头委托 PeriodHeaderCellContent(整列统一字号/中点/dash 轴),
/// 渲染期占位节次 = 更低调呈现(半透明底只显时间); 文字放不下的占位行 = 纯灰块,
/// 点击展开(用户反馈 2026-09-16)。
private struct SingleTimeHeadCell: View {
    @Environment(\.localWakeUpColors) private var colors
    let slot: TimeSlot
    var scale: Double = 1.0
    var cornerRatio: Double = 1.0
    var textFits: Bool = true
    var onToggleExpand: (() -> Void)? = nil
    var sharedFont: PeriodHeaderAdaptiveFont? = nil
    var sharedPlacement: PeriodHeaderPlacement? = nil
    var sharedLegacyAxis: CGFloat? = nil

    var body: some View {
        let headerLayout = AppPrefs.shared.getPeriodHeaderLayout()
        let headerStyle = AppPrefs.shared.getPeriodHeaderStyle()
        let isPh = slot.isPlaceholder
        // 用户反馈 2026-09-16: 文字放不下的占位行 = 纯灰块(不显示文字), 点击展开/折叠。
        // 只灰置占位卡片本身, 课程卡片照常渲染(几何由课程卡自身比例定位, 不受此影响)。
        let phCollapsed = isPh && !textFits
        let shape = RoundedRectangle(cornerRadius: 8 * scale * min(cornerRatio, 1))

        ZStack {
            Group {
                if phCollapsed {
                    // 灰块形态: 无文字 — 信息靠点击展开
                    Color.clear
                } else if isPh {
                    Text(slot.timeString)
                        .font(.system(size: 9 * scale))
                        .foregroundColor(colors.onSurfaceVariant)
                        .lineLimit(1)
                        .truncationMode(.tail)
                } else {
                    PeriodHeaderCellContent(
                        displayStart: slot.displayStart,
                        displayEnd: slot.displayEnd,
                        nodeStart: slot.nodeStart,
                        nodeEnd: slot.nodeEnd,
                        isPlaceholder: false,
                        layout: headerLayout,
                        style: headerStyle,
                        scale: CGFloat(scale),
                        sharedFont: sharedFont,
                        sharedPlacement: sharedPlacement,
                        sharedLegacyAxis: sharedLegacyAxis)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        // 与设置页预览逐层相等(PERIOD_HEADER_CARD_PAD_DP, 用户 2026-09-28 令):
        // 之前 2dp 外 + 3dp 内 = 5dp, 预览只有 3dp → 周视图卡片比预览小一圈。
        .padding(periodHeaderCardPadDp * scale)
        .background(colors.surfaceContainerLow.opacity(isPh ? 0.5 : 1))
        .clipShape(shape)
        .modifier(TapExpandModifier(onToggleExpand: onToggleExpand))
    }
}

/// 占位灰块点击展开(仅 onToggleExpand 非空时挂 tap) ← noRippleClickable 条件链
private struct TapExpandModifier: ViewModifier {
    let onToggleExpand: (() -> Void)?
    func body(content: Content) -> some View {
        if let onToggleExpand {
            content.onTapGesture(perform: onToggleExpand)
        } else {
            content
        }
    }
}

// MARK: - CourseOverlayCard ← CourseOverlayCard

private struct CourseOverlayCard: View {
    @Environment(\.localWakeUpColors) private var colors
    let course: CourseEntity
    var cardHeight: CGFloat = 0   // 0 = 调用方未提供, 回退旧行为
    let isDark: Bool
    var isGrey: Bool = false      // 节假日灰显
    /// issue#22: 同 groupId 全行(AUTO 模式按行序算 hue; 不传 = 退化为单行 groupRows)
    var groupRows: [CourseEntity] = []
    /// issue#8: 网格缩放/圆角比例
    var scale: Double = 1.0
    var cornerRatio: Double = 1.0
    let onClick: () -> Void

    var body: some View {
        let effRows = groupRows.isEmpty ? [course] : groupRows
        // 统一取色入口(决策 D3)— 中性色 secondaryContainer ← Android neutralColor
        let bg = CourseColorUtil.pickCourseColorSwiftUIWithGroupRows(
            course, groupRows: effRows, isDark: isDark,
            neutralColor: colors.secondaryContainer,
            colorless: AppPrefs.shared.isCourseColorless())
        // 文字色亮度自适应(决策 D5-13)
        let fg = CourseColorUtil.textColorOn(bg: bg, isDark: isDark, onSurface: colors.onSurface)
        // 节假日灰显: 色块叠 alpha + 文字 strikethrough
        let effectiveBg = isGrey ? bg.opacity(SleepyTheme.Alpha.inactive) : bg
        let effectiveFg = isGrey ? fg.opacity(SleepyTheme.Alpha.inactive) : fg
        let strikethrough = isGrey && AppPrefs.shared.getHolidayStyle() == "strikethrough"
        // 副信息(教室/教师/无) — grid_sub_info 设置决定; 卡片 y 位置本身编码节次,
        // 卡内不再显示节次/时间
        let subInfo = AppPrefs.shared.getGridSubInfo()
        // issue#26: 网格场景别名 — 网格设置开且别名非空才显示别名, 否则原名
        let name = CourseDisplayUtil.displayName(course, AppPrefs.shared.isGridUseAlias())
        let subText: String = {
            switch subInfo {
            case "room": return course.room
            case "teacher": return course.teacher
            default: return ""
            }
        }()

        Button(action: onClick) {
            Group {
                if subText.isEmpty {
                    // 无副信息: 课程名整体居中(原行为)
                    Text(name)
                        .font(.system(size: 10 * scale, weight: .semibold))
                        .foregroundColor(effectiveFg)
                        .strikethrough(strikethrough)
                        .lineLimit(6)
                        .multilineTextAlignment(.center)
                } else {
                    // 有副信息: 课程名在上半区居中(剩余空间), 副信息贴卡底 — 主文字不紧贴副文字
                    VStack(spacing: 0) {
                        Text(name)
                            .font(.system(size: 10 * scale, weight: .semibold))
                            .foregroundColor(effectiveFg)
                            .strikethrough(strikethrough)
                            .lineLimit(6)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        Text(subText)
                            .font(.system(size: 9 * scale))
                            .foregroundColor(effectiveFg.opacity(SleepyTheme.Alpha.highContent))
                            .strikethrough(strikethrough)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(SleepyButtonStyle())
        .accessibilityIdentifier("gridcell_\(course.id)")
        .padding(4 * scale)
        .background(effectiveBg)
        .cornerRadius(12 * scale * cornerRatio)
        .padding(2 * scale)
    }
}

// MARK: - DayHeadCell ← DayHeadCell

private struct DayHeadCell: View {
    @Environment(\.localWakeUpColors) private var colors
    let day: Int
    /// 该周页真实日期 = 今天(← DateUtils.dateOfWeek + isDateToday, 非 day == today)
    let isToday: Bool
    var isGrey: Bool = false
    let courseCount: Int
    var dateStr: String? = nil
    /// issue#8: 缩放(字号/内边距联动) + 圆角比例(← Android 10*scale*cornerRatio.coerceAtMost(1))
    var scale: Double = 1.0
    var cornerRatio: Double = 1.0

    var body: some View {
        let bg = isToday ? colors.primaryContainer : colors.surface
        let fg = isGrey ? colors.onSurfaceVariant.opacity(SleepyTheme.Alpha.inactive)
                        : (isToday ? colors.onPrimaryContainer : colors.onSurface)
        let subFg = isGrey ? colors.onSurfaceVariant.opacity(SleepyTheme.Alpha.inactive)
                           : (isToday ? colors.onPrimaryContainer.opacity(SleepyTheme.Alpha.highContent)
                                      : colors.onSurfaceVariant)

        VStack(spacing: 1 * scale) {
            // ← Android fontSize = (14*scale).sp lineHeight 20
            Text(DateUtils.localizedDay(day))
                .font(.system(size: 14 * scale, weight: .semibold))
                .foregroundColor(fg)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .allowsTightening(true)
            if let dateStr = dateStr {
                // ← micro 10*scale/11
                Text(dateStr)
                    .font(.system(size: 10 * scale))
                    .foregroundColor(subFg)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .allowsTightening(true)
            } else {
                // ← micro 9*scale/11
                Text(courseCount == 0 ? L10n.format("no_course")
                                      : L10n.format("course_count_format", courseCount))
                    .font(.system(size: 9 * scale))
                    .foregroundColor(subFg)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .allowsTightening(true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // ← Android padding(vertical = if (dateStr != null) 4f else 3f) ×scale
        .padding(.vertical, (dateStr != nil ? 4 : 3) * scale)
        .background(bg)
        // ← Android RoundedCornerShape((10 * scale * cornerRatio.coerceAtMost(1f)).dp)
        .cornerRadius(10 * scale * min(cornerRatio, 1))
    }
}

// =====================================================================================
// 7days full 视图 — switchable.html #fullView ← FullWeekView
// =====================================================================================

struct FullWeekView: View {
    @Environment(\.localWakeUpColors) private var colors
    @Environment(\.localCoursePalette) private var palette
    @Environment(\.localNavExtraBottomPadding) private var navExtra
    let courses: [CourseEntity]
    var visibleDays: Set<Int> = Set(1...7)
    var displayMode: String = "node"
    var timeJson: String = ""
    var today: Int = DateUtils.todayDayOfWeek()
    var todayDate: Date = Date()
    /// 周页上下文: isToday 按该页(week, day)真实日期判定, 非"星期号 = 今天星期号" —
    /// 浏览非当前周高亮错天(v7.10.x Android 同构: cards header/WeekStrip/DetailPanel/DayColumn 全链路线程化)
    var startDate: String = ""
    var currentWeek: Int = 1
    let onCourseClick: (CourseEntity) -> Void
    var greyDays: Set<Int> = []  // 本周应灰显的星期几 (1-7)

    var body: some View {
        let byDay = Dictionary(grouping: courses, by: { $0.day })
        // ← Android FullWeekView: 设置页改 weekScale/cornerRatio/twoColumn/hideEmptyDays/别名后即时生效
        let weekScale = CGFloat(AppPrefs.shared.getWeekScale())
        let cornerRatio = CGFloat(AppPrefs.shared.getGridCornerRatio())
        let useAlias = AppPrefs.shared.isWeekUseAlias()

        ScrollView(.vertical) {
            VStack(spacing: 0) {
                WeekStrip(byDay: byDay, visibleDays: visibleDays,
                          today: today, todayDate: todayDate,
                          startDate: startDate, currentWeek: currentWeek,
                          greyDays: greyDays,
                          scale: weekScale, cornerRatio: cornerRatio, useAlias: useAlias)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                DetailPanel(byDay: byDay, visibleDays: visibleDays, displayMode: displayMode,
                            timeJson: timeJson,
                            today: today, todayDate: todayDate,
                            startDate: startDate, currentWeek: currentWeek,
                            greyDays: greyDays,
                            scale: weekScale, cornerRatio: cornerRatio,
                            twoColumn: AppPrefs.shared.isWeekTwoColumn(),
                            twoColumnMode: AppPrefs.shared.getWeekTwoColumnMode(),
                            hideEmptyDays: AppPrefs.shared.isWeekHideEmptyDays(),
                            onCourseClick: onCourseClick)
                // 悬浮底栏额外余量(→ Android LocalNavExtraBottomPadding Spacer):
                //   镜像 Android FullWeekView 末行追加 Spacer(height = navExtra),
                //   最后一张课不被悬浮药丸遮住。
                Color.clear.frame(height: navExtra)
            }
        }
    }
}

// ← WeekStrip
private struct WeekStrip: View {
    let byDay: [Int: [CourseEntity]]
    let visibleDays: Set<Int>
    let today: Int
    let todayDate: Date
    let startDate: String
    let currentWeek: Int
    var greyDays: Set<Int> = []
    var scale: Double = 1.0
    var cornerRatio: Double = 1.0
    var useAlias: Bool = false

    var body: some View {
        HStack(spacing: 6 * scale) {
            ForEach(visibleDays.sorted(), id: \.self) { day in
                DaySummaryCell(day: day, courses: byDay[day] ?? [],
                               isToday: isDateTodayOfWeek(startDate: startDate, week: currentWeek,
                                                          day: day, todayDate: todayDate),
                               isGrey: greyDays.contains(day),
                               scale: scale, cornerRatio: cornerRatio, useAlias: useAlias)
            }
        }
    }
}

// ← DaySummaryCell
private struct DaySummaryCell: View {
    @Environment(\.localWakeUpColors) private var colors
    let day: Int
    let courses: [CourseEntity]
    let isToday: Bool
    var isGrey: Bool = false
    var scale: Double = 1.0
    var cornerRatio: Double = 1.0
    var useAlias: Bool = false

    var body: some View {
        let bg = isToday ? colors.primaryContainer : colors.surfaceContainer
        let fg = isGrey ? colors.onSurfaceVariant.opacity(SleepyTheme.Alpha.inactive)
                        : (isToday ? colors.onPrimaryContainer : colors.onSurface)

        VStack(spacing: 0) {
            // 日期 (← Android 13*scale / lineHeight 18*scale)
            Text(DateUtils.localizedDay(day))
                .font(.system(size: 13 * scale, weight: .semibold))
                .foregroundColor(fg)

            Spacer().frame(height: 6 * scale)

            // Chip: 课程数 — "N 门" 完整文字, 列宽放不下退化为纯数字。
            // ← Android textMeasurer: fullText 在列宽内换行(lineCount>1) → 只显数字。
            //   ViewThatFits 等价: fullText(单行)放得下用 fullText, 否则回退数字。
            // chipFg ← Android: onSurfaceVariant@alpha(grey ? inactive : 1)
            let chipFg = isGrey ? colors.onSurfaceVariant.opacity(SleepyTheme.Alpha.inactive)
                                : colors.onSurfaceVariant
            if courses.isEmpty {
                Spacer().frame(height: 14 * scale)
            } else {
                // iOS 15 兼容:ViewThatFits 是 iOS16+ API。原语义 = fullText 放不下
                // 回退纯数字;minimumScaleFactor 缩到 0.6 下限近似该意图(列宽极窄时
                // 缩字号仍可读,不再二选一),iOS 16+ 视觉行为不变。
                Text(L10n.format("course_count_format", courses.count))
                    .font(.system(size: 10 * scale, weight: .semibold))
                    .foregroundColor(chipFg)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                .padding(.horizontal, 7 * scale)
                .padding(.vertical, 2 * scale)
                .background(colors.surfaceVariant)
                .cornerRadius(50)
            }

            Spacer().frame(height: 4 * scale)

            // Mini-list: 前 5 门课名(别名开启时显示别名 ← issue#26) —
            // 左对齐(← Android fillMaxWidth Column + Text 默认 Start)
            VStack(alignment: .leading, spacing: 2 * scale) {
                ForEach(courses.prefix(5)) { c in
                    Text(CourseDisplayUtil.displayName(c, useAlias))
                        .font(.system(size: 9 * scale))
                        .foregroundColor(isToday
                            ? colors.onPrimaryContainer.opacity(SleepyTheme.Alpha.highContent)
                            : colors.onSurfaceVariant)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 132 * scale)   // ← Android heightIn(min = 132*scale)
        .padding(.horizontal, 6 * scale)
        .padding(.vertical, 8 * scale)
        .background(bg)
        .cornerRadius(12 * scale * cornerRatio)
    }
}

// ← DetailPanel
private struct DetailPanel: View {
    @Environment(\.localWakeUpColors) private var colors
    let byDay: [Int: [CourseEntity]]
    let visibleDays: Set<Int>
    let displayMode: String
    let timeJson: String
    let today: Int
    let todayDate: Date
    let startDate: String
    let currentWeek: Int
    var greyDays: Set<Int> = []
    var scale: Double = 1.0
    var cornerRatio: Double = 1.0
    /// issue#8 周视图两栏 + 分栏标准(days=按天对半 / balance=按课程数动态平衡) + 隐藏无课日
    var twoColumn: Bool = false
    var twoColumnMode: String = "days"
    var hideEmptyDays: Bool = false
    let onCourseClick: (CourseEntity) -> Void

    var body: some View {
        let sd: (Double) -> CGFloat = { CGFloat($0 * scale) }
        // issue#8 隐藏无课日 — 单栏/两栏都生效(过滤一次, 两分支同吃过滤后的列表)
        let sortedDays = visibleDays.sorted().filter {
            !hideEmptyDays || !(byDay[$0] ?? []).isEmpty
        }

        // issue#8 周视图两栏, 省纵向滚动:
        //   days    = 按天对半分 — 前半周左/后半周右, 天数固定(隐藏无课日后按剩余天数平分,
        //             奇数天多的一天落左栏)
        //   balance = 按课程数动态平衡 — 逐天放进当天卡片(约)更矮的栏, 两栏高度接近
        if twoColumn && sortedDays.count >= 2 {
            let split: ([Int], [Int]) = {
                if twoColumnMode == "balance" {
                    // 贪心: 按天序遍历, 权重 = 课程数(空天也有卡头记 1), 每天放进更矮的栏
                    var l = 0, r = 0
                    var left: [Int] = [], right: [Int] = []
                    for day in sortedDays {
                        let w = max((byDay[day] ?? []).count, 1)
                        if l <= r { left.append(day); l += w } else { right.append(day); r += w }
                    }
                    return (left, right)
                }
                let splitIdx = (sortedDays.count + 1) / 2
                return (Array(sortedDays[..<splitIdx]), Array(sortedDays[splitIdx...]))
            }()
            HStack(alignment: .top, spacing: sd(10)) {
                DetailDayColumn(days: split.0, byDay: byDay,
                                today: today, todayDate: todayDate,
                                startDate: startDate, currentWeek: currentWeek,
                                displayMode: displayMode, timeJson: timeJson,
                                greyDays: greyDays, scale: scale, cornerRatio: cornerRatio,
                                onCourseClick: onCourseClick)
                    .frame(maxWidth: .infinity)
                if !split.1.isEmpty {
                    DetailDayColumn(days: split.1, byDay: byDay,
                                    today: today, todayDate: todayDate,
                                    startDate: startDate, currentWeek: currentWeek,
                                    displayMode: displayMode, timeJson: timeJson,
                                    greyDays: greyDays, scale: scale, cornerRatio: cornerRatio,
                                    onCourseClick: onCourseClick)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(sd(12))
        } else {
            // 单栏(或两栏下过滤后不足 2 天) — 显示过滤后剩余星期
            VStack(spacing: sd(10)) {
                ForEach(sortedDays, id: \.self) { day in
                    let dayCourses = (byDay[day] ?? []).sorted { $0.startNode < $1.startNode }
                    DetailDayCard(day: day, courses: dayCourses,
                                  isToday: isDateTodayOfWeek(startDate: startDate, week: currentWeek,
                                                             day: day, todayDate: todayDate),
                                  displayMode: displayMode, timeJson: timeJson,
                                  isGrey: greyDays.contains(day),
                                  scale: scale, cornerRatio: cornerRatio,
                                  onCourseClick: onCourseClick)
                }
            }
            .padding(sd(12))
            .background(colors.surfaceContainerHigh)
            .cornerRadius(16 * scale * cornerRatio)
        }
    }
}

// ← DayColumn: 两栏模式的单侧栏 — 半周的天卡片竖排在一个独立面板里
private struct DetailDayColumn: View {
    @Environment(\.localWakeUpColors) private var colors
    let days: [Int]
    let byDay: [Int: [CourseEntity]]
    let today: Int
    let todayDate: Date
    let startDate: String
    let currentWeek: Int
    let displayMode: String
    let timeJson: String
    var greyDays: Set<Int> = []
    var scale: Double = 1.0
    var cornerRatio: Double = 1.0
    let onCourseClick: (CourseEntity) -> Void

    var body: some View {
        VStack(spacing: 10 * scale) {
            ForEach(days, id: \.self) { day in
                let dayCourses = (byDay[day] ?? []).sorted { $0.startNode < $1.startNode }
                DetailDayCard(day: day, courses: dayCourses,
                              isToday: isDateTodayOfWeek(startDate: startDate, week: currentWeek,
                                                         day: day, todayDate: todayDate),
                              displayMode: displayMode, timeJson: timeJson,
                              isGrey: greyDays.contains(day),
                              scale: scale, cornerRatio: cornerRatio,
                              onCourseClick: onCourseClick)
            }
        }
        .padding(10 * scale)
        .background(colors.surfaceContainerHigh)
        .cornerRadius(16 * scale * cornerRatio)
    }
}

// ← DetailDayCard
private struct DetailDayCard: View {
    @Environment(\.localWakeUpColors) private var colors
    let day: Int
    let courses: [CourseEntity]
    let isToday: Bool
    var displayMode: String = "node"
    var timeJson: String = ""
    var isGrey: Bool = false
    var scale: Double = 1.0
    var cornerRatio: Double = 1.0
    let onCourseClick: (CourseEntity) -> Void

    // v7.10.4 冲突栏字体压缩: lane 实宽按内容区宽算(行满宽 → 与卡内边距对齐)
    @State private var contentW: CGFloat = 0

    var body: some View {
        let greyFg = colors.onSurfaceVariant.opacity(SleepyTheme.Alpha.inactive)
        VStack(spacing: 8 * scale) {
            // 头部: 星期 + 今天标记
            HStack {
                Text(DateUtils.localizedDay(day) + (isToday ? L10n.format("today_suffix") : ""))
                    // ← Android titleSmall.copy(SemiBold): 14sp 不随 weekScale 缩放
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isGrey ? greyFg : colors.onSurface)
                Spacer()
            }

            if courses.isEmpty {
                Text(DateUtils.localizedDay(day) + L10n.format("no_course_today"))
                    .font(.system(size: 12 * scale))
                    .foregroundColor(isGrey ? greyFg : colors.onSurfaceVariant)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                // v7.10.6 行分组下沉引擎 + v7.10.10 栏间浅细竖分隔线:
                // mergeOverlapping 区域是划分(每课恰属一区域), 冲突区域整区域一行
                // (横向 laneCount 栏,同栏多门课纵向堆叠), 无冲突课一行一门全宽。
                let rows = ConflictLayoutEngine.weekLaneRows(
                    courses, timeJson: timeJson.isEmpty ? nil : timeJson)
                VStack(spacing: 7 * scale) {
                    ForEach(rows, id: \.courses.first!.id) { row in
                        if row.laneCount == 1, let only = row.courses.first {
                            LessonRow(course: only, displayMode: displayMode, timeJson: timeJson,
                                      isGrey: isGrey, groupRows: courses.filter { $0.groupId == only.groupId },
                                      scale: scale, cornerRatio: cornerRatio) {
                                onCourseClick(only)
                            }
                        } else {
                            // 冲突行: 按 lane 并排(每栏均分), 同栏课程纵向堆叠
                            // (栏内课互不重叠——chainGroups 独立集保证,堆叠即正确时序)
                            // v7.10.4: 栏实宽 → 字体线性压缩(两栏模式下 lane 半宽不缩则字挤)
                            let laneGap = 6 * scale
                            let laneW = contentW > 0
                                ? (contentW - laneGap * CGFloat(row.laneCount - 1)) / CGFloat(row.laneCount)
                                : 0
                            let laneScale = weekLaneFontScale(laneW: CGFloat(laneW))
                            let hideSide = weekLaneHideSideLabel(laneW: CGFloat(laneW))
                            HStack(alignment: .top, spacing: laneGap) {
                                ForEach(0..<row.laneCount, id: \.self) { li in
                                    if li > 0 {
                                        // 栏间浅细竖线: 0.5dp 宽, onSurface hairline, 高度随行
                                        Rectangle()
                                            .fill(colors.onSurface.opacity(SleepyTheme.Alpha.hairline))
                                            .frame(width: 0.5)
                                    }
                                    let laneCourses = row.courses.filter { row.laneOf[$0.id] == li }
                                    VStack(spacing: 5 * scale) {
                                        ForEach(laneCourses) { laneCourse in
                                            LessonRow(course: laneCourse, displayMode: displayMode,
                                                      timeJson: timeJson, isGrey: isGrey,
                                                      groupRows: courses.filter { $0.groupId == laneCourse.groupId },
                                                      scale: scale, cornerRatio: cornerRatio,
                                                      laneScale: laneScale, hideSideLabel: hideSide) {
                                                onCourseClick(laneCourse)
                                            }
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(10 * scale)
        .frame(maxWidth: .infinity, alignment: .leading)
        // 空课 surfaceContainerLow(← DetailDayCard), 无描边
        .background(courses.isEmpty ? colors.surfaceContainerLow : colors.surface)
        .cornerRadius(12 * scale * cornerRatio)
        .background(
            // 内容区宽测量 → 冲突 lane 压缩比(一次测量, 卡内全部冲突行共用)
            GeometryReader { g in
                Color.clear.preference(key: DetailDayCardWidthKey.self, value: g.size.width)
            }
        )
        .onPreferenceChange(DetailDayCardWidthKey.self) { contentW = $0 - 20 * scale }
    }
}

private struct DetailDayCardWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

// =====================================================================================
// v7.10.4 冲突栏字号/间距压缩 — 用户 2026-09-02: 两栏模式下分栏字全挤到一起,
// 需按 lane 实宽调画面比例。(← Android weekLaneFontScale/weekLaneHideSideLabel)
// =====================================================================================

/// lane 宽压缩基准: 单栏半宽量级(用户实测"比较好"的现状), 低于它开始线性缩。
let WEEK_LANE_SCALE_BASE: CGFloat = 150
/// 压缩下限 — 再窄也不无限缩, 可读性由隐藏侧栏标签/副信息兜底。
let WEEK_LANE_SCALE_FLOOR: CGFloat = 0.6

/// 冲突栏内 LessonRow 的缩放比(纯函数可测): laneW ≥ 150dp → 1.0; 以下线性压缩; 0.6 封底。
func weekLaneFontScale(laneW: CGFloat) -> Double {
    if laneW >= WEEK_LANE_SCALE_BASE { return 1 }
    return Double(max(laneW / WEEK_LANE_SCALE_BASE, WEEK_LANE_SCALE_FLOOR))
}

/// 极窄 lane 判定: 侧栏节次/时间标签(42dp+8dp 间距)挤占正文 → 隐藏它。
func weekLaneHideSideLabel(laneW: CGFloat) -> Bool { laneW < 110 }

// ← LessonRow
private struct LessonRow: View {
    @Environment(\.localWakeUpColors) private var colors
    @Environment(\.localCoursePalette) private var palette
    let course: CourseEntity
    let displayMode: String
    let timeJson: String
    var isGrey: Bool = false
    /// issue#22: 同 groupId 全行(AUTO 模式按行序算 hue; 不传 = 退化为单行 groupRows)
    var groupRows: [CourseEntity] = []
    /// issue#8: 周视图缩放 + 冲突栏压缩(v7.10.4: effScale = scale × laneScale)
    var scale: Double = 1.0
    var cornerRatio: Double = 1.0
    var laneScale: Double = 1.0
    /// 极窄 lane: 侧栏节次/时间标签(42+8)挤占正文 → 隐藏(← weekLaneHideSideLabel)
    var hideSideLabel: Bool = false
    let onClick: () -> Void

    var body: some View {
        let isDark = CourseColorUtil.isPaletteDark(palette)
        let effRows = groupRows.isEmpty ? [course] : groupRows
        // 统一取色入口(决策 D3) — 中性色 secondaryContainer ← Android neutralColor
        let bg = CourseColorUtil.pickCourseColorSwiftUIWithGroupRows(
            course, groupRows: effRows, isDark: isDark,
            neutralColor: colors.secondaryContainer,
            colorless: AppPrefs.shared.isCourseColorless())
        let fg = CourseColorUtil.textColorOn(bg: bg, isDark: isDark, onSurface: colors.onSurface)
        // 节假日灰显 ← effectiveBg/effectiveFg/textDecoration
        let effectiveBg = isGrey ? bg.opacity(SleepyTheme.Alpha.inactive) : bg
        let effectiveFg = isGrey ? fg.opacity(SleepyTheme.Alpha.inactive) : fg
        let strikethrough = isGrey && AppPrefs.shared.getHolidayStyle() == "strikethrough"
        let effScale = scale * laneScale
        // issue#26: 周视图场景别名 — 与 colorless 同模式, 叶子直接读场景开关
        let name = CourseDisplayUtil.displayName(course, AppPrefs.shared.isWeekUseAlias())

        // time 模式: 时间段在连字符后折行; node 模式: 节次标签
        let timeParts: (String, String)? = displayMode == "time" && !timeJson.isEmpty
            ? TimeTableUtils.courseTimeParts(courseStartNode: course.startNode, courseStep: course.step,
                                             timeJson: timeJson, ownTime: course.ownTime,
                                             startTime: course.startTime, endTime: course.endTime)
            : nil
        let nodeLabel = course.nodeString(isShort: true)

        // meta: 教师 · 教室
        let meta: String = {
            var s = ""
            if !course.teacher.isEmpty { s += course.teacher }
            if !course.room.isEmpty {
                if !s.isEmpty { s += " · " }
                s += course.room
            }
            return s
        }()

        Button(action: onClick) {
            HStack(alignment: .top, spacing: 8 * effScale) {
                if !hideSideLabel {
                    if let parts = timeParts {
                        Text("\(parts.0)-\n\(parts.1)")
                            .font(.system(size: 12 * effScale, weight: .semibold))
                            .foregroundColor(effectiveFg)
                            .strikethrough(strikethrough)
                            .frame(width: 42 * effScale, alignment: .leading)
                    } else {
                        Text(nodeLabel)
                            .font(.system(size: 12 * effScale, weight: .semibold))
                            .foregroundColor(effectiveFg)
                            .strikethrough(strikethrough)
                            .frame(width: 42 * effScale, alignment: .leading)
                            .lineLimit(1)
                    }
                }
                // ← Android Column(weight(1f)) 无 spacing(0)
                VStack(alignment: .leading, spacing: 0) {
                    Text(name)
                        .font(.system(size: 12 * effScale, weight: .semibold))
                        .foregroundColor(effectiveFg)
                        .strikethrough(strikethrough)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    // 极窄 lane 下副信息(教师/教室)也让位给课名(← Android !hideSideLabel)
                    if !meta.isEmpty && !hideSideLabel {
                        Text(meta)
                            .font(.system(size: 11 * effScale))
                            .foregroundColor(effectiveFg.opacity(SleepyTheme.Alpha.highContent))
                            .strikethrough(strikethrough)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(9 * effScale)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(effectiveBg)
            .cornerRadius(12 * effScale * cornerRatio)
        }
        .buttonStyle(SleepyButtonStyle())
        .accessibilityIdentifier("lesson_\(course.id)")   // ← G5: 详情锚点
    }
}

// =====================================================================================
// 公共小组件
// =====================================================================================

// ← SectionHead
struct SectionHead: View {
    @Environment(\.localWakeUpColors) private var colors
    let title: String
    var action: String? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(SleepyTextStyle.sectionHead())
                .foregroundColor(colors.onSurface)
            Spacer()
            if let action = action {
                Text(action)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(colors.primary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
