// LocalCalendarFallbackTests.swift — ← app/src/test/java/com/lingion/sleepy/data/calendar/LocalCalendarFallbackContractTest.kt (v1.0.62 B6)
// 无可写日历时自建本地日历的兜底契约 — fake store 锁死:
// 并发仅建一次 / 无权限不查询 / 查询失败不授权插入 / 修复不重复 /
// 插入失败不发明日历 / 自建修复失败保留三方可写日历。
//
// 平台注记: 原版本 LocalCalendarStore 走 CalendarContract provider; iOS 侧由
// EventKitLocalCalendarStore 承担同一平台边界 — 本文件只测 LocalCalendarFallback
// 的策略层(与 原版本 契约逐条对齐), 不触真实 EventKit。

import XCTest
@testable import Sleepy

final class LocalCalendarFallbackTests: XCTestCase {

    private struct StoreError: Error {}

    /// ← 原版本 Store inner class — 失败注入 + 调用计数。
    /// 所有 store 调用都发生在 LocalCalendarFallback actor 内(串行),
    /// 测试线程仅在 await 完成后读计数, 无数据竞争; @unchecked Sendable 仅为此标注。
    private final class FakeStore: LocalCalendarStore, @unchecked Sendable {
        // 种子与外层测试实例的 info 同值（SystemCalendarInfo 按字段相等）
        static let seedInfo = SystemCalendarInfo(id: "42", displayName: "Sleepy",
                                                 accountName: "com.lingion.sleepy.account")
        var permission = true
        var queryFailure = false
        var ownedFailure = false
        var insertFailure = false
        var enableResult = true
        var inserts = 0
        var enables = 0
        var queries = 0
        var rows: [LocalCalendarRow] = []
        var calendars: [LocalCalendarRow] = []

        func hasPermissions() -> Bool { permission }
        func queryWritable() throws -> [LocalCalendarRow] {
            queries += 1
            if queryFailure { throw StoreError() }  // ← 原 check(!queryFailure)
            return calendars
        }
        func queryOwned() throws -> [LocalCalendarRow] {
            queries += 1
            if ownedFailure { throw StoreError() }
            return rows
        }
        func enable(_ row: LocalCalendarRow) -> Bool {
            enables += 1
            return enableResult
        }
        func insert() -> SystemCalendarInfo? {
            inserts += 1
            if insertFailure { return nil }
            rows = [LocalCalendarRow(info: Self.seedInfo, writable: true, deleted: false, visible: true, syncEvents: true)]
            return Self.seedInfo
        }
    }

    // ← 原版本 SystemCalendarInfo(42, "Sleepy", "com.lingion.sleepy.account", "LOCAL")
    //   iOS 无 type 字段, id 为 String(calendarIdentifier)
    private let info = SystemCalendarInfo(id: "42", displayName: "Sleepy",
                                          accountName: "com.lingion.sleepy.account")

    private func row(_ info: SystemCalendarInfo, writable: Bool, deleted: Bool,
                     visible: Bool, syncEvents: Bool, owned: Bool = false) -> LocalCalendarRow {
        LocalCalendarRow(info: info, writable: writable, deleted: deleted,
                         visible: visible, syncEvents: syncEvents, owned: owned)
    }

    // 1. 并发仅建一次 ← repeatedAndConcurrentCallsCreateExactlyOneCalendar
    func testRepeatedAndConcurrentCallsCreateExactlyOneCalendar() async {
        let policy = LocalCalendarFallback()
        let store = FakeStore()
        var results: [SystemCalendarInfo?] = []
        await withTaskGroup(of: SystemCalendarInfo?.self) { group in
            for _ in 0..<20 { group.addTask { await policy.ensure(store: store) } }
            for await r in group { results.append(r) }
        }
        XCTAssertEqual(20, results.count)
        for r in results {
            XCTAssertEqual(info.id, r?.id)
            XCTAssertEqual(info.displayName, r?.displayName)
            XCTAssertEqual(info.accountName, r?.accountName)
        }
        let again = await policy.ensure(store: store)
        XCTAssertEqual(info.id, again?.id)
        XCTAssertEqual(1, store.inserts)
    }

    // 2. 无权限不查询 ← deniedPermissionDoesNotAccessProvider
    func testDeniedPermissionDoesNotAccessProvider() async {
        let store = FakeStore()
        store.permission = false
        let policy = LocalCalendarFallback()
        let ensured = await policy.ensure(store: store)
        XCTAssertNil(ensured)
        let writable = await policy.writable(store: store)
        XCTAssertTrue(writable.isEmpty)
        XCTAssertEqual(0, store.queries)
        XCTAssertEqual(0, store.inserts)
    }

