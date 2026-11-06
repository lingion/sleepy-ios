// ClassDayActivityManager.swift — 实况活动生命周期 (v1.0.64)
//
// 能力上限(与 ReminderScreen 文案、SPEC 差异表同源, 不可含糊):
//   - 纯本地 App, 无服务端 → 只能 Activity.request 本地创建, 退后台后无法新建/更新。
//     现实策略 = 前台/唤醒时刷新「当前段」; 课间隔 >1h 的下一段要等下次回前台。
//   - 段内倒计时由 Text(timerInterval:) 系统自己走字, 长时间不刷新也不会显示过期数值。
//
// 共源编译(Sleepy 主 App 调用; SleepyWidget 也会编入本文件但因无人调用可忽略)。
// iOS 16.1+ 门控 — 调用方一律 #available 守卫。

import ActivityKit
import Foundation

@available(iOS 16.1, *)
enum ClassDayActivityManager {

    /// 幂等刷新: 按当前前置提醒模式(fluid=实况) + 今日课程, 维护至多一条活动。
    /// - 模式非 fluid / 今日无进行或未来课 → 结束全部本 App 活动
    /// - 已有活动且段起点不同 → update; 无活动 → request
    static func refresh() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let mode = AppPrefs.shared.getBeforeClassMode()
        guard mode == AppPrefs.BEFORE_CLASS_MODE_FLUID else {
            endAll()
            return
        }

        let repo = ScheduleRepository(AppDatabase.getShared())
        guard let table = WidgetTableResolver.resolveCurrentTable(repo),
              let courses = try? repo.getCourses(table.id) else {
            endAll()
            return
        }
        let items = WatchAgendaCore.dayItems(table: table, courses: courses, date: Date())
        guard let segment = ClassDayActivityCore.activeSegment(from: items, now: Date()) else {
            endAll()
            return
        }

        let state = SleepyClassActivityAttributes.ContentState(
            tableName: table.name,
            entries: segment.map {
                SleepyClassActivityAttributes.Entry(name: $0.courseName, room: $0.room,
                                                    start: $0.startDate, end: $0.endDate)
            })

        if let existing = Activity<SleepyClassActivityAttributes>.activities.first {
            let sameSegment = existing.contentState.entries.map(\.start) == state.entries.map(\.start)
            guard !sameSegment else { return }
            Task {
                if #available(iOS 16.2, *) {
                    await existing.update(ActivityContent(state: state, staleDate: nil))
                } else {
                    await existing.update(using: state)
                }
            }
        } else {
            do {
                _ = try Activity.request(attributes: SleepyClassActivityAttributes(),
                                         contentState: state, pushType: nil)
            } catch {
                // 系统限额/繁忙 — 静默; 下次前台刷新再试(不向用户报错, 避免误导向)
            }
        }
    }

    /// 结束本 App 的全部活动(立即移除, 不留锁屏残影)。
    static func endAll() {
        for activity in Activity<SleepyClassActivityAttributes>.activities {
            Task {
                if #available(iOS 16.2, *) {
                    await activity.end(nil, dismissalPolicy: .immediate)
                } else {
                    await activity.end(using: nil, dismissalPolicy: .immediate)
                }
            }
        }
    }
}
