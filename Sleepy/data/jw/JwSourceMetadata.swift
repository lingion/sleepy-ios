// Android v1.0.64 source contracts. Presence is preserved independently of user edits.
import Foundation
import CoreFoundation
import SwiftSoup

enum JwSgSourceMetadata {
    static func capture(_ source: String, _ type: String?) throws -> String {
        guard type == JwProtocol.TYPE_SG_ASSET, source.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") else { return "" }
        guard let root = object(source), root["sleepySgAsset"] as? Bool == true else { return "" }
        guard let config = root["config"] as? [String: Any] else { throw JwParseError(message: "Invalid source timetable metadata") }
        var metadata: [String: Any] = ["schemaVersion": 1, "config": config]
        if let adapter = root["adapter"] { metadata["adapter"] = adapter }
        let json = try stringify(metadata)
        guard read(json) != nil else { throw JwParseError(message: "Invalid source timetable metadata") }
        return json
    }

    static func read(_ json: String) -> [String: Any]? {
        guard let root = object(json), strictInteger(root["schemaVersion"]) == 1,
              let config = root["config"] as? [String: Any] else { return nil }
        if let value = root["adapter"] {
            guard let adapter = value as? [String: Any] else { return nil }
            for key in ["schoolId", "adapterId", "name", "category", "importUrl"] where adapter[key] != nil {
                guard adapter[key] is String else { return nil }
            }
        }
        if let date = config["semesterStartDate"], !(date is NSNull) {
            guard let text = date as? String, JwSourceCalendar.canonicalDate(text) == text else { return nil }
        }
        for (key, lower, upper) in [("semesterTotalWeeks", 1, 366), ("firstDayOfWeek", 1, 7),
                                    ("defaultClassDuration", 1, 9_007_199_254_740_991),
                                    ("defaultBreakDuration", 0, 9_007_199_254_740_991)] where config[key] != nil {
            guard let value = strictInteger(config[key]), (lower...upper).contains(value) else { return nil }
        }
        return root
    }

    static func object(_ json: String) -> [String: Any]? {
        guard let data = json.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
    static func stringify(_ value: Any) throws -> String {
        String(data: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), encoding: .utf8) ?? ""
    }
    static func strictInteger(_ value: Any?) -> Int? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
              !["f", "d"].contains(String(cString: n.objCType)) else { return nil }
        return Int(n.stringValue)
    }
}

enum JwSourceCalendar {
    private static var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
    static func parseDate(_ text: String?) -> Date? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), text.range(of: #"^[0-9]{4}-[0-9]{1,2}-[0-9]{1,2}$"#, options: .regularExpression) != nil else { return nil }
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, parts[0] > 0, let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else { return nil }
        let check = calendar.dateComponents([.year, .month, .day], from: date)
        return check.year == parts[0] && check.month == parts[1] && check.day == parts[2] ? date : nil
    }
    static func stamp(_ date: Date) -> String {
        let p = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", p.year!, p.month!, p.day!)
    }
    static func canonicalDate(_ text: String) -> String? { parseDate(text).map(stamp) }
    static func monday(_ text: String) -> String? {
        guard let date = parseDate(text) else { return nil }
        let offset = (calendar.component(.weekday, from: date) + 5) % 7
        return calendar.date(byAdding: .day, value: -offset, to: date).map(stamp)
    }
    static func resolveWeekCount(_ source: String, _ type: String?, schoolName: String = "") -> Int {
        if type == JwProtocol.TYPE_NWPU_POST { return 22 }
        if type == "wist" && schoolName.contains("武汉船舶职业技术学院") { return 20 }
        if type == JwProtocol.TYPE_THU, let semester = JwThuCapturePayload.semesterJson(source), let root = JwSgSourceMetadata.object(semester) { return jw1064Integer(root["weekCount"]) ?? 16 }
        guard let root = JwSgSourceMetadata.object(source) else { return 0 }
        var value: Any?
        switch type {
        case JwProtocol.TYPE_SG_ASSET:
            if root["sleepySgAsset"] as? Bool == true { value = (root["config"] as? [String: Any])?["semesterTotalWeeks"] }
        case "ccibe": value = (root["calendar"] as? [String: Any])?["allWeek"]
        case JwProtocol.TYPE_THU: value = (root["semesterData"] as? [String: Any])?["weekCount"]
        case JwProtocol.TYPE_CF_NEW:
            guard root["sleepyCfNtss"] as? Bool == true, let weeks = root["requestedWeeks"] as? [Any], !weeks.isEmpty else { return 0 }
            let parsed = weeks.compactMap { Int(String(describing: $0)) }
            guard parsed.count == weeks.count, parsed.allSatisfy({ (1...366).contains($0) }) else { return 0 }
            return parsed.max() ?? 0
        default: break
        }
        guard let value, let count = Int(String(describing: value)), (1...366).contains(count) else { return 0 }
        return count
    }
    static func resolveStartDate(_ source: String, _ type: String?, capturedDate: String) -> String {
        let root = JwSgSourceMetadata.object(source)
        if type == JwProtocol.TYPE_SG_ASSET, root?["sleepySgAsset"] as? Bool == true,
           let config = root?["config"] as? [String: Any], config.keys.contains("semesterStartDate") {
            return (config["semesterStartDate"] as? String).flatMap(monday) ?? ""
        }
        if type == "shsmu" { return root.flatMap(JwShsmuCaptureCalendar.resolve).map(stamp) ?? "" }
        let declared: String?
        switch type {
        case "ccibe": declared = (root?["calendar"] as? [String: Any])?["startTime"] as? String
        case "cppu": declared = root?["startDate"] as? String
        default: declared = nil
        }
        return declared.flatMap(monday) ?? monday(capturedDate) ?? ""
    }
}

