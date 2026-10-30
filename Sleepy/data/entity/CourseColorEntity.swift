// CourseColorEntity.swift — ← data/entity/CourseColorEntity.kt (v1.0.62, GPL-3.0)
// Room @Entity(tableName = "course_colors", primaryKeys = ["tableKey", "groupId"])
// → GRDB 复合主键记录。表结构/列名/类型亲和与 Room schema 逐列一致。
//
// 语义: App 级「派生档」把课程组的色相持久化 — 渲染层纯读(persistedHue ?: stableHue),
// 写入只发生在课程组诞生时刻(导入/单课新增)与显式全量重排。
// 无回填: 升级到 v1.0.62 时 course_colors 为空 → 渲染零变化(CLASSIC 档)。

import Foundation
import GRDB

/// 持久色相记录 — tableKey + groupId 复合主键
struct CourseColorEntity: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "course_colors"

    /// 课表键 — 当前只有全局档 "__global__"(与 Android CourseColorEntity.GLOBAL_TABLE_KEY 同值)
    var tableKey: String = CourseColorEntity.globalTableKey
    /// 课程组 ID
    var groupId: String
    /// 色相(0..360)
    var hue: Float

    /// 全局档键 — course_colors 暂只存全局一套(跨课表共享, 与 Android 一致)
    static let globalTableKey = "__global__"

    enum Columns {
        static let tableKey = Column("tableKey")
        static let groupId = Column("groupId")
        static let hue = Column("hue")
    }

    init(tableKey: String = CourseColorEntity.globalTableKey, groupId: String, hue: Float) {
        self.tableKey = tableKey
        self.groupId = groupId
        self.hue = hue
    }

    func encode(to container: inout PersistenceContainer) {
        container["tableKey"] = tableKey
        container["groupId"] = groupId
        container["hue"] = hue
    }
}
