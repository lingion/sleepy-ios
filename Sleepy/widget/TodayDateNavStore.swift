// TodayDateNavStore.swift — ← widget/TodayDateNavCore.kt + TodayDateNavStore.kt
//   (两文件合一, 职责分区注释保留)
//
// 每日课程小组件日期导航的纯状态核心 + 持久化 facade。
//
// 状态语义: 每个 appWidgetId(原版本)/kind(iOS) 存 (selectedEpochDay, anchorEpochDay)。
// - anchor == 今天的 epochDay → 用户处于导航态, 显示 selected
// - anchor 已跨天(stale) → 显示今天 (R5: 到新的一天回到今天)
// 偏移钳制在 ±[MAX_ABS_OFFSET_DAYS] 天(约 ±13 周) — 防止用户连点箭头把 epochDay
// 推到荒谬位置; 也保证 currentWeek(startDate, target) 落到合理 week 范围。
//
// ★ 平台差异: 原版本 翻页靠 nav PendingIntent 广播 + onReceive 钩子; iOS 15.6 的
//   WidgetKit 无 per-widget 交互式按钮 (InteractiveWidget 需 iOS 17) → Store 与
//   Core 全量移植(数据流/钳制/跨天回今天语义), 翻页 UI 入口(◀▶↻ 按钮)无对应物,
//   target/shift 由编辑页或未来交互式扩展接管。持久层: SharedPreferences →
//   App Group 共享容器 JSON 文件 (WidgetBindingStore 同模式)。

import Foundation

// MARK: - TodayDateNavCore (纯逻辑, 可单测)

enum TodayDateNavCore {

    /// 存储文件名 — ← PREFS_NAME("widget_today_nav") + ".json" 后缀
    static let storeFileName = "widget_today_nav.json"

    /// 选中期 epochDay 的 key 前缀。
    static let KEY_SEL_PREFIX = "today_nav_sel_"

    /// 锚点期 epochDay 的 key 前缀 (即最近一次用户点击箭头时「今天」的 epochDay)。
    static let KEY_ANCHOR_PREFIX = "today_nav_anchor_"

    /// 选中相对今天的最大偏移天数 (前/后对称) — 约一学期浏览范围。
    static let MAX_ABS_OFFSET_DAYS = 92

    struct Entry {
        let selectedEpochDay: Int
        let anchorEpochDay: Int
    }

    static func keySel(_ widgetId: String) -> String { KEY_SEL_PREFIX + widgetId }
    static func keyAnchor(_ widgetId: String) -> String { KEY_ANCHOR_PREFIX + widgetId }

    /// 决定实际渲染的日期 epochDay。
    /// 无 entry → today; entry 锚点失效(锚 != today)→ today (R5 跨天回今天);
    /// 锚点有效 → 返回 selected。
    static func resolveTargetEpochDay(_ entry: Entry?, _ todayEpochDay: Int) -> Int {
        if let entry = entry, entry.anchorEpochDay == todayEpochDay {
            return entry.selectedEpochDay
        }
        return todayEpochDay
    }

    /// 从当前 entry + today 出发, 沿 deltaDays 推进 (正向未来 / 负向过去)。
    /// 锚点失效的 entry 视为「无状态」, 以 today 为基准。
    /// 偏移钳制在 ±[MAX_ABS_OFFSET_DAYS] 内; 锚点一律刷新为 today。
    static func shift(_ entry: Entry?, _ todayEpochDay: Int, _ deltaDays: Int) -> Entry {
        let base = resolveTargetEpochDay(entry, todayEpochDay)
        let target = min(max(base - todayEpochDay + deltaDays, -MAX_ABS_OFFSET_DAYS), MAX_ABS_OFFSET_DAYS)
        return Entry(selectedEpochDay: todayEpochDay + target, anchorEpochDay: todayEpochDay)
    }

    /// 写 raw map (Store facade 使用, 测试也可直接断言 key 形状)。
    static func write(_ raw: inout [String: Int], _ widgetId: String, _ entry: Entry) {
        raw[keySel(widgetId)] = entry.selectedEpochDay
        raw[keyAnchor(widgetId)] = entry.anchorEpochDay
    }

    /// 读 raw map; sel 或 anchor 缺失返回 nil (Entry 完整性自我约束)。
    static func read(_ raw: [String: Int], _ widgetId: String) -> Entry? {
        guard let sel = raw[keySel(widgetId)],
              let anchor = raw[keyAnchor(widgetId)] else { return nil }
        return Entry(selectedEpochDay: sel, anchorEpochDay: anchor)
    }

    /// 删 raw map 中该 widget 的两条 key (R4 隔离: 只动自己的 entry)。
    static func delete(_ raw: inout [String: Int], _ widgetId: String) {
        raw.removeValue(forKey: keySel(widgetId))
        raw.removeValue(forKey: keyAnchor(widgetId))
    }
}

// MARK: - TodayDateNavStore (持久化 facade)

enum TodayDateNavStore {

    /// 读取存储解析出该 widget 应渲染的日期 (无状态 → today)。
    static func target(_ widgetId: String, _ today: Date) -> Date {
        let entry = read(widgetId)
        let epoch = TodayDateNavCore.resolveTargetEpochDay(entry, Calendar.epochDay(today))
        return Calendar.dateFromEpochDay(epoch)
    }

    /// true 表示用户曾经手动翻过日期；自动周末切换不得覆盖这类导航态。
    static func hasNavigation(_ widgetId: String) -> Bool {
        read(widgetId) != nil
    }

    /// 把日期推进 ±deltaDays (锚点刷新为 today); 钳制在 Core.MAX_ABS_OFFSET_DAYS 内。
    static func shift(_ widgetId: String, _ today: Date, _ deltaDays: Int) {
        lock.lock(); defer { lock.unlock() }
        let entry = read(widgetId)
        let newEntry = TodayDateNavCore.shift(entry, Calendar.epochDay(today), deltaDays)
        var raw = loadAll()
        TodayDateNavCore.write(&raw, widgetId, newEntry)
        saveAll(raw)
    }

    /// 重置为「今天」 — 删除该 widget 的两条 key (语义上等价「无导航态」)。
    static func remove(_ widgetId: String) {
        lock.lock(); defer { lock.unlock() }
        var raw = loadAll()
        TodayDateNavCore.delete(&raw, widgetId)
        saveAll(raw)
    }

    // 读改写互斥锁 — shift/remove 是「读全量 → 改一条 → 重写全量」的非原子三步
    // (双 tap 并发丢翻页的防线, 语义原样保留)。
    private static let lock = NSLock()

    private static func read(_ widgetId: String) -> TodayDateNavCore.Entry? {
        TodayDateNavCore.read(loadAll(), widgetId)
    }

    private static func storeURL() -> URL {
        AppGroupResolver.sharedDirectory().appendingPathComponent(TodayDateNavCore.storeFileName)
    }

    private static func loadAll() -> [String: Int] {
        guard let data = try? Data(contentsOf: storeURL()),
              let map = try? JSONDecoder().decode([String: Int].self, from: data) else {
            return [:]
        }
        return map
    }

    private static func saveAll(_ data: [String: Int]) {
        guard let data = try? JSONEncoder().encode(data) else { return }
        try? data.write(to: storeURL(), options: .atomic)
    }
}
