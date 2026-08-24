// JwParser.swift — ← JwParser.kt
// 教务系统 HTML 解析器抽象基类。
//
// 设计来自 dIT8Zv/WakeupSchedule_BUPT (Apache-2.0) 的 Parser.kt
// (https://github.com/dIT8Zv/WakeupSchedule_BUPT/blob/master/app/src/main/java/com/suda/yzune/wakeupschedule/schedule_import/parser/Parser.kt)
//
// 简化点:
//   - 去掉了 saveCourse / convertCourse 中对 wakeup 私有 bean 的依赖
//   - 改成直接输出 [JwCourse],由 JwImportViewModel 统一转 CourseEntity
//   - 去掉了 Context 依赖(颜色生成等放到 ViewModel 层)
//
// 用法:
//   let courses = JwQzCrazyParser(html).generateCourseList()

/// Kotlin `abstract class` + open `source` 属性 → Swift 无抽象类,
/// 用 protocol + 泛型工厂保持同构(每个子类仍是 final class,持 source)。
protocol JwParser {
    var source: String { get }

    /// 解析教务 HTML 源码,输出统一结构的课程列表
    func generateCourseList() -> [JwCourse]
}
