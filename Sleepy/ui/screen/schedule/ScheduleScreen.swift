// ScheduleScreen.swift — ← ui/screen/schedule/ScheduleScreen.kt
// 课表页: TopBar(周导航+跳周菜单+撤回/取消撤回胶囊+行高缩放 tick) + 视图切换(周视图/网格, 可隐藏) +
// 左右滑翻周(TabView pager, 含 issue#44 调休渲染期换日) + 详情 BottomSheet。
// 空态两分支: 无表 → EmptyState; 有表无课 → NoCourseState。

import SwiftUI

enum ViewMode: Hashable {
    case full   // ← ViewMode.Full (周视图)
    case cards  // ← ViewMode.Cards (网格)
}

private enum WeekPageMotion {
    static var animation: Animation {
        UIAccessibility.isReduceMotionEnabled ? .easeOut(duration: 0.15)
            : .timingCurve(0.1, 0.1, 0, 1, duration: 0.3)
    }
}

/// Keep the selected occurrence and its display context together across layout changes.
struct ScheduleCourseDetailRequest: Identifiable {
    let id = UUID()
    let course: CourseEntity
    let allCourses: [CourseEntity]
    let displayDate: Date?
    let table: TimeTableEntity?
}

private struct WeekLabelSurface: ViewModifier {
    @Environment(\.sleepyUIStyle) private var style
    let grouped: Bool
    let color: Color
    @ViewBuilder func body(content: Content) -> some View {
        if grouped || style == .liquidGlass { content } else { content.sleepyControlSurface(cornerRadius: SleepyShapes.medium, tint: color) }
    }
}
private struct ScheduleWeekLabelButtonStyle: PrimitiveButtonStyle {
    let grouped: Bool
    @ViewBuilder func makeBody(configuration: Configuration) -> some View {
        if grouped {
            Button(role: configuration.role, action: configuration.trigger) { configuration.label }
                .buttonStyle(SleepyButtonStyle())
        } else {
            Button(role: configuration.role, action: configuration.trigger) { configuration.label }
                .buttonStyle(SleepyPlatformButtonStyle(cornerRadius: SleepyShapes.medium, compact: true))
        }
    }
}

private struct WeekGroupSurface: ViewModifier {
    @Environment(\.sleepyUIStyle) private var style
    let grouped: Bool
    let color: Color
    @ViewBuilder func body(content: Content) -> some View {
        if grouped {
            if style == .liquidGlass {
                content.sleepyNativeGlassSurface(cornerRadius: 16, tint: color, interactive: true)
                    .accessibilityElement(children: .contain).accessibilityIdentifier("week_group")
            } else {
                content.sleepyControlSurface(cornerRadius: 16, tint: color)
                    .accessibilityElement(children: .contain).accessibilityIdentifier("week_group")
            }
        } else { content }
    }
}

struct ScheduleScreen: View {
    @Environment(\.localWakeUpColors) private var colors
    @ObservedObject var viewModel: ScheduleViewModel
    // ← 原版本 b96c865b: 视图模式提升到 AppRoot 会话层(切 tab/开 overlay 不再弹回启动默认),
    // 顶部手动切换只改会话态, 不回写启动偏好(KEY_START_VIEW 既有分离设计)
    @Binding var viewMode: ViewMode
    var onGoImport: () -> Void = {}
    var onShareRequested: ((TimeTableEntity, [CourseEntity]) -> Void)? = nil
    var onCourseDetailRequested: ((ScheduleCourseDetailRequest) -> Void)? = nil
    var courseDetailPresented = false
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
                    onPrevWeek: { selectWeek(state.selectedWeek - 1) },
                    onNextWeek: {
                        selectWeek(state.selectedWeek + 1)
                    },
                    onJumpToActual: {
                        guard let start = state.currentTable?.startDate else { return }
                        selectWeek(DateUtils.currentWeek(startDate: start))
                    },
                    onSelectWeek: selectWeek,
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
                    onShare: {
                        quickAdd.dismiss()
                        if let onShareRequested, let table = state.effectiveCurrentTable {
                            onShareRequested(table, state.courses)
                        } else { showShareSheet = true }
                    },
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