enum JwSourcePeriods {
    static func confirmationRows(courseMaxNode: Int, sourcePeriods: [(Int, String, String)]) -> [(Int, String, String)] {
        let map = Dictionary(sourcePeriods.map { ($0.0, ($0.1, $0.2)) }, uniquingKeysWith: { _, b in b })
        let count = max(courseMaxNode, sourcePeriods.map { $0.0 }.max() ?? 0)
        guard count > 0 else { return [] }
        return (1...count).map { ($0, map[$0]?.0 ?? "", map[$0]?.1 ?? "") }
    }
    static func resolve(_ source: String, _ type: String?, schoolName: String, captured: [(Int, String, String)]) -> [(Int, String, String)] {
        if !captured.isEmpty { return captured }
        if type == JwProtocol.TYPE_EAMS5 && schoolName.contains("安徽大学") { return JwAhuSourcePeriods.resolve(source) }
        if [JwProtocol.TYPE_ECUPL_SCRIPT, JwProtocol.TYPE_ECUPL, JwProtocol.TYPE_ECUPL_SUPER, JwProtocol.TYPE_CLASSIC_EAMS].contains(type ?? "") {
            let annualSelected = [JwProtocol.TYPE_ECUPL, JwProtocol.TYPE_ECUPL_SUPER].contains(type ?? "") && source.contains("new TaskActivity(") && source.contains("table0.marshalTable") && source.range(of: #"(?i)<table[^>]*id=[\"']?listTable"#, options: .regularExpression) != nil && !((try? JwEcuplParser(source).generateCourseList()) ?? []).isEmpty
            if !annualSelected { let rows = JwEcuplScriptParser.sourcePeriods(source); if !rows.isEmpty { return rows } }
        }
        if type == JwProtocol.TYPE_ECUPL || type == JwProtocol.TYPE_ECUPL_SUPER { return JwEcuplSourcePeriods.resolve(source) }
        if type == JwProtocol.TYPE_NWPU_POST { return JwNwpuPostSourceMetadata.periods(source) }
        if type == "shu2024" { return JwUndergradBHtmlParser.shuPeriods }
        if type == "shsmu" { return JwUndergradClockParser.shsmuPeriods.enumerated().map { ($0.offset + 1, $0.element.0, $0.element.1) } }
        let times: String
        switch type {
        case "shtu_post", "shtu_post_2024": times = "08:15-09:00 09:10-09:55 10:15-11:00 11:10-11:55 13:00-13:45 13:55-14:40 15:00-15:45 15:55-16:40 16:50-17:35 18:00-18:45 18:55-19:40 19:50-20:35 20:45-21:30"
        case "wist" where schoolName.contains("武汉船舶职业技术学院"):
            times = "08:10-08:55 09:05-09:50 10:10-10:55 11:05-11:50 12:30-13:10 13:20-14:00 14:00-14:45 14:55-15:40 16:00-16:45 16:55-17:40 19:00-19:45 19:55-20:40"
        case "qz_fspt": times = "08:40-09:20 09:25-10:05 10:25-11:05 11:10-11:50 14:00-14:40 14:45-15:25 15:45-16:25 16:30-17:10 19:00-19:40 19:45-20:25 20:35-21:15 21:20-22:00"
        case "gdbh": times = "08:25-09:10 09:20-10:05 10:25-11:10 11:20-12:05 15:00-15:45 15:55-16:40 17:00-17:45 17:55-18:40 19:40-20:25 20:35-21:20"
        case "fstvc" where schoolName == "福州软件职业技术学院":
            guard let array = try? JSONSerialization.jsonObject(with: Data(source.utf8)) as? [[String: Any]] else { return [] }
            let classes = array.compactMap { $0["skbjmc"] as? String }.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            let majors = ["软件技术", "移动互联应用技术", "信息安全技术应用", "智能产品开发与应用", "人工智能技术应用", "建设工程管理", "建筑室内设计", "工程造价", "建筑智能化工程技术", "智能建造技术", "现代通信技术", "现代移动通信技术", "智能互联网络技术", "网络规划与优化技术", "大数据技术", "区块链技术应用", "云计算技术应用", "工业软件开发技术"]
            let batches = Set(classes.map { name in majors.contains { name.contains($0) } })
            guard batches.count == 1, let first = batches.first else { return [] }
            let morning = first ? "08:25-09:10 09:15-10:00 10:10-10:55 11:00-11:45" : "08:45-09:30 09:35-10:20 10:30-11:15 11:20-12:05"
            times = morning + " 13:50-14:35 14:40-15:25 15:35-16:20 16:25-17:10 18:30-19:15 19:25-20:10 20:20-21:05 21:15-22:00"
        case "sues": times = "08:15-08:55 08:55-09:35 09:55-10:40 10:40-11:35 11:35-12:20 13:20-14:00 14:00-14:40 15:00-15:40 15:40-16:20 16:35-17:15 17:15-17:55 18:10-18:50 18:50-19:30 19:35-20:15 20:20-21:00"
        default: return []
        }
        return rows(times)
    }
    static func rows(_ times: String) -> [(Int, String, String)] {
        times.split(separator: " ").enumerated().compactMap { index, item in
            let pair = item.split(separator: "-"); guard pair.count == 2 else { return nil }
            return (index + 1, String(pair[0]), String(pair[1]))
        }
    }
}

enum JwNwpuPostSourceMetadata {
    static func periods(_ source: String, month: Int = Calendar.current.component(.month, from: Date())) -> [(Int, String, String)] {
        guard let doc = try? SwiftSoup.parse(source), let table = try? doc.select("#sample-table-1").first(),
              let headers = try? table.select("thead tr th").array(),
              let column = headers.firstIndex(where: { ((try? $0.text()) ?? "").contains("上课时间") }),
              let rows = try? table.select("tbody tr").array() else { return [] }
        let times = rows.compactMap { row -> String? in
            guard let cells = try? row.select("td").array(), column < cells.count else { return nil }
            return try? cells[column].text()
        }
        guard !times.isEmpty else { return [] }
        let changan = times.filter { $0.contains("长安") }.count
        let youyi = times.filter { !$0.contains("长安") && $0.contains("友谊") }.count
        let clocks: String
        if changan >= youyi { clocks = "08:30-09:15 09:25-10:10 10:30-11:15 11:25-12:10 12:20-13:05 13:05-13:50 14:00-14:45 14:55-15:40 16:00-16:45 16:55-17:40 19:00-19:45 19:55-20:40 20:40-21:25" }
        else if (5...9).contains(month) { clocks = "08:00-08:50 09:00-09:50 10:10-11:00 11:10-12:00 12:10-13:10 13:20-14:20 14:30-15:20 15:30-16:20 16:40-17:30 17:40-18:30 19:30-20:20 20:30-21:20 20:40-21:25" }
        else { clocks = "08:00-08:50 09:00-09:50 10:10-11:00 11:10-12:00 12:10-13:00 13:10-14:00 14:00-14:50 15:00-15:50 16:10-17:00 17:10-18:00 19:00-19:50 20:00-20:50 20:50-21:25" }
        return JwSourcePeriods.rows(clocks)
    }
}

enum JwSourceTableName {
    static func resolve(_ source: String, _ type: String?, schoolName: String) -> String? {
        if type == "shu2024" { return JwUndergradBHtmlParser(source, protocolType: "shu2024").tableName() }
        guard let document = try? SwiftSoup.parse(source) else { return nil }
        if type == JwProtocol.TYPE_NWPU_POST, (try? document.select("#sample-table-1").first()) != nil,
           let option = try? document.select("#xq option[selected]").first(), let value = try? option.text(), !value.isEmpty { return "西工大研 \(value)" }
        if type == "wist", schoolName.contains("武汉船舶职业技术学院") {
            let names = ((try? document.select("td[data-role=item] .mtt_arrange_item .mtt_item_bjmc").array()) ?? []).compactMap { try? $0.text() }.filter { !$0.isEmpty }
            return "武船" + Set(names).sorted().joined(separator: ",") + "课表"
        }
        return nil
    }
}
