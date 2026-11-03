// PeriodTableEntity.swift — ← data/entity/PeriodTableEntity.kt (逐行翻译, GPL-3.0)

import Foundation
import GRDB

/// 独立时间节次表 (issue#40) — "第 N 节是几点到几点"的真源, 与课程表(TimeTable)平行的层级。
///
/// 一张时间节次表可被零张或多张课程表引用 (TimeTable.periodTableId 单向指向本表);
/// 修改本表 = 所有引用它的课程表立即按新作息解释节次。课程行按 startNode/step
/// 节次绑定, 不因本表修改而重算 (2026-09-15 用户拍板)。
///
/// timeJson/smartConfigJson 沿用 TimeTableUtils 的 JSON 形状, 单一解析来源。
struct PeriodTableEntity: Codable, FetchableRecord, MutablePersistableRecord, Identifiable {
    static let databaseTableName = "period_tables"

    /// 用户可见名称, 如"春季作息"
    var name: String
    /// 一天的节次数
    var nodesPerDay: Int = 12
    /// 第几节课的上课时间表 JSON。默认值委托给 TimeTableUtils.DEFAULT_TIME_JSON,
    /// 与 UI 渲染 / 解析器保持**单一来源**。
    var timeJson: String = TimeTableUtils.DEFAULT_TIME_JSON
    /// 智慧节次配置 JSON。空串表示手动模式（timeJson）。
    var smartConfigJson: String = ""
    var createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    var updatedAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    /// 主键 autoGenerate
    var id: Int64 = 0

    /// GRDB: 自增主键插入后回填
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    /// Kotlin @PrimaryKey(autoGenerate = true) 语义: id=0 视为"未设置"。
    func encode(to container: inout PersistenceContainer) {
        container["id"] = id == 0 ? nil : id
        container["name"] = name
        container["nodesPerDay"] = nodesPerDay
        container["timeJson"] = timeJson
        container["smartConfigJson"] = smartConfigJson
        container["createdAt"] = createdAt
        container["updatedAt"] = updatedAt
    }

    // MARK: - 绑定/解绑状态机 (C2, 2026-09-20, issue#40 用户数据破坏修复)

    /// C2: 首次绑定(null → 非 null)时产出的新实体 — 兼容列不变,
    /// 只写 periodTableId 并把绑定前的 {t,n,s} 三元组存进快照列。
    /// (periodTableId 在 TimeTableEntity 上;此处产快照 JSON, 由调用方落列)
    static func snapshotJsonForBind(table: TimeTableEntity) -> String {
        let obj: [String: Any] = [
            "t": table.timeJson,
            "n": table.nodesPerDay,
            "s": table.smartConfigJson,
        ]
        // JSONSerialization 输出顺序不保证;原版本 org.json.JSONObject 同样无序,
        // 消费端只按键读取, 顺序无关 → 语义等价
        if let data = try? JSONSerialization.data(withJSONObject: obj),
           let s = String(data: data, encoding: .utf8) {
            return s
        }
        return ""
    }

    /// C2: 解绑(非 null → null)时的新实体 — 快照存在则恢复绑定前兼容列再清空;
    /// 快照缺失(空/损坏, 只可能来自旧版本升级/历史脏数据)按原样解绑,
    /// 兼容列保持绑定期间最后一次已知值(旧行为)。
    static func restoredForUnbind(_ table: TimeTableEntity) -> TimeTableEntity {
        var t = table
        if t.preBindSnapshotJson.isEmpty { t.periodTableId = nil; t.preBindSnapshotJson = ""; return t }
        guard let data = t.preBindSnapshotJson.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            t.periodTableId = nil; t.preBindSnapshotJson = ""; return t
        }
        t.periodTableId = nil
        if let n = obj["n"] as? Int { t.nodesPerDay = n }
        if let jt = obj["t"] as? String { t.timeJson = jt }
        if let s = obj["s"] as? String { t.smartConfigJson = s }
        t.preBindSnapshotJson = ""
        return t
    }
}
