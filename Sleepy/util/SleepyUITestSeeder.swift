// SleepyUITestSeeder.swift — G5+ 全交互面测试的数据种子
// XCUITest 走 UI 无法直接建库;启动参数 -SLEEPY_UI_TEST_SEED 触发:
//   清空两表 → 建"我的课表"(本周一~五, 本周=第1周) + 4 门课 → 默认表。
// 种子数据确定性: 固定 startDate 使 currentWeek==1, 课程全落第 1 周。

import Foundation

enum SleepyUITestSeeder {
    static func seed(database: AppDatabase) {
        do {
            try database.dbQueue.write { db in
                try db.execute(sql: "DELETE FROM courses")
                try db.execute(sql: "DELETE FROM time_tables")
            }
        } catch { return }

        // 周一为本周起点(今天回推到本周一, ISO 8601)→ currentWeek==1
        let cal = Calendar(identifier: .iso8601)
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        let monday = cal.date(from: comps)!
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.calendar = cal
        let startDate = fmt.string(from: monday)

        var table = TimeTableEntity(
            name: "我的课表", startDate: startDate, maxWeek: 20,
            nodesPerDay: 12, timeJson: TimeTableUtils.DEFAULT_TIME_JSON,
            color: "#FF6750A4", isDefault: true)
        guard (try? database.timeTableDao.insert(table)).map({ $0 > 0 }) == true else { return }
        table.id = (try? database.timeTableDao.getAll().first?.id) ?? 0
        guard table.id > 0 else { return }

        // 4 门课: 周一1-2 高数 / 周二3-4 英语 / 周三5-6 物理 / 周五1-2 体育
        let courses: [(Int, Int, Int, String, String, String)] = [
            (1, 1, 2, "高等数学", "张老师", "教1-101"),
            (2, 3, 4, "大学英语", "李老师", "外楼202"),
            (3, 5, 6, "大学物理", "王老师", "理楼305"),
            (5, 1, 2, "体育", "赵老师", "操场"),
        ]
        for (day, sn, en, name, teacher, room) in courses {
            var c = CourseEntity(
                groupId: UUID().uuidString, tableId: table.id,
                courseName: name, teacher: teacher, room: room,
                day: day, startNode: sn, step: en - sn + 1,
                startWeek: 1, endWeek: 20, type: 0, color: "#FF6750A4")
            c.note = ""
            _ = try? database.courseDao.insert(c)
        }
    }
}
