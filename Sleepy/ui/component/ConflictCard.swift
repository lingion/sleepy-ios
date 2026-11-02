// ConflictCard.swift — ← ui/component/ConflictCard.kt (1000 行, 终态 v7.10.16s, 逐行翻译, GPL-3.0)
// Sleepy iOS — 100% port of sleepy Android
// 冲突簇整卡渲染: STACK 等大双卡左上/右下 / FOLD 折角 / RAIL 顶卡收窄。
// 引擎与几何纯函数在 ConflictLayoutEngine.swift(绘制序/命中区/簇级形态)。
// 轮换完整重排(v7.10.16r 对齐): 经引擎 layoutCluster 的 layerOrderOverride 通道落地,
//   与 Android ConflictCard.kt:478-480 同一逻辑(引擎侧参数已接线, 见 ConflictLayoutEngine.swift)。

import SwiftUI

// ============================ 视觉常量(视觉修订 v4) ============================

/// 课程卡圆角(dp) — 与 SleepyShapes.medium(12)同源
private let cardCorner: CGFloat = 12
/// 冲突卡描边宽(dp) — 卡窄,边框要细(用户 2026-09-01)
private let cardBorder: CGFloat = 1
/// FOLD flap 内折角圆角(dp)
private let foldFlapCorner: CGFloat = 6
/// FOLD 虚线轮廓: 段长/段间隙(dp)
private let dashLen: CGFloat = 4
private let dashGap: CGFloat = 3
/// N 徽标直径(dp)/字号
private let badgeSize: CGFloat = 14
private let badgeFont: CGFloat = 8

/// 冲突卡描边色 — 亮色压暗/暗色提亮,与自身填充、网格底、相邻课色都有对比。
func conflictBorderColor(_ base: Color) -> Color {
    // SwiftUI Color 无 luminance 直取;转 UIColor 亮度(0.299/0.587/0.114 加权)。
    // ← Compose base.luminance() > 0.5 分支
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    UIColor(base).getRed(&r, green: &g, blue: &b, alpha: &a)
    let lum = 0.299 * r + 0.587 * g + 0.114 * b
    return lum > 0.5 ? base.interpolate(to: .black, 0.35) : base.interpolate(to: .white, 0.45)
}

/// flap 色 = 顶层课色压暗(翻面朝里的物理意象)
private func foldFlapColor(_ topColor: Color) -> Color {
    topColor.interpolate(to: .black, 0.28)
}

private extension Color {
    /// 线性插值到目标色(Kotlin lerp(start, stop, fraction) 等价)
    func interpolate(to target: Color, _ fraction: CGFloat) -> Color {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        UIColor(self).getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        UIColor(target).getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let f = max(0, min(1, fraction))
        return Color(red: Double(r1 + (r2 - r1) * f),
                     green: Double(g1 + (g2 - g1) * f),
                     blue: Double(b1 + (b2 - b1) * f),
                     opacity: Double(a1 + (a2 - a1) * f))
    }
}

/// 顶卡「折角剪裁形」— 圆角矩形挖掉右上角三角(折痕从顶边 (w-f,0) 到右边 (w,f))。
/// ← FoldCutShape(Shape);iOS 用 .mask 实现(Shape 自定义 fill 差集在 SwiftUI 无直接等价)
private struct FoldCutMask: Shape {
    var fold: CGFloat
    var corner: CGFloat

    func path(in rect: CGRect) -> Path {
        // 手工构造: 圆角矩形轮廓挖掉右上三角(SwiftUI Path 无布尔差集)。
        // 顶边从 (w-f, 0) 直接斜切到 (w, f) — 与 Kotlin outline.op(Difference) 同形。
        let r = min(corner, rect.width / 2, rect.height / 2)
        let f = min(fold, rect.width - r, rect.height - r)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - f, y: rect.minY))     // 顶边到折痕上端
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + f))     // 斜切(缺角边)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        // 右下/左下/左上圆角
        p.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r,
                 startAngle: .degrees(0), endAngle: .degrees(90), clockwise: true)
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r), radius: r,
                 startAngle: .degrees(90), endAngle: .degrees(180), clockwise: true)
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r), radius: r,
                 startAngle: .degrees(180), endAngle: .degrees(270), clockwise: true)
        p.closeSubpath()
        return p
    }
}

