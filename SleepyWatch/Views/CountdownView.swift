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
            let courses = store.todayCourses(table: table)
                .map { $0.normalizeNode(timeJson: table.timeJson) }
                .sorted { $0.startNode < $1.startNode }
            let state = computeState(courses: courses, table: table, now: now)

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
                        .font(.system(size: 36, weight: .bold).monospacedDigit())
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
        let nodes = TimeTableUtils.parseNodes(table.timeJson)
        let cal = Calendar(identifier: .gregorian)
        let day = cal.startOfDay(for: now)

        func clock(_ s: String) -> Date? {
            guard let p = SleepyNativeFormat.parseClock(s) else { return nil }
            return day.addingTimeInterval(TimeInterval(p.h * 3600 + p.min * 60))
        }

        func interval(_ c: CourseEntity) -> (Date, Date)? {
            if (c.ownTime || c.isIrregularTime), !c.startTime.isEmpty, !c.endTime.isEmpty,
               let st = clock(c.startTime), let en = clock(c.endTime) {
                return (st, en)
            }
            if c.isIrregularNode { return nil }
            guard let s = nodes.first(where: { $0.node == c.startNode }),
                  let e = nodes.first(where: { $0.node == c.startNode + c.step - 1 })
            else { return nil }
            let st = combine(cal, day, s.start)
            let en = combine(cal, day, e.end)
            return (st, en)
        }

        // 找进行中 / 下一节
        for c in courses {
            guard let (st, en) = interval(c) else { continue }
            if now >= st && now < en {
                let remaining = Int(en.timeIntervalSince(now) / 60)
                return State(phase: .inClass,
                             label: L10n.t("watch_countdown_in_class"),
                             countdownText: "\(max(remaining, 0))",
                             courseName: c.courseName)
            }
            if now < st {
                let until = Int(st.timeIntervalSince(now) / 60)
                return State(phase: .between,
                             label: L10n.t("watch_countdown_next"),
                             countdownText: "\(until)",
                             courseName: c.courseName)
            }
        }

        return State(phase: .done,
                     label: L10n.t("watch_countdown_done"),
                     countdownText: "—",
                     courseName: nil)
    }

    private func combine(_ cal: Calendar, _ day: Date, _ time: Date) -> Date {
        let secs = cal.component(.hour, from: time) * 3600 + cal.component(.minute, from: time) * 60
        return day.addingTimeInterval(TimeInterval(secs))
    }
}
