// WidgetCourseCard.swift — ← WidgetBitmapRenderers.kt drawCourse
// 课程胶囊卡(Today/TwoDay 列表用):统一取色 + 亮度自适应文字色 + 名称截断。
// Canvas 手绘 → SwiftUI 等价布局:pad 3dp / 圆角 8dp / 名称 BOLD + meta 逐行垂直居中。

import SwiftUI

struct WidgetCourseCard: View {
    let course: CourseEntity
    let timeJson: String
    let scheme: WidgetScheme
    let colorless: Bool
    var fontSizeSp: CGFloat = 12
    var displayMode: String = "node"

    var body: some View {
        // 统一取色入口 (决策 D3) — colorless 灰底传 surfaceVariant
        let bgColor = CourseColorUtil.pickCourseColorSwiftUI(course, isDark: scheme.isDark,
                                                             neutralColor: scheme.surfaceVariant,
                                                             colorless: colorless)
        // 文字色亮度自适应 (决策 D5-13) — 深色自定义课色上切白字, 浅色底仍 onSurface
        let textColor = CourseColorUtil.textColorOn(bg: bgColor, isDark: scheme.isDark,
                                                    onSurface: scheme.onSurface)
        let timeStr = timeString
        let meta = course.room.isEmpty ? timeStr : "\(timeStr) · \(course.room)"

        VStack(alignment: .leading, spacing: 2) {
            Text(displayName)
                .font(.system(size: fontSizeSp, weight: .bold))
                .lineLimit(1)
            if !meta.isEmpty {
                Text(meta)
                    .font(.system(size: fontSizeSp - 2))
                    .lineLimit(1)
            }
        }
        .foregroundColor(textColor)
        .padding(.horizontal, 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(bgColor)
        .cornerRadius(8)
    }

    // ★ displayMode (决策 D5-12, 对齐 CourseTableView.LessonRow):
    //   "time" → 具体时间段 "08:00-09:35"; "node"(默认) → 节次 "3-4节"
    private var timeString: String {
        if displayMode == "time" && !timeJson.isEmpty {
            let t = TimeTableUtils.courseTimeString(
                courseStartNode: course.startNode,
                courseStep: course.step,
                timeJson: timeJson,
                ownTime: course.ownTime,
                startTime: course.startTime,
                endTime: course.endTime)
            if let t = t { return t }
        }
        return course.nodeString(isShort: true)
    }

    // Android: measureText 超 maxWidth → 逐字截断加 "…"(SwiftUI lineLimit(1) 等价)
    private var displayName: String { course.courseName }
}
