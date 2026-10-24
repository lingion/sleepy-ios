// HolidayManagerTests.swift — ← HolidayManagerTest.kt + HolidayRangeTest.kt +
// HolidayGreyTransferTest.kt + HolidaySkipDecisionTest.kt
// 范围化覆盖纯逻辑: 聚合/合并/集合展开/序列化 + 灰显判定 + 调休豁免 + 跳过决策 + 年数据可用性 (不触网络)。

import XCTest
@testable import Sleepy

final class HolidayManagerTests: XCTestCase {

    // CST 日历构造 y/m/d — 与 Android LocalDate.of 语义对齐(午夜基准, 与 dateFormat 解析输出一致)
    private func d(_ m: Int, _ day: Int) -> Date {
        var c = DateComponents()
        c.year = 2025; c.month = m; c.day = day; c.hour = 0
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return Calendar(identifier: .gregorian).date(from: c)!
    }
    private func dy(_ y: Int, _ m: Int, _ day: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = day; c.hour = 0
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return Calendar(identifier: .gregorian).date(from: c)!
    }
    private func entry(_ m: Int, _ day: Int, _ name: String, _ type: String) -> HolidayEntry {
        HolidayEntry(date: d(m, day), name: name, type: type)
    }
    private func range(_ id: String, _ name: String, _ start: Date, _ end: Date,
                       _ type: String, _ sourceKey: String?) -> HolidayRange {
        HolidayRange(id: id, name: name, startDate: start, endDate: end, type: type, sourceKey: sourceKey)
    }

    // ===== 灰显判定 decideGrey (← HolidayManagerTest) =====

    private var holiday: Date { d(1, 1) }
    private var saturday: Date { d(1, 4) }        // 2025-01-04 是周六
    private var sundayWorkday: Date { d(1, 26) }  // 2025-01-26 是周日(春节补班)
    private var weekday: Date { d(1, 6) }         // 2025-01-06 是周一

    func testDecideGrey_respectsHolidayToggle() {
        XCTAssertTrue(HolidayManager.decideGrey(date: holiday, holidays: [holiday], workdays: [],
                                                greyHoliday: true, greyWeekend: false, ignoreWorkday: false))
        XCTAssertFalse(HolidayManager.decideGrey(date: holiday, holidays: [holiday], workdays: [],
                                                 greyHoliday: false, greyWeekend: false, ignoreWorkday: false))
    }

    func testDecideGrey_respectsWeekendToggle() {
        XCTAssertTrue(HolidayManager.decideGrey(date: saturday, holidays: [], workdays: [],
                                                greyHoliday: false, greyWeekend: true, ignoreWorkday: false))
        XCTAssertFalse(HolidayManager.decideGrey(date: saturday, holidays: [], workdays: [],
                                                 greyHoliday: false, greyWeekend: false, ignoreWorkday: false))
    }

    func testDecideGrey_canIgnoreMakeupWorkday() {
        let workdays: Set<Date> = [sundayWorkday]
        XCTAssertFalse(HolidayManager.decideGrey(date: sundayWorkday, holidays: [], workdays: workdays,
                                                 greyHoliday: false, greyWeekend: true, ignoreWorkday: true))
        XCTAssertTrue(HolidayManager.decideGrey(date: sundayWorkday, holidays: [], workdays: workdays,
                                                greyHoliday: false, greyWeekend: true, ignoreWorkday: false))
    }

    func testDecideGrey_neverGreysNormalWeekdayWithoutHoliday() {
        XCTAssertFalse(HolidayManager.decideGrey(date: weekday, holidays: [], workdays: [],
                                                 greyHoliday: true, greyWeekend: true, ignoreWorkday: false))
    }

    // ===== issue#44 灰显与调休映射联动 (← HolidayGreyTransferTest.kt) =====
    // 2026-10-01 周四法定假日; 2026-10-10 补班周六

    private func dy26(_ m: Int, _ day: Int) -> Date { dy(2026, m, day) }

    func testGreyTransfer_mappedSourceDateNeverGreysEvenIfHoliday() {
        // 10/1 已映射到某目标日 → 那天上课, 不灰
        let nationalDay = dy26(10, 1)
        let holidays: Set<Date> = [nationalDay, dy26(10, 2), dy26(10, 3)]
        let workdays: Set<Date> = [dy26(10, 10)]
        let transfers = [HolidayTransferEntry(sourceDate: nationalDay, targetDate: dy26(10, 8), segmentId: "seg")]
        let isMapped: (Date) -> Bool = { HolidayTransferOps.transferFor($0, transfers) != nil }
        XCTAssertFalse(HolidayManager.decideGrey(
            date: nationalDay, holidays: holidays, workdays: workdays,
            greyHoliday: true, greyWeekend: true, ignoreWorkday: true,
            dateHasTransfer: isMapped(nationalDay)))
    }

