// CourseEntity.swift — ← data/entity/CourseEntity.kt (逐行翻译, GPL-3.0)
// Sleepy iOS — 100% port of sleepy Android

import Foundation
import GRDB

/// 课程实体 — Room @Entity(tableName = "courses") 的 GRDB 对应
/// 表结构/列名/索引/FK 与 Room schema 逐列一致(建表 SQL 见 AppDatabase.swift)
struct CourseEntity: Codable, FetchableRecord, MutablePersistableRecord, Identifiable {
    static let databaseTableName = "courses"

    /// 课程组 ID — 同一门课的所有节次共享，编辑/删除时按此操作
    var groupId: String
    /// 所属课表 ID
    var tableId: Int64
    /// 课程名
    var courseName: String
    /// 教师
    var teacher: String = ""
    /// 教室
    var room: String = ""
    /// 备注
    var note: String = ""
    /// 周几 1-7 (周一=1)
    var day: Int
    /// 开始节次 (1-based, 1 = 第 1 节)
    var startNode: Int
    /// 持续节数 (例如 2 节连上)
    var step: Int
    /// 起始周
    var startWeek: Int
    /// 结束周
    var endWeek: Int
    /// 周次类型: 0=每周, 1=单周(第1/3/5周), 2=双周(第2/4/6周), 3=按周次列实际指定的周
    /// (用于"只在某一两周上"的单次实验课; 解析器在类型列缺失/不明时默认填 3 而非 0,
    /// 避免把"周次=6 单次实验"误标成"每周都上")
    var type: Int = 0
    /// 颜色 (ARGB Hex, 例如 "#FF6750A4")
    ///
    /// 字段语义随 colorMode 而异:
    ///   - colorMode = GROUP  : 整门课程的"组色",所有节次共享(原行为)
    ///   - colorMode = AUTO   : 本字段无意义;渲染时按 golden angle 137.508° 重算
    ///   - colorMode = CUSTOM : 本字段存用户选定的十六进制
    var color: String
    /// 颜色模式 (issue#22 同名课程多地点修复新增):
    ///   0 = GROUP  — 跟随整门课程组色 (默认,旧数据全部走这个)
    ///   1 = AUTO   — 自动色,渲染时按 row 自身 id 相对同组行序号实时算
    ///   2 = CUSTOM — 自定义色,color 字段存十六进制
    var colorMode: Int = 0
    /// 非常规节次卡 (issue#23): startNode 为边缘编号(早课/午休/晚课)时为 true,
    /// 渲染走独立卡片通道; 保存时由 startNode 推导回写防漂移
    var isIrregularNode: Bool = false
    /// 非常规时间卡 (issue#23): true = 用 startTime/endTime 直读时间(吞并旧 ownTime 语义)
    var isIrregularTime: Bool = false
    /// 是否自定义时间 (即 startTime/endTime 由用户设置而非系统)
    /// 保留字段以兼容 WakeUp 旧 db
    var ownTime: Bool = false
    /// 自定义开始时间 (HH:mm), 仅 ownTime/isIrregularTime=true 时使用
    var startTime: String = ""
    /// 自定义结束时间 (HH:mm), 仅 ownTime/isIrregularTime=true 时使用
    var endTime: String = ""
    /// 课程别名 (issue#26): 非空时界面显示此名, 课表数据仍用 courseName
    var alias: String = ""
    var credit: Double = 0
    var level: Int = 0
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
        container["groupId"] = groupId
        container["tableId"] = tableId
        container["courseName"] = courseName
        container["teacher"] = teacher
        container["room"] = room
        container["note"] = note
        container["day"] = day
        container["startNode"] = startNode
        container["step"] = step
        container["startWeek"] = startWeek
        container["endWeek"] = endWeek
        container["type"] = type
        container["color"] = color
        container["colorMode"] = colorMode
        container["isIrregularNode"] = isIrregularNode
        container["isIrregularTime"] = isIrregularTime
        container["ownTime"] = ownTime
        container["startTime"] = startTime
        container["endTime"] = endTime
        container["alias"] = alias
        container["credit"] = credit
        container["level"] = level
    }
}

/// ← CourseColorMode (issue#22): 0=GROUP 跟随组色 / 1=AUTO 自动色 / 2=CUSTOM 自定义色
enum CourseColorMode {
    static let GROUP = 0
    static let AUTO = 1
    static let CUSTOM = 2
}

extension CourseEntity {
    /// Kotlin `isNotBlank()` 等价: 纯空白串(空格/换行/制表)视为空
    private static func isNotBlank(_ s: String) -> Bool {
        return !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 第 N 周是否上这门课
    /// Kotlin: fun inWeek(week: Int): Boolean
    func inWeek(_ week: Int) -> Bool {
        if week < startWeek || week > endWeek { return false }
        switch type {
        case 0: return true   // 每周
        case 1: return week % 2 == 1  // 单周
        case 2: return week % 2 == 0  // 双周
        default: return true  // 3 = 按周次列实际指定的周(上面已限定区间); 旧数据非法 type 防御性不丢失
        }
    }

    /// "18:30-20:55"(ownTime) 或 "第 3-4 节" 本地化(nodeString(context))
    /// Android 两变体 nodeString/shortNodeString 合并:isShort 切换 course_node_format / course_period_range
    func nodeString(isShort: Bool = false) -> String {
        if ownTime && Self.isNotBlank(startTime) && Self.isNotBlank(endTime) {
            return "\(startTime)-\(endTime)"
        }
        let range = "\(startNode)-\(startNode + step - 1)"
        return isShort
            ? L10n.format("course_period_range", startNode, startNode + step - 1)
            : L10n.format("course_node_format", range)
    }

    /// 渲染前归一化：ownTime=true 的课根据时间表反算等效 startNode/step，
    /// 使其在网格中正确定位。ownTime=false 的课原样返回。
    func normalizeNode(timeJson: String) -> CourseEntity {
        // issue#23: 边缘槽位卡的网格位置 = 槽位编号本身, 禁止按时间重映射
        if isIrregularNode { return self }
        if !ownTime || !Self.isNotBlank(startTime) || !Self.isNotBlank(endTime) { return self }
        guard let mapped = TimeTableUtils.timeToNode(startTime, endTime, timeJson) else { return self }
        var copy = self
        copy.startNode = mapped.0
        copy.step = mapped.1
        return copy
    }
}
