// CourseDisplayUtil.swift — ← util/CourseDisplayUtil.kt
// issue#26 课程别名 — 展示名解析。
// 语义: alias 是"展示名", 不改身份。
//   - useAlias=false → 原名 (三场景设置默认值, 升级用户行为不变)
//   - useAlias=true  → trim 后别名; 空串回退原名
// 别名不参与匹配/导出/通知/详情等身份场景 — 那些点直接读 course.courseName。

enum CourseDisplayUtil {
    /// 展示名 = 场景开关开启时取别名(空回退原名), 否则原名
    static func displayName(_ course: CourseEntity, _ useAlias: Bool) -> String {
        guard useAlias else { return course.courseName }
        let trimmed = course.alias.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? course.courseName : trimmed
    }

    /// 便捷重载: 逐课独立判断 — 周视图两栏 "balance" 等需要按行混合场景
    /// ← Kotlin `displayName(course, useAliasFor: (CourseEntity) -> Boolean)`
    static func displayName(_ course: CourseEntity, useAliasFor: (CourseEntity) -> Bool) -> String {
        displayName(course, useAliasFor(course))
    }
}