    func testGreyTransfer_unmappedHolidayStillGreys() {
        let nationalDay = dy26(10, 1)
        let holidays: Set<Date> = [nationalDay, dy26(10, 2), dy26(10, 3)]
        let workdays: Set<Date> = [dy26(10, 10)]
        let transfers = [HolidayTransferEntry(sourceDate: nationalDay, targetDate: dy26(10, 8), segmentId: "seg")]
        let isMapped: (Date) -> Bool = { HolidayTransferOps.transferFor($0, transfers) != nil }
        XCTAssertTrue(HolidayManager.decideGrey(
            date: dy26(10, 2), // 同段未映射的假日
            holidays: holidays, workdays: workdays,
            greyHoliday: true, greyWeekend: true, ignoreWorkday: true,
            dateHasTransfer: isMapped(dy26(10, 2))))
    }

    func testGreyTransfer_emptyTransfersKeepsLegacyGreyBehavior() {
        // 兼容锁: dateHasTransfer=false 时逐位等同旧签名结果
        let nationalDay = dy26(10, 1)
        let holidays: Set<Date> = [nationalDay, dy26(10, 2), dy26(10, 3)]
        let workdays: Set<Date> = [dy26(10, 10)]
        let legacy = HolidayManager.decideGrey(
            date: nationalDay, holidays: holidays, workdays: workdays,
            greyHoliday: true, greyWeekend: true, ignoreWorkday: true)
        let withFlag = HolidayManager.decideGrey(
            date: nationalDay, holidays: holidays, workdays: workdays,
            greyHoliday: true, greyWeekend: true, ignoreWorkday: true,
            dateHasTransfer: false)
        XCTAssertTrue(legacy)
        XCTAssertEqual(legacy, withFlag)
    }

    // ===== 课程提醒"节假日跳过"纯决策核 (← HolidaySkipDecisionTest.kt) =====

    func testSkipPublicHoliday_inHolidayNoTransfer_skips() {
        let d1 = dy26(10, 1)
        XCTAssertTrue(HolidayManager.decideSkipPublicHoliday(date: d1, holidays: [d1], dateHasTransfer: false))
    }

    func testSkipPublicHoliday_mappedTransfer_doesNotSkip() {
        // 法定节假日但命中调休映射 → 不跳过 (当天要上课)
        let d1 = dy26(10, 1)
        XCTAssertFalse(HolidayManager.decideSkipPublicHoliday(date: d1, holidays: [d1], dateHasTransfer: true))
    }

    func testSkipPublicHoliday_notInHolidays_doesNotSkip() {
        XCTAssertFalse(HolidayManager.decideSkipPublicHoliday(
            date: dy26(10, 1), holidays: [dy26(5, 1)], dateHasTransfer: false))
    }

    func testSkipPublicHoliday_emptySetFailureState_doesNotSkip() {
        // 空集合 网络失败态 → 不跳过 (宁误报不丢课)
        XCTAssertFalse(HolidayManager.decideSkipPublicHoliday(
            date: dy26(10, 1), holidays: [], dateHasTransfer: false))
    }

    // ===== isPublicHolidayCached (cache-only, 不触网络) =====

    func testIsPublicHolidayCached_greyHolidaySwitchOff_returnsFalse() {
        let original = AppPrefs.shared.isHolidayGreyHoliday()
        AppPrefs.shared.setHolidayGreyHoliday(false)
        defer { AppPrefs.shared.setHolidayGreyHoliday(original) }
        XCTAssertFalse(HolidayManager.isPublicHolidayCached(dy26(10, 1), tableId: 1))
    }

    func testIsPublicHolidayCached_unknownYearEmptyData_doesNotSkip() {
        // 远未来年份: 无内存/磁盘缓存 → 节假日集合为空 → 不跳过 (宁误报不丢课); 全程无网络 I/O
        let farYearDate = dy(2099, 1, 1)
        XCTAssertFalse(HolidayManager.isPublicHolidayCached(farYearDate))
    }

    // ===== 年数据可用性 (← HolidayManagerTest.kt year-data cases) =====

    func testYearData_effectiveEntriesPreserveNetworkRowsRemovedByUserOverrides() {
        let effectiveEntry = entry(1, 1, "New Year", HolidayManager.TYPE_PUBLIC_HOLIDAY)
        let result = HolidayManager.yearData([effectiveEntry], fetchFailed: false, hasCachedData: true)
        XCTAssertEqual(result.entries, [effectiveEntry])
        XCTAssertTrue(result.available)
    }

