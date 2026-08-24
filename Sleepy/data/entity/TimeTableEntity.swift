// TimeTableEntity.swift — ← data/entity/TimeTableEntity.kt (逐行翻译, GPL-3.0)

import Foundation
import GRDB

/// 课表实体 (TimeTable) — 一个课表包含多个课程
struct TimeTableEntity: Codable, FetchableRecord, PersistableRecord {
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
    /// 主键 autoGenerate
    var id: Int64 = 0
}
