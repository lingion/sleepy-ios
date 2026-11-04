// 独立 macOS target 的平台边界；数据库/偏好/配色算法/胶水使用生产源码。
import Foundation
import SwiftUI
import AppKit
import GRDB

final class UIColor {
    private let value: NSColor
    init(_ color: Color) { value = NSColor(color).usingColorSpace(.sRGB)! }
    func getRed(_ r: inout CGFloat, green g: inout CGFloat, blue b: inout CGFloat, alpha a: inout CGFloat) {
        value.getRed(&r, green: &g, blue: &b, alpha: &a)
    }
}

struct TestScheme { var primary = Color(red: 103.0/255, green: 80.0/255, blue: 164.0/255) }
struct TestPreset { var light = TestScheme(); var dark = TestScheme() }
enum ThemePresets {
    static let KEY_DEFAULT = "default", KEY_SYSTEM = "system", CUSTOM_KEY_PREFIX = "custom:"
    static func byKey(_ key: String) -> TestPreset { TestPreset() }
}
struct CustomTheme {
    let id: String, name: String, primary: String, secondary: String, tertiary: String
    let surfaceHue: Double, surfaceChroma: Double
    let createdAt: Int64
}
enum CustomThemeStore { static func getById(_ id: String) -> CustomTheme? { nil } }
enum CustomSchemeDeriver {
    static func derive(theme: CustomTheme, isDark: Bool) -> TestScheme { TestScheme() }
}
struct CoursePalette { let primary: Int }
enum L10n { static func format(_ key: String, _ args: CVarArg...) -> String { key } }
enum TimeTableUtils {
    static func timeToNode(_ start: String, _ end: String, _ json: String) -> (Int, Int)? { nil }
}
struct HolidayRange {}
enum HolidayRangeOps {
    static func decodeOverrides(_ json: String) -> [HolidayRange] { [] }
    static func encodeOverrides(_ ranges: [HolidayRange]) -> String { "[]" }
}
struct HolidayTransferEntry { let sourceDate: Date, targetDate: Date; let segmentId: String }
enum HolidayTransferOps {
    static func decodeTransfers(_ json: String) -> [HolidayTransferEntry] { [] }
    static func encodeTransfers(_ entries: [HolidayTransferEntry]) -> String { "[]" }
    static func withTargetExclusivity(_ entries: [HolidayTransferEntry], _ entry: HolidayTransferEntry) -> [HolidayTransferEntry] { entries }
}

// 小型真 GRDB 库，只建本轮被测表；不是 AppDatabase 全量迁移验证。
final class AppDatabase {
    let dbQueue: DatabaseQueue
    var courseColorDao: CourseColorDao { CourseColorDao(db: dbQueue) }
    init() throws {
        dbQueue = try DatabaseQueue()
        try dbQueue.write {
            try $0.execute(sql: "CREATE TABLE course_colors (tableKey TEXT NOT NULL, groupId TEXT NOT NULL, hue REAL NOT NULL, PRIMARY KEY (tableKey, groupId))")
        }
    }
    static func inMemory() throws -> AppDatabase { try AppDatabase() }
}
