// ScheduleScreen.swift — ← ui/screen/schedule/ScheduleScreen.kt
// 课表页: TopBar(周导航+跳周菜单+撤回/取消撤回胶囊+行高缩放 tick) + 视图切换(周视图/网格, 可隐藏) +
// 左右滑翻周(TabView pager, 含 issue#44 调休渲染期换日) + 详情 BottomSheet。
// 空态两分支: 无表 → EmptyState; 有表无课 → NoCourseState。

import SwiftUI

enum ViewMode: Hashable {
    case full   // ← ViewMode.Full (周视图)
    case cards  // ← ViewMode.Cards (网格)
}

struct ScheduleScreen: View {
    @Environment(\.localWakeUpColors) private var colors
    @ObservedObject var viewModel: ScheduleViewModel
    // ← 原版本 b96c865b: 视图模式提升到 AppRoot 会话层(切 tab/开 overlay 不再弹回启动默认),
    // 顶部手动切换只改会话态, 不回写启动偏好(KEY_START_VIEW 既有分离设计)
    @Binding var viewMode: ViewMode
    var onGoImport: () -> Void = {}
    var onManualAdd: () -> Void = {}
    var onCreateTable: () -> Void = {}
    var onEditCourse: (CourseEntity) -> Void = { _ in }
    /// 与原版本 onAddAt 同序：tableId、展示周、星期、起始节、连续节数。
    var onAddAt: ((Int64, Int, Int, Int, Int) -> Void)? = nil
    @StateObject private var quickAdd = QuickAddCourseState()

    // 2026-09-21 用户令: 撤回/取消撤回按钮显隐实时订阅 ← 原版本 TopBar 内直读
    // UndoManager.hasSnapshot/hasRedoSnapshot(Compose mutableStateOf → ObservableObject,
    // 槽变 objectWillChange 即刷顶栏, 不必等其他状态变化带动重算)
    @ObservedObject private var undoManager = UndoManager.shared

    @State private var selectedCourse: CourseEntity? = nil
    @State private var selectedCourseDate: Date? = nil
    @State private var selectedCourseWeek = 1
    // v7.10.16 / 2026-09-21: 无可撤回/无可重做时 toast(按钮不隐藏保持布局稳定)。
    // 文案 + 单调 token: 连点同款文案也能重启消失计时(Toast 每次重发)
    @State private var toastMessage: String? = nil
    @State private var toastToken = 0
    // v7.10.14 顶栏 logo → 课表切换弹窗
    @State private var showTableSwitcher = false
    // v7.10.7 顶栏分享 → 格式选择弹层
    @State private var showShareSheet = false
    // ← 原版本 跳周 DropdownMenu(menuOpen): 自绘 ZStack 浮层呈现 280pt chip 网格
    @State private var showWeekJumpMenu = false

    // v7.10.5 + v7.10.16r(评审#4): 会话级置顶 override / 簇轮换步数 — 与原实现
    // ScheduleScreen.kt L106-112 同级持有点(本视图), HorizontalPager 翻页/周切换不丢,
    // 纯会话级不落盘, 离开课表页即重置。此前 iOS 压在每页 CardsGridView 缺省参数上,
    // 同簇换层/轮换步数翻页即丢(issue F106-9)。
    @State private var topOverrides: [String: Int64] = [:]
    @State private var rotationSteps: [String: Int] = [:]
    func setTopOverride(key: String, courseId: Int64?) {
        if let courseId { topOverrides[key] = courseId } else { topOverrides.removeValue(forKey: key) }
    }
    func setRotationStep(key: String, step: Int) {
        if step <= 0 { rotationSteps.removeValue(forKey: key) } else { rotationSteps[key] = step }
    }

    // 双指行高缩放 (2026-09-16 用户令, ← ScheduleScreen.kt L126-130): 初始=上次 tick 确认的
    // 持久值; 捏合只改会话值, 顶栏 tick=落盘长期生效, 切表时回到该表确认值
    // (remember(state.selectedTableId) { AppPrefs.getGridRowScale } 语义)。
    @State private var rowHeightScale: CGFloat = AppPrefs.shared.getGridRowScale()
    @State private var savedRowScale: CGFloat = AppPrefs.shared.getGridRowScale()
    // scaleUncommitted = abs(rowHeightScale - savedRowScale) > 0.001f ← L130
    private var scaleUncommitted: Bool { abs(rowHeightScale - savedRowScale) > 0.001 }

