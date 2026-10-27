// HolidayManager.swift — ← HolidayManager.kt + HolidayRange.kt
// 节假日管理器 - 从网络获取法定节假日, App 内判断是否显示灰显。
//
// API: https://unpkg.com/holiday-calendar/data/CN/{year}.json
// 格式: {"year":2025,"region":"CN","dates":[{"date":"2025-01-01","name":"元旦","type":"public_holiday"}]}
//
// 数据源：https://gitcode.com/zy-mayong/publicHoliday (MIT, 商用 OK)

import Foundation

// MARK: - HolidayEntry (← data class HolidayEntry)

/** 带名称的节假日/补班日条目 */
struct HolidayEntry: Equatable {
    let date: Date
    let name: String
    let type: String
}

/** 某年数据 + 该数据是否可作权威判定 ← data class HolidayYearData */
struct HolidayYearData: Equatable {
    let entries: [HolidayEntry]
    let available: Bool
}

// MARK: - HolidayRange (← data class HolidayRange)

/** 用户可编辑的节假日段(连续日期范围)。type 复用 HolidayManager 常量 + HolidayRangeOps.REMOVED */
struct HolidayRange: Equatable {
    let id: String
    let name: String
    let startDate: Date
    let endDate: Date
    let type: String
    /// 被本段替换/删除的网络段首日标识 "holiday:<date>"/"workday:<date>"; nil=纯新增
    let sourceKey: String?
}

// MARK: - HolidayManager (← object HolidayManager)

enum HolidayManager {
    /// API 条目类型: 法定节假日 / 补班日(周末但要上课)
    static let TYPE_PUBLIC_HOLIDAY = "public_holiday"
    static let TYPE_TRANSFER_WORKDAY = "transfer_workday"

    private static let BASE_URL = "https://unpkg.com/holiday-calendar/data/CN/"
    /// 与 AppPrefs 同一个 UserDefaults(App 端用 .standard) ← PREFS_NAME
    private static var prefs: UserDefaults { AppPrefs.shared.sharedBackedStore }
    private static let CONNECT_TIMEOUT_S: TimeInterval = 5
    private static let READ_TIMEOUT_S: TimeInterval = 5

