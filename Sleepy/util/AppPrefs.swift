// AppPrefs.swift — ← AppPrefs.kt
// Android: SharedPreferences + callbackFlow → iOS: UserDefaults + Combine CurrentValueSubject
// 进程内 @Published 同步给 UI,磁盘做持久化(与 Kotlin object 单例语义一致)。

import Foundation
import Combine

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
    static let KEY_BEFORE_CLASS_FLUID_PRIMARY = "before_class_fluid_primary" // name/time/room
    static let KEY_THEME = "theme_key"
    static let KEY_LANG = "language"
    static let KEY_DISPLAY_MODE = "display_mode" // "node" or "time"
    static let KEY_GRID_SUB_INFO = "grid_sub_info" // "room" / "teacher" / "none" — 网格卡片副信息(周视图网格卡课程名下方那行;左栏已有节次,故此处不再显示节次/时间)
    static let KEY_SHOW_DATE = "show_date"       // boolean
    static let KEY_VISIBLE_DAYS = "visible_days" // "1,2,3,4,5,6,7"
    static let KEY_VERT_PUNCT_REPLACE = "vert_punct_replace" // bool default false (方案B开关)
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
        precondition(value == "name" || value == "time" || value == "room")
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

    func getDisplayMode() -> String { sp().string(forKey: Self.KEY_DISPLAY_MODE) ?? "node" }
    func setDisplayMode(_ mode: String) { sp().set(mode, forKey: Self.KEY_DISPLAY_MODE) }

    // ===== 网格卡片副信息:教室 / 教师 / 无 =====

    func getGridSubInfo() -> String { sp().string(forKey: Self.KEY_GRID_SUB_INFO) ?? "room" }

    func setGridSubInfo(_ value: String) {
        precondition(value == "room" || value == "teacher" || value == "none")
        sp().set(value, forKey: Self.KEY_GRID_SUB_INFO)
    }

    // ===== 网格显示日期 =====

    func isShowDate() -> Bool { sp().bool(forKey: Self.KEY_SHOW_DATE) }
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
}