                if state.hasPeriodConflict {
                    PeriodConflictBanner(message: L10n.format("period_conflict_detected_banner", state.periodValidation.errorMessage))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
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
                          dragEnabled: !showWeekJumpMenu && !showTableSwitcher && !showShareSheet
                            && selectedCourse == nil && !courseDetailPresented,
                          quickAdd: quickAdd, quickAddEnabled: onAddAt != nil,
                          onQuickAdd: { week, day, node, step in
                              guard let table = state.currentTable else { return }
                              onAddAt?(table.id, week, day, node, step)
                           }) { course, page in
                    let displayDate = state.currentTable.flatMap {
                        CourseOccurrences.date(startDate: $0.startDate, week: page, day: course.day)
                    }
                    if let onCourseDetailRequested {
                        quickAdd.dismiss()
                        onCourseDetailRequested(ScheduleCourseDetailRequest(
                            course: course, allCourses: detailCourses(for: page),
                            displayDate: displayDate, table: state.effectiveCurrentTable))
                    } else {
                        selectedCourseWeek = page
                        selectedCourseDate = displayDate
                        selectedCourse = course
                    }
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
        .centeredDialog(isPresented: $showTableSwitcher) {
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
        // Week selection stays centered regardless of the toolbar's current layout.
        .centeredDialog(isPresented: $showWeekJumpMenu) {
                // v1.0.62 B5b: 跳周 chip 网格上限同 displayMaxWeek ← 原版本 TopBar 内 DropdownMenu 同参
                WeekJumpMenu(currentWeek: state.selectedWeek,
                             maxWeek: state.displayMaxWeek,
                             onSelect: { week in
                                 selectWeek(week)
                                 showWeekJumpMenu = false
                             },
                             onDismiss: { showWeekJumpMenu = false })
        }
        // 详情 Bottom Sheet
        .sheet(item: $selectedCourse) { course in
            // v1.0.62 B5b: 详情页聚簇同域 ← 原 allCourses = 逐日 coursesForDate 投影:
            // 调休周里补班日列的课(投影 day)与放假日空列都按同一渲染域参与聚簇, 幽灵/漏簇同修。
            return CourseDetailSheet(
                course: course,
                timeString: course.nodeString(),
                // v7.10.16q: allCourses 必须与网格同周域 —
                // 周次不相交同行(如周1-4/周6-13)全量传会被当成同时存在 → 幽灵图层
                allCourses: detailCourses(for: selectedCourseWeek),
                onEdit: { c in
                    selectedCourse = nil
                    // v1.0.62 B5b: 编辑回传库内原始行 ← 原版本 onEditCourse(firstOrNull(id) ?: course) —
                    // 投影替身(day 已改写)不落库, 按 id 找回原始行
                    onEditCourse(state.courses.first { $0.id == c.id } ?? c)
                },
                // issue#40: 详情页时间域与网格同源 = 水合表 effectiveCurrentTable
                timeJson: state.effectiveRenderTimeJson,
                displayDate: selectedCourseDate,
                occurrenceTable: state.effectiveCurrentTable,
                occurrenceRepository: viewModel.occurrenceRepository,
                onOccurrenceSaved: {
                    selectedCourse = nil
                    viewModel.occurrenceSaved()
                })
        }
    }

    private func detailCourses(for week: Int) -> [CourseEntity] {
        let state = viewModel.state
        guard let table = state.currentTable else { return [] }
        return renderCoursesForWeek(table, week: week, courses: state.courses,
                                    transfers: state.transfers, timeJson: nil)
    }

    private func showToast(_ message: String) {
        toastMessage = message
        toastToken += 1   // 单调 token: 同款文案连点也能重启消失计时
    }

    private func selectWeek(_ week: Int) {
        // TabView's page selection is bridged to UIKit. Put the mutation in
        // the animation transaction; animating only its content does not slide pages.
        withAnimation(WeekPageMotion.animation) { viewModel.changeWeek(week) }
    }
}

private struct TopBarWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// 2026-09-21 用户令: 撤回/取消撤回一体胶囊 ← UndoRedoCapsule — 体育场形状(左右半圆+中间矩形),
/// 撤回左半·取消撤回右半, 中间一条淡淡竖线。两半由 popup 宿主按 hasUndo||hasRedo 同现同隐,
/// 各半按有无快照 enabled/禁用(alpha 0.38 占位保形)。scale=动态挤压系数(周三件套逼近时缩)。
private struct UndoRedoCapsule: View {
    @Environment(\.localWakeUpColors) private var colors
    @Environment(\.sleepyUIStyle) private var style
    let showUndo: Bool
    let showRedo: Bool
    let scale: CGFloat
    let onUndo: () -> Void
    let onRedo: () -> Void

    var body: some View {
        // 几何 ← 原版本: halfSize=32*scale / dividerHeight=14*scale / icon=20*scale
        let halfSize = 32 * scale
        return Group {
            if style == .liquidGlass {
                buttons(halfSize: halfSize)
                    .sleepyNativeGlassSurface(cornerRadius: halfSize / 2, interactive: true)
            } else {
                buttons(halfSize: halfSize)
                    .sleepyControlSurface(cornerRadius: halfSize / 2, tint: colors.surfaceContainerHigh)
            }
        }
        .frame(height: style == .classic ? halfSize : nil)
    }

