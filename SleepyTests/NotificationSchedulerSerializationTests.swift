import XCTest
import UserNotifications
@testable import Sleepy

final class NotificationSchedulerSerializationTests: XCTestCase {
    /// The test decides exactly when I/O returns; no network or notification
    /// permission is involved in these production scheduling entry points.
    private actor Suspension {
        let entered: XCTestExpectation
        private var used = false
        private var continuation: CheckedContinuation<Void, Never>?

        init(_ entered: XCTestExpectation) { self.entered = entered }

        func pauseOnce() async {
            guard !used else { return }
            used = true
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                entered.fulfill()
            }
        }

        func release() {
            continuation?.resume()
            continuation = nil
        }
    }

    private final class Environment: NotificationSchedulerBeforeClassEnv {
        private let lock = NSLock()
        private var master = true
        private var ledger: Set<String> = []
        let daily: Bool
        let beforeClass: Bool
        let today = DateUtils.parseDate("2026-11-09")!

        init(daily: Bool = false, beforeClass: Bool = true) {
            self.daily = daily
            self.beforeClass = beforeClass
        }

        func setMaster(_ value: Bool) { lock.lock(); defer { lock.unlock() }; master = value }
        func isReminderEnabled() -> Bool { lock.lock(); defer { lock.unlock() }; return master }
        func isDailyReminderEnabled() -> Bool { daily }
        func isTodayReminderEnabled() -> Bool { true }
        func isTomorrowReminderEnabled() -> Bool { false }
        func isBeforeClassEnabled() -> Bool { beforeClass }
        func beforeClassMinutes() -> Int { 10 }
        func nowEpochMs() -> Int64 { Int64(today.timeIntervalSince1970 * 1_000) }
        func todayDate() -> Date { today }
        func loadArmedIds() -> Set<String> { lock.lock(); defer { lock.unlock() }; return ledger }
        func saveArmedIds(_ ids: Set<String>) { lock.lock(); defer { lock.unlock() }; ledger = ids }
    }

    private final class Source: NotificationSchedulerBeforeClassDataSource {
        private let lock = NSLock()
        private var enteredFirstPolicy = false
        private var firstPolicyFinished = false
        private var overlap = false
        let pause: Suspension?
        let overlapExpectation: XCTestExpectation?
        let table = TimeTableEntity(name: "串行提醒", startDate: "2026-11-09", maxWeek: 2,
            timeJson: #"[{"node":1,"start":"08:00","end":"08:45"}]"#, id: 1)
        let course = CourseEntity(groupId: "math", tableId: 1, courseName: "数学", day: 1,
            startNode: 1, step: 1, startWeek: 1, endWeek: 2, color: "", id: 7)

        init(pause: Suspension? = nil, overlap: XCTestExpectation? = nil) {
            self.pause = pause
            self.overlapExpectation = overlap
        }

        func resolveCurrentTable() -> TimeTableEntity? { table }
        func coursesForDay(tableId: Int64, dayOfWeek: Int) -> [CourseEntity] {
            dayOfWeek == course.day ? [course] : []
        }
        func allCourseIds() -> [Int64] { [course.id] }
        func courseDateForDate(tableId: Int64?, date: Date) -> Date? { date }

        private func beginPolicy() -> Bool {
            lock.lock(); defer { lock.unlock() }
            if !enteredFirstPolicy {
                enteredFirstPolicy = true
                return true
            }
            if !firstPolicyFinished {
                overlap = true
                overlapExpectation?.fulfill()
            }
            return false
        }

        private func finishFirstPolicy() { lock.lock(); defer { lock.unlock() }; firstPolicyFinished = true }
        func observedOverlap() -> Bool { lock.lock(); defer { lock.unlock() }; return overlap }

        func allowsReminder(tableId: Int64, date: Date) async -> Bool {
            if beginPolicy() {
                await pause?.pauseOnce()
                finishFirstPolicy()
            }
            return true
        }
    }

    private final class Port: NotificationSchedulerBeforeClassAlarmPort {
        private let lock = NSLock()
        private var pending: Set<String> = []
        private var events: [String] = []
        let exactPause: Suspension?
        let summaryPause: Suspension?

        init(exactPause: Suspension? = nil, summaryPause: Suspension? = nil) {
            self.exactPause = exactPause
            self.summaryPause = summaryPause
        }

        private func begin(_ id: String) { lock.lock(); defer { lock.unlock() }; events.append("begin:\(id)") }
        private func finish(_ id: String) {
            lock.lock(); defer { lock.unlock() }
            pending.insert(id)
            events.append("finish:\(id)")
        }

        func setExact(id: String, epochMs: Int64, extras: [String: Any?]) async {
            begin(id)
            await exactPause?.pauseOnce()
            finish(id)
        }

        func write(_ request: UNNotificationRequest) async {
            begin(request.identifier)
            await summaryPause?.pauseOnce()
            finish(request.identifier)
        }

        func cancel(id: String) {
            lock.lock(); defer { lock.unlock() }
            pending.remove(id)
            events.append("cancel:\(id)")
        }

        func pendingIDs() -> Set<String> { lock.lock(); defer { lock.unlock() }; return pending }
        func recordedEvents() -> [String] { lock.lock(); defer { lock.unlock() }; return events }
    }

    private func emptyAgenda(_ date: Date) -> LoadedDailyAgenda {
        LoadedDailyAgenda(agenda: DailyAgenda(date: date, items: []), suppressed: false)
    }

    func testConcurrentResyncSuspendsWithoutEnteringAnotherOperation() async {
        let paused = expectation(description: "First holiday policy lookup suspended")
        let suspension = Suspension(paused)
        let overlap = expectation(description: "Second resync must wait without entering the data source")
        overlap.isInverted = true
        let env = Environment()
        let source = Source(pause: suspension, overlap: overlap)
        let port = Port()
        let scheduler = NotificationScheduler(env: env, dataSource: source, alarmPort: port)
        let first = Task { await scheduler.scheduleNext7DaysExactAlarms() }
        await fulfillment(of: [paused], timeout: 3)
        let second = Task { await scheduler.scheduleNext7DaysExactAlarms() }
        await fulfillment(of: [overlap], timeout: 0.1)
        await suspension.release()
        await first.value
        await second.value
        XCTAssertFalse(source.observedOverlap())
        XCTAssertEqual(port.pendingIDs(), [NotificationScheduler.NOTIFY_BEFORE_CLASS_PREFIX + "7"])
        XCTAssertEqual(env.loadArmedIds(), port.pendingIDs())
    }

    func testCancelWaitsForActualCourseWriteAndClearsRequestsAndLedger() async {
        let paused = expectation(description: "Actual course notification write suspended")
        let suspension = Suspension(paused)
        let env = Environment()
        let port = Port(exactPause: suspension)
        let scheduler = NotificationScheduler(env: env, dataSource: Source(), alarmPort: port)
        let first = Task { await scheduler.scheduleNext7DaysExactAlarms() }
        await fulfillment(of: [paused], timeout: 3)
        env.setMaster(false)
        let cancelStarted = expectation(description: "Cancellation reached the occupied schedule queue")
        let cancelReturned = expectation(description: "Cancellation cannot return before the write finishes")
        cancelReturned.isInverted = true
        let cancel = Task {
            cancelStarted.fulfill()
            await scheduler.cancelAll()
            cancelReturned.fulfill()
        }
        await fulfillment(of: [cancelStarted], timeout: 3)
        await fulfillment(of: [cancelReturned], timeout: 0.1)
        await suspension.release()
        await first.value
        await cancel.value
        XCTAssertTrue(port.pendingIDs().isEmpty)
        XCTAssertTrue(env.loadArmedIds().isEmpty)
        let id = NotificationScheduler.NOTIFY_BEFORE_CLASS_PREFIX + "7"
        let events = port.recordedEvents()
        let finished = events.firstIndex(of: "finish:\(id)")
        let cancelled = events.firstIndex(of: "cancel:\(id)")
        XCTAssertNotNil(finished)
        XCTAssertNotNil(cancelled)
        if let finished, let cancelled { XCTAssertLessThan(finished, cancelled) }

        env.setMaster(true)
        await scheduler.scheduleNext7DaysExactAlarms()
        XCTAssertEqual(port.pendingIDs(), [id], "A completed cancel must release the queue for later rescheduling")
        XCTAssertEqual(env.loadArmedIds(), [id])
    }

    private func checkSuspendedDailyLoadCannotRestoreAfterMasterOff(throwsAfterLoad: Bool) async {
        let paused = expectation(description: "Daily agenda load suspended")
        let suspension = Suspension(paused)
        let env = Environment(daily: true, beforeClass: false)
        let port = Port()
        let scheduler = NotificationScheduler(env: env, dataSource: Source(), alarmPort: port,
            writeNotification: { await port.write($0) },
            loadAgenda: { date in
                await suspension.pauseOnce()
                if throwsAfterLoad { throw NSError(domain: "injected", code: 1) }
                return self.emptyAgenda(date)
            })
        let first = scheduler.scheduleAll()
        await fulfillment(of: [paused], timeout: 3)
        env.setMaster(false)
        let cancel = Task { await scheduler.cancelAll() }
        await suspension.release()
        await first.value
        await cancel.value
        XCTAssertTrue(port.pendingIDs().isEmpty)
        XCTAssertTrue(env.loadArmedIds().isEmpty)
        XCTAssertFalse(port.recordedEvents().contains { $0.hasPrefix("begin:") },
                       "Neither a normal summary nor a failure's silent anchor may restore a disabled reminder")
    }

    func testSuspendedDailyLoadRechecksMasterBeforePosting() async {
        await checkSuspendedDailyLoadCannotRestoreAfterMasterOff(throwsAfterLoad: false)
    }

    func testSuspendedDailyLoadFailureCannotRestoreSilentAnchor() async {
        await checkSuspendedDailyLoadCannotRestoreAfterMasterOff(throwsAfterLoad: true)
    }

    func testDailyRefreshWaitsForWriteBeforeCancellationAndQueueRemainsUsable() async {
        let paused = expectation(description: "Actual daily summary write suspended")
        let suspension = Suspension(paused)
        let env = Environment(daily: true, beforeClass: false)
        let port = Port(summaryPause: suspension)
        let scheduler = NotificationScheduler(env: env, dataSource: Source(), alarmPort: port,
            writeNotification: { await port.write($0) }, loadAgenda: { self.emptyAgenda($0) })
        let first = Task { await scheduler.refreshDailySummaries(isTomorrowPreview: false) }
        await fulfillment(of: [paused], timeout: 3)
        env.setMaster(false)
        let cancelStarted = expectation(description: "Cancellation reached the occupied schedule queue")
        let cancelReturned = expectation(description: "Cancellation cannot return before the write finishes")
        cancelReturned.isInverted = true
        let cancel = Task {
            cancelStarted.fulfill()
            await scheduler.cancelAll()
            cancelReturned.fulfill()
        }
        await fulfillment(of: [cancelStarted], timeout: 3)
        await fulfillment(of: [cancelReturned], timeout: 0.1)
        await suspension.release()
        await first.value
        await cancel.value
        XCTAssertTrue(port.pendingIDs().isEmpty)
        let id = NotificationScheduler.NOTIFY_DAILY
        let events = port.recordedEvents()
        let finished = events.firstIndex(of: "finish:\(id)")
        let cancelled = events.firstIndex(of: "cancel:\(id)")
        XCTAssertNotNil(finished)
        XCTAssertNotNil(cancelled)
        if let finished, let cancelled { XCTAssertLessThan(finished, cancelled) }

        env.setMaster(true)
        await scheduler.refreshDailySummaries(isTomorrowPreview: false)
        XCTAssertEqual(port.pendingIDs(), [id], "Refresh must return only after the notification write finishes")
    }
}
