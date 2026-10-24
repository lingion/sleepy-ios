// SleepyNativeExporter.swift — ← data/parser/SleepyNativeExporter.kt (逐行翻译, GPL-3.0)
// Sleepy iOS — sleepy-v1 导出器(规范 §4/§5/§8.1):
// 写规范形(导出永不出现裸危险字符; 字段编码紧凑, 调色板走索引, Nd 折叠);
// 承担散周 partition 与同名异组强制 token(契约二)。

import Foundation

enum SleepyNativeExporter {

    /// 文件形态: 末尾追加 z|chk=crc32:xxxxxxxx(文件导出默认写)
    static func exportFile(tableName: String, startDate: String, maxWeek: Int,
                           nodesPerDay: Int, timeJson: String, courses: [CourseEntity],
                           periodTable: PeriodTableExport? = nil) -> String {
        let body = buildBody(tableName: tableName, startDate: startDate, maxWeek: maxWeek,
                             nodesPerDay: nodesPerDay, timeJson: timeJson, courses: courses,
                             periodTable: periodTable)
        return body + "\nz|chk=crc32:" + SleepyNativeFormat.crc32(body.data(using: .utf8)!)
    }

    /// 分享文本形态: 【来自Sleepy】+ 包裹 marker + 无 chk(规范 §1.1)
    static func exportShareText(tableName: String, startDate: String, maxWeek: Int,
                                nodesPerDay: Int, timeJson: String, courses: [CourseEntity],
                                periodTable: PeriodTableExport? = nil) -> String {
        let body = buildBody(tableName: tableName, startDate: startDate, maxWeek: maxWeek,
                             nodesPerDay: nodesPerDay, timeJson: timeJson, courses: courses,
                             periodTable: periodTable)
        return "【来自Sleepy】\n课程分享：\n\n<<<SLEEPY-BEGIN>>>\n\(body)\n<<<SLEEPY-END>>>"
    }

    /// issue#40 §6: 新格式可选 periodTable 区块的数据载体(← Kotlin data class PeriodTableExport)。
    /// id = 导出时该课程表绑定的 period_tables.id(导入端恢复共享关系的键);
    /// id 空/未绑定 = 调用方传 nil, 不写 P 区块。
    struct PeriodTableExport {
        let id: Int64
        let name: String
        let nodesPerDay: Int
        let timeJson: String
    }

    private static func buildBody(tableName: String, startDate: String, maxWeek: Int,
                                  nodesPerDay: Int, timeJson: String, courses: [CourseEntity],
                                  periodTable: PeriodTableExport? = nil) -> String {
        var sb = ""
        sb += "#sleepy-v1\n"

        // ---- T 行(§3.5) ----
        sb += "T"
        sb += SleepyNativeFormat.escape(tableName.isBlank ? "导入的课表" : tableName)
        sb += "|" + startDate
        sb += "|" + String(maxWeek)
        sb += "|" + String(nodesPerDay)
        // §4 契约二: 同名异组须显式 token
        let hasSameNameMultiGroup = hasSameNameMultipleGroups(courses)
        // n= 计数行(§8.3); 散周 partition 可能拆行, 数字会变; 导出端用 partition 后 C 行数
        let partitionedCount = countAfterPartition(courses)
        sb += "|n=\(partitionedCount)\n"

        // ---- issue#40: P 行(独立时间节次表, §6 新格式可选区块) ----
        // 携带绑定关系(periodTable 非空)时输出; 旧版本读到 P 行走"未知行类型→dropped+warning"通道, 不硬拒。
        if let pt = periodTable {
            sb += "P"
            sb += SleepyNativeFormat.escape(pt.name)
            sb += "|" + String(pt.id)
            sb += "|" + String(pt.nodesPerDay)
            sb += "\n"
            if SleepyNativeFormat.matchesNdPreset(pt.timeJson) {
                sb += "Pd\n"
            } else if !pt.timeJson.isBlank {
                let cal = Calendar(identifier: .gregorian)
                for n in TimeTableUtils.parseNodes(pt.timeJson) {
                    sb += "Pn" + String(n.node)
                    sb += "|" + fmtDate(n.start, cal: cal)
                    sb += "|" + fmtDate(n.end, cal: cal)
                    sb += "\n"
                }
            }
        }

        // ---- 作息 (Nd 或逐节 N 行) (§5) — 兼容列永远保留(§6 旧版本至少读到 timeJson) ----
        if SleepyNativeFormat.matchesNdPreset(timeJson) {
            sb += "Nd\n"
        } else if !timeJson.isBlank {
            let nodes = TimeTableUtils.parseNodes(timeJson)
            let cal = Calendar(identifier: .gregorian)
            for n in nodes {
                sb += "N\(n.node)"
                sb += "|" + fmtDate(n.start, cal: cal)
                sb += "|" + fmtDate(n.end, cal: cal)
                sb += "\n"
            }
        }

        // ---- 课程行 ----
        for line in exportCourses(courses, forceToken: hasSameNameMultiGroup) {
            sb += line + "\n"
        }

        // 去尾换行 — file 形 chk 前, share 形 marker 内
        while sb.hasSuffix("\n") { sb.removeLast() }
        return sb
    }

