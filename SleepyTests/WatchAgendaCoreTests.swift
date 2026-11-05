// WatchAgendaCoreTests.swift — 表盘小组件共享议程核口径锁
// 真源对照: WatchStore.courses(on:)(今日课过滤) + 原 WatchComplicationData(时间反解/startLabel)
// 锁: 学期过滤(beforeStart 空 / afterEnd 补班日例外) · 有效星期(调休换日) · inWeek 周次 ·
//     排序 · 「正在上」半开区间 [start,end) · 「下一节」跳过进行中 · weekInfo clamp ·
//     node/time 两种 startLabel · ownTime 直读 · minutesUntil/progress · 时间反解失败跳过。
// 日期一律系统日历构造(与 core 内 Calendar(identifier:.gregorian) 同域), 跨时区可复现。

import XCTest
@testable import Sleepy

final class WatchAgendaCoreTests: XCTestCase {

    private let tableId: Int64 = 9901   // 独立 id, 防与其它用例的调休 prefs 串扰

    override func setUp() {
        super.setUp()
        AppPrefs.shared.setLanguage("zh-CN")
        AppPrefs.shared.setDisplayMode("time")
        AppPrefs.shared.setHolidayTransfers(tableId, [])
    }

    override func tearDown() {
        AppPrefs.shared.setHolidayTransfers(tableId, [])
        super.tearDown()
    }

    // MARK: - helpers

    /// 2026-08-24 = 周一 (学期第 1 周起点); 2026-11-05 = 周四, 学期第 11 周
    private func table(startDate: String = "2026-08-24", maxWeek: Int = 20) -> TimeTableEntity {
        var t = TimeTableEntity(name: "t", startDate: startDate)
        t.maxWeek = maxWeek
        t.id = tableId
        return t
    }

    /// DEFAULT_TIME_JSON: node1 08:00–08:45 / node2 08:55–09:40 / node3 10:00–10:45 / node4 10:55–11:40
    private func course(_ name: String, day: Int, startNode: Int, step: Int = 2,
                        startWeek: Int = 1, endWeek: Int = 20, type: Int = 0,
                        isIrregularTime: Bool = false, ownTime: Bool = false,
                        startTime: String = "", endTime: String = "") -> CourseEntity {
        CourseEntity(groupId: name, tableId: tableId, courseName: name, teacher: "师",
                     room: "A101", day: day, startNode: startNode, step: step,
                     startWeek: startWeek, endWeek: endWeek, type: type,
                     color: "#FF6750A4",
                     isIrregularTime: isIrregularTime, ownTime: ownTime,
                     startTime: startTime, endTime: endTime,
                     id: 0)
    }

