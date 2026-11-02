// JwImportReport.swift — ← data/jw/JwImportReport.kt
//
// 未验证学校导入成功后的可粘贴报告文本(离线回路, 2026-10-18)。
//
// 背景: 项目无云端、承诺不上传任何数据 — 导入失败用户会开 issue,
// 成功却是静默的, 维护者永远看不到。本对象把成功事实压成一段纯文本,
// 由 app 生成、用户复制到 QQ 群粘贴; 维护者据此把该条目在
// school_url_evidence 中翻为 verified, 下个版本该学校的确认/报告提示即消失。
//
// 隐私边界(结构性保证): 输入只有学校侧公开信息 + 计数 + 版本号 + 日期,
// 函数签名不接触账号、口令、session — 报告文本里不可能出现凭据。
// 纯本地化字段固定为 ASCII key 保证跨 locale 可 grep。

import Foundation

enum JwImportReport {

    /// QQ 群粘贴行的头部标记 — 维护者抓报告的第一道过滤。
    static let PASTE_MARKER = "[Sleepy导入成功]"

    /// type 缺失时的占位(不写 null, 避免被当成数据损坏)。
    static let UNKNOWN = "unknown"

    /// 生成报告文本。← JwImportReport.build
    ///
    /// - Parameters:
    ///   - school: 目录条目(公开信息)
    ///   - courseCount: 导入成功的课程数
    ///   - versionName: App 版本名(如 1.0.62)
    ///   - versionCode: App 构建号(如 62)
    ///   - date: 报告日期(yyyy-MM-dd)
    static func build(school: JwSchoolInfo,
                      courseCount: Int,
                      versionName: String,
                      versionCode: Int,
                      date: String) -> String {
        var lines: [String] = []
        lines.append(PASTE_MARKER)
        lines.append("app=\(versionName) (\(versionCode))")
        lines.append("date=\(date)")
        lines.append("school=\(school.name)")
        lines.append("catalogId=\(school.catalogId.isEmpty ? UNKNOWN : school.catalogId)")
        lines.append("status=\(school.status)")
        let protocolName = JwProtocol.displayName(school.type)
        let rawType = school.type ?? UNKNOWN
        lines.append("protocol=\(protocolName) (\(rawType))")
        lines.append("url=\(school.url.isEmpty ? UNKNOWN : school.url)")
        lines.append("courses=\(courseCount)")
        return lines.joined(separator: "\n")
    }

    /// 报告日期 —— 本地时区的 yyyy-MM-dd。
    static func todayStamp(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