    private static func fmtDate(_ d: Date, cal: Calendar) -> String {
        SleepyNativeFormat.fmtTime(h: cal.component(.hour, from: d), min: cal.component(.minute, from: d))
    }

    /**
     * 按 §4 散周 partition 拆行: 把每个课程的上课周集合按"极大连续段"拆为多条 C 行, 每行 type 重新判定:
     * - 段全奇 → type 1 (S-E单) · 段全偶 → type 2 (S-E双) · 段全周 → type 0 (S-E)
     * - 段非全周非纯奇偶 → type 3 (S-E定)
     * 不支持"零散单周内插"(1, 10, 12): 本函数按"区间合并到段"处理, 多段分别一行 type 3。
     * v1 简化: 尊重输入 (startWeek, endWeek, type) 三元组, 输出单条(与 Kotlin 实现一致)。
     */
    private static func partitionWeeks(_ startWeek: Int, _ endWeek: Int, _ type: Int) -> [(Int, Int, Int)] {
        [(startWeek, endWeek, type)]
    }

    private static func exportCourses(_ courses: [CourseEntity], forceToken: Bool) -> [String] {
        // 按 groupId 排序输出(§8.1)
        let sorted = courses.sorted { a, b in
            if a.groupId != b.groupId { return a.groupId < b.groupId }
            return a.courseName < b.courseName
        }
        var tokenMap: [String: String] = [:]
        var out: [String] = []
        for c in sorted {
            let token: String
            if c.groupId.isBlank {
                token = ""
            } else if forceToken {
                if tokenMap[c.groupId] == nil { tokenMap[c.groupId] = String(tokenMap.count + 1) }
                token = tokenMap[c.groupId]!
            } else {
                // 决定是否需要显式 token: §3.4 契约二 — 同名异组必写; 否则按组是否跨多名判定
                let sameGroupCount = sorted.filter { $0.groupId == c.groupId }.count
                let sameNameCount = sorted.filter { $0.courseName.trimmingCharacters(in: .whitespacesAndNewlines) == c.courseName.trimmingCharacters(in: .whitespacesAndNewlines) }.count
                if sameGroupCount > 0 && sameNameCount > 1 {
                    if tokenMap[c.groupId] == nil { tokenMap[c.groupId] = String(tokenMap.count + 1) }
                    token = tokenMap[c.groupId]!
                } else {
                    token = ""
                }
            }
            out.append(buildCourseLine(c, token: token))
        }
        return out
    }