    private static func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = 12
        c.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        return Calendar(identifier: .gregorian).date(from: c) ?? Date.distantPast
    }

    private static func yearOf(_ d: Date) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        return cal.component(.year, from: d)
    }

    private static var entriesCache: [Int: [HolidayEntry]] = [:]
    /// 各年数据是否拉取成功过(空结果+成功=false => 网络失败)
    private static var yearFetchFailed: [Int: Bool] = [:]

    /// ★ 线程安全(2026-10-26 崩溃修复): iOS 26 原生 TabView 同时实例化 4 页,
    ///   多 async 任务并发读写上面两个 static 字典 → SIGSEGV(objc_msgSend 野指针,
    ///   崩在 Dictionary._Variant.setValue)。两字典一切读写必须走锁封装访问器,
    ///   禁止直访。yearFetchFailed 旧写法的 await MainActor.run 只统一了写线程,
    ///   与任意线程的读(isYearFetchFailed)仍是数据竞争, 一并收进锁内。
    private static let cacheLock = NSLock()

    private static func cacheGet(_ year: Int) -> [HolidayEntry]? {
        cacheLock.lock(); defer { cacheLock.unlock() }
        return entriesCache[year]
    }
    private static func cachePut(_ year: Int, _ entries: [HolidayEntry]) {
        cacheLock.lock(); defer { cacheLock.unlock() }
        entriesCache[year] = entries
    }
    private static func failedGet(_ year: Int) -> Bool {
        cacheLock.lock(); defer { cacheLock.unlock() }
        return yearFetchFailed[year] == true
    }
    private static func failedPut(_ year: Int, _ failed: Bool) {
        cacheLock.lock(); defer { cacheLock.unlock() }
        if failed { yearFetchFailed[year] = true } else { yearFetchFailed.removeValue(forKey: year) }
    }

    /**
     * 磁盘缓存 — 拉成功一次即落盘, 进程重启后仍有效。
     * 刷新走 refreshYearEntries 强制绕过内存+磁盘。
     */
    private static let CACHE_KEY_PREFIX = "holiday_entries_"
    private static let CACHE_LOADED_SUFFIX = "_loaded"
    private static func cacheKey(_ year: Int) -> String { CACHE_KEY_PREFIX + String(year) }
    private static func loadedKey(_ year: Int) -> String { cacheKey(year) + CACHE_LOADED_SUFFIX }

    private static func diskCache(_ year: Int) -> [HolidayEntry]? {
        // loaded 标记与数据同写: 空年份(该年确实无数据)也视为已缓存, 否则每次启动都会重复请求
        guard prefs.bool(forKey: loadedKey(year)) else { return nil }
        guard let json = prefs.string(forKey: cacheKey(year)),
              let data = json.data(using: .utf8),
              let dates = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else { return nil }
        // ← Android JSONObject().put("dates", dates) 再 parseEntries: 落盘是裸数组串, 解析要求根 {"dates":[...]}
        guard let wrapped = try? JSONSerialization.data(withJSONObject: ["dates": dates]),
              let wrappedJson = String(data: wrapped, encoding: .utf8) else { return nil }
        return parseEntries(wrappedJson)
    }

    private static func writeDiskCache(_ year: Int, _ entries: [HolidayEntry]) {
        // 存 JSON *字符串*(← Android putString(cacheKey, arr.toString())), 与 diskCache 的 string(forKey:) 读回同型
        let arr: [[String: Any]] = entries.map { e in
            ["date": dateFormat.string(from: e.date), "name": e.name, "type": e.type]
        }
        let s: String
        if let data = try? JSONSerialization.data(withJSONObject: arr),
           let str = String(data: data, encoding: .utf8) {
            s = str
        } else {
            s = "[]"
        }
        prefs.set(s, forKey: cacheKey(year))
        prefs.set(true, forKey: loadedKey(year))
    }

    /// 判断某日期是否为周末 ← isWeekend (Kotlin dayOfWeek 6=Sat 7=Sun)
    static func isWeekend(_ date: Date) -> Bool {
        let wd = Calendar.gregorianCST.component(.weekday, from: date) // 1=Sun ... 7=Sat
        return wd == 1 || wd == 7
    }

    /// 纯决策核: 日期在法定节假日集合内且该日未被调休映射 → 应跳过课程类提醒。← decideSkipPublicHoliday
    static func decideSkipPublicHoliday(
        date: Date,
        holidays: Set<Date>,
        dateHasTransfer: Bool
    ) -> Bool { holidays.contains(date) && !dateHasTransfer }

    /// Cache-only holiday decision for scheduler/recovery paths; never performs network I/O. ← isPublicHolidayCached
    /// [tableId] 给定时同时查该表调休映射(命中 = 那天要上课, 不跳过)。
    static func isPublicHolidayCached(_ date: Date, tableId: Int64? = nil) -> Bool {
        guard AppPrefs.shared.isHolidayGreyHoliday() else { return false }
        let networkEntries = cacheGet(date.year) ?? diskCache(date.year) ?? []
        let ranges = AppPrefs.shared.getHolidayRanges()
        let merged = HolidayRangeOps.mergeSegments(networkEntries, ranges)
        let (holidays, _) = HolidayRangeOps.toSets(merged.active)
        let hasTransfer = tableId != nil &&
            HolidayTransferOps.transferFor(date, AppPrefs.shared.getHolidayTransfers(tableId!)) != nil
        return decideSkipPublicHoliday(date: date, holidays: holidays, dateHasTransfer: hasTransfer)
    }

    /// 判断某日期是否应该灰显（根据用户设置，含用户范围化覆盖）← shouldGrey
    /// [tableId] 给定时同时查该表调休映射: 命中映射的放假日那天要上课, 永不灰 (issue#44)。
    static func shouldGrey(_ date: Date, tableId: Int64? = nil) async -> Bool {
        let ranges = AppPrefs.shared.getHolidayRanges()
        let networkEntries = await getYearEntries(date.year)
        let merged = HolidayRangeOps.mergeSegments(networkEntries, ranges)
        let (holidays, networkWorkdays) = HolidayRangeOps.toSets(merged.active)
        // 补班日集合 = 网络法定补班日 + 用户自定义补班日(映射的 targetDate)
        // ← Android L111-15: 周末调休补班当天 greyWeekend+ignoreWorkday 开启时不灰
        let customWorkdays: Set<Date> = tableId != nil
            ? Set(AppPrefs.shared.getHolidayTransfers(tableId!).map { $0.targetDate })
            : []
        let workdays = networkWorkdays.union(customWorkdays)
        let workdaysForWeekend: Set<Date> =
            (AppPrefs.shared.isHolidayGreyWeekend() && AppPrefs.shared.isHolidayIgnoreWorkday())
            ? workdays : []
        let hasTransfer = tableId != nil &&
            HolidayTransferOps.transferFor(date, AppPrefs.shared.getHolidayTransfers(tableId!)) != nil
        return decideGrey(
            date: date,
            holidays: holidays,
            workdays: workdaysForWeekend,
            greyHoliday: AppPrefs.shared.isHolidayGreyHoliday(),
            greyWeekend: AppPrefs.shared.isHolidayGreyWeekend(),
            ignoreWorkday: AppPrefs.shared.isHolidayIgnoreWorkday(),
            dateHasTransfer: hasTransfer
        )
    }

    /**
     * 获取某年全部原始网络条目(节假日+补班日, 带名称, 不含用户覆盖)。
     * 取数顺序: 内存缓存 → 磁盘缓存(拉成功一次即永久) → 网络。
     * 空列表 + yearFetchFailed == true 表示网络失败而非"该年无数据"。
     */
    static func getYearEntries(_ year: Int) async -> [HolidayEntry] {
        if let hit = cacheGet(year) { return hit }
        if let hit = diskCache(year) {
            cachePut(year, hit)
            return hit
        }
        let entries = await fetchEntries(year)
        if !entries.isEmpty || !isYearFetchFailed(year) {
            // 成功(含空年份, loaded 标记保证空数据也算已缓存)才落盘; 网络失败不缓存失败态
            cachePut(year, entries)
            writeDiskCache(year, entries)
        }
        return entries
    }

    /// 某年生效数据(含用户覆盖展开) + 可用性 ← getYearData
    static func getYearData(_ year: Int) async -> HolidayYearData {
        let cacheEntries = cacheGet(year) ?? diskCache(year)
        // ?? 右操作数是 autoclosure 不支持 await, 拆成显式分支
        let entries: [HolidayEntry]
        if let cacheEntries {
            entries = cacheEntries
        } else {
            entries = await getYearEntries(year)
        }
        if let cacheEntries { cachePut(year, cacheEntries) }
        let effective = HolidayRangeOps.mergeSegments(entries, AppPrefs.shared.getHolidayRanges()).active
        // 段按日逐天展开 ← generateSequence(segment.startDate){...}
        var effectiveEntries: [HolidayEntry] = []
        for segment in effective {
            var d = segment.startDate
            while d <= segment.endDate {
                effectiveEntries.append(HolidayEntry(date: d, name: segment.name, type: segment.type))
                guard let next = Calendar.gregorianCST.date(byAdding: .day, value: 1, to: d) else { break }
                d = next
            }
        }
        return yearData(effectiveEntries, fetchFailed: isYearFetchFailed(year), hasCachedData: cacheEntries != nil)
    }

    /// 纯装配核 ← yearData: 用户覆盖能分类具体日期, 但不能让拉取失败的网络年对其他日期成为权威。
    static func yearData(
        _ entries: [HolidayEntry],
        fetchFailed: Bool,
        hasCachedData: Bool
    ) -> HolidayYearData {
        HolidayYearData(
            entries: entries,
            available: hasCachedData || !fetchFailed
        )
    }

    /// 纯刷新核 ← refreshedEntries: 刷新失败且有缓存 → 保留缓存条目。
    static func refreshedEntries(
        cached: [HolidayEntry]?,
        fetched: [HolidayEntry],
        fetchFailed: Bool
    ) -> [HolidayEntry] {
        if fetchFailed { return cached ?? fetched }
        return fetched
    }

    /// 某年数据是否因网络原因拉取失败 ← isYearFetchFailed
    static func isYearFetchFailed(_ year: Int) -> Bool { failedGet(year) }

    /// 强制重新拉取某年条目(设置页"刷新"按钮用): 绕过内存+磁盘缓存 ← refreshYearEntries
    static func refreshYearEntries(_ year: Int) async -> [HolidayEntry] {
        let cached = cacheGet(year) ?? diskCache(year)
        if let cached { cachePut(year, cached) }
        failedPut(year, false)

        let fetched = await fetchEntries(year)
        let fetchFailed = isYearFetchFailed(year)
        let result = refreshedEntries(cached: cached, fetched: fetched, fetchFailed: fetchFailed)
        if !fetchFailed {
            cachePut(year, fetched)
            writeDiskCache(year, fetched)
        }
        return result
    }

    /// 拉取并解析某年全部条目(带名称), 供二级页展示 ← fetchEntries
    private static func fetchEntries(_ year: Int) async -> [HolidayEntry] {
        guard let url = URL(string: BASE_URL + "\(year).json") else {
            failedPut(year, true)
            return []
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = READ_TIMEOUT_S
        request.setValue("Sleepy/holiday", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                failedPut(year, true)
                return []
            }
            let json = String(data: data, encoding: .utf8) ?? ""
            let entries = parseEntries(json)
            if entries.isEmpty && !json.contains("\"dates\"") {
                // 返回体异常(非预期结构)视为失败
                failedPut(year, true)
            } else {
                // 解析成功 → 清除失败标记(← Android else { yearFetchFailed.remove(year) }):
                // 否则先前失败的年份在后续成功后仍被 isYearFetchFailed 判失败
                failedPut(year, false)
            }
            return entries
        } catch {
            failedPut(year, true)
            return []
        }
    }

    /// ISO 日期格式化( yyyy-MM-dd, CST) — HolidayRangeOps 编解码共用
    static let dateFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return f
    }()

    /// 解析 API JSON 为条目列表(纯函数, 单测覆盖) ← parseEntries
    static func parseEntries(_ json: String) -> [HolidayEntry] {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dates = root["dates"] as? [[String: Any]] else { return [] }
        var entries: [HolidayEntry] = []
        for entry in dates {
            guard let dateStr = entry["date"] as? String,
                  let d = dateFormat.date(from: dateStr) else { continue }
            entries.append(HolidayEntry(
                date: d,
                name: entry["name"] as? String ?? "",
                type: entry["type"] as? String ?? ""
            ))
        }
        return entries.sorted { $0.date < $1.date }
    }

    /// 预加载当前年和明年的节假日数据 ← preload
    static func preload() async {
        let year = Date().year
        _ = await getYearEntries(year)
        _ = await getYearEntries(year + 1)
    }

    /**
     * 灰显判定纯函数(无网络, 单测覆盖) ← decideGrey。
     * greyHoliday/greyWeekend/ignoreWorkday 对应用户三个开关,
     * workdays 为该年补班日集合(仅周末判定分支用到),
     * dateHasTransfer = 该日命中课表调休映射(issue#44)。
     */
    static func decideGrey(
        date: Date,
        holidays: Set<Date>,
        workdays: Set<Date>,
        greyHoliday: Bool,
        greyWeekend: Bool,
        ignoreWorkday: Bool,
        dateHasTransfer: Bool = false
    ) -> Bool {
        // issue#44: 命中调休映射的放假日 = 那天要上课(上目标日的课), 永不灰
        if dateHasTransfer { return false }

        // 法定节假日（独立开关）
        if greyHoliday && holidays.contains(date) { return true }

        // 周末; 补班日(transfer_workday)是"周末但要上课"的日子, 开关开时豁免
        if greyWeekend && isWeekend(date) {
            if ignoreWorkday && workdays.contains(date) { return false }
            return true
        }
        return false
    }
}

