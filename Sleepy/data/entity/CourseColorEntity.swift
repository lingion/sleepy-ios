// CourseColorEntity.swift — ← data/entity/CourseColorEntity.kt (v1.0.62 B1)
// GRDB 复刻: course_colors 表, 复合主键 (tableKey, groupId)。
//
// 颜色绑定 groupId（课程身份标识），跨导入/改名稳定——重导入经认亲继承旧 groupId 即命中旧 hue；
// 改名同 row 同 gid 不动。
//
// tableKey 现阶段恒为 GLOBAL_TABLE_KEY：hue 跟课组走、与课表无关；
// 主键保留该维度，未来「每课表独立配色」直接启用，不动 schema。
//
// 写路径仅 ViewModel/导入层（spec §2.3），渲染层纯读；CLASSIC 档不读本表。

import Foundation
import GRDB

struct CourseColorEntity: Codable, FetchableRecord, MutablePersistableRecord {
    var tableKey: String
    var groupId: String
    var hue: Float

    enum CodingKeys: String, CodingKey {
        case tableKey, groupId, hue
    }

    static let GLOBAL_TABLE_KEY = "__global__"

    // MARK: - PersistableRecord

    static var databaseTableName = "course_colors"

    enum Columns: String, ColumnExpression {
        case tableKey
        case groupId
        case hue
    }

    func encode(to container: inout PersistenceContainer) {
        container["tableKey"] = tableKey
        container["groupId"] = groupId
        container["hue"] = hue
    }

    init(tableKey: String = GLOBAL_TABLE_KEY, groupId: String, hue: Float) {
        self.tableKey = tableKey
        self.groupId = groupId
        self.hue = hue
    }
}
