// JwImportDraft.swift — ← JwImportDraft.kt (GPL-3.0, 逐行翻译)
//
// 教务导入确认流程的可恢复部分 (resumable part)。
// 刻意独立于 Room/Compose/Android 生命周期, 供未来屏幕或持久化适配器消费。

import Foundation

/// 导入草稿快照: 教务解析后、应用到课表前暂存的全量数据。
struct JwImportDraftSnapshot: Equatable {
    var school: JwSchoolInfo
    var courses: [JwCourse]
    var periods: [JwImportDraftPeriod]
    var termStartDate: String = ""
    var tableName: String = ""
    /// 序列化 SmartPeriodConfig; 对 UI/实体类保持不透明, 避免契约耦合。
    var smartConfigJson: String = ""
    var phase: JwImportDraftPhase = .configureConfirm

    init(school: JwSchoolInfo,
         courses: [JwCourse],
         periods: [JwImportDraftPeriod],
         termStartDate: String = "",
         tableName: String = "",
         smartConfigJson: String = "",
         phase: JwImportDraftPhase = .configureConfirm) {
        self.school = school
        self.courses = courses
        self.periods = periods
        self.termStartDate = termStartDate
        self.tableName = tableName
        self.smartConfigJson = smartConfigJson
        self.phase = phase
    }
}

struct JwImportDraftPeriod: Equatable {
    var node: Int
    var start: String
    var end: String
}

enum JwImportDraftPhase: String {
    case webViewLogin = "WEBVIEW_LOGIN"
    case configureConfirm = "CONFIGURE_CONFIRM"
}

/// 对齐 Kotlin String.isBlank() = Character.isWhitespace (含 \n/\r/\f):
/// .whitespaces 只覆盖空格+tab, 换行-only 字符串会被误判为非空白。
private func jwIsBlank(_ s: String) -> Bool {
    s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}

/// [JwImportDraftSnapshot] 的带版本 JSON 边界。
enum JwImportDraftCodec {
    static let schemaVersion: Int = 1

