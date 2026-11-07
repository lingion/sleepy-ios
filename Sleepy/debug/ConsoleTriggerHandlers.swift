#if DEBUG && !WIDGET_EXT && !WATCH_APP
import Foundation

@MainActor
final class ConsoleTriggerHandlers {
    static let supported = ["before_class_alarm", "notification", "schedule_before_class_now", "sync",
        "restore_and_cleanup", "delete_non_default_tables", "add_soonest_course", "import_helper"]
    static let unsupported = ["fluid_cloud", "test_before_class", "live_card", "clear_fluid_notification"]
    private let repo: ScheduleRepository
    private let data: ConsoleDataHandlers
    private let reschedule: () async -> Void

    init(repository: ScheduleRepository, data: ConsoleDataHandlers,
         reschedule: @escaping () async -> Void = { await NotificationScheduler.shared.scheduleTodayBeforeClassAlarms() }) {
        repo = repository; self.data = data; self.reschedule = reschedule
    }

    func handle(_ o: [String: Any]) async throws -> Any {
        try Task.checkCancellation()
        let type = try ConsoleJSON.string(o, "type")
        let summary: String
        switch type {
        case "before_class_alarm", "notification", "schedule_before_class_now":
            // 等待真实调度器返回。此函数不证明 OS 已展示通知，沿用提醒权限/偏好守卫。
            await reschedule()
            try Task.checkCancellation()
            summary = "scheduleTodayBeforeClassAlarms executed (iOS next-7-days resync; delivery not asserted)"
        case "sync", "restore_and_cleanup":
            let all = try repo.getAllTables()
            let keep = all.first { !$0.name.contains("测试") && !$0.name.contains("fluid") }
            if let keep { try repo.setDefault(keep.id) }
            // 刻意保留上游 keep 与 delete 的中英文判据差异，不偷偷缩成 console: 前缀。
            let deleted = all.filter { $0.name.contains("测试") || $0.name.contains("流体") }
            for table in deleted { try repo.deleteTable(table.id) }
            summary = "deleted=\(deleted.count) names=\(deleted.map(\.name)) default=\(keep?.name ?? "null")"
        case "delete_non_default_tables":
            let all = try repo.getAllTables()
            for table in all where !table.isDefault { try repo.deleteTable(table.id) }
            summary = "tables \(all.count) -> \(try repo.getAllTables().count)"
        case "add_soonest_course":
            let delay = try ConsoleJSON.integer(o, "delayMin", default: 5)
            guard (0...10080).contains(delay) else { throw ConsoleFailure("delayMin must be 0...10080") }
            let name = try ConsoleJSON.string(o, "courseName", default: "流体云测试课")
            let room = try ConsoleJSON.string(o, "room", default: "A101")
            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ConsoleFailure("courseName required") }
            let now = AppClock.now
            let start = now.addingTimeInterval(Double(delay) * 60)
            let end = start.addingTimeInterval(45 * 60)
            let date = DateFormatter()
            date.locale = Locale(identifier: "en_US_POSIX")
            date.timeZone = DateUtils.isoCalendar.timeZone
            date.dateFormat = "yyyy-MM-dd"
            let startDate = date.string(from: DateUtils.mondayOf(now))
            date.dateFormat = "HH:mm"
            let startTime = date.string(from: start), endTime = date.string(from: end)
            let id = try repo.insertTable(TimeTableEntity(name: "流体云触发测试", startDate: startDate, isDefault: true))
            try repo.setDefault(id)
            let course = CourseEntity(groupId: UUID().uuidString, tableId: id, courseName: name,
                teacher: "测试", room: room, day: DateUtils.todayDayOfWeek(today: now), startNode: 1, step: 1,
                startWeek: 1, endWeek: 20, type: 0, color: "#FF6750A4", ownTime: true,
                startTime: startTime, endTime: endTime)
            try repo.insertCourse(course)
            summary = "tableId=\(id) startTime=\(startTime) endTime=\(endTime) day=\(course.day)"
        case "import_helper":
            guard o["text"] != nil || o["b64"] != nil else { throw ConsoleFailure("import_helper requires text or b64") }
            var source: [String: Any] = [:]
            if let text = o["text"] { source["text"] = text } else { source["b64"] = o["b64"] }
            guard let result = try data.course(source, forceGroupRecognition: true) as? [String: Any],
                  let tableId = result["tableId"], let inserted = result["inserted"] else {
                throw ConsoleFailure(500, "import result unavailable")
            }
            summary = "tableId=\(tableId) inserted=\(inserted)"
        case "fluid_cloud", "test_before_class", "live_card", "clear_fluid_notification":
            throw ConsoleFailure(501, "Android FluidCloudService has no implemented iOS equivalent")
        default: throw ConsoleFailure("unknown trigger type")
        }
        ConsoleLogStore.shared.record(.trigger)
        return ["type": type, "result": summary]
    }
}
#endif