    func testYearData_mergedUserOverrideParticipatesInPolicyClassification() {
        let ov = range("user-holiday", "User holiday", holiday, holiday,
                       HolidayManager.TYPE_PUBLIC_HOLIDAY, nil)
        let merged = HolidayRangeOps.mergeSegments([], [ov])
        let sets = HolidayRangeOps.toSets(merged.active)
        let result = HolidayReminderPolicy.decide(
            date: holiday,
            publicHolidays: sets.holidays,
            transferWorkdays: sets.workdays,
            transfers: [],
            rulesEnabled: true,
            publicHolidayReminder: false,
            transferHolidayReminder: true,
            makeupWorkdayReminder: true,
            ordinaryWeekendReminder: true,
            dataAvailable: true)
        XCTAssertTrue(sets.holidays.contains(holiday))
        XCTAssertEqual(result.category, .publicHoliday)
        XCTAssertFalse(result.allowReminder)
    }

    func testYearData_unavailableEmptyFetchDistinctFromSuccessfulEmptyYear() {
        let unavailable = HolidayManager.yearData([], fetchFailed: true, hasCachedData: false)
        let successfulEmpty = HolidayManager.yearData([], fetchFailed: false, hasCachedData: true)
        XCTAssertFalse(unavailable.available)
        XCTAssertTrue(unavailable.entries.isEmpty)
        let unavailableDecision = HolidayReminderPolicy.decide(
            date: holiday,
            publicHolidays: [],
            transferWorkdays: [],
            transfers: [],
            rulesEnabled: true,
            publicHolidayReminder: false,
            transferHolidayReminder: false,
            makeupWorkdayReminder: false,
            ordinaryWeekendReminder: false,
            dataAvailable: unavailable.available)
        XCTAssertEqual(unavailableDecision.category, .dataUnavailable)
        XCTAssertTrue(unavailableDecision.allowReminder)
        XCTAssertTrue(successfulEmpty.available)
        XCTAssertTrue(successfulEmpty.entries.isEmpty)
    }

    func testYearData_overrideEntriesDoNotMakeFailedNetworkDataAvailable() {
        let override = [entry(1, 1, "User holiday", HolidayManager.TYPE_PUBLIC_HOLIDAY)]
        let result = HolidayManager.yearData(override, fetchFailed: true, hasCachedData: false)
        XCTAssertFalse(result.available)
        let decision = HolidayReminderPolicy.decide(
            date: holiday,
            publicHolidays: [holiday],
            transferWorkdays: [],
            transfers: [],
            rulesEnabled: true,
            publicHolidayReminder: false,
            transferHolidayReminder: true,
            makeupWorkdayReminder: true,
            ordinaryWeekendReminder: true,
            dataAvailable: result.available)
        XCTAssertEqual(decision.category, .dataUnavailable)
        XCTAssertTrue(decision.allowReminder)
    }

    // ===== 刷新失败保留缓存 (← HolidayManagerTest.kt refresh cases) =====

    func testRefreshedEntries_failedRefreshWithCacheRetainsCachedEntries() {
        let cached = [entry(1, 1, "New Year", HolidayManager.TYPE_PUBLIC_HOLIDAY)]
        let result = HolidayManager.refreshedEntries(cached: cached, fetched: [], fetchFailed: true)
        XCTAssertTrue(HolidayManager.yearData(result, fetchFailed: true, hasCachedData: true).available)
        XCTAssertEqual(result, cached)
    }

    func testRefreshedEntries_failedRefreshWithoutCacheReturnsUnavailableEmptyData() {
        let result = HolidayManager.refreshedEntries(cached: nil, fetched: [], fetchFailed: true)
        XCTAssertEqual(result, [])
        XCTAssertFalse(HolidayManager.yearData(result, fetchFailed: true, hasCachedData: false).available)
    }

    func testRefreshedEntries_successfulEmptyRefreshReplacesCachedDataAndRemainsAvailable() {
        let cached = [entry(1, 1, "New Year", HolidayManager.TYPE_PUBLIC_HOLIDAY)]
        let result = HolidayManager.refreshedEntries(cached: cached, fetched: [], fetchFailed: false)
        XCTAssertTrue(result.isEmpty)
        XCTAssertTrue(HolidayManager.yearData(result, fetchFailed: false, hasCachedData: true).available)
    }

    // ===== parseEntries (← HolidayManagerTest) =====

