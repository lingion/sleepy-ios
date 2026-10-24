// NotificationSchedulerTests.swift — ← widget/notification/CourseNotificationSchedulerTest.kt
// 逐用例移植 + v1.0.61 每表独立提醒新增用例 (GPL-3.0)。
//
// 7 天课前闹钟预排纯逻辑单测 — 走注入端口
// (NotificationSchedulerBeforeClassAlarmPort/Env/DataSource), 不依赖真实通知中心/数据库。
// 核心不变量:
//  ① 窗口内未来的课 → 一节课一颗精确通知 (courseId 稳定 id);
//  ② 重复调用不产生重复槽位, 仍需要的槽位不经历"先撤后排"的空窗;
//  ③ 学期范围外/已过触发点/开关关闭 → 零通知;
//  ④ 上次排过、这次不再需要的 id(换表/删课/关开关)按持久化账本撤销。
// v1.0.61 (#143) 新增不变量:
//  ⑤ 多张 reminderEnabled 表各自排闹钟; reminderEnabled=false 的表零闹钟且不撤销他表;
//  ⑥ 摘要扇出 id 号段 sleepy_summary_{5000+tableId*2(+1 次日)} 与到货链路判定;
//  ⑦ resolveReminderTables 协议默认实现回退「当前表且 reminderEnabled」兼容旧替身;
//  ⑧ 课前 extras 携带发送时重校验载荷 tableId/reminderDate。

import XCTest
@testable import Sleepy

final class NotificationSchedulerTests: XCTestCase {

    private let fixedToday = DateUtils.parseDate("2026-10-07")!  // 星期三

    private func day(_ s: String) -> Date { DateUtils.parseDate(s)! }

    /// epoch(本地, isoCalendar 锚) — "yyyy-MM-dd HH:mm"
    private func epoch(_ s: String) -> Int64 {
        let parts = s.split(separator: " ")
        let base = day(String(parts[0]))
        let hm = parts[1].split(separator: ":")
        var comps = DateUtils.isoCalendar.dateComponents([.year, .month, .day], from: base)
        comps.hour = Int(hm[0])!; comps.minute = Int(hm[1])!
        return Int64(DateUtils.isoCalendar.date(from: comps)!.timeIntervalSince1970 * 1000)
    }

    // MARK: - Fake 端口 (← 测试文件内 FakeAlarmPort/FakeEnv/FakeDataSource)

    final class FakeAlarmPort: NotificationSchedulerBeforeClassAlarmPort {
        var armed: [String: Int64] = [:]          // id → epochMs (重复 set 覆盖, 语义同同 id 替换)
        var armedOrder: [String] = []             // 插入顺序 (LinkedHashMap 语义)
        var cancels: [String] = []
        var lastExtras: [String: [String: Any?]] = [:]
        var setCount = 0
        func setExact(id: String, epochMs: Int64, extras: [String: Any?]) {
            setCount += 1
            if armed[id] == nil { armedOrder.append(id) }
            armed[id] = epochMs
            lastExtras[id] = extras
        }
        func cancel(id: String) {
            cancels.append(id)
            if armed[id] != nil {
                armed.removeValue(forKey: id)
                armedOrder.removeAll { $0 == id }
            }
        }
    }