    var body: some View {
        let state = viewModel.state
        let displayMode = AppPrefs.shared.getDisplayMode()
        let showDate = AppPrefs.shared.isShowDate()
        let visibleDays = AppPrefs.shared.getVisibleDays()

        let hasTable = !state.tables.isEmpty
        let hasCourses = !state.courses.isEmpty

        VStack(spacing: 0) {
            if !hasTable {
                // 真的没表: 去创建
                EmptyState(onGoImport: onGoImport, onCreateTable: onCreateTable)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            } else if !hasCourses {
                // 有表无课: 加课/导入
                NoCourseState(tableName: state.currentTable?.name ?? "",
                              onAddCourse: onManualAdd, onImport: onGoImport)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            } else {
                ScheduleTopBar(
                    currentWeek: state.selectedWeek,
                    // v1.0.62 B5b: 跳周菜单上限并入调休目标周 ← 原版本 TopBar(maxWeek = state.displayMaxWeek)
                    maxWeek: state.displayMaxWeek,
                    startDate: state.currentTable?.startDate ?? "",
                    // ← 原版本 TopBar(displayContext = state.weekDisplayContext):
                    // actualWeek/semesterStatus 优先取 VM 展示上下文(最近有课日逻辑),
                    // 表头不再与 VM 判定分叉(issue F106-8)
                    displayContext: state.weekDisplayContext,
                    onPrevWeek: { viewModel.changeWeek(state.selectedWeek - 1) },
                    onNextWeek: { viewModel.changeWeek(state.selectedWeek + 1) },
                    onJumpToActual: {
                        guard let start = state.currentTable?.startDate else { return }
                        viewModel.changeWeek(DateUtils.currentWeek(startDate: start))
                    },
                    onSelectWeek: { week in viewModel.changeWeek(week) },
                    onUndo: {
                        // v7.10.16: 任何课表数据改动可一键撤销一次
                        if !viewModel.undoLastChange() { showToast(L10n.format("schedule_undo_none")) }
                    },
                    onRedo: {
                        // 2026-09-21 用户令: 取消最近一次撤回; 无可重做 → schedule_redo_none
                        if !viewModel.redoLastUndo() { showToast(L10n.format("schedule_redo_none")) }
                    },
                    onSwitchTable: { showTableSwitcher = true },
                    onAddCourse: onManualAdd,
                    onShare: { showShareSheet = true },
                    hasUndoSnapshot: undoManager.hasSnapshot,
                    hasRedoSnapshot: undoManager.hasRedoSnapshot,
                    scaleUncommitted: scaleUncommitted,
                    onScaleCommit: {
                        // 2026-09-16 用户令: tick=落盘长期生效, 会话确认值同步抬齐 → tick 熄灭
                        AppPrefs.shared.setGridRowScale(Double(rowHeightScale))
                        savedRowScale = rowHeightScale
                    },
                    onOpenWeekJump: { showWeekJumpMenu = true })

                // Segmented Switcher — 用户令 2026-09-23: 切换栏可隐藏(AppPrefs show_view_switcher,
                // 默认 true)。隐藏只释放这根 Bar 的空间, 不改 viewMode 与启动默认页。
                // iOS 无 changeBus: 设置页返回后父级重建 → body 重算即生效(AppPrefs.swift:349 同模式)。
                if AppPrefs.shared.isShowViewSwitcher() {
                    SegmentedSwitcher(
                        options: [(ViewMode.full, L10n.format("view_full")),
                                  (ViewMode.cards, L10n.format("view_cards"))],
                        selected: viewMode,
                        onSelect: { viewMode = $0 })
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }

                // 主体视图 — 左右滑动切换周次(TabView pager)
                // v1.0.62 B5b: 翻页页数并入调休目标周 ← 原 pagerMaxWeek = state.displayMaxWeek
                let pagerMaxWeek = max(state.displayMaxWeek, 1)
                WeekPager(viewModel: viewModel, viewMode: viewMode, pagerMaxWeek: pagerMaxWeek,
                          displayMode: displayMode, showDate: showDate, visibleDays: visibleDays,
                          topOverrides: $topOverrides,
                          onSetTopOverride: setTopOverride(key:courseId:),
                          rotationSteps: $rotationSteps,
                          onRotationStep: setRotationStep(key:step:),
                          rowHeightScale: rowHeightScale,
                          onRowHeightScaleChange: { rowHeightScale = $0 },
                          pinchZoomEnabled: AppPrefs.shared.isGridPinchZoom(),
                          dragEnabled: !showWeekJumpMenu && !showTableSwitcher && !showShareSheet && selectedCourse == nil,
                          quickAdd: quickAdd, quickAddEnabled: onAddAt != nil,
                          onQuickAdd: { week, day, node, step in
                              guard let table = state.currentTable else { return }
                              onAddAt?(table.id, week, day, node, step)
                           }) { course, page in
                    selectedCourseWeek = page
                    selectedCourseDate = state.currentTable.flatMap {
                        CourseOccurrences.date(startDate: $0.startDate, week: page, day: course.day)
                    }
                    selectedCourse = course
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(QuickAddOutsidePressShield(state: quickAdd).accessibilityHidden(true))
        .onChange(of: state.selectedWeek) { _ in quickAdd.dismiss() }
        .onChange(of: state.currentTable?.startDate) { _ in quickAdd.dismiss() }
        .onChange(of: selectedCourse?.id) { if $0 != nil { quickAdd.dismiss() } }
        .onChange(of: viewMode) { _ in quickAdd.dismiss() }
        .onChange(of: showWeekJumpMenu) { if $0 { quickAdd.dismiss() } }
        .onChange(of: showTableSwitcher) { if $0 { quickAdd.dismiss() } }
        .onChange(of: showShareSheet) { if $0 { quickAdd.dismiss() } }
        .onDisappear { quickAdd.dismiss() }
        // v7.10.14 课表切换弹窗(← TableSwitcherDialog)
        .sheet(isPresented: $showTableSwitcher) {
            TableSwitcherSheet(
                tables: state.tables,
                selectedTableId: state.selectedTableId,
                onSelect: { id in
                    viewModel.selectTable(id)
                    showTableSwitcher = false
                },
                onDismiss: { showTableSwitcher = false })
        }
        // v7.10.7 顶栏分享 → 格式选择弹层(JSON / 分享文本 / ICS)
        .sheet(isPresented: $showShareSheet) {
            if let table = state.effectiveCurrentTable {
                ShareScheduleSheet(table: table, courses: state.courses,
                                   onDismiss: { showShareSheet = false })
            }
        }
        // ← 原版本 Toast schedule_undo_none / schedule_redo_none(同一浮层位, 文案随触发源变)
        .overlay(alignment: .bottom) {
            if let toastMessage {
                Text(toastMessage)
                    .font(.system(size: 14, weight: .medium)) // ← 原 Snackbar bodyMedium 14
                    .foregroundColor(colors.onSurface)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(colors.surfaceContainerHigh)
                    .cornerRadius(SleepyShapes.large)
                    .padding(.bottom, 24)
                    .transition(.opacity)
                    // 原生并发取消语义: id 变化自动取消旧计时,连发不误杀(← asyncAfter)。
                    // id=toastToken(单调递增)而非文案: 连点撤回两次同款文案也要重起计时
                    .task(id: toastToken) {
                        try? await Task.sleep(nanoseconds: 1_800_000_000)
                        guard !Task.isCancelled else { return }
                        withAnimation { self.toastMessage = nil }
                    }
            }
        }
        // ← 原版本 remember(state.selectedTableId) { AppPrefs.getGridRowScale }:
        // 切表回到持久确认值(会话未落盘捏合不跨表携带)
        .onChange(of: state.selectedTableId) { _ in
            quickAdd.dismiss()
            let persisted = CGFloat(AppPrefs.shared.getGridRowScale())
            savedRowScale = persisted
            rowHeightScale = persisted
        }
        // ← 原版本 跳周 DropdownMenu: 自绘 ZStack 浮层(与仓库浮层容器同款模式),
        //   280pt 面板 + 圆形周 chip 网格, 点击即选即关, 点面板外任意处关闭。
        .overlay(alignment: .top) {
            if showWeekJumpMenu {
                // v1.0.62 B5b: 跳周 chip 网格上限同 displayMaxWeek ← 原版本 TopBar 内 DropdownMenu 同参
                WeekJumpMenu(currentWeek: state.selectedWeek,
                             maxWeek: state.displayMaxWeek,
                             onSelect: { week in
                                 viewModel.changeWeek(week)
                                 showWeekJumpMenu = false
                             },
                             onDismiss: { showWeekJumpMenu = false })
                    .padding(.top, 56)   // 锚在顶栏周胶囊正下方
            }
        }
        // 详情 Bottom Sheet
        .sheet(item: $selectedCourse) { course in
            // v1.0.62 B5b: 详情页聚簇同域 ← 原 allCourses = 逐日 coursesForDate 投影:
            // 调休周里补班日列的课(投影 day)与放假日空列都按同一渲染域参与聚簇, 幽灵/漏簇同修。
            let detailAllCourses: [CourseEntity] = state.currentTable.map { table in
                (1...7).flatMap { day -> [CourseEntity] in
                    guard let date = CourseOccurrences.date(startDate: table.startDate,
                                                            week: selectedCourseWeek, day: day) else { return [] }
                    return HolidayTransferOps.coursesForDate(
                        date, startDate: table.startDate, maxWeek: table.maxWeek,
                        courses: state.courses, transfers: state.transfers
                    ).map { c -> CourseEntity in
                        var projected = c
                        projected.day = day
                        return projected
                    }
                }
            } ?? []
            return CourseDetailSheet(
                course: course,
                timeString: course.nodeString(),
                // v7.10.16q: allCourses 必须与网格同周域 —
                // 周次不相交同行(如周1-4/周6-13)全量传会被当成同时存在 → 幽灵图层
                allCourses: detailAllCourses,
                onEdit: { c in
                    selectedCourse = nil
                    // v1.0.62 B5b: 编辑回传库内原始行 ← 原版本 onEditCourse(firstOrNull(id) ?: course) —
                    // 投影替身(day 已改写)不落库, 按 id 找回原始行
                    onEditCourse(state.courses.first { $0.id == c.id } ?? c)
                },
                // issue#40: 详情页时间域与网格同源 = 水合表 effectiveCurrentTable
                timeJson: state.effectiveCurrentTable?.timeJson,
                displayDate: selectedCourseDate,
                occurrenceTable: state.effectiveCurrentTable,
                occurrenceRepository: viewModel.occurrenceRepository,
                onOccurrenceSaved: {
                    selectedCourse = nil
                    viewModel.occurrenceSaved()
                })
        }
    }

    private func showToast(_ message: String) {
        toastMessage = message
        toastToken += 1   // 单调 token: 同款文案连点也能重启消失计时
    }
}

// 胶囊挤压测量坐标系 ← 原版本 onGloballyPositioned/positionInParent
private enum CapsuleMeasureSpace { static let name = "scheduleTopBar" }

private struct TripleOriginXKey: PreferenceKey {
    static var defaultValue: CGFloat = .greatestFiniteMagnitude   // 未测得 = 不挤压
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// 2026-09-21 用户令: 撤回/取消撤回一体胶囊 ← UndoRedoCapsule — 体育场形状(左右半圆+中间矩形),
/// 撤回左半·取消撤回右半, 中间一条淡淡竖线。两半由 popup 宿主按 hasUndo||hasRedo 同现同隐,
/// 各半按有无快照 enabled/禁用(alpha 0.38 占位保形)。scale=动态挤压系数(周三件套逼近时缩)。
private struct UndoRedoCapsule: View {
    @Environment(\.localWakeUpColors) private var colors
    let showUndo: Bool
    let showRedo: Bool
    let scale: CGFloat
    let onUndo: () -> Void
    let onRedo: () -> Void

    var body: some View {
        // 几何 ← 原版本: halfSize=32*scale / dividerHeight=14*scale / icon=20*scale
        let halfSize = 32 * scale
        let dividerHeight = 14 * scale
        return HStack(spacing: 0) {
            // 左半: 撤回 — 无可撤回时半透明禁用(占位保形, 双侧共存才像一体胶囊)
            Button(action: onUndo) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 20 * scale))
                    .foregroundColor(colors.onSurfaceVariant.opacity(showUndo ? 1 : 0.38))
                    .frame(width: halfSize, height: halfSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(SleepyButtonStyle())
            .disabled(!showUndo)
            .accessibilityLabel(L10n.format("schedule_undo"))
            .accessibilityIdentifier("undo_button")

            // 中缝: 淡淡竖线 — 与图标同色调降透明度, 视觉上"一体两半"
            Rectangle()
                .fill(colors.onSurfaceVariant.opacity(SleepyTheme.Alpha.inactive))
                .frame(width: 1, height: dividerHeight)

            // 右半: 取消撤回 — 无可重做时半透明禁用
            Button(action: onRedo) {
                Image(systemName: "arrow.uturn.forward")
                    .font(.system(size: 20 * scale))
                    .foregroundColor(colors.onSurfaceVariant.opacity(showRedo ? 1 : 0.38))
                    .frame(width: halfSize, height: halfSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(SleepyButtonStyle())
            .disabled(!showRedo)
            .accessibilityLabel(L10n.format("schedule_redo"))
            .accessibilityIdentifier("redo_button")
        }
        .frame(height: halfSize)
        .background(colors.surfaceContainerHigh)
        .clipShape(Capsule())
    }
}

// HorizontalPager → TabView(.page): 双向同步(手势→VM / VM→pager)
// Cards 网格的 TimeSlot: 每节一行(node/nodeStart 单节, 原版本 同为逐节行)
// ← 原版本 TimeTableUtils.timeSlotsFor(state.effectiveCurrentTable): 时间域真源=水合表,
//   表为 nil → 空表(禁 DEFAULT_TIME_JSON 兜底 — 有表无课才进得本页, 语义与 原版本 对齐)
private func cardTimeSlots(table: TimeTableEntity?) -> [TimeSlot] {
    guard let table else { return [] }
    return TimeTableUtils.renderSlots(timeJson: table.timeJson)
}

// v1.0.62 B5b: 调休渲染改逐日投影 ← ScheduleScreen.kt L290-300 (coursesForDate 版):
// 本页 7 天逐日走 HolidayTransferOps.coursesForDate — 补班日列 = sourceDate 星期的课,
// 放假日列 = 空(课被挪走), 未命中日 = 自然星期; 投影行 day 改写为所在列, 渲染期替身不写库。
// 旧 remapCoursesForTransfers(daySwap 整列搬移)口径废弃: 补班日原课未屏蔽会与调来的课同列叠加。
func renderCoursesForWeek(_ table: TimeTableEntity,
                          week: Int,
                          courses: [CourseEntity],
                          transfers: [HolidayTransferEntry],
                          timeJson: String?,
                          calendar: Calendar? = nil) -> [CourseEntity] {
    return (1...7).flatMap { day -> [CourseEntity] in
        guard let date = CourseOccurrences.date(startDate: table.startDate, week: week, day: day, calendar: calendar) else {
            return []
        }
        return HolidayTransferOps.coursesForDate(
            date, startDate: table.startDate, maxWeek: table.maxWeek,
            courses: courses, transfers: transfers
        ).map { c -> CourseEntity in
            var projected = c
            projected.day = day
            if let tj = timeJson {
                projected = projected.normalizeNode(timeJson: tj)
            }
            return projected
        }
    }
}

private struct WeekPager: View {
    @ObservedObject var viewModel: ScheduleViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var drag = CourseDragContext()
    @State private var dragError = false
    let viewMode: ViewMode
    let pagerMaxWeek: Int
    let displayMode: String
    let showDate: Bool
    let visibleDays: Set<Int>
    // v7.10.5/v7.10.16r: 会话真相源在 ScheduleScreen 持有, 透传到每页网格 ← topOverrides/rotationSteps
    @Binding var topOverrides: [String: Int64]
    let onSetTopOverride: (String, Int64?) -> Void
    @Binding var rotationSteps: [String: Int]
    let onRotationStep: (String, Int) -> Void
    // 双指行高缩放(2026-09-16): 会话 scale 与实验室总开关(默认关=手势不挂, tick 恒不亮)透传
    let rowHeightScale: CGFloat
    let onRowHeightScaleChange: (CGFloat) -> Void
    let pinchZoomEnabled: Bool
    let dragEnabled: Bool
    @ObservedObject var quickAdd: QuickAddCourseState
    let quickAddEnabled: Bool
    let onQuickAdd: (Int, Int, Int, Int) -> Void
    let onCourseClick: (CourseEntity, Int) -> Void

    // 每个 pager 页独立缓存灰显星期 ← 原版本 produceState(greyDays, page, startDate)
    @State private var greyDaysByWeek: [Int: Set<Int>] = [:]
    // 灰显缓存失效闸 ← produceState 键含 state.transfers: 调休映射变 → 全周重算
    @State private var greyCacheSignature = ""

    var body: some View {
        dragPager
            .onChange(of: viewModel.state.selectedTableId) { _ in drag.end() }
            .onChange(of: viewMode) { _ in drag.end() }
            .onChange(of: dragEnabled) { if !$0 { drag.end(); quickAdd.dismiss() } }
            .onChange(of: quickAddEnabled) { if !$0 { quickAdd.dismiss() } }
            .onChange(of: scenePhase) { phase in
                if phase != .active { drag.end(); quickAdd.dismiss() }
            }
            .onDisappear { drag.end() }
            .alert(L10n.t("schedule_drag_failed"), isPresented: $dragError) {
                Button(L10n.t("ok"), role: .cancel) {}
            }
            .task(id: "\(viewModel.state.currentTable?.startDate ?? "")-\(viewModel.state.selectedWeek)-\(pagerMaxWeek)") {
                await refreshGreyDays()
            }
    }

    private var pages: some View {
        let state = viewModel.state
        // VM 变化(TopBar 点击) → 同步 pager(直写 selection); 手势滑动 → changeWeek 回写 VM
        return TabView(selection: Binding(
            get: { min(max(state.selectedWeek, 1), pagerMaxWeek) },
            set: { newWeek in viewModel.changeWeek(newWeek) }   // 手势滑动 → VM
        )) {
            ForEach(1...pagerMaxWeek, id: \.self) { page in
                // page 是 1-based 周索引,独立于 state.currentWeek 过滤课程
                let weekCourses: [CourseEntity] = {
                    let list = state.courses.filter { $0.inWeek(page) }
                    // issue#40: normalizeNode 时间域真源 = 水合表 effectiveCurrentTable
                    // (绑定作息表编辑后立即生效), 不得再读 currentTable.timeJson 旧兼容列
                    guard let tj = state.effectiveCurrentTable?.timeJson else { return list }
                    return list.map { $0.normalizeNode(timeJson: tj) }
                }()
                // v1.0.62 B5b: 调休渲染改 coursesForDate 逐日投影 ← ScheduleScreen.kt L290-300
                // (表缺省回落 weekCourses 原路径; 投影内部已含 normalizeNode 时间域归一)
                let renderCourses = state.currentTable.map {
                    renderCoursesForWeek($0, week: page, courses: state.courses,
                                         transfers: state.transfers,
                                         timeJson: state.effectiveCurrentTable?.timeJson)
                } ?? weekCourses
                Group {
                    switch viewMode {
                    case .full:
                        FullWeekView(courses: renderCourses,
                                     visibleDays: visibleDays,
                                     displayMode: displayMode,
                                     // issue#40: 时间域读水合表 ← 原版本 effectiveCurrentTable?.timeJson ?: ""
                                     timeJson: state.effectiveCurrentTable?.timeJson ?? "",
                                     startDate: state.currentTable?.startDate ?? "",
                                     currentWeek: page,
                                       onCourseClick: { onCourseClick($0, page) },
                                     greyDays: greyDaysByWeek[page] ?? [],
                                     // v1.0.62 B5b: 周视图日期「·M月d日」← 原版本 FullWeekView(showDate = showDate)
                                     showDate: showDate)
                    case .cards:
                        CardsGridView(courses: renderCourses,
                                      timeSlots: cardTimeSlots(table: state.effectiveCurrentTable),
                                      // issue#40 §5: 时间域(含非常规课占位合成)同样以水合表为准
                                      timeJson: state.effectiveCurrentTable?.timeJson ?? "",
                                      visibleDays: visibleDays,
                                      showDate: showDate,
                                      startDate: state.currentTable?.startDate ?? "",
                                      currentWeek: page,
                                      onCourseClick: { onCourseClick($0, page) },
                                      greyDays: greyDaysByWeek[page] ?? [],
                                      // ← 原 allCourses = state.courses(晚间自动收起按全学期判)
                                      allCourses: state.courses,
                                      // 会话级置顶/轮换真相源在 ScheduleScreen — 翻页不丢(v7.10.16r)
                                      topOverrides: topOverrides,
                                      onSetTopOverride: onSetTopOverride,
                                      rotationSteps: rotationSteps,
                                      onRotationStep: onRotationStep,
                                      // 双指行高缩放(2026-09-16)+ 实验室开关(v1.0.56 T3)
                                      rowHeightScale: rowHeightScale,
                                      onRowHeightScaleChange: onRowHeightScaleChange,
                                      pinchZoomEnabled: pinchZoomEnabled,
                                      dragMaxWeek: state.currentTable?.maxWeek ?? 0,
                                      dragTransfers: state.transfers,
                                      quickAddState: quickAdd,
                                      quickAddEnabled: quickAddEnabled && dragEnabled && page == state.selectedWeek,
                                      onQuickAdd: { day, node, step in onQuickAdd(page, day, node, step) })
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .environment(\.courseDragContext, viewMode == .cards ? drag : nil)
                .environment(\.courseDragWeek, page)
                .tag(page)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    private var dragPager: some View {
        let state = viewModel.state
        return pages
        .onPreferenceChange(CourseDropGridKey.self) { drag.grids = $0 }
        .background(NativeCourseDropTarget(drag: drag, week: state.selectedWeek, maxWeek: pagerMaxWeek,
            table: state.effectiveCurrentTable, allCourses: state.courses, transfers: state.transfers,
            enabled: dragEnabled && viewMode == .cards && !dragError && quickAdd.selection == nil,
            onChangeWeek: { week in
                // 拖动驻边直接换周，避免横移动画把落点网格带出手指位置。
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) { viewModel.changeWeek(week) }
            },
            onMove: { source, week, day, node, startTime in
                let success = viewModel.moveDraggedOccurrence(source: source, targetWeek: week,
                    displayDay: day, targetNode: node, targetStartTime: startTime)
                if !success { dragError = true }
                return success
            }))
        .overlay(CourseDragProjection(drag: drag))
        .accessibilityIdentifier("schedule_week_pager")
    }

    // 每页独立计算灰显星期(节假日/周末)。
    private func refreshGreyDays() async {
        let state = viewModel.state
        let start = state.currentTable?.startDate ?? ""
        // issue#44: 灰显要查当前表调休映射(命中映射的放假日那天要上课, 永不灰) ← ScheduleScreen.kt:326
        // issue F106-7: 表 ID 取水合表(effectiveCurrentTable?.id) ← 原版本 同口径
        let tableId = state.effectiveCurrentTable?.id
        guard !start.isEmpty else {
            greyDaysByWeek = [:]
            return
        }
        // ← produceState 键含 state.transfers: 映射变(设置页改完 refreshTransfer)缓存整体作废重算
        let signature = state.transfers.map { DateUtils.fullDate($0.sourceDate) + ">" + DateUtils.fullDate($0.targetDate) }
            .joined(separator: ",")
        if signature != greyCacheSignature {
            greyDaysByWeek = [:]
            greyCacheSignature = signature
        }
        for week in 1...pagerMaxWeek where greyDaysByWeek[week] == nil {
            var grey: Set<Int> = []
            for day in 1...7 {
                if let date = DateUtils.dateOfWeek(startDate: start, week: week, dayOfWeek: day),
                   await HolidayManager.shouldGrey(date, tableId: tableId) {
                    grey.insert(day)
                }
            }
            greyDaysByWeek[week] = grey
        }
    }
}

// ← TopBar
private struct ScheduleTopBar: View {
    @Environment(\.localWakeUpColors) private var colors
    let currentWeek: Int
    let maxWeek: Int
    let startDate: String
    // ← 原版本 displayContext: actualWeek/semesterStatus 优先 VM 展示上下文
    var displayContext: WeekDisplayContext? = nil
    let onPrevWeek: () -> Void
    let onNextWeek: () -> Void
    let onJumpToActual: () -> Void
    let onSelectWeek: (Int) -> Void
    var onUndo: () -> Void = {}
    var onRedo: () -> Void = {}
    var onSwitchTable: () -> Void = {}
    var onAddCourse: () -> Void = {}
    var onShare: () -> Void = {}
    /// 2026-09-21 用户令: 胶囊两半的有无快照(UndoManager 槽订阅) ← hasUndo/hasRedo
    var hasUndoSnapshot: Bool = false
    var hasRedoSnapshot: Bool = false
    /// 2026-09-16 用户令: 捏合未确认时独立 tick 圆钮 ← scaleUncommitted/onScaleCommit
    var scaleUncommitted: Bool = false
    var onScaleCommit: () -> Void = {}
    // ← 原版本 menuOpen=true: 打开跳周 DropdownMenu(浮层由 ScheduleScreen 呈现)
    var onOpenWeekJump: () -> Void = {}

    // 胶囊动态挤压 ← 原版本 centerLeftPx/onGloballyPositioned:
    // 翻页三件套左缘实测 x(初始 +∞ = 未测得不挤压), 与 iOS 仓库同模式(PreferenceKey 测量)
    @State private var tripleOriginX: CGFloat = .greatestFiniteMagnitude

    var body: some View {
        // ← 原版本: actualWeek = displayContext?.actualWeek ?: currentWeek(startDate);
        //   semesterStatus = displayContext?.semesterStatus ?: semesterStatus(startDate, maxWeek)
        let actualWeek = displayContext?.actualWeek
            ?? (startDate.isEmpty ? 1 : DateUtils.currentWeek(startDate: startDate))
        let isOnActual = currentWeek == actualWeek
        let semesterStatus = displayContext?.semesterStatus
            ?? DateUtils.semesterStatus(startDate: startDate, maxWeek: maxWeek)
        // capsuleScale = ((centerLeftPx − 32 − 6 − (scaleUncommitted ? 38 : 0) − 6) / 65).coerceIn(0.65,1)
        // — 周三件套把胶囊挤到左边时按剩余空间缩, 0.65 封底(TopBar 空间紧张)
        let capsuleScale = min(max((tripleOriginX - 32 - 6 - (scaleUncommitted ? 38 : 0) - 6) / 65, 0.65), 1.0)

        // v7.10.12: 三件套改 ZStack 叠加实现屏幕正中 —
        // 旧 Spacer 平衡是在"扣除两侧按钮后的剩余空间"里居中, 视觉偏移;
        // ZStack 叠加让三件套对齐全宽正中, 两侧操作区绝对定位(Box 叠加)。
        ZStack {
            // 翻页三件套(箭头+胶囊+箭头) — 箭头紧贴胶囊, 全宽正中;
            // background 挂在 hug-content HStack 上(在 frame 撑满之前), GeometryReader 上报
            // 居中内容簇左缘 x ← 原版本 onGloballyPositioned{ positionInParent().x }(非撑满后的 0)
            HStack(spacing: 8) {
                pagerTriple(isOnActual: isOnActual, semesterStatus: semesterStatus)   // 见下(week label sheet 挂在胶囊上)
            }
            .background(GeometryReader { proxy in
                Color.clear.preference(key: TripleOriginXKey.self,
                                       value: proxy.frame(in: .named(CapsuleMeasureSpace.name)).minX)
            })
            .frame(maxWidth: .infinity)

            // 最左操作区: logo + 撤回/取消撤回胶囊 + 行高 tick(各自有则现)
            HStack(spacing: 0) {
                WeekNavButton(icon: "calendar", a11yLabel: L10n.format("schedule_switch_table"), onClick: onSwitchTable)
                    .accessibilityIdentifier("switch_table")
                // 2026-09-21 用户令: 一起出现一起消失 — 无 undo 也无 redo 时整胶囊隐藏
                // 宿主持续存在以保留退场；间距随内容收回，隐藏后不留空槽。
                SleepyPopup(visible: hasUndoSnapshot || hasRedoSnapshot) {
                    UndoRedoCapsule(showUndo: hasUndoSnapshot,
                                    showRedo: hasRedoSnapshot,
                                    scale: capsuleScale,
                                    onUndo: onUndo,
                                    onRedo: onRedo)
                        .padding(.leading, 6)
                }
                // 2026-09-16 用户令: tick 单列圆形按钮, 与数据撤回胶囊语义不同互不干涉;
                // tick=落盘长期生效, 胶囊撤回=回到上次确认值
                if scaleUncommitted {
                    WeekNavButton(icon: "checkmark", a11yLabel: L10n.format("schedule_scale_keep"), onClick: onScaleCommit)
                        .accessibilityIdentifier("scale_keep")
                        .padding(.leading, 6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 右侧操作区: 加课 + 分享 — 与翻页箭头同款圆形底
            HStack(spacing: 6) {
                WeekNavButton(icon: "plus", a11yLabel: L10n.format("schedule_add_course"), onClick: onAddCourse)
                    .accessibilityIdentifier("topbar_add")
                WeekNavButton(icon: "square.and.arrow.up", a11yLabel: L10n.format("schedule_share_table"), onClick: onShare)
                    .accessibilityIdentifier("topbar_share")
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .coordinateSpace(name: CapsuleMeasureSpace.name)
        .onPreferenceChange(TripleOriginXKey.self) { tripleOriginX = $0 }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(colors.surface)
    }

    // 翻页三件套(箭头+胶囊+箭头); 胶囊点击 = 跳周菜单/一键跳回
    // isOnActual/semesterStatus 由 body 统一算(优先 displayContext)传入 —
    // ← 原版本 TopBar 单点计算, 三件套与表头点击行为共用同一真值
    private func pagerTriple(isOnActual: Bool, semesterStatus: DateUtils.SemesterStatus) -> some View {
        return HStack(spacing: 8) {
            WeekNavButton(icon: "chevron.left", onClick: onPrevWeek)

            // 第 N 周 标签 — 点击行为根据是否在当前实际周而不同
            // ★ 跳周弹层走 ScheduleScreen 顶层 ZStack 浮层(WeekJumpMenu),
            //   ← 原版本 DropdownMenu 280dp FlowRow chip 弹层逐项对齐。
            Button {
                if isOnActual {
                    onOpenWeekJump()
                } else {
                    onJumpToActual()   // 不在实际周 → 一键跳回(原 simultaneousGesture 语义)
                }
            } label: {
                // ★ 学期外: 标签带上周数(学期未开始 · 第 3 周), 翻周时数字跟着变, 用户才知道自己看到第几周
                Text(semesterStatus == .inRange
                     ? L10n.format("schedule_current_week", currentWeek)
                     : "\(L10n.format(semesterStatus == .beforeStart ? "semester_not_started" : "semester_ended")) · \(L10n.format("schedule_week_prefix", currentWeek))")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isOnActual ? colors.onPrimaryContainer : colors.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .allowsTightening(true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
                    .background(isOnActual ? colors.primaryContainer
                                           : colors.primaryContainer.opacity(SleepyTheme.Alpha.inactive))
                    .cornerRadius(SleepyShapes.medium)
            }
            .buttonStyle(SleepyButtonStyle())
            .accessibilityIdentifier("week_label")   // ← G5: 跳周菜单锚点

            WeekNavButton(icon: "chevron.right", onClick: onNextWeek)
        }
    }
}

// v7.10.14 顶栏 logo 点击弹出的课表切换弹层 —
// 列出全部课表, 当前行 primaryContainer 高亮 + 对勾, 点击即切换。
private struct TableSwitcherSheet: View {
    @Environment(\.localWakeUpColors) private var colors
    let tables: [TimeTableEntity]
    let selectedTableId: Int64?
    let onSelect: (Int64) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text(L10n.format("schedule_switch_table"))
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(colors.onSurface)
                .padding(.top, 16)
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(tables) { table in
                        let isCurrent = table.id == selectedTableId
                        Button {
                            onSelect(table.id)
                        } label: {
                            HStack {
                                Text(table.name)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(isCurrent ? colors.onPrimaryContainer : colors.onSurface)
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if isCurrent {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 18))
                                        .foregroundColor(colors.primary)
                                }
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 8)
                            .background(isCurrent ? colors.primaryContainer : colors.surfaceContainer)
                            .cornerRadius(SleepyShapes.small)
                        }
                        .buttonStyle(SleepyButtonStyle())
                        .accessibilityIdentifier("switch_table_\(table.id)")
                    }
                }
                .padding(.horizontal, 16)
            }
            .frame(maxHeight: 360)
        }
        .padding(.bottom, 16)
        .sheetDetents([.medium])
    }
}

// ← WeekNavButton
private struct WeekNavButton: View {
    @Environment(\.localWakeUpColors) private var colors
    let icon: String
    // ← 原版本 contentDescriptionRes: 传了才挂 a11y 标签, 箭头按钮不传
    var a11yLabel: String? = nil
    let onClick: () -> Void

    var body: some View {
        if let a11yLabel {
            button.accessibilityLabel(a11yLabel)
        } else {
            button
        }
    }

    private var button: some View {
        // ← 原版本: Box.size(32.dp).clip.background.clickable.padding(6.dp) — padding 在框内
        //   (只缩图标槽 32−2×6=20), 占位恒 32。旧 iOS 把 padding 挂在 frame 外 → 占位 44,
        //   比 capsuleScale 公式(按 32+6+38+6 预留)每钮多挤 12pt,
        //   撤回胶囊/tick 会压到居中翻页三件套(issue: 顶栏重叠/与安卓不一致)。
        //   图标由 frame 32 居中渲染, 不受 padding 位置影响; 热区 32×32 ← SleepyButtonStyle。
        Button(action: onClick) {
            Image(systemName: icon)
                .foregroundColor(colors.onSurfaceVariant)
                .frame(width: 32, height: 32)
                .background(colors.surfaceContainerHigh)
                .clipShape(Circle())
        }
        .buttonStyle(SleepyButtonStyle())
        // ← G5: 周导航箭头锚点(chevron.left → week_prev / chevron.right → week_next)
        .accessibilityIdentifier(icon.contains("left") ? "week_prev" : "week_next")
    }
}

// ← ScheduleScreen.kt L475-528 跳周 DropdownMenu — 280dp 弹层 + FlowRow 圆形周 chip:
//   容器 surfaceContainerHighest / 内边距 12 / 标题 schedule_jump_week(labelMedium
//   onSurfaceVariant, padding start4 bottom8) / chip 40dp Circle spacedBy 8×8,
//   选中 primary+Bold+onPrimary, 未选中 surfaceContainerHigh+Regular+onSurface,
//   点击即选即关; 点面板外任意处关闭(自绘 ZStack 浮层, 与仓库浮层容器模式一致)。
private struct WeekJumpMenu: View {
    @Environment(\.localWakeUpColors) private var colors
    let currentWeek: Int
    let maxWeek: Int
    let onSelect: (Int) -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            // 弹层外点击关闭(原版本 DropdownMenu 外点 scrim);近透明不遮内容
            Color.black.opacity(0.001)
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)
            menuPanel
                .padding(.top, 56)   // 锚在顶栏周胶囊正下方
        }
    }

    // 面板: 宽 280 + containerColor surfaceContainerHighest + Column padding 12
    private var menuPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.format("schedule_jump_week"))
                .font(.system(size: 12, weight: .medium))   // ← labelMedium 12
                .foregroundColor(colors.onSurfaceVariant)
                .padding(.leading, 4)
                .padding(.bottom, 8)
            chipGrid
        }
        .padding(12)                                  // ← Column(padding 12dp)
        .frame(width: 280, alignment: .leading)       // ← DropdownMenu 宽 280dp
        .background(colors.surfaceContainerHighest)   // ← containerColor
        .cornerRadius(4)                              // ← M3 menu 容器 extra-small 圆角
        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
    }

    // FlowRow(spacedBy 8/8, fillMaxWidth): 均一 40pt chip → 256pt 内每行 5 枚
    private var chipGrid: some View {
        let clampedMax = max(maxWeek, 1)
        let rows = stride(from: 1, through: clampedMax, by: 5).map {
            Array($0...min($0 + 4, clampedMax))
        }
        return VStack(spacing: 8) {   // ← FlowRow 纵向 spacedBy(8)
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 8) {  // ← FlowRow 横向 spacedBy(8)
                    ForEach(rows[r], id: \.self) { w in
                        weekChip(w)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)   // ← FlowRow fillMaxWidth
    }

    // 40dp Circle chip: 选中 primary/Bold/onPrimary,未选中 surfaceContainerHigh/Regular/onSurface
    private func weekChip(_ w: Int) -> some View {
        let isCurrent = w == currentWeek
        return Button {
            onSelect(w)   // ← onSelectWeek(w) + menuOpen=false: 点击即选即关
        } label: {
            Text("\(w)")
                .font(.system(size: 14, weight: isCurrent ? .bold : .regular))  // ← labelLarge 14
                .foregroundColor(isCurrent ? colors.onPrimary : colors.onSurface)
                .frame(width: 40, height: 40)   // ← 40dp
                .background(isCurrent ? colors.primary : colors.surfaceContainerHigh)
                .clipShape(Circle())            // ← M3 圆形 chip
                .contentShape(Circle())
        }
        .buttonStyle(SleepyButtonStyle())
        .accessibilityIdentifier("week_num_\(w)")
    }
}

// ← NoCourseState
private struct NoCourseState: View {
    @Environment(\.localWakeUpColors) private var colors
    let tableName: String
    let onAddCourse: () -> Void
    let onImport: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text(L10n.format("schedule_empty_name", tableName))
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(colors.onSurface)
            Text(L10n.format("schedule_empty_name_hint"))
                .font(.system(size: 14))
                .foregroundColor(colors.onSurfaceVariant)
            Button(action: onAddCourse) {
                Text(L10n.format("schedule_manual_first"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(colors.onPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(colors.primary)
                    .cornerRadius(SleepyShapes.large)
            }
            .buttonStyle(SleepyButtonStyle())
            Button(action: onImport) {
                Text(L10n.format("schedule_go_manage"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(colors.onSecondaryContainer)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(colors.secondaryContainer)
                    .cornerRadius(SleepyShapes.large)
            }
            .buttonStyle(SleepyButtonStyle())
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 24)
        .background(colors.surfaceContainer)
        .cornerRadius(SleepyShapes.extraLarge)
    }
}

// ← EmptyState — 主按钮=导入第一张课表, 副按钮=建表流(无表载体时"加课"无从谈起, ← 原版本)
private struct EmptyState: View {
    @Environment(\.localWakeUpColors) private var colors
    let onGoImport: () -> Void
    var onCreateTable: () -> Void = {}

    var body: some View {
        VStack(spacing: 12) {
            Text(L10n.format("schedule_empty"))
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(colors.onSurface)
            Text(L10n.format("schedule_empty_hint"))
                .font(.system(size: 14))
                .foregroundColor(colors.onSurfaceVariant)
            Button(action: onGoImport) {
                Text(L10n.format("schedule_empty_import"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(colors.onPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(colors.primary)
                    .cornerRadius(SleepyShapes.large)
            }
            .buttonStyle(SleepyButtonStyle())
            Button(action: onCreateTable) {
                Text(L10n.format("schedule_empty_create_table"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(colors.onSecondaryContainer)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(colors.secondaryContainer)
                    .cornerRadius(SleepyShapes.large)
            }
            .buttonStyle(SleepyButtonStyle())
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 24)
        .background(colors.surfaceContainer)
        .cornerRadius(SleepyShapes.extraLarge)
        // ← 原版本 EmptyState Column 链首 .padding(horizontal = 22.dp)(clip/background 之前 = 卡片外水平边距)
        .padding(.horizontal, 22)
        // ← 原版本 外层 Box .align(Alignment.Center): 空态卡在剩余空间垂直/水平居中
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