    private func d(_ y: Int, _ m: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = day; c.hour = hour; c.minute = minute
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    // MARK: - dayItems

    func testDayItemsSortsFiltersByDayAndWeek() {
        let t = table()
        let courses = [
            course("C3", day: 4, startNode: 3),              // 10:00 周四
            course("C1", day: 4, startNode: 1),              // 08:00 周四
            course("Fri", day: 5, startNode: 1),             // 周五, 应被过滤
            course("Past", day: 4, startNode: 5, endWeek: 10),   // 周次已过, 过滤
            course("Future", day: 4, startNode: 5, startWeek: 12), // 周次未到, 过滤
            course("Odd", day: 4, startNode: 5, type: 1)     // 第11周(奇数周)命中
        ]
        let items = WatchAgendaCore.dayItems(table: t, courses: courses, date: d(2026, 11, 5, 12))
        XCTAssertEqual(items.map(\.courseName), ["C1", "C3", "Odd"])
        XCTAssertEqual(items[0].startMin, 480)   // 08:00
        XCTAssertEqual(items[0].endMin, 580)     // node1+step2 → 09:40
        XCTAssertEqual(items[1].startMin, 600)   // 10:00
        XCTAssertEqual(items[0].room, "A101")
        XCTAssertEqual(items[0].startLabel, "08:00–09:40")
    }

    func testDayItemsBeforeStartEmpty() {
        let t = table(startDate: "2026-12-01")   // 未开学
        XCTAssertEqual(WatchAgendaCore.dayItems(table: t, courses: [course("X", day: 4, startNode: 1)],
                                                date: d(2026, 11, 5, 12)), [])
    }

    func testDayItemsAfterEndEmptyWithoutTransfer() {
        let t = table(startDate: "2026-06-01", maxWeek: 9)   // 第 23 周 > 9 → afterEnd
        XCTAssertEqual(WatchAgendaCore.dayItems(table: t, courses: [course("X", day: 4, startNode: 1, endWeek: 30)],
                                                date: d(2026, 11, 5, 12)), [])
    }

    func testDayItemsAfterEndKeepsTransferDay() {
        let t = table(startDate: "2026-06-01", maxWeek: 9)
        // 补班日 = 调休映射 sourceDate (上班日→换日上课): 11-05 按 targetDate(11-02 周一) 星期取课
        AppPrefs.shared.setHolidayTransfers(tableId, [
            HolidayTransferEntry(sourceDate: d(2026, 11, 5), targetDate: d(2026, 11, 2), segmentId: "s")
        ])
        let mondayCourse = course("MonMakeup", day: 1, startNode: 1, endWeek: 30)
        let items = WatchAgendaCore.dayItems(table: t, courses: [mondayCourse], date: d(2026, 11, 5, 12))
        XCTAssertEqual(items.map(\.courseName), ["MonMakeup"])
        // 非补班日仍清空
        XCTAssertEqual(WatchAgendaCore.dayItems(table: t, courses: [mondayCourse], date: d(2026, 11, 4, 12)), [])
    }

    func testTomorrowTransferMapsToTargetWeekday() {
        let t = table()
        let courses = [course("Wed", day: 3, startNode: 1), course("Fri", day: 5, startNode: 1)]
        let tomorrow = d(2026, 11, 6)   // 周五

        // 自然周五 → 周五的课
        XCTAssertEqual(WatchAgendaCore.dayItems(table: t, courses: courses, date: tomorrow).map(\.courseName),
                       ["Fri"])

        // 调休: 周五是补班日, 上 targetDate(11-04 周三) 的课
        AppPrefs.shared.setHolidayTransfers(tableId, [
            HolidayTransferEntry(sourceDate: tomorrow, targetDate: d(2026, 11, 4), segmentId: "s")
        ])
        XCTAssertEqual(WatchAgendaCore.dayItems(table: t, courses: courses, date: tomorrow).map(\.courseName),
                       ["Wed"])
    }

    func testDayItemsSkipsUnparseableTime() {
        let t = table()
        // node 13 不存在 (DEFAULT_TIME_JSON 到 node 12) → 反解失败跳过
        XCTAssertEqual(WatchAgendaCore.dayItems(table: t, courses: [course("X", day: 4, startNode: 12)],
                                                date: d(2026, 11, 5, 12)), [])
    }

    // MARK: - currentClass / nextClass

    func testCurrentClassHalfOpenInterval() {
        let t = table()
        let items = WatchAgendaCore.dayItems(table: t,
                                             courses: [course("C1", day: 4, startNode: 1),
                                                       course("C3", day: 4, startNode: 3)],
                                             date: d(2026, 11, 5))
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(WatchAgendaCore.currentClass(in: items, now: d(2026, 11, 5, 7, 59))?.courseName, nil)
        XCTAssertEqual(WatchAgendaCore.currentClass(in: items, now: d(2026, 11, 5, 8, 0))?.courseName, "C1")
        XCTAssertEqual(WatchAgendaCore.currentClass(in: items, now: d(2026, 11, 5, 9, 39))?.courseName, "C1")
        XCTAssertEqual(WatchAgendaCore.currentClass(in: items, now: d(2026, 11, 5, 9, 40))?.courseName, nil) // endMin 半开
        XCTAssertEqual(WatchAgendaCore.currentClass(in: items, now: d(2026, 11, 5, 10, 30))?.courseName, "C3")
        XCTAssertEqual(WatchAgendaCore.currentClass(in: items, now: d(2026, 11, 5, 11, 40))?.courseName, nil)
    }

    func testNextClassSkipsInProgress() {
        let t = table()
        let items = WatchAgendaCore.dayItems(table: t,
                                             courses: [course("C1", day: 4, startNode: 1),
                                                       course("C3", day: 4, startNode: 3)],
                                             date: d(2026, 11, 5))
        XCTAssertEqual(WatchAgendaCore.nextClass(in: items, now: d(2026, 11, 5, 7, 0))?.courseName, "C1")
        XCTAssertEqual(WatchAgendaCore.nextClass(in: items, now: d(2026, 11, 5, 8, 30))?.courseName, "C3") // 进行中不算下一节
        XCTAssertEqual(WatchAgendaCore.nextClass(in: items, now: d(2026, 11, 5, 23, 0))?.courseName, nil)
    }

    // MARK: - weekInfo

    func testWeekInfoAndClamp() {
        let now = d(2026, 11, 5, 12)
        var info = WatchAgendaCore.weekInfo(table: table(), date: now)
        XCTAssertEqual(info.week, 11)
        XCTAssertEqual(info.maxWeek, 20)
        XCTAssertEqual(info.ratio, 0.55, accuracy: 0.0001)

        info = WatchAgendaCore.weekInfo(table: table(maxWeek: 9), date: now)
        XCTAssertEqual(info.week, 11)      // 周次只看 startDate→date, 不受 maxWeek 影响
        XCTAssertEqual(info.ratio, 1.0)    // 11/9 clamp 到 1

        info = WatchAgendaCore.weekInfo(table: table(maxWeek: 0), date: now)
        XCTAssertEqual(info.ratio, 0)      // maxWeek ≤ 0 防御
    }

    // MARK: - startLabel 口径

    func testSlotLabelNodeMode() {
        AppPrefs.shared.setDisplayMode("node")
        let t = table()
        let items = WatchAgendaCore.dayItems(table: t, courses: [course("C1", day: 4, startNode: 1)],
                                             date: d(2026, 11, 5, 12))
        XCTAssertEqual(items[0].startLabel, L10n.format("course_period_range", 1, 2))
    }

    func testOwnTimeDirectRead() {
        let t = table()
        let items = WatchAgendaCore.dayItems(table: t,
                                             courses: [course("Late", day: 4, startNode: 1,
                                                              isIrregularTime: true,
                                                              startTime: "18:30", endTime: "20:55")],
                                             date: d(2026, 11, 5, 12))
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].startMin, 18 * 60 + 30)
        XCTAssertEqual(items[0].endMin, 20 * 60 + 55)
        XCTAssertEqual(items[0].startLabel, "18:30–20:55")
    }

    // MARK: - ClassItem 数值

    func testMinutesUntilAndProgress() {
        let t = table()
        let items = WatchAgendaCore.dayItems(table: t, courses: [course("C1", day: 4, startNode: 1)],
                                             date: d(2026, 11, 5))
        let item = items[0]
        XCTAssertEqual(item.minutesUntil(from: d(2026, 11, 5, 7, 0)), 60)
        XCTAssertEqual(item.minutesUntil(from: d(2026, 11, 5, 8, 0)), 0)
        XCTAssertEqual(item.minutesUntil(from: d(2026, 11, 5, 9, 0)), 0)   // 开课后不再倒计时

        XCTAssertEqual(item.progress(at: d(2026, 11, 5, 7, 0)), 0)        // 课前钳 0
        XCTAssertEqual(item.progress(at: d(2026, 11, 5, 8, 0)), 0)
        XCTAssertEqual(item.progress(at: d(2026, 11, 5, 8, 50)), 0.5, accuracy: 0.0001)
        XCTAssertEqual(item.progress(at: d(2026, 11, 5, 9, 40)), 1)       // 下课钳 1
        XCTAssertEqual(item.progress(at: d(2026, 11, 5, 23, 0)), 1)
    }

    // MARK: - semesterStatus 透传

    func testSemesterStatusPassthrough() {
        let now = d(2026, 11, 5, 12)
        XCTAssertEqual(WatchAgendaCore.semesterStatus(table: table(), date: now), .inRange)
        XCTAssertEqual(WatchAgendaCore.semesterStatus(table: table(startDate: "2026-12-01"), date: now), .beforeStart)
        XCTAssertEqual(WatchAgendaCore.semesterStatus(table: table(startDate: "2026-06-01", maxWeek: 9), date: now), .afterEnd)
    }
}