// MARK: - HolidayRangeOps (← object HolidayRangeOps)

/** 网络段 + 用户段合并纯函数集(无网络) */
enum HolidayRangeOps {
    /// 用户删除段的哨兵类型: 该段整体抹掉 ← REMOVED
    static let REMOVED = "removed"

    static func newId() -> String {
        let bytes = (0..<4).map { _ in UInt8.random(in: 0...255) }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /**
     * 网络逐日条目 → 连续段。按「name+type 相同 + 日期连续」聚合;
     * 输入乱序没关系(先排序); 返回按 startDate 排序。← aggregateSegments
     */
    static func aggregateSegments(_ entries: [HolidayEntry]) -> [HolidayRange] {
        let sorted = entries.sorted { $0.date < $1.date }
        var result: [HolidayRange] = []
        for e in sorted {
            if let last = result.last,
               last.name == e.name && last.type == e.type,
               let nextDay = Calendar.gregorianCST.date(byAdding: .day, value: 1, to: last.endDate),
               nextDay == e.date {
                result[result.count - 1] = HolidayRange(
                    id: last.id, name: last.name,
                    startDate: last.startDate, endDate: e.date,
                    type: last.type, sourceKey: last.sourceKey
                )
            } else {
                result.append(HolidayRange(id: newId(), name: e.name, startDate: e.date, endDate: e.date, type: e.type, sourceKey: nil))
            }
        }
        return result
    }

    /// 合并结果: active=生效段, removed=被用户删除的网络段(展示在"已删除"区块) ← MergeResult
    struct MergeResult {
        let active: [HolidayRange]
        let removed: [HolidayRange]
    }

    private static func sourceKeyOf(_ type: String, _ date: Date) -> String {
        "\(type == HolidayManager.TYPE_TRANSFER_WORKDAY ? "workday" : "holiday"):\(HolidayManager.dateFormat.string(from: date))"
    }

    /**
     * 网络条目 + 用户覆盖段 → 合并。按 overrides 顺序应用:
     * sourceKey 命中网络段(sourceKey==nil 的段)→ 整段抹除; 同 sourceKey 的先前用户段被后者替换。← mergeSegments
     * removed 型只在其 sourceKey 确实对应网络段时进入 removed 列表。
     */
    static func mergeSegments(_ network: [HolidayEntry], _ overrides: [HolidayRange]) -> MergeResult {
        var active = aggregateSegments(network)
        var removed: [HolidayRange] = []
        let networkKeys = Set(active.map { sourceKeyOf($0.type, $0.startDate) })

        for ov in overrides {
            if let sk = ov.sourceKey {
                active.removeAll {
                    ($0.sourceKey == nil && sourceKeyOf($0.type, $0.startDate) == sk) ||
                        ($0.sourceKey == sk && $0.id != ov.id)
                }
            }
            if ov.type == REMOVED {
                if let sk = ov.sourceKey, networkKeys.contains(sk) { removed.append(ov) }
            } else {
                active.append(ov)
            }
        }
        return MergeResult(active: active.sorted { $0.startDate < $1.startDate }, removed: removed)
    }

    /// 生效段 → (holidays, workdays) 集合, 供灰显判定 ← toSets
    static func toSets(_ active: [HolidayRange]) -> (holidays: Set<Date>, workdays: Set<Date>) {
        var holidays: Set<Date> = []
        var workdays: Set<Date> = []
        for seg in active {
            var d = seg.startDate
            while d <= seg.endDate {
                if seg.type == HolidayManager.TYPE_TRANSFER_WORKDAY { workdays.insert(d) } else { holidays.insert(d) }
                guard let next = Calendar.gregorianCST.date(byAdding: .day, value: 1, to: d) else { break }
                d = next
            }
        }
        return (holidays, workdays)
    }

    /// 用户段列表 → JSON 数组 ← encodeOverrides
    static func encodeOverrides(_ overrides: [HolidayRange]) -> String {
        let arr: [[String: Any]] = overrides.map { ov in
            var dict: [String: Any] = [
                "id": ov.id,
                "name": ov.name,
                "start": HolidayManager.dateFormat.string(from: ov.startDate),
                "end": HolidayManager.dateFormat.string(from: ov.endDate),
                "type": ov.type
            ]
            dict["sourceKey"] = ov.sourceKey as Any?
            return dict
        }
        guard let data = try? JSONSerialization.data(withJSONObject: arr),
              let s = String(data: data, encoding: .utf8) else { return "[]" }
        return s
    }

    /// JSON → 用户段列表(坏行跳过, start>end 跳过, 类型不认跳过, 解析失败返回空) ← decodeOverrides
    static func decodeOverrides(_ json: String) -> [HolidayRange] {
        guard let data = json.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        var result: [HolidayRange] = []
        for obj in arr {
            guard let id = obj["id"] as? String, !id.isBlank else { continue }
            let name = obj["name"] as? String ?? ""
            guard let startStr = obj["start"] as? String,
                  let start = HolidayManager.dateFormat.date(from: startStr) else { continue }
            guard let endStr = obj["end"] as? String,
                  let end = HolidayManager.dateFormat.date(from: endStr) else { continue }
            let type = obj["type"] as? String ?? ""
            if type != HolidayManager.TYPE_PUBLIC_HOLIDAY &&
                type != HolidayManager.TYPE_TRANSFER_WORKDAY && type != REMOVED { continue }
            if end < start { continue }
            let sk: String?
            if obj["sourceKey"] == nil {
                sk = nil
            } else {
                let raw = obj["sourceKey"] as? String ?? ""
                sk = raw.isBlank ? nil : raw
            }
            result.append(HolidayRange(id: id, name: name, startDate: start, endDate: end, type: type, sourceKey: sk))
        }
        return result
    }
}

// MARK: - Calendar/Date 辅助

extension Calendar {
    /// 固定 CST(与 Android 端 LocalDate 语义对齐 — 无 DST 漂移, 日期比较稳定)
    static let gregorianCST: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        return c
    }()
}

extension Date {
    var year: Int { Calendar.gregorianCST.component(.year, from: self) }
}

extension String {
    var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