    func testParseEntries_sortsAndKeepsSupportedTypes() {
        let json = "{\"year\":2025,\"dates\":[" +
            "{\"date\":\"2025-01-26\",\"name\":\"春节\",\"type\":\"transfer_workday\"}," +
            "{\"date\":\"2025-01-01\",\"name\":\"元旦\",\"type\":\"public_holiday\"}]}"
        let entries = HolidayManager.parseEntries(json)
        XCTAssertEqual(entries.map { $0.date }, [d(1, 1), sundayWorkday])
        XCTAssertEqual(entries.map { $0.type }, [HolidayManager.TYPE_PUBLIC_HOLIDAY, HolidayManager.TYPE_TRANSFER_WORKDAY])
    }

    func testParseEntries_skipsBadRowsAndMalformedDocuments() {
        let json = "{\"dates\":[" +
            "{\"date\":\"bad\",\"name\":\"x\",\"type\":\"public_holiday\"}," +
            "{\"date\":\"2025-01-06\",\"name\":\"y\",\"type\":\"other\"}]}"
        XCTAssertEqual(HolidayManager.parseEntries(json).count, 1)
        XCTAssertTrue(HolidayManager.parseEntries("{not json").isEmpty)
        XCTAssertTrue(HolidayManager.parseEntries("{}").isEmpty)
    }

    // ===== 网络段聚合 (← HolidayRangeTest) =====

