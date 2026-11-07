#if DEBUG && !WIDGET_EXT && !WATCH_APP
import Foundation
import UIKit

@MainActor
final class ConsoleDataHandlers {
    private let repo: ScheduleRepository
    private let prefs: AppPrefs
    private let prefsDomain: String

    init(repository: ScheduleRepository, prefs: AppPrefs = .shared,
         prefsDomain: String = Bundle.main.bundleIdentifier ?? "com.lingion.Sleepy") {
        repo = repository; self.prefs = prefs; self.prefsDomain = prefsDomain
    }

    func install(on router: ConsoleRouter, catalogConsumerWired: Bool = false) {
        router.register("GET", "/v1/data/tables") { [self] _ in try tables() }
        router.register("POST", "/v1/data/table") { [self] request in
            let result = try table(request.object()); ConsoleLogStore.shared.record(.dataChanged); return result
        }
        router.register("POST", "/v1/data/course") { [self] request in
            let result = try course(request.object()); ConsoleLogStore.shared.record(.dataChanged); return result
        }
        router.register("POST", "/v1/data/timesetting") { [self] request in
            let result = try period(request.object()); ConsoleLogStore.shared.record(.dataChanged); return result
        }
        router.register("GET", "/v1/data/prefs") { [self] _ in
            let stored = prefs.sharedBackedStore.persistentDomain(forName: prefsDomain) ?? [:]
            return ["values": stored.filter { !$0.key.hasPrefix("console_") }.mapValues { value -> Any in
                if value is String || value is NSNumber { return value }
                return String(describing: value)
            }]
        }
        router.register("POST", "/v1/data/prefs") { [self] request in
            let result = try putPrefs(request.object()); ConsoleLogStore.shared.record(.prefsChanged); return result
        }
        router.register("POST", "/v1/data/catalog") { request in
            let o = try request.object()
            let result = try ConsoleCatalogStore.shared.handle(o, consumerWired: catalogConsumerWired) {
                guard let url = Bundle.main.url(forResource: "schools", withExtension: "json"),
                      let text = try? String(contentsOf: url, encoding: .utf8) else {
                    throw ConsoleFailure(500, "schools resource unavailable")
                }
                return JwImportViewModel.parseSchoolsJson(text)
            }
            if o["op"] as? String == "set" { ConsoleLogStore.shared.record(.catalog) }
            return result
        }
    }

    func tables() throws -> [String: Any] {
        let rows: [[String: Any]] = try repo.getAllTables().map { table in
            var row = try ConsoleJSON.encoded(table) as! [String: Any]
            let courses = try repo.getCourses(table.id)
            row["courses"] = try courses.map { course -> [String: Any] in
                var result = try ConsoleJSON.encoded(course) as! [String: Any]
                result["fixedDate"] = course.fixedDate as Any? ?? NSNull()
                return result
            }
            row["courseCount"] = courses.count
            row["periodTableId"] = table.periodTableId as Any? ?? NSNull()
            row["periodTable"] = try repo.effectivePeriodTable(tableId: table.id).map { try ConsoleJSON.encoded($0) } ?? NSNull()
            return row
        }
        return ["tables": rows, "periodTables": try ConsoleJSON.encoded(repo.getAllPeriodTables()),
                "defaultTableId": try repo.getDefaultTable()?.id as Any? ?? NSNull()]
    }

    func table(_ o: [String: Any]) throws -> Any {
        let op = try ConsoleJSON.string(o, "op")
        if op == "create" {
            let value = try patchedTable(TimeTableEntity(name: "", startDate: ""), o)
            let id = try repo.insertTable(value)
            repo.onDataChangedHook?()
            return ["id": id]
        }
        let id = Int64(try ConsoleJSON.integer(o, "id"))
        guard let current = try repo.getTable(id) else { throw ConsoleFailure("no time table with id") }
        switch op {
        case "update":
            let next = try patchedTable(current, o)
            try repo.updateTable(next)
            return try ConsoleJSON.encoded(next)
        case "delete": try repo.deleteTable(id); return ["deleted": id]
        case "setDefault": try repo.setDefault(id); return ["defaultTableId": id]
        default: throw ConsoleFailure("op must be create|update|delete|setDefault")
        }
    }

