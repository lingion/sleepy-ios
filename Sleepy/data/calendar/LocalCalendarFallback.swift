// LocalCalendarFallback.swift — ← data/calendar/LocalCalendarFallback.kt (v1.0.62 B6)
//                              + data/calendar/原日历存储实现 (平台等价)
//
// 无可写日历时自建本地日历的兜底策略。原版本 侧 LocalCalendarStore 走 CalendarContract
// provider; iOS 侧 EventKit 无「自建日历 provider」等价物, 由 EventKitLocalCalendarStore
// 承担同一平台边界 — 契约(权限闸 / 查询失败不授权创建 / 自建去重 / 修复不重复)逐条对齐,
// 由 LocalCalendarFallbackTests 以 fake store 锁死(← 原 LocalCalendarFallbackContractTest)。
//
// 平台映射:
// - ACCOUNT_NAME=packageName.account + ACCOUNT_TYPE_LOCAL 的 owned 判定 →
//   EventKit 无账号元数据 → 以保留显示名 "Sleepy" 识别自建日历(兜底产物必须能被再次找到)
// - DELETED / VISIBLE / SYNC_EVENTS 位 → EventKit 无对应概念: 恒 false/true/true;
//   enable 无位可写 → no-op true (修复路径在真机恒不触发, 契约由 fake store 测试承载)
// - 自建日历源: 本地源优先(← ACCOUNT_TYPE_LOCAL 不入云); 设备无本地源时退
//   defaultCalendarForNewEvents 的源(EventKit 公开 API 无法凭空创建 .local source)

import EventKit
import Foundation
import UIKit

/// ← 原版本 LocalCalendarRow (internal data class)
struct LocalCalendarRow {
    var info: SystemCalendarInfo
    var writable: Bool
    var deleted: Bool
    var visible: Bool
    var syncEvents: Bool
    var owned: Bool = false
}

/// ← 原版本 LocalCalendarStore (internal interface) — 平台边界。
/// 查询失败必须 throw(不可吞成空数组) ← 原版本 "Null provider cursors and other
/// query failures must throw; empty means success"。
protocol LocalCalendarStore {
    func hasPermissions() -> Bool
    func queryWritable() throws -> [LocalCalendarRow]
    func queryOwned() throws -> [LocalCalendarRow]
    func enable(_ row: LocalCalendarRow) -> Bool
    func insert() -> SystemCalendarInfo?
}

/// ← 原版本 LocalCalendarFallback — 串行化整个 check/create 流程。
/// Kotlin kotlinx Mutex.withLock → Swift actor 隔离(同一进程内所有调用方串行)。
/// safely(fallback) 语义 → try? 捕获一切查询/写入失败回落默认值。
actor LocalCalendarFallback {

    /// ← 原版本 ensure: 无权限直接 nil; 查询失败不授权创建。
    func ensure(store: LocalCalendarStore) async -> SystemCalendarInfo? {
        guard store.hasPermissions() else { return nil }
        // ← 原版本 safely(null): CancellationException 重抛 — Swift 侧 store 调用
        //   均为同步快调用, 无挂起点, 无需显式取消传播。
        return (try? ensureLocked(store)) ?? nil
    }

    /// ← 原版本 writable: 先列可写日历(owned 行 syncEvents 关闭时先修复),
    /// 全空才 ensureLocked 兜底自建; 任何查询失败整体回落空列表。
    func writable(store: LocalCalendarStore) async -> [SystemCalendarInfo] {
        guard store.hasPermissions() else { return [] }
        return (try? writableLocked(store)) ?? []
    }

    private func writableLocked(_ store: LocalCalendarStore) throws -> [SystemCalendarInfo] {
        let calendars: [SystemCalendarInfo] = try store.queryWritable().compactMap { row in
            if row.owned && !row.syncEvents {
                // ← 原版本 safely(false) { store.enable(row) }: 单行修复失败只丢该行
                return store.enable(row) ? row.info : nil
            }
            return row.info
        }
        if !calendars.isEmpty { return calendars }
        // ← 原版本 listOfNotNull(ensureLocked(store)): ensureLocked 失败 → 整体空
        return try ensureLocked(store).map { [$0] } ?? []
    }

    /// ← 原版本 ensureLocked: 已有可用自建日历 → 复用(必要时修复);
    /// 存在但已删/只读 → 不重复创建; 完全没有 → insert 自建。
    private func ensureLocked(_ store: LocalCalendarStore) throws -> SystemCalendarInfo? {
        let owned = try store.queryOwned()
        if let row = owned.first(where: { $0.writable && !$0.deleted }) {
            if (!row.visible || !row.syncEvents) && !store.enable(row) { return nil }
            return row.info
        }
        // Existing deleted/read-only calendars do not authorize creating a duplicate.
        return owned.isEmpty && store.hasPermissions() ? store.insert() : nil
    }
}

