import ActivityKit
import Combine
import Foundation
import UIKit
import os

/// In-memory system-request status, deliberately excluded from preference sync.
final class ClassDayActivityStatus: ObservableObject {
    static let shared = ClassDayActivityStatus()
    @Published var scheduledCount = 0
    @Published var coveredThrough: Date?
    @Published var hadFailure = false
}

@available(iOS 16.1, *)
@MainActor
enum ClassDayActivityManager {
    private static let logger = Logger(subsystem: "com.lingion.sleepy", category: "LiveActivity")
    private static var worker: Task<Void, Never>?
    private static var revision = 0
    private static var boundaryTimer: Timer?
    private static var observations: [String: Task<Void, Never>] = [:]
    private static let ledger = UserDefaults(suiteName: "sleepy_activity_ledger")

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

    /// Only an active system-scheduled activity can suppress a duplicate
    /// foreground presentation. Pending requests never remove notifications.
    static func notificationReplacements() -> Set<String> {
        guard #available(iOS 26.0, *),
              ClassDayActivityCore.isEnabled(prefs: AppPrefs.shared),
              ActivityAuthorizationInfo().areActivitiesEnabled else { return [] }
        return Set(Activity<SleepyClassActivityAttributes>.activities.compactMap { activity in
            guard activity.activityState == .active,
                  activity.content.state.phase == "scheduled",
                  let first = activity.content.state.entries.first, first.end > Date(),
                  let id = activity.content.state.occurrenceIdentifier else { return nil }
            return NotificationScheduler.NOTIFY_BEFORE_CLASS_PREFIX + id
        })
    }