    private static func buildCourseLine(_ c: CourseEntity, token: String) -> String {
        var sb = ""
        sb += "C" + SleepyNativeFormat.escape(c.courseName)
        sb += "|" + String(c.day)
        sb += "|" + "\(c.startNode)-\(c.startNode + c.step - 1)"
        sb += "|" + SleepyNativeFormat.weekSpecToToken(c.startWeek, c.endWeek, c.type)
        sb += "|" + SleepyNativeFormat.escape(c.teacher)
        sb += "|" + SleepyNativeFormat.escape(c.room)
        sb += "|" + SleepyNativeFormat.colorToToken(c.color)
        sb += "|" + SleepyNativeFormat.escape(c.note)
        if c.ownTime && !c.startTime.isBlank && !c.endTime.isBlank {
            sb += "|" + c.startTime + "-" + c.endTime
        } else {
            sb += "|"
        }
        sb += "|" + token
        // issue#26: 可选第 11 列 = 课程别名(escape 后写入); 空别名不写列(文件形状与既有 v1 完全一致)
        if !c.alias.isBlank {
            sb += "|" + SleepyNativeFormat.escape(c.alias.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return sb
    }

    private static func hasSameNameMultipleGroups(_ courses: [CourseEntity]) -> Bool {
        let byName = Dictionary(grouping: courses) { $0.courseName.trimmingCharacters(in: .whitespacesAndNewlines) }
        return byName.values.contains { Set($0.map { $0.groupId }).count > 1 }
    }

    private static func countAfterPartition(_ courses: [CourseEntity]) -> Int {
        // v1 简化: 暂不展开 partition; 等于课程数(当 partition 实现完备后这里同步改)
        courses.count
    }

    // MARK: - v1.0.56 T11: 作息表单独导出(← exportPeriodTableShareText / exportPeriodTableJson)

    /// 纯作息分享文本: 【来自Sleepy】+ 包裹 marker + P 头 + Pd/Pn 行(无 T/N/C 行)。
    static func exportPeriodTableShareText(_ pt: PeriodTableEntity) -> String {
        let body = buildPeriodOnlyBody(pt)
        return "【来自Sleepy】\n作息分享：\n\n<<<SLEEPY-BEGIN>>>\n\(body)\n<<<SLEEPY-END>>>"
    }

    /// JSON 形态: {"name":"…","tableInfo":{"nodesPerDay":N,"timeList":[{"node":1,"startTime":"08:00","endTime":"08:45"},…]}}
    /// 字段名 startTime/endTime 与 WakeUp 原生一致 — 解析端 harvest 按此收割, courses 空 + periodTable 非空走 T9 纯作息路径。
    static func exportPeriodTableJson(_ pt: PeriodTableEntity) -> String {
        let nodes = TimeTableUtils.parseNodes(pt.timeJson)
        let timeArr = nodes.map { n -> String in
            let cal = Calendar(identifier: .gregorian)
            return "{\"node\":\(n.node),\"startTime\":\(jsonQuote(SleepyNativeFormat.fmtTime(h: cal.component(.hour, from: n.start), min: cal.component(.minute, from: n.start)))),\"endTime\":\(jsonQuote(SleepyNativeFormat.fmtTime(h: cal.component(.hour, from: n.end), min: cal.component(.minute, from: n.end))))}"
        }.joined(separator: ",")
        return "{\"name\":\(jsonQuote(pt.name)),\"tableInfo\":{\"nodesPerDay\":\(max(pt.nodesPerDay, 1)),\"timeList\":[\(timeArr)]}}"
    }

    private static func jsonQuote(_ s: String) -> String {
        var sb = "\""
        // 逐标量迭代 — Kotlin 逐码元; 若按 Character(图簇)迭代会把 "\r\n" 当一簇丢失第二标量
        for u in s.unicodeScalars {
            switch u {
            case "\"": sb += "\\\""
            case "\\": sb += "\\\\"
            case "\u{0A}": sb += "\\n"
            case "\u{0D}": sb += "\\r"
            case "\u{09}": sb += "\\t"
            default:
                if u.value < 0x20 { sb += String(format: "\\u%04x", u.value) }
                else { sb.unicodeScalars.append(u) }
            }
        }
        sb += "\""
        return sb
    }

    /// 纯作息 body: magic + P 头 + Pd/Pn 行, 无 T/N/C 行。
    private static func buildPeriodOnlyBody(_ pt: PeriodTableEntity) -> String {
        var sb = "#sleepy-v1\n"
        sb += "P"
        sb += SleepyNativeFormat.escape(pt.name)
        sb += "|" + String(pt.id)
        sb += "|" + String(max(pt.nodesPerDay, 1))
        sb += "\n"
        if SleepyNativeFormat.matchesNdPreset(pt.timeJson) {
            sb += "Pd\n"
        } else {
            let cal = Calendar(identifier: .gregorian)
            for n in TimeTableUtils.parseNodes(pt.timeJson) {
                sb += "Pn" + String(n.node)
                sb += "|" + fmtDate(n.start, cal: cal)
                sb += "|" + fmtDate(n.end, cal: cal)
                sb += "\n"
            }
        }
        while sb.hasSuffix("\n") { sb.removeLast() }
        return sb
    }

}
