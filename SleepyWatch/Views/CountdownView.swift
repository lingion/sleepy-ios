// CountdownView.swift — 全屏沉浸式倒计时 (2026-10 watch 伴侣 App)
// 手表独创交互: 双击今日页头卡进入, 大字显示距下课/距上课分钟数。
// 课间趴桌上一抬腕就看到, 零交互成本 (always-on / wrist-raise)。
//
// UI 对齐: 配色走 WatchPalette (同源 resolveWidgetScheme), 字号用系统 bold
// monospacedDigit (与 iOS TodayCourseCard 时间槽 .system(size:16, weight:.bold)
// 同族, 手表放大到 48pt 适配圆屏), 胶囊 Stat 复用 TodayView.stat 同款形态。
// 数据源 = WatchStore.classState 同口径 (ownTime 直读时钟 / 节次查 timeJson)。

import SwiftUI

struct CountdownView: View {
    let table: TimeTableEntity

    @EnvironmentObject private var store: WatchStore
    @Environment(\.colorScheme) private var envScheme

    var body: some View {
        let scheme = WatchPalette.scheme(envDark: envScheme == .dark)
        // 每分钟刷新一次 (TimelineView 是 watchOS 原生省电刷新机制)
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let now = context.date
            let effective = store.tableForDisplay(table, on: now)
            let courses = store.courses(on: now, table: effective)
            let state = computeState(courses: courses, table: effective, now: now)

            ZStack {
                // 背景: 进行中 = primaryContainer (与 iOS Stat 周次胶囊同源色);
                // 课间/无课 = surfaceVariant
                (state.phase == .inClass ? scheme.primaryContainer : scheme.surfaceVariant)
                    .ignoresSafeArea()

                VStack(spacing: 8) {
                    // 状态标签
                    Text(state.label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(state.phase == .inClass
                                           ? scheme.onPrimaryContainer
                                           : scheme.onSurfaceVariant)

                    // 大字倒计时 — M3 displaySmall=36pt (最大 display 层级)
                    Text(state.countdownText)
                        .font(SleepyTypography.displaySmall).fontWeight(.bold).monospacedDigit()
                        .foregroundColor(state.phase == .inClass
                                         ? scheme.onPrimaryContainer
                                         : scheme.onSurface)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)

                    // 课程名 (进行中/下一节时显示)
                    if let name = state.courseName {
                        Text(name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(state.phase == .inClass
                                             ? scheme.onPrimaryContainer.opacity(SleepyTheme.Alpha.highContent)
                                             : scheme.onSurfaceVariant)
                            .lineLimit(1)
                    }
                }
                .padding(8)
            }
        }
        .navigationTitle(Text(L10n.t("watch_countdown_title")))
    }

    // MARK: - 状态计算 (与 TodayView.classState 同口径)

    private enum Phase { case inClass, between, done }

    private struct State {
        let phase: Phase
        let label: String
        let countdownText: String
        let courseName: String?
    }

    private func computeState(courses: [CourseEntity], table: TimeTableEntity, now: Date) -> State {
        let bells = ReminderBellTimes(table.timeJson)
        let items = courses.compactMap { WatchAgendaCore.item(for: $0, bells: bells, now: now) }
            .sorted { $0.startDate < $1.startDate }
        if let current = WatchAgendaCore.currentClass(in: items, now: now) {
            let remaining = Int(current.endDate.timeIntervalSince(now) / 60)
            return State(phase: .inClass, label: L10n.t("watch_countdown_in_class"),
                         countdownText: "\(max(remaining, 0))", courseName: current.courseName)
        }
        if let next = WatchAgendaCore.nextClass(in: items, now: now) {
            return State(phase: .between, label: L10n.t("watch_countdown_next"),
                         countdownText: "\(next.minutesUntil(from: now))", courseName: next.courseName)
        }
        return State(phase: .done, label: L10n.t("watch_countdown_done"),
                     countdownText: "—", courseName: nil)
    }
}
