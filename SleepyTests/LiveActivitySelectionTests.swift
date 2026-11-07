import XCTest
@testable import Sleepy

final class LiveActivitySelectionTests: XCTestCase {
    private let midnight = CourseOccurrences.parseDate("2026-11-02")!
    private func time(_ minute: Int) -> Date { midnight.addingTimeInterval(Double(minute) * 60) }
    private func course(_ id: Int64, _ start: Int, _ end: Int, room: String = "101") -> ClassDayActivityCore.Course {
        .init(tableId: 1, courseId: id, tableName: "A", name: "C\(id)", room: room,
              start: time(start), end: time(end))
    }

    func testRespectsConfiguredLeadTime() {
        let courses = [course(1, 600, 650)]
        XCTAssertNil(ClassDayActivityCore.selection(from: courses, now: time(580), leadMinutes: 10))
        XCTAssertEqual(ClassDayActivityCore.selection(from: courses, now: time(590), leadMinutes: 10)?.current.courseId, 1)
    }

    func testRunningCourseWinsOverUpcomingCourse() {
        let result = ClassDayActivityCore.selection(from: [course(1, 600, 650), course(2, 640, 690)], now: time(630), leadMinutes: 20)
        XCTAssertEqual(result?.current.courseId, 1)
        XCTAssertEqual(result?.next?.courseId, 2)
        XCTAssertEqual(result?.phase, .ongoing)
    }

    func testNextCourseExcludesEndedOverlappingCourse() {
        let courses = [course(1, 600, 720), course(2, 630, 640), course(3, 780, 840)]
        let result = ClassDayActivityCore.selection(from: courses, now: time(660), leadMinutes: 10)
        XCTAssertEqual(result?.current.courseId, 1)
        XCTAssertEqual(result?.next?.courseId, 3)
    }

    func testSelectionUsesTimeAfterLoadingCrossesAClassBoundary() {
        let courses = [course(1, 600, 650)]
        XCTAssertEqual(ClassDayActivityCore.selection(from: courses, now: time(599), leadMinutes: 10)?.phase, .upcoming)
        XCTAssertEqual(ClassDayActivityCore.selection(from: courses, now: time(600), leadMinutes: 10)?.phase, .ongoing)
        XCTAssertNil(ClassDayActivityCore.selection(from: courses, now: time(650), leadMinutes: 10))
    }

    func testBreakSelectsUpcomingCourse() {
        let result = ClassDayActivityCore.selection(from: [course(1, 480, 540), course(2, 550, 600)], now: time(545), leadMinutes: 10)
        XCTAssertEqual(result?.current.courseId, 2)
        XCTAssertEqual(result?.phase, .upcoming)
        XCTAssertEqual(result?.refreshAt, time(550))
    }

    func testEndBoundaryIsExclusiveAndInvalidTimesAreIgnored() {
        XCTAssertNil(ClassDayActivityCore.selection(from: [course(1, 480, 540), course(2, 540, 540), course(3, 541, 539)], now: time(540), leadMinutes: 10))
    }

    func testAnotherDayCannotMatchByMinuteOfDay() {
        XCTAssertNil(ClassDayActivityCore.selection(from: [course(1, 480, 540)], now: time(500 + 1440), leadMinutes: 10))
    }

    func testEachGateDisablesLiveReminders() {
        let suite = "live-gates-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = AppPrefs(defaults: defaults)
        prefs.setBeforeClassMode(AppPrefs.BEFORE_CLASS_MODE_FLUID)
        prefs.setReminderEnabled(true)
        prefs.setBeforeClassEnabled(true)
        XCTAssertTrue(ClassDayActivityCore.isEnabled(prefs: prefs))
        prefs.setReminderEnabled(false)
        XCTAssertFalse(ClassDayActivityCore.isEnabled(prefs: prefs))
        prefs.setReminderEnabled(true)
        prefs.setBeforeClassEnabled(false)
        XCTAssertFalse(ClassDayActivityCore.isEnabled(prefs: prefs))
        prefs.setBeforeClassEnabled(true)
        prefs.setBeforeClassMode(AppPrefs.BEFORE_CLASS_MODE_BANNER)
        XCTAssertFalse(ClassDayActivityCore.isEnabled(prefs: prefs))
    }

    func testUpcomingRefreshStartsAtLeadWindow() {
        XCTAssertEqual(ClassDayActivityCore.nextRefreshDate(from: [course(1, 600, 650)], now: time(580), leadMinutes: 10), time(590))
    }

    @available(iOS 16.1, *)
    func testPayloadIsBoundedForLongUnicodeFields() throws {
        let long = String(repeating: "🧑🏽‍💻", count: 3000)
        let input = ClassDayActivityCore.Course(tableId: 1, courseId: 1, tableName: long, name: long, room: long, start: time(600), end: time(650))
        let selected = try XCTUnwrap(ClassDayActivityCore.selection(from: [input], now: time(610), leadMinutes: 10))
        XCTAssertLessThan(try JSONEncoder().encode(SleepyClassActivityAttributes.ContentState(selection: selected)).count, 3500)
    }

    @available(iOS 16.1, *)
    func testSameStartWithChangedRoomOrEndChangesPayload() throws {
        let a = try XCTUnwrap(ClassDayActivityCore.selection(from: [course(1, 600, 650)], now: time(610), leadMinutes: 10))
        let b = try XCTUnwrap(ClassDayActivityCore.selection(from: [course(1, 600, 660, room: "202")], now: time(610), leadMinutes: 10))
        XCTAssertNotEqual(SleepyClassActivityAttributes.ContentState(selection: a), SleepyClassActivityAttributes.ContentState(selection: b))
    }
}
