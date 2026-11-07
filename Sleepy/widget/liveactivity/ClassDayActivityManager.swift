import ActivityKit
import Foundation
import UIKit
import os

@available(iOS 16.1, *)
@MainActor
enum ClassDayActivityManager {
    private static let logger = Logger(subsystem: "com.lingion.sleepy", category: "LiveActivity")
    private static var worker: Task<Void, Never>?
    private static var revision = 0
    private static var boundaryTimer: Timer?

    static func refresh() {
        revision += 1
        guard worker == nil else { return }
        worker = Task {
            var processed: Int
            repeat {
                processed = revision
                await reconcile(revision: processed)
            } while processed != revision
            worker = nil
        }
    }

    static func suspend() {
        boundaryTimer?.invalidate()
        boundaryTimer = nil
    }

    private static func reconcile(revision expected: Int) async {
        suspend()
        let prefs = AppPrefs.shared
        guard ClassDayActivityCore.isEnabled(prefs: prefs),
              ActivityAuthorizationInfo().areActivitiesEnabled else {
            await endAll()
            return
        }

        let loadDate = Date()
        let courses: [ClassDayActivityCore.Course]
        do {
            courses = try await loadCourses(now: loadDate)
        } catch {
            logger.error("Unable to load live-activity schedule: \(String(describing: error), privacy: .private)")
            await endAll()
            scheduleRefresh(at: Date().addingTimeInterval(60))
            return
        }
        guard expected == revision else { return }
        let now = Date()
        guard CourseOccurrences.calendar.isDate(loadDate, inSameDayAs: now) else {
            revision += 1
            return
        }
        let lead = prefs.getBeforeClassMinutes()
        let selection = ClassDayActivityCore.selection(from: courses, now: now, leadMinutes: lead)
        let nextBoundary = ClassDayActivityCore.nextRefreshDate(from: courses, now: now, leadMinutes: lead)
        scheduleRefresh(at: nextBoundary ?? now.addingTimeInterval(60))
        guard let selection else {
            await endAll()
            return
        }

        let state = SleepyClassActivityAttributes.ContentState(selection: selection)
        let activities = Activity<SleepyClassActivityAttributes>.activities
        let reusable = activities.first { activity in
            guard activity.activityState == .active || activity.activityState == .stale else { return false }
            let old = content(of: activity)
            return old.tableId == state.tableId && old.courseId == state.courseId
                && old.entries.first?.start == state.entries.first?.start
        }
        for activity in activities where activity.id != reusable?.id {
            await end(activity)
        }
        guard expected == revision, ClassDayActivityCore.isEnabled(prefs: prefs) else { return }
        if let reusable {
            guard content(of: reusable) != state else { return }
            if #available(iOS 16.2, *) {
                await reusable.update(ActivityContent(state: state, staleDate: selection.refreshAt))
            } else {
                await reusable.update(using: state)
            }
        } else {
            // iOS 16.1 supports local starts only while the app is in the foreground.
            guard UIApplication.shared.applicationState == .active else { return }
            do {
                if #available(iOS 16.2, *) {
                    _ = try Activity.request(attributes: SleepyClassActivityAttributes(),
                        content: ActivityContent(state: state, staleDate: selection.refreshAt), pushType: nil)
                } else {
                    _ = try Activity.request(attributes: SleepyClassActivityAttributes(), contentState: state, pushType: nil)
                }
            } catch {
                logger.error("Unable to start live activity: \(String(describing: error), privacy: .private)")
                scheduleRefresh(at: min(selection.refreshAt, now.addingTimeInterval(60)))
            }
        }
    }

    private static func content(of activity: Activity<SleepyClassActivityAttributes>) -> SleepyClassActivityAttributes.ContentState {
        if #available(iOS 16.2, *) { return activity.content.state }
        return activity.contentState
    }

    private static func endAll() async {
        for activity in Activity<SleepyClassActivityAttributes>.activities { await end(activity) }
    }

    private static func end(_ activity: Activity<SleepyClassActivityAttributes>) async {
        if #available(iOS 16.2, *) {
            await activity.end(nil, dismissalPolicy: .immediate)
        } else {
            await activity.end(using: nil, dismissalPolicy: .immediate)
        }
    }

    private static func scheduleRefresh(at date: Date) {
        suspend()
        guard UIApplication.shared.applicationState == .active else { return }
        let timer = Timer(timeInterval: max(1, date.timeIntervalSinceNow), repeats: false) { _ in
            Task { @MainActor in refresh() }
        }
        boundaryTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private static func loadCourses(now: Date) async throws -> [ClassDayActivityCore.Course] {
        let repository = ScheduleRepository(AppDatabase.getShared())
        let calendar = CourseOccurrences.calendar
        let day = calendar.startOfDay(for: now)
        var result: [ClassDayActivityCore.Course] = []
        for raw in try repository.getAllTables() where raw.reminderEnabled {
            let period = try raw.periodTableId.flatMap { try repository.getPeriodTable($0) }
            let table = raw.hydratedWith(period)
            guard await HolidayReminderPolicyAdapter.decide(date: now, tableId: table.id).allowReminder else { continue }
            let courses = CourseOccurrences.coursesForDate(now, startDate: table.startDate, maxWeek: table.maxWeek,
                courses: try repository.getCourses(table.id), transfers: HolidayTransferHelper.transfers(for: table.id))
            for course in courses {
                guard let times = TimeTableUtils.effectiveCourseTime(
                    isIrregularTime: course.ownTime || course.isIrregularTime,
                    startTime: course.startTime, endTime: course.endTime,
                    startNode: course.startNode, step: course.step, timeJson: table.timeJson),
                    let startMinute = TimeTableUtils.hmMinutes(times.0),
                    let endMinute = TimeTableUtils.hmMinutes(times.1), endMinute > startMinute,
                    let start = calendar.date(byAdding: .minute, value: startMinute, to: day),
                    let end = calendar.date(byAdding: .minute, value: endMinute, to: day) else { continue }
                result.append(.init(tableId: table.id, courseId: course.id, tableName: table.name,
                                    name: course.courseName, room: course.room, start: start, end: end))
            }
        }
        return result
    }
}
