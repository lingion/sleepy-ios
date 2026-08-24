// JwCourse.swift — ← JwCourse.kt
// 解析中间结构:教务系统 HTML 解析后的一条课程记录
//
// 此结构是 wakeup (Apache-2.0) `Course` 数据类的精简复刻。
// 字段名/语义与 wakeup 原版保持一致,方便直接喂给 JwParser 的子类
// (如 JwQzParser / JwQzCrazyParser)。
//
// 后续通过 JwImportViewModel.toCourseEntities 转成 CourseEntity

struct JwCourse: Equatable {
    let name: String
    var room: String = ""
    var teacher: String = ""
    let day: Int
    let startNode: Int
    let endNode: Int
    let startWeek: Int
    let endWeek: Int
    var type: Int = 0  // 0=每周 1=单周 2=双周
}
