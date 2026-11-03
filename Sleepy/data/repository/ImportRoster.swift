// ImportRoster.swift — ← data/repository/NewTableImport.kt (v1.0.62, GPL-3.0)
// 导入「认亲」名册 — 同名课程继承旧 groupId, 从而继承旧持久色相。
//
// 身份键 importNameKey(原版本 同名函数): 课程名 trim + 连续空白折叠为单空格 + 小写。
// 认亲优先级(原 normalizedImportGroups 逐条对齐):
//   ① 全局名册 knownNameToGroup[key]  ← 最高优先(同名的历史课程)
//   ② 该行自带的非空 groupId          ← sleepy-v1 token 分区权威值
//   ③ 新 UUID
//
// 名册构建 knownNameToGroupId(原版本 同名函数): LinkedHashMap + putIfAbsent
// (先到先得), 跳过 groupId 空白行, 跳过空键。调用方需按 id 升序喂入保证确定性。
//
// 注: 本文件位于 data/repository/ → 同时编译进 Widget / Watch 目标,
// 因此不得引用任何 app 专属 API。

import Foundation

enum ImportRoster {

    /// 身份键 — trim + 空白折叠 + 小写(原 importNameKey 逐字对齐)
    static func importNameKey(_ courseName: String) -> String {
        let trimmed = courseName.trimmingCharacters(in: .whitespacesAndNewlines)
        let collapsed = trimmed.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return collapsed.lowercased()
    }

    /// 全局名册: 课程名身份键 → groupId(先到先得)
    static func knownNameToGroupId(_ existingRows: [CourseEntity]) -> [String: String] {
        var map: [String: String] = [:]
        map.reserveCapacity(existingRows.count)
        for row in existingRows {
            if row.groupId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            let key = importNameKey(row.courseName)
            if key.isEmpty { continue }
            if map[key] == nil { map[key] = row.groupId }
        }
        return map
    }

    /// 按认亲优先级重写每行 groupId(原版本 normalizedImportGroups)
    static func normalizedImportGroups(_ courses: [CourseEntity],
                                       knownNameToGroup: [String: String] = [:]) -> [CourseEntity] {
        var nameToGroupId: [String: String] = [:]
        var out: [CourseEntity] = []
        out.reserveCapacity(courses.count)
        for c in courses {
            let key = importNameKey(c.courseName)
            let gid: String
            if let hit = nameToGroupId[key] {
                gid = hit
            } else {
                let own = c.groupId.trimmingCharacters(in: .whitespacesAndNewlines)
                let chosen = knownNameToGroup[key]
                    ?? (own.isEmpty ? nil : own)
                    ?? UUID().uuidString
                nameToGroupId[key] = chosen
                gid = chosen
            }
            var copy = c
            copy.groupId = gid
            out.append(copy)
        }
        return out
    }
}
