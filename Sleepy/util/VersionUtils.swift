// VersionUtils.swift — ← VersionUtils.kt
// Semantic comparison for release names such as v1.2.3 and 1.2.3-debug.

import Foundation

enum VersionUtils {
    /// 当前 App 版本(= 原版本 BuildConfig.VERSION_NAME;iOS = CFBundleShortVersionString)
    /// 1.0.64 自 UpdateManager 迁居(更新检查下线, 版本号展示仍被关于页/导入报告消费)。
    static var currentVersionName: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0"
    }

    private static func parts(_ version: String) -> [Int] {
        // ← Regex("\\d+").findAll(version.removePrefix("v"))
        let digits = version.hasPrefix("v") ? String(version.dropFirst()) : version
        let regex = try! NSRegularExpression(pattern: #"\d+"#)
        let ns = digits as NSString
        let found = regex.matches(in: digits, range: NSRange(location: 0, length: ns.length))
            .compactMap { Range($0.range, in: digits) }
            .map { Int(digits[$0])! }
        return found.isEmpty ? [0] : found
    }

    static func compare(_ left: String, _ right: String) -> Int {
        let a = parts(left)
        let b = parts(right)
        for i in 0..<max(a.count, b.count) {
            let diff = (i < a.count ? a[i] : 0) - (i < b.count ? b[i] : 0)
            if diff != 0 { return diff < 0 ? -1 : 1 }
        }
        return 0
    }
}
