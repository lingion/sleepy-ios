import SwiftUI

/// 真实课程预览保留完整行与同表组成员，复用课表的 CUSTOM/AUTO/GROUP 取色顺序。
struct CourseColorPreview: Identifiable {
    let course: CourseEntity
    let groupRows: [CourseEntity]
    var id: Int64 { course.id }
    var name: String { course.alias.isEmpty ? course.courseName : course.alias }

    static func groups(from courses: [CourseEntity]) -> [CourseColorPreview] {
        struct Key: Hashable {
            let tableId: Int64
            let groupId: String
        }
        let grouped = Dictionary(grouping: courses) { Key(tableId: $0.tableId, groupId: $0.groupId) }
        var seen: Set<Key> = []
        return courses.filter { seen.insert(Key(tableId: $0.tableId, groupId: $0.groupId)).inserted }
            .prefix(5).map { course in
                CourseColorPreview(course: course,
                    groupRows: grouped[Key(tableId: course.tableId, groupId: course.groupId)] ?? [course])
            }
    }

    func color(isDark: Bool, neutral: Color, colorless: Bool, persistedHue: Float?) -> Color {
        CourseColorUtil.pickCourseColorSwiftUIWithGroupRows(
            course, groupRows: groupRows, isDark: isDark, neutralColor: neutral,
            colorless: colorless, persistedHue: persistedHue)
    }
}
