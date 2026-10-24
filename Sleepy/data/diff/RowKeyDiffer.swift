// RowKeyDiffer.swift — ← data/diff/{RowKey.kt, DiffResult.kt, RowKeyDiffer.kt} 1:1 翻译 (GPL-3.0)
// 三类合一文件(项目按目录 glob 编译, 不强求 Android 的三文件拆分)。

import Foundation

/// 行身份键 — 区分"是不是同一行"的最小集合 (issue#22)。
///
/// 设计原则:
///   room/teacher 进 key — 同名课程在不同地点/不同老师上课视为不同行
///   colorMode/color/note 不进 key — 改字段不视为新行(编辑器改颜色应原地 update, 不能删+插)
struct RowKey: Hashable {
    let day: Int
    let startNode: Int
    let step: Int
    let startWeek: Int
    let endWeek: Int
    let type: Int
    let room: String
    let teacher: String

    static func of(_ c: CourseEntity) -> RowKey {
        RowKey(day: c.day, startNode: c.startNode, step: c.step,
               startWeek: c.startWeek, endWeek: c.endWeek, type: c.type,
               room: c.room, teacher: c.teacher)
    }
}

/// 行级 diff 结果 — 落到数据库的三类操作。
///
/// 替代旧 `replaceGroup(tableId, groupId, newCourses)` 整组覆盖模式;
/// editor 保存时把"现况"和"草稿"喂给 RowKeyDiffer.diff 即可。
struct DiffResult {
    /// 新行(id=0 让 GRDB 自增; 若携带非零 id 走 REPLACE 覆盖)
    let toInsert: [CourseEntity]
    /// 字段变动但 RowKey 不变(包含 server 原 id, 落库按 id 覆盖)
    let toUpdate: [CourseEntity]
    /// 被删行的 server id
    let toDelete: [Int64]
}

/// 行级 diff/patch — 编辑器保存路径核心 (issue#22 同名多地点)。
///
/// 算法:
///   1. 按 groupId 分桶(server / draft 双侧)
///   2. 每桶内用 RowKey 比对
///      - draft 有 server 匹配 → update(保留 server 的 id)
///      - draft 无 server 匹配 → insert(id=0 自增)
///      - server 无 draft 匹配 → delete(server.id)
///   3. groupId="" 走兜底(契约一保护): draft 全 insert, server 全 delete
///
/// 替代 CourseDao.replaceGroup 的整组覆盖模式 —
/// 旧模式会丢数据(同名课多地点编辑一处带崩全局)
enum RowKeyDiffer {
    static func diff(_ drafts: [CourseEntity], _ server: [CourseEntity]) -> DiffResult {
        var inserts: [CourseEntity] = []
        var updates: [CourseEntity] = []
        var deletes: [Int64] = []

        // 按 groupId 分桶
        let serverByGroup = Dictionary(grouping: server) { $0.groupId }
        let draftByGroup = Dictionary(grouping: drafts) { $0.groupId }

        // Kotlin: serverByGroup.keys + draftByGroup.keys — 保留序去重
        var allGroups: [String] = []
        for gid in serverByGroup.keys where !allGroups.contains(gid) { allGroups.append(gid) }
        for gid in draftByGroup.keys where !allGroups.contains(gid) { allGroups.append(gid) }

        for gid in allGroups {
            if gid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // 旧 groupId="" 兜底(契约一保护): 整组 insert
                let s = serverByGroup[gid] ?? []
                let d = draftByGroup[gid] ?? []
                inserts += d.map { c in var c = c; c.id = 0; return c }
                deletes += s.map { $0.id }
                continue
            }

            let s = serverByGroup[gid] ?? []
            let d = draftByGroup[gid] ?? []

            // Kotlin associateBy 文档语义: 同键多行保留【最后一条】(last-wins)。
            // 旧代码 { a, _ in a } 保留第一条 → 同组内 RowKey 全同但 note/credit/alias
            // 不同的两行, 两端 update/delete 结果不一致 (对齐 1.0.61 修正)。
            let sKeyToCourse = Dictionary(s.map { (RowKey.of($0), $0) },
                                          uniquingKeysWith: { _, b in b })
            let dKeyToCourse = Dictionary(d.map { (RowKey.of($0), $0) },
                                          uniquingKeysWith: { _, b in b })

            for (key, draftCourse) in dKeyToCourse {
                if let serverCourse = sKeyToCourse[key] {
                    if fieldsDiffer(serverCourse, draftCourse) {
                        var c = draftCourse
                        c.id = serverCourse.id
                        updates.append(c)
                    }
                    // else: 完全相同 → 跳过
                } else {
                    var c = draftCourse
                    c.id = 0
                    inserts.append(c)
                }
            }
            for (key, serverCourse) in sKeyToCourse where dKeyToCourse[key] == nil {
                deletes.append(serverCourse.id)
            }
        }

        return DiffResult(toInsert: inserts, toUpdate: updates, toDelete: deletes)
    }

    /// 比较除 id/groupId/RowKey 包含字段外的其他字段是否相同
    private static func fieldsDiffer(_ a: CourseEntity, _ b: CourseEntity) -> Bool {
        if a.courseName != b.courseName { return true }
        // 用户报障 2026-09-11: 别名无法保存 — RowKey 不含 alias(展示名非身份)但 fieldsDiffer 必须含。
        // 漏掉一行 → diff 判"完全相同"跳过 update, 旧 alias 永远进不去。
        if a.alias != b.alias { return true }
        if a.note != b.note { return true }
        if a.color != b.color { return true }
        if a.colorMode != b.colorMode { return true }
        if a.ownTime != b.ownTime { return true }
        if a.startTime != b.startTime { return true }
        if a.endTime != b.endTime { return true }
        if a.credit != b.credit { return true }
        if a.level != b.level { return true }
        if a.tableId != b.tableId { return true }
        return false
    }
}