    // 3. 查询失败不授权插入 ← failedQueriesNeverAuthorizeInsert
    func testFailedQueriesNeverAuthorizeInsert() async {
        for writableFailure in [true, false] {
            let store = FakeStore()
            store.queryFailure = writableFailure
            store.ownedFailure = !writableFailure
            let policy = LocalCalendarFallback()
            let writable = await policy.writable(store: store)
            XCTAssertTrue(writable.isEmpty)
            XCTAssertEqual(0, store.inserts)
        }
    }

    // 4. 空查询兜底自建 / 有三方日历不自建 ← successfulEmptyQueryCreatesFallbackButExternalCalendarDoesNot
    func testSuccessfulEmptyQueryCreatesFallbackButExternalCalendarDoesNot() async {
        let policy = LocalCalendarFallback()
        let empty = FakeStore()
        let fallbackList = await policy.writable(store: empty)
        XCTAssertEqual([info.id], fallbackList.map { $0.id })
        XCTAssertEqual(1, empty.inserts)

        let external = info.copy(id: "99")
        let store = FakeStore()
        store.calendars = [row(external, writable: true, deleted: false, visible: true, syncEvents: true)]
        let listed = await policy.writable(store: store)
        XCTAssertEqual([external.id], listed.map { $0.id })
        XCTAssertEqual(0, store.inserts)
        XCTAssertEqual(1, store.queries)
    }

    // 5. 隐藏/实例停用的自建日历修复而不重复 ← hiddenOrInstancesDisabledOwnedCalendarIsRepairedWithoutDuplicate
    func testHiddenOrInstancesDisabledOwnedCalendarIsRepairedWithoutDuplicate() async {
        for visible in [true, false] {
            let store = FakeStore()
            store.rows = [row(info, writable: true, deleted: false, visible: visible, syncEvents: false)]
            let got = await LocalCalendarFallback().ensure(store: store)
            XCTAssertEqual(info.id, got?.id)
            XCTAssertEqual(1, store.enables)
            XCTAssertEqual(0, store.inserts)
        }
    }

    // 6. 修复失败/已有行不可用都不重复创建 ← failedRepairAndUnusableExistingRowsDoNotDuplicate
    func testFailedRepairAndUnusableExistingRowsDoNotDuplicate() async {
        let repair = FakeStore()
        repair.rows = [row(info, writable: true, deleted: false, visible: true, syncEvents: false)]
        repair.enableResult = false
        let ensured = await LocalCalendarFallback().ensure(store: repair)
        XCTAssertNil(ensured)
        XCTAssertEqual(0, repair.inserts)

        // ← 原版本 LocalCalendarRow(info, deleted, deleted, true, true): writable 与 deleted 同值
        for deleted in [true, false] {
            let store = FakeStore()
            store.rows = [row(info, writable: deleted, deleted: deleted, visible: true, syncEvents: true)]
            let ensured = await LocalCalendarFallback().ensure(store: store)
            XCTAssertNil(ensured)
            XCTAssertEqual(0, store.inserts)
        }
    }

    // 7. 插入失败返回空且不发明日历 ← insertionFailureReturnsEmptyWithoutInventedCalendar
    func testInsertionFailureReturnsEmptyWithoutInventedCalendar() async {
        let store = FakeStore()
        store.insertFailure = true
        let listed = await LocalCalendarFallback().writable(store: store)
        XCTAssertTrue(listed.isEmpty)
        XCTAssertEqual(1, store.inserts)
    }

    // 8. 自建修复失败保留三方可写日历 ← ownedRepairFailurePreservesThirdPartyWritableCalendars
    func testOwnedRepairFailurePreservesThirdPartyWritableCalendars() async {
        let external = info.copy(id: "99", accountName: "external")
        let store = FakeStore()
        store.calendars = [
            row(info, writable: true, deleted: false, visible: true, syncEvents: false, owned: true),
            row(external, writable: true, deleted: false, visible: true, syncEvents: false),
        ]
        store.enableResult = false
        let listed = await LocalCalendarFallback().writable(store: store)
        XCTAssertEqual([external.id], listed.map { $0.id })
        XCTAssertEqual(1, store.enables)
        XCTAssertEqual(0, store.inserts)
    }

    // 9. 可见自建日历实例停用时修复 ← visibleOwnedCalendarWithDisabledInstancesIsRepaired
    func testVisibleOwnedCalendarWithDisabledInstancesIsRepaired() async {
        let store = FakeStore()
        store.calendars = [row(info, writable: true, deleted: false, visible: true, syncEvents: false, owned: true)]
        let listed = await LocalCalendarFallback().writable(store: store)
        XCTAssertEqual([info.id], listed.map { $0.id })
        XCTAssertEqual(1, store.enables)
        XCTAssertEqual(0, store.inserts)
    }
}

/// SystemCalendarInfo 非 Equatable — 测试局部 helper
private extension SystemCalendarInfo {
    func copy(id: String? = nil, accountName: String? = nil) -> SystemCalendarInfo {
        SystemCalendarInfo(id: id ?? self.id, displayName: displayName, accountName: accountName ?? self.accountName)
    }
}
