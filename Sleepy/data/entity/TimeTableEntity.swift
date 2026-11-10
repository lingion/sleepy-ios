// TimeTableEntity.swift — ← data/entity/TimeTableEntity.kt (逐行翻译, GPL-3.0)

import Foundation
import GRDB

/// 课表实体 (TimeTable) — 一个课表包含多个课程
struct TimeTableEntity: Codable, FetchableRecord, MutablePersistableRecord, Identifiable {
    static let databaseTableName = "time_tables"

    var name: String
    /// 学期开始日期 (yyyy-MM-dd), 用于计算当前周次
    var startDate: String
    /// 学期总周数
    var maxWeek: Int = 20
    /// 一天的节次数
    var nodesPerDay: Int = 12
    /// 第几节课的上课时间表 JSON。
    /// 默认值委托给 TimeTableUtils.DEFAULT_TIME_JSON,保持与 UI 渲染 / 解析器**单一来源**。
    var timeJson: String = TimeTableUtils.DEFAULT_TIME_JSON
    /// 颜色主题
    var color: String = "#FF6750A4"
    /// 是否为默认课表
    var isDefault: Bool = false
    /// v1.0.16 自动模式（智慧节次）配置 JSON。空串表示该表走手动模式（timeJson）。
    var smartConfigJson: String = ""
    var createdAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    /// issue#40 绑定的独立时间节次表 (period_tables.id)。nil = 未绑定(用旧 timeJson 兼容列)。
    /// 课程表 → 时间节次表的单向引用; 一张时间节次表可被多张课程表引用。
    /// 修改所绑时间表 = 本表立即按新作息解释节次; 课程行 startNode/step 不重算。
    var periodTableId: Int64? = nil
    /// C2(2026-09-20): 换绑前本表自身作息快照 — 绑定时的 timeJson/nodesPerDay/smartConfigJson
    /// 三元组 JSON 包络({t,n,s}), 解绑时恢复此快照再清空。
    /// 修复 issue#40 用户数据破坏: 旧实现换绑时把目标表内容镜像覆盖本表兼容列,
    /// 解绑后"使用本表作息"读到的是镜像副本, 用户手工作息永久丢失。
    /// 快照仅当 periodTableId 由 nil → 非 nil 时写入一次; 绑→绑换目标不刷新快照。
    var preBindSnapshotJson: String = ""
    /// v11 (2026-10-08 用户诉求): 每表独立提醒开关。旧行默认 1 = 所有表继续参与提醒。
    var reminderEnabled: Bool = true
    /// Nil follows the selected timetable until the first manual scope choice.
    var reminderOverride: Bool? = nil
    /// Source suggestions remain separate from confirmed timetable fields.
    var importSourceJson: String = ""
    /// 主键 autoGenerate
    var id: Int64 = 0

    /// GRDB: 自增主键插入后回填
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    /// Kotlin @PrimaryKey(autoGenerate = true) 语义: id=0 视为"未设置",
    /// INSERT 时不编码该列 → SQLite 走自增。(GRDB 默认会把 0 当显式值插入,与 Room 不一致)
    func encode(to container: inout PersistenceContainer) {
        container["id"] = id == 0 ? nil : id
        container["name"] = name
        container["startDate"] = startDate
        container["maxWeek"] = maxWeek
        container["nodesPerDay"] = nodesPerDay
        container["timeJson"] = timeJson
        container["color"] = color
        container["isDefault"] = isDefault
        container["smartConfigJson"] = smartConfigJson
        container["createdAt"] = createdAt
        container["periodTableId"] = periodTableId
        container["preBindSnapshotJson"] = preBindSnapshotJson
        container["reminderEnabled"] = reminderEnabled
        container["reminderOverride"] = reminderOverride
        container["importSourceJson"] = importSourceJson
    }

    /// issue#40 有效时间表水合(设计 §5.1): 绑定存在 → 节次时间/智慧节次/节次数
    /// 全部以所绑 periodTable 为准覆盖本表对应字段(兼容列保留不动, 仅作回退);
    /// 未绑定或传入 nil → 原样返回(读旧兼容列, 行为与升级前一致)。
    ///
    /// 渲染/通知/widget 路径统一经此函数取"节次→时间"的真源;
    /// 课程行按 startNode/step 节次绑定, 不因水合而变。
    func hydratedWith(_ periodTable: PeriodTableEntity?) -> TimeTableEntity {
        guard let pt = periodTable else { return self }
        var t = self
        t.nodesPerDay = pt.nodesPerDay
        t.timeJson = pt.timeJson
        t.smartConfigJson = pt.smartConfigJson
        return t
    }

    /// C2: 首次绑定(nil → 非 nil)时产出的新实体 — 兼容列不变,
    /// 只写 periodTableId 并把绑定前的 {t,n,s} 三元组存进快照列。
    static func snapshotForBind(table: TimeTableEntity, targetId: Int64) -> TimeTableEntity {
        var t = table
        t.periodTableId = targetId
        t.preBindSnapshotJson = PeriodTableEntity.snapshotJsonForBind(table: table)
        return t
    }

    /// C2: 解绑(非 nil → nil)时的新实体 — 见 PeriodTableEntity.restoredForUnbind
    static func restoredForUnbind(table: TimeTableEntity) -> TimeTableEntity {
        PeriodTableEntity.restoredForUnbind(table)
    }
}


extension TimeTableEntity {
    enum CodingKeys: String, CodingKey {
        case name, startDate, maxWeek, nodesPerDay, timeJson, color, isDefault,
             smartConfigJson, createdAt, periodTableId, preBindSnapshotJson,
             reminderEnabled, reminderOverride, importSourceJson, id
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        startDate = try c.decode(String.self, forKey: .startDate)
        maxWeek = try c.decodeIfPresent(Int.self, forKey: .maxWeek) ?? 20
        nodesPerDay = try c.decodeIfPresent(Int.self, forKey: .nodesPerDay) ?? 12
        timeJson = try c.decodeIfPresent(String.self, forKey: .timeJson) ?? TimeTableUtils.DEFAULT_TIME_JSON
        color = try c.decodeIfPresent(String.self, forKey: .color) ?? "#FF6750A4"
        isDefault = try c.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        smartConfigJson = try c.decodeIfPresent(String.self, forKey: .smartConfigJson) ?? ""
        createdAt = try c.decodeIfPresent(Int64.self, forKey: .createdAt) ?? 0
        periodTableId = try c.decodeIfPresent(Int64.self, forKey: .periodTableId)
        preBindSnapshotJson = try c.decodeIfPresent(String.self, forKey: .preBindSnapshotJson) ?? ""
        reminderEnabled = try c.decodeIfPresent(Bool.self, forKey: .reminderEnabled) ?? true
        reminderOverride = try c.decodeIfPresent(Bool.self, forKey: .reminderOverride)
        importSourceJson = try c.decodeIfPresent(String.self, forKey: .importSourceJson) ?? ""
        id = try c.decodeIfPresent(Int64.self, forKey: .id) ?? 0
    }
}

func resolveReminderTableScope(tables: [TimeTableEntity], selectedTableId: Int64?) -> [TimeTableEntity] {
    let manual = tables.contains { $0.reminderOverride != nil }
    let selected = tables.first { $0.id == selectedTableId } ?? tables.first { $0.isDefault } ?? tables.first
    return tables.map { source in
        var table = source
        table.reminderEnabled = manual ? source.reminderOverride == true
            : source.id == selected?.id && source.reminderEnabled
        return table
    }
}
