// AppPrefs.swift — ← AppPrefs.kt
// Android: SharedPreferences + callbackFlow → iOS: UserDefaults + Combine CurrentValueSubject
// 进程内 @Published 同步给 UI,磁盘做持久化(与 Kotlin object 单例语义一致)。

import Foundation
import Combine
import WidgetKit

/// App 级别轻量设置 — 避免引入额外依赖。
final class AppPrefs {
    static let shared = AppPrefs()

    static let FILE = "sleepy_prefs"
    static let KEY_DARK = "dark_mode"
    static let KEY_REMINDER = "reminder_master"      // master toggle (default false)
    static let KEY_DAILY_ENABLED = "daily_reminder"   // daily sub-toggle (default true)
    static let KEY_DAILY_TIME = "daily_reminder_time" // "HH:mm" default "07:00"
    static let KEY_BEFORE_CLASS_ENABLED = "before_class_enabled"       // bool default false
    static let KEY_BEFORE_CLASS_MINUTES = "before_class_minutes"       // int default 10
    static let KEY_BEFORE_CLASS_BANNER = "before_class_banner"         // bool default true
    static let KEY_BEFORE_CLASS_FLUID = "before_class_fluid"            // bool default false
    static let KEY_BEFORE_CLASS_FLUID_FIELDS = "before_class_fluid_fields" // legacy multi-select
    // ← v1.0.60 新增: 次日预告 + 当日提醒 + 上课自动勿扰
    static let KEY_TOMORROW_REMINDER_ENABLED = "tomorrow_reminder"             // bool default false
    static let KEY_TOMORROW_REMINDER_TIME = "tomorrow_reminder_time"           // "HH:mm" default "22:00"
    static let DEFAULT_TOMORROW_REMINDER_ENABLED = false
    static let DEFAULT_TOMORROW_REMINDER_TIME = "22:00"
    static let KEY_TODAY_REMINDER_ENABLED = "today_reminder"                   // bool default true ← KEY_TODAY_REMINDER_ENABLED
    static let DEFAULT_TODAY_REMINDER_ENABLED = true
    static let KEY_CLASS_DND_ENABLED = "class_dnd_enabled"                     // bool default false — 上课自动勿扰
    static let KEY_BEFORE_CLASS_FLUID_PRIMARY = "before_class_fluid_primary" // name/time/room
    static let KEY_THEME = "theme_key"
    static let KEY_LANG = "language"
    static let KEY_DISPLAY_MODE = "display_mode" // "node" or "time"
    static let KEY_START_VIEW = "start_view" // "full" / "cards" — ← AppPrefs.KEY_START_VIEW Android; 启动默认视图（仅通用设置里设置；手动切换课表顶部视图不写入）
    static let KEY_GRID_SUB_INFO = "grid_sub_info" // "room" / "teacher" / "none" — 网格卡片副信息(周视图网格卡课程名下方那行;左栏已有节次,故此处不再显示节次/时间)
    static let KEY_CONFLICT_STYLE = "conflict_style" // "stack"/"fold"/"rail" — 冲突课程显示样式,默认 "rail"(← KEY_CONFLICT_STYLE v7.10.16s)
    static let KEY_CONFLICT_TOP_INSET = "conflict_top_inset" // Double dp — 旧共用收窄量 key: 仅作拆分迁移源,停写(用户 2026-09-04 拆分)
    static let KEY_CONFLICT_STACK_INSET = "conflict_stack_inset" // Double dp — 叠层偏移量(STACK 专有, 用户 2026-09-04 拆分: 两样式独立配置不共享)
    static let KEY_CONFLICT_RAIL_INSET = "conflict_rail_inset"   // Double dp — 右缘让宽(RAIL 专有, 同上)
    static let KEY_CONFLICT_FOLD_SIZE = "conflict_fold_size" // Double dp — 折角幅度(fold 样式): 折痕直角边长, 视觉符号与命中区共用; 默认 16dp
    static let KEY_CONFLICT_DEFAULT_TOP = "conflict_default_top" // JSON {"day:startNode:step": layerRepId} — 冲突簇默认置顶图层
    static let KEY_SHOW_DATE = "show_date"       // boolean
    static let KEY_VISIBLE_DAYS = "visible_days" // "1,2,3,4,5,6,7"
    static let KEY_VERT_PUNCT_REPLACE = "vert_punct_replace" // bool default false (方案B开关)
    static let KEY_PERIOD_HEADER_LAYOUT = "period_header_layout" // "legacy" / "three_line", default legacy
    static let KEY_PERIOD_HEADER_STYLE = "period_header_style" // arabic / chinese / financial / circled / roman, default arabic
    static let KEY_PERIOD_HEADER_HANGING = "period_header_hanging" // Float time-width units, -1..1, default 0
    static let KEY_PERIOD_HEADER_SHOW_X = "period_header_show_x" // boolean default false
    static let KEY_WIDGET_COLORLESS = "widget_colorless" // bool default false
    static let KEY_COURSE_COLORLESS = "course_colorless" // bool default false (App 课程胶囊专用)
    static let KEY_WIDGET_SEPARATOR = "widget_separator" // bool default true (WeekView 纯文字课程间分隔线)
    static let KEY_HOLIDAY_GREY_HOLIDAY = "holiday_grey_holiday" // bool default true
    static let KEY_HOLIDAY_GREY_WEEKEND = "holiday_grey_weekend" // bool default true
    static let KEY_HOLIDAY_STYLE = "holiday_style"          // "grey" / "strikethrough" default "grey"
    static let KEY_HOLIDAY_IGNORE_WORKDAY = "holiday_ignore_workday" // bool default true
    static let KEY_HOLIDAY_OVERRIDES = "holiday_overrides"  // JSON, HolidayRangeOps 编解码
    static let KEY_THEME_MODE = "theme_mode"  // light/dark/system
    static let THEME_MODE_LIGHT = "light"
    static let THEME_MODE_DARK = "dark"
    static let THEME_MODE_SYSTEM = "system"
    // ★ v1.0.45 画面分组: 底栏样式(默认贴底 ← Android b0f8280)
    // (KEY_HIGH_REFRESH 已随 no-op 桩删除 — iOS 无公开刷率 API,2026-09-10 原生化审计)
    static let KEY_NAV_DOCK = "nav_dock"              // bool default false (false=贴底, true=悬浮药丸 ← Android b0f8280)
    // ★ issue#8 主页显示 pill 组: 网格/周视图缩放 + 圆角比例 + 周视图两栏 (← Android AppPrefs.kt 65-72)
    static let KEY_GRID_SCALE = "grid_scale"          // Float 0.7~1.3 default 1.0 — 网格整体缩放(字号/行高/间距/圆角联动)
    static let KEY_WEEK_SCALE = "week_scale"          // Float 0.7~1.3 default 1.0 — 周视图整体缩放
    static let KEY_GRID_CORNER_RATIO = "grid_corner_ratio" // Float 0.0~2.0 default 1.0 — 圆角比例(乘基准圆角)
    static let KEY_WEEK_TWO_COLUMN = "week_two_column" // bool default false — 周视图两栏
    static let KEY_WEEK_TWO_COLUMN_MODE = "week_two_column_mode" // "days"/"balance" default "days"
    static let KEY_WEEK_HIDE_EMPTY_DAYS = "week_hide_empty_days" // bool default false — 隐藏无课日
    static let KEY_WEEK_USE_ALIAS = "week_use_alias"  // bool default false — 周视图显示别名 (issue#26)
    static let KEY_GRID_USE_ALIAS = "grid_use_alias"  // bool default false — 网格视图显示别名 (issue#26)
    static let KEY_WIDGET_USE_ALIAS = "widget_use_alias"  // bool default false — widget 场景显示别名 (issue#26, 全局一档)
    // ★ 实验室开关组(← AppPrefs.kt KEY_GRID_* v1.0.56): CourseTableView.GridLabPrefs 直读
    //   的正式归属地; UserDefaults.standard 与 AppPrefs.shared 默认 suite 同源, 行为等价。
    static let KEY_GRID_AUTO_HIDE_EMPTY_EVENING = "grid_auto_hide_empty_evening" // bool default false — 自动收起无课晚间节次
    static let KEY_GRID_ADAPTIVE_HEIGHT = "grid_adaptive_height" // bool default false — 自适应行高(默认固定 52dp 基座)
    static let KEY_GRID_EVENING_START = "grid_evening_start"     // "HH:mm" default 18:00 — 晚间起始时间(用户自定义)
    static let KEY_GRID_ROW_SCALE = "grid_row_scale"             // Float default 1.0 — 双指行高缩放确认值(相对基座; Android 读侧不钳制)
    static let KEY_GRID_PINCH_ZOOM = "grid_pinch_zoom"           // bool default false — 双指捏放行高(v1.0.56 默认关, 关=手势不挂; 存量缩放值不清)
    static let DEFAULT_GRID_PINCH_ZOOM = false
    static let KEY_GRID_SHOW_SEPARATORS = "grid_show_separators" // bool default false — 网格额外分隔线
    static let DEFAULT_GRID_SHOW_SEPARATORS = false
    static let KEY_GRID_LONG_BREAK_SPACING = "grid_long_break_spacing" // bool default false — 长课间额外留白
    static let DEFAULT_GRID_LONG_BREAK_SPACING = false
    static let KEY_SHOW_VIEW_SWITCHER = "show_view_switcher"     // bool default true — 首页周/网格视图切换栏显隐(GeneralSettingsScreen.LabPrefs 正式归属地)
    // ★ widget v1.0.60 对齐键 (← AppPrefs.kt)
    static let KEY_NEAREST_BUSY_DAY = "nearest_busy_day" // bool default false — 今天没课时自动显示最近一个有课的日子
    static let KEY_COMPACT_WINDOW_TODAY_FIRST = "compact_window_today_first" // bool default true — 最小档三天窗口锚点(2026-09-15 用户令)
    static let KEY_WIDGET_SCROLL_ENABLED = "widget_scroll_enabled" // bool default false — 强制滚动(实验), 默认 FIXED 固定窗口
    static let GRID_SCALE_RANGE: ClosedRange<Double> = 0.7...1.3
    static let CORNER_RATIO_RANGE: ClosedRange<Double> = 0.0...2.0