/// 冲突卡形状: 折角(FoldCutMask)或普通圆角 — iOS15 无 AnyShape 的 enum 封装
struct ConflictCardShape: Shape {
    var folded: Bool
    var fold: CGFloat
    var corner: CGFloat

    func path(in rect: CGRect) -> Path {
        if folded {
            return FoldCutMask(fold: fold, corner: corner).path(in: rect)
        }
        let r = min(corner, rect.width / 2, rect.height / 2)
        var p = Path()
        p.addRoundedRect(in: rect, cornerSize: CGSize(width: r, height: r))
        return p
    }
}

/**
 * ConflictClusterCard — 整簇一张,内部自绘各课(← ConflictClusterCard Composable)。
 *
 * 点击语义(设计 §4, v7.8/v7.10.16r 改写):
 *   点顶卡/置顶链组成员 → onCourseClick(该课)
 *   点露出带/沉底课程卡 → N≥3 轮换推进;否则 onPickTop(沉底层代表 id)
 *   N 徽标(图层 N≥3) → 点选弹窗(「换来看」轮换 / onPickTop 持久化)
 */
struct ConflictClusterCard: View {
    @Environment(\.localWakeUpColors) private var colors
    @Environment(\.localCoursePalette) private var palette
    let cluster: ConflictCluster
    let style: String
    let topOverrideId: Int64?
    let onPickTop: (Int64?) -> Void
    let onCourseClick: (CourseEntity) -> Void
    let colW: CGFloat
    let rowH: CGFloat
    let maxNode: Int
    let gapW: CGFloat
    let gapH: CGFloat
    /// issue#23: 边缘节点(课表外节次)允许进簇 — 传 timeSlots 让簇内 filter+clamp
    /// 能用真实 slotIndex 替代过时的 startNode ∈ [1, maxNode] 判定。
    /// 不传 = 旧行为(startNode ∈ [1, maxNode] 才绘)。
    var timeSlots: [TimeSlot] = []
    /// issue#23 §5: 行跨度(分数行) → 像素高(占位节次行按分钟加权); nil = 等高回落
    var spanDpOf: ((Double, Double) -> Double)? = nil
    let isGrey: Bool
    /// v7.10.16r 轮换(issue#10): 会话内轮换步数(nil=默认序),不落盘
    var rotationStep: Int? = nil
    var onRotate: () -> Void = {}
    /// 气泡弹窗选课 = 「换来看」: 把目标层转到轮换序首位(参数=该层在默认序中的位置)
    var onPickFromBadge: (Int) -> Void = { _ in }

    @State private var showPicker = false

