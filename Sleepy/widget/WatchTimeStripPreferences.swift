import Foundation

/// Watch App 与独立 Widget Extension 共用的时间带显示口径。
struct WatchTimeStripPreferences: Codable {
    var showsTomorrow: Bool = false
    var language: String = "zh-CN"
    /// tableId → HolidayTransferOps JSON 原串, 与 WatchSyncSnapshot 保持同一映射格式。
    var transfers: [Int64: String] = [:]
}

final class WatchTimeStripPreferencesStore {
    static let shared: WatchTimeStripPreferencesStore = {
        let defaults = AppGroupResolver.resolve().flatMap { UserDefaults(suiteName: $0) } ?? .standard
        return WatchTimeStripPreferencesStore(defaults: defaults)
    }()

    private static let storageKey = "watch_time_strip_preferences"
    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// 不缓存进程内副本; 独立扩展每次从共享存储读取完整快照。
    func load() -> WatchTimeStripPreferences {
        guard let data = defaults.data(forKey: Self.storageKey),
              let preferences = try? JSONDecoder().decode(WatchTimeStripPreferences.self, from: data)
        else { return WatchTimeStripPreferences() }
        return preferences
    }

    func save(_ preferences: WatchTimeStripPreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        // 单键 Data 一次替换, 避免跨进程读取到新开关配旧语言/调休映射。
        defaults.set(data, forKey: Self.storageKey)
    }

    func apply(_ snapshot: WatchSyncSnapshot.PrefsSnapshot) {
        // 全量替换: 旧手机缺字段时关闭预览, 已删除的课表映射不残留。
        save(WatchTimeStripPreferences(showsTomorrow: snapshot.timeStripTomorrow ?? false,
                                      language: snapshot.language,
                                      transfers: snapshot.transfers))
    }
}