    private func patchedTable(_ current: TimeTableEntity, _ o: [String: Any]) throws -> TimeTableEntity {
        var next = current
        next.name = try ConsoleJSON.string(o, "name", default: current.name)
        next.startDate = try ConsoleJSON.string(o, "startDate", default: current.startDate)
        next.maxWeek = try ConsoleJSON.integer(o, "maxWeek", default: current.maxWeek)
        next.nodesPerDay = try ConsoleJSON.integer(o, "nodesPerDay", default: current.nodesPerDay)
        next.timeJson = try ConsoleJSON.string(o, "timeJson", default: current.timeJson)
        next.color = try ConsoleJSON.string(o, "color", default: current.color)
        next.reminderEnabled = try ConsoleJSON.bool(o, "reminderEnabled", default: current.reminderEnabled)
        if current.id == 0 { next.isDefault = try ConsoleJSON.bool(o, "isDefault") }
        guard !next.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              Self.validDate(next.startDate), (1...1000).contains(next.maxWeek),
              (1...1000).contains(next.nodesPerDay) else { throw ConsoleFailure("invalid name/startDate/maxWeek/nodesPerDay") }
        return next
    }

    func period(_ o: [String: Any]) throws -> Any {
        let op = try ConsoleJSON.string(o, "op")
        var value: PeriodTableEntity
        if op == "create" { value = PeriodTableEntity(name: "") }
        else {
            let id = Int64(try ConsoleJSON.integer(o, "id"))
            guard let current = try repo.getPeriodTable(id) else { throw ConsoleFailure("no period table with id") }
            value = current
        }
        if op == "delete" {
            guard try repo.deletePeriodTable(value.id) else { throw ConsoleFailure("delete refused: still bound") }
            return ["deleted": value.id]
        }
        guard op == "create" || op == "update" else { throw ConsoleFailure("op must be create|update|delete") }
        value.name = try ConsoleJSON.string(o, "name", default: value.name)
        value.nodesPerDay = try ConsoleJSON.integer(o, "nodesPerDay", default: value.nodesPerDay)
        value.timeJson = try ConsoleJSON.string(o, "timeJson", default: value.timeJson)
        value.smartConfigJson = try ConsoleJSON.string(o, "smartConfigJson", default: value.smartConfigJson)
        guard !value.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              (1...1000).contains(value.nodesPerDay) else { throw ConsoleFailure("invalid name/nodesPerDay") }
        if op == "create" {
            let id = try repo.insertPeriodTable(value)
            repo.onDataChangedHook?()
            return ["id": id]
        }
        return ["id": value.id, "boundCount": try repo.savePeriodTable(value)]
    }