    var body: some View {
        let isDark = CourseColorUtil.isPaletteDark(palette)
        // v7.10.16r 轮换(issue#10, N≥3): 换层落地 = 层代表 id 作为 topOverrideId;
        // 轮换是会话态,不落盘;两节簇 rotationStep 恒 null 走原 topOverride 通道
        let layerRepIdOfCourse = ConflictLayoutEngine.memberToLayerRep(cluster.courses)
        // ← overrideAwareLayerOrder: 置顶感知基准序 — 用户置顶层恒在基准首位(整层),
        //   整周期(步数≡0 mod N)轮换序===基准序 → 置顶自动还原(评审 #4)
        let baselineOrderIds: [Int64] =
            ConflictLayoutEngine.overrideAwareLayerOrder(cluster.courses, topRepId: topOverrideId)
        let clusterLayerCount = baselineOrderIds.count
        let rotationActive = clusterLayerCount >= 3 && (rotationStep ?? 0) > 0
        // ← 完整轮换层序(Android :472-474 同源);整层序完整重排经引擎 layerOrderOverride
        //   通道落地(评审 #2: 第 3 层能到第二可见位)。
        let rotationLayerOrder: [Int64]? = rotationActive
            ? ConflictLayoutEngine.applyLayerRotation(baselineOrderIds, rotationStep!)
            : nil
        // 布局现算(引擎零缓存承诺)——override 变化即重排;hidden 与渲染同一裁剪空间。
        // ← Android :478-480: topOverrideId 原样传, layerOrderOverride 非空时引擎内
        //   优先生效(两通道互斥), 轮换激活时不折叠成单一 topId。
        let laid = ConflictLayoutEngine.layoutCluster(
            cluster, style: style, topOverrideId: topOverrideId, maxNode: maxNode,
            layerOrderOverride: rotationLayerOrder)
        // 绘制集: 与原单卡循环同一过滤 — issue#23: 边缘节点用 slotIndexOf ≥ 0 替代
        // 旧 startNode ∈ [1, maxNode],否则 第 0 节 / 第 N+1 节 课会在簇内被静默吞掉。
        // timeSlots 为空(旧调用方)= 退回旧行为,数据脏课被显式过滤仍兜底。
        let slotIndexOf: (Int) -> Int = timeSlots.isEmpty
            ? { node in (1...maxNode).contains(node) ? node - 1 : -1 }
            : { node in timeSlots.firstIndex { $0.nodeStart == node } ?? -1 }
        let drawList = laid.filter { slotIndexOf($0.course.startNode) >= 0 }
        // ← Kotlin ConflictCard.kt:491 `if (drawList.isEmpty()) return` — 必须在
        //   topLaid/drawList[0] 求值之前: 全簇出界(边缘节点过滤后)时整簇安全跳过,
        //   否则下方 `?? drawList[0]` 触发 Array index out of range trap。
        if drawList.isEmpty {
            // Kotlin return@Composable → EmptyView;外层 ZStack 空占位无害
            return AnyView(EmptyView())
        }
        // v7.10.16r 图层模型统一(评审 #5): 轮换/徽标/切换闸门共用「全量簇的层数」,
        // 不再从 drawList 重算 chainGroups(出界过滤会让两模型分歧)。徽标「+N」= 层数-2
        // (评审 #3: 按层计,轮换中恒定;默认两层已显示,三层 +1 / 四层 +2)。
        let layerCount = clusterLayerCount
        let hiddenLayerN = ConflictLayoutEngine.hiddenLayerCount(layerCount)   // ← Android :497
        let showBadgeV = ConflictLayoutEngine.conflictShowBadge(layerCount, hiddenLayerN)
        // ← chainGroups 从簇全量课推导(评审 #5): 层归属/层代表/折角资格同一模型
        let chainGroups = ConflictLayoutEngine.chainGroups(cluster.courses)
        // 绘制序: 非顶卡(zRank 降序) → 顶卡 → hidden 课 Mark 命中区(overlay 层)
        let drawOrder = ConflictLayoutEngine.overlayMarkOrder(drawList)
        // 顶层判定(与 overlayMarkOrder 兜底同源)
        let topLaid = drawList.first { $0.zRank == 0 } ?? drawList[0]
        let topCourse = topLaid.course
        let hiddenItems = drawList.filter { $0.hidden }
        // 簇级形态(v5/v7.8): fold 回落资格 = 首图层 size≥2(链组一起折角)
        let topLayer = chainGroups.first ?? []
        let foldEligible = !drawList.isEmpty && topLayer.count >= 2
        let form = ConflictLayoutEngine.clusterForm(
            style: style,
            firstHiddenVariant: hiddenItems.first?.variant,
            foldEligible: foldEligible)
        let courseById = Dictionary(uniqueKeysWithValues: drawList.map { ($0.course.id, $0.course) })
        // 簇几何(分数行域, issue#23 §5): ownTime 课按真实分钟比例, 常规课整格吸附。
        // 整簇基点 = 主课判定序首位课(override 不改变该锚点)。
        let baseCourse = cluster.courses.first!
        let clampedSteps: [Int64: Int] = Dictionary(uniqueKeysWithValues: drawList.map { laidItem in
            let sIdx = slotIndexOf(laidItem.course.startNode)
            // issue#23: 步长上限按 timeSlots 剩余行数算,边缘节点也走同一公式
            // (maxNode - startNode + 1 在 startNode > maxNode 时会变 ≤ 0,导致 edge 课被压成 1 节)
            let maxStep = sIdx < 0 ? max(laidItem.course.step, 1) : max(timeSlots.count - sIdx, 1)
            return (laidItem.course.id, min(max(laidItem.course.step, 1), maxStep))
        })
        // 每课行几何 (startRowFrac, ownRowsFrac): ownTime 且时间可解析 → 分钟比例;
        // 否则整格吸附(起点=槽位行号, 行数=clamp 后步长)
        let rowGeomOf: [Int64: (start: Double, rows: Double)] =
            Dictionary(uniqueKeysWithValues: drawList.map { laidItem in
                let c = laidItem.course
                if c.ownTime && !c.startTime.isEmpty && !c.endTime.isEmpty,
                   let f = TimeTableUtils.timeToFractionalRows(c.startTime, c.endTime, slots: timeSlots) {
                    return (c.id, (f.0, f.1 - f.0))
                }
                let sIdx = Double(max(slotIndexOf(c.startNode), 0))
                return (c.id, (sIdx, Double(clampedSteps[c.id] ?? 1)))
            })
        let baseRowFrac = rowGeomOf[baseCourse.id]?.start
            ?? Double(max(slotIndexOf(baseCourse.startNode), 0))
        let minStartRow = rowGeomOf.values.map(\.start).min() ?? baseRowFrac
        let maxEndRow = rowGeomOf.values.map { $0.start + $0.rows }.max() ?? baseRowFrac + 1
        let clusterH = CGFloat(spanDpOf?(minStartRow, maxEndRow)
                               ?? Double(rowH) * (maxEndRow - minStartRow)) - gapH
        // 簇内容相对锚点(cardY=yOfRows(base))的上移量: yOfRows(minStart)−yOfRows(base) ≤ 0。
        // 注: Android 81a42eef 此处 spanDpOf(minStart,base) 符号写反(与 fallback 相反),
        // iOS 按 fallback/历史语义的正确符号实现(base→minStart 的跨度)。
        let clusterYOffset = CGFloat(spanDpOf?(baseRowFrac, minStartRow)
                                     ?? Double(rowH) * (minStartRow - baseRowFrac))
        // v6: 顶卡收窄量 = 用户设置(用户 2026-09-04 拆分: STACK/RAIL 独立配置不共享),滑杆 4..20dp
        let topInset = form == .rail
            ? AppPrefs.shared.getConflictRailInset()
            : AppPrefs.shared.getConflictStackInset()
        // v7.10.16o: 折角幅度 = 用户拖杆设置(8..28dp)
        let foldSize = AppPrefs.shared.getConflictFoldSize()
        // v7.8 图层归属: 图层序号 → 该层整层代表 id
        var layerOfId: [Int64: Int] = [:]
        for (gi, g) in chainGroups.enumerated() { for c in g { layerOfId[c.id] = gi } }
        var layerRepId: [Int: Int64] = [:]
        for (gi, g) in chainGroups.enumerated() {
            layerRepId[gi] = layerRepIdOfCourse[g.first!.id] ?? g.first!.id
        }
        // v7.8: 拼条态仅用于 FOLD flap 绘制,不影响 rect 几何
        let chainStripActive = topLaid.chainFront

        // ---- 局部渲染辅助(依赖 body 局部量,以闭包内联) ----
        // issue#22: 同名课程多地点 — 传 cluster 全行作为 groupRows,支持 AUTO/CUSTOM 模式取色
        let groupRowsForCard = cluster.courses
        func courseColorOf(_ course: CourseEntity) -> Color {
            var bg = CourseColorUtil.pickCourseColorSwiftUIWithGroupRows(
                course, groupRows: groupRowsForCard, isDark: isDark,
                neutralColor: colors.surfaceVariant,
                colorless: AppPrefs.shared.isCourseColorless(),
                persistedHue: CourseHueStore.hueFor(groupId: course.groupId))
            if isGrey { bg = bg.opacity(SleepyTheme.Alpha.inactive) }
            return bg
        }
        func cardYOf(_ courseId: Int64) -> CGFloat {
            let g = rowGeomOf[courseId]?.start ?? 0
            return CGFloat(spanDpOf?(minStartRow, g) ?? Double(rowH) * (g - minStartRow))
        }
        func cardHOf(_ courseId: Int64) -> CGFloat {
            let g = rowGeomOf[courseId] ?? (0, 1)
            let span = spanDpOf?(g.start, g.start + g.rows) ?? Double(rowH) * g.rows
            return CGFloat(max(span, Double(rowH) * 0.3)) - gapH
        }
        func layerRepOf(_ courseId: Int64) -> Int64? { layerOfId[courseId].flatMap { layerRepId[$0] } }
        func rectOf(_ course: CourseEntity, isFront: Bool) -> ConflictLayoutEngine.ConflictRect {
            let g = rowGeomOf[course.id] ?? (Double(max(slotIndexOf(course.startNode), 0)), 1)
            return ConflictLayoutEngine.conflictCardRectFrac(
                startRowFrac: g.start,
                ownRowsFrac: g.rows,
                isTop: isFront,
                form: form,
                colW: Double(colW), rowH: Double(rowH), gapH: Double(gapH),
                minStartRow: minStartRow, topInset: topInset, spanDpOf: spanDpOf)
        }
        func switchTap(_ n: Int, _ fallbackRepId: Int64) {
            if n >= 3 { onRotate() } else { onPickTop(fallbackRepId) }
        }
        // 绘制序单项(hidden/顶卡/沉底卡)
        func renderItem(_ item: ConflictLayoutEngine.CourseDrawItem) -> AnyView {
            switch item {
            case .card(let l):
                let course = l.course
                let isFrontCard = l.chainFront || l.zRank == 0
                let cardIsFolded = form == .fold && (l.chainFront || l.zRank == 0)
                if isFrontCard {
                    let r = rectOf(course, isFront: true)
                    return AnyView(ConflictCourseCard(
                        course: course, onClick: { onCourseClick(course) },
                        isDark: isDark, isGrey: isGrey,
                        folded: cardIsFolded && !l.hidden,
                        foldSize: foldSize, corner: cardCorner,
                        groupRows: groupRowsForCard)
                        .frame(width: CGFloat(r.width), height: CGFloat(r.height))
                        .offset(x: CGFloat(r.x), y: CGFloat(r.y)))
                }
                // 沉底卡: 点击 = N≥3 轮换推进;否则该课所在层整层上移
                // v7.10.16m: FOLD 端态沉底(hidden)不渲染真卡 — 只留透明命中区
                let r = rectOf(course, isFront: false)
                if form == .fold && l.hidden {
                    return AnyView(Button {
                        switchTap(layerCount, layerRepOf(course.id) ?? course.id)
                    } label: {
                        Color.clear
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(SleepyButtonStyle())
                    .frame(width: CGFloat(r.width), height: CGFloat(r.height))
                    .offset(x: CGFloat(r.x), y: CGFloat(r.y)))
                }
                return AnyView(ConflictCourseCard(
                    course: course,
                    onClick: { switchTap(layerCount, layerRepOf(course.id) ?? course.id) },
                    isDark: isDark, isGrey: isGrey,
                    folded: false, foldSize: foldSize, corner: cardCorner,
                    groupRows: groupRowsForCard)
                    .frame(width: CGFloat(r.width), height: CGFloat(r.height))
                    .offset(x: CGFloat(r.x), y: CGFloat(r.y)))
            case .mark(let hiddenId, let variant):
                // Mark = hidden 课的命中区(v7.8: 点击 = 层代表置顶/轮换)
                guard let hiddenCourse = courseById[hiddenId], variant != .noMark
                else { return AnyView(EmptyView()) }
                return AnyView(markHit(hiddenCourse, variant: variant))
            }
        }
        // hidden 课命中区(v7.8.4: RAIL 复用 STACK 右下;FOLD 锚顶卡右上与 flap 同锚)
        func markHit(_ hiddenCourse: CourseEntity, variant: ConflictVariant) -> AnyView {
            switch variant {
            case .stack, .rail:
                let g = rowGeomOf[hiddenCourse.id] ?? (Double(max(slotIndexOf(hiddenCourse.startNode), 0)), 1)
                let hit = ConflictLayoutEngine.conflictMarkRectFrac(
                    startRowFrac: g.start,
                    ownRowsFrac: g.rows,
                    form: .stack,
                    colW: Double(colW), rowH: Double(rowH), gapH: Double(gapH),
                    minStartRow: minStartRow, spanDpOf: spanDpOf)
                return AnyView(Button {
                    switchTap(layerCount, layerRepOf(hiddenCourse.id) ?? hiddenCourse.id)
                } label: {
                    Color.clear
                        .contentShape(Rectangle())
                }
                .buttonStyle(SleepyButtonStyle())
                .frame(width: CGFloat(hit.width), height: CGFloat(hit.height))
                .offset(x: CGFloat(hit.x), y: CGFloat(hit.y)))
            case .fold:
                let (w, h) = ConflictLayoutEngine.foldSwitchHitArea(
                    .fold, cardWidth: Double(colW), cardHeight: Double(clusterH), foldSize: foldSize)
                let hitW = min(CGFloat(w), colW), hitH = min(CGFloat(h), clusterH)
                return AnyView(Button {
                    switchTap(layerCount, layerRepOf(hiddenCourse.id) ?? hiddenCourse.id)
                } label: {
                    Color.clear
                        .contentShape(Rectangle())
                }
                .buttonStyle(SleepyButtonStyle())
                .frame(width: hitW, height: hitH)
                .offset(x: colW - hitW, y: cardYOf(topCourse.id)))
            case .noMark:
                return AnyView(EmptyView())
            }
        }

        // ZStack 整簇渲染。绘制序消费: 先非顶卡 → 顶卡 → Mark → flap/虚线/徽标 overlay
        return AnyView(
            ZStack(alignment: .topLeading) {
                ForEach(Array(drawOrder.enumerated()), id: \.offset) { _, item in
                    renderItem(item)
                }
                // ---- FOLD flap 视觉(v6 簇级/v7.4 逐成员)+ 折角切换命中区(v7.10.16h 双向挂载)
                if form == .fold {
                    let flapHosts: [CourseEntity] = chainStripActive
                        ? drawList.filter { ($0.chainFront && !$0.hidden) || $0.zRank == 0 }.map { $0.course }
                        : [topCourse]
                    let nextLayerIndex = layerRepId.keys.sorted().count > 1
                        ? layerRepId.keys.sorted()[1] : nil
                    let switchTarget = nextLayerIndex.flatMap { layerRepId[$0] }
                    let markPresent = !hiddenItems.isEmpty
                    ForEach(Array(flapHosts.enumerated()), id: \.offset) { _, host in
                        FoldFlap(fold: foldSize, corner: foldFlapCorner,
                                 color: foldFlapColor(courseColorOf(host)))
                            .frame(width: foldSize, height: foldSize)
                            .offset(x: colW - foldSize - 2, y: cardYOf(host.id) + 2)
                        // v7.10.16m 双向挂载: 切走后折角区域仍可点切回;经典双课态 Mark 在场不重复叠
                        if !markPresent, let target = switchTarget {
                            let (w, h) = ConflictLayoutEngine.foldSwitchHitArea(
                                .fold, cardWidth: Double(colW), cardHeight: Double(clusterH), foldSize: foldSize)
                            let hitW = min(CGFloat(w), colW), hitH = min(CGFloat(h), clusterH)
                            Button {
                                switchTap(layerCount, target)
                            } label: {
                                Color.clear
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(SleepyButtonStyle())
                            .frame(width: hitW, height: hitH)
                            .offset(x: colW - hitW, y: cardYOf(host.id))
                        }
                    }
                }
                // ---- FOLD 虚线轮廓: hidden 课唯一存在形式(v7.10.16o: 全遮/部分遮一律画)
                if form == .fold {
                    ForEach(hiddenItems, id: \.course.id) { hid in
                        let hidH = cardHOf(hid.course.id)
                        DashOutlineShape(color: conflictBorderColor(courseColorOf(hid.course)),
                                         corner: cardCorner,
                                         border: cardBorder,
                                         dashLen: dashLen, dashGap: dashGap)
                            .frame(width: colW - 4, height: hidH - 4)
                            .offset(x: 2, y: cardYOf(hid.course.id) + 2)
                    }
                }
                // ---- N 徽标(图层 N≥3 且存在被盖层): overlay 右上,+层数-2(评审#3 按层计)
                if showBadgeV {
                    let styleIsFold = form == .fold
                    ConflictBadge(hiddenLayerN: hiddenLayerN, onClick: { showPicker = true })
                        .offset(x: styleIsFold ? -(foldSize + 4) : -2, y: 2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
            }
            .frame(width: colW, height: clusterH, alignment: .topLeading)
            .offset(y: clusterYOffset)
            .sheet(isPresented: $showPicker) {
                ConflictCoursePickerSheet(
                    courses: drawList.map { $0.course },
                    // ← Android (rotationLayerOrder ?: baselineOrderIds).first(): 轮换顶层,
                    //   否则置顶感知基准序顶层(= topOverrideId 所在层代表)
                    layerRepIdOfCourse: layerRepIdOfCourse,
                    topRepId: (rotationLayerOrder ?? baselineOrderIds).first ?? 0,
                    onDismiss: { showPicker = false },
                    onPick: { id in
                        showPicker = false
                        if clusterLayerCount >= 3 {
                            // v7.10.16r: 气泡选课 = 「换来看」— 轮换步数使该层转到基准
                            // 首位(会话态);target=0 = 清轮换回基准,语义自洽
                            let repId = layerRepIdOfCourse[id] ?? id
                            if let target = baselineOrderIds.firstIndex(of: repId) {
                                onPickFromBadge(target)
                            }
                        } else {
                            onPickTop(id)
                        }
                    })
                    .sheetDetents([.medium])
            }
        )
    }
}

/// FOLD flap 三角 — 折痕 (0,0)→(f,f),内折角保留圆角意象(← Canvas flap Path)
private struct FoldFlap: Shape {
    var fold: CGFloat
    var corner: CGFloat
    var color: Color

    func path(in rect: CGRect) -> Path {
        let f = rect.width
        let c = corner
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))                  // 折痕上端(卡顶边)
        p.addLine(to: CGPoint(x: f, y: f))               // 折痕下端(卡右边)
        p.addLine(to: CGPoint(x: c, y: f))
        p.addQuadCurve(to: CGPoint(x: 0, y: f - c),
                       control: CGPoint(x: 0, y: f))     // 内折角圆角
        p.closeSubpath()
        return p
    }
}

/// FOLD 虚线轮廓 — 被遮底课的真实占位提示(圆角虚线框,不接点击)
private struct DashOutlineShape: View {
    let color: Color
    let corner: CGFloat
    let border: CGFloat
    let dashLen: CGFloat
    let dashGap: CGFloat

    var body: some View {
        Canvas { context, size in
            var p = Path()
            p.addRoundedRect(in: CGRect(origin: .zero, size: size),
                             cornerSize: CGSize(width: corner, height: corner))
            context.stroke(
                p,
                with: .color(color),
                style: StrokeStyle(lineWidth: border, dash: [dashLen, dashGap]))
        }
    }
}

/**
 * 簇内单课真卡(← ConflictCourseCard) — 取色/灰显/文案逻辑与 CourseOverlayCard 对齐。
 * 视觉修订 v4: shape 可注入(FOLD 折角剪裁形);自派生 1dp 细描边(每张真卡各一层)。
 */
private struct ConflictCourseCard: View {
    @Environment(\.localWakeUpColors) private var colors
    let course: CourseEntity
    let onClick: () -> Void
    let isDark: Bool
    var isGrey: Bool = false
    /// FOLD 折角剪裁(右上缺角)
    var folded: Bool = false
    var foldSize: CGFloat = 16
    var corner: CGFloat = 12
    /// issue#22: 同 groupId 全行(AUTO 模式按行序算 hue; 不传 = 退化为单行 groupRows)
    var groupRows: [CourseEntity] = []

    var body: some View {
        let effRows = groupRows.isEmpty ? [course] : groupRows
        let bg = CourseColorUtil.pickCourseColorSwiftUIWithGroupRows(
            course, groupRows: effRows, isDark: isDark,
            neutralColor: colors.surfaceVariant,
            colorless: AppPrefs.shared.isCourseColorless(),
            persistedHue: CourseHueStore.hueFor(groupId: course.groupId))
        let fg = CourseColorUtil.textColorOn(bg: bg, isDark: isDark, onSurface: colors.onSurface)
        let effectiveBg = isGrey ? bg.opacity(SleepyTheme.Alpha.inactive) : bg
        let effectiveFg = isGrey ? fg.opacity(SleepyTheme.Alpha.inactive) : fg
        let textDecoration = isGrey && AppPrefs.shared.getHolidayStyle() == "strikethrough"
        let subInfo = AppPrefs.shared.getGridSubInfo()
        // issue#26: 冲突卡属网格场景 — 跟随网格别名开关(与 CourseOverlayCard 同步)
        // ← Android ConflictCard.kt:996 CourseDisplayUtil.displayName(course, isGridUseAlias)
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
                if subText.isBlank {
                    Text(name)
                        // ← Android labelSmall.copy(SemiBold, 10sp, lineHeight 13sp)
                        //   + textAlign = Center + align(Center)(:1016-1021): 多行逐行居中
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(effectiveFg)
                        .strikethrough(textDecoration)
                        .lineSpacing(1)
                        .lineLimit(6)
                        .minimumScaleFactor(0.6)
                        .allowsTightening(true)
                        .multilineTextAlignment(.center)
                } else {
                    VStack(spacing: 0) {
                        Text(name)
                            // ← Android labelSmall.copy(SemiBold, 10sp, lineHeight 13sp), textAlign 默认 Start
                            //   (有副信息分支: 无 textAlign=Center、无 align(Center),:1028-1040 —— 多行逐行左对齐)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(effectiveFg)
                            .strikethrough(textDecoration)
                            .lineSpacing(1)
                            .lineLimit(6)
                            .minimumScaleFactor(0.6)
                            .allowsTightening(true)
                            .frame(maxHeight: .infinity)
                        Text(subText)
                            .font(SleepyTextStyle.micro())
                            .foregroundColor(effectiveFg.opacity(SleepyTheme.Alpha.highContent))
                            .strikethrough(textDecoration)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                            .allowsTightening(true)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(SleepyButtonStyle())
        .padding(4)
        .background(effectiveBg)
        .clipShape(ConflictCardShape(folded: folded, fold: foldSize, corner: corner))
        .overlay(
            // 1dp 细描边,FOLD 时也沿折角剪裁形走
            ConflictCardShape(folded: folded, fold: foldSize, corner: corner)
                .stroke(conflictBorderColor(effectiveBg), lineWidth: cardBorder)
        )
        .padding(2)
    }
}

/// N 徽标(N≥3) — 右上角小气泡;文案 = 「+层数-2」(三层 +1 / 四层 +2,按层计不按课数)
private struct ConflictBadge: View {
    @Environment(\.localWakeUpColors) private var colors
    let hiddenLayerN: Int
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            Text("+\(hiddenLayerN)")
                .font(.system(size: badgeFont, weight: .medium))
                .foregroundColor(colors.onSurface)
                .lineLimit(1)
                // ← Android 单位数固定 14dp 圆形 / 两位数固定 14×23.8 胶囊,无水平 padding
                .frame(width: (0...9).contains(hiddenLayerN) ? badgeSize : badgeSize * 1.7,
                       height: badgeSize)
        }
        .buttonStyle(SleepyButtonStyle())
        .background(Capsule().fill(colors.surface))
        .accessibilityIdentifier("conflict_badge")
    }
}

/// N 徽标点选弹窗(← AlertDialog → iOS sheet) — 列簇内全部课课名点选
private struct ConflictCoursePickerSheet: View {
    @Environment(\.localWakeUpColors) private var colors
    let courses: [CourseEntity]
    // ← Android ConflictCoursePickerDialog(layerRepIdOfCourse, topRepId): 顶层行
    //   primaryContainer/onPrimaryContainer + 层代表 Check;仅视觉高亮用
    let layerRepIdOfCourse: [Int64: Int64]
    let topRepId: Int64
    let onDismiss: () -> Void
    let onPick: (Int64) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.format("import_conflicts"))
                // ← Android M3 AlertDialog title 默认走 titleLarge;SleepyTypography
                //   覆写 titleLarge = 22sp(Theme.kt:268)。此前 24(headlineSmall 误标)。
                .font(.system(size: 22))
                .foregroundColor(colors.onSurface)
                .padding(.bottom, 8)
            ScrollView {
                // ← Android Column .heightIn(max = 360.dp).verticalScroll(:1113-1117)
                //   — 内容高上限 360dp,课程多时可视列表高度与 Android 一致
                VStack(spacing: 4) {
                    ForEach(courses) { course in
                        Button {
                            onPick(course.id)
                        } label: {
                            let repId = layerRepIdOfCourse[course.id] ?? course.id
                            let isTopLayer = repId == topRepId
                            HStack(spacing: 0) {
                                Text(course.courseName)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(isTopLayer ? colors.onPrimaryContainer : colors.onSurface)
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if repId == course.id && isTopLayer {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 18))
                                        .foregroundColor(colors.primary)
                                }
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 8)
                            .background(isTopLayer ? colors.primaryContainer : colors.surfaceContainer)
                            .cornerRadius(SleepyShapes.small)
                        }
                        .buttonStyle(SleepyButtonStyle())
                        .accessibilityLabel(course.courseName)
                    }
                }
            }
            // ← Android .heightIn(max = 360.dp) — ScrollView 可视高度上限 360
            .frame(maxHeight: 360, alignment: .top)
        }
        .padding(20)
        .background(colors.surface)
        .modifier(SleepyThemeProvider(darkTheme: false, themeKey: ""))
    }
}

