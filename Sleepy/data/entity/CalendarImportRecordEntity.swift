// CalendarImportRecordEntity.swift — ← data/entity/CalendarImportRecordEntity.kt (逐行翻译, GPL-3.0)
// 原版本 calendarId/eventId 是 Long (CalendarContract.Events._id);
// iOS EventKit 对应 EKEvent CalendarItemExternalIdentifier (String), 语义等价适配,
// 列类型对齐 Room schema 保持 TEXT — 原版本 侧 Long 的十进制字符串在 iOS 侧不出现。

import Foundation
import GRDB

/// 只记录 Sleepy 自己写入系统日历的事件, 供后续同步去重/清理。
struct CalendarImportRecordEntity: Codable, FetchableRecord, MutablePersistableRecord, Identifiable {
    static let databaseTableName = "calendar_import_records"

    var tableId: Int64
    var courseId: Int64
    /// yyyy-MM-dd
    var eventDate: String
    /// iOS: EKCalendar.calendarIdentifier
    var calendarId: String
    /// iOS: EKEvent.calendarItemExternalIdentifier
    var eventId: String
    /// 一次导入批次的 uuid
    var batchId: String
    var fingerprint: String
    var alarmRequested: Bool
    var createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    /// 主键 autoGenerate
    var id: Int64 = 0

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    func encode(to container: inout PersistenceContainer) {
        container["id"] = id == 0 ? nil : id
        container["tableId"] = tableId
        container["courseId"] = courseId
        container["eventDate"] = eventDate
        container["calendarId"] = calendarId
        container["eventId"] = eventId
        container["batchId"] = batchId
        container["fingerprint"] = fingerprint
        container["alarmRequested"] = alarmRequested
        container["createdAt"] = createdAt
    }
}
