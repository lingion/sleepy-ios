// WatchSyncSnapshot.swift — sleepy-watch-sync v2 契约 (2026-10 watch 伴侣 App)
// iPhone → Apple Watch 全量镜像快照: 序列化/反序列化 + 落地重建 单点收敛于此,
// 三端编同一份文件 (iPhone: WatchSyncCoordinator 组装发送;
//  Watch App: WatchSyncReceiver 收到即 apply;
//  Watch Extension: WatchComplicationStore 收到即 apply — 杜绝契约漂移)。
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
    /// 载荷字典格式键 — applicationContext["format"] 契约判别。
    /// 两端 (含未来 Extension) 编同一份文件 → 字符串天然同步; 上架后若需
    /// 新旧 App 共存, 在此键演进 (v1 未发布过, 无历史载荷兼容负担)。
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
        /// 手表「已同步」回执落 iPhone 的 epoch ms (0=从未) — 回执 ack 驱动:
        /// 手表→iPhone context["watchAck"] → Coordinator 存 AppPrefs →
        /// capture 镜像回手表。单源单向, 手表不写本地键 (零独有开关纪律)。
        var ackSentAt: Int64 = 0
        // 外观随快照下发: 手表 UserDefaults 与手机不互通, 不镜像则手表恒默认主题
        var themeKey: String = "default"
        var themeMode: String = "system"

        // ===== v2 功能对齐镜像 (2026-10-27 用户定调: 手表无独有功能, iOS 全部
        // 显示口径以镜像值生效; 键名/缺省语义与 AppPrefs 逐一对齐) =====
        var classDndEnabled: Bool = false
        // fluid 仅镜像开关供设置页只读展示 — iOS 无 NotificationChannelFluid 运行时
        // 载体 ( CHANNEL_FLUID 仅 id 常量), fields/primary 无消费者, 不镜像。
        var beforeClassFluidEnabled: Bool = false
        var language: String = "zh"
        // 课表显示 (手表语义映射, 见各视图): timeMode←display_mode; listAlias←
        // week_use_alias (周/清单页); gridAlias←grid_use_alias (网格行页);
        // showDate←show_date; visibleDays←"1,2,3,4,5,6,7" CSV; neutralColor←course_colorless
        var timeMode: String = "time"
        var listAlias: Bool = false
        var gridAlias: Bool = false
        var showDate: Bool = true
        var visibleDays: String = "1,2,3,4,5,6,7"
        var neutralColor: Bool = false
        // 「今天无课自动跳最近有课日」— WidgetWeekDataLoader.resolve 的 enabled 入参,
        // 手表今日页走同源 loader 必镜像 (缺则手表恒不跳日, 与手机行为分裂)
        var nearestBusyDay: Bool = false
        // 节假日灰显: 开关×3 + 样式; overridesJson←KEY_HOLIDAY_OVERRIDES 原串
        var greyHoliday: Bool = true
        var greyWeekend: Bool = true
        var holidayStyle: String = "grey"
        var ignoreWorkday: Bool = true
        var overridesJson: String = "[]"
        // HolidayManager 年度缓存 (UserDefaults 原串, {date,name,type}[]; loaded 标记并入)
        var holidayYears: [Int: String] = [:]
        // 每表调休映射 (AppPrefs KEY holiday_transfer_{tableId} 语义;
        // HolidayTransferEntry 非 Codable → 值存 HolidayTransferOps JSON 原串)
        var transfers: [Int64: String] = [:]
        // 冲突默认置顶: iOS 内存真相源 ConflictDefaultTopStore (按表存储但 UI 无表参,
        // AppPrefs 实况), 全局镜像
        var conflictDefaultTop: [String: Int64] = [:]
        var autoHideEvening: Bool = false
        var eveningStart: String = "18:00"   // KEY_GRID_EVENING_START "HH:mm" 原串
        // ===== 课程配色派生档 (2026-10 B1 对齐) =====
        // 0=CLASSIC(纯 stableHue) 1=FOLLOW_THEME(跟主题) 2=CUSTOM(种子色)
        var courseColorMode: Int = 0
        // CUSTOM 档种子色相 0..360 (未设 = -1)
        var courseColorSeedHue: Float = -1
        // 可选以兼容尚未携带此字段的 iPhone; 缺失在使用侧按 false 处理。
        var timeStripTomorrow: Bool? = nil
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
        // course_colors 镜像: groupId → hue (派生档持久色相)
        // 原版本 WatchSync 契约无对应字段(手表不镜像配色) — iOS 手表端按
        // 「无独有功能, 手机口径镜像」原则补齐, 手表课程色与手机一致。
        var courseColors: [String: Float] = [:]
    }

    // MARK: - WCSession 消息/载荷键 (两端契约单点)

    /// 手表 → iPhone: 冷启动补拉全量 (sendMessage)
    static let keyRequestContents = "requestContents"
    /// iPhone → 手表 context 载荷键: 快照 JSON
    static let keySyncPayload = "sync"
    /// 手表 → iPhone context 载荷键: 已应用回执 (value = 已应用快照 sentAt)。
    /// 走 updateApplicationContext = 「最近意图」语义: 手表离线时代系统代存,
    /// iPhone 上线自动消费 — 免队列、免逐条投递确认 (transferUserInfo 无 per-item
    /// 送达回调, 多条回执对消费端反而多余)。
    static let keyAckPayload = "watchAck"

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
            ackSentAt: prefs.getWatchAckSentAt(),
            themeKey: prefs.getThemeKey(),
            themeMode: prefs.getThemeMode(),
            // ===== v2 显示口径镜像 (getter 名与缺省语义逐一对应 AppPrefs) =====
            classDndEnabled: prefs.isClassDndEnabled(),
            beforeClassFluidEnabled: prefs.isBeforeClassFluidEnabled(),
            language: prefs.getLanguage(),
            timeMode: prefs.getDisplayMode(),
            listAlias: prefs.isWeekUseAlias(),
            gridAlias: prefs.isGridUseAlias(),
            showDate: prefs.isShowDate(),
            visibleDays: prefs.getVisibleDays().sorted().map(String.init).joined(separator: ","),
            neutralColor: prefs.isCourseColorless(),
            nearestBusyDay: prefs.isNearestBusyDay(),
            greyHoliday: prefs.isHolidayGreyHoliday(),
            greyWeekend: prefs.isHolidayGreyWeekend(),
            holidayStyle: prefs.getHolidayStyle(),
            ignoreWorkday: prefs.isHolidayIgnoreWorkday(),
            overridesJson: HolidayRangeOps.encodeOverrides(prefs.getHolidayRanges()),
            holidayYears: Self.captureHolidayYears(tables: body.timeTables),
            transfers: Self.captureTransfers(tables: body.timeTables),
            conflictDefaultTop: prefs.getConflictDefaultTop(),
            autoHideEvening: prefs.isGridAutoHideEmptyEvening(),
            eveningStart: prefs.getGridEveningStart(),
            courseColorMode: prefs.getCourseColorMode(),
            courseColorSeedHue: prefs.getCourseColorSeedHue(),
            timeStripTomorrow: prefs.isWatchTimeStripTomorrow())
        // course_colors 表仅派生档有值; CLASSIC 档恒空(渲染零变化)。
        let mode = prefs.getCourseColorMode()
        if mode != AppPrefs.COURSE_COLOR_MODE_CLASSIC {
            let dao = repo.database.courseColorDao
            body.courseColors = (try? dao.getHueMap(CourseColorEntity.globalTableKey)) ?? [:]
        }
        return body
    }

    /// HolidayManager 年度磁盘缓存原串 — 仅收磁盘有数据且落在学期区间 (或当前年)
    /// 的年: startDate..学期末 跨年时两端年各收一次, 不硬塞全学期逐年 (20 周只
    /// 跨年 1 次); 当前年恒收 (00:05 重同步的今年数据必镜像)。
    private static func captureHolidayYears(tables: [TimeTableEntity]) -> [Int: String] {
        let cal = Calendar(identifier: .gregorian)
        var years: Set<Int> = [cal.component(.year, from: Date())]
        for t in tables {
            guard let start = DateUtils.parseDate(t.startDate) else { continue }
            let end = cal.date(byAdding: .day, value: max(t.maxWeek, 1) * 7, to: start) ?? start
            years.insert(cal.component(.year, from: start))
            years.insert(cal.component(.year, from: end))
        }
        return HolidayManager.collectDiskYears(years)
    }

    /// 每表调休映射 JSON 原串 (走 HolidayTransferOps 编解码, 与 AppPrefs 私有
    /// transferKey 存储同格式)。
    private static func captureTransfers(tables: [TimeTableEntity]) -> [Int64: String] {
        var out: [Int64: String] = [:]
        for t in tables {
            let list = AppPrefs.shared.getHolidayTransfers(t.id)
            if !list.isEmpty { out[t.id] = HolidayTransferOps.encodeTransfers(list) }
        }
        return out
    }

    // MARK: - 序列化 / 反序列化 (三端共编)

    /// → applicationContext 载荷字典; 失败返回空字典 (调用方判 format 缺失)
    static func encodeToApplicationContext(_ body: Body) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(body),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return ["format": FORMAT, keySyncPayload: json]
    }

    /// ← applicationContext 载荷; 非法/缺 sync 键/版本与格式不符 → nil。
    /// 兼容策略: v1 载荷 (旧 iPhone) 判 FORMAT 即拒 — 半读旧结构必错语义,
    /// 宁显示空态 (手表端提示「请在 iPhone 更新 Sleepy」由 UI 兜底)。
    static func decode(from applicationContext: [String: Any]) -> Body? {
        guard applicationContext["format"] as? String == FORMAT,
              let sync = applicationContext[keySyncPayload] as? [String: Any],
              let data = try? JSONSerialization.data(withJSONObject: sync),
              let body = try? JSONDecoder().decode(Body.self, from: data),
              body.version == Body.VERSION
        else { return nil }
        return body
    }

    // MARK: - 落地重建 (手表侧: App 与 Extension 共走)

    /// prefs 快照 → 手表本地 UserDefaults (AppPrefs 键名同源; 镜像只读不回写手机)。
    /// 走 setter 显式写 (sp().set), 缺省字段也写死当前值 — 全量载荷无"保留旧值"语义。
    static func applyPrefs(_ snapshot: PrefsSnapshot?) {
        guard let snapshot = snapshot else { return }
        // 先写共享快照: 下方 setNearestBusyDay 也会触发 timeline reload,
        // WatchStore 的最终 reload 同样必须读到完整的新选项/语言/映射。
        WatchTimeStripPreferencesStore.shared.apply(snapshot)
        let prefs = AppPrefs.shared
        prefs.setWatchTimeStripTomorrow(snapshot.timeStripTomorrow ?? false)
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
        // ===== v2 显示口径镜像 =====
        prefs.setClassDndEnabled(snapshot.classDndEnabled)
        prefs.setBeforeClassFluidEnabled(snapshot.beforeClassFluidEnabled)
        prefs.setLanguage(snapshot.language)
        prefs.setDisplayMode(snapshot.timeMode)
        prefs.setWeekUseAlias(snapshot.listAlias)
        prefs.setGridUseAlias(snapshot.gridAlias)
        prefs.setShowDate(snapshot.showDate)
        prefs.setVisibleDays(Set(snapshot.visibleDays.split(separator: ",").compactMap { Int($0) }))
        prefs.setCourseColorless(snapshot.neutralColor)
        prefs.setNearestBusyDay(snapshot.nearestBusyDay)
        prefs.setHolidayGreyHoliday(snapshot.greyHoliday)
        prefs.setHolidayGreyWeekend(snapshot.greyWeekend)
        // setHolidayStyle 有 precondition(grey|strikethrough) — 非法串(旧版/篡改)
        // 会崩手表, 校验后才落
        if snapshot.holidayStyle == "grey" || snapshot.holidayStyle == "strikethrough" {
            prefs.setHolidayStyle(snapshot.holidayStyle)
        }
        prefs.setHolidayIgnoreWorkday(snapshot.ignoreWorkday)
        prefs.setHolidayRanges(HolidayRangeOps.decodeOverrides(snapshot.overridesJson))
        // 年度节假日缓存全量覆盖 (载荷是唯一真源); HolidayManager 缓存读写均在
        // 私有锁内且每次现读 UserDefaults → 落盘后其读取自然命中镜像年。
        HolidayManager.replaceDiskYears(snapshot.holidayYears)
        // 调休映射逐表落 (镜像表集合外无读取方, 残键无害)
        for (tableId, json) in snapshot.transfers {
            prefs.setHolidayTransfers(tableId, HolidayTransferOps.decodeTransfers(json))
        }
        // 冲突默认置顶内存真相源 (手表 UI 直读)
        ConflictDefaultTopStore.shared.prime(snapshot.conflictDefaultTop)
        prefs.setGridAutoHideEmptyEvening(snapshot.autoHideEvening)
        prefs.setGridEveningStart(snapshot.eveningStart)
        prefs.setCourseColorMode(snapshot.courseColorMode)
        prefs.setCourseColorSeedHue(snapshot.courseColorSeedHue)
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
            // course_colors 镜像重建 (派生档持久色相): 载荷是唯一真源 → 全量替换。
            try writDB.execute(sql: "DELETE FROM course_colors")
            for (gid, hue) in body.courseColors {
                var row = CourseColorEntity(tableKey: CourseColorEntity.globalTableKey,
                                            groupId: gid, hue: hue)
                try row.insert(writDB, onConflict: .replace)
            }
        }
    }
}