    func course(_ o: [String: Any], forceGroupRecognition: Bool = false) throws -> Any {
        if let raw = o["courses"] {
            let id = Int64(try ConsoleJSON.integer(o, "tableId"))
            guard try repo.getTable(id) != nil else { throw ConsoleFailure("no time table with tableId") }
            guard let array = raw as? [[String: Any]], !array.isEmpty else { throw ConsoleFailure("courses must be a non-empty object array") }
            // 整批 decode + validate 在第一次 repository 写入之前完成。
            let courses = try array.map { try Self.decodeCourse($0, tableId: id) }
            let ids = try insert(courses)
            return ["tableId": id, "inserted": ids.count, "courseIds": ids]
        }
        let text: String
        if o["text"] != nil { text = try ConsoleJSON.string(o, "text") }
        else if o["b64"] != nil {
            guard let bytes = Data(base64Encoded: try ConsoleJSON.string(o, "b64")),
                  let decoded = String(data: bytes, encoding: .utf8) else { throw ConsoleFailure("invalid UTF-8 base64") }
            text = decoded
        } else if o["path"] != nil {
            let path = try ConsoleJSON.string(o, "path")
            if path == "clipboard" {
                guard let value = UIPasteboard.general.string else { throw ConsoleFailure("clipboard unavailable") }
                text = value
            } else {
                let url = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
                let home = URL(fileURLWithPath: NSHomeDirectory()).resolvingSymlinksInPath().path + "/"
                guard url.path.hasPrefix(home),
                      let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                      size <= ConsoleHTTPParser.bodyLimit,
                      let value = try? String(contentsOf: url, encoding: .utf8) else {
                    throw ConsoleFailure("path must be a readable UTF-8 file inside app sandbox, at most 1 MiB")
                }
                text = value
            }
        } else { throw ConsoleFailure("body needs courses or text|b64|path") }
        guard text.utf8.count <= ConsoleHTTPParser.bodyLimit else { throw ConsoleFailure(413, "import too large") }
        let parsed: ScheduleParser.ParseResult
        do { parsed = try ScheduleParser.parse(text, defaultTableId: 0).get() }
        catch { throw ConsoleFailure("schedule parse failed") }
        guard !parsed.courses.isEmpty else { throw ConsoleFailure("parsed no courses") }
        for row in parsed.courses { try Self.validate(row) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let table = TimeTableEntity(name: parsed.tableName.isEmpty ? "导入的课表" : parsed.tableName,
                                    startDate: parsed.startDate.isEmpty ? formatter.string(from: AppClock.now) : parsed.startDate,
                                    maxWeek: 20, nodesPerDay: 13)
        guard Self.validDate(table.startDate) else { throw ConsoleFailure("invalid startDate") }
        // 与上游文本通路一致，不抢已有默认表；不使用会强制 setDefault 的 importNewTable。
        let id = try repo.insertTable(table)
        let rows = parsed.courses.map { row -> CourseEntity in var c = row; c.id = 0; c.tableId = id; return c }
        let ids: [Int64]
        if forceGroupRecognition { ids = try repo.insertCourses(rows) }
        else { ids = parsed.groupIdsAuthoritative ? try repo.insertCoursesKeepingGroups(rows) : try insert(rows) }
        return ["tableId": id, "inserted": ids.count, "droppedLines": parsed.droppedLines, "warnings": parsed.warnings]
    }

    private func insert(_ courses: [CourseEntity]) throws -> [Int64] {
        if courses.allSatisfy({ !$0.groupId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return try repo.insertCoursesKeepingGroups(courses)
        }
        return try repo.insertCourses(courses)
    }

    static func decodeCourse(_ o: [String: Any], tableId: Int64) throws -> CourseEntity {
        let base = CourseEntity(groupId: "", tableId: tableId, courseName: "", day: 0, startNode: 0,
                                step: 0, startWeek: 0, endWeek: 0, color: "#FF6750A4")
        var merged = try ConsoleJSON.encoded(base) as! [String: Any]
        for (key, value) in o where key != "id" && key != "tableId" { merged[key] = value }
        let course: CourseEntity
        do { course = try JSONDecoder().decode(CourseEntity.self, from: JSONSerialization.data(withJSONObject: merged)) }
        catch { throw ConsoleFailure("invalid course field type") }
        try validate(course)
        return course
    }

    static func validate(_ c: CourseEntity) throws {
        guard !c.courseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              (1...7).contains(c.day), (1...1000).contains(c.startNode), (1...1000).contains(c.step),
              (1...1000).contains(c.startWeek), (c.startWeek...1000).contains(c.endWeek),
              (0...3).contains(c.type), (0...2).contains(c.colorMode), c.credit.isFinite else {
            throw ConsoleFailure("invalid courseName/day/startNode/step/weeks/type/colorMode/credit")
        }
        if let date = c.fixedDate, !validDate(date) { throw ConsoleFailure("invalid fixedDate") }
    }

    static func validDate(_ string: String) -> Bool {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: string) else { return false }
        return formatter.string(from: date) == string
    }

    func putPrefs(_ o: [String: Any]) throws -> Any {
        guard !o.isEmpty, !o.keys.contains(where: { $0.hasPrefix("console_") }) else {
            throw ConsoleFailure("empty prefs or reserved console_ key")
        }
        // 类型/保留键全部检查后再写；禁止 PropertyList 不支持的 JSON null 嵌套值。
        for value in o.values {
            guard value is String || value is NSNumber || value is NSNull else {
                throw ConsoleFailure("prefs supports string/number/boolean/null only")
            }
        }
        let defaults = prefs.sharedBackedStore
        for (key, value) in o {
            if value is NSNull { defaults.removeObject(forKey: key) }
            else if key == AppPrefs.KEY_THEME, let value = value as? String { prefs.setThemeKey(value) }
            else { defaults.set(value, forKey: key) }
        }
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: defaults)
        return ["applied": o.count]
    }

    func resetSession() throws -> Any {
        let doomed = try repo.getAllTables().filter { $0.name.hasPrefix("console:") }.map(\.id)
        for id in doomed { try repo.deleteTable(id) }
        AppClock.reset()
        return ["deletedTableIds": doomed, "clockReset": true, "importDraftsCleared": false]
    }
}
#endif