    final class FakeEnv: NotificationSchedulerBeforeClassEnv {
        var enabled = true
        var minutes = 10
        var nowMs: () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }
        var today: Date
        var ledger: Set<String> = []
        var summaryLedgerToday: Set<String> = []
        var summaryLedgerTomorrow: Set<String> = []
        init(today: Date) { self.today = today }
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
        init(table: TimeTableEntity?, byDay: [Int: [CourseEntity]] = [:],
             courseIds: @escaping () -> [Int64] = { [] },
             dayMapping: @escaping (Date) -> Int = { date in
                 let w = DateUtils.isoCalendar.component(.weekday, from: date)
                 return w == 1 ? 7 : w - 1
             },
             holidayDates: Set<String> = []) {
            self.table = table
            self.byDay = byDay
            self.courseIds = courseIds
            self.dayMapping = dayMapping
            self.holidayDates = holidayDates
        }
        func resolveCurrentTable() -> TimeTableEntity? { table }
        // 未 override reminderTables → 协议默认实现 (旧替身兼容)
        func resolveReminderTables() -> [TimeTableEntity] {
            reminderTables?() ?? {
                guard let t = table else { return [] }
                return t.reminderEnabled ? [t] : []
            }()
        }
        func coursesForDay(tableId: Int64, dayOfWeek: Int) -> [CourseEntity] {
            if let p = coursesProvider { return p(tableId, dayOfWeek) }
            return byDay[dayOfWeek] ?? []
        }
        func allCourseIds() -> [Int64] {
            if byDay.isEmpty { return courseIds() }
            return byDay.values.flatMap { $0 }.map { $0.id }
        }
        func effectiveDayOfWeek(tableId: Int64?, date: Date) -> Int { dayMapping(date) }
        func allowsReminder(tableId: Int64, date: Date) async -> Bool {
            !holidayDates.contains(DateUtils.fullDate(date))
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
        c.endTime = ""
        return c
    }

    private let bc = NotificationScheduler.NOTIFY_BEFORE_CLASS_PREFIX  // "sleepy_bc_2000_"

    private func env(now: Int64) -> FakeEnv {
        let e = FakeEnv(today: fixedToday)
        e.nowMs = { now }
        return e
    }

    // ==== Android 原用例 (CourseNotificationSchedulerTest.kt 逐用例移植) ====

    func testFutureCourseInWindowArmsOneExactAlarm() async {
        // 周三今天, 周五(day=5)第1节 08:00 → 2026-10-09 07:50 (提前 10 分钟)
        let src = FakeDataSource(table: makeTable(), byDay: [5: [makeCourse(id: 7, day: 5, startNode: 1)]])
        let port = FakeAlarmPort()
        let s = NotificationScheduler(env: env(now: epoch("2026-10-07 09:00")), dataSource: src, alarmPort: port)
        await s.scheduleNext7DaysExactAlarms()

        XCTAssertEqual([bc + "7": epoch("2026-10-09 07:50")], port.armed)
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
        XCTAssertEqual([bc + "7"], e.ledger)
    }