    private func buttons(halfSize: CGFloat) -> some View {
        HStack(spacing: 0) {
            // 左半: 撤回 — 无可撤回时半透明禁用(占位保形, 双侧共存才像一体胶囊)
            Button(action: onUndo) {
                AndroidMaterialIcon(name: .undo, size: 20 * scale)
                    .foregroundColor(colors.onSurfaceVariant.opacity(showUndo ? 1 : 0.38))
                    .frame(width: halfSize, height: halfSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(SleepyButtonStyle())
            .frame(width: style == .classic ? halfSize : nil, height: style == .classic ? halfSize : nil)
            .disabled(!showUndo)
            .accessibilityLabel(L10n.format("schedule_undo"))
            .accessibilityIdentifier("undo_button")

            // 中缝: 淡淡竖线 — 与图标同色调降透明度, 视觉上"一体两半"
            if style == .classic {
                Rectangle()
                    .fill(colors.onSurfaceVariant.opacity(SleepyTheme.Alpha.inactive))
                    .frame(width: scale, height: 14 * scale)
            } else {
                Color.clear.frame(width: scale, height: 14 * scale)
            }

            // 右半: 取消撤回 — 无可重做时半透明禁用
            Button(action: onRedo) {
                AndroidMaterialIcon(name: .redo, size: 20 * scale)
                    .foregroundColor(colors.onSurfaceVariant.opacity(showRedo ? 1 : 0.38))
                    .frame(width: halfSize, height: halfSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(SleepyButtonStyle())
            .frame(width: style == .classic ? halfSize : nil, height: style == .classic ? halfSize : nil)
            .disabled(!showRedo)
            .accessibilityLabel(L10n.format("schedule_redo"))
            .accessibilityIdentifier("redo_button")
        }
    }
}

// HorizontalPager → TabView(.page): 双向同步(手势→VM / VM→pager)
// Cards 网格的 TimeSlot: 每节一行(node/nodeStart 单节, 原版本 同为逐节行)
// ← 原版本 TimeTableUtils.timeSlotsFor(state.effectiveCurrentTable): 时间域真源=水合表,
//   表为 nil → 空表(禁 DEFAULT_TIME_JSON 兜底 — 有表无课才进得本页, 语义与 原版本 对齐)
private func cardTimeSlots(timeJson: String?) -> [TimeSlot] {
    guard let timeJson else { return [] }
    return TimeTableUtils.renderSlots(timeJson: timeJson)
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
    let input = WeekCourseProjectionCache.Input(tableId: table.id, startDate: table.startDate,
        maxWeek: table.maxWeek, week: week, courses: courses, transfers: transfers,
        timeJson: timeJson, calendar: calendar)
    return WeekCourseProjectionCache.shared.value(for: input) {
        (1...7).flatMap { day -> [CourseEntity] in
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
}

private struct WeekPager: View {
    @ObservedObject var viewModel: ScheduleViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var drag = CourseDragContext()
    @State private var dragError = false
    @State private var dragHostWeek: Int?
    @State private var pagerEpoch: UInt = 0
    @State private var floatingOccurrence: FloatingOccurrenceRequest?
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

    private struct FloatingOccurrenceRequest: Identifiable {
        let id = UUID()
        let occurrence: CourseOccurrence
        let table: TimeTableEntity
        let startInEdit: Bool
        var startWithDelete = false
    }

    var body: some View {
        dragPager
            .onReceive(drag.$source.map { $0?.displayWeek }.removeDuplicates()) { sourceWeek in
                // CurrentValuePublisher can emit while SwiftUI installs this
                // subscription. Apply the host change after that render, and
                // discard an event superseded by a newer lift/dismissal.
                DispatchQueue.main.async {
                    guard drag.source?.displayWeek == sourceWeek, sourceWeek != dragHostWeek else { return }
                    var transaction = Transaction(animation: nil)
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        if let hostWeek = dragHostWeek, sourceWeek == nil,
                           hostWeek != viewModel.state.selectedWeek {
                            // Start at the final week; the old pinned pager can report intermediate pages.
                            pagerEpoch &+= 1
                        }
                        dragHostWeek = sourceWeek
                    }
                }
            }
            .onChange(of: viewModel.state.selectedTableId) { _ in drag.end(); viewModel.cancelPendingCourseMove() }
            .onChange(of: viewModel.state.selectedWeek) { week in
                if !drag.isHolding, let source = drag.source, source.displayWeek != week { drag.end() }
            }
            .onChange(of: viewMode) { _ in drag.end(); viewModel.cancelPendingCourseMove() }
            .onChange(of: dragEnabled) { if !$0 { drag.end(); quickAdd.dismiss(); viewModel.cancelPendingCourseMove() } }
            .onChange(of: quickAddEnabled) { if !$0 { quickAdd.dismiss() } }
            .onChange(of: scenePhase) { phase in
                if phase != .active { drag.end(); quickAdd.dismiss(); viewModel.cancelPendingCourseMove() }
            }
            .onDisappear { drag.end(); viewModel.cancelPendingCourseMove() }
            .alert(L10n.t("schedule_drag_failed"), isPresented: $dragError) {
                Button(L10n.t("ok"), role: .cancel) {}
            }
            .alert(viewModel.pendingCourseMove?.confirmationTitle ?? "",
                   isPresented: Binding(get: { viewModel.courseMovePromptPresented }, set: { _ in }),
                   presenting: viewModel.pendingCourseMove) { request in
                let respond: (CourseDragMoveChoice) -> Void = { choice in
                    switch viewModel.advancePendingCourseMove(choice) {
                    case .awaitingApproval: break
                    case .saved: drag.resolveConfirmation(saved: true)
                    case .canceled: drag.resolveConfirmation(saved: false)
                    case .failed:
                        drag.resolveConfirmation(saved: false)
                        DispatchQueue.main.async { dragError = true }
                    }
                }
                Button(request.confirmationAction, role: request.confirmationIsDestructive ? .destructive : nil) {
                    respond(.confirm)
                }.accessibilityIdentifier("course_move_confirm")
                if request.prompt == .destination {
                    Button(L10n.t("occurrence_direct")) { respond(.direct) }
                        .accessibilityIdentifier("course_move_direct")
                }
                Button(L10n.t("conflict_detail_go_back"), role: .cancel) {
                    respond(.cancel)
                }
                    .accessibilityIdentifier("course_move_cancel")
            } message: { request in
                Text(request.confirmationMessage)
            }
            .sheet(item: $floatingOccurrence) { request in
                CourseOccurrenceEditor(occurrence: request.occurrence, table: request.table,
                    repository: viewModel.occurrenceRepository,
                    onSaved: { floatingOccurrence = nil; viewModel.occurrenceSaved() },
                    onDismiss: { floatingOccurrence = nil }, startInEdit: request.startInEdit,
                    startWithDelete: request.startWithDelete)
            }
            .task(id: "\(viewModel.state.currentTable?.startDate ?? "")-\(viewModel.state.selectedWeek)-\(pagerMaxWeek)") {
                await refreshGreyDays()
            }
    }

    private var pages: some View {
        let state = viewModel.state
        let epoch = pagerEpoch
        // Keep TabView's source subtree alive, including its scroll and expanded rows.
        // Target pages are measured alongside it instead of waiting for lazy page hosts.
        return TabView(selection: Binding(
            get: { min(max(dragHostWeek ?? state.selectedWeek, 1), pagerMaxWeek) },
            set: { newWeek in
                guard epoch == pagerEpoch, dragHostWeek == nil else { return }
                viewModel.changeWeek(newWeek)
            }
        )) {
            ForEach(1...pagerMaxWeek, id: \.self) { page in
                GeometryReader { geometry in
                    weekPage(page, renderSelectedWeek: dragHostWeek ?? state.selectedWeek,
                             publishesDropGrid: dragHostWeek == nil || page == dragHostWeek)
                        .offset(x: dragHostWeek == nil ? 0 : CGFloat(page - state.selectedWeek) * geometry.size.width)
                    if dragHostWeek == page {
                        dragTargetPages(width: geometry.size.width)
                    }
                }
                .clipped()
                .animation(weekPageAnimation, value: state.selectedWeek)
                .tag(page)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tabViewStyle(.page(indexDisplayMode: .never))
        .animation(dragHostWeek == nil ? weekPageAnimation : nil, value: state.selectedWeek)
        .id(epoch)
    }

    private var weekPageAnimation: Animation {
        WeekPageMotion.animation
    }

    private func dragTargetPages(width: CGFloat) -> some View {
        let state = viewModel.state
        return ForEach(1...pagerMaxWeek, id: \.self) { page in
            if page != dragHostWeek,
               TimetableViewportPolicy.shouldRenderWeek(page, selectedWeek: state.selectedWeek,
                                                         dragHostWeek: nil) {
                weekPage(page, renderSelectedWeek: state.selectedWeek, publishesDropGrid: true)
                    .offset(x: CGFloat(page - state.selectedWeek) * width)
                    .allowsHitTesting(page == state.selectedWeek)
            }
        }
    }

    private func weekPage(_ page: Int, renderSelectedWeek: Int, publishesDropGrid: Bool) -> some View {
        let state = viewModel.state
        return Group {
            if (dragHostWeek == nil || publishesDropGrid),
               TimetableViewportPolicy.shouldRenderWeek(page, selectedWeek: renderSelectedWeek,
                                                         dragHostWeek: dragHostWeek) {
                // page 是 1-based 周索引,独立于 state.currentWeek 过滤课程
                // The fallback is lazy: a real table uses the daily projection,
                // so it must not also normalize and discard a second course list.
                let renderCourses = state.currentTable.map {
                    renderCoursesForWeek($0, week: page, courses: state.courses,
                                         transfers: state.transfers,
                                         timeJson: state.effectiveRenderTimeJson)
                } ?? {
                    let list = state.courses.filter { $0.inWeek(page) }
                    // issue#40: normalizeNode 时间域真源 = 水合表 effectiveCurrentTable
                    // (绑定作息表编辑后立即生效), 不得再读 currentTable.timeJson 旧兼容列
                    guard let tj = state.effectiveRenderTimeJson else { return list }
                    return list.map { $0.normalizeNode(timeJson: tj) }
                }()
                Group {
                    switch viewMode {
                    case .full:
                        FullWeekView(courses: renderCourses,
                                     visibleDays: visibleDays,
                                     displayMode: displayMode,
                                     // issue#40: 时间域读水合表 ← 原版本 effectiveCurrentTable?.timeJson ?: ""
                                     timeJson: state.effectiveRenderTimeJson ?? "",
                                     startDate: state.currentTable?.startDate ?? "",
                                     currentWeek: page,
                                     onCourseClick: { onCourseClick($0, page) },
                                     onCourseLongClick: { openWeekOccurrence($0, displayWeek: page) },
                                     greyDays: greyDaysByWeek[page] ?? [],
                                     // v1.0.62 B5b: 周视图日期「·M月d日」← 原版本 FullWeekView(showDate = showDate)
                                     showDate: showDate)
                    case .cards:
                        CardsGridView(courses: renderCourses,
                                      timeSlots: cardTimeSlots(timeJson: state.effectiveRenderTimeJson),
                                      // issue#40 §5: 时间域(含非常规课占位合成)同样以水合表为准
                                      timeJson: state.effectiveRenderTimeJson ?? "",
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
                                      onQuickAdd: { day, node, step in onQuickAdd(page, day, node, step) },
                                      publishesDropGrid: publishesDropGrid)
                    }
                }
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.courseDragContext, viewMode == .cards && publishesDropGrid ? drag : nil)
        .environment(\.courseDragWeek, page)
        .accessibilityHidden(page != state.selectedWeek)
        .tag(page)
    }

    private var dragPager: some View {
        let state = viewModel.state
        return pages
        .modifier(CourseDragBackdrop(drag: drag))
        .onPreferenceChange(CourseDropGridKey.self) { drag.grids = $0 }
        .background(NativeCourseDropTarget(drag: drag, week: state.selectedWeek, maxWeek: pagerMaxWeek,
            table: state.effectiveCurrentTable, allCourses: state.courses, transfers: state.transfers,
            enabled: dragEnabled && viewMode == .cards && !dragError && quickAdd.selection == nil
                && viewModel.pendingCourseMove == nil,
            onChangeWeek: { week in
                // The preview lives in UIWindow; only the pinned page stack moves.
                // Hit testing uses the target week's measured grid in the viewport.
                withAnimation(weekPageAnimation) { viewModel.changeWeek(week) }
            },
            onMove: { source, week, day, node, startTime, step, resizeOnly in
                let success = viewModel.stageDraggedOccurrence(source: source, targetWeek: week,
                    displayDay: day, targetNode: node, targetStartTime: startTime, targetStep: step,
                    resizeOnly: resizeOnly)
                if success && viewModel.pendingCourseMove == nil { drag.resolveConfirmation(saved: true) }
                if !success { dragError = true }
                return success
            }, onOccurrenceAction: { source, editing in
                guard let table = viewModel.state.effectiveCurrentTable,
                      table.id == source.course.tableId,
                      let displayDate = DateUtils.dateOfWeek(startDate: table.startDate,
                        week: source.displayWeek, dayOfWeek: source.displayDay),
                      let occurrence = CourseOccurrences.resolve(course: source.course,
                        displayDate: displayDate, table: table, transfers: viewModel.state.transfers) else {
                    dragError = true
                    return
                }
                floatingOccurrence = FloatingOccurrenceRequest(occurrence: occurrence,
                    table: table, startInEdit: editing, startWithDelete: !editing)
            }))
        .overlay(CourseDragProjection(drag: drag))
        .overlay(CourseDragEdgePeek(drag: drag))
        .accessibilityIdentifier("schedule_week_pager")
    }

    private func openWeekOccurrence(_ projected: CourseEntity, displayWeek: Int) {
        guard dragEnabled, floatingOccurrence == nil,
              projected.tableId == viewModel.state.selectedTableId else { return }
        do {
            let repository = viewModel.occurrenceRepository
            guard let stored = try repository.getTable(projected.tableId),
                  let original = try repository.getCourse(projected.id), original.tableId == stored.id,
                  let displayDate = CourseOccurrences.date(startDate: stored.startDate,
                    week: displayWeek, day: projected.day) else {
                throw CourseOccurrences.ValidationError.invalidOccurrence
            }
            let table = stored.hydratedWith(try repository.effectivePeriodTable(tableId: stored.id))
            guard let occurrence = CourseOccurrences.resolve(course: original, displayDate: displayDate,
                table: table, transfers: AppPrefs.shared.getHolidayTransfers(stored.id)) else {
                throw CourseOccurrences.ValidationError.invalidOccurrence
            }
            floatingOccurrence = FloatingOccurrenceRequest(occurrence: occurrence, table: table, startInEdit: false)
        } catch { dragError = true }
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

private struct NativeToolbarMetricsKey: PreferenceKey {
    static var defaultValue: [Int: CGSize] = [:]
    static func reduce(value: inout [Int: CGSize], nextValue: () -> [Int: CGSize]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

// ← TopBar
private struct ScheduleTopBar: View {
    @Environment(\.localWakeUpColors) private var colors
    @Environment(\.sleepyUIStyle) private var style
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

    @Environment(\.layoutDirection) private var direction
    @State private var barWidth: CGFloat = 0
    @State private var nativeSizes: [Int: CGSize] = [:]

    var body: some View {
        let actualWeek = displayContext?.actualWeek
            ?? (startDate.isEmpty ? 1 : DateUtils.currentWeek(startDate: startDate))
        let isOnActual = currentWeek == actualWeek
        let status = displayContext?.semesterStatus ?? DateUtils.semesterStatus(startDate: startDate, maxWeek: maxWeek)
        let label = L10n.format("schedule_current_week", currentWeek)
        let description = status == .inRange ? label
            : L10n.format(status == .beforeStart ? "semester_not_started" : "semester_ended") + " · " + label
        let font = UIFont.systemFont(ofSize: 14, weight: .semibold)
        let textWidth = ceil((label as NSString).size(withAttributes: [.font: font]).width)
        let numberWidth = max(32, ceil((String(currentWeek) as NSString).size(withAttributes: [.font: font]).width) + 8)
        let native = style == .liquidGlass
        let normalStart = nativeSizes[0]
        let tightStart = nativeSizes[4]
        let normalEnd = nativeSizes[2]
        let tightEnd = nativeSizes[5]
        let layout = ScheduleToolbarGeometry.resolve(width: max(0, barWidth),
            fullCenterWidth: native ? nativeSizes[1]?.width ?? 140 + textWidth : 140 + textWidth,
            groupedCenterWidth: native ? nativeSizes[3]?.width ?? 66 + numberWidth : 66 + numberWidth,
            history: hasUndoSnapshot || hasRedoSnapshot, confirm: scaleUncommitted,
            normalStartWidth: native ? normalStart?.width : nil,
            tightStartWidth: native ? tightStart?.width : nil,
            normalEndWidth: native ? normalEnd?.width ?? 104 : 104,
            tightEndWidth: native ? tightEnd?.width ?? 96 : 96,
            sideHeight: native ? max(normalStart?.height ?? 48, normalEnd?.height ?? 48) : 48,
            fullCenterHeight: native ? nativeSizes[1]?.height ?? 48 : 48,
            groupedCenterHeight: native ? nativeSizes[3]?.height ?? 32 : 32)
        GeometryReader { proxy in
            let fit = layout.fitScale
            let leadingX = layout.inset + layout.startWidth * fit / 2
            let trailingX = proxy.size.width - layout.inset - layout.endWidth * fit / 2
            ZStack {
                leadingActions(scale: native ? 1 : layout.sideScale, gap: layout.sideGap)
                    .fixedSize()
                    .scaleEffect(fit * (native ? layout.sideScale : 1))
                    .position(x: direction == .leftToRight ? leadingX : proxy.size.width - leadingX, y: proxy.size.height / 2)
                pagerTriple(isOnActual: isOnActual, grouped: layout.grouped, label: label,
                            description: description, numberWidth: numberWidth)
                    .frame(width: layout.centerWidth)
                    .scaleEffect(fit)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                trailingActions(scale: native ? 1 : layout.sideScale, gap: layout.sideGap)
                    .fixedSize()
                    .scaleEffect(fit * (native ? layout.sideScale : 1))
                    .position(x: direction == .leftToRight ? trailingX : proxy.size.width - trailingX, y: proxy.size.height / 2)
            }
            .overlay(alignment: .topLeading) {
                if native {
                    nativeMeasurements(isOnActual: isOnActual, label: label,
                                       description: description, numberWidth: numberWidth)
                }
            }
            .preference(key: TopBarWidthKey.self, value: proxy.size.width)
        }
        .frame(height: barWidth > 0 ? layout.height : 48)
        .onPreferenceChange(TopBarWidthKey.self) { barWidth = $0 }
        .padding(.vertical, 6)
        .background(colors.surface)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("schedule_toolbar")
    }

    /// Measure every current candidate, including the full week label while
    /// grouped. Native chrome follows the same spacing/side-scale fallback as Material.
    private func nativeMeasurements(isOnActual: Bool, label: String, description: String,
                                    numberWidth: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            nativeMeasured(leadingActions(scale: 1, gap: 8), id: 0)
            nativeMeasured(leadingActions(scale: 1, gap: 0), id: 4)
            nativeMeasured(trailingActions(scale: 1, gap: 8), id: 2)
            nativeMeasured(trailingActions(scale: 1, gap: 0), id: 5)
            nativeMeasured(pagerTriple(isOnActual: isOnActual, grouped: false, label: label,
                                       description: description, numberWidth: numberWidth), id: 1)
            nativeMeasured(pagerTriple(isOnActual: isOnActual, grouped: true, label: label,
                                       description: description, numberWidth: numberWidth), id: 3)
        }
        .hidden()
        .accessibilityHidden(true)
        .allowsHitTesting(false)
        .onPreferenceChange(NativeToolbarMetricsKey.self) { sizes in
            if sizes != nativeSizes { nativeSizes = sizes }
        }
    }

    private func nativeMeasured<Content: View>(_ content: Content, id: Int) -> some View {
        content.fixedSize()
            .background(GeometryReader { proxy in
                Color.clear.preference(key: NativeToolbarMetricsKey.self, value: [id: proxy.size])
            })
    }

    private func leadingActions(scale: CGFloat, gap: CGFloat) -> some View {
        HStack(spacing: 0) {
            WeekNavButton(icon: .calendarMonth, a11yLabel: L10n.format("schedule_switch_table"), scale: scale, onClick: onSwitchTable)
                .accessibilityIdentifier("switch_table")
            if hasUndoSnapshot || hasRedoSnapshot {
                UndoRedoCapsule(showUndo: hasUndoSnapshot, showRedo: hasRedoSnapshot,
                                scale: scale, onUndo: onUndo, onRedo: onRedo)
                    .padding(.leading, gap * scale)
            }
            if scaleUncommitted {
                WeekNavButton(icon: .check, a11yLabel: L10n.format("schedule_scale_keep"), scale: scale, onClick: onScaleCommit)
                    .accessibilityIdentifier("scale_keep")
                    .padding(.leading, gap * scale)
            }
        }
    }

    private func trailingActions(scale: CGFloat, gap: CGFloat) -> some View {
        HStack(spacing: gap * scale) {
            WeekNavButton(icon: .add, a11yLabel: L10n.format("schedule_add_course"), scale: scale, onClick: onAddCourse)
                .accessibilityIdentifier("topbar_add")
            WeekNavButton(icon: .iosShare, a11yLabel: L10n.format("schedule_share_table"), scale: scale, onClick: onShare)
                .accessibilityIdentifier("topbar_share")
        }
    }

    private func pagerTriple(isOnActual: Bool, grouped: Bool, label: String, description: String, numberWidth: CGFloat) -> some View {
        HStack(spacing: grouped ? 0 : 8) {
            if grouped { groupedArrow(.chevronLeft, action: onPrevWeek); groupDivider }
            else { WeekNavButton(icon: .chevronLeft, onClick: onPrevWeek) }
            Button {
                if isOnActual { onOpenWeekJump() } else { onJumpToActual() }
            } label: {
                Text(grouped ? String(currentWeek) : label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isOnActual && !grouped ? colors.onPrimaryContainer : colors.primary)
                    .lineLimit(1).fixedSize()
                    .padding(.horizontal, grouped ? 0 : 14)
                    .padding(.vertical, grouped ? 0 : 4)
                    .frame(width: grouped ? numberWidth : nil, height: grouped ? 32 : nil)
                    .modifier(WeekLabelSurface(grouped: grouped, color: isOnActual ? colors.primaryContainer : colors.primaryContainer.opacity(SleepyTheme.Alpha.inactive)))
            }
            .buttonStyle(ScheduleWeekLabelButtonStyle(grouped: grouped))
            .tint(isOnActual ? colors.primaryContainer : colors.primaryContainer.opacity(SleepyTheme.Alpha.inactive))
            .accessibilityLabel(description)
            .accessibilityIdentifier("week_label")
            if grouped { groupDivider; groupedArrow(.chevronRight, action: onNextWeek) }
            else { WeekNavButton(icon: .chevronRight, onClick: onNextWeek) }
        }
        .modifier(WeekGroupSurface(grouped: grouped, color: colors.surfaceContainerHigh))
    }

    private var groupDivider: some View {
        Rectangle().fill(style == .liquidGlass ? Color.clear : colors.onSurfaceVariant.opacity(SleepyTheme.Alpha.inactive)).frame(width: 1, height: 14)
    }
    private func groupedArrow(_ icon: AndroidMaterialIcon.Name, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            AndroidMaterialIcon(name: icon, size: 20).foregroundColor(colors.onSurfaceVariant)
                .frame(width: 32, height: 32).contentShape(Rectangle())
        }
        .buttonStyle(SleepyButtonStyle())
        .frame(width: 32, height: 32)
        .accessibilityIdentifier(icon == .chevronLeft ? "week_prev" : "week_next")
        .accessibilityLabel(L10n.t(icon == .chevronLeft ? "schedule_previous_week" : "schedule_next_week"))
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
        CenteredPickerDialog(title: L10n.format("schedule_switch_table"), onDismiss: onDismiss) {
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
                                    AndroidMaterialIcon(name: .check, size: 18)
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
        }
    }
}

// ← WeekNavButton
private struct WeekNavButton: View {
    @Environment(\.localWakeUpColors) private var colors
    @Environment(\.sleepyUIStyle) private var style
    let icon: AndroidMaterialIcon.Name
    // Non-arrow actions can override the default week-navigation accessibility label.
    var a11yLabel: String? = nil
    var scale: CGFloat = 1
    let onClick: () -> Void

    var body: some View {
        if let a11yLabel {
            button.accessibilityLabel(a11yLabel)
        } else {
            button
        }
    }

    private var button: some View {
        // v1.0.64: 32pt visual circle inside the 48pt action slot; both
        // follow the toolbar side scale before the final narrow-window fit.
        Button(action: onClick) {
            AndroidMaterialIcon(name: icon, size: 20 * scale)
                .foregroundColor(colors.onSurfaceVariant)
                .frame(width: style == .classic ? 32 * scale : nil,
                       height: style == .classic ? 32 * scale : nil)
                .sleepyControlSurface(cornerRadius: 16 * scale, tint: colors.surfaceContainerHigh)
                .frame(width: style == .classic ? 48 * scale : nil,
                       height: style == .classic ? 48 * scale : nil)
                .contentShape(Rectangle())
        }
        .buttonStyle(SleepyPlatformButtonStyle(cornerRadius: 16 * scale, compact: true, shape: .circle))
        .frame(width: 48 * scale, height: 48 * scale)
        .tint(colors.surfaceContainerHigh)
        // ← G5: 周导航箭头锚点(chevron.left → week_prev / chevron.right → week_next)
        .accessibilityIdentifier(icon == .chevronLeft ? "week_prev" : "week_next")
        .accessibilityLabel(L10n.t(icon == .chevronLeft ? "schedule_previous_week" : "schedule_next_week"))
    }
}

// Window-centered week dialog; its placement is independent of the toolbar label.
struct WeekJumpMenu: View {
    @Environment(\.localWakeUpColors) private var colors
    @Environment(\.sleepyUIStyle) private var style
    let currentWeek: Int
    let maxWeek: Int
    let onSelect: (Int) -> Void
    let onDismiss: () -> Void

    private var chipDiameter: CGFloat { style == .liquidGlass ? 44 : 40 }

    var body: some View {
        GeometryReader { geometry in
            let panelWidth = min(320, max(geometry.size.width - 48, 0))
            let stride = chipDiameter + 8
            let columns = max(Int((panelWidth - 48 + 8) / stride), 1)
            let rows = (max(maxWeek, 1) - 1) / columns + 1
            let gridHeight = CGFloat(rows) * stride - 8
            ZStack {
                Color.black.opacity(0.32)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onDismiss)
                menuPanel(gridHeight: min(gridHeight, min(400, max(geometry.size.height - 176, 40))))
                    .frame(width: panelWidth, alignment: .leading)
                    .background(colors.surfaceContainerHigh)
                    .cornerRadius(28)
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("week_jump_dialog")
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
    }

    private func menuPanel(gridHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.format("schedule_jump_week"))
                .font(SleepyTypography.titleLarge)
                .foregroundColor(colors.onSurface)
                .padding(.bottom, 16)
                .accessibilityIdentifier("week_jump_title")
            ScrollViewReader { proxy in
                ScrollView {
                    chipGrid
                }
                .frame(height: gridHeight)
                .onAppear { proxy.scrollTo(currentWeek, anchor: .center) }
            }
            HStack {
                Spacer()
                Button(action: onDismiss) { Text(L10n.format("cancel")) }
                    .buttonStyle(SleepyPlatformButtonStyle())
                    .tint(colors.primary)
                    .accessibilityIdentifier("week_jump_cancel")
            }
            .padding(.top, 16)
        }
        .padding(24)
    }

    // Keep the familiar five-column menu, allowing fewer columns in narrow panes.
    private var chipGrid: some View {
        let clampedMax = max(maxWeek, 1)
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: chipDiameter, maximum: chipDiameter), spacing: 8)],
                         alignment: .leading, spacing: 8) {
            ForEach(1...clampedMax, id: \.self) { week in
                weekChip(week).id(week)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // 40dp Circle chip: 选中 primary/Bold/onPrimary,未选中 surfaceContainerHigh/Regular/onSurface
    @ViewBuilder
    private func weekChip(_ w: Int) -> some View {
        let isCurrent = w == currentWeek
        if style == .liquidGlass {
            Button { onSelect(w) } label: {
                Text("\(w)")
                    .font(.system(size: 14, weight: isCurrent ? .bold : .regular))
                    .foregroundColor(isCurrent ? colors.onPrimary : colors.onSurface)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(SleepyPlatformButtonStyle(prominent: isCurrent,
                                                   cornerRadius: 20, compact: true, shape: .circle))
            .tint(colors.primary)
            .frame(width: chipDiameter, height: chipDiameter)
            .accessibilityIdentifier("week_num_\(w)")
            .accessibilityAddTraits(isCurrent ? .isSelected : [])
        } else {
            classicWeekChip(w, isCurrent: isCurrent)
        }
    }

    private func classicWeekChip(_ w: Int, isCurrent: Bool) -> some View {
        Button {
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
    @Environment(\.sleepyUIStyle) private var style
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
                    .frame(height: style == .classic ? 56 : nil)
                    .sleepyControlSurface(cornerRadius: SleepyShapes.large, tint: colors.primary, prominent: true)
            }
            .buttonStyle(SleepyPlatformButtonStyle(prominent: true, cornerRadius: SleepyShapes.large))
            .frame(minHeight: 56)
            .tint(colors.primary)
            Button(action: onImport) {
                Text(L10n.format("schedule_go_manage"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(colors.onSecondaryContainer)
                    .frame(maxWidth: .infinity)
                    .frame(height: style == .classic ? 56 : nil)
                    .sleepyControlSurface(cornerRadius: SleepyShapes.large, tint: colors.secondaryContainer, prominent: true)
            }
            .buttonStyle(SleepyPlatformButtonStyle(prominent: true, cornerRadius: SleepyShapes.large))
            .frame(minHeight: 56)
            .tint(colors.secondaryContainer)
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
    @Environment(\.sleepyUIStyle) private var style
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
                    .frame(height: style == .classic ? 56 : nil)
                    .sleepyControlSurface(cornerRadius: SleepyShapes.large, tint: colors.primary, prominent: true)
            }
            .buttonStyle(SleepyPlatformButtonStyle(prominent: true, cornerRadius: SleepyShapes.large))
            .frame(minHeight: 56)
            .tint(colors.primary)
            Button(action: onCreateTable) {
                Text(L10n.format("schedule_empty_create_table"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(colors.onSecondaryContainer)
                    .frame(maxWidth: .infinity)
                    .frame(height: style == .classic ? 56 : nil)
                    .sleepyControlSurface(cornerRadius: SleepyShapes.large, tint: colors.secondaryContainer, prominent: true)
            }
            .buttonStyle(SleepyPlatformButtonStyle(prominent: true, cornerRadius: SleepyShapes.large))
            .frame(minHeight: 56)
            .tint(colors.secondaryContainer)
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