    /// 不支持的 schema 或任何非法/不完整的外部 payload 返回 nil。
    static func fromJson(_ json: String) -> JwImportDraftSnapshot? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? parse(data)
    }

    static func toJson(_ snapshot: JwImportDraftSnapshot) -> String {
        var root: [String: Any] = [
            "schemaVersion": schemaVersion,
            "phase": snapshot.phase.rawValue,
            "school": schoolToJson(snapshot.school),
            "termStartDate": snapshot.termStartDate,
            "tableName": snapshot.tableName,
            "smartConfigJson": snapshot.smartConfigJson,
        ]
        root["courses"] = snapshot.courses.map(courseToJson)
        root["periods"] = snapshot.periods.map(periodToJson)
        guard let data = try? JSONSerialization.data(withJSONObject: root),
              let out = String(data: data, encoding: .utf8) else { return "{}" }
        return out
    }

    // MARK: - 解析 (失败即返回 nil, 语义对齐 Kotlin runCatching + getOrNull)

    private static func parse(_ data: Data) throws -> JwImportDraftSnapshot? {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        // schemaVersion 缺省 = -1 (Kotlin optInt default)
        guard (root["schemaVersion"] as? Int) ?? -1 == schemaVersion else { return nil }

        // Kotlin: optString("phase", 默认) 仅在 key 缺失时取默认; 非字符串/JSON null 会被
        // org.json 强制转成不匹配的名字 → 整包 null。Swift 若直接 ?? 默认值会误接受。
        var phaseName = JwImportDraftPhase.configureConfirm.rawValue
        if let raw = root["phase"] {
            guard let s = raw as? String else { return nil }
            phaseName = s
        }
        guard let phase = JwImportDraftPhase(rawValue: phaseName) else { return nil }

        guard let schoolJson = root["school"] as? [String: Any] else { return nil }
        guard let school = schoolFromJson(schoolJson) else { return nil }

        guard let coursesJson = root["courses"] as? [[String: Any]] else { return nil }
        guard let periodsJson = root["periods"] as? [[String: Any]] else { return nil }

        var courses: [JwCourse] = []
        for item in coursesJson {
            guard let c = courseFromJson(item) else { return nil }
            courses.append(c)
        }
        var periods: [JwImportDraftPeriod] = []
        for item in periodsJson {
            guard let p = periodFromJson(item) else { return nil }
            periods.append(p)
        }

        return JwImportDraftSnapshot(
            school: school,
            courses: courses,
            periods: periods,
            termStartDate: (root["termStartDate"] as? String) ?? "",
            tableName: (root["tableName"] as? String) ?? "",
            smartConfigJson: (root["smartConfigJson"] as? String) ?? "",
            phase: phase
        )
    }

    private static func schoolToJson(_ school: JwSchoolInfo) -> [String: Any] {
        // cities 属 v1.0.60 目录展示字段, 与 Kotlin codec 一致不进快照 (往返不保留)。
        var o: [String: Any] = [
            "sortKey": school.sortKey,
            "name": school.name,
            "url": school.url,
            "status": school.status,
            "aliases": school.aliases,
            "sortKeyFull": school.sortKeyFull,
            "enableFetch": school.enableFetch,
        ]
        if let type = school.type { o["type"] = type }
        return o
    }

    private static func schoolFromJson(_ json: [String: Any]) -> JwSchoolInfo? {
        let sortKey = (json["sortKey"] as? String) ?? ""
        let name = (json["name"] as? String) ?? ""
        if jwIsBlank(sortKey) || jwIsBlank(name) { return nil }

        let aliasesJson = json["aliases"] as? [Any]
        var aliases: [String] = []
        if let arr = aliasesJson {
            for item in arr {
                let alias = (item as? String) ?? ""
                if jwIsBlank(alias) { return nil }
                aliases.append(alias)
            }
        }

        // Kotlin: optString("type","").ifBlank { null }
        let typeRaw = (json["type"] as? String) ?? ""
        let type: String? = jwIsBlank(typeRaw) ? nil : typeRaw

        return JwSchoolInfo(
            sortKey: sortKey,
            name: name,
            url: (json["url"] as? String) ?? "",
            type: type,
            status: (json["status"] as? String) ?? JwSchoolInfo.STATUS_SUPPORTED,
            aliases: aliases,
            sortKeyFull: (json["sortKeyFull"] as? String) ?? "",
            enableFetch: (json["enableFetch"] as? Bool) ?? false
        )
    }

    private static func courseToJson(_ course: JwCourse) -> [String: Any] {
        [
            "name": course.name,
            "room": course.room,
            "teacher": course.teacher,
            "day": course.day,
            "startNode": course.startNode,
            "endNode": course.endNode,
            "startWeek": course.startWeek,
            "endWeek": course.endWeek,
            "type": course.type,
        ]
    }

    private static func courseFromJson(_ json: [String: Any]) -> JwCourse? {
        let course = JwCourse(
            name: (json["name"] as? String) ?? "",
            room: (json["room"] as? String) ?? "",
            teacher: (json["teacher"] as? String) ?? "",
            day: (json["day"] as? Int) ?? 0,
            startNode: (json["startNode"] as? Int) ?? 0,
            endNode: (json["endNode"] as? Int) ?? 0,
            startWeek: (json["startWeek"] as? Int) ?? 0,
            endWeek: (json["endWeek"] as? Int) ?? 0,
            type: (json["type"] as? Int) ?? 0
        )
        // Kotlin: JwCourse(...).takeIf { ... } — Swift 无内置 takeIf, 等价为 valid ? course : nil
        let validName = !jwIsBlank(course.name)
        let validDay = (1...7).contains(course.day)
        let validNode = course.startNode >= 1 && course.endNode >= course.startNode
        let validWeek = course.startWeek >= 1 && course.endWeek >= course.startWeek
        let valid = validName && validDay && validNode && validWeek && course.type >= 0
        return valid ? course : nil
    }

    private static func periodToJson(_ period: JwImportDraftPeriod) -> [String: Any] {
        ["node": period.node, "start": period.start, "end": period.end]
    }

    private static func periodFromJson(_ json: [String: Any]) -> JwImportDraftPeriod? {
        let period = JwImportDraftPeriod(
            node: (json["node"] as? Int) ?? 0,
            start: (json["start"] as? String) ?? "",
            end: (json["end"] as? String) ?? ""
        )
        let blankStart = jwIsBlank(period.start)
        let blankEnd = jwIsBlank(period.end)
        let hhmm = { (s: String) in s.range(of: #"^\d{2}:\d{2}$"#, options: .regularExpression) != nil }
        // Kotlin: period.takeIf { ... } — Swift 无内置 takeIf, 等价为 valid ? period : nil
        let bothBlank = blankStart && blankEnd
        let bothTime = hhmm(period.start) && hhmm(period.end) && period.start < period.end
        let valid = period.node >= 1 && (bothBlank || bothTime)
        return valid ? period : nil
    }
}
