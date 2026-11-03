// DailyAgenda.swift — ← widget/notification/DailyAgenda.kt (v1.0.62 B5)
// 多课表合并「每日议程」: 跨表同名同刻的课合并为一条(来源全保留), 通知文案与
// 议程页共用同一份构建结果。纯 Foundation 逻辑(三 target 共源编译)。

import Foundation

/// ← DailyAgendaItem: 一次合并后的议程条目(sources = 各表来源, 至少 1 条)
/// sources 为 var ← 原 buildDailyAgenda 的 `groups[index] = copy(sources = ... + entry)`:
/// 合并命中时向既有组追加来源(struct 值语义下 let 不可变, 原版本 的 copy-with 是重建)。
struct DailyAgendaItem {
    var sources: [DailyScheduleEntry]
    /// 解析成功的结束时间(当日分钟数) ← 原版本 endTime: LocalTime?
    let endTimeMinutes: Int?

    var first: DailyScheduleEntry { sources[0] }

    /// 来源课表名串联(空名回落 unknownTable) ← sourceNames
    func sourceNames(unknownTable: String) -> String {
        sources.map { $0.table.name.isBlank ? unknownTable : $0.table.name }
            .joined(separator: " · ")
    }

    /// "08:00" / "08:00–09:00" / unknownTime ← timeText (LocalTime.toString 投影)
    func timeText(unknownTime: String) -> String {
        guard let start = first.startTimeMinutes else { return unknownTime }
        let end = endTimeMinutes.map { "–" + DailyAgendaTime.format($0) } ?? ""
        return DailyAgendaTime.format(start) + end
    }

    /// 通知单行文案: "08:00 · 数学 · 101〔课表A／课表B〕" ← notificationLine
    func notificationLine(unknownTime: String, unknownRoom: String,
                          sourceLabels: [Int64: String]) -> String {
        let start = first.startTimeMinutes.map { DailyAgendaTime.format($0) } ?? unknownTime
        let room = first.course.room.isBlank ? unknownRoom : first.course.room
        let source = sources.compactMap { sourceLabels[$0.table.id] }.joined(separator: "／")
        return "\(start) · \(first.course.courseName) · \(room)" +
            (source.isEmpty ? "" : "〔\(source)〕")
    }
}

/// ← DailyAgenda
struct DailyAgenda {
    let date: Date
    let items: [DailyAgendaItem]
    /// 参与来源标注的课表全集(= 开启提醒的全部表, 含当日无课的) ← sourceTables
    var sourceTables: [TimeTableEntity] = []

    /// 通知来源标签表 ← notificationSources
    func notificationSources(unknownTable: String) -> [Int64: String] {
        notificationSourceLabels(sourceTables, unknownTable)
    }

    /// 贡献课表数(按条目来源去重) ← tableCount
    var tableCount: Int {
        Set(items.flatMap { $0.sources.map { $0.table.id } }).count
    }

    /// 预览截断 ← preview(limit=6): (可见条目, 隐藏数)
    func preview(limit: Int = 6) -> ([DailyAgendaItem], Int) {
        precondition(limit > 0)
        return (Array(items.prefix(limit)), max(items.count - limit, 0))
    }
}

private struct AgendaIdentity: Hashable {
    // date 恒等于构建入参(单日构建), 不参与分桶 ← 原版本 Identity 含 date 但同构建恒同值
    let start: Int
    let end: Int
    let name: String
    let room: String
    let teacher: String
}