/// ← 原版本 原日历存储 — EventKit 平台实现。
/// queryWritable 保留 v1.0.61 平台裁决(排除 .local/.calDAV 外部源)并恒纳入
/// Sleepy 自建日历 — 兜底产物必须出现在可写列表, 否则用户永远选不中它。
final class EventKitLocalCalendarStore: LocalCalendarStore {

    /// 自建日历保留显示名(CALENDAR_DISPLAY_NAME = "Sleepy")
    static let ownedDisplayName = "Sleepy"
    /// ← 原版本 CALENDAR_COLOR = 0xFF4285F4
    private static let ownedColorRed: CGFloat = 0x42 / 255.0
    private static let ownedColorGreen: CGFloat = 0x85 / 255.0
    private static let ownedColorBlue: CGFloat = 0xF4 / 255.0

    private let store: EKEventStore

    init(store: EKEventStore) {
        self.store = store
    }

    func hasPermissions() -> Bool {
        SystemCalendarManager.shared.hasCalendarPermissions()
    }

    func queryWritable() throws -> [LocalCalendarRow] {
        // 排序 ← 原 query ORDER BY IS_PRIMARY DESC, CALENDAR_DISPLAY_NAME COLLATE NOCASE:
        // defaultCalendarForNewEvents 作为 primary 代理恒排首位, 其余按 title 不区分大小写升序。
        let defaultId = store.defaultCalendarForNewEvents?.calendarIdentifier
        return store.calendars(for: .event)
            .filter { cal in
                guard cal.allowsContentModifications else { return false }
                return isOwned(cal) || (cal.type != .local && cal.type != .calDAV)
            }
            .map { row(for: $0) }
            .sorted { lhs, rhs in
                let lPrimary = lhs.info.id == defaultId
                let rPrimary = rhs.info.id == defaultId
                if lPrimary != rPrimary { return lPrimary }
                return lhs.info.displayName.localizedCaseInsensitiveCompare(rhs.info.displayName) == .orderedAscending
            }
    }

    func queryOwned() throws -> [LocalCalendarRow] {
        let defaultId = store.defaultCalendarForNewEvents?.calendarIdentifier
        return store.calendars(for: .event)
            .filter { isOwned($0) }
            .map { row(for: $0) }
            .sorted { lhs, rhs in
                let lPrimary = lhs.info.id == defaultId
                let rPrimary = rhs.info.id == defaultId
                if lPrimary != rPrimary { return lPrimary }
                return lhs.info.displayName.localizedCaseInsensitiveCompare(rhs.info.displayName) == .orderedAscending
            }
    }

    /// 平台裁决: EventKit 无 VISIBLE/SYNC_EVENTS 可写位 → no-op true。
    /// (原 enable 翻 VISIBLE=1 + SYNC_EVENTS=1; iOS 本地日历恒可见恒同步)
    func enable(_ row: LocalCalendarRow) -> Bool { true }

    /// ← 原版本 insert(): 自建「Sleepy」日历。本地源优先(不入云 ← ACCOUNT_TYPE_LOCAL);
    /// 无本地源时退 defaultCalendarForNewEvents 的源(公开 API 无法凭空创建 .local source)。
    func insert() -> SystemCalendarInfo? {
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = Self.ownedDisplayName
        calendar.cgColor = UIColor(red: Self.ownedColorRed, green: Self.ownedColorGreen,
                                 blue: Self.ownedColorBlue, alpha: 1).cgColor
        guard let source = store.sources.first(where: { $0.sourceType == .local })
            ?? store.defaultCalendarForNewEvents?.source else { return nil }
        calendar.source = source
        guard (try? store.saveCalendar(calendar, commit: true)) != nil else { return nil }
        return SystemCalendarInfo(
            id: calendar.calendarIdentifier,
            displayName: calendar.title,
            accountName: calendar.source.title
        )
    }

    private func isOwned(_ cal: EKCalendar) -> Bool {
        cal.title == Self.ownedDisplayName
    }

    /// ← 原 query 投影: writable=ACCESS_LEVEL>=CONTRIBUTOR, deleted/visible/syncEvents
    /// EventKit 无位 → 恒 false/true/true; owned 按保留显示名判定。
    private func row(for cal: EKCalendar) -> LocalCalendarRow {
        LocalCalendarRow(
            info: SystemCalendarInfo(
                id: cal.calendarIdentifier,
                displayName: cal.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? cal.source.title : cal.title,
                accountName: cal.source.title
            ),
            writable: cal.allowsContentModifications,
            deleted: false,
            visible: true,
            syncEvents: true,
            owned: isOwned(cal)
        )
    }
}
