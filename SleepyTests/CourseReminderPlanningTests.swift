import XCTest
@testable import Sleepy

final class CourseReminderPlanningTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func course(_ id: Int64, startsIn minutes: Double, duration: Double = 50) -> CourseReminderOccurrence {
        .init(tableId: 1, courseId: id, tableName: "课表", name: "课程", room: "101",
              start: now.addingTimeInterval(minutes * 60), end: now.addingTimeInterval((minutes + duration) * 60))
    }

    func testNewSystemsPlanCurrentAndNearestFutureWithinAppBudget() {
        let current = course(1, startsIn: -10)
        let first = course(2, startsIn: 60)
        let second = course(3, startsIn: 120)
        let later = course(4, startsIn: 180)
        XCTAssertEqual(ClassDayActivityCore.activityPlan(from: [later, second, current, first], now: now,
            leadMinutes: 10, supportsScheduling: true), [current, first, second])
    }

    func testOlderSystemsNeverPretendToScheduleFutureCourse() {
        XCTAssertTrue(ClassDayActivityCore.activityPlan(from: [course(1, startsIn: 60)], now: now,
            leadMinutes: 10, supportsScheduling: false).isEmpty)
        let upcoming = course(1, startsIn: 5)
        XCTAssertEqual(ClassDayActivityCore.activityPlan(from: [upcoming], now: now,
            leadMinutes: 10, supportsScheduling: false), [upcoming])
    }

    func testActivityExceedingEightHourWindowFallsBackToNotifications() {
        XCTAssertTrue(ClassDayActivityCore.activityPlan(from: [course(1, startsIn: 600)], now: now,
            leadMinutes: 999, supportsScheduling: true).isEmpty)
    }

    func testEndedInvalidAndDuplicateOccurrencesDoNotConsumeCapacity() {
        let next = course(2, startsIn: 60)
        XCTAssertEqual(ClassDayActivityCore.activityPlan(from: [course(1, startsIn: -120),
            course(3, startsIn: 30, duration: -5), next, next], now: now,
            leadMinutes: 10, supportsScheduling: true), [next])
    }

    func testSameCourseOnDifferentDatesHasDifferentNotificationIdentity() {
        let today = course(1, startsIn: 60)
        let tomorrow = course(1, startsIn: 1500)
        XCTAssertNotEqual(today.notificationIdentifier, tomorrow.notificationIdentifier)
        XCTAssertEqual(CourseReminderOccurrence.ordered([tomorrow, today]).count, 2)
    }

    func testNotificationTriggerRetainsAbsoluteCourseTimeAndSeconds() throws {
        let fire = try XCTUnwrap(CourseOccurrences.parseDate("2026-11-12")).addingTimeInterval(8 * 3600 + 30 * 60 + 25)
        let components = CourseReminderOccurrence.notificationDateComponents(for: fire)
        XCTAssertEqual(components.timeZone, CourseOccurrences.calendar.timeZone)
        XCTAssertEqual(components.date, fire)
        XCTAssertEqual(components.hour, 8)
        XCTAssertEqual(components.minute, 30)
        XCTAssertEqual(components.second, 25)
        var overseas = Calendar(identifier: .gregorian)
        overseas.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        XCTAssertEqual(overseas.date(from: components), fire)
    }

    func testLeadTimeIsBoundedAndZeroBudgetDoesNotSchedule() {
        let next = course(1, startsIn: 60)
        XCTAssertEqual(next.reminderDate(leadMinutes: -10), next.start)
        XCTAssertEqual(next.reminderDate(leadMinutes: 2000), next.start.addingTimeInterval(-999 * 60))
        XCTAssertTrue(ClassDayActivityCore.activityPlan(from: [next], now: now,
            leadMinutes: 10, supportsScheduling: true, budget: 0).isEmpty)
    }

    @available(iOS 16.1, *)
    func testScheduledStateUsesFixedTimesAndFitsPayloadLimit() throws {
        var item = course(1, startsIn: 60)
        item.teacher = String(repeating: "很长的教师名", count: 2000)
        let state = SleepyClassActivityAttributes.ContentState(course: item,
            reminderStart: item.reminderDate(leadMinutes: 10), scheduled: true)
        XCTAssertEqual(state.phase, "scheduled")
        XCTAssertTrue(state.usesFixedCourseTimes)
        XCTAssertEqual(state.occurrenceIdentifier, item.identifier)
        let encoder = JSONEncoder()
        XCTAssertLessThan(try encoder.encode(state).count + encoder.encode(SleepyClassActivityAttributes()).count, 4096)
    }
}