/// ← buildDailyAgenda: 只合并「不同表中完全同刻同名同室同师」的出现;
/// 时间不完整(起/终任一不可解析或 end≤start)或名称/教室空白 → 永不参与合并。
func buildDailyAgenda(
    date: Date,
    summary: DailyScheduleSummary,
    sourceTables: [TimeTableEntity] = []
) -> DailyAgenda {
    // 原版本 默认参 = summary.entries.map { it.table }.distinctBy { it.id }
    let effectiveSourceTables: [TimeTableEntity] = sourceTables.isEmpty
        ? summary.entries.map { $0.table }.reduce([]) { acc, t in
            acc.contains(where: { $0.id == t.id }) ? acc : acc + [t]
        }
        : sourceTables

    var groups: [DailyAgendaItem] = []
    var identities: [AgendaIdentity: [Int]] = [:]
    for entry in summary.entries {
        let course = entry.course
        // ← end: ownTime → 严格解析 endTime(畸形=null); 否则取末节点的节点终时
        let endMinutes: Int?
        if course.ownTime || course.isIrregularTime {
            endMinutes = TimeTableUtils.hmMinutes(course.endTime)
        } else {
            endMinutes = TimeTableUtils
                .parseNodes(entry.table.timeJson)
                .first(where: { $0.node == course.startNode + course.step - 1 })
                .map { DailyAgendaTime.minutes(of: $0.end) }
        }
        let start = entry.startTimeMinutes
        let identity: AgendaIdentity?
        if let start, let endMinutes, endMinutes > start,
           !course.courseName.isBlank, !course.room.isBlank {
            identity = AgendaIdentity(start: start, end: endMinutes,
                                      name: course.courseName, room: course.room,
                                      teacher: course.teacher)
        } else {
            identity = nil
        }
        // 合并目标 = 同 identity 且该组尚未包含同表来源(同表多次出现永不合并)
        let index = identity.flatMap { identities[$0] }?.first { idx in
            !groups[idx].sources.contains(where: { $0.table.id == entry.table.id })
        }
        if let index {
            groups[index].sources.append(entry)
        } else {
            if let identity {
                identities[identity, default: []].append(groups.count)
            }
            groups.append(DailyAgendaItem(sources: [entry], endTimeMinutes: endMinutes))
        }
    }
    return DailyAgenda(date: date, items: groups, sourceTables: effectiveSourceTables)
}

/// ← notificationSourceLabels: 展示用中段省略号 — 两端保留, 且最终标签必须两两可区分。
/// >16 码点 → 前 8 + "…" + 后 7; 重名循环追加 " #id" 直至全唯一。
func notificationSourceLabels(
    _ tables: [TimeTableEntity], _ unknownTable: String
) -> [Int64: String] {
    var distinct: [TimeTableEntity] = []
    for t in tables where !distinct.contains(where: { $0.id == t.id }) { distinct.append(t) }
    if distinct.count <= 1 { return [:] }

    var labels: [Int64: String] = [:]
    for table in distinct {
        let name = table.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? unknownTable : table.name
        // ← 原版本 name.codePoints(): Swift unicode scalar ≙ Java code point
        // (代理对成对计 1, emoji 计 1 — 与 原 codePointCount 同口径)
        // ← 原版本 String(points, 0, 8) / String(points, size-7, 7): [UnicodeScalar] 切片
        //   不能直接 String.init, 必须经 UnicodeScalarView 重组 (首尾各保 8/7 个码点)。
        let points = Array(name.unicodeScalars)
        labels[table.id] = points.count <= 16
            ? name
            : String(String.UnicodeScalarView(points[0..<8])) + "…"
                + String(String.UnicodeScalarView(points[(points.count - 7)...]))
    }
    // 重名消歧循环 ← while (labels.values.toSet().size != labels.size)
    while Set(labels.values).count != labels.count {
        var counts: [String: Int] = [:]
        for v in labels.values { counts[v, default: 0] += 1 }
        labels = Dictionary(uniqueKeysWithValues: labels.map { id, name in
            (id, (counts[name] ?? 0) > 1 ? "\(name) #\(id)" : name)
        })
    }
    return labels
}

/// ← dailyNotificationLifetime: 相对"今天/明天"文案在下一个本地午夜过期(含 DST 日)。
/// 返回毫秒数, 下限 1ms。iOS 无 setTimeoutAfter 等价物(平台缺口, 见 NotificationScheduler
/// 注释) — 纯函数保留与 原版本 同口径, 由单测锁定行为。
/// (本仓库无 Kotlin coerceAtLeast 扩展, 就地 max(...) 同义 — 见 JwWiseduParser 同款处理)
func dailyNotificationLifetime(now: Date, calendar: Calendar = DateUtils.isoCalendar) -> Int64 {
    let nextMidnight = calendar.startOfDay(
        for: calendar.date(byAdding: .day, value: 1, to: now) ?? now)
    return max(Int64((nextMidnight.timeIntervalSince(now) * 1000).rounded()), 1)
}
