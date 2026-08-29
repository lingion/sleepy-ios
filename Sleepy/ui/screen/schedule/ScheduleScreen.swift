// ScheduleScreen.swift — ← ui/screen/schedule/ScheduleScreen.kt
// 课表页: TopBar(周导航+跳周菜单) + 视图切换(周视图/网格) + 左右滑翻周(TabView pager) +
// 详情 BottomSheet。空态两分支: 无表 → EmptyState; 有表无课 → NoCourseState。

import SwiftUI

private enum ViewMode: Hashable {
    case full   // ← ViewMode.Full (周视图)
    case cards  // ← ViewMode.Cards (网格)
}

struct ScheduleScreen: View {
    @Environment(\.localWakeUpColors) private var colors
    @ObservedObject var viewModel: ScheduleViewModel
    var onGoImport: () -> Void = {}
    var onManualAdd: () -> Void = {}
    var onEditCourse: (CourseEntity) -> Void = { _ in }

    @State private var viewMode: ViewMode = .full
    @State private var selectedCourse: CourseEntity? = nil

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
                EmptyState(onGoImport: onGoImport, onManualAdd: onManualAdd)
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
                    maxWeek: state.currentTable?.maxWeek ?? 20,
                    startDate: state.currentTable?.startDate ?? "",
                    onPrevWeek: { viewModel.changeWeek(state.selectedWeek - 1) },
                    onNextWeek: { viewModel.changeWeek(state.selectedWeek + 1) },
                    onJumpToActual: {
                        guard let start = state.currentTable?.startDate else { return }
                        viewModel.changeWeek(DateUtils.currentWeek(startDate: start))
                    },
                    onSelectWeek: { week in viewModel.changeWeek(week) })

                // Segmented Switcher
                SegmentedSwitcher(
                    options: [(ViewMode.full, L10n.format("view_full")),
                              (ViewMode.cards, L10n.format("view_cards"))],
                    selected: viewMode) { viewMode = $0 }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                // 主体视图 — 左右滑动切换周次(TabView pager)
                let pagerMaxWeek = max(state.currentTable?.maxWeek ?? 20, 1)
                WeekPager(viewModel: viewModel, viewMode: viewMode, pagerMaxWeek: pagerMaxWeek,
                          displayMode: displayMode, showDate: showDate, visibleDays: visibleDays) {
                    selectedCourse = $0
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // 详情 Bottom Sheet
        .sheet(item: $selectedCourse) { course in
            CourseDetailSheet(
                course: course,
                timeString: course.nodeString(),
                onEdit: { c in
                    selectedCourse = nil
                    onEditCourse(c)
                })
        }
    }
}

// HorizontalPager → TabView(.page): 双向同步(手势→VM / VM→pager)
// Cards 网格的 TimeSlot: parseNodes 每节一行(node/nodeStart 单节, Android 同为逐节行)
private func cardTimeSlots(table: TimeTableEntity?) -> [TimeSlot] {
    let nodes = TimeTableUtils.parseNodes(table?.timeJson ?? TimeTableUtils.DEFAULT_TIME_JSON)
    return nodes.map { n in
        let sc = Calendar.current.dateComponents([.hour, .minute], from: n.start)
        let ec = Calendar.current.dateComponents([.hour, .minute], from: n.end)
        return TimeSlot(label: "\(n.node)", startHour: sc.hour ?? 0, startMinute: sc.minute ?? 0,
                        endHour: ec.hour ?? 0, endMinute: ec.minute ?? 0, nodeStart: n.node)
    }
}
private struct WeekPager: View {
    @ObservedObject var viewModel: ScheduleViewModel
    let viewMode: ViewMode
    let pagerMaxWeek: Int
    let displayMode: String
    let showDate: Bool
    let visibleDays: Set<Int>
    let onCourseClick: (CourseEntity) -> Void

    // 本页灰显的星期几 ← Android produceState greyDays: 逐日 shouldGrey
    @State private var greyDays: Set<Int> = []
    @State private var greyLoadedWeek: Int = -1