    func testSwitchTableCancelsOldTableAlarmsByLedger() async {
        let src = FakeDataSource(table: makeTable(), byDay: [5: [makeCourse(id: 7, day: 5, startNode: 1)]])
        let port = FakeAlarmPort()
        let e = env(now: epoch("2026-10-07 09:00"))
        let s = NotificationScheduler(env: e, dataSource: src, alarmPort: port)
        await s.scheduleNext7DaysExactAlarms()

        src.table = makeTable(id: 2)
        src.byDay = [4: [makeCourse(id: 8, day: 4, startNode: 1)]]
        await s.scheduleNext7DaysExactAlarms()

        XCTAssertEqual([bc + "8"], port.armedOrder)
        XCTAssertTrue(port.cancels.contains(bc + "7"))
        XCTAssertEqual([bc + "8"], e.ledger)
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
        XCTAssertEqual(Set([bc + "5", bc + "7"]), Set(port.armedOrder))

        src.byDay = [5: [makeCourse(id: 7, day: 5, startNode: 1)]]
        await s.scheduleNext7DaysExactAlarms()
        XCTAssertEqual([bc + "7"], port.armedOrder)
        XCTAssertEqual([bc + "5"], port.cancels)
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

    func testTransferMappingSameCourseTwiceOnlyEarliest() async {
        // 周六(10-10)补周五的课 → 课 7 在 10-09 与 10-10 各出现一次, 只排最早
        let src = FakeDataSource(table: makeTable(), byDay: [5: [makeCourse(id: 7, day: 5, startNode: 1)]],
                                 dayMapping: { [weak self] date in
                                     guard let self = self else { return 1 }
                                     if date == self.day("2026-10-10") { return 5 }
                                     let w = DateUtils.isoCalendar.component(.weekday, from: date)
                                     return w == 1 ? 7 : w - 1
                                 })
        let port = FakeAlarmPort()
        let s = NotificationScheduler(env: env(now: epoch("2026-10-07 09:00")), dataSource: src, alarmPort: port)
        await s.scheduleNext7DaysExactAlarms()
        XCTAssertEqual([bc + "7": epoch("2026-10-09 07:50")], port.armed)
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
        XCTAssertEqual([bc + "5"], port.armedOrder)
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
        XCTAssertEqual([bc + "8": epoch("2026-10-10 07:50")], port.armed)
    }

    func testOwnTimeCourseUsesCustomStartTime() async {
        let src = FakeDataSource(table: makeTable(),
                                 byDay: [5: [makeCourse(id: 9, day: 5, startNode: 1, ownTime: true, startTime: "15:30")]])
        let port = FakeAlarmPort()
        let s = NotificationScheduler(env: env(now: epoch("2026-10-07 09:00")), dataSource: src, alarmPort: port)
        await s.scheduleNext7DaysExactAlarms()
        XCTAssertEqual(epoch("2026-10-09 15:20"), port.armed[bc + "9"])
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
        XCTAssertEqual(Set([bc + "7", bc + "8"]), Set(port.armedOrder))
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
        XCTAssertEqual([bc + "8"], port.armedOrder)
        XCTAssertTrue(port.cancels.contains(bc + "7"), "A 表关提醒后其旧闹钟按账本精确撤销")
    }

    func testProtocolDefaultResolveReminderTablesFallsBackToEnabledCurrentTable() {
        // 旧测试替身兼容: 不实现 resolveReminderTables 的最小 conformer 走协议默认实现
        // (← Android BeforeClassDataSource 接口默认方法: 当前表且 reminderEnabled 才返回)
        let enabled: NotificationSchedulerBeforeClassDataSource =
            LegacyMinimalDataSource(table: makeTable(reminderEnabled: true))
        XCTAssertEqual(1, enabled.resolveReminderTables().count)
        let disabled: NotificationSchedulerBeforeClassDataSource =
            LegacyMinimalDataSource(table: makeTable(reminderEnabled: false))
        XCTAssertTrue(disabled.resolveReminderTables().isEmpty)
        let gone: NotificationSchedulerBeforeClassDataSource = LegacyMinimalDataSource(table: nil)
        XCTAssertTrue(gone.resolveReminderTables().isEmpty)
    }

    func testSummaryIdentifierFanOutNumberingMatchesAndroid() {
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
        XCTAssertFalse(NotificationScheduler.isTomorrowSummaryIdentifier(bc + "7"))
        XCTAssertFalse(NotificationScheduler.isTodaySummaryIdentifier(NotificationScheduler.NOTIFY_RESYNC))
    }

    func testBeforeClassExtrasCarryFireTimeRevalidationPayload() async {
        // 发送时重校验载荷: extras 必须带 tableId + reminderDate (delegate 到货复查用)
        let src = FakeDataSource(table: makeTable(id: 42, name: "A"),
                                 byDay: [5: [makeCourse(id: 7, day: 5, startNode: 1, tableId: 42)]])
        let port = FakeAlarmPort()
        let s = NotificationScheduler(env: env(now: epoch("2026-10-07 09:00")), dataSource: src, alarmPort: port)
        await s.scheduleNext7DaysExactAlarms()
        let extras = port.lastExtras[bc + "7"]
        XCTAssertEqual(42, extras?["tableId"] as? Int64)
        XCTAssertEqual("2026-10-09", extras?["reminderDate"] as? String)
    }
}

/// 最小 conformer — 刻意不实现 resolveReminderTables, 验证协议默认实现的旧替身兼容路径。
private final class LegacyMinimalDataSource: NotificationSchedulerBeforeClassDataSource {
    let table: TimeTableEntity?
    init(table: TimeTableEntity?) { self.table = table }
    func resolveCurrentTable() -> TimeTableEntity? { table }
    func coursesForDay(tableId: Int64, dayOfWeek: Int) -> [CourseEntity] { [] }
    func allCourseIds() -> [Int64] { [] }
    func effectiveDayOfWeek(tableId: Int64?, date: Date) -> Int { 1 }
    func allowsReminder(tableId: Int64, date: Date) async -> Bool { true }
}
