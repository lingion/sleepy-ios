// SleepyUITestSeeder.swift — G5+ 全交互面测试的数据种子
// XCUITest 走 UI 无法直接建库;启动参数 -SLEEPY_UI_TEST_SEED 触发:
//   清空两表 → 建"我的课表"(本周一~五, 本周=第1周) + 4 门课 → 默认表。
// 种子数据确定性: 固定 startDate 使 currentWeek==1, 课程全落第 1 周。

import Foundation

enum SleepyUITestSeeder {
    static func seed(database: AppDatabase) {
        // 语言复位: 语言切换测试会持久化 KEY_LANG/AppleLanguages, 残留会污染
        // 后续依赖系统语言(launch args -AppleLanguages)的用例 → 每次种子清零。
        // (L10n 现在跟随 AppPrefs 保存值 ← Android wrapDefault 语义)
        UserDefaults.standard.removeObject(forKey: "language")
        UserDefaults.standard.removeObject(forKey: "AppleLanguages")

        // 偏好复位(串行套件防污染): 设置页测试会真实写库这些偏好, 残留会改变
        // 后续 suite 的启动形态 —— 实证链: MineSettings 把 Mon 关进 visible_days →
        // 后续 ScheduleFlow 种子课"高等数学"(周一)整列消失; 启动视图被改 "full" →
        // grid 用例起步即在 Week 模式。逐 key 复位到出厂默认(= AppPrefs 各 getter
        // 的 ?? 兜底值), 每个带种子用例拿到的都是干净出厂态。
        let d = AppPrefs.shared.sharedBackedStore
        d.removeObject(forKey: AppPrefs.KEY_VISIBLE_DAYS)   // 出厂 1..7 全显
        d.removeObject(forKey: AppPrefs.KEY_SHOW_DATE)      // 出厂 true
        d.removeObject(forKey: AppPrefs.KEY_START_VIEW)     // 出厂 "cards"(← Android "cards")
        d.removeObject(forKey: AppPrefs.KEY_NAV_DOCK)       // 出厂 false(贴底)
        d.removeObject(forKey: "settings_expanded_sections") // 折叠卡展开集(GeneralSettings 持久化)
        // 竖排标点替换开关(方案B): testGeneralToggles 真实点按 → 持久化; UI 测试
        // terminate 不清容器, 残留经 Xcode14 串行的共享 app 容器渗入 SleepyTests
        // (WidgetLogicTests.testTokenizePunctPlanA / VersionAndUpdateTests 断言出厂
        //  false)→ 套件红。复位到出厂 false 断链。
        d.removeObject(forKey: AppPrefs.KEY_VERT_PUNCT_REPLACE)

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
        // ★ 固定 id 1..4: sleepy://course/N 深链测试需确定性定位(自增 id 跨种子漂移)
        let courses: [(Int64, Int, Int, Int, String, String, String)] = [
            (1, 1, 1, 2, "高等数学", "张老师", "教1-101"),
            (2, 2, 3, 4, "大学英语", "李老师", "外楼202"),
            (3, 3, 5, 6, "大学物理", "王老师", "理楼305"),
            (4, 5, 1, 2, "体育", "赵老师", "操场"),
        ]
        for (id, day, sn, en, name, teacher, room) in courses {
            var c = CourseEntity(
                groupId: UUID().uuidString, tableId: table.id,
                courseName: name, teacher: teacher, room: room,
                day: day, startNode: sn, step: en - sn + 1,
                startWeek: 1, endWeek: 20, type: 0, color: "#FF6750A4")
            c.id = id
            c.note = ""
            _ = try? database.courseDao.insert(c)
        }
    }
}