    var body: some View {
        let state = viewModel.state
        // VM 变化(TopBar 点击) → 同步 pager(binding 直写, 防双向打架由 onChange 用户手势分支承担)
        TabView(selection: Binding(
            get: { min(max(state.selectedWeek, 1), pagerMaxWeek) },
            set: { newWeek in viewModel.changeWeek(newWeek) }   // 手势滑动 → VM
        )) {
            ForEach(1...pagerMaxWeek, id: \.self) { page in
                // page 是 1-based 周索引,独立于 state.currentWeek 过滤课程
                let weekCourses: [CourseEntity] = {
                    let list = state.courses.filter { $0.inWeek(page) }
                    guard let tj = state.currentTable?.timeJson else { return list }
                    return list.map { $0.normalizeNode(timeJson: tj) }
                }()
                Group {
                    switch viewMode {
                    case .full:
                        FullWeekView(courses: weekCourses,
                                     visibleDays: visibleDays,
                                     displayMode: displayMode,
                                     timeJson: state.currentTable?.timeJson ?? "",
                                     onCourseClick: onCourseClick,
                                     greyDays: page == state.selectedWeek ? greyDays : [])
                    case .cards:
                        CardsGridView(courses: weekCourses,
                                      timeSlots: cardTimeSlots(table: state.currentTable),
                                      visibleDays: visibleDays,
                                      showDate: showDate,
                                      startDate: state.currentTable?.startDate ?? "",
                                      currentWeek: page,
                                      onCourseClick: onCourseClick,
                                      greyDays: page == state.selectedWeek ? greyDays : [])
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .tag(page)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tabViewStyle(.page(indexDisplayMode: .never))
        // 计算本周哪些天是节假日/周末(灰显用) ← Android produceState(greyDays, page, startDate)
        .task(id: "\(state.selectedWeek)-\(state.currentTable?.startDate ?? "")") {
            let start = state.currentTable?.startDate ?? ""
            guard !start.isEmpty else {
                greyDays = []
                greyLoadedWeek = state.selectedWeek
                return
            }
            let week = state.selectedWeek
            if week == greyLoadedWeek { return }
            var grey: Set<Int> = []
            for day in 1...7 {
                if let date = DateUtils.dateOfWeek(startDate: start, week: week, dayOfWeek: day),
                   await HolidayManager.shouldGrey(date) {
                    grey.insert(day)
                }
            }
            greyDays = grey
            greyLoadedWeek = week
        }
    }
}

// ← TopBar
private struct ScheduleTopBar: View {
    @Environment(\.localWakeUpColors) private var colors
    let currentWeek: Int
    let maxWeek: Int
    let startDate: String
    let onPrevWeek: () -> Void
    let onNextWeek: () -> Void
    let onJumpToActual: () -> Void
    let onSelectWeek: (Int) -> Void

    @State private var menuOpen = false

    var body: some View {
        let actualWeek = startDate.isEmpty ? 1 : DateUtils.currentWeek(startDate: startDate)
        let isOnActual = currentWeek == actualWeek
        let semesterStatus = DateUtils.semesterStatus(startDate: startDate, maxWeek: maxWeek)

        HStack {
            WeekNavButton(icon: "chevron.left", onClick: onPrevWeek)

            // 第 N 周 标签 — 点击行为根据是否在当前实际周而不同
            // ★ iOS 16 修复(二段): Menu 挂非 Button 顶层内容(VStack/LazyVGrid)在
            //   iOS 16 上点击不展开(实测 menu 元素为 0)→ 改为 Button + sheet 弹层,
            //   与 Android FlowRow 280dp 弹层语义一致。
            Button {
                if isOnActual {
                    menuOpen = true
                } else {
                    onJumpToActual()   // 不在实际周 → 一键跳回(原 simultaneousGesture 语义)
                }
            } label: {
                // ★ 学期外: 标签带上周数(学期未开始 · 第 3 周), 翻周时数字跟着变, 用户才知道自己看到第几周
                Text(semesterStatus == .inRange
                     ? L10n.format("schedule_current_week", currentWeek)
                     : "\(L10n.format(semesterStatus == .beforeStart ? "semester_not_started" : "semester_ended")) · \(L10n.format("schedule_week_prefix", currentWeek))")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isOnActual ? colors.onPrimaryContainer : colors.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .allowsTightening(true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(isOnActual ? colors.primaryContainer
                                           : colors.primaryContainer.opacity(SleepyTheme.Alpha.inactive))
                    .cornerRadius(SleepyShapes.medium)
            }
            .buttonStyle(SleepyButtonStyle())
            .accessibilityIdentifier("week_label")   // ← G5: 跳周菜单锚点
            .sheet(isPresented: $menuOpen) {
                // 标签式选周(← Android FlowRow 280dp 弹层)
                VStack(spacing: 12) {
                    Text(L10n.format("schedule_jump_week"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(colors.onSurfaceVariant)
                    ScrollView {
                        // 弹层宽度自适应: 40dp 圆钮 x5 列装不下时按可用宽缩列距(窄屏 iPhone SE 可用)
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(40), spacing: 8), count: 5),
                                  spacing: 8) {
                            ForEach(1...maxWeek, id: \.self) { w in
                                let isCurrent = w == currentWeek
                                Button {
                                    onSelectWeek(w)
                                    menuOpen = false
                                } label: {
                                    Text("\(w)")
                                        .font(.system(size: 14, weight: isCurrent ? .bold : .regular))
                                        .foregroundColor(isCurrent ? colors.onPrimary : colors.onSurface)
                                        .frame(width: 40, height: 40)
                                        .background(isCurrent ? colors.primary : colors.surfaceContainerHigh)
                                        .clipShape(Circle())
                                }
                                .accessibilityIdentifier("week_num_\(w)")
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    .frame(maxHeight: 340)
                }
                .padding(.vertical, 16)
                .presentationDetents([.height(400)])
            }

            WeekNavButton(icon: "chevron.right", onClick: onNextWeek)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(colors.surface)
    }
}

// ← WeekNavButton
private struct WeekNavButton: View {
    @Environment(\.localWakeUpColors) private var colors
    let icon: String
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            Image(systemName: icon)
                .foregroundColor(colors.onSurfaceVariant)
                .frame(width: 32, height: 32)
                .background(colors.surfaceContainerHigh)
                .clipShape(Circle())
                .padding(6)
        }
        .buttonStyle(SleepyButtonStyle())
        // ← G5: 周导航箭头锚点(chevron.left → week_prev / chevron.right → week_next)
        .accessibilityIdentifier(icon.contains("left") ? "week_prev" : "week_next")
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
                .font(.system(size: 20, weight: .semibold))
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

// ← EmptyState
private struct EmptyState: View {
    @Environment(\.localWakeUpColors) private var colors
    let onGoImport: () -> Void
    let onManualAdd: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text(L10n.format("schedule_empty"))
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(colors.onSurface)
            Text(L10n.format("schedule_empty_hint"))
                .font(.system(size: 14))
                .foregroundColor(colors.onSurfaceVariant)
            Button(action: onGoImport) {
                Text(L10n.format("schedule_go_manage"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(colors.onPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(colors.primary)
                    .cornerRadius(SleepyShapes.large)
            }
            .buttonStyle(SleepyButtonStyle())
            Button(action: onManualAdd) {
                Text(L10n.format("schedule_manual_first"))
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
