// macOS 独立 target 的外部边界；持久化类、迁移、撤销、时间计算全部编译生产原文件。
import Foundation
import GRDB

enum L10n {
    static func format(_ key: String, _ args: CVarArg...) -> String {
        fatalError("本切片不应调用 UI 本地化")
    }
}

extension String {
    var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

enum AppGroupResolver {
    static func sharedDirectory() -> URL {
        fatalError("测试必须显式创建独立数据库，不访问 App Group")
    }
}

final class NotificationScheduler {
    static let shared = NotificationScheduler()
    func cancelCourseAlarms(courseIds: [Int64]) {
        fatalError("移动测试不应进入系统通知取消路径")
    }
}

// Undo/redo 会读取冲突置顶偏好：独立测试固定无 UI 偏好，避免触碰用户 UserDefaults。
final class AppPrefs {
    static let shared = AppPrefs()
    func getConflictDefaultTop() -> [String: Int64] { [:] }
    func setConflictDefaultTop(_ value: [String: Int64]) {
        fatalError("空 UI 偏好不应触发写入")
    }
    func clearHolidayTransfers(_ tableId: Int64) {
        fatalError("本切片不删除课表")
    }
}

enum ConflictLayoutEngine {
    static func pruneConflictDefaultTop(_ prefs: [String: Int64], _ courses: [CourseEntity],
                                       timeJson: String?) -> [String: Int64] {
        fatalError("空 UI 偏好不应触发布局计算")
    }
}

// 移动保留既有 groupId，不走新增组配色；意外走到这里必须失败。
enum CourseColorWriteGlue {
    static func persistNewGroupHues(dao: CourseColorDao, entities: [CourseEntity]) -> [Int64] {
        fatalError("移动不应创建新的组色")
    }
    static func persistNewGroupHuesInDb(dbw: Database, dao: CourseColorDao,
                                      entities: [CourseEntity]) -> [Int64] {
        fatalError("移动不应进入导入组色路径")
    }
}
