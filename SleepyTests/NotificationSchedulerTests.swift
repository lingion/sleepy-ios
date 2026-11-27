// NotificationSchedulerTests.swift — ← widget/notification/CourseNotificationSchedulerTest.kt
// 逐用例移植 + v1.0.61 每表独立提醒新增用例 (GPL-3.0)。
//
// 7 天课前闹钟预排纯逻辑单测 — 走注入端口
// (NotificationSchedulerBeforeClassAlarmPort/Env/DataSource), 不依赖真实通知中心/数据库。
// 核心不变量:
//  ① 窗口内未来的课 → 一节课一颗精确通知 (课表/课程/开课时间稳定 id);
//  ② 重复调用不产生重复槽位, 仍需要的槽位不经历"先撤后排"的空窗;
//  ③ 学期范围外/已过触发点/开关关闭 → 零通知;
//  ④ 上次排过、这次不再需要的 id(换表/删课/关开关)按持久化账本撤销。
// v1.0.61 (#143) 新增不变量:
//  ⑤ 多张 reminderEnabled 表各自排闹钟; reminderEnabled=false 的表零闹钟且不撤销他表;
//  ⑥ 摘要扇出 id 号段 sleepy_summary_{5000+tableId*2(+1 次日)} 与到货链路判定;
//  ⑦ resolveReminderTables 协议默认实现回退「当前表且 reminderEnabled」兼容旧替身;
//  ⑧ 课前 extras 携带发送时重校验载荷 tableId/reminderDate。

import XCTest
import UserNotifications
@testable import Sleepy

final class NotificationSchedulerTests: XCTestCase {

    private let fixedToday = CourseOccurrences.parseDate("2026-10-07")!  // 星期三

    private func day(_ s: String) -> Date { CourseOccurrences.parseDate(s)! }

    /// Epoch for the fake schedule's pinned Shanghai zone, independent of the host.
    private func epoch(_ s: String) -> Int64 {
        let parts = s.split(separator: " ")
        let base = day(String(parts[0]))
        let hm = parts[1].split(separator: ":")
        let calendar = CourseOccurrences.calendar
        var comps = calendar.dateComponents([.year, .month, .day], from: base)
        comps.hour = Int(hm[0])!; comps.minute = Int(hm[1])!
        return Int64(calendar.date(from: comps)!.timeIntervalSince1970 * 1000)
    }

    // MARK: - Fake 端口 (← 测试文件内 FakeAlarmPort/FakeEnv/FakeDataSource)

    final class FakeAlarmPort: NotificationSchedulerBeforeClassAlarmPort {
        var armed: [String: Int64] = [:]          // id → epochMs (重复 set 覆盖, 语义同同 id 替换)
        var armedOrder: [String] = []             // 插入顺序 (LinkedHashMap 语义)
        var cancels: [String] = []
        var lastExtras: [String: [String: Any?]] = [:]
        var setCount = 0
        var rejected = Set<String>()
        var capacity = 60
        var summaries: [String: UNNotificationRequest] = [:]
        func setExact(id: String, epochMs: Int64, extras: [String: Any?]) async -> Bool {
            setCount += 1
            guard !rejected.contains(id) else { return false }
            if armed[id] == nil { armedOrder.append(id) }
            armed[id] = epochMs
            lastExtras[id] = extras
            return true
        }
        func pendingIdentifiers() async -> Set<String> { Set(armed.keys).union(summaries.keys) }
        func pendingRequestMatches(id: String, fireEpochMs: Int64, timeZone: TimeZone, extras: [String: Any?]) async -> Bool {
            guard armed[id] == fireEpochMs, let old = lastExtras[id] else { return false }
            let keys = ["courseName", "room", "startTime", "sourceLabel", "reminderDate"]
            for key in keys where (old[key] as? String) != (extras[key] as? String) { return false }
            return (old["tableId"] as? Int64) == (extras["tableId"] as? Int64)
        }
        func write(_ request: UNNotificationRequest) { summaries[request.identifier] = request }
        func availableSlots() async -> Int { capacity }
        func cancel(id: String) {
            cancels.append(id)
            summaries.removeValue(forKey: id)
            if armed[id] != nil {
                armed.removeValue(forKey: id)
                armedOrder.removeAll { $0 == id }
            }
        }
    }