    func testAggregate_mergesConsecutiveSameNameSameType() {
        let segments = HolidayRangeOps.aggregateSegments([
            entry(2, 10, "春节", HolidayManager.TYPE_PUBLIC_HOLIDAY),
            entry(2, 11, "春节", HolidayManager.TYPE_PUBLIC_HOLIDAY),
            entry(2, 12, "春节", HolidayManager.TYPE_PUBLIC_HOLIDAY),
        ])
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].startDate, d(2, 10))
        XCTAssertEqual(segments[0].endDate, d(2, 12))
    }

    func testAggregate_splitsOnGapOrNameOrTypeChange() {
        let segments = HolidayRangeOps.aggregateSegments([
            entry(5, 1, "劳动节", HolidayManager.TYPE_PUBLIC_HOLIDAY),
            entry(5, 2, "劳动节", HolidayManager.TYPE_PUBLIC_HOLIDAY),
            entry(5, 4, "劳动节", HolidayManager.TYPE_PUBLIC_HOLIDAY),        // 5/3 断档
            entry(5, 5, "劳动节(青年节)", HolidayManager.TYPE_PUBLIC_HOLIDAY), // 名称变
            entry(4, 27, "班", HolidayManager.TYPE_TRANSFER_WORKDAY),         // 类型变+乱序
        ])
        XCTAssertEqual(segments.count, 4)
    }

    func testAggregate_emptyAndSingleton() {
        XCTAssertTrue(HolidayRangeOps.aggregateSegments([]).isEmpty)
        let one = HolidayRangeOps.aggregateSegments([entry(1, 1, "元旦", HolidayManager.TYPE_PUBLIC_HOLIDAY)])
        XCTAssertEqual(one.count, 1)
        XCTAssertEqual(one[0].startDate, d(1, 1))
    }

    // ===== 合并 (← HolidayRangeTest) =====

    func testMerge_addsNewRange() {
        let ov = range("id1", "校庆", d(3, 8), d(3, 9), HolidayManager.TYPE_PUBLIC_HOLIDAY, nil)
        let result = HolidayRangeOps.mergeSegments(
            [entry(1, 1, "元旦", HolidayManager.TYPE_PUBLIC_HOLIDAY)], [ov])
        XCTAssertEqual(result.active.count, 2)
        XCTAssertTrue(result.removed.isEmpty)
    }

    func testMerge_replacesNetworkSegmentViaSourceKey() {
        // 网络: 春节 2/10-2/14; 用户改成 2/10-2/12
        let ov = range("id1", "春节", d(2, 10), d(2, 12),
                       HolidayManager.TYPE_PUBLIC_HOLIDAY, "holiday:" + iso(d(2, 10)))
        let result = HolidayRangeOps.mergeSegments(
            (10...14).map { entry(2, $0, "春节", HolidayManager.TYPE_PUBLIC_HOLIDAY) }, [ov])
        XCTAssertEqual(result.active.count, 1)
        XCTAssertEqual(result.active[0].endDate, d(2, 12))
    }

    func testMerge_removedNetworkSegmentGoesToRemovedList() {
        let ov = range("id1", "元旦", d(1, 1), d(1, 1), HolidayRangeOps.REMOVED, "holiday:" + iso(d(1, 1)))
        let result = HolidayRangeOps.mergeSegments(
            [entry(1, 1, "元旦", HolidayManager.TYPE_PUBLIC_HOLIDAY)], [ov])
        XCTAssertTrue(result.active.isEmpty)
        XCTAssertEqual(result.removed.count, 1)
    }

    func testMerge_workdaySourceKeyOnlyKillsWorkdaySegment() {
        let ov = range("id1", "班", d(1, 26), d(1, 26), HolidayRangeOps.REMOVED, "workday:" + iso(d(1, 26)))
        let result = HolidayRangeOps.mergeSegments(
            [entry(1, 26, "班", HolidayManager.TYPE_TRANSFER_WORKDAY)], [ov])
        XCTAssertTrue(result.active.isEmpty)
    }

    func testMerge_sameSourceKeyTwiceSecondWins() {
        let a = range("id1", "春节", d(2, 10), d(2, 12), HolidayManager.TYPE_PUBLIC_HOLIDAY, "holiday:" + iso(d(2, 10)))
        let b = range("id2", "寒假", d(2, 10), d(2, 14), HolidayManager.TYPE_PUBLIC_HOLIDAY, "holiday:" + iso(d(2, 10)))
        let result = HolidayRangeOps.mergeSegments(
            (10...14).map { entry(2, $0, "春节", HolidayManager.TYPE_PUBLIC_HOLIDAY) }, [a, b])
        // 后应用的覆盖前者: active 里只剩 id2
        XCTAssertEqual(result.active.count, 1)
        XCTAssertEqual(result.active[0].id, "id2")
    }

    // ===== 集合展开 (← HolidayRangeTest) =====

    func testToSets_expandsRangesAndSplitsTypes() {
        let active = [
            range("id1", "春节", d(2, 10), d(2, 11), HolidayManager.TYPE_PUBLIC_HOLIDAY, nil),
            range("id2", "班", d(1, 26), d(1, 26), HolidayManager.TYPE_TRANSFER_WORKDAY, nil),
        ]
        let sets = HolidayRangeOps.toSets(active)
        XCTAssertEqual(sets.holidays, [d(2, 10), d(2, 11)])
        XCTAssertEqual(sets.workdays, [d(1, 26)])
    }

    // ===== 序列化 (← HolidayRangeTest) =====

    func testOverrides_roundtripThroughJson() {
        let overrides = [
            range("id1", "校庆", d(3, 8), d(3, 9), HolidayManager.TYPE_PUBLIC_HOLIDAY, nil),
            range("id2", "调休", d(9, 28), d(9, 28), HolidayManager.TYPE_TRANSFER_WORKDAY, "workday:" + iso(d(9, 28))),
            range("id3", "元旦", d(1, 1), d(1, 1), HolidayRangeOps.REMOVED, "holiday:" + iso(d(1, 1))),
        ]
        let decoded = HolidayRangeOps.decodeOverrides(HolidayRangeOps.encodeOverrides(overrides))
        XCTAssertEqual(decoded, overrides)
    }

    func testDecodeOverrides_survivesGarbageAndBadRows() {
        XCTAssertTrue(HolidayRangeOps.decodeOverrides("{not json").isEmpty)
        XCTAssertTrue(HolidayRangeOps.decodeOverrides("[]").isEmpty)
        // start > end 的段跳过
        XCTAssertTrue(HolidayRangeOps.decodeOverrides(
            "[{\"id\":\"x\",\"name\":\"n\",\"start\":\"2025-03-09\",\"end\":\"2025-03-08\",\"type\":\"public_holiday\"}]"
        ).isEmpty)
        // 类型不认的跳过
        XCTAssertTrue(HolidayRangeOps.decodeOverrides(
            "[{\"id\":\"x\",\"name\":\"n\",\"start\":\"2025-03-08\",\"end\":\"2025-03-08\",\"type\":\"weird\"}]"
        ).isEmpty)
    }

    func testNewId_is8HexCharsAndUnique() {
        let ids = Set((1...100).map { _ in HolidayRangeOps.newId() })
        XCTAssertEqual(ids.count, 100)
        for id in ids {
            XCTAssertEqual(id.count, 8)
            XCTAssertTrue(id.allSatisfy { $0.isNumber || ("a"..."f").contains(String($0)) })
        }
    }

    // ===== isWeekend 边界 =====

    func testIsWeekend_matchesKotlinDayOfWeekSemantics() {
        XCTAssertTrue(HolidayManager.isWeekend(saturday))
        XCTAssertTrue(HolidayManager.isWeekend(sundayWorkday))
        XCTAssertFalse(HolidayManager.isWeekend(weekday))
    }

    private func iso(_ date: Date) -> String {
        HolidayManager.dateFormat.string(from: date)
    }
}
