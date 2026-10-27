// WatchSyncSnapshot.swift — sleep-watch-sync-v1 契约 (2026-10 watch 伴侣 App)
// iPhone → Apple Watch 全量镜像快照: 序列化/反序列化 + 落地重建 单点收敛于此,
// 两端编同一份文件 (iPhone: WatchSyncCoordinator 组装发送;
//  Watch: WatchSyncReceiver 收到即 apply), 杜绝双端契约漂移。
//
// 形态: JSON (entities 直 Codable, id 原样保留 — 手表通知 id 由 courseId 派生,
// 跨端一致)。不走 sleepy-v1 文本(会丢 id/periodTableId/reminderEnabled,
// 且作息重建复杂)。载荷走 WCSession applicationContext (上限 256KB;
// 全校课表 JSON 实测几十 KB, 超限由发送端截断并记日志)。
//
// 语义: 载荷是唯一真源 — apply 全量重建镜像库 (三表清空后显式 id 直插),
// 幂等; 无增量/diff。prefs 快照落手表本地 UserDefaults (AppPrefs 同键名),
// 使共享 NotificationScheduler 的「到货重查三闸」语义在手表侧原样成立。

import Foundation

enum WatchSyncSnapshot {
    /// 载荷字典格式键 — applicationContext["format"] 契约判别
    static let FORMAT = "sleepy-watch-sync-v1"

    struct PrefsSnapshot: Codable {
        // 默认值与 AppPrefs 各 getter 的 nil-缺省语义逐项对齐 (手表首装无键时行为一致)
        var reminderMaster: Bool = false
        var dailyEnabled: Bool = true
        var dailyTime: String = "07:00"
        var todayReminder: Bool = true
        var tomorrowReminder: Bool = false
        var tomorrowTime: String = "22:00"
        var beforeClassEnabled: Bool = false
        var beforeClassMinutes: Int = 10
        var beforeClassBanner: Bool = true
        // 外观随快照下发: 手表 UserDefaults 与手机不互通, 不镜像则手表恒默认主题
        var themeKey: String = "default"
        var themeMode: String = "system"
    }

    struct Body: Codable {
        static let VERSION = 1
        var version: Int = VERSION
        /// 发送端生成 (epoch ms) — 手表 UI 显示「上次同步」+ 幂等去重 (旧载荷丢弃)
        var sentAt: Int64 = 0
        var periodTables: [PeriodTableEntity] = []
        var timeTables: [TimeTableEntity] = []
        var courses: [CourseEntity] = []
        var prefs: PrefsSnapshot? = nil
    }

    /// 主键: "sync" = JSON body; 消息键契约
    static let keyRequestContents = "requestContents"

    // MARK: - 组装 (iPhone 侧)

    /// 从当前库读三表 + AppPrefs 组快照。courseDao.getAllCourses() 已按表遍历,
    /// 直接取全量 (镜像保 id 全局唯一语义, courseId 通知 id 跨端稳定)。
    static func capture(repo: ScheduleRepository) -> Body {
        var body = Body()
        body.sentAt = Int64(Date().timeIntervalSince1970 * 1000)
        body.periodTables = (try? repo.getAllPeriodTables()) ?? []
        body.timeTables = (try? repo.getAllTables()) ?? []
        body.courses = (try? repo.getAllCourses()) ?? []
        let prefs = AppPrefs.shared
        body.prefs = PrefsSnapshot(
            reminderMaster: prefs.isReminderEnabled(),
            dailyEnabled: prefs.isDailyReminderEnabled(),
            dailyTime: prefs.getDailyReminderTime(),
            todayReminder: prefs.isTodayReminderEnabled(),
            tomorrowReminder: prefs.isTomorrowReminderEnabled(),
            tomorrowTime: prefs.getTomorrowReminderTime(),
            beforeClassEnabled: prefs.isBeforeClassEnabled(),
            beforeClassMinutes: prefs.getBeforeClassMinutes(),
            beforeClassBanner: prefs.isBeforeClassBannerEnabled(),
            themeKey: prefs.getThemeKey(),
            themeMode: prefs.getThemeMode())
        return body
    }

    // MARK: - 序列化 / 反序列化 (两端)

    /// → applicationContext 载荷字典; 失败返回空字典 (调用方判 format 缺失)
    static func encodeToApplicationContext(_ body: Body) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(body),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return ["format": FORMAT, "sync": json]
    }

    /// ← applicationContext 载荷; 非法/缺 sync 键 → nil。兼容: 只认 "sync" 一个键,
    /// 其余键 (旧版 "tables" 文本形态等) 一律拒绝并让调用方清旧上下文, 不做静默降级。
    static func decode(from applicationContext: [String: Any]) -> Body? {
        guard applicationContext["format"] as? String == FORMAT,
              let sync = applicationContext["sync"] as? [String: Any],
              let data = try? JSONSerialization.data(withJSONObject: sync),
              let body = try? JSONDecoder().decode(Body.self, from: data),
              body.version == Body.VERSION
        else { return nil }
        return body
    }

    // MARK: - 落地重建 (手表侧)

    /// prefs 快照 → 手表本地 UserDefaults (AppPrefs 键名同源; 镜像只读不回写手机)。
    /// 走 setter 显式写 (sp().set), 缺省字段也写死当前值 — 全量载荷无"保留旧值"语义。
    static func applyPrefs(_ snapshot: PrefsSnapshot?) {
        guard let snapshot = snapshot else { return }
        let prefs = AppPrefs.shared
        prefs.setReminderEnabled(snapshot.reminderMaster)
        prefs.setDailyReminderEnabled(snapshot.dailyEnabled)
        prefs.setDailyReminderTime(snapshot.dailyTime)
        prefs.setTodayReminderEnabled(snapshot.todayReminder)
        prefs.setTomorrowReminderEnabled(snapshot.tomorrowReminder)
        prefs.setTomorrowReminderTime(snapshot.tomorrowTime)
        prefs.setBeforeClassEnabled(snapshot.beforeClassEnabled)
        prefs.setBeforeClassMinutes(snapshot.beforeClassMinutes)
        prefs.setBeforeClassBannerEnabled(snapshot.beforeClassBanner)
        prefs.setThemeKey(snapshot.themeKey)
        prefs.setThemeMode(snapshot.themeMode)
    }

    /// 全量重建镜像库: 三表清空 → 显式 id 直插 (FK CASCADE 已建,
    /// 删除顺序 courses→time_tables→period_tables 事务内一次完成)。
    /// 单事务: 中途失败整体回滚, 手表保留上一份镜像 (通知调度读旧库仍自洽)。
    /// id 保留: 三实体 encode(to:) 均「id==0 → nil 走自增 / 非 0 → 原样落列」
    /// (Room autoGenerate 语义, GRDB 注释见各实体), 镜像实体 id 恒非 0,
    /// dao.insertInDb(onConflict: .replace) 直接按提供 id 落 rowid。
    static func apply(db: AppDatabase, body: Body) throws {
        try db.dbQueue.write { writDB in
            try writDB.execute(sql: "DELETE FROM courses")
            try writDB.execute(sql: "DELETE FROM time_tables")
            try writDB.execute(sql: "DELETE FROM period_tables")
            for pt in body.periodTables {
                try db.periodTableDao.insertInDb(writDB, pt)
            }
            for t in body.timeTables {
                try db.timeTableDao.insertInDb(writDB, t)
            }
            for c in body.courses {
                try db.courseDao.insertInDb(writDB, c)
            }
        }
    }
}