    private static func reconcile(revision expected: Int) async {
        suspend()
        let prefs = AppPrefs.shared
        guard ClassDayActivityCore.isEnabled(prefs: prefs),
              ActivityAuthorizationInfo().areActivitiesEnabled else {
            await endAll()
            publishStatus(failed: false)
            return
        }
        let courses: [CourseReminderOccurrence]
        do { courses = try await NotificationScheduler.shared.upcomingOccurrences() }
        catch {
            // A transient database failure must not erase valid pending requests.
            logger.error("Unable to load live-activity schedule: \(String(describing: error), privacy: .private)")
            publishStatus(failed: true)
            scheduleRefresh(at: Date().addingTimeInterval(60))
            return
        }
        guard expected == revision else { return }
        let now = Date()
        let dismissed = (ledger?.dictionary(forKey: "dismissed") as? [String: Double] ?? [:])
            .filter { $0.value > now.timeIntervalSince1970 }
        ledger?.set(dismissed, forKey: "dismissed")
        let lead = prefs.getBeforeClassMinutes()
        let supportsScheduling: Bool
        if #available(iOS 26.0, *) { supportsScheduling = true } else { supportsScheduling = false }
        let planned = ClassDayActivityCore.activityPlan(from: courses.filter { dismissed[$0.identifier] == nil }, now: now,
            leadMinutes: lead, supportsScheduling: supportsScheduling)
        let wanted = Set(planned.map(\.identifier))
        for activity in Activity<SleepyClassActivityAttributes>.activities {
            let old = content(of: activity)
            if old.occurrenceIdentifier.map({ !wanted.contains($0) }) ?? true {
                await end(activity)
            }
        }
        var failed = false
        for course in planned {
            guard expected == revision, ClassDayActivityCore.isEnabled(prefs: prefs) else { return }
            let fire = course.reminderDate(leadMinutes: lead)
            var existing = Activity<SleepyClassActivityAttributes>.activities.first {
                isReusable($0) && content(of: $0).occurrenceIdentifier == course.identifier
            }
            let scheduled = existing.flatMap { activity -> Bool? in
                isPending(activity) ? nil : content(of: activity).phase == "scheduled"
            } ?? (supportsScheduling && fire > now)
            let state = SleepyClassActivityAttributes.ContentState(course: course, reminderStart: fire, scheduled: scheduled)
            // Content updates cannot replace the scheduled start or original
            // alert configuration. Recreate a changed pending request so course
            // names, rooms and times cannot leave an outdated system alert.
            if let activity = existing, isPending(activity), content(of: activity) != state {
                await end(activity)
                existing = nil
            }
            if let existing {
                if content(of: existing) != state {
                    if #available(iOS 16.2, *) {
                        await existing.update(ActivityContent(state: state, staleDate: course.end))
                    } else { await existing.update(using: state) }
                }
                observe(existing)
                continue
            }
            // Scheduling is a foreground operation. A BG task may restore
            // notifications, but is never used to promise a new activity.
            guard UIApplication.shared.applicationState == .active else { continue }
            do {
                let activity: Activity<SleepyClassActivityAttributes>
                if #available(iOS 26.0, *), fire > now {
                    // Apple: pending requests count toward the activity limit;
                    // scheduled starts require an explicit alert configuration.
                    // https://developer.apple.com/documentation/activitykit/activity/request(attributes:content:pushtype:style:alertconfiguration:start:)
                    activity = try Activity.request(attributes: SleepyClassActivityAttributes(),
                        content: ActivityContent(state: state, staleDate: course.end), pushType: nil,
                        style: .standard,
                        alertConfiguration: AlertConfiguration(title: "\(course.name)",
                            body: "\(TimeTableUtils.formatTime(course.start)) · \(course.room)", sound: .default),
                        start: fire)
                } else if #available(iOS 16.2, *) {
                    activity = try Activity.request(attributes: SleepyClassActivityAttributes(),
                        content: ActivityContent(state: state, staleDate: course.end), pushType: nil)
                } else {
                    activity = try Activity.request(attributes: SleepyClassActivityAttributes(), contentState: state, pushType: nil)
                }
                observe(activity)
            } catch {
                failed = true
                logger.error("Unable to request live activity: \(String(describing: error), privacy: .private)")
                // Retain the ordinary notification. Do not destroy other accepted
                // activities just to make room, or retry unboundedly in a loop.
                break
            }
        }
        guard expected == revision else { return }
        publishStatus(failed: failed)
        await NotificationScheduler.shared.scheduleNext7DaysExactAlarms()
        let boundary = ClassDayActivityCore.nextRefreshDate(from: courses, now: now, leadMinutes: lead)
        scheduleRefresh(at: failed ? min(boundary ?? now.addingTimeInterval(60), now.addingTimeInterval(60))
                        : boundary ?? CourseOccurrences.calendar.startOfDay(for: now).addingTimeInterval(86400))
    }

    private static func publishStatus(failed: Bool) {
        let pending = Activity<SleepyClassActivityAttributes>.activities.filter { isPending($0) }
        let status = ClassDayActivityStatus.shared
        status.scheduledCount = pending.count
        status.coveredThrough = pending.compactMap { content(of: $0).entries.first?.start }.max()
        status.hadFailure = failed
    }

    private static func isPending(_ activity: Activity<SleepyClassActivityAttributes>) -> Bool {
        if #available(iOS 26.0, *) { return activity.activityState == .pending }
        return false
    }

    private static func isReusable(_ activity: Activity<SleepyClassActivityAttributes>) -> Bool {
        if isPending(activity) { return true }
        if #available(iOS 16.2, *), activity.activityState == .stale { return true }
        return activity.activityState == .active
    }

    private static func observe(_ activity: Activity<SleepyClassActivityAttributes>) {
        guard observations[activity.id] == nil else { return }
        observations[activity.id] = Task {
            for await state in activity.activityStateUpdates {
                guard !Task.isCancelled else { return }
                if state == .dismissed || state == .ended {
                    if state == .dismissed, let id = content(of: activity).occurrenceIdentifier,
                       let end = content(of: activity).entries.first?.end {
                        var dismissed = ledger?.dictionary(forKey: "dismissed") as? [String: Double] ?? [:]
                        dismissed[id] = end.timeIntervalSince1970
                        ledger?.set(dismissed, forKey: "dismissed")
                    }
                    observations.removeValue(forKey: activity.id)
                    if UIApplication.shared.applicationState == .active { refresh() }
                    return
                }
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
        observations.removeValue(forKey: activity.id)?.cancel()
        if #available(iOS 16.2, *) { await activity.end(nil, dismissalPolicy: .immediate) }
        else { await activity.end(using: nil, dismissalPolicy: .immediate) }
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
}