    /// 主题色 key 的进程内 Flow — ← themeKeyFlow(callbackFlow+distinctUntilChanged)
    /// 订阅即收当前值,变更推送新值,去重。
    private let themeKeySubject = CurrentValueSubject<String, Never>(ThemePresets.KEY_DEFAULT)
    lazy private(set) var themeKeyPublisher: AnyPublisher<String, Never> = themeKeySubject.eraseToAnyPublisher()

    /// 单测注入用:默认 UserDefaults.standard。测试用 suiteName 隔离。
    private let d: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.d = defaults
    }

    private func sp() -> UserDefaults { d }

    /// HolidayManager 磁盘缓存与业务 prefs 共用同一存储(← PREFS_NAME 同文件语义)
    var sharedBackedStore: UserDefaults { d }

    /// 实际是否深色:dark→true, light→false, system→isSystemDark。isSystemDark 由调用方传入。 ← isDarkMode
    func isDarkMode(isSystemDark: Bool = false) -> Bool {
        // 向后兼容:旧 boolean KEY_DARK 在无新三态时生效
        if sp().object(forKey: Self.KEY_THEME_MODE) == nil {
            if let legacy = sp().object(forKey: Self.KEY_DARK) as? Bool {
                return legacy
            }
        }
        switch getThemeMode() {
        case Self.THEME_MODE_DARK: return true
        case Self.THEME_MODE_LIGHT: return false
        default: return isSystemDark
        }
    }

    /// 主题模式:light / dark / system。默认 system。 ← getThemeMode/setThemeMode
    func getThemeMode() -> String {
        sp().string(forKey: Self.KEY_THEME_MODE) ?? Self.THEME_MODE_SYSTEM
    }

    func setThemeMode(_ mode: String) {
        precondition(mode == Self.THEME_MODE_LIGHT || mode == Self.THEME_MODE_DARK || mode == Self.THEME_MODE_SYSTEM)
        sp().set(mode, forKey: Self.KEY_THEME_MODE)
    }

    // ===== 画面 =====

    /// 底栏样式 — false=贴底(默认), true=悬浮药丸(← Android v1.0.45 AppPrefs.KEY_NAV_DOCK 一字对齐)。
    /// API 名沿用 isNavDocked()/setNavDocked(_:) 以保留调用方,但语义已校正:
    /// 传入 true 意味着"是悬浮药丸"(写入 KEY_NAV_DOCK=true),返回 true 同义。
    /// 关键修复(2026-09-08): 早期实现方向反转 → 新装用户看不到悬浮形态。
    func isNavDocked() -> Bool {
        // 反向兼容: 旧版本以「false=悬浮」存值。新版本「true=悬浮」,
        // 因此首读时一旦读到旧值 false 还要再判一次是否从未写入过。
        guard sp().object(forKey: Self.KEY_NAV_DOCK) != nil else { return false }
        return sp().bool(forKey: Self.KEY_NAV_DOCK)
    }

    /// 用户是否显式选过底栏样式(2026-10-26 设备自适应改造)。
    /// 未写入 = 从未设置 → 生效值交给 NavStyleResolver 按设备形态/系统能力自判;
    /// 写入过(含 false=贴底)即用户意志, 永久优先, 不再自适应。
    func hasExplicitNavStyle() -> Bool {
        sp().object(forKey: Self.KEY_NAV_DOCK) != nil
    }

    func setNavDocked(_ floating: Bool) {
        sp().set(floating, forKey: Self.KEY_NAV_DOCK)
    }

    /// 撤销显式选择 → 回到"跟随设备自适应"(设置页「自动」档)。
    func clearNavStyle() {
        sp().removeObject(forKey: Self.KEY_NAV_DOCK)
    }

    // ===== 主题色 =====

    func getThemeKey() -> String {
        sp().string(forKey: Self.KEY_THEME) ?? ThemePresets.KEY_DEFAULT
    }

    func setThemeKey(_ key: String) {
        sp().set(key, forKey: Self.KEY_THEME)
        themeKeySubject.send(key)
    }

    // ===== 提醒 =====

    /// Master toggle — default false
    func isReminderEnabled() -> Bool { sp().bool(forKey: Self.KEY_REMINDER) }
    func setReminderEnabled(_ v: Bool) { sp().set(v, forKey: Self.KEY_REMINDER) }

    /// Daily reminder sub-toggle — default true (only active when master on)
    func isDailyReminderEnabled() -> Bool {
        sp().object(forKey: Self.KEY_DAILY_ENABLED) as? Bool ?? true
    }
    func setDailyReminderEnabled(_ v: Bool) { sp().set(v, forKey: Self.KEY_DAILY_ENABLED) }

    /// Daily reminder time "HH:mm" — default "07:00"
    func getDailyReminderTime() -> String { sp().string(forKey: Self.KEY_DAILY_TIME) ?? "07:00" }
    func setDailyReminderTime(_ time: String) { sp().set(time, forKey: Self.KEY_DAILY_TIME) }

    /// Before-class reminder sub-toggle — default false
    func isBeforeClassEnabled() -> Bool { sp().bool(forKey: Self.KEY_BEFORE_CLASS_ENABLED) }
    func setBeforeClassEnabled(_ v: Bool) { sp().set(v, forKey: Self.KEY_BEFORE_CLASS_ENABLED) }

    /// Minutes before class to notify — default 10
    func getBeforeClassMinutes() -> Int {
        sp().object(forKey: Self.KEY_BEFORE_CLASS_MINUTES) as? Int ?? 10
    }
    func setBeforeClassMinutes(_ minutes: Int) { sp().set(minutes, forKey: Self.KEY_BEFORE_CLASS_MINUTES) }

    // MARK: - v1.0.60 次日预告提醒

    /// 当日提醒子闸 — default true (← Android isTodayReminderEnabled getBoolean(key, DEFAULT_TODAY_REMINDER_ENABLED=true))
    func isTodayReminderEnabled() -> Bool {
        sp().object(forKey: Self.KEY_TODAY_REMINDER_ENABLED) as? Bool ?? Self.DEFAULT_TODAY_REMINDER_ENABLED
    }
    func setTodayReminderEnabled(_ v: Bool) { sp().set(v, forKey: Self.KEY_TODAY_REMINDER_ENABLED) }

    func isTomorrowReminderEnabled() -> Bool {
        sp().object(forKey: Self.KEY_TOMORROW_REMINDER_ENABLED) as? Bool ?? Self.DEFAULT_TOMORROW_REMINDER_ENABLED
    }
    func setTomorrowReminderEnabled(_ v: Bool) { sp().set(v, forKey: Self.KEY_TOMORROW_REMINDER_ENABLED) }

    func getTomorrowReminderTime() -> String {
        sp().string(forKey: Self.KEY_TOMORROW_REMINDER_TIME) ?? Self.DEFAULT_TOMORROW_REMINDER_TIME
    }
    func setTomorrowReminderTime(_ s: String) { sp().set(s, forKey: Self.KEY_TOMORROW_REMINDER_TIME) }

    // MARK: - v1.0.60 上课自动勿扰

    func isClassDndEnabled() -> Bool {
        sp().bool(forKey: Self.KEY_CLASS_DND_ENABLED)
    }
    func setClassDndEnabled(_ v: Bool) { sp().set(v, forKey: Self.KEY_CLASS_DND_ENABLED) }

    // MARK: - v1.0.61 系统日历导入 (对齐)

    func isBeforeClassBannerEnabled() -> Bool {
        sp().object(forKey: Self.KEY_BEFORE_CLASS_BANNER) as? Bool ?? true
    }
    func setBeforeClassBannerEnabled(_ v: Bool) { sp().set(v, forKey: Self.KEY_BEFORE_CLASS_BANNER) }

    func isBeforeClassFluidEnabled() -> Bool { sp().bool(forKey: Self.KEY_BEFORE_CLASS_FLUID) }
    func setBeforeClassFluidEnabled(_ v: Bool) { sp().set(v, forKey: Self.KEY_BEFORE_CLASS_FLUID) }

    /// legacy multi-select 读取(死写路径已删 — setBeforeClassFluidFields 全库零调用,读取仅通知组件用旧数据)
    func getBeforeClassFluidFields() -> Set<String> {
        let raw = sp().string(forKey: Self.KEY_BEFORE_CLASS_FLUID_FIELDS) ?? "name,time,room,teacher"
        return Set(raw.split(separator: ",").filter { !$0.isEmpty }.map(String.init))
    }

    func getBeforeClassFluidPrimary() -> String {
        sp().string(forKey: Self.KEY_BEFORE_CLASS_FLUID_PRIMARY) ?? "room"
    }

    func setBeforeClassFluidPrimary(_ value: String) {
        // ← Android require(name|time|room|countdown) v1.0.61: countdown 是合法主字段
        precondition(value == "name" || value == "time" || value == "room" || value == "countdown")
        // ★ 只写 PRIMARY;不再覆盖 FIELDS(多选字段集),否则用户配置的多字段组合被冲掉。
        sp().set(value, forKey: Self.KEY_BEFORE_CLASS_FLUID_PRIMARY)
    }

    // ===== 语言 =====

    /// 首启无保存值 → 从 AppleLanguages 推断(等价 Android 首启跟随系统;
    /// 用户在 App 内切过语言后 KEY_LANG 固定, AppPrefs 为唯一事实来源 ← wrapDefault)。
    /// 读 UserDefaults "AppleLanguages"(launch args/系统设置同源), 非 Locale.preferredLanguages。
    func getLanguage() -> String {
        if let saved = sp().string(forKey: Self.KEY_LANG) { return saved }
        let preferred = sp().stringArray(forKey: "AppleLanguages")?.first
            ?? Locale.preferredLanguages.first ?? "zh-CN"
        if preferred.hasPrefix("zh") {
            return preferred.contains("Hant") || preferred.contains("TW")
                || preferred.contains("HK") || preferred.contains("MO") ? "zh-TW" : "zh-CN"
        }
        if preferred.hasPrefix("en") { return "en" }
        if preferred.hasPrefix("ja") { return "ja" }
        if preferred.hasPrefix("es") { return "es" }
        return "zh-CN"
    }
    func setLanguage(_ lang: String) { sp().set(lang, forKey: Self.KEY_LANG) }

    // ===== 显示模式:节次 / 时间 =====

    /// 显示模式出厂默认 "time"(时间段) — 用户 2026-09-14 指令, ← Android getString(KEY_DISPLAY_MODE, "time")
    func getDisplayMode() -> String { sp().string(forKey: Self.KEY_DISPLAY_MODE) ?? "time" }
    func setDisplayMode(_ mode: String) { sp().set(mode, forKey: Self.KEY_DISPLAY_MODE) }

    /// 启动默认视图 — ← AppPrefs.getStartView Android (出厂默认 "cards": 用户反馈网格更好用)。
    /// 仅通用设置里设置, 手动切换课表顶部视图不写入(Android 注释硬规则, iOS 一致遵循)。
    func getStartView() -> String { sp().string(forKey: Self.KEY_START_VIEW) ?? "cards" }
    func setStartView(_ mode: String) {
        precondition(mode == "full" || mode == "cards")
        sp().set(mode, forKey: Self.KEY_START_VIEW)
    }

    // ===== 网格卡片副信息:教室 / 教师 / 无 =====

    func getGridSubInfo() -> String { sp().string(forKey: Self.KEY_GRID_SUB_INFO) ?? "room" }

    func setGridSubInfo(_ value: String) {
        precondition(value == "room" || value == "teacher" || value == "none")
        sp().set(value, forKey: Self.KEY_GRID_SUB_INFO)
    }

    // ===== 冲突课程显示样式：叠层 / 折角 / 竖轨(← v7.10.16s) =====

    /// 滑杆量程/默认值(← CONFLICT_TOP_INSET_RANGE / CONFLICT_FOLD_SIZE_RANGE)
    static let CONFLICT_TOP_INSET_RANGE: ClosedRange<Double> = 4...20
    static let CONFLICT_TOP_INSET_DEFAULT: Double = 7
    static let CONFLICT_FOLD_SIZE_RANGE: ClosedRange<Double> = 8...28
    static let CONFLICT_FOLD_SIZE_DEFAULT: Double = 16

    func getConflictStyle() -> String { sp().string(forKey: Self.KEY_CONFLICT_STYLE) ?? "rail" }

    func setConflictStyle(_ value: String) {
        precondition(value == "stack" || value == "fold" || value == "rail")
        sp().set(value, forKey: Self.KEY_CONFLICT_STYLE)
    }

    // ===== 冲突顶卡收窄量(用户 2026-09-04 拆分: 叠层/竖轨独立配置不共享) =====
    // 首次读取时从旧共用 key 迁移一次(旧值复制到两新 key), 旧 key 停写保留仅作迁移源。

    func getConflictStackInset() -> Double {
        if sp().object(forKey: Self.KEY_CONFLICT_STACK_INSET) == nil {
            sp().set(sp().double(forKey: Self.KEY_CONFLICT_TOP_INSET) == 0
                ? Self.CONFLICT_TOP_INSET_DEFAULT
                : sp().double(forKey: Self.KEY_CONFLICT_TOP_INSET),
                forKey: Self.KEY_CONFLICT_STACK_INSET)
        }
        let v = sp().double(forKey: Self.KEY_CONFLICT_STACK_INSET)
        return v == 0 ? Self.CONFLICT_TOP_INSET_DEFAULT : v
    }

    func setConflictStackInset(_ value: Double) {
        precondition(Self.CONFLICT_TOP_INSET_RANGE.contains(value))
        sp().set(value, forKey: Self.KEY_CONFLICT_STACK_INSET)
    }

    func getConflictRailInset() -> Double {
        if sp().object(forKey: Self.KEY_CONFLICT_RAIL_INSET) == nil {
            sp().set(sp().double(forKey: Self.KEY_CONFLICT_TOP_INSET) == 0
                ? Self.CONFLICT_TOP_INSET_DEFAULT
                : sp().double(forKey: Self.KEY_CONFLICT_TOP_INSET),
                forKey: Self.KEY_CONFLICT_RAIL_INSET)
        }
        let v = sp().double(forKey: Self.KEY_CONFLICT_RAIL_INSET)
        return v == 0 ? Self.CONFLICT_TOP_INSET_DEFAULT : v
    }

    func setConflictRailInset(_ value: Double) {
        precondition(Self.CONFLICT_TOP_INSET_RANGE.contains(value))
        sp().set(value, forKey: Self.KEY_CONFLICT_RAIL_INSET)
    }

    // ===== 冲突折角幅度(fold 样式专有) — 折痕直角边长,视觉/命中区同一真值 =====

    func getConflictFoldSize() -> Double {
        let v = sp().double(forKey: Self.KEY_CONFLICT_FOLD_SIZE)
        return v == 0 ? Self.CONFLICT_FOLD_SIZE_DEFAULT : v
    }

    func setConflictFoldSize(_ value: Double) {
        precondition(Self.CONFLICT_FOLD_SIZE_RANGE.contains(value))
        sp().set(value, forKey: Self.KEY_CONFLICT_FOLD_SIZE)
    }

    // ===== issue#8 主页显示 pill 组(← Android AppPrefs.kt get/set + changeBus) =====
    // iOS 无 changeBus:渲染层在 body 内直读(靠设置页关闭触发父级重建重算),与冲突滑杆同模式。

    func getGridScale() -> Double {
        // ← Android getFloat(key, 1.0f).coerceIn(0.7f, 1.3f): 读侧钳制(存量越界值安全落地)
        let v = sp().object(forKey: Self.KEY_GRID_SCALE) as? Double ?? 1.0
        return min(max(v, Self.GRID_SCALE_RANGE.lowerBound), Self.GRID_SCALE_RANGE.upperBound)
    }

    func setGridScale(_ value: Double) {
        // ← Android setter 静默 coerceIn(0.7f, 1.3f), 不抛
        sp().set(min(max(value, Self.GRID_SCALE_RANGE.lowerBound), Self.GRID_SCALE_RANGE.upperBound),
                 forKey: Self.KEY_GRID_SCALE)
    }

    func getWeekScale() -> Double {
        // ← Android getFloat(key, 1.0f).coerceIn(0.7f, 1.3f)
        let v = sp().object(forKey: Self.KEY_WEEK_SCALE) as? Double ?? 1.0
        return min(max(v, Self.GRID_SCALE_RANGE.lowerBound), Self.GRID_SCALE_RANGE.upperBound)
    }

    func setWeekScale(_ value: Double) {
        // ← Android setter 静默 coerceIn(0.7f, 1.3f)
        sp().set(min(max(value, Self.GRID_SCALE_RANGE.lowerBound), Self.GRID_SCALE_RANGE.upperBound),
                 forKey: Self.KEY_WEEK_SCALE)
    }

    func getGridCornerRatio() -> Double {
        // ← Android getFloat(key, 1.0f).coerceIn(0f, 2f)
        let v = sp().object(forKey: Self.KEY_GRID_CORNER_RATIO) as? Double ?? 1.0
        return min(max(v, Self.CORNER_RATIO_RANGE.lowerBound), Self.CORNER_RATIO_RANGE.upperBound)
    }

    func setGridCornerRatio(_ value: Double) {
        // ← Android setter 静默 coerceIn(0f, 2f)
        sp().set(min(max(value, Self.CORNER_RATIO_RANGE.lowerBound), Self.CORNER_RATIO_RANGE.upperBound),
                 forKey: Self.KEY_GRID_CORNER_RATIO)
    }

    func isWeekTwoColumn() -> Bool { sp().bool(forKey: Self.KEY_WEEK_TWO_COLUMN) }
    func setWeekTwoColumn(_ v: Bool) { sp().set(v, forKey: Self.KEY_WEEK_TWO_COLUMN) }

    func getWeekTwoColumnMode() -> String {
        sp().string(forKey: Self.KEY_WEEK_TWO_COLUMN_MODE) ?? "days"
    }
    func setWeekTwoColumnMode(_ v: String) {
        // ← Android: if (v == "balance") "balance" else "days" — 任意其它值静默归一为 "days"
        sp().set(v == "balance" ? "balance" : "days", forKey: Self.KEY_WEEK_TWO_COLUMN_MODE)
    }

    func isWeekHideEmptyDays() -> Bool { sp().bool(forKey: Self.KEY_WEEK_HIDE_EMPTY_DAYS) }
    func setWeekHideEmptyDays(_ v: Bool) { sp().set(v, forKey: Self.KEY_WEEK_HIDE_EMPTY_DAYS) }

    func isWeekUseAlias() -> Bool { sp().bool(forKey: Self.KEY_WEEK_USE_ALIAS) }
    func setWeekUseAlias(_ v: Bool) { sp().set(v, forKey: Self.KEY_WEEK_USE_ALIAS) }

    func isGridUseAlias() -> Bool { sp().bool(forKey: Self.KEY_GRID_USE_ALIAS) }
    func setGridUseAlias(_ v: Bool) { sp().set(v, forKey: Self.KEY_GRID_USE_ALIAS) }

    // issue#26: widget 场景 课程名显示 原名/别名 — 全局一档(所有小组件共享, 渲染器无
    // widgetId, 与 colorless/separator 同先例)。写入后全量刷 timeline
    // (← Android WidgetUpdater.notifyDataChanged, 桌面即时重绘)。
    func isWidgetUseAlias() -> Bool { sp().bool(forKey: Self.KEY_WIDGET_USE_ALIAS) }
    func setWidgetUseAlias(_ v: Bool) {
        sp().set(v, forKey: Self.KEY_WIDGET_USE_ALIAS)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // ===== 冲突簇默认置顶图层 =====
    // JSON Map<clusterKey, layerRepId>;内存真相源(@Published)保瞬时更新 —
    // 点击 → set 同帧刷 UI(用户 2026-09-02:「勾选的那一瞬间课表就应该完成置顶更新」),
    // UserDefaults 落盘异步不驱动 UI(← StateFlow 瞬时通道, v7.10.2)。

    /// 冲突默认置顶内存真相源(实例级 — AppPrefs 单例,与 Kotlin object 对齐)
    private let conflictDefaultTopSubject = ConflictDefaultTopStore.shared

    func getConflictDefaultTop() -> [String: Int64] {
        conflictDefaultTopSubject.map
    }

    func setConflictDefaultTop(_ map: [String: Int64]) {
        conflictDefaultTopSubject.map = map
        // ← encodeDefaultTopMap: JSONEncoder 过 Dictionary[String: Int64]
        if let data = try? JSONEncoder().encode(map) {
            sp().set(data, forKey: Self.KEY_CONFLICT_DEFAULT_TOP)
        } else {
            sp().removeObject(forKey: Self.KEY_CONFLICT_DEFAULT_TOP)
        }
    }

    /// 修改单个 clusterKey;传 nil = 删除该键(回退系统默认)。
    func putConflictDefaultTop(_ clusterKey: String, _ layerRepId: Int64?) {
        var current = getConflictDefaultTop()
        if let id = layerRepId { current[clusterKey] = id } else { current.removeValue(forKey: clusterKey) }
        setConflictDefaultTop(current)
    }

    /// 冷启动加载磁盘值进内存真相源 — 幂等(磁盘值与内存一致时不发射)。
    func primeConflictDefaultTop() {
        guard let data = sp().data(forKey: Self.KEY_CONFLICT_DEFAULT_TOP),
              let disk = try? JSONDecoder().decode([String: Int64].self, from: data) else { return }
        conflictDefaultTopSubject.prime(disk)
    }

    /// SwiftUI 订阅入口(GridConflictLayer @ObservedObject 用)
    static var sharedConflictDefaultTopStore: ConflictDefaultTopStore { ConflictDefaultTopStore.shared }

    // ===== 网格显示日期 =====

    /// 出厂默认 true ← Android getBoolean(KEY_SHOW_DATE, true) (用户反馈找不到开关, 直接默认开)
    func isShowDate() -> Bool {
        sp().object(forKey: Self.KEY_SHOW_DATE) as? Bool ?? true
    }
    func setShowDate(_ v: Bool) { sp().set(v, forKey: Self.KEY_SHOW_DATE) }

    // ===== 可见天 =====

    func getVisibleDays() -> Set<Int> {
        let raw = sp().string(forKey: Self.KEY_VISIBLE_DAYS) ?? "1,2,3,4,5,6,7"
        // ← mapNotNull { it.trim().toIntOrNull() }:非数字段丢弃
        return Set(raw.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) })
    }

    func setVisibleDays(_ days: Set<Int>) {
        let joined = days.sorted().map(String.init).joined(separator: ",")
        sp().set(joined, forKey: Self.KEY_VISIBLE_DAYS)
    }

    // ===== 竖排标点优化(方案B: 标点替换为 Unicode Vertical Forms) — 默认 false =====

    func isVertPunctReplace() -> Bool { sp().bool(forKey: Self.KEY_VERT_PUNCT_REPLACE) }
    func setVertPunctReplace(_ v: Bool) { sp().set(v, forKey: Self.KEY_VERT_PUNCT_REPLACE) }

    // ===== 小组件无色模式 — 默认 false =====

    func isWidgetColorless() -> Bool { sp().bool(forKey: Self.KEY_WIDGET_COLORLESS) }
    func setWidgetColorless(_ v: Bool) { sp().set(v, forKey: Self.KEY_WIDGET_COLORLESS) }

    // ===== App 课程胶囊无色模式 — 默认 false =====

    func isCourseColorless() -> Bool { sp().bool(forKey: Self.KEY_COURSE_COLORLESS) }
    func setCourseColorless(_ v: Bool) { sp().set(v, forKey: Self.KEY_COURSE_COLORLESS) }

    // ===== widget v1.0.60 对齐键 (← AppPrefs.kt 同名键) =====

    /// 今天没课时自动显示最近一个有课的日子 — 默认 false
    /// (← KEY_NEAREST_BUSY_DAY; WidgetWeekDataLoader.resolve enabled 入参)
    func isNearestBusyDay() -> Bool { sp().bool(forKey: Self.KEY_NEAREST_BUSY_DAY) }
    func setNearestBusyDay(_ v: Bool) {
        sp().set(v, forKey: Self.KEY_NEAREST_BUSY_DAY)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// 最小档三天窗口锚点全局旧值 — 默认 true (← Android getBoolean(KEY_COMPACT_WINDOW_TODAY_FIRST, true);
    /// 2026-09-15 用户令: 未写入过时今日居第一位)
    /// 仅作 per-kind 显式值未设置时的迁移默认 (WidgetCompactWindowStore.resolve)
    func isCompactWindowTodayFirst() -> Bool {
        sp().object(forKey: Self.KEY_COMPACT_WINDOW_TODAY_FIRST) as? Bool ?? true
    }
    func setCompactWindowTodayFirst(_ v: Bool) {
        sp().set(v, forKey: Self.KEY_COMPACT_WINDOW_TODAY_FIRST)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// 强制滚动(实验)全局旧值 — 默认 false = FIXED 固定窗口
    /// (← KEY_WIDGET_SCROLL_ENABLED; WidgetScrollStore 迁移默认)
    /// ★ 平台差异: iOS 无 RemoteViews 滚动条带, 开关仅作迁移语义载体 + 未来
    ///   ScrollView 扩展位, FIXED 窗口为 iOS 唯一渲染路径。
    func isWidgetScrollEnabled() -> Bool { sp().bool(forKey: Self.KEY_WIDGET_SCROLL_ENABLED) }

    // ===== WeekView 纯文字组件:课程间分隔线 — 默认 true =====

    func isWidgetSeparator() -> Bool {
        sp().object(forKey: Self.KEY_WIDGET_SEPARATOR) as? Bool ?? true
    }
    func setWidgetSeparator(_ v: Bool) { sp().set(v, forKey: Self.KEY_WIDGET_SEPARATOR) }

    // ===== 节假日灰显 =====

    /// 法定节假日灰显开关 — 默认 true ← isHolidayGreyHoliday
    func isHolidayGreyHoliday() -> Bool {
        sp().object(forKey: Self.KEY_HOLIDAY_GREY_HOLIDAY) as? Bool ?? true
    }
    func setHolidayGreyHoliday(_ v: Bool) { sp().set(v, forKey: Self.KEY_HOLIDAY_GREY_HOLIDAY) }

    /// 周末灰显开关 — 默认 true ← isHolidayGreyWeekend
    func isHolidayGreyWeekend() -> Bool {
        sp().object(forKey: Self.KEY_HOLIDAY_GREY_WEEKEND) as? Bool ?? true
    }
    func setHolidayGreyWeekend(_ v: Bool) { sp().set(v, forKey: Self.KEY_HOLIDAY_GREY_WEEKEND) }

    /// 灰显样式 — 默认 "grey" ← getHolidayStyle/setHolidayStyle
    func getHolidayStyle() -> String {
        sp().string(forKey: Self.KEY_HOLIDAY_STYLE) ?? "grey"
    }
    func setHolidayStyle(_ style: String) {
        precondition(style == "grey" || style == "strikethrough")
        sp().set(style, forKey: Self.KEY_HOLIDAY_STYLE)
    }

    /// 忽略补班日 — 默认 true ← isHolidayIgnoreWorkday
    func isHolidayIgnoreWorkday() -> Bool {
        sp().object(forKey: Self.KEY_HOLIDAY_IGNORE_WORKDAY) as? Bool ?? true
    }
    func setHolidayIgnoreWorkday(_ v: Bool) { sp().set(v, forKey: Self.KEY_HOLIDAY_IGNORE_WORKDAY) }

    /// 用户范围化覆盖段: 编辑/新增/删除节日段 ← getHolidayRanges/setHolidayRanges
    func getHolidayRanges() -> [HolidayRange] {
        HolidayRangeOps.decodeOverrides(sp().string(forKey: Self.KEY_HOLIDAY_OVERRIDES) ?? "[]")
    }
    func setHolidayRanges(_ ranges: [HolidayRange]) {
        sp().set(HolidayRangeOps.encodeOverrides(ranges), forKey: Self.KEY_HOLIDAY_OVERRIDES)
    }

    // ===== 节假日提醒规则开关 (v1.0.60 对齐) =====
    // 总开关默认 false(← Android getBoolean(KEY_HOLIDAY_REMINDER_RULES_ENABLED, false) —
    // 出厂不自动开启规则, 用户显式打开), 四类规则子开关默认 true(← getBoolean(KEY, true))。
    static let KEY_HOLIDAY_REMINDER_RULES_ENABLED = "holiday_reminder_rules_enabled"
    static let KEY_HOLIDAY_REMINDER_PUBLIC_HOLIDAY = "holiday_reminder_public_holiday"
    static let KEY_HOLIDAY_REMINDER_TRANSFER_HOLIDAY = "holiday_reminder_transfer_holiday"
    static let KEY_HOLIDAY_REMINDER_MAKEUP_WORKDAY = "holiday_reminder_makeup_workday"
    static let KEY_HOLIDAY_REMINDER_ORDINARY_WEEKEND = "holiday_reminder_ordinary_weekend"

    private func reminderFlag(_ key: String) -> Bool {
        sp().object(forKey: key) as? Bool ?? true
    }

    func isHolidayReminderRulesEnabled() -> Bool {
        sp().object(forKey: Self.KEY_HOLIDAY_REMINDER_RULES_ENABLED) as? Bool ?? false
    }
    func setHolidayReminderRulesEnabled(_ v: Bool) { sp().set(v, forKey: Self.KEY_HOLIDAY_REMINDER_RULES_ENABLED) }
    func isHolidayReminderPublicHolidayEnabled() -> Bool { reminderFlag(Self.KEY_HOLIDAY_REMINDER_PUBLIC_HOLIDAY) }
    func setHolidayReminderPublicHolidayEnabled(_ v: Bool) { sp().set(v, forKey: Self.KEY_HOLIDAY_REMINDER_PUBLIC_HOLIDAY) }
    func isHolidayReminderTransferHolidayEnabled() -> Bool { reminderFlag(Self.KEY_HOLIDAY_REMINDER_TRANSFER_HOLIDAY) }
    func setHolidayReminderTransferHolidayEnabled(_ v: Bool) { sp().set(v, forKey: Self.KEY_HOLIDAY_REMINDER_TRANSFER_HOLIDAY) }
    func isHolidayReminderMakeupWorkdayEnabled() -> Bool { reminderFlag(Self.KEY_HOLIDAY_REMINDER_MAKEUP_WORKDAY) }
    func setHolidayReminderMakeupWorkdayEnabled(_ v: Bool) { sp().set(v, forKey: Self.KEY_HOLIDAY_REMINDER_MAKEUP_WORKDAY) }
    func isHolidayReminderOrdinaryWeekendEnabled() -> Bool { reminderFlag(Self.KEY_HOLIDAY_REMINDER_ORDINARY_WEEKEND) }
    func setHolidayReminderOrdinaryWeekendEnabled(_ v: Bool) { sp().set(v, forKey: Self.KEY_HOLIDAY_REMINDER_ORDINARY_WEEKEND) }

    // ===== 系统日历导入 (v1.0.61 对齐, ← Android 同名 KEY, 默认值 1:1) =====
    // iOS 平台映射: Android calendarId 是 Long(内容库 _ID) → iOS 用 EKCalendar.calendarIdentifier(String)。
    //   "未选"(Android Long -1) 等价 = key 不存在(d.object(forKey:)==nil)。
    static let KEY_CALENDAR_TARGET_ID = "calendar_import_target_id"       // String?(EKCalendar identifier) 默认 unset
    static let KEY_CALENDAR_IMPORT_RANGE = "calendar_import_range"        // String "NEXT_WEEK"/"NEXT_MONTH"/"SEMESTER" 默认 NEXT_WEEK
    static let KEY_CALENDAR_APPLY_TRANSFERS = "calendar_import_apply_transfers" // bool 默认 true
    static let KEY_CALENDAR_REMINDER_MINUTES = "calendar_import_reminder_minutes" // int 默认 15, -1 = 无普通提醒
    static let KEY_CALENDAR_FIRST_ALARM = "calendar_import_first_alarm"   // bool 默认 false
    static let KEY_CALENDAR_FIRST_ALARM_MINUTES = "calendar_import_first_alarm_minutes" // int 默认 60

    /// 目标日历 EKCalendar.calendarIdentifier; 未设置 = nil(← Android getLong 默认 -1)
    func getCalendarTargetId() -> String? { sp().string(forKey: Self.KEY_CALENDAR_TARGET_ID) }
    func setCalendarTargetId(_ id: String) { sp().set(id, forKey: Self.KEY_CALENDAR_TARGET_ID) }

    func getCalendarImportRange() -> String {
        sp().string(forKey: Self.KEY_CALENDAR_IMPORT_RANGE) ?? "NEXT_WEEK"
    }
    func setCalendarImportRange(_ range: String) {
        precondition((["NEXT_WEEK", "NEXT_MONTH", "SEMESTER"] as Set).contains(range))
        sp().set(range, forKey: Self.KEY_CALENDAR_IMPORT_RANGE)
    }

    // ← Android 同名 KEY 默认值 1:1 (apply_transfers=true, first_alarm=false)
    func isCalendarApplyTransfers() -> Bool {
        sp().object(forKey: Self.KEY_CALENDAR_APPLY_TRANSFERS) as? Bool ?? true
    }
    func setCalendarApplyTransfers(_ enabled: Bool) { sp().set(enabled, forKey: Self.KEY_CALENDAR_APPLY_TRANSFERS) }

    /// nil = 日历事件不加普通提醒(← Android sp.getInt(KEY, 15).takeIf { it >= 0 }; -1 = 关)
    func getCalendarReminderMinutes() -> Int? {
        let v = sp().object(forKey: Self.KEY_CALENDAR_REMINDER_MINUTES) as? Int ?? 15
        return v >= 0 ? v : nil
    }
    /// 传 nil 存 -1(关提醒); 数值钳制 0...999(← Android coerceIn)
    func setCalendarReminderMinutes(_ minutes: Int?) {
        sp().set(minutes.map { min(max($0, 0), 999) } ?? -1, forKey: Self.KEY_CALENDAR_REMINDER_MINUTES)
    }
    func isCalendarFirstAlarmEnabled() -> Bool { sp().bool(forKey: Self.KEY_CALENDAR_FIRST_ALARM) }
    func setCalendarFirstAlarmEnabled(_ enabled: Bool) { sp().set(enabled, forKey: Self.KEY_CALENDAR_FIRST_ALARM) }
    func getCalendarFirstAlarmMinutes() -> Int {
        min(max(sp().object(forKey: Self.KEY_CALENDAR_FIRST_ALARM_MINUTES) as? Int ?? 60, 0), 999)
    }
    func setCalendarFirstAlarmMinutes(_ minutes: Int) {
        sp().set(min(max(minutes, 0), 999), forKey: Self.KEY_CALENDAR_FIRST_ALARM_MINUTES)
    }

    // ===== issue#44 调休映射(按课表隔离, 放假日→补班日) =====

    /// 调休映射按课表 ID 单独存 key — 各校补法不同(同一天 A 校补周四、B 校补周一),
    /// 全局一份会跨表套错。删表时可整键删除。
    private static func transferKey(_ tableId: Int64) -> String { "holiday_transfer_\(tableId)" }

    /// 某课表的调休映射; 无表/未设置 = 空(全部按自然星期取课)
    func getHolidayTransfers(_ tableId: Int64) -> [HolidayTransferEntry] {
        HolidayTransferOps.decodeTransfers(sp().string(forKey: Self.transferKey(tableId)) ?? "[]")
    }

    func setHolidayTransfers(_ tableId: Int64, _ transfers: [HolidayTransferEntry]) {
        sp().set(HolidayTransferOps.encodeTransfers(transfers), forKey: Self.transferKey(tableId))
    }

    /// 设/改某放假日的映射; targetDate = nil → 清除该放假日(回到自然星期)。
    /// 互斥(后选覆盖前选): 写入前移除同 targetDate 的既有条目 — 一天只能上一次课。
    func updateHolidayTransfer(_ tableId: Int64, sourceDate: Date, targetDate: Date?, segmentId: String) {
        let existing = getHolidayTransfers(tableId)
        let next: [HolidayTransferEntry]
        if let td = targetDate {
            next = HolidayTransferOps.withTargetExclusivity(
                existing, HolidayTransferEntry(sourceDate: sourceDate, targetDate: td, segmentId: segmentId))
        } else {
            next = existing.filter { $0.sourceDate != sourceDate }
        }
        setHolidayTransfers(tableId, next)
    }

    // MARK: - 节次表头设置(← AppPrefs.kt getPeriodHeaderLayout/Style/Hanging + isPeriodHeaderShowX, v1.0.60)
    // iOS 渲染层在 body 内直读(设置页切换触发父级重建),与冲突滑杆/网格缩放同模式 —
    // 无 changeBus,无 @Published 注入。

    /// Header layout 有两个持久态; 旧值 "vertical" 映射到 "three_line" — 升级时 UI 始终有选项。
    func getPeriodHeaderLayout() -> String {
        switch sp().string(forKey: Self.KEY_PERIOD_HEADER_LAYOUT) ?? "legacy" {
        case "three_line", "vertical": return "three_line"
        default: return "legacy"
        }
    }
    func setPeriodHeaderLayout(_ value: String) {
        precondition(value == "legacy" || value == "three_line")
        sp().set(value, forKey: Self.KEY_PERIOD_HEADER_LAYOUT)
    }
    func getPeriodHeaderStyle() -> String {
        sp().string(forKey: Self.KEY_PERIOD_HEADER_STYLE) ?? "arabic"
    }
    func setPeriodHeaderStyle(_ value: String) {
        let allowed: Set<String> = ["arabic", "chinese", "financial", "circled", "roman"]
        precondition(allowed.contains(value))
        sp().set(value, forKey: Self.KEY_PERIOD_HEADER_STYLE)
    }
    func getPeriodHeaderHanging() -> Float {
        let raw = sp().float(forKey: Self.KEY_PERIOD_HEADER_HANGING)
        return max(-1.0, min(1.0, raw))
    }
    func setPeriodHeaderHanging(_ value: Float) {
        sp().set(max(-1.0, min(1.0, value)), forKey: Self.KEY_PERIOD_HEADER_HANGING)
    }
    func isPeriodHeaderShowX() -> Bool {
        sp().bool(forKey: Self.KEY_PERIOD_HEADER_SHOW_X)
    }
    func setPeriodHeaderShowX(_ value: Bool) {
        sp().set(value, forKey: Self.KEY_PERIOD_HEADER_SHOW_X)
    }

    // MARK: - 实验室开关组 getter(← AppPrefs.kt KEY_GRID_* / KEY_SHOW_VIEW_SWITCHER, v1.0.56)
    // GeneralSettingsScreen.LabPrefs / CourseTableView.GridLabPrefs 此前经 UserDefaults.standard
    // 同源直读(AppPrefs.shared 默认 suite 即 standard), 行为等价; 本组为正式归属地。
    // iOS 无 changeBus: 渲染层 body 内直读, 写入无需广播。

    /// 自动收起无课晚间节次 — default false ← isGridAutoHideEmptyEvening
    func isGridAutoHideEmptyEvening() -> Bool {
        sp().object(forKey: Self.KEY_GRID_AUTO_HIDE_EMPTY_EVENING) as? Bool ?? false
    }
    func setGridAutoHideEmptyEvening(_ v: Bool) { sp().set(v, forKey: Self.KEY_GRID_AUTO_HIDE_EMPTY_EVENING) }

    /// 自适应行高(默认固定 52dp 基座) — default false ← isGridAdaptiveHeight
    func isGridAdaptiveHeight() -> Bool {
        sp().object(forKey: Self.KEY_GRID_ADAPTIVE_HEIGHT) as? Bool ?? false
    }
    func setGridAdaptiveHeight(_ v: Bool) { sp().set(v, forKey: Self.KEY_GRID_ADAPTIVE_HEIGHT) }

    /// 晚间起始时间 "HH:mm" — default "18:00" ← getGridEveningStart
    func getGridEveningStart() -> String {
        sp().string(forKey: Self.KEY_GRID_EVENING_START) ?? "18:00"
    }
    func setGridEveningStart(_ v: String) { sp().set(v, forKey: Self.KEY_GRID_EVENING_START) }

    /// 双指行高缩放确认值 — default 1.0 ← getGridRowScale(Android 读侧不钳制, iOS 一致)
    func getGridRowScale() -> Double {
        sp().object(forKey: Self.KEY_GRID_ROW_SCALE) as? Double ?? 1.0
    }
    func setGridRowScale(_ v: Double) { sp().set(v, forKey: Self.KEY_GRID_ROW_SCALE) }

    /// 双指捏放行高 — default false(v1.0.56 默认关, 关=手势不挂) ← isGridPinchZoom
    func isGridPinchZoom() -> Bool {
        sp().object(forKey: Self.KEY_GRID_PINCH_ZOOM) as? Bool ?? Self.DEFAULT_GRID_PINCH_ZOOM
    }
    func setGridPinchZoom(_ v: Bool) { sp().set(v, forKey: Self.KEY_GRID_PINCH_ZOOM) }

    /// 网格额外分隔线 — default false ← isGridShowSeparators
    func isGridShowSeparators() -> Bool {
        sp().object(forKey: Self.KEY_GRID_SHOW_SEPARATORS) as? Bool ?? Self.DEFAULT_GRID_SHOW_SEPARATORS
    }
    func setGridShowSeparators(_ v: Bool) { sp().set(v, forKey: Self.KEY_GRID_SHOW_SEPARATORS) }

    /// 长课间额外留白 — default false ← isGridLongBreakSpacing
    func isGridLongBreakSpacing() -> Bool {
        sp().object(forKey: Self.KEY_GRID_LONG_BREAK_SPACING) as? Bool ?? Self.DEFAULT_GRID_LONG_BREAK_SPACING
    }
    func setGridLongBreakSpacing(_ v: Bool) { sp().set(v, forKey: Self.KEY_GRID_LONG_BREAK_SPACING) }

    /// 首页周/网格视图切换栏显隐 — default true ← isShowViewSwitcher getBoolean(key, true)
    func isShowViewSwitcher() -> Bool {
        sp().object(forKey: Self.KEY_SHOW_VIEW_SWITCHER) as? Bool ?? true
    }
    func setShowViewSwitcher(_ v: Bool) { sp().set(v, forKey: Self.KEY_SHOW_VIEW_SWITCHER) }

    /// 删表时清掉该表映射
    func clearHolidayTransfers(_ tableId: Int64) {
        sp().removeObject(forKey: Self.transferKey(tableId))
    }
}

/// 冲突默认置顶内存真相源(← MutableStateFlow) — @Published 供 SwiftUI 同帧刷 UI
final class ConflictDefaultTopStore: ObservableObject {
    static let shared = ConflictDefaultTopStore()
    @Published var map: [String: Int64] = [:]

    /// 幂等加载: 磁盘值与内存一致时不发射
    func prime(_ disk: [String: Int64]) {
        if map != disk { map = disk }
    }
}
