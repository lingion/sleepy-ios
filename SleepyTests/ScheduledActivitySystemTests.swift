import ActivityKit
import UIKit
import XCTest
@testable import Sleepy

/// Exercises the real system API, isolated to a short-lived test course.
final class ScheduledActivitySystemTests: XCTestCase {
    @MainActor
    func testScheduledActivityStartsAndEndsThroughSystem() async throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("Requires iOS 26 scheduling") }
        guard UIApplication.shared.applicationState == .active else { throw XCTSkip("App must be foreground to schedule") }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { throw XCTSkip("Live Activities disabled on this test device") }
        let now = Date()
        let fire = now.addingTimeInterval(5)
        let course = CourseReminderOccurrence(tableId: -910, courseId: -910, tableName: "System API test",
            name: "Scheduled course test", room: "Test room", start: fire.addingTimeInterval(30), end: fire.addingTimeInterval(60))
        let state = SleepyClassActivityAttributes.ContentState(course: course, reminderStart: fire, scheduled: true)
        let activity = try Activity.request(attributes: SleepyClassActivityAttributes(),
            content: ActivityContent(state: state, staleDate: course.end), pushType: nil, style: .standard,
            alertConfiguration: AlertConfiguration(title: "Scheduled course test", body: "System scheduling verification", sound: .default),
            start: fire)
        XCTAssertEqual(activity.activityState, .pending)
        let deadline = Date().addingTimeInterval(20)
        while activity.activityState == .pending && Date() < deadline {
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        let observed = activity.activityState
        await activity.end(nil, dismissalPolicy: .immediate)
        XCTAssertEqual(observed, .active, "The system should activate the scheduled request without an app timer")
        XCTAssertTrue(activity.activityState == .ended || activity.activityState == .dismissed)
    }

    @MainActor
    func testCancellingPendingActivityPreventsItsStart() async throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("Requires iOS 26 scheduling") }
        guard UIApplication.shared.applicationState == .active else { throw XCTSkip("App must be foreground to schedule") }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { throw XCTSkip("Live Activities disabled on this test device") }
        let fire = Date().addingTimeInterval(5)
        let course = CourseReminderOccurrence(tableId: -911, courseId: -911, tableName: "System API test",
            name: "Cancelled course test", room: "Test room", start: fire.addingTimeInterval(30), end: fire.addingTimeInterval(60))
        let activity = try Activity.request(attributes: SleepyClassActivityAttributes(),
            content: ActivityContent(state: .init(course: course, reminderStart: fire, scheduled: true), staleDate: course.end),
            pushType: nil, style: .standard,
            alertConfiguration: AlertConfiguration(title: "Cancelled course test", body: "Should not be shown", sound: .default), start: fire)
        XCTAssertEqual(activity.activityState, .pending)
        await activity.end(nil, dismissalPolicy: .immediate)
        try? await Task.sleep(nanoseconds: 6_000_000_000)
        XCTAssertNotEqual(activity.activityState, .active)
        XCTAssertNotEqual(activity.activityState, .pending)
    }
}
