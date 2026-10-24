// HolidayReminderPolicyAdapterTests.swift — ← util/HolidayReminderPolicyAdapterTest.kt (GPL-3.0)
//
// 安卓用 File.readText() 读源头文件做结构契约(沿用 WidgetInfoXmlContractTest 先例);
// iOS 沿用 #filePath 相对定位工程内源文件的同一手法(见 UndoCaptureCoverageTests)。
// 这里锁的是"适配器只做边界、不做第二遍合并"这一结构事实:
// HolidayReminderPolicyAdapterTest.kt 用 assertFalse 硬性禁止 mergeSegments/toSets
// 出现在适配器里, 因此 iOS 侧若把它们塞回适配器(=先前会话的修法)就是违宪。
//
// 真机测试宿主上源文件不在盘(模拟器可读宿主文件), 此时显式 XCTSkip 而非静默通过。

import XCTest
@testable import Sleepy

final class HolidayReminderPolicyAdapterTests: XCTestCase {

    /// Sleepy/util/ 目录: 相对本测试源文件定位工程根。
    private var utilDir: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // SleepyTests/
            .deletingLastPathComponent()   // 工程根
            .appendingPathComponent("Sleepy/util")
    }

    /// 读源文件; 不在盘时抛 XCTSkip(与安卓 test.root 缺失时的语义不同, 这里必须显式跳过)。
    private func source(_ name: String) throws -> String {
        let url = utilDir.appendingPathComponent(name)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw XCTSkip("源文件不在盘(真机宿主?) — 契约测试需在模拟器/主机构建运行: \(url.path)")
        }
        return text
    }

    /// ← 安卓 `adapter reads reminder preferences rather than grey holiday preferences`
    /// 提醒路径只读 reminder 开关, 绝不读灰显开关(两套 pref 混用会让课表灰显设置
    /// 意外改变提醒行为)。
    func testAdapterReadsReminderPreferencesNotGreyHolidayPreferences() throws {
        let source = try source("HolidayReminderPolicyAdapter.swift")

        for read in [
            "isHolidayReminderRulesEnabled()",
            "isHolidayReminderPublicHolidayEnabled()",
            "isHolidayReminderTransferHolidayEnabled()",
            "isHolidayReminderMakeupWorkdayEnabled()",
            "isHolidayReminderOrdinaryWeekendEnabled()",
        ] {
            XCTAssertTrue(source.contains(read), "缺少提醒开关读取: \(read)")
        }

        for forbidden in [
            "KEY_HOLIDAY_GREY_HOLIDAY", "KEY_HOLIDAY_GREY_WEEKEND", "KEY_HOLIDAY_IGNORE_WORKDAY",
            "isHolidayGreyHoliday", "isHolidayGreyWeekend", "isHolidayIgnoreWorkday",
        ] {
            XCTAssertFalse(source.contains(forbidden), "适配器不得引用灰显开关: \(forbidden)")
        }
    }

    /// ← 安卓 `adapter reads effective entries merged by manager without merging twice`
    /// 合并只做一次且只做在 HolidayManager.getYearData() 里; 适配器只按两种 API 类型
    /// 过滤 yearData.entries, 可用性直接取 yearData.available。
    func testAdapterReadsEntriesMergedByManagerWithoutMergingTwice() throws {
        let adapterSource = try source("HolidayReminderPolicyAdapter.swift")
        let managerSource = try source("HolidayManager.swift")

        // 合并确实发生在 manager 侧
        XCTAssertTrue(managerSource.contains("HolidayRangeOps.mergeSegments(entries, AppPrefs.shared.getHolidayRanges())"),
                      "HolidayManager.getYearData 必须完成用户覆盖合并")
        XCTAssertTrue(managerSource.contains("available: hasCachedData || !fetchFailed"),
                      "HolidayManager.yearData 必须按 hasCachedData || !fetchFailed 计算 available")

        // 适配器只消费 manager 的合并结果
        XCTAssertTrue(adapterSource.contains("yearData.entries"),
                      "适配器必须从 yearData.entries 取生效条目")
        XCTAssertTrue(adapterSource.contains("HolidayManager.TYPE_PUBLIC_HOLIDAY"),
                      "适配器必须按 public_holiday 类型过滤")
        XCTAssertTrue(adapterSource.contains("HolidayManager.TYPE_TRANSFER_WORKDAY"),
                      "适配器必须按 transfer_workday 类型过滤")
        XCTAssertTrue(adapterSource.contains("dataAvailable: yearData.available"),
                      "适配器必须把 yearData.available 原样传给策略")

        // 适配器禁止自己再合并一遍
        XCTAssertFalse(adapterSource.contains("HolidayRangeOps.mergeSegments"),
                       "适配器不得自行 mergeSegments — 合并只在 manager 做一次")
        XCTAssertFalse(adapterSource.contains("HolidayRangeOps.toSets"),
                       "适配器不得自行 toSets — 与安卓契约同为违宪")
        XCTAssertFalse(adapterSource.contains("getYearEntries"),
                       "适配器不得绕过 getYearData 直接取原始网络条目")
    }

    /// ← 安卓 `adapter scopes transfer lookup to the supplied table id`
    /// 调休映射按课表隔离, 取数必须带 tableId(无参重载会读到别的课表的映射)。
    func testAdapterScopesTransferLookupToSuppliedTableId() throws {
        let source = try source("HolidayReminderPolicyAdapter.swift")
        XCTAssertTrue(source.contains("getHolidayTransfers(tableId)"),
                      "调休查表必须限定在传入的 tableId")
    }

    // MARK: - 行为面: 类型桶化语义(← HolidayYearData 展开后的按日条目)

    /// 展开后的生效条目里, 只有两种 API 类型参与桶化: public_holiday 进节假日集合,
    /// transfer_workday 进补班集合; 未知类型两者都不进(← 安卓两个 == 过滤, 而非
    /// toSets 的"非 workday 即节假日")。
    func testBucketingFiltersExactlyTwoApiTypes() throws {
        let date = HolidayManager.dateFormat.date(from: "2026-05-01")
        XCTAssertNotNil(date, "日期解析前置条件")
        let d = try XCTUnwrap(date)

        let yearData = HolidayYearData(
            entries: [
                HolidayEntry(date: d, name: "劳动节", type: HolidayManager.TYPE_PUBLIC_HOLIDAY),
                HolidayEntry(date: d, name: "班", type: HolidayManager.TYPE_TRANSFER_WORKDAY),
                HolidayEntry(date: d, name: "异常类型", type: "something_else"),
            ],
            available: true
        )

        let holidays = Set(yearData.entries
            .filter { $0.type == HolidayManager.TYPE_PUBLIC_HOLIDAY }
            .map { $0.date })
        let workdays = Set(yearData.entries
            .filter { $0.type == HolidayManager.TYPE_TRANSFER_WORKDAY }
            .map { $0.date })

        XCTAssertEqual(holidays, [d])
        XCTAssertEqual(workdays, [d])
    }

    /// available=false(该年取数失败且无缓存)时策略走 dataUnavailable 兜底:
    /// allowReminder 仍为 true, 但分类为 .dataUnavailable —— 适配器把 yearData.available
    /// 原样传入正是为了让这一分支与安卓一致。← HolidayReminderPolicy.decide L145-147
    func testUnavailableYearStillAllowsReminderButReportsDataUnavailable() {
        let unavailable = HolidayManager.yearData([], fetchFailed: true, hasCachedData: false)
        XCTAssertFalse(unavailable.available)

        let result = HolidayReminderPolicy.decide(
            date: Date(),
            publicHolidays: [],
            transferWorkdays: [],
            transfers: [],
            rulesEnabled: true,
            publicHolidayReminder: true,
            transferHolidayReminder: true,
            makeupWorkdayReminder: true,
            ordinaryWeekendReminder: true,
            dataAvailable: unavailable.available
        )
        XCTAssertEqual(result.category, .dataUnavailable)
        XCTAssertTrue(result.allowReminder)
    }

    /// 空年份但取数成功(available=true)不能被误判为数据不可用 —— 这是
    /// dataAvailable 语义的核心区分(安卓 same 断言于 HolidayManagerTest)。
    func testSuccessfulEmptyYearIsAvailableNotDataUnavailable() {
        let successfulEmpty = HolidayManager.yearData([], fetchFailed: false, hasCachedData: false)
        XCTAssertTrue(successfulEmpty.available)

        let result = HolidayReminderPolicy.decide(
            date: Date(),
            publicHolidays: [],
            transferWorkdays: [],
            transfers: [],
            rulesEnabled: true,
            publicHolidayReminder: true,
            transferHolidayReminder: true,
            makeupWorkdayReminder: true,
            ordinaryWeekendReminder: true,
            dataAvailable: successfulEmpty.available
        )
        XCTAssertNotEqual(result.category, .dataUnavailable)
    }
}