    final class FakeEnv: NotificationSchedulerBeforeClassEnv {
        var enabled = true
        var dailyEnabled = false
        var todayEnabled = true
        var todayReminderTime = "07:00"
        var tomorrowPreviewTime = "22:00"
        var timeZone = CourseOccurrences.calendar.timeZone
        var minutes = 10
        var nowMs: () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }
        var today: Date
        var ledger: Set<String> = []
        var summaryLedgerToday: Set<String> = []
        var summaryLedgerTomorrow: Set<String> = []
        init(today: Date) { self.today = today }
        func isDailyReminderEnabled() -> Bool { dailyEnabled }
        func isTodayReminderEnabled() -> Bool { todayEnabled }
        func dailyReminderTime() -> String { todayReminderTime }
        func tomorrowReminderTime() -> String { tomorrowPreviewTime }
        func notificationTimeZone() -> TimeZone { timeZone }
        func isBeforeClassEnabled() -> Bool { enabled }
        func beforeClassMinutes() -> Int { minutes }
        func nowEpochMs() -> Int64 { nowMs() }
        func todayDate() -> Date { today }
        func loadArmedIds() -> Set<String> { ledger }
        func saveArmedIds(_ ids: Set<String>) { ledger = ids }
        func loadDailySummaryIds(isTomorrowPreview: Bool) -> Set<String> {
            isTomorrowPreview ? summaryLedgerTomorrow : summaryLedgerToday
        }
        func saveDailySummaryIds(_ ids: Set<String>, isTomorrowPreview: Bool) {
            if isTomorrowPreview { summaryLedgerTomorrow = ids } else { summaryLedgerToday = ids }
        }
    }

    /// 单表旧替身 (resolveReminderTables 走协议默认实现) + 多表替身共用:
    /// coursesProvider(tableId, dow) 可按表返回课程; nil → 旧 byDay 单表口径。
    final class FakeDataSource: NotificationSchedulerBeforeClassDataSource {
        var table: TimeTableEntity?
        var byDay: [Int: [CourseEntity]]
        var reminderTables: (() -> [TimeTableEntity])?
        var coursesProvider: ((Int64, Int) -> [CourseEntity])?
        var courseIds: () -> [Int64]
        var dayMapping: (Date) -> Int
        var holidayDates: Set<String>
        var failLoad = false
        var period: PeriodTableEntity?
        var sourceDateOverride: ((Date) -> Date?)?
        init(table: TimeTableEntity?, byDay: [Int: [CourseEntity]] = [:],
             courseIds: @escaping () -> [Int64] = { [] },
             dayMapping: @escaping (Date) -> Int = { CourseOccurrences.day($0) },
             holidayDates: Set<String> = []) {
            self.table = table
            self.byDay = byDay
            self.courseIds = courseIds
            self.dayMapping = dayMapping
            self.holidayDates = holidayDates
        }
        func resolveCurrentTable() -> TimeTableEntity? { table }
        // 未 override reminderTables → 协议默认实现 (旧替身兼容)
        func resolveReminderTables() throws -> [TimeTableEntity] {
            if failLoad { throw CourseReminderLoadError.unavailable }
            return reminderTables?() ?? {
                guard let t = table else { return [] }
                return t.reminderEnabled ? [t] : []
            }()
        }
        func boundPeriodTable(for table: TimeTableEntity) -> PeriodTableEntity? { period }
        func coursesForDay(tableId: Int64, dayOfWeek: Int) -> [CourseEntity] {
            if let p = coursesProvider { return p(tableId, dayOfWeek) }
            return byDay[dayOfWeek] ?? []
        }
        func allCourseIds() -> [Int64] {
            if byDay.isEmpty { return courseIds() }
            return byDay.values.flatMap { $0 }.map { $0.id }
        }
        func courseDateForDate(tableId: Int64?, date: Date) -> Date? {
            if let sourceDateOverride { return sourceDateOverride(date) }
            let currentDay = CourseOccurrences.day(date)
            // 既有 fixture 映射的是同周星期；新接口需要保留完整来源日期。
            return CourseOccurrences.calendar.date(byAdding: .day, value: dayMapping(date) - currentDay, to: date)
        }
        func allowsReminder(tableId: Int64, date: Date) async -> Bool {
            !holidayDates.contains(HolidayTransferOps.dayKey(date))
        }
    }

    private func makeTable(startDate: String = "2026-09-30", maxWeek: Int = 20,
                           id: Int64 = 1, name: String = "t", reminderEnabled: Bool = true) -> TimeTableEntity {
        var t = TimeTableEntity(name: name, startDate: startDate)
        t.id = id
        t.maxWeek = maxWeek
        t.reminderEnabled = reminderEnabled
        return t
    }

    private func makeCourse(id: Int64, day: Int, startNode: Int, tableId: Int64 = 1,
                            ownTime: Bool = false, startTime: String = "") -> CourseEntity {
        var c = CourseEntity(groupId: "g\(id)", tableId: tableId, courseName: "课\(id)",
                             teacher: "师", room: "101", note: "", day: day,
                             startNode: startNode, step: 1, startWeek: 1, endWeek: 20,
                             type: 0, color: "#FF6750A4")
        c.id = id
        c.ownTime = ownTime
        c.startTime = startTime
        c.endTime = ownTime ? "16:30" : ""
        return c
    }

    func testDateSpecificReminderUsesDestinationDayAndPreservesExplicitClocks() async throws {
        let table = makeTable(startDate: "2026-09-07")
        let recurring = makeCourse(id: 101, day: 1, startNode: 1)
        var fixed = makeCourse(id: 102, day: 7, startNode: 1, ownTime: true, startTime: "13:10")
        fixed.fixedDate = "2026-09-20"
        fixed.endTime = "14:10"
        let source = FakeDataSource(table: table, byDay: [1: [recurring], 7: [fixed]])
        source.period = PeriodTableEntity(name: "Autumn", nodesPerDay: 1,
            timeJson: #"[{"node":1,"start":"08:00","end":"08:45"}]"#,
            comboScheduleJson: """
            {"publicSchedules":[{"name":"Makeup","startDate":"2026-09-20","endDate":"2026-09-20",
              "timeSlots":[{"number":1,"startTime":"09:30","endTime":"10:15"}]}]}
            """)
        source.sourceDateOverride = { date in
            if date == self.day("2026-09-20") { return self.day("2026-09-07") }
            if date == self.day("2026-09-07") { return nil }
            return date
        }
        let clock = CourseReminderCalendar(timeZone: try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles")))
        // Use an explicitly local instant for the window anchor, independent of host settings.
        let start = try XCTUnwrap(clock.instant(on: day("2026-09-20"), wallSeconds: 0))
        let occurrences = try await CourseReminderLoader.load(tables: [table], dataSource: source,
                                                              from: start, days: 2, calendar: clock)
        XCTAssertEqual(occurrences.map(\.courseId), [101, 102, 101])
        XCTAssertEqual(occurrences.map { clock.timeText(for: $0.start) }, ["09:30", "13:10", "08:00"])
        XCTAssertEqual(occurrences.map { clock.timeText(for: $0.end) }, ["10:15", "14:10", "08:45"])
    }

    private let bc = NotificationScheduler.NOTIFY_BEFORE_CLASS_PREFIX  // "sleepy_bc_2000_"

    private func id(_ course: Int64, _ start: String = "2026-10-09 08:00", table: Int64 = 1) -> String {
        bc + "\(table)_\(course)_\(epoch(start) / 1000)"
    }

    private func env(now: Int64) -> FakeEnv {
        let e = FakeEnv(today: fixedToday)
        e.nowMs = { now }
        return e
    }

    // ==== 原版本 原用例 (CourseNotificationSchedulerTest.kt 逐用例移植) ====

    func testFutureCourseInWindowArmsOneExactAlarm() async {
        // 周三今天, 周五(day=5)第1节 08:00 → 2026-10-09 07:50 (提前 10 分钟)
        let src = FakeDataSource(table: makeTable(), byDay: [5: [makeCourse(id: 7, day: 5, startNode: 1)]])
        let port = FakeAlarmPort()
        let s = NotificationScheduler(env: env(now: epoch("2026-10-07 09:00")), dataSource: src, alarmPort: port)
        await s.scheduleNext7DaysExactAlarms()

        XCTAssertEqual([id(7): epoch("2026-10-09 07:50")], port.armed)
    }

    func testRepeatedCallIsIdempotentNoCancelWindow() async {
        let src = FakeDataSource(table: makeTable(), byDay: [5: [makeCourse(id: 7, day: 5, startNode: 1)]])
        let port = FakeAlarmPort()
        let e = env(now: epoch("2026-10-07 09:00"))
        let s = NotificationScheduler(env: e, dataSource: src, alarmPort: port)
        await s.scheduleNext7DaysExactAlarms()
        let firstArmed = port.armed
        port.cancels.removeAll(); port.setCount = 0

        await s.scheduleNext7DaysExactAlarms()
        XCTAssertTrue(port.cancels.filter { $0.hasPrefix(bc) }.isEmpty,
                      "仍需要的 id 不能先撤再排, 中间窗口会丢通知")
        XCTAssertEqual(firstArmed, port.armed)
        XCTAssertEqual(1, port.setCount)
        XCTAssertEqual([id(7)], e.ledger)
    }

    func testSwitchTableCancelsOldTableAlarmsByLedger() async {
        let src = FakeDataSource(table: makeTable(), byDay: [5: [makeCourse(id: 7, day: 5, startNode: 1)]])
        let port = FakeAlarmPort()
        let e = env(now: epoch("2026-10-07 09:00"))
        let s = NotificationScheduler(env: e, dataSource: src, alarmPort: port)
        await s.scheduleNext7DaysExactAlarms()

        src.table = makeTable(id: 2)
        src.byDay = [4: [makeCourse(id: 8, day: 4, startNode: 1, tableId: 2)]]
        await s.scheduleNext7DaysExactAlarms()

        XCTAssertEqual([id(8, "2026-10-08 08:00", table: 2)], port.armedOrder)
        XCTAssertTrue(port.cancels.contains(id(7)))
        XCTAssertEqual([id(8, "2026-10-08 08:00", table: 2)], e.ledger)
    }

    func testDeletedCourseAlarmCancelledByLedger() async {
        let src = FakeDataSource(table: makeTable(), byDay: [
            4: [makeCourse(id: 5, day: 4, startNode: 1)],
            5: [makeCourse(id: 7, day: 5, startNode: 1)],
        ])
        let port = FakeAlarmPort()
        let e = env(now: epoch("2026-10-07 09:00"))
        let s = NotificationScheduler(env: e, dataSource: src, alarmPort: port)
        await s.scheduleNext7DaysExactAlarms()
        XCTAssertEqual(Set([id(5, "2026-10-08 08:00"), id(7)]), Set(port.armedOrder))

        src.byDay = [5: [makeCourse(id: 7, day: 5, startNode: 1)]]
        await s.scheduleNext7DaysExactAlarms()
        XCTAssertEqual([id(7)], port.armedOrder)
        XCTAssertEqual([id(5, "2026-10-08 08:00")], port.cancels)
    }

    func testDisableBeforeClassCancelsAllLedgerAlarms() async {
        let src = FakeDataSource(table: makeTable(), byDay: [5: [makeCourse(id: 7, day: 5, startNode: 1)]])
        let port = FakeAlarmPort()
        let e = env(now: epoch("2026-10-07 09:00"))
        let s = NotificationScheduler(env: e, dataSource: src, alarmPort: port)
        await s.scheduleNext7DaysExactAlarms()

        e.enabled = false
        await s.scheduleNext7DaysExactAlarms()
        XCTAssertTrue(port.armed.isEmpty)
        XCTAssertTrue(e.ledger.isEmpty)
    }

    func testTableDisappearsCancelsAllLedgerAlarms() async {
        let src = FakeDataSource(table: makeTable(), byDay: [5: [makeCourse(id: 7, day: 5, startNode: 1)]])
        let port = FakeAlarmPort()
        let e = env(now: epoch("2026-10-07 09:00"))
        let s = NotificationScheduler(env: e, dataSource: src, alarmPort: port)
        await s.scheduleNext7DaysExactAlarms()

        src.table = nil
        src.byDay = [:]
        await s.scheduleNext7DaysExactAlarms()
        XCTAssertTrue(port.armed.isEmpty)
        XCTAssertTrue(e.ledger.isEmpty)
    }

    func testTransferMappingSameCourseTwicePreservesBothOccurrences() async {
        // 周六(10-10)补周五的课 → 课 7 在 10-09 与 10-10 各出现一次，必须分别预排
        let src = FakeDataSource(table: makeTable(), byDay: [5: [makeCourse(id: 7, day: 5, startNode: 1)]],
                                 dayMapping: { [weak self] date in
                                     guard let self = self else { return 1 }
                                     if date == self.day("2026-10-10") { return 5 }
                                     return CourseOccurrences.day(date)
                                 })
        let port = FakeAlarmPort()
        let s = NotificationScheduler(env: env(now: epoch("2026-10-07 09:00")), dataSource: src, alarmPort: port)
        await s.scheduleNext7DaysExactAlarms()
        XCTAssertEqual([id(7): epoch("2026-10-09 07:50"), id(7, "2026-10-10 08:00"): epoch("2026-10-10 07:50")], port.armed)
    }

    func testOutsideSemesterZeroAlarms() async {
        // 学期 2026-11-06 才开始 → 窗口 7 天全在学期外
        let src = FakeDataSource(table: makeTable(startDate: "2026-11-06"),
                                 byDay: [5: [makeCourse(id: 7, day: 5, startNode: 1)]])
        let port = FakeAlarmPort()
        let s = NotificationScheduler(env: env(now: epoch("2026-10-07 09:00")), dataSource: src, alarmPort: port)
        await s.scheduleNext7DaysExactAlarms()
        XCTAssertTrue(port.armed.isEmpty)
    }

    func testPastNotifyTimeSkippedFutureWeekCourseUnaffected() async {
        // 周三今天(day=3) 08:00 的课, 现在 09:00 → 今日已过点, 跳过; 周五 day=5 课仍排
        let src = FakeDataSource(table: makeTable(), byDay: [
            3: [makeCourse(id: 3, day: 3, startNode: 1)],
            5: [makeCourse(id: 5, day: 5, startNode: 1)],
        ])
        let port = FakeAlarmPort()
        let s = NotificationScheduler(env: env(now: epoch("2026-10-07 09:00")), dataSource: src, alarmPort: port)
        await s.scheduleNext7DaysExactAlarms()
        XCTAssertEqual([id(5)], port.armedOrder)
    }

    func testSwitchOffZeroAlarms() async {
        let src = FakeDataSource(table: makeTable(), byDay: [5: [makeCourse(id: 7, day: 5, startNode: 1)]])
        let port = FakeAlarmPort()
        let e = env(now: epoch("2026-10-07 09:00"))
        e.enabled = false
        let s = NotificationScheduler(env: e, dataSource: src, alarmPort: port)
        await s.scheduleNext7DaysExactAlarms()
        XCTAssertTrue(port.armed.isEmpty)
    }

    func testHolidayInWindowSkipsThatDayKeepsLater() async {
        let src = FakeDataSource(
            table: makeTable(),
            byDay: [
                5: [makeCourse(id: 7, day: 5, startNode: 1)],   // 10-09 (周五) 放假
                6: [makeCourse(id: 8, day: 6, startNode: 1)],   // 10-10 (周六)
            ],
            holidayDates: ["2026-10-09"])
        let port = FakeAlarmPort()
        let s = NotificationScheduler(env: env(now: epoch("2026-10-07 09:00")), dataSource: src, alarmPort: port)
        await s.scheduleNext7DaysExactAlarms()
        XCTAssertEqual([id(8, "2026-10-10 08:00"): epoch("2026-10-10 07:50")], port.armed)
    }

    func testOwnTimeCourseUsesCustomStartTime() async {
        let src = FakeDataSource(table: makeTable(),
                                 byDay: [5: [makeCourse(id: 9, day: 5, startNode: 1, ownTime: true, startTime: "15:30")]])
        let port = FakeAlarmPort()
        let s = NotificationScheduler(env: env(now: epoch("2026-10-07 09:00")), dataSource: src, alarmPort: port)
        await s.scheduleNext7DaysExactAlarms()
        XCTAssertEqual(epoch("2026-10-09 15:20"), port.armed[id(9, "2026-10-09 15:30")])
    }

    func testBrokenTimeSkippedNoCrash() async {
        let src = FakeDataSource(table: makeTable(),
                                 byDay: [5: [makeCourse(id: 9, day: 5, startNode: 1, ownTime: true, startTime: "25:99")]])
        let port = FakeAlarmPort()
        let s = NotificationScheduler(env: env(now: epoch("2026-10-07 09:00")), dataSource: src, alarmPort: port)
        await s.scheduleNext7DaysExactAlarms()
        XCTAssertTrue(port.armed.isEmpty)
    }

    // ==== v1.0.61 每表独立提醒 (#143) 新增用例 ====

    func testMultipleReminderTablesEachGetOwnAlarms() async {
        // A 表(id=1)周五课 7, B 表(id=2)周六课 8 — 两表各自排闹钟
        let src = FakeDataSource(table: nil, byDay: [:])
        src.reminderTables = { [weak self] in
            guard let self = self else { return [] }
            return [self.makeTable(id: 1, name: "A"), self.makeTable(id: 2, name: "B")]
        }
        src.coursesProvider = { [weak self] tableId, dow in
            guard let self = self else { return [] }
            if tableId == 1 && dow == 5 { return [self.makeCourse(id: 7, day: 5, startNode: 1, tableId: 1)] }
            if tableId == 2 && dow == 6 { return [self.makeCourse(id: 8, day: 6, startNode: 1, tableId: 2)] }
            return []
        }
        let port = FakeAlarmPort()
        let s = NotificationScheduler(env: env(now: epoch("2026-10-07 09:00")), dataSource: src, alarmPort: port)
        await s.scheduleNext7DaysExactAlarms()
        XCTAssertEqual(Set([id(7), id(8, "2026-10-10 08:00", table: 2)]), Set(port.armedOrder))
    }

    func testTableWithReminderDisabledGetsNoAlarmsButOthersKeepTheirs() async {
        // 每表独立提醒核心行为: 当前表 reminderEnabled=false ≠ 全体静默,
        // 其它开启提醒的表照常排; 旧实现只看 resolveCurrentTable 会在关掉当前表后清空一切。
        let current = makeTable(id: 1, name: "A", reminderEnabled: false)
        let other = makeTable(id: 2, name: "B")
        let src = FakeDataSource(table: current, byDay: [:])
        src.reminderTables = { return [other] }
        src.coursesProvider = { [weak self] tableId, dow in
            guard let self = self else { return [] }
            return tableId == 2 && dow == 5 ? [self.makeCourse(id: 8, day: 5, startNode: 1, tableId: 2)] : []
        }
        let port = FakeAlarmPort()
        let e = env(now: epoch("2026-10-07 09:00"))
        e.ledger = [bc + "7"]  // 旧版本(A 表当权时)排下的课
        let s = NotificationScheduler(env: e, dataSource: src, alarmPort: port)
        await s.scheduleNext7DaysExactAlarms()
        XCTAssertEqual([id(8, table: 2)], port.armedOrder)
        XCTAssertTrue(port.cancels.contains(bc + "7"), "A 表关提醒后其旧闹钟按账本精确撤销")
    }

    func testProtocolDefaultResolveReminderTablesFallsBackToEnabledCurrentTable() {
        // 旧测试替身兼容: 不实现 resolveReminderTables 的最小 conformer 走协议默认实现
        // (BeforeClassDataSource 接口默认方法: 当前表且 reminderEnabled 才返回)
        let enabled: NotificationSchedulerBeforeClassDataSource =
            LegacyMinimalDataSource(table: makeTable(reminderEnabled: true))
        XCTAssertEqual(1, try enabled.resolveReminderTables().count)
        let disabled: NotificationSchedulerBeforeClassDataSource =
            LegacyMinimalDataSource(table: makeTable(reminderEnabled: false))
        XCTAssertTrue(try disabled.resolveReminderTables().isEmpty)
        let gone: NotificationSchedulerBeforeClassDataSource = LegacyMinimalDataSource(table: nil)
        XCTAssertTrue(try gone.resolveReminderTables().isEmpty)
    }

    func testSummaryIdentifierFanOutNumberingMatchesOriginal() {
        // 5000 + tableId*2 (+1 次日), 字符串化 = sleepy_summary_*
        XCTAssertEqual("sleepy_summary_5002", NotificationScheduler.summaryIdentifier(tableId: 1, isTomorrowPreview: false))
        XCTAssertEqual("sleepy_summary_5003", NotificationScheduler.summaryIdentifier(tableId: 1, isTomorrowPreview: true))
        XCTAssertEqual("sleepy_summary_5008", NotificationScheduler.summaryIdentifier(tableId: 4, isTomorrowPreview: false))
        XCTAssertEqual("sleepy_summary_5009", NotificationScheduler.summaryIdentifier(tableId: 4, isTomorrowPreview: true))
        XCTAssertEqual("sleepy_summary_5000", NotificationScheduler.summaryIdentifier(tableId: 0, isTomorrowPreview: false))
    }

    func testSummaryLinkIdentifierClassification() {
        // 到货链路判定: 1001/偶号=当日, 1002/奇号=次日; 课前与重同步载体不属于摘要链路
        XCTAssertTrue(NotificationScheduler.isTomorrowSummaryIdentifier(NotificationScheduler.NOTIFY_TOMORROW_DAILY))
        XCTAssertTrue(NotificationScheduler.isTomorrowSummaryIdentifier("sleepy_summary_5003"))
        XCTAssertFalse(NotificationScheduler.isTomorrowSummaryIdentifier("sleepy_summary_5002"))
        XCTAssertTrue(NotificationScheduler.isTodaySummaryIdentifier(NotificationScheduler.NOTIFY_DAILY))
        XCTAssertTrue(NotificationScheduler.isTodaySummaryIdentifier("sleepy_summary_5002"))
        XCTAssertFalse(NotificationScheduler.isTodaySummaryIdentifier("sleepy_summary_5003"))
        XCTAssertFalse(NotificationScheduler.isTodaySummaryIdentifier(NotificationScheduler.NOTIFY_TOMORROW_DAILY))
        XCTAssertFalse(NotificationScheduler.isTomorrowSummaryIdentifier(id(7)))
        XCTAssertFalse(NotificationScheduler.isTodaySummaryIdentifier(NotificationScheduler.NOTIFY_RESYNC))
    }

    func testBeforeClassExtrasCarryFireTimeRevalidationPayload() async {
        // 发送时重校验载荷: extras 必须带 tableId + reminderDate (delegate 到货复查用)
        let src = FakeDataSource(table: makeTable(id: 42, name: "A"),
                                 byDay: [5: [makeCourse(id: 7, day: 5, startNode: 1, tableId: 42)]])
        let port = FakeAlarmPort()
        let s = NotificationScheduler(env: env(now: epoch("2026-10-07 09:00")), dataSource: src, alarmPort: port)
        await s.scheduleNext7DaysExactAlarms()
        let extras = port.lastExtras[id(7, table: 42)]
        XCTAssertEqual(42, extras?["tableId"] as? Int64)
        XCTAssertEqual("2026-10-09", extras?["reminderDate"] as? String)
    }

    private func instant(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private func epochMs(_ value: String) -> Int64 { Int64(instant(value).timeIntervalSince1970 * 1000) }

    func testAppleCalendarTriggerResolvesThePlannedAbsoluteInstant() {
        let future = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970) + 2 * 86_400)
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: CourseReminderOccurrence.notificationDateComponents(for: future), repeats: false)
        XCTAssertEqual(trigger.nextTriggerDate(), future)
    }

    func testBeforeClassUsesBellTimeInDeviceZoneInsteadOfShanghaiInstant() async throws {
        let source = FakeDataSource(table: makeTable(id: 42),
                                    byDay: [5: [makeCourse(id: 7, day: 5, startNode: 1, tableId: 42)]])
        let e = FakeEnv(today: instant("2026-10-08T12:00:00Z"))
        e.nowMs = { self.epochMs("2026-10-08T12:00:00Z") }
        e.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/London"))
        let port = FakeAlarmPort()
        await NotificationScheduler(env: e, dataSource: source, alarmPort: port).scheduleNext7DaysExactAlarms()

        let id = bc + "42_7_\(epochMs("2026-10-09T07:00:00Z") / 1000)"
        XCTAssertEqual(port.armed, [id: epochMs("2026-10-09T06:50:00Z")])
        XCTAssertEqual(port.lastExtras[id]?["startTime"] as? String, "08:00")
        XCTAssertEqual(port.lastExtras[id]?["tableId"] as? Int64, 42)
    }

    func testMidnightLeadUsesPreviousLocalDayButRetainsOwningClassDate() async throws {
        var night = makeCourse(id: 7, day: 5, startNode: 1, tableId: 42, ownTime: true, startTime: "00:05:30")
        night.endTime = "00:45"
        let source = FakeDataSource(table: makeTable(id: 42), byDay: [5: [night]])
        let e = FakeEnv(today: instant("2026-10-09T05:00:00Z")) // Still Thursday in Los Angeles.
        e.nowMs = { self.epochMs("2026-10-09T05:00:00Z") }
        e.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let port = FakeAlarmPort()
        await NotificationScheduler(env: e, dataSource: source, alarmPort: port).scheduleNext7DaysExactAlarms()

        let id = bc + "42_7_\(epochMs("2026-10-09T07:05:30Z") / 1000)"
        XCTAssertEqual(port.armed, [id: epochMs("2026-10-09T06:55:30Z")])
        XCTAssertEqual(port.lastExtras[id]?["reminderDate"] as? String, "2026-10-09")
        XCTAssertEqual(port.lastExtras[id]?["tableId"] as? Int64, 42)
    }

    func testMorningBellDoesNotShiftByAnHourOnSpringDSTDay() async throws {
        let source = FakeDataSource(table: makeTable(startDate: "2026-03-23"),
                                    byDay: [7: [makeCourse(id: 7, day: 7, startNode: 1)]])
        let e = FakeEnv(today: instant("2026-03-28T21:00:00Z"))
        e.nowMs = { self.epochMs("2026-03-28T21:00:00Z") }
        e.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/London"))
        let port = FakeAlarmPort()
        await NotificationScheduler(env: e, dataSource: source, alarmPort: port).scheduleNext7DaysExactAlarms()

        let id = bc + "1_7_\(epochMs("2026-03-29T07:00:00Z") / 1000)"
        XCTAssertEqual(port.armed, [id: epochMs("2026-03-29T06:50:00Z")])
        XCTAssertEqual(port.lastExtras[id]?["startTime"] as? String, "08:00")
    }

    func testCourseRequestUsesOwningTableAndLabelFromTheSameScope() async throws {
        let source = FakeDataSource(table: nil)
        source.reminderTables = { [self] in [makeTable(id: 2, name: "Biology"), makeTable(id: 42, name: "Physics")] }
        source.coursesProvider = { [self] tableId, weekday in
            guard weekday == 5, tableId == 42 else { return [] }
            return [makeCourse(id: 7, day: 5, startNode: 1, tableId: 42),
                    makeCourse(id: 8, day: 5, startNode: 1, tableId: 2)]
        }
        let port = FakeAlarmPort()
        let scheduler = NotificationScheduler(env: env(now: epoch("2026-10-07 09:00")),
                                              dataSource: source, alarmPort: port)
        await scheduler.scheduleNext7DaysExactAlarms()

        let id = id(7, table: 42)
        XCTAssertEqual(Set(port.armed.keys), [id])
        XCTAssertEqual(port.lastExtras[id]?["sourceLabel"] as? String, "Physics")
    }

    func testForegroundCourseRequiresItsOwnEnabledTableAndValidCivilDate() async {
        let source = FakeDataSource(table: nil, holidayDates: ["2026-10-10"])
        source.reminderTables = { [self] in [makeTable(id: 2, reminderEnabled: false), makeTable(id: 42)] }
        let scheduler = NotificationScheduler(env: env(now: epoch("2026-10-07 09:00")),
                                              dataSource: source, alarmPort: FakeAlarmPort())
        let valid = await scheduler.beforeClassDeliveryAllowed(userInfo: ["tableId": Int64(42), "reminderDate": "2026-10-09"])
        let wrongTable = await scheduler.beforeClassDeliveryAllowed(userInfo: ["tableId": Int64(2), "reminderDate": "2026-10-09"])
        let legacy = await scheduler.beforeClassDeliveryAllowed(userInfo: ["reminderDate": "2026-10-09"])
        let wrongDay = await scheduler.beforeClassDeliveryAllowed(userInfo: ["tableId": Int64(42), "reminderDate": "2026-02-30"])
        let holiday = await scheduler.beforeClassDeliveryAllowed(userInfo: ["tableId": Int64(42), "reminderDate": "2026-10-10"])
        XCTAssertTrue(valid)
        XCTAssertFalse(wrongTable)
        XCTAssertFalse(legacy)
        XCTAssertFalse(wrongDay)
        XCTAssertFalse(holiday)
    }

    func testDailySummariesStayBoundToTheirOwnDatesAndSelectedTable() async throws {
        let e = FakeEnv(today: instant("2026-10-09T03:00:00Z")) // Thursday at 20:00 local.
        e.nowMs = { self.epochMs("2026-10-09T03:00:00Z") }
        e.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        e.dailyEnabled = true
        e.enabled = false
        e.todayReminderTime = "07:30"
        e.tomorrowPreviewTime = "21:15"
        let port = FakeAlarmPort()
        let unrelated = UNNotificationRequest(identifier: "not_sleepy", content: .init(), trigger: nil)
        let legacy = UNNotificationRequest(identifier: NotificationScheduler.NOTIFY_DAILY, content: .init(),
                                           trigger: UNCalendarNotificationTrigger(dateMatching: .init(hour: 7), repeats: true))
        port.write(unrelated)
        port.write(legacy)
        var selected = makeTable(id: 42, name: "Physics")
        let source = FakeDataSource(table: selected)
        let scheduler = NotificationScheduler(env: e, dataSource: source, alarmPort: port,
            writeNotification: { port.write($0); return true }, loadAgenda: { [self] target in
                let targetKey = HolidayTransferOps.dayKey(target)
                var course = makeCourse(id: 7, day: 5, startNode: 1, tableId: selected.id)
                course.courseName = "\(selected.name) \(targetKey)"
                let summary = buildDailyScheduleSummary([DailyTableCourses(table: selected, courses: [course])])
                return LoadedDailyAgenda(agenda: buildDailyAgenda(date: target, summary: summary), suppressed: false)
            })
        await scheduler.refreshDailySummaries(isTomorrowPreview: false)
        await scheduler.refreshDailySummaries(isTomorrowPreview: true)

        let formatted = port.summaries.values.filter { $0.identifier != unrelated.identifier }
        XCTAssertEqual(formatted.count, 13) // Today has passed on Thursday; tomorrow has not.
        XCTAssertNil(port.summaries[legacy.identifier])
        XCTAssertNotNil(port.summaries[NotificationScheduler.NOTIFY_DAILY + "_2026-10-09"])
        XCTAssertNotNil(port.summaries[NotificationScheduler.NOTIFY_TOMORROW_DAILY + "_2026-10-08"])
        for request in formatted {
            let trigger = try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)
            XCTAssertFalse(trigger.repeats)
            let targetKey = try XCTUnwrap(request.content.userInfo[NotificationScheduler.KEY_USERINFO_AGENDA_DATE] as? String)
            XCTAssertTrue(request.content.body.contains("Physics \(targetKey)"))
            let isTomorrow = NotificationScheduler.isTomorrowSummaryIdentifier(request.identifier)
            XCTAssertTrue(scheduler.dailySummaryDeliveryAllowed(request, isTomorrowPreview: isTomorrow))
            if targetKey == "2026-10-09" {
                XCTAssertEqual(trigger.dateComponents.date,
                               instant(isTomorrow ? "2026-10-09T04:15:00Z" : "2026-10-09T14:30:00Z"))
            }
        }

        selected = makeTable(id: 2, name: "Biology")
        source.table = selected
        XCTAssertTrue(formatted.allSatisfy {
            !scheduler.dailySummaryDeliveryAllowed($0, isTomorrowPreview: NotificationScheduler.isTomorrowSummaryIdentifier($0.identifier))
        })
        await scheduler.scheduleAll().value
        XCTAssertEqual(port.summaries.count, 14)
        XCTAssertNotNil(port.summaries[unrelated.identifier])
        XCTAssertTrue(port.summaries.values.filter { $0.identifier != unrelated.identifier }.allSatisfy {
            $0.content.body.contains("Biology") && !$0.content.body.contains("Physics")
        })

        e.todayEnabled = false
        await scheduler.scheduleAll().value
        XCTAssertEqual(port.summaries.count, 8)
        XCTAssertTrue(port.summaries.keys.filter { $0 != unrelated.identifier }.allSatisfy(NotificationScheduler.isTomorrowSummaryIdentifier))
    }

    func testDailySummariesCancelUnreadableSuppressedAndRejectedDatesRatherThanKeepStaleContent() async {
        let e = env(now: epoch("2026-10-07 06:00"))
        e.enabled = false
        e.dailyEnabled = true
        let port = FakeAlarmPort()
        var fail = false
        let prefix = NotificationScheduler.NOTIFY_DAILY + "_"
        let unreadable = prefix + "2026-10-08", suppressed = prefix + "2026-10-09", rejected = prefix + "2026-10-10"
        let scheduler = NotificationScheduler(env: e, dataSource: FakeDataSource(table: nil), alarmPort: port,
            writeNotification: { request in
                if fail, request.identifier == rejected { return false }
                port.write(request)
                return true
            }, loadAgenda: { date in
                let key = HolidayTransferOps.dayKey(date)
                if fail, key == "2026-10-08" { throw CourseReminderLoadError.unavailable }
                return LoadedDailyAgenda(agenda: DailyAgenda(date: date, items: []), suppressed: fail && key == "2026-10-09")
            })
        await scheduler.refreshDailySummaries(isTomorrowPreview: false)
        XCTAssertEqual(port.summaries.count, 7)
        fail = true
        await scheduler.refreshDailySummaries(isTomorrowPreview: false)
        XCTAssertEqual(port.summaries.count, 4)
        XCTAssertNil(port.summaries[unreadable])
        XCTAssertNil(port.summaries[suppressed])
        XCTAssertNil(port.summaries[rejected])
    }

    func testRejectedRequestNeverEntersLedgerAndCanBeRetried() async {
        let src = FakeDataSource(table: makeTable(), byDay: [5: [makeCourse(id: 7, day: 5, startNode: 1)]])
        let port = FakeAlarmPort()
        port.rejected = [id(7)]
        let e = env(now: epoch("2026-10-07 09:00"))
        let scheduler = NotificationScheduler(env: e, dataSource: src, alarmPort: port)
        await scheduler.scheduleNext7DaysExactAlarms()
        XCTAssertTrue(e.ledger.isEmpty)
        XCTAssertTrue(port.armed.isEmpty)
        port.rejected = []
        await scheduler.scheduleNext7DaysExactAlarms()
        XCTAssertEqual(e.ledger, [id(7)])
    }

    func testCapacityKeepsNearestOccurrencesAcrossTables() async {
        let src = FakeDataSource(table: makeTable(), byDay: [
            6: [makeCourse(id: 8, day: 6, startNode: 1)],
            4: [makeCourse(id: 5, day: 4, startNode: 1)]])
        let port = FakeAlarmPort()
        port.capacity = 1
        let scheduler = NotificationScheduler(env: env(now: epoch("2026-10-07 09:00")), dataSource: src, alarmPort: port)
        await scheduler.scheduleNext7DaysExactAlarms()
        XCTAssertEqual(port.armedOrder, [id(5, "2026-10-08 08:00")])
    }

    func testTemporaryDatabaseFailurePreservesAcceptedReminders() async {
        let src = FakeDataSource(table: makeTable(), byDay: [5: [makeCourse(id: 7, day: 5, startNode: 1)]])
        let port = FakeAlarmPort()
        let e = env(now: epoch("2026-10-07 09:00"))
        let scheduler = NotificationScheduler(env: e, dataSource: src, alarmPort: port)
        await scheduler.scheduleNext7DaysExactAlarms()
        src.failLoad = true
        await scheduler.scheduleNext7DaysExactAlarms()
        XCTAssertEqual(e.ledger, [id(7)])
        XCTAssertNotNil(port.armed[id(7)])
        XCTAssertTrue(port.cancels.isEmpty)
    }

    func testActivityPresentationNeverRemovesConfiguredNotificationFallback() async {
        let src = FakeDataSource(table: makeTable(), byDay: [5: [makeCourse(id: 7, day: 5, startNode: 1)]])
        let port = FakeAlarmPort()
        let scheduler = NotificationScheduler(env: env(now: epoch("2026-10-07 09:00")), dataSource: src, alarmPort: port)
        await scheduler.scheduleNext7DaysExactAlarms()
        scheduler.foregroundActivityIDs = { [self] in [id(7)] }
        await scheduler.scheduleNext7DaysExactAlarms()
        XCTAssertNotNil(port.armed[id(7)])
        scheduler.foregroundActivityIDs = { [] }
        await scheduler.scheduleNext7DaysExactAlarms()
        XCTAssertNotNil(port.armed[id(7)])
    }

    func testFixedDateCourseSurvivesMissingRecurringSource() async throws {
        var fixed = makeCourse(id: 9, day: 5, startNode: 1)
        fixed.fixedDate = "2026-10-09"
        let src = FakeDataSource(table: makeTable(startDate: "2027-01-01"), byDay: [5: [fixed]])
        src.sourceDateOverride = { _ in nil }
        let port = FakeAlarmPort()
        let scheduler = NotificationScheduler(env: env(now: epoch("2026-10-07 09:00")), dataSource: src, alarmPort: port)
        await scheduler.scheduleNext7DaysExactAlarms()
        XCTAssertEqual(port.armedOrder, [id(9)])
    }

    func testCustomSecondsArePreservedInNotificationTime() async {
        var item = makeCourse(id: 9, day: 5, startNode: 1, ownTime: true, startTime: "15:30:30")
        item.endTime = "16:30:30"
        let src = FakeDataSource(table: makeTable(), byDay: [5: [item]])
        let port = FakeAlarmPort()
        let scheduler = NotificationScheduler(env: env(now: epoch("2026-10-07 09:00")), dataSource: src, alarmPort: port)
        await scheduler.scheduleNext7DaysExactAlarms()
        XCTAssertEqual(Array(port.armed.values), [epoch("2026-10-09 15:20") + 30_000])
    }

    func testSameDatabaseCourseIDInDifferentTablesNeverCollides() async {
        let src = FakeDataSource(table: nil)
        src.reminderTables = { [self] in [makeTable(id: 1), makeTable(id: 2)] }
        src.coursesProvider = { [self] table, dow in
            dow == 5 ? [makeCourse(id: 7, day: 5, startNode: 1, tableId: table)] : []
        }
        let port = FakeAlarmPort()
        let scheduler = NotificationScheduler(env: env(now: epoch("2026-10-07 09:00")), dataSource: src, alarmPort: port)
        await scheduler.scheduleNext7DaysExactAlarms()
        XCTAssertEqual(Set(port.armed.keys), [id(7), id(7, table: 2)])
    }

    func testOddEvenWeekAndTransferUseSourceWeek() async {
        var item = makeCourse(id: 7, day: 5, startNode: 1)
        item.type = 1 // odd weeks only; natural Oct 9 is week 2.
        let src = FakeDataSource(table: makeTable(), byDay: [5: [item]])
        src.sourceDateOverride = { [self] date in date == day("2026-10-09") ? day("2026-10-02") : nil }
        let port = FakeAlarmPort()
        let scheduler = NotificationScheduler(env: env(now: epoch("2026-10-07 09:00")), dataSource: src, alarmPort: port)
        await scheduler.scheduleNext7DaysExactAlarms()
        XCTAssertEqual(port.armedOrder, [id(7)])
    }

    func testFailedReplacementRetainsAlreadyAcceptedMatchingRequest() async {
        let src = FakeDataSource(table: makeTable(), byDay: [5: [makeCourse(id: 7, day: 5, startNode: 1)]])
        let port = FakeAlarmPort()
        let e = env(now: epoch("2026-10-07 09:00"))
        let scheduler = NotificationScheduler(env: e, dataSource: src, alarmPort: port)
        await scheduler.scheduleNext7DaysExactAlarms()
        port.rejected = [id(7)]
        await scheduler.scheduleNext7DaysExactAlarms()
        XCTAssertEqual(e.ledger, [id(7)])
        XCTAssertNotNil(port.armed[id(7)])
    }

    func testFailedReplacementCancelsStaleRequestWhenPayloadOrFireTimeChanges() async {
        var course = makeCourse(id: 7, day: 5, startNode: 1)
        let src = FakeDataSource(table: makeTable(), byDay: [5: [course]])
        let port = FakeAlarmPort()
        let e = env(now: epoch("2026-10-07 09:00"))
        let scheduler = NotificationScheduler(env: e, dataSource: src, alarmPort: port)
        await scheduler.scheduleNext7DaysExactAlarms()
        XCTAssertEqual(e.ledger, [id(7)])

        course.room = "B204"
        src.byDay = [5: [course]]
        port.rejected = [id(7)]
        await scheduler.scheduleNext7DaysExactAlarms()
        XCTAssertTrue(e.ledger.isEmpty)
        XCTAssertNil(port.armed[id(7)])
        XCTAssertTrue(port.cancels.contains(id(7)))
    }

    func testDailySummaryTriggerTimeZoneAndLedgerFollowActiveZone() async throws {
        let e = FakeEnv(today: instant("2026-10-08T01:00:00Z"))
        e.nowMs = { self.epochMs("2026-10-08T01:00:00Z") }
        e.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        e.dailyEnabled = true
        e.enabled = false
        e.todayReminderTime = "20:00"
        let port = FakeAlarmPort()
        let selected = makeTable(id: 1, name: "Default")
        let scheduler = NotificationScheduler(
            env: e,
            dataSource: FakeDataSource(table: selected),
            alarmPort: port,
            writeNotification: { port.write($0); return true },
            loadAgenda: { date in LoadedDailyAgenda(agenda: DailyAgenda(date: date, items: []), suppressed: false) }
        )
        await scheduler.refreshDailySummaries(isTomorrowPreview: false)
        XCTAssertEqual(e.summaryLedgerToday.count, 7)
        XCTAssertFalse(e.summaryLedgerToday.isEmpty)
        for req in port.summaries.values {
            let trig = try XCTUnwrap(req.trigger as? UNCalendarNotificationTrigger)
            XCTAssertEqual(trig.dateComponents.timeZone?.identifier, "America/Los_Angeles")
        }
        XCTAssertTrue(port.summaries.values.compactMap { ($0.trigger as? UNCalendarNotificationTrigger)?.dateComponents.day }.contains(7))

        e.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/London"))
        await scheduler.refreshDailySummaries(isTomorrowPreview: false)
        for req in port.summaries.values {
            let trig = try XCTUnwrap(req.trigger as? UNCalendarNotificationTrigger)
            XCTAssertEqual(trig.dateComponents.timeZone?.identifier, "Europe/London")
        }
        XCTAssertTrue(port.summaries.values.compactMap { ($0.trigger as? UNCalendarNotificationTrigger)?.dateComponents.day }.contains(8))

        e.dailyEnabled = false
        await scheduler.refreshDailySummaries(isTomorrowPreview: false)
        XCTAssertTrue(e.summaryLedgerToday.isEmpty)
        XCTAssertTrue(port.summaries.isEmpty)
    }

}

/// 最小 conformer — 刻意不实现 resolveReminderTables, 验证协议默认实现的旧替身兼容路径。
private final class LegacyMinimalDataSource: NotificationSchedulerBeforeClassDataSource {
    let table: TimeTableEntity?
    init(table: TimeTableEntity?) { self.table = table }
    func resolveCurrentTable() -> TimeTableEntity? { table }
    func coursesForDay(tableId: Int64, dayOfWeek: Int) -> [CourseEntity] { [] }
    func allCourseIds() -> [Int64] { [] }
    func courseDateForDate(tableId: Int64?, date: Date) -> Date? { date }
    func allowsReminder(tableId: Int64, date: Date) async -> Bool { true }
}
